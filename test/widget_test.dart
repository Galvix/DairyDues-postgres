// Unit tests for the pure, offline billing/paneer logic. (The data layer is now
// the remote ApiService, so widget smoke tests would need a live backend; these
// cover the math that stayed client-side.)

import 'package:flutter_test/flutter_test.dart';
import 'package:dairy_app/utils/payment_calculator.dart';

void main() {
  group('PaneerValidation', () {
    test('reduces milk when sample yield is below standard', () {
      final v = PaneerValidation.validate(
        netMilkTotal: 100,
        samplePaneerKg: 6.0,
        standardPaneerKg: 6.5,
      );
      expect(v.adjustmentNeeded, isTrue);
      expect(v.effectiveRatio, closeTo(6.0 / 6.5, 1e-9));
      expect(v.adjustedMilkTotal, closeTo(100 * 6.0 / 6.5, 1e-6));
    });

    test('leaves milk unchanged when sample meets standard', () {
      final v = PaneerValidation.validate(
        netMilkTotal: 100,
        samplePaneerKg: 6.5,
        standardPaneerKg: 6.5,
      );
      expect(v.adjustmentNeeded, isFalse);
      expect(v.adjustedMilkTotal, 100);
    });
  });

  group('WeeklyPaymentSummary', () {
    test('nets earnings against this-week and carried-over loans', () {
      final s = WeeklyPaymentSummary.calculate(
        milkmanId: 'm1',
        milkmanName: 'A',
        milkRate: 50,
        khoyaRate: 0,
        totalMilkKg: 10,
        totalKhoyaKg: 0,
        thisWeekLoans: 100,
        carriedOverLoan: 50,
      );
      expect(s.totalEarnings, 500);
      expect(s.totalLoanDeducted, 150);
      expect(s.netPayable, 350);
      expect(s.loanCarryForward, 0);
    });

    test('carries the shortfall forward when loans exceed earnings', () {
      final s = WeeklyPaymentSummary.calculate(
        milkmanId: 'm1',
        milkmanName: 'A',
        milkRate: 10,
        khoyaRate: 0,
        totalMilkKg: 10,
        totalKhoyaKg: 0,
        thisWeekLoans: 300,
        carriedOverLoan: 0,
      );
      expect(s.totalEarnings, 100);
      expect(s.netPayable, 0);
      expect(s.loanCarryForward, 200);
    });
  });

  group('DateHelpers', () {
    test('week starts on Monday', () {
      // 2026-06-18 is a Thursday -> week start is Monday 2026-06-15.
      final ws = DateHelpers.getWeekStart(DateTime(2026, 6, 18));
      expect(ws, DateTime(2026, 6, 15));
      expect(DateHelpers.getWeekEnd(ws), DateTime(2026, 6, 21));
    });
  });
}
