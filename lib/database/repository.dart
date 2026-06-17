// lib/database/repository.dart
//
// Offline-first facade. This is what the providers/screens talk to (as `db`),
// with the same method names the old ApiService exposed, so callers barely
// change. Reads serve the local cache instantly (works with no connection).
// Writes apply to the cache + enqueue an outbox op + kick a background sync.
// Print jobs are inherently online and delegate straight to ApiService.

import 'package:uuid/uuid.dart';

import 'api_service.dart';
import 'local_store.dart';
import 'models.dart';
import 'sync_service.dart';

class Repository {
  final ApiService api;
  final LocalStore store;
  final SyncService syncService;
  final _uuid = const Uuid();

  Repository(this.api, this.store, this.syncService);

  // ─── helpers ───────────────────────────────────────────────────────────────

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Apply an op to the cache, queue it, and kick a background sync.
  Future<void> _mutate(String kind, Map<String, dynamic> payload) async {
    await cacheApply(store, kind, payload);
    await store.enqueue(kind, payload);
    _kick();
  }

  void _kick() {
    // fire-and-forget; SyncService no-ops if already syncing or offline
    syncService.sync();
  }

  List<Milkman> get _milkmen =>
      store.records(kMilkmen).map(Milkman.fromJson).toList();
  List<MilkDelivery> get _deliveries =>
      store.records(kMilkDeliveries).map(MilkDelivery.fromJson).toList();
  List<KhoyaDelivery> get _khoya =>
      store.records(kKhoyaDeliveries).map(KhoyaDelivery.fromJson).toList();
  List<PaneerEntry> get _paneer =>
      store.records(kPaneerEntries).map(PaneerEntry.fromJson).toList();
  List<Loan> get _loans =>
      store.records(kLoans).map(Loan.fromJson).toList();
  List<WeeklyPayment> get _payments =>
      store.records(kWeeklyPayments).map(WeeklyPayment.fromJson).toList();

  /// Pull from the server + flush the outbox (used by pull-to-refresh).
  Future<void> syncNow() => syncService.sync();

  // ─── SETTINGS ───────────────────────────────────────────────────────────────

  Future<double> getStandardPaneerKg() async =>
      store.setting('standard_paneer_kg') ?? 6.5;
  Future<double> getSampleMilkKg() async =>
      store.setting('sample_milk_kg') ?? 24.0;
  Future<double> getToleranceKg() async =>
      store.setting('paneer_tolerance_kg') ?? 0.5;

  Future<void> setSetting(String key, double value) =>
      _mutate('set_setting', {'key': key, 'value': value});

  // ─── MILKMEN ──────────────────────────────────────────────────────────────

  Future<List<Milkman>> getActiveMilkmen() async {
    final list = _milkmen.where((m) => m.isActive).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  Future<String> addMilkman(Milkman m) async {
    final id = m.id.isEmpty ? _uuid.v4() : m.id;
    final json = m.toCacheJson()..['id'] = id;
    await _mutate('create_milkman', json);
    return id;
  }

  Future<void> updateMilkman(Milkman m) =>
      _mutate('update_milkman', m.toCacheJson());

  Future<void> deactivateMilkman(String id) =>
      _mutate('deactivate_milkman', {'id': id});

  // ─── MILK DELIVERIES ──────────────────────────────────────────────────────

  Future<List<MilkDelivery>> getDeliveriesForDate(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final list = _deliveries.where((d) => _sameDay(d.deliveryDate, start)).toList()
      ..sort((a, b) => a.deliveryDate.compareTo(b.deliveryDate));
    return list;
  }

  Future<List<MilkDelivery>> getDeliveriesForWeek(
      String milkmanId, DateTime weekStart) async {
    final end = weekStart.add(const Duration(days: 7));
    return _deliveries
        .where((d) =>
            d.milkmanId == milkmanId &&
            !d.deliveryDate.isBefore(weekStart) &&
            d.deliveryDate.isBefore(end))
        .toList();
  }

  Future<String> addMilkDelivery(MilkDelivery d) async {
    final id = d.id.isEmpty ? _uuid.v4() : d.id;
    final json = d.toCacheJson()
      ..['id'] = id
      ..['billable_milk'] = d.netMilk
      ..['paneer_adjusted'] = false;
    await _mutate('create_milk_delivery', json);
    return id;
  }

  Future<void> deleteMilkDelivery(String milkmanId, String id) async {
    await store.remove(kMilkDeliveries, id);
    final droppedUnsynced =
        await store.dropPendingCreate('create_milk_delivery', id);
    if (!droppedUnsynced) {
      await store.enqueue(
          'delete_milk_delivery', {'id': id, 'milkman_id': milkmanId});
    }
    _kick();
  }

  // ─── KHOYA ────────────────────────────────────────────────────────────────

  Future<List<KhoyaDelivery>> getKhoyaForDate(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    return _khoya.where((k) => _sameDay(k.deliveryDate, start)).toList();
  }

  Future<List<KhoyaDelivery>> getKhoyaDeliveriesForWeek(
      String milkmanId, DateTime weekStart) async {
    final end = weekStart.add(const Duration(days: 7));
    return _khoya
        .where((k) =>
            k.milkmanId == milkmanId &&
            !k.deliveryDate.isBefore(weekStart) &&
            k.deliveryDate.isBefore(end))
        .toList();
  }

  Future<double> getTotalKhoyaForWeek(
      String milkmanId, DateTime weekStart) async {
    final list = await getKhoyaDeliveriesForWeek(milkmanId, weekStart);
    return list.fold<double>(0.0, (s, k) => s + k.weight);
  }

  Future<String> addKhoyaDelivery(KhoyaDelivery k) async {
    final id = k.id.isEmpty ? _uuid.v4() : k.id;
    final json = k.toCacheJson()..['id'] = id;
    await _mutate('create_khoya', json);
    return id;
  }

  Future<void> deleteKhoyaDelivery(String milkmanId, String id) async {
    await store.remove(kKhoyaDeliveries, id);
    final droppedUnsynced = await store.dropPendingCreate('create_khoya', id);
    if (!droppedUnsynced) {
      await store.enqueue('delete_khoya', {'id': id, 'milkman_id': milkmanId});
    }
    _kick();
  }

  // ─── PANEER ───────────────────────────────────────────────────────────────

  Future<List<PaneerEntry>> getPaneerEntriesForDate(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    return _paneer.where((e) => _sameDay(e.entryDate, start)).toList();
  }

  Future<List<PaneerEntry>> getRecentPaneerEntries({int limit = 30}) async {
    final list = _paneer..sort((a, b) => b.entryDate.compareTo(a.entryDate));
    return list.take(limit).toList();
  }

  /// Record a paneer test. The server recomputes on sync; locally we mirror the
  /// same adjustment so the delivery's billable updates immediately offline.
  Future<void> createPaneerEntry({
    required String milkmanId,
    required String deliveryId,
    required DateTime entryDate,
    required double totalMilkUsed,
    required double expectedPaneer,
    required double actualPaneer,
    double toleranceKg = 0,
  }) async {
    final id = _uuid.v4();
    final ratio = expectedPaneer > 0 ? actualPaneer / expectedPaneer : 1.0;
    final del = store.record(kMilkDeliveries, deliveryId);
    final net = del == null ? 0.0 : (del['net_milk'] as num).toDouble();
    final entry = PaneerEntry(
      id: id,
      milkmanId: milkmanId,
      deliveryId: deliveryId,
      entryDate: entryDate,
      totalMilkUsed: totalMilkUsed,
      expectedPaneer: expectedPaneer,
      actualPaneer: actualPaneer,
      yieldRatio: ratio,
      toleranceKg: toleranceKg,
      adjustmentApplied: true,
      adjustedMilkTotal: net * ratio,
    );
    await _mutate('create_paneer', entry.toCacheJson());
  }

  // ─── LOANS ────────────────────────────────────────────────────────────────

  Future<List<Loan>> getLoansForMilkman(String milkmanId, {int limit = 30}) async {
    final list = _loans.where((l) => l.milkmanId == milkmanId).toList()
      ..sort((a, b) => b.loanDate.compareTo(a.loanDate));
    return list.take(limit).toList();
  }

  Future<double> getTotalLoansForWeek(
      String milkmanId, DateTime weekStart) async {
    final end = weekStart.add(const Duration(days: 7));
    return _loans
        .where((l) =>
            l.milkmanId == milkmanId &&
            !l.loanDate.isBefore(weekStart) &&
            l.loanDate.isBefore(end))
        .fold<double>(0.0, (s, l) => s + l.amount);
  }

  Future<double> getCarriedOverLoan(
      String milkmanId, DateTime weekStart) async {
    final previous = _payments
        .where((p) => p.milkmanId == milkmanId && p.weekStartDate.isBefore(weekStart))
        .toList()
      ..sort((a, b) => b.weekStartDate.compareTo(a.weekStartDate));
    return previous.isEmpty ? 0.0 : previous.first.loanCarryForward;
  }

  Future<void> addLoan(Loan l) async {
    final id = l.id.isEmpty ? _uuid.v4() : l.id;
    final json = l.toCacheJson()..['id'] = id;
    await _mutate('create_loan', json);
  }

  Future<void> deleteLoan(String id) async {
    await store.remove(kLoans, id);
    final droppedUnsynced = await store.dropPendingCreate('create_loan', id);
    if (!droppedUnsynced) {
      await store.enqueue('delete_loan', {'id': id});
    }
    _kick();
  }

  // ─── WEEKLY PAYMENTS ──────────────────────────────────────────────────────

  Future<WeeklyPayment?> getPaymentForWeek(
      String milkmanId, DateTime weekStart) async {
    final r =
        store.record(kWeeklyPayments, weeklyPaymentKey(milkmanId, weekStart));
    return r == null ? null : WeeklyPayment.fromJson(r);
  }

  Future<void> upsertWeeklyPayment(WeeklyPayment p) =>
      _mutate('upsert_payment', p.toCacheJson());

  Future<void> markPaymentPaidForWeek(String milkmanId, DateTime weekStart) =>
      _mutate('mark_paid', {
        'milkman_id': milkmanId,
        'week_start_date': weekStart.toUtc().toIso8601String(),
      });

  // ─── PRINT JOBS (online-only — can't print offline) ───────────────────────

  Future<PrintJob> enqueuePrintJob(
          String jobType, Map<String, dynamic> params) =>
      api.enqueuePrintJob(jobType, params);

  Future<List<PrintJob>> getPrintJobs({String? status}) =>
      api.getPrintJobs(status: status);

  Future<PrintJob?> getPrintJob(String id) => api.getPrintJob(id);
}
