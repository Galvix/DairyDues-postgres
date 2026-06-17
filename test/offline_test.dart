// Offline-first core: local cache mutations + outbox semantics, with no server.

import 'package:flutter_test/flutter_test.dart';
import 'package:dairy_app/database/local_store.dart';
import 'package:dairy_app/database/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> milkman(String id, String name) => {
        'id': id,
        'name': name,
        'milk_rate': 50.0,
        'khoya_rate': 0.0,
        'supplies_khoya': false,
        'is_active': true,
      };

  Map<String, dynamic> delivery(String id, String milkmanId, double net) => {
        'id': id,
        'milkman_id': milkmanId,
        'delivery_date': DateTime.now().toUtc().toIso8601String(),
        'gross_weight': net,
        'can_weight': 0.0,
        'net_milk': net,
        'billable_milk': net,
        'paneer_adjusted': false,
        'notes': '',
      };

  test('cacheApply persists a created record', () async {
    final store = LocalStore();
    await store.init(); // in-memory in tests (no path_provider)
    await cacheApply(store, 'create_milkman', milkman('m1', 'Ravi'));
    expect(store.record(kMilkmen, 'm1')?['name'], 'Ravi');
  });

  test('offline paneer test mirrors the billable adjustment onto the delivery',
      () async {
    final store = LocalStore();
    await store.init();
    await cacheApply(store, 'create_milk_delivery', delivery('d1', 'm1', 100));
    await cacheApply(store, 'create_paneer', {
      'id': 'p1',
      'milkman_id': 'm1',
      'delivery_id': 'd1',
      'entry_date': '2026-06-18',
      'total_milk_used': 100.0,
      'expected_paneer': 6.5,
      'actual_paneer': 6.0,
      'yield_ratio': 6.0 / 6.5,
      'tolerance_kg': 0.0,
      'adjustment_applied': true,
      'adjusted_milk_total': 100 * 6.0 / 6.5,
    });
    final d = store.record(kMilkDeliveries, 'd1')!;
    expect(d['paneer_adjusted'], true);
    expect((d['billable_milk'] as num).toDouble(), closeTo(100 * 6.0 / 6.5, 1e-6));
  });

  test('outbox: enqueue, then create+delete of an unsynced record collapses',
      () async {
    final store = LocalStore();
    await store.init();
    await store.enqueue('create_loan', {'id': 'l1', 'amount': 100.0});
    expect(store.pendingCount, 1);

    // Deleting a not-yet-synced create drops the pending op (nothing to send).
    final dropped = await store.dropPendingCreate('create_loan', 'l1');
    expect(dropped, true);
    expect(store.pendingCount, 0);
  });
}
