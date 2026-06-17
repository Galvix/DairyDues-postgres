// lib/database/models.dart
//
// Plain JSON (de)serialization for the FastAPI + PostgreSQL backend, and for the
// local offline-first cache.
// - Postgres PKs are uuid -> represented as Dart String (model `id` stays String).
//   For offline-first, ids are generated client-side (uuid v4) and the backend
//   upserts by them, so create bodies include `id`.
// - timestamptz / date fields are ISO-8601 strings, parsed to local DateTime.
// - JSON keys are snake_case to match the backend Pydantic models.
// - toCacheJson() produces the full server-shaped record persisted locally; it
//   round-trips back through fromJson().

/// Parse an ISO-8601 timestamptz/date string into a local DateTime.
DateTime _parseDate(dynamic value) {
  if (value == null) return DateTime.now();
  if (value is DateTime) return value;
  return DateTime.parse(value as String).toLocal();
}

double _toDouble(dynamic value) =>
    value == null ? 0.0 : (value as num).toDouble();

/// timestamptz payload: send UTC with offset so Postgres stores an unambiguous
/// instant. Round-trips back to the same local wall-clock via _parseDate().
String _isoTimestamp(DateTime d) => d.toUtc().toIso8601String();

/// `date` payload (calendar date, no time/zone): "YYYY-MM-DD" in local terms.
String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

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

  factory Milkman.fromJson(Map<String, dynamic> d) => Milkman(
        id: d['id'] as String,
        name: d['name'] ?? '',
        milkRate: _toDouble(d['milk_rate']),
        khoyaRate: _toDouble(d['khoya_rate']),
        suppliesKhoya: d['supplies_khoya'] ?? false,
        isActive: d['is_active'] ?? true,
      );

  /// Body for POST /milkmen/ and PATCH /milkmen/{id}. Includes `id` so the POST
  /// upserts by the client-generated id (ignored by the PATCH update model).
  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'name': name,
        'milk_rate': milkRate,
        'khoya_rate': khoyaRate,
        'supplies_khoya': suppliesKhoya,
        'is_active': isActive,
      };

  /// Full server-shaped record for the local cache.
  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'name': name,
        'milk_rate': milkRate,
        'khoya_rate': khoyaRate,
        'supplies_khoya': suppliesKhoya,
        'is_active': isActive,
      };

  Milkman copyWith({
    String? id,
    String? name,
    double? milkRate,
    double? khoyaRate,
    bool? suppliesKhoya,
    bool? isActive,
  }) =>
      Milkman(
        id: id ?? this.id,
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

  factory MilkDelivery.fromJson(Map<String, dynamic> d) => MilkDelivery(
        id: d['id'] as String,
        milkmanId: d['milkman_id'] ?? '',
        deliveryDate: _parseDate(d['delivery_date']),
        grossWeight: _toDouble(d['gross_weight']),
        canWeight: _toDouble(d['can_weight']),
        netMilk: _toDouble(d['net_milk']),
        billableMilk: _toDouble(d['billable_milk']),
        paneerAdjusted: d['paneer_adjusted'] ?? false,
        notes: d['notes'] ?? '',
      );

  /// Body for POST /milkmen/{milkman_id}/deliveries (milkman_id is a path param).
  Map<String, dynamic> toCreateJson() => {
        if (id.isNotEmpty) 'id': id,
        'delivery_date': _isoTimestamp(deliveryDate),
        'gross_weight': grossWeight,
        'can_weight': canWeight,
        'net_milk': netMilk,
        'notes': notes,
      };

  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'milkman_id': milkmanId,
        'delivery_date': _isoTimestamp(deliveryDate),
        'gross_weight': grossWeight,
        'can_weight': canWeight,
        'net_milk': netMilk,
        'billable_milk': billableMilk,
        'paneer_adjusted': paneerAdjusted,
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

  factory KhoyaDelivery.fromJson(Map<String, dynamic> d) => KhoyaDelivery(
        id: d['id'] as String,
        milkmanId: d['milkman_id'] ?? '',
        deliveryDate: _parseDate(d['delivery_date']),
        weight: _toDouble(d['weight']),
        notes: d['notes'] ?? '',
      );

  /// Body for POST /milkmen/{milkman_id}/khoya (milkman_id is a path param).
  Map<String, dynamic> toCreateJson() => {
        if (id.isNotEmpty) 'id': id,
        'delivery_date': _isoTimestamp(deliveryDate),
        'weight': weight,
        'notes': notes,
      };

  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'milkman_id': milkmanId,
        'delivery_date': _isoTimestamp(deliveryDate),
        'weight': weight,
        'notes': notes,
      };
}

class PaneerEntry {
  final String id;
  final String? milkmanId;
  final String? deliveryId; // the specific milk_deliveries row tested
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
    this.deliveryId,
    required this.entryDate,
    required this.totalMilkUsed,
    required this.expectedPaneer,
    required this.actualPaneer,
    required this.yieldRatio,
    required this.toleranceKg,
    required this.adjustmentApplied,
    this.adjustedMilkTotal,
  });

  factory PaneerEntry.fromJson(Map<String, dynamic> d) => PaneerEntry(
        id: d['id'] as String,
        milkmanId: d['milkman_id'] as String?,
        deliveryId: d['delivery_id'] as String?,
        entryDate: _parseDate(d['entry_date']),
        totalMilkUsed: _toDouble(d['total_milk_used']),
        expectedPaneer: _toDouble(d['expected_paneer']),
        actualPaneer: _toDouble(d['actual_paneer']),
        yieldRatio: d['yield_ratio'] == null ? 1.0 : _toDouble(d['yield_ratio']),
        toleranceKg: _toDouble(d['tolerance_kg']),
        adjustmentApplied: d['adjustment_applied'] ?? false,
        adjustedMilkTotal: d['adjusted_milk_total'] == null
            ? null
            : _toDouble(d['adjusted_milk_total']),
      );

  /// Body for POST /milkmen/{milkman_id}/paneer. The backend computes
  /// yield_ratio / adjusted_milk_total / adjustment_applied itself.
  Map<String, dynamic> toCreateJson() => {
        if (id.isNotEmpty) 'id': id,
        'milkman_id': milkmanId,
        'delivery_id': deliveryId,
        'entry_date': _isoDate(entryDate),
        'total_milk_used': totalMilkUsed,
        'expected_paneer': expectedPaneer,
        'actual_paneer': actualPaneer,
        'tolerance_kg': toleranceKg,
      };

  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'milkman_id': milkmanId,
        'delivery_id': deliveryId,
        'entry_date': _isoDate(entryDate),
        'total_milk_used': totalMilkUsed,
        'expected_paneer': expectedPaneer,
        'actual_paneer': actualPaneer,
        'yield_ratio': yieldRatio,
        'tolerance_kg': toleranceKg,
        'adjustment_applied': adjustmentApplied,
        'adjusted_milk_total': adjustedMilkTotal,
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

  factory Loan.fromJson(Map<String, dynamic> d) => Loan(
        id: d['id'] as String,
        milkmanId: d['milkman_id'] ?? '',
        loanDate: _parseDate(d['loan_date']),
        amount: _toDouble(d['amount']),
        notes: d['notes'] ?? '',
      );

  /// Body for POST /milkmen/{milkman_id}/loans (milkman_id is a path param).
  Map<String, dynamic> toCreateJson() => {
        if (id.isNotEmpty) 'id': id,
        'amount': amount,
        'loan_date': _isoTimestamp(loanDate),
        'notes': notes,
      };

  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'milkman_id': milkmanId,
        'amount': amount,
        'loan_date': _isoTimestamp(loanDate),
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
  final double milkRateApplied;
  final double khoyaRateApplied;

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
    this.milkRateApplied = 0.0,
    this.khoyaRateApplied = 0.0,
  });

  factory WeeklyPayment.fromJson(Map<String, dynamic> d) => WeeklyPayment(
        id: (d['id'] ?? '') as String,
        milkmanId: d['milkman_id'] ?? '',
        weekStartDate: _parseDate(d['week_start_date']),
        weekEndDate: _parseDate(d['week_end_date']),
        totalMilkKg: _toDouble(d['total_milk_kg']),
        milkEarnings: _toDouble(d['milk_earnings']),
        totalKhoyaKg: _toDouble(d['total_khoya_kg']),
        khoyaEarnings: _toDouble(d['khoya_earnings']),
        totalEarnings: _toDouble(d['total_earnings']),
        loanDeducted: _toDouble(d['loan_deducted']),
        carriedOverLoan: _toDouble(d['carried_over_loan']),
        netPayable: _toDouble(d['net_payable']),
        loanCarryForward: _toDouble(d['loan_carry_forward']),
        isPaid: d['is_paid'] ?? false,
        paidAt: d['paid_at'] == null ? null : _parseDate(d['paid_at']),
        milkRateApplied: _toDouble(d['milk_rate_applied']),
        khoyaRateApplied: _toDouble(d['khoya_rate_applied']),
      );

  /// Body for POST /milkmen/{milkman_id}/payments (upsert by milkman+week).
  Map<String, dynamic> toCreateJson() => {
        'week_start_date': _isoTimestamp(weekStartDate),
        'week_end_date': _isoTimestamp(weekEndDate),
        'total_milk_kg': totalMilkKg,
        'milk_earnings': milkEarnings,
        'total_khoya_kg': totalKhoyaKg,
        'khoya_earnings': khoyaEarnings,
        'total_earnings': totalEarnings,
        'loan_deducted': loanDeducted,
        'carried_over_loan': carriedOverLoan,
        'net_payable': netPayable,
        'loan_carry_forward': loanCarryForward,
        'is_paid': isPaid,
        'milk_rate_applied': milkRateApplied,
        'khoya_rate_applied': khoyaRateApplied,
      };

  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'milkman_id': milkmanId,
        ...toCreateJson(),
        'paid_at': paidAt == null ? null : _isoTimestamp(paidAt!),
      };
}

/// A queued print job (POST /print-jobs/). Returned rows omit the `pdf` bytes.
class PrintJob {
  final String id;
  final String jobType;
  final Map<String, dynamic> params;
  final String status; // pending | printing | done | failed
  final int attempts;
  final String? error;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? printedAt;

  PrintJob({
    required this.id,
    required this.jobType,
    required this.params,
    required this.status,
    required this.attempts,
    this.error,
    required this.createdAt,
    required this.updatedAt,
    this.printedAt,
  });

  factory PrintJob.fromJson(Map<String, dynamic> d) => PrintJob(
        id: d['id'] as String,
        jobType: d['job_type'] ?? '',
        params: (d['params'] as Map?)?.cast<String, dynamic>() ?? {},
        status: d['status'] ?? 'pending',
        attempts: (d['attempts'] ?? 0) as int,
        error: d['error'] as String?,
        createdAt: _parseDate(d['created_at']),
        updatedAt: _parseDate(d['updated_at']),
        printedAt: d['printed_at'] == null ? null : _parseDate(d['printed_at']),
      );
}
