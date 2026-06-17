// lib/database/local_store.dart
//
// On-device persistence for the offline-first layer. Holds:
//   - a cache of every collection (server-shaped JSON records, keyed by id), and
//   - an outbox of pending mutations to replay against the server.
//
// Backed by a single JSON file in the app documents directory (via the existing
// path_provider dependency), mirrored in memory for instant reads. Data volume
// for a dairy is small, so the whole state is rewritten on each change.
//
// NOTE: on web, path_provider has no documents dir, so the store runs
// in-memory only (no persistence across reloads). All native platforms persist.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

/// Collection names mirror the Postgres tables.
const kMilkmen = 'milkmen';
const kMilkDeliveries = 'milk_deliveries';
const kKhoyaDeliveries = 'khoya_deliveries';
const kPaneerEntries = 'paneer_entries';
const kLoans = 'loans';
const kWeeklyPayments = 'weekly_payments';

const _kCollections = [
  kMilkmen,
  kMilkDeliveries,
  kKhoyaDeliveries,
  kPaneerEntries,
  kLoans,
  kWeeklyPayments,
];

class LocalStore {
  // collection -> recordKey -> json record
  final Map<String, Map<String, Map<String, dynamic>>> _collections = {
    for (final c in _kCollections) c: <String, Map<String, dynamic>>{},
  };
  final Map<String, double> _settings = {};
  final List<Map<String, dynamic>> _outbox = [];
  int _seq = 0;

  File? _file;
  bool _ready = false;

  Future<void> init() async {
    if (kIsWeb) {
      _ready = true;
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/dairydues_cache.json');
      if (await _file!.exists()) {
        final raw = jsonDecode(await _file!.readAsString());
        if (raw is Map<String, dynamic>) _loadFrom(raw);
      }
    } catch (_) {
      // Corrupt/unreadable cache -> start empty; it will be repopulated on sync.
    }
    _ready = true;
  }

  void _loadFrom(Map<String, dynamic> data) {
    final cols = data['collections'];
    if (cols is Map) {
      for (final c in _kCollections) {
        final m = cols[c];
        if (m is Map) {
          _collections[c]!
            ..clear()
            ..addAll(m.map((k, v) =>
                MapEntry(k as String, (v as Map).cast<String, dynamic>())));
        }
      }
    }
    final settings = data['settings'];
    if (settings is Map) {
      _settings
        ..clear()
        ..addAll(settings.map((k, v) => MapEntry(k as String, (v as num).toDouble())));
    }
    final outbox = data['outbox'];
    if (outbox is List) {
      _outbox
        ..clear()
        ..addAll(outbox.map((e) => (e as Map).cast<String, dynamic>()));
    }
    _seq = (data['seq'] as num?)?.toInt() ?? 0;
  }

  Future<void> _persist() async {
    if (_file == null) return; // web / no-fs
    final data = {
      'collections': _collections,
      'settings': _settings,
      'outbox': _outbox,
      'seq': _seq,
    };
    try {
      await _file!.writeAsString(jsonEncode(data));
    } catch (_) {
      // Best-effort: a failed write just means this change isn't durable yet.
    }
  }

  bool get isReady => _ready;

  // ─── Cache: records ─────────────────────────────────────────────────────────

  List<Map<String, dynamic>> records(String collection) =>
      _collections[collection]!.values.map((e) => Map<String, dynamic>.from(e)).toList();

  Map<String, dynamic>? record(String collection, String key) {
    final r = _collections[collection]![key];
    return r == null ? null : Map<String, dynamic>.from(r);
  }

  Future<void> put(String collection, String key, Map<String, dynamic> json) async {
    _collections[collection]![key] = Map<String, dynamic>.from(json);
    await _persist();
  }

  Future<void> remove(String collection, String key) async {
    _collections[collection]!.remove(key);
    await _persist();
  }

  /// Replace a whole collection from a server pull. Optionally scoped to records
  /// matching [keep] (e.g. one milkman's rows) so a pull of a subset doesn't drop
  /// everything else.
  Future<void> replaceCollection(
    String collection,
    Iterable<MapEntry<String, Map<String, dynamic>>> entries, {
    bool Function(Map<String, dynamic> existing)? scope,
  }) async {
    final box = _collections[collection]!;
    if (scope != null) {
      box.removeWhere((_, v) => scope(v));
    } else {
      box.clear();
    }
    for (final e in entries) {
      box[e.key] = Map<String, dynamic>.from(e.value);
    }
    await _persist();
  }

  // ─── Cache: settings ────────────────────────────────────────────────────────

  double? setting(String key) => _settings[key];

  Future<void> putSetting(String key, double value) async {
    _settings[key] = value;
    await _persist();
  }

  // ─── Outbox ─────────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get outbox =>
      _outbox.map((e) => Map<String, dynamic>.from(e)).toList();

  int get pendingCount => _outbox.length;

  Future<void> enqueue(String kind, Map<String, dynamic> payload) async {
    _outbox.add({'seq': ++_seq, 'kind': kind, 'payload': payload});
    await _persist();
  }

  Future<void> removeOp(int seq) async {
    _outbox.removeWhere((o) => o['seq'] == seq);
    await _persist();
  }

  /// If a still-pending `create_*` op exists for [recordId], drop it and return
  /// true — used to collapse a create+delete that never reached the server.
  Future<bool> dropPendingCreate(String createKind, String recordId) async {
    final idx = _outbox.indexWhere((o) =>
        o['kind'] == createKind &&
        (o['payload'] as Map)['id'] == recordId);
    if (idx == -1) return false;
    _outbox.removeAt(idx);
    await _persist();
    return true;
  }
}
