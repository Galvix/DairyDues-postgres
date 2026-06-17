// lib/database/firestore_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'models.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference get _milkmen => _db.collection('milkmen');
  CollectionReference get _deliveries => _db.collection('deliveries');
  CollectionReference get _khoya => _db.collection('khoya');
  CollectionReference get _paneer => _db.collection('paneer');
  CollectionReference get _loans => _db.collection('loans');
  CollectionReference get _payments => _db.collection('weeklyPayments');
  CollectionReference get _settings => _db.collection('settings');

  // ─── SETTINGS ─────────────────────────────────────────────────────────────

  Future<double> getStandardPaneerKg() async {
    try {
      final doc = await _settings.doc('standard_paneer_kg').get();
      if (!doc.exists) return 6.5;
      return ((doc.data() as Map)['value'] ?? 6.5).toDouble();
    } catch (_) {
      return 6.5;
    }
  }

  Future<double> getSampleMilkKg() async {
    try {
      final doc = await _settings.doc('sample_milk_kg').get();
      if (!doc.exists) return 24.0;
      return ((doc.data() as Map)['value'] ?? 24.0).toDouble();
    } catch (_) {
      return 24.0;
    }
  }

  Future<double> getToleranceKg() async {
    try {
      final doc = await _settings.doc('paneer_tolerance_kg').get();
      if (!doc.exists) return 0.5;
      return ((doc.data() as Map)['value'] ?? 0.5).toDouble();
    } catch (_) {
      return 0.5;
    }
  }

  Future<void> setSetting(String key, double value) =>
      _settings.doc(key).set({'value': value});

  // ─── MILKMEN ──────────────────────────────────────────────────────────────

  Stream<List<Milkman>> watchActiveMilkmen() {
    return _milkmen
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) =>
              Milkman.fromFirestore(d.id, d.data() as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => a.name.compareTo(b.name));
      return list;
    });
  }

  Future<List<Milkman>> getActiveMilkmen() async {
    final snap = await _milkmen.where('isActive', isEqualTo: true).get();
    final list = snap.docs
        .map((d) =>
            Milkman.fromFirestore(d.id, d.data() as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  Future<String> addMilkman(Milkman m) async {
    final ref = await _milkmen.add(m.toMap());
    return ref.id;
  }

  Future<void> updateMilkman(Milkman m) =>
      _milkmen.doc(m.id).update(m.toMap());

  Future<void> deactivateMilkman(String id) =>
      _milkmen.doc(id).update({'isActive': false});

  // ─── MILK DELIVERIES ──────────────────────────────────────────────────────

  Future<String> addMilkDelivery(MilkDelivery d) async {
    final ref = await _deliveries.add(d.toMap());
    return ref.id;
  }

  Future<void> deleteMilkDelivery(String id) => _deliveries.doc(id).delete();

  Stream<List<MilkDelivery>> watchDeliveriesForDate(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return _deliveries
        .where('deliveryDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('deliveryDate', isLessThan: Timestamp.fromDate(end))
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => MilkDelivery.fromFirestore(
              d.id, d.data() as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => a.deliveryDate.compareTo(b.deliveryDate));
      return list;
    });
  }

  Future<List<MilkDelivery>> getAllDeliveriesForDate(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final snap = await _deliveries
        .where('deliveryDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('deliveryDate', isLessThan: Timestamp.fromDate(end))
        .get();
    return snap.docs
        .map((d) =>
            MilkDelivery.fromFirestore(d.id, d.data() as Map<String, dynamic>))
        .toList();
  }

  Future<List<MilkDelivery>> getDeliveriesForWeek(
      String milkmanId, DateTime weekStart) async {
    final end = weekStart.add(const Duration(days: 7));
    final snap =
        await _deliveries.where('milkmanId', isEqualTo: milkmanId).get();
    return snap.docs
        .map((d) =>
            MilkDelivery.fromFirestore(d.id, d.data() as Map<String, dynamic>))
        .where((d) =>
            !d.deliveryDate.isBefore(weekStart) && d.deliveryDate.isBefore(end))
        .toList();
  }

  Future<void> applyPaneerAdjustment(
      DateTime date, double adjustedMilkTotal) async {
    final deliveries = await getAllDeliveriesForDate(date);
    final actualTotal =
        deliveries.fold<double>(0.0, (s, d) => s + d.netMilk);
    if (actualTotal <= 0) return;

    final ratio = adjustedMilkTotal / actualTotal;
    final batch = _db.batch();
    for (final d in deliveries) {
      batch.update(_deliveries.doc(d.id), {
        'billableMilk': d.netMilk * ratio,
        'paneerAdjusted': true,
      });
    }
    await batch.commit();
  }

  // ─── KHOYA ────────────────────────────────────────────────────────────────

  Future<void> addKhoyaDelivery(KhoyaDelivery k) => _khoya.add(k.toMap());

  Future<void> deleteKhoyaDelivery(String id) => _khoya.doc(id).delete();

  Stream<List<KhoyaDelivery>> watchKhoyaForDate(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return _khoya
        .where('deliveryDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('deliveryDate', isLessThan: Timestamp.fromDate(end))
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => KhoyaDelivery.fromFirestore(
                d.id, d.data() as Map<String, dynamic>))
            .toList());
  }

  Future<List<KhoyaDelivery>> getKhoyaDeliveriesForWeek(
      String milkmanId, DateTime weekStart) async {
    final end = weekStart.add(const Duration(days: 7));
    final snap = await _khoya.where('milkmanId', isEqualTo: milkmanId).get();
    return snap.docs
        .map((d) =>
            KhoyaDelivery.fromFirestore(d.id, d.data() as Map<String, dynamic>))
        .where((k) =>
            !k.deliveryDate.isBefore(weekStart) &&
            k.deliveryDate.isBefore(end))
        .toList();
  }

  Future<double> getTotalKhoyaForWeek(
      String milkmanId, DateTime weekStart) async {
    final list = await getKhoyaDeliveriesForWeek(milkmanId, weekStart);
    return list.fold<double>(0.0, (s, k) => s + k.weight);
  }

  // ─── PANEER ───────────────────────────────────────────────────────────────

  Future<void> addPaneerEntry(PaneerEntry p) => _paneer.add(p.toMap());

  Future<PaneerEntry?> getPaneerEntryForDateAndMilkman(
      DateTime date, String milkmanId) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final snap = await _paneer
        .where('entryDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('entryDate', isLessThan: Timestamp.fromDate(end))
        .where('milkmanId', isEqualTo: milkmanId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return PaneerEntry.fromFirestore(
        snap.docs.first.id, snap.docs.first.data() as Map<String, dynamic>);
  }

  Stream<List<PaneerEntry>> watchPaneerEntriesForDate(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return _paneer
        .where('entryDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('entryDate', isLessThan: Timestamp.fromDate(end))
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => PaneerEntry.fromFirestore(
                d.id, d.data() as Map<String, dynamic>))
            .toList());
  }

  Stream<List<PaneerEntry>> watchRecentPaneerEntries({int limit = 30}) {
    return _paneer
        .orderBy('entryDate', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => PaneerEntry.fromFirestore(
                d.id, d.data() as Map<String, dynamic>))
            .toList());
  }

  Future<void> applyPaneerAdjustmentForMilkman(
      DateTime date, String milkmanId, double effectiveRatio) async {
    final deliveries = await getAllDeliveriesForDate(date);
    final myDeliveries =
        deliveries.where((d) => d.milkmanId == milkmanId).toList();
    final batch = _db.batch();
    for (final d in myDeliveries) {
      batch.update(_deliveries.doc(d.id), {
        'billableMilk': d.netMilk * effectiveRatio,
        'paneerAdjusted': true,
      });
    }
    await batch.commit();
  }

  // ─── LOANS ────────────────────────────────────────────────────────────────

  Future<void> addLoan(Loan l) => _loans.add(l.toMap());

  Future<void> deleteLoan(String id) => _loans.doc(id).delete();

  Stream<List<Loan>> watchLoansForMilkman(String milkmanId,
      {int limit = 30}) {
    return _loans
        .where('milkmanId', isEqualTo: milkmanId)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map(
              (d) => Loan.fromFirestore(d.id, d.data() as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.loanDate.compareTo(a.loanDate));
      return list.take(limit).toList();
    });
  }

  Future<double> getTotalLoansForWeek(
      String milkmanId, DateTime weekStart) async {
    final end = weekStart.add(const Duration(days: 7));
    final snap = await _loans.where('milkmanId', isEqualTo: milkmanId).get();
    return snap.docs
        .map(
            (d) => Loan.fromFirestore(d.id, d.data() as Map<String, dynamic>))
        .where((l) =>
            !l.loanDate.isBefore(weekStart) && l.loanDate.isBefore(end))
        .fold<double>(0.0, (s, l) => s + l.amount);
  }

  Future<double> getCarriedOverLoan(
      String milkmanId, DateTime weekStart) async {
    final snap =
        await _payments.where('milkmanId', isEqualTo: milkmanId).get();
    final previous = snap.docs
        .map((d) => WeeklyPayment.fromFirestore(
            d.id, d.data() as Map<String, dynamic>))
        .where((p) => p.weekStartDate.isBefore(weekStart))
        .toList();
    if (previous.isEmpty) return 0.0;
    previous.sort((a, b) => b.weekStartDate.compareTo(a.weekStartDate));
    return previous.first.loanCarryForward;
  }

  // ─── WEEKLY PAYMENTS ──────────────────────────────────────────────────────

  Future<WeeklyPayment?> getPaymentForWeek(
      String milkmanId, DateTime weekStart) async {
    final snap =
        await _payments.where('milkmanId', isEqualTo: milkmanId).get();
    final matches = snap.docs
        .map((d) => WeeklyPayment.fromFirestore(
            d.id, d.data() as Map<String, dynamic>))
        .where((p) => _sameDay(p.weekStartDate, weekStart))
        .toList();
    return matches.isEmpty ? null : matches.first;
  }

  Future<void> upsertWeeklyPayment(WeeklyPayment p) async {
    final existing = await getPaymentForWeek(p.milkmanId, p.weekStartDate);
    if (existing != null) {
      if (!existing.isPaid) {
        await _payments.doc(existing.id).update(p.toMap());
      }
    } else {
      await _payments.add(p.toMap());
    }
  }

  Future<void> markPaymentPaid(String id) => _payments.doc(id).update({
        'isPaid': true,
        'paidAt': Timestamp.fromDate(DateTime.now()),
      });

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
