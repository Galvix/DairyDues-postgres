// lib/utils/payment_calculator.dart
import 'package:intl/intl.dart';

class WeeklyPaymentSummary {
  final String milkmanId;
  final String milkmanName;
  final double milkRate;
  final double khoyaRate;
  final double totalMilkKg;
  final double milkEarnings;
  final double totalKhoyaKg;
  final double khoyaEarnings;
  final double totalEarnings;
  final double thisWeekLoans;
  final double carriedOverLoan;
  final double totalLoanDeducted;
  final double netPayable;
  final double loanCarryForward;

  const WeeklyPaymentSummary({
    required this.milkmanId,
    required this.milkmanName,
    required this.milkRate,
    required this.khoyaRate,
    required this.totalMilkKg,
    required this.milkEarnings,
    required this.totalKhoyaKg,
    required this.khoyaEarnings,
    required this.totalEarnings,
    required this.thisWeekLoans,
    required this.carriedOverLoan,
    required this.totalLoanDeducted,
    required this.netPayable,
    required this.loanCarryForward,
  });

  factory WeeklyPaymentSummary.calculate({
    required String milkmanId,
    required String milkmanName,
    required double milkRate,
    required double khoyaRate,
    required double totalMilkKg,
    required double totalKhoyaKg,
    required double thisWeekLoans,
    required double carriedOverLoan,
  }) {
    final milkEarnings = totalMilkKg * milkRate;
    final khoyaEarnings = totalKhoyaKg * khoyaRate;
    final totalEarnings = milkEarnings + khoyaEarnings;
    final totalLoans = thisWeekLoans + carriedOverLoan;
    final net = totalEarnings - totalLoans;

    return WeeklyPaymentSummary(
      milkmanId: milkmanId,
      milkmanName: milkmanName,
      milkRate: milkRate,
      khoyaRate: khoyaRate,
      totalMilkKg: totalMilkKg,
      milkEarnings: milkEarnings,
      totalKhoyaKg: totalKhoyaKg,
      khoyaEarnings: khoyaEarnings,
      totalEarnings: totalEarnings,
      thisWeekLoans: thisWeekLoans,
      carriedOverLoan: carriedOverLoan,
      totalLoanDeducted: totalLoans,
      netPayable: net > 0 ? net : 0.0,
      loanCarryForward: net < 0 ? net.abs() : 0.0,
    );
  }
}

class PaneerValidation {
  final double netMilkTotal;
  // samplePaneerKg: actual paneer weighed from the 24kg sample
  // standardPaneerKg: expected paneer from that same sample (e.g. 6.5 kg)
  final double samplePaneerKg;
  final double standardPaneerKg;
  final double effectiveRatio;   // samplePaneerKg / standardPaneerKg
  final double toleranceKg;
  final bool adjustmentNeeded;
  final double adjustedMilkTotal;

  const PaneerValidation({
    required this.netMilkTotal,
    required this.samplePaneerKg,
    required this.standardPaneerKg,
    required this.effectiveRatio,
    required this.toleranceKg,
    required this.adjustmentNeeded,
    required this.adjustedMilkTotal,
  });

  factory PaneerValidation.validate({
    required double netMilkTotal,
    required double samplePaneerKg,
    required double standardPaneerKg,
  }) {
    final effectiveRatio = samplePaneerKg / standardPaneerKg;
    final adjustmentNeeded = samplePaneerKg < standardPaneerKg;
    final adjustedMilkTotal =
        adjustmentNeeded ? netMilkTotal * effectiveRatio : netMilkTotal;

    return PaneerValidation(
      netMilkTotal: netMilkTotal,
      samplePaneerKg: samplePaneerKg,
      standardPaneerKg: standardPaneerKg,
      effectiveRatio: effectiveRatio,
      toleranceKg: 0,
      adjustmentNeeded: adjustmentNeeded,
      adjustedMilkTotal: adjustedMilkTotal,
    );
  }

  double get gap => standardPaneerKg - samplePaneerKg;
  double get milkReduction => netMilkTotal - adjustedMilkTotal;
}

class DateHelpers {
  static DateTime getWeekStart(DateTime date) {
    final daysFromMonday = date.weekday - 1;
    return DateTime(date.year, date.month, date.day - daysFromMonday);
  }

  static DateTime getWeekEnd(DateTime weekStart) =>
      weekStart.add(const Duration(days: 6));

  static String formatDate(DateTime date) =>
      DateFormat('dd MMM yyyy').format(date);

  static String formatWeekRange(DateTime weekStart) {
    final end = getWeekEnd(weekStart);
    return '${DateFormat('dd MMM').format(weekStart)} – ${DateFormat('dd MMM yyyy').format(end)}';
  }

  static String formatWeight(double kg) => '${kg.toStringAsFixed(2)} kg';

  static String formatCurrency(double amount) =>
      NumberFormat('#,##,##0.00').format(amount);
}
