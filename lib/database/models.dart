// lib/database/models.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Safe DateTime extraction — handles both Timestamp and DateTime
DateTime _toDateTime(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return DateTime.now();
}

class Milkman {
  final String id;
  final String name;
  final double milkRate;
  final double khoyaRate;
  final bool suppliesKhoya;
  final bool isActive;

  Milkman({
    required this.id,
    required this.name,
    required this.milkRate,
    this.khoyaRate = 0.0,
    this.suppliesKhoya = false,
    this.isActive = true,
  });

  factory Milkman.fromFirestore(String id, Map<String, dynamic> d) => Milkman(
        id: id,
        name: d['name'] ?? '',
        milkRate: (d['milkRate'] ?? 0).toDouble(),
        khoyaRate: (d['khoyaRate'] ?? 0).toDouble(),
        suppliesKhoya: d['suppliesKhoya'] ?? false,
        isActive: d['isActive'] ?? true,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'milkRate': milkRate,
        'khoyaRate': khoyaRate,
        'suppliesKhoya': suppliesKhoya,
        'isActive': isActive,
      };

  Milkman copyWith({
    String? name,
    double? milkRate,
    double? khoyaRate,
    bool? suppliesKhoya,
    bool? isActive,
  }) =>
      Milkman(
        id: id,
        name: name ?? this.name,
        milkRate: milkRate ?? this.milkRate,
        khoyaRate: khoyaRate ?? this.khoyaRate,
        suppliesKhoya: suppliesKhoya ?? this.suppliesKhoya,
        isActive: isActive ?? this.isActive,
      );
}

class MilkDelivery {
  final String id;
  final String milkmanId;
  final DateTime deliveryDate;
  final double grossWeight;
  final double canWeight;
  final double netMilk;
  double billableMilk;
  bool paneerAdjusted;
  final String notes;

  MilkDelivery({
    required this.id,
    required this.milkmanId,
    required this.deliveryDate,
    required this.grossWeight,
    required this.canWeight,
    required this.netMilk,
    required this.billableMilk,
    this.paneerAdjusted = false,
    this.notes = '',
  });

  factory MilkDelivery.fromFirestore(String id, Map<String, dynamic> d) =>
      MilkDelivery(
        id: id,
        milkmanId: d['milkmanId'] ?? '',
        deliveryDate: _toDateTime(d['deliveryDate']),
        grossWeight: (d['grossWeight'] ?? 0).toDouble(),
        canWeight: (d['canWeight'] ?? 0).toDouble(),
        netMilk: (d['netMilk'] ?? 0).toDouble(),
        billableMilk: (d['billableMilk'] ?? 0).toDouble(),
        paneerAdjusted: d['paneerAdjusted'] ?? false,
        notes: d['notes'] ?? '',
      );

  Map<String, dynamic> toMap() => {
        'milkmanId': milkmanId,
        'deliveryDate': Timestamp.fromDate(deliveryDate),
        'grossWeight': grossWeight,
        'canWeight': canWeight,
        'netMilk': netMilk,
        'billableMilk': billableMilk,
        'paneerAdjusted': paneerAdjusted,
        'notes': notes,
      };
}

class KhoyaDelivery {
  final String id;
  final String milkmanId;
  final DateTime deliveryDate;
  final double weight;
  final String notes;

  KhoyaDelivery({
    required this.id,
    required this.milkmanId,
    required this.deliveryDate,
    required this.weight,
    this.notes = '',
  });

  factory KhoyaDelivery.fromFirestore(String id, Map<String, dynamic> d) =>
      KhoyaDelivery(
        id: id,
        milkmanId: d['milkmanId'] ?? '',
        deliveryDate: _toDateTime(d['deliveryDate']),
        weight: (d['weight'] ?? 0).toDouble(),
        notes: d['notes'] ?? '',
      );

  Map<String, dynamic> toMap() => {
        'milkmanId': milkmanId,
        'deliveryDate': Timestamp.fromDate(deliveryDate),
        'weight': weight,
        'notes': notes,
      };
}

class PaneerEntry {
  final String id;
  final String? milkmanId;  // null for old daily-level entries
  final DateTime entryDate;
  final double totalMilkUsed;
  final double expectedPaneer;
  final double actualPaneer;
  final double yieldRatio;
  final double toleranceKg;
  final bool adjustmentApplied;
  final double? adjustedMilkTotal;

  PaneerEntry({
    required this.id,
    this.milkmanId,
    required this.entryDate,
    required this.totalMilkUsed,
    required this.expectedPaneer,
    required this.actualPaneer,
    required this.yieldRatio,
    required this.toleranceKg,
    required this.adjustmentApplied,
    this.adjustedMilkTotal,
  });

  factory PaneerEntry.fromFirestore(String id, Map<String, dynamic> d) =>
      PaneerEntry(
        id: id,
        milkmanId: d['milkmanId'] as String?,
        entryDate: _toDateTime(d['entryDate']),
        totalMilkUsed: (d['totalMilkUsed'] ?? 0).toDouble(),
        expectedPaneer: (d['expectedPaneer'] ?? 0).toDouble(),
        actualPaneer: (d['actualPaneer'] ?? 0).toDouble(),
        yieldRatio: (d['yieldRatio'] ?? 1.0).toDouble(),
        toleranceKg: (d['toleranceKg'] ?? 0).toDouble(),
        adjustmentApplied: d['adjustmentApplied'] ?? false,
        adjustedMilkTotal: d['adjustedMilkTotal']?.toDouble(),
      );

  Map<String, dynamic> toMap() => {
        if (milkmanId != null) 'milkmanId': milkmanId,
        'entryDate': Timestamp.fromDate(entryDate),
        'totalMilkUsed': totalMilkUsed,
        'expectedPaneer': expectedPaneer,
        'actualPaneer': actualPaneer,
        'yieldRatio': yieldRatio,
        'toleranceKg': toleranceKg,
        'adjustmentApplied': adjustmentApplied,
        'adjustedMilkTotal': adjustedMilkTotal,
      };
}

class Loan {
  final String id;
  final String milkmanId;
  final DateTime loanDate;
  final double amount;
  final String notes;

  Loan({
    required this.id,
    required this.milkmanId,
    required this.loanDate,
    required this.amount,
    this.notes = '',
  });

  factory Loan.fromFirestore(String id, Map<String, dynamic> d) => Loan(
        id: id,
        milkmanId: d['milkmanId'] ?? '',
        loanDate: _toDateTime(d['loanDate']),
        amount: (d['amount'] ?? 0).toDouble(),
        notes: d['notes'] ?? '',
      );

  Map<String, dynamic> toMap() => {
        'milkmanId': milkmanId,
        'loanDate': Timestamp.fromDate(loanDate),
        'amount': amount,
        'notes': notes,
      };
}

class WeeklyPayment {
  final String id;
  final String milkmanId;
  final DateTime weekStartDate;
  final DateTime weekEndDate;
  final double totalMilkKg;
  final double milkEarnings;
  final double totalKhoyaKg;
  final double khoyaEarnings;
  final double totalEarnings;
  final double loanDeducted;
  final double carriedOverLoan;
  final double netPayable;
  final double loanCarryForward;
  final bool isPaid;
  final DateTime? paidAt;

  WeeklyPayment({
    required this.id,
    required this.milkmanId,
    required this.weekStartDate,
    required this.weekEndDate,
    required this.totalMilkKg,
    required this.milkEarnings,
    required this.totalKhoyaKg,
    required this.khoyaEarnings,
    required this.totalEarnings,
    required this.loanDeducted,
    required this.carriedOverLoan,
    required this.netPayable,
    required this.loanCarryForward,
    this.isPaid = false,
    this.paidAt,
  });

  factory WeeklyPayment.fromFirestore(String id, Map<String, dynamic> d) =>
      WeeklyPayment(
        id: id,
        milkmanId: d['milkmanId'] ?? '',
        weekStartDate: _toDateTime(d['weekStartDate']),
        weekEndDate: _toDateTime(d['weekEndDate']),
        totalMilkKg: (d['totalMilkKg'] ?? 0).toDouble(),
        milkEarnings: (d['milkEarnings'] ?? 0).toDouble(),
        totalKhoyaKg: (d['totalKhoyaKg'] ?? 0).toDouble(),
        khoyaEarnings: (d['khoyaEarnings'] ?? 0).toDouble(),
        totalEarnings: (d['totalEarnings'] ?? 0).toDouble(),
        loanDeducted: (d['loanDeducted'] ?? 0).toDouble(),
        carriedOverLoan: (d['carriedOverLoan'] ?? 0).toDouble(),
        netPayable: (d['netPayable'] ?? 0).toDouble(),
        loanCarryForward: (d['loanCarryForward'] ?? 0).toDouble(),
        isPaid: d['isPaid'] ?? false,
        paidAt: d['paidAt'] != null ? _toDateTime(d['paidAt']) : null,
      );

  Map<String, dynamic> toMap() => {
        'milkmanId': milkmanId,
        'weekStartDate': Timestamp.fromDate(weekStartDate),
        'weekEndDate': Timestamp.fromDate(weekEndDate),
        'totalMilkKg': totalMilkKg,
        'milkEarnings': milkEarnings,
        'totalKhoyaKg': totalKhoyaKg,
        'khoyaEarnings': khoyaEarnings,
        'totalEarnings': totalEarnings,
        'loanDeducted': loanDeducted,
        'carriedOverLoan': carriedOverLoan,
        'netPayable': netPayable,
        'loanCarryForward': loanCarryForward,
        'isPaid': isPaid,
        'paidAt': paidAt != null ? Timestamp.fromDate(paidAt!) : null,
      };
}
