// lib/providers/app_provider.dart
import 'package:flutter/foundation.dart';
import '../database/repository.dart';
import '../database/models.dart';
import '../utils/payment_calculator.dart';

class AppProvider extends ChangeNotifier {
  final Repository db;

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
  //
  // The billable_milk adjustment now lives SERVER-SIDE: POSTing a paneer entry
  // makes the backend compute yield_ratio = actual/expected and write
  // billable_milk = net_milk * yield_ratio onto that delivery (see api/app/
  // routers/deliveries.py:create_paneer_entry). The backend ties each test to
  // ONE delivery, so to reproduce the old "adjust the whole day for this milkman"
  // behaviour we post one test per delivery the milkman made that day.
  //
  // The returned PaneerValidation is computed client-side purely for the result
  // dialog / live preview (display logic, unchanged).
  Future<PaneerValidation> validateAndSavePaneerForMilkman({
    required DateTime date,
    required String milkmanId,
    required double samplePaneerKg,
  }) async {
    final deliveries = await db.getDeliveriesForDate(date);
    final myDeliveries =
        deliveries.where((d) => d.milkmanId == milkmanId).toList();
    final milkmanMilk =
        myDeliveries.fold<double>(0.0, (s, d) => s + d.netMilk);

    final validation = PaneerValidation.validate(
      netMilkTotal: milkmanMilk,
      samplePaneerKg: samplePaneerKg,
      standardPaneerKg: _standardPaneerKg,
    );

    for (final d in myDeliveries) {
      await db.createPaneerEntry(
        milkmanId: milkmanId,
        deliveryId: d.id,
        entryDate: date,
        totalMilkUsed: milkmanMilk,
        expectedPaneer: _standardPaneerKg,
        actualPaneer: samplePaneerKg,
        toleranceKg: 0,
      );
    }

    return validation;
  }

  // ─── WEEKLY PAYMENT ───────────────────────────────────────────────────────
  //
  // Weekly aggregation stays client-side (WeeklyPaymentSummary.calculate). The
  // backend's GET /milkmen/{id}/hisab is intentionally NOT used because it lacks
  // the carry-forward / week-windowed-loan logic this UI depends on — see the
  // BACKEND GAPS note in MIGRATION_REPORT.md. It reads billable_milk, which the
  // server already adjusts for paneer tests.
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
          // Snapshot the rates used for this settlement.
          milkRateApplied: m.milkRate,
          khoyaRateApplied: m.khoyaRate,
        ));
      }
    }

    return summaries;
  }
}
