// lib/database/sync_service.dart
//
// The offline-first sync engine. Owns the outbox replay (local -> server) and
// the pull (server -> local cache), plus connectivity-driven auto-sync.
//
// Two pure helpers are shared with the Repository so a mutation is applied to
// the cache exactly the same way whether it's made live or re-overlaid after a
// pull:
//   - cacheApply(store, kind, payload): mutate the local cache for an op
//   - replayOp(api, kind, payload):     send the op to the server

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'local_store.dart';
import 'models.dart';

/// Stable cache key for a weekly payment (one row per milkman per week).
String weeklyPaymentKey(String milkmanId, DateTime weekStart) =>
    '$milkmanId|${weekStart.year.toString().padLeft(4, '0')}-'
    '${weekStart.month.toString().padLeft(2, '0')}-'
    '${weekStart.day.toString().padLeft(2, '0')}';

String _weeklyKeyFromJson(Map<String, dynamic> p) {
  final ws = DateTime.parse(p['week_start_date'] as String).toLocal();
  return weeklyPaymentKey(p['milkman_id'] as String, ws);
}

// ─── Local cache mutation for an outbox op ──────────────────────────────────

Future<void> cacheApply(
    LocalStore store, String kind, Map<String, dynamic> p) async {
  switch (kind) {
    case 'create_milkman':
    case 'update_milkman':
      await store.put(kMilkmen, p['id'] as String, p);
      break;
    case 'deactivate_milkman':
      final m = store.record(kMilkmen, p['id'] as String);
      if (m != null) {
        m['is_active'] = false;
        await store.put(kMilkmen, p['id'] as String, m);
      }
      break;
    case 'create_milk_delivery':
      await store.put(kMilkDeliveries, p['id'] as String, p);
      break;
    case 'delete_milk_delivery':
      await store.remove(kMilkDeliveries, p['id'] as String);
      break;
    case 'create_khoya':
      await store.put(kKhoyaDeliveries, p['id'] as String, p);
      break;
    case 'delete_khoya':
      await store.remove(kKhoyaDeliveries, p['id'] as String);
      break;
    case 'create_paneer':
      await store.put(kPaneerEntries, p['id'] as String, p);
      // Mirror the server-side billable adjustment locally so offline paneer
      // tests are reflected on the delivery immediately.
      final delId = p['delivery_id'] as String?;
      final expected = (p['expected_paneer'] as num).toDouble();
      final actual = (p['actual_paneer'] as num).toDouble();
      if (delId != null && expected > 0) {
        final del = store.record(kMilkDeliveries, delId);
        if (del != null) {
          final net = (del['net_milk'] as num).toDouble();
          del['billable_milk'] = net * (actual / expected);
          del['paneer_adjusted'] = true;
          await store.put(kMilkDeliveries, delId, del);
        }
      }
      break;
    case 'create_loan':
      await store.put(kLoans, p['id'] as String, p);
      break;
    case 'delete_loan':
      await store.remove(kLoans, p['id'] as String);
      break;
    case 'upsert_payment':
      await store.put(kWeeklyPayments, _weeklyKeyFromJson(p), p);
      break;
    case 'mark_paid':
      final key = _weeklyKeyFromJson(p);
      final wp = store.record(kWeeklyPayments, key);
      if (wp != null) {
        wp['is_paid'] = true;
        wp['paid_at'] = DateTime.now().toUtc().toIso8601String();
        await store.put(kWeeklyPayments, key, wp);
      }
      break;
    case 'set_setting':
      await store.putSetting(p['key'] as String, (p['value'] as num).toDouble());
      break;
  }
}

// ─── Network replay for an outbox op ────────────────────────────────────────

Future<void> replayOp(
    ApiService api, String kind, Map<String, dynamic> p) async {
  switch (kind) {
    case 'create_milkman':
      await api.addMilkman(Milkman.fromJson(p));
      break;
    case 'update_milkman':
      await api.updateMilkman(Milkman.fromJson(p));
      break;
    case 'deactivate_milkman':
      await api.deactivateMilkman(p['id'] as String);
      break;
    case 'create_milk_delivery':
      await api.addMilkDelivery(MilkDelivery.fromJson(p));
      break;
    case 'delete_milk_delivery':
      await api.deleteMilkDelivery(p['milkman_id'] as String, p['id'] as String);
      break;
    case 'create_khoya':
      await api.addKhoyaDelivery(KhoyaDelivery.fromJson(p));
      break;
    case 'delete_khoya':
      await api.deleteKhoyaDelivery(p['milkman_id'] as String, p['id'] as String);
      break;
    case 'create_paneer':
      await api.createPaneerEntry(
        id: p['id'] as String,
        milkmanId: p['milkman_id'] as String,
        deliveryId: p['delivery_id'] as String,
        entryDate: DateTime.parse(p['entry_date'] as String).toLocal(),
        totalMilkUsed: (p['total_milk_used'] as num).toDouble(),
        expectedPaneer: (p['expected_paneer'] as num).toDouble(),
        actualPaneer: (p['actual_paneer'] as num).toDouble(),
        toleranceKg: (p['tolerance_kg'] as num).toDouble(),
      );
      break;
    case 'create_loan':
      await api.addLoan(Loan.fromJson(p));
      break;
    case 'delete_loan':
      await api.deleteLoan(p['id'] as String);
      break;
    case 'upsert_payment':
      await api.upsertWeeklyPayment(WeeklyPayment.fromJson(p));
      break;
    case 'mark_paid':
      await api.markPaymentPaidByWeek(
        p['milkman_id'] as String,
        DateTime.parse(p['week_start_date'] as String).toLocal(),
      );
      break;
    case 'set_setting':
      await api.setSetting(p['key'] as String, (p['value'] as num).toDouble());
      break;
  }
}

// ─── SyncService ────────────────────────────────────────────────────────────

class SyncService extends ChangeNotifier {
  final ApiService api;
  final LocalStore store;

  SyncService(this.api, this.store);

  bool _online = true;
  bool _syncing = false;
  DateTime? _lastSyncAt;
  String? _lastError;
  StreamSubscription? _connSub;

  bool get online => _online;
  bool get syncing => _syncing;
  int get pendingCount => store.pendingCount;
  DateTime? get lastSyncAt => _lastSyncAt;
  String? get lastError => _lastError;

  /// Start listening for connectivity changes; auto-sync when the network
  /// comes back and an initial sync on startup.
  void start() {
    _connSub = Connectivity().onConnectivityChanged.listen((result) {
      final up = !result.contains(ConnectivityResult.none);
      final cameBack = up && !_online;
      _online = up;
      notifyListeners();
      if (cameBack) sync();
    });
    sync();
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }

  /// Flush the outbox to the server, then pull fresh data into the cache.
  /// Safe to call often; it no-ops while a sync is already running.
  Future<void> sync() async {
    if (_syncing) return;
    _syncing = true;
    _lastError = null;
    notifyListeners();
    try {
      await _flushOutbox();
      await _pull();
      _online = true;
      _lastSyncAt = DateTime.now();
    } on ApiException catch (e) {
      _lastError = e.message;
      if (e.kind == ApiErrorKind.network) _online = false;
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Replay queued mutations FIFO. Stops on a transient failure (network/5xx) to
  /// retry later; drops a permanently-failing op (4xx) so it can't wedge the queue.
  Future<void> _flushOutbox() async {
    for (final op in store.outbox) {
      final seq = op['seq'] as int;
      final kind = op['kind'] as String;
      final payload = (op['payload'] as Map).cast<String, dynamic>();
      try {
        await replayOp(api, kind, payload);
        await store.removeOp(seq);
      } on ApiException catch (e) {
        final permanent = e.kind == ApiErrorKind.server &&
            (e.statusCode != null && e.statusCode! >= 400 && e.statusCode! < 500);
        if (permanent) {
          // Won't ever succeed (bad request / not found) — drop and keep going.
          await store.removeOp(seq);
          _lastError = 'Dropped a change the server rejected: ${e.message}';
          continue;
        }
        rethrow; // transient (network / auth / 5xx): stop, retry next sync
      }
    }
  }

  /// Pull every collection from the server into the cache (server is truth),
  /// then re-overlay still-pending local ops so unsynced changes survive.
  Future<void> _pull() async {
    final milkmen = await api.getAllMilkmen();

    final milkmanEntries = <MapEntry<String, Map<String, dynamic>>>[];
    final deliveries = <MapEntry<String, Map<String, dynamic>>>[];
    final khoya = <MapEntry<String, Map<String, dynamic>>>[];
    final paneer = <MapEntry<String, Map<String, dynamic>>>[];
    final loans = <MapEntry<String, Map<String, dynamic>>>[];
    final payments = <MapEntry<String, Map<String, dynamic>>>[];

    for (final m in milkmen) {
      milkmanEntries.add(MapEntry(m.id, m.toCacheJson()));
    }
    for (final m in milkmen) {
      for (final d in await api.getMilkDeliveries(m.id)) {
        deliveries.add(MapEntry(d.id, d.toCacheJson()));
      }
      for (final k in await api.getKhoyaDeliveries(m.id)) {
        khoya.add(MapEntry(k.id, k.toCacheJson()));
      }
      for (final p in await api.getPaneerEntries(m.id)) {
        paneer.add(MapEntry(p.id, p.toCacheJson()));
      }
      for (final l in await api.getLoansForMilkman(m.id, limit: 100000)) {
        loans.add(MapEntry(l.id, l.toCacheJson()));
      }
      for (final wp in await api.getPaymentsForMilkman(m.id)) {
        payments.add(
            MapEntry(weeklyPaymentKey(wp.milkmanId, wp.weekStartDate), wp.toCacheJson()));
      }
    }

    await store.replaceCollection(kMilkmen, milkmanEntries);
    await store.replaceCollection(kMilkDeliveries, deliveries);
    await store.replaceCollection(kKhoyaDeliveries, khoya);
    await store.replaceCollection(kPaneerEntries, paneer);
    await store.replaceCollection(kLoans, loans);
    await store.replaceCollection(kWeeklyPayments, payments);

    final settings = await api.getAllSettings();
    for (final e in settings.entries) {
      await store.putSetting(e.key, e.value);
    }

    // Re-overlay queued local changes so the cache = server truth + pending ops.
    for (final op in store.outbox) {
      await cacheApply(
          store, op['kind'] as String, (op['payload'] as Map).cast<String, dynamic>());
    }
  }
}
