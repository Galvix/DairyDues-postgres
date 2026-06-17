// lib/providers/app_provider.dart
import 'package:flutter/foundation.dart';
import '../database/firestore_service.dart';
import '../database/models.dart';
import '../utils/payment_calculator.dart';

class AppProvider extends ChangeNotifier {
  final FirestoreService db;

  AppProvider(this.db);

  DateTime _selectedDate = DateTime.now();
  DateTime get selectedDate => _selectedDate;

  double _standardPaneerKg = 6.5;  // expected paneer from a 24kg sample
  double _sampleMilkKg = 24.0;     // the fixed sample size

  double get standardPaneerKg => _standardPaneerKg;
  double get sampleMilkKg => _sampleMilkKg;

  void setSelectedDate(DateTime date) {
    _selectedDate = date;
    notifyListeners();
  }

  DateTime get currentWeekStart => DateHelpers.getWeekStart(DateTime.now());

  Future<void> loadSettings() async {
    _standardPaneerKg = await db.getStandardPaneerKg();
    _sampleMilkKg = await db.getSampleMilkKg();
    notifyListeners();
  }

  Future<void> updateStandardPaneerKg(double value) async {
    await db.setSetting('standard_paneer_kg', value);
    _standardPaneerKg = value;
    notifyListeners();
  }

  Future<void> updateSampleMilkKg(double value) async {
    await db.setSetting('sample_milk_kg', value);
    _sampleMilkKg = value;
    notifyListeners();
  }

  // ─── MILK ENTRY ───────────────────────────────────────────────────────────

  Future<void> addMilkDelivery({
    required String milkmanId,
    required DateTime deliveryDate,
    required double grossWeight,
    required double canWeight,
    String notes = '',
  }) async {
    final netMilk = grossWeight - canWeight;
    await db.addMilkDelivery(MilkDelivery(
      id: '',
      milkmanId: milkmanId,
      deliveryDate: deliveryDate,
      grossWeight: grossWeight,
      canWeight: canWeight,
      netMilk: netMilk,
      billableMilk: netMilk,
      notes: notes,
    ));
  }

  // ─── PANEER VALIDATION ────────────────────────────────────────────────────

  Future<PaneerValidation> validateAndSavePaneerForMilkman({
    required DateTime date,
    required String milkmanId,
    required double samplePaneerKg,
  }) async {
    final deliveries = await db.getAllDeliveriesForDate(date);
    final milkmanMilk = deliveries
        .where((d) => d.milkmanId == milkmanId)
        .fold<double>(0.0, (s, d) => s + d.netMilk);

    final validation = PaneerValidation.validate(
      netMilkTotal: milkmanMilk,
      samplePaneerKg: samplePaneerKg,
      standardPaneerKg: _standardPaneerKg,
    );

    await db.addPaneerEntry(PaneerEntry(
      id: '',
      milkmanId: milkmanId,
      entryDate: date,
      totalMilkUsed: milkmanMilk,
      expectedPaneer: _standardPaneerKg,
      actualPaneer: samplePaneerKg,
      yieldRatio: validation.effectiveRatio,
      toleranceKg: 0,
      adjustmentApplied: validation.adjustmentNeeded,
      adjustedMilkTotal:
          validation.adjustmentNeeded ? validation.adjustedMilkTotal : null,
    ));

    if (validation.adjustmentNeeded) {
      await db.applyPaneerAdjustmentForMilkman(
          date, milkmanId, validation.effectiveRatio);
    }

    return validation;
  }

  // ─── WEEKLY PAYMENT ───────────────────────────────────────────────────────

  Future<List<WeeklyPaymentSummary>> calculateWeeklyPayments(
      DateTime weekStart) async {
    final milkmen = await db.getActiveMilkmen();
    final summaries = <WeeklyPaymentSummary>[];

    for (final m in milkmen) {
      final deliveries = await db.getDeliveriesForWeek(m.id, weekStart);
      final totalMilk =
          deliveries.fold<double>(0.0, (s, d) => s + d.billableMilk);
      final totalKhoya = await db.getTotalKhoyaForWeek(m.id, weekStart);
      final thisWeekLoans = await db.getTotalLoansForWeek(m.id, weekStart);
      final carriedOver = await db.getCarriedOverLoan(m.id, weekStart);

      final summary = WeeklyPaymentSummary.calculate(
        milkmanId: m.id,
        milkmanName: m.name,
        milkRate: m.milkRate,
        khoyaRate: m.khoyaRate,
        totalMilkKg: totalMilk,
        totalKhoyaKg: totalKhoya,
        thisWeekLoans: thisWeekLoans,
        carriedOverLoan: carriedOver,
      );

      summaries.add(summary);

      final existing = await db.getPaymentForWeek(m.id, weekStart);
      if (existing == null || !existing.isPaid) {
        await db.upsertWeeklyPayment(WeeklyPayment(
          id: '',
          milkmanId: m.id,
          weekStartDate: weekStart,
          weekEndDate: DateHelpers.getWeekEnd(weekStart),
          totalMilkKg: totalMilk,
          milkEarnings: summary.milkEarnings,
          totalKhoyaKg: totalKhoya,
          khoyaEarnings: summary.khoyaEarnings,
          totalEarnings: summary.totalEarnings,
          loanDeducted: summary.totalLoanDeducted,
          carriedOverLoan: carriedOver,
          netPayable: summary.netPayable,
          loanCarryForward: summary.loanCarryForward,
        ));
      }
    }

    return summaries;
  }
}
