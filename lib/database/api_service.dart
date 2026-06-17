// lib/database/api_service.dart
//
// Data layer backed by the self-hosted FastAPI + PostgreSQL backend (see ../api).
// Replaces the former FirestoreService. Public method names mirror the old
// service so the screens/provider change as little as possible.
//
// Auth: a single Dio instance attaches `Authorization: Bearer <API_TOKEN>` to
// every request via an interceptor. Base URL + token come from a gitignored
// .env (see .env.example), loaded by flutter_dotenv in main().

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'models.dart';

/// How an API call failed — lets the UI distinguish auth from network from server.
enum ApiErrorKind { auth, network, server, unknown }

class ApiException implements Exception {
  final String message;
  final ApiErrorKind kind;
  final int? statusCode;
  ApiException(this.message, this.kind, [this.statusCode]);

  @override
  String toString() => message;
}

class ApiService {
  late final Dio _dio;

  ApiService({Dio? dio}) {
    final baseUrl = (dotenv.env['API_BASE_URL'] ?? '').trim();
    final token = (dotenv.env['API_TOKEN'] ?? '').trim();

    _dio = dio ??
        Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          // Treat only 2xx as success; everything else surfaces as DioException
          // so _toApiException can classify it.
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  // ─── error mapping ──────────────────────────────────────────────────────────

  ApiException _toApiException(Object e) {
    if (e is ApiException) return e;
    if (e is DioException) {
      final status = e.response?.statusCode;
      if (status == 401) {
        return ApiException(
          'Authentication failed (401). Check API_TOKEN in your .env.',
          ApiErrorKind.auth,
          status,
        );
      }
      if (status != null && status >= 500) {
        return ApiException('Server error ($status).', ApiErrorKind.server, status);
      }
      if (status != null) {
        // 4xx other than 401 — surface the backend's `detail` if present.
        final data = e.response?.data;
        final detail = (data is Map && data['detail'] != null)
            ? data['detail'].toString()
            : 'Request failed ($status).';
        return ApiException(detail, ApiErrorKind.server, status);
      }
      return ApiException(
        'Network error: cannot reach the server. '
        'Check API_BASE_URL and your Tailscale connection.',
        ApiErrorKind.network,
      );
    }
    return ApiException(e.toString(), ApiErrorKind.unknown);
  }

  Future<T> _run<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw _toApiException(e);
    }
  }

  String _dateParam(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<Map<String, dynamic>> _asList(dynamic data) =>
      (data as List).cast<Map<String, dynamic>>();

  // ─── SETTINGS ───────────────────────────────────────────────────────────────

  Future<double> _getSetting(String key, double fallback) => _run(() async {
        try {
          final r = await _dio.get('/settings/$key');
          return (r.data['value'] as num).toDouble();
        } on DioException catch (e) {
          if (e.response?.statusCode == 404) return fallback;
          rethrow;
        }
      });

  Future<double> getStandardPaneerKg() => _getSetting('standard_paneer_kg', 6.5);
  Future<double> getSampleMilkKg() => _getSetting('sample_milk_kg', 24.0);
  Future<double> getToleranceKg() => _getSetting('paneer_tolerance_kg', 0.5);

  /// All settings as a map (used by the sync pull to seed the local cache).
  Future<Map<String, double>> getAllSettings() => _run(() async {
        final r = await _dio.get('/settings/');
        return {
          for (final s in _asList(r.data))
            s['key'] as String: (s['value'] as num).toDouble(),
        };
      });

  Future<void> setSetting(String key, double value) => _run(() async {
        await _dio.put('/settings/$key', data: {'value': value});
      });

  // ─── MILKMEN ──────────────────────────────────────────────────────────────

  Future<List<Milkman>> getActiveMilkmen() => _run(() async {
        final r = await _dio.get('/milkmen/',
            queryParameters: {'active_only': true});
        final list = _asList(r.data).map(Milkman.fromJson).toList();
        list.sort((a, b) => a.name.compareTo(b.name));
        return list;
      });

  /// All milkmen (active + inactive) — used to resolve names / fan out queries.
  Future<List<Milkman>> getAllMilkmen() => _run(() async {
        final r = await _dio.get('/milkmen/');
        return _asList(r.data).map(Milkman.fromJson).toList();
      });

  Future<String> addMilkman(Milkman m) => _run(() async {
        final r = await _dio.post('/milkmen/', data: m.toJson());
        return Milkman.fromJson(r.data).id;
      });

  Future<void> updateMilkman(Milkman m) => _run(() async {
        await _dio.patch('/milkmen/${m.id}', data: m.toJson());
      });

  Future<void> deactivateMilkman(String id) => _run(() async {
        await _dio.patch('/milkmen/$id', data: {'is_active': false});
      });

  // ─── MILK DELIVERIES ──────────────────────────────────────────────────────

  Future<List<MilkDelivery>> getMilkDeliveries(String milkmanId,
          {DateTime? from, DateTime? to}) =>
      _run(() async {
        final q = <String, dynamic>{};
        if (from != null) q['from_date'] = _dateParam(from);
        if (to != null) q['to_date'] = _dateParam(to);
        final r = await _dio.get('/milkmen/$milkmanId/deliveries',
            queryParameters: q.isEmpty ? null : q);
        return _asList(r.data).map(MilkDelivery.fromJson).toList();
      });

  Future<String> addMilkDelivery(MilkDelivery d) => _run(() async {
        final r = await _dio.post('/milkmen/${d.milkmanId}/deliveries',
            data: d.toCreateJson());
        return MilkDelivery.fromJson(r.data).id;
      });

  Future<void> deleteMilkDelivery(String milkmanId, String id) => _run(() async {
        await _dio.delete('/milkmen/$milkmanId/deliveries/$id');
      });

  /// All deliveries on [date], across every milkman. The backend only exposes
  /// per-milkman delivery lists, so this fans out. (See BACKEND GAPS in report.)
  Future<List<MilkDelivery>> getDeliveriesForDate(DateTime date) =>
      _run(() async {
        final start = DateTime(date.year, date.month, date.day);
        final milkmen = await getAllMilkmen();
        final out = <MilkDelivery>[];
        for (final m in milkmen) {
          final list =
              await getMilkDeliveries(m.id, from: start, to: start);
          out.addAll(list.where((d) => _sameDay(d.deliveryDate, start)));
        }
        out.sort((a, b) => a.deliveryDate.compareTo(b.deliveryDate));
        return out;
      });

  Future<List<MilkDelivery>> getDeliveriesForWeek(
          String milkmanId, DateTime weekStart) =>
      _run(() async {
        final end = weekStart.add(const Duration(days: 7));
        final list =
            await getMilkDeliveries(milkmanId, from: weekStart, to: end);
        return list
            .where((d) =>
                !d.deliveryDate.isBefore(weekStart) &&
                d.deliveryDate.isBefore(end))
            .toList();
      });

  // ─── KHOYA ────────────────────────────────────────────────────────────────

  Future<List<KhoyaDelivery>> getKhoyaDeliveries(String milkmanId,
          {DateTime? from, DateTime? to}) =>
      _run(() async {
        final q = <String, dynamic>{};
        if (from != null) q['from_date'] = _dateParam(from);
        if (to != null) q['to_date'] = _dateParam(to);
        final r = await _dio.get('/milkmen/$milkmanId/khoya',
            queryParameters: q.isEmpty ? null : q);
        return _asList(r.data).map(KhoyaDelivery.fromJson).toList();
      });

  Future<String> addKhoyaDelivery(KhoyaDelivery k) => _run(() async {
        final r = await _dio.post('/milkmen/${k.milkmanId}/khoya',
            data: k.toCreateJson());
        return KhoyaDelivery.fromJson(r.data).id;
      });

  Future<void> deleteKhoyaDelivery(String milkmanId, String id) => _run(() async {
        await _dio.delete('/milkmen/$milkmanId/khoya/$id');
      });

  Future<List<KhoyaDelivery>> getKhoyaForDate(DateTime date) => _run(() async {
        final start = DateTime(date.year, date.month, date.day);
        final milkmen = await getAllMilkmen();
        final out = <KhoyaDelivery>[];
        for (final m in milkmen) {
          if (!m.suppliesKhoya) continue;
          final list = await getKhoyaDeliveries(m.id, from: start, to: start);
          out.addAll(list.where((k) => _sameDay(k.deliveryDate, start)));
        }
        return out;
      });

  Future<List<KhoyaDelivery>> getKhoyaDeliveriesForWeek(
          String milkmanId, DateTime weekStart) =>
      _run(() async {
        final end = weekStart.add(const Duration(days: 7));
        final list =
            await getKhoyaDeliveries(milkmanId, from: weekStart, to: end);
        return list
            .where((k) =>
                !k.deliveryDate.isBefore(weekStart) &&
                k.deliveryDate.isBefore(end))
            .toList();
      });

  Future<double> getTotalKhoyaForWeek(String milkmanId, DateTime weekStart) async {
    final list = await getKhoyaDeliveriesForWeek(milkmanId, weekStart);
    return list.fold<double>(0.0, (s, k) => s + k.weight);
  }

  // ─── PANEER ───────────────────────────────────────────────────────────────

  Future<List<PaneerEntry>> getPaneerEntries(String milkmanId,
          {DateTime? from, DateTime? to}) =>
      _run(() async {
        final q = <String, dynamic>{};
        if (from != null) q['from_date'] = _dateParam(from);
        if (to != null) q['to_date'] = _dateParam(to);
        final r = await _dio.get('/milkmen/$milkmanId/paneer',
            queryParameters: q.isEmpty ? null : q);
        return _asList(r.data).map(PaneerEntry.fromJson).toList();
      });

  /// Records a paneer test against ONE specific delivery. The backend computes
  /// yield_ratio + adjusted_milk_total and writes billable_milk on that
  /// delivery itself (server-side adjustment).
  Future<PaneerEntry> createPaneerEntry({
    required String milkmanId,
    required String deliveryId,
    required DateTime entryDate,
    required double totalMilkUsed,
    required double expectedPaneer,
    required double actualPaneer,
    double toleranceKg = 0,
    String id = '',
  }) =>
      _run(() async {
        final body = PaneerEntry(
          id: id,
          milkmanId: milkmanId,
          deliveryId: deliveryId,
          entryDate: entryDate,
          totalMilkUsed: totalMilkUsed,
          expectedPaneer: expectedPaneer,
          actualPaneer: actualPaneer,
          yieldRatio: 0,
          toleranceKg: toleranceKg,
          adjustmentApplied: false,
        ).toCreateJson();
        final r = await _dio.post('/milkmen/$milkmanId/paneer', data: body);
        return PaneerEntry.fromJson(r.data);
      });

  Future<List<PaneerEntry>> getPaneerEntriesForDate(DateTime date) =>
      _run(() async {
        final start = DateTime(date.year, date.month, date.day);
        final milkmen = await getAllMilkmen();
        final out = <PaneerEntry>[];
        for (final m in milkmen) {
          final list = await getPaneerEntries(m.id, from: start, to: start);
          out.addAll(list.where((e) => _sameDay(e.entryDate, start)));
        }
        return out;
      });

  Future<List<PaneerEntry>> getRecentPaneerEntries({int limit = 30}) =>
      _run(() async {
        final milkmen = await getAllMilkmen();
        final out = <PaneerEntry>[];
        for (final m in milkmen) {
          out.addAll(await getPaneerEntries(m.id));
        }
        out.sort((a, b) => b.entryDate.compareTo(a.entryDate));
        return out.take(limit).toList();
      });

  // ─── LOANS ────────────────────────────────────────────────────────────────

  Future<void> addLoan(Loan l) => _run(() async {
        await _dio.post('/milkmen/${l.milkmanId}/loans', data: l.toCreateJson());
      });

  Future<void> deleteLoan(String id) => _run(() async {
        await _dio.delete('/loans/$id');
      });

  Future<List<Loan>> getLoansForMilkman(String milkmanId, {int limit = 30}) =>
      _run(() async {
        final r = await _dio.get('/milkmen/$milkmanId/loans');
        final list = _asList(r.data).map(Loan.fromJson).toList();
        list.sort((a, b) => b.loanDate.compareTo(a.loanDate));
        return list.take(limit).toList();
      });

  Future<double> getTotalLoansForWeek(
      String milkmanId, DateTime weekStart) async {
    final end = weekStart.add(const Duration(days: 7));
    final loans = await getLoansForMilkman(milkmanId, limit: 1000);
    return loans
        .where((l) =>
            !l.loanDate.isBefore(weekStart) && l.loanDate.isBefore(end))
        .fold<double>(0.0, (s, l) => s + l.amount);
  }

  Future<double> getCarriedOverLoan(
      String milkmanId, DateTime weekStart) async {
    final payments = await getPaymentsForMilkman(milkmanId);
    final previous =
        payments.where((p) => p.weekStartDate.isBefore(weekStart)).toList();
    if (previous.isEmpty) return 0.0;
    previous.sort((a, b) => b.weekStartDate.compareTo(a.weekStartDate));
    return previous.first.loanCarryForward;
  }

  // ─── WEEKLY PAYMENTS ──────────────────────────────────────────────────────

  Future<List<WeeklyPayment>> getPaymentsForMilkman(String milkmanId) =>
      _run(() async {
        final r = await _dio.get('/milkmen/$milkmanId/payments');
        return _asList(r.data).map(WeeklyPayment.fromJson).toList();
      });

  Future<WeeklyPayment?> getPaymentForWeek(
      String milkmanId, DateTime weekStart) async {
    final payments = await getPaymentsForMilkman(milkmanId);
    final matches =
        payments.where((p) => _sameDay(p.weekStartDate, weekStart)).toList();
    return matches.isEmpty ? null : matches.first;
  }

  /// Upserts the weekly payment row (backend ON CONFLICT (milkman, week_start)).
  Future<void> upsertWeeklyPayment(WeeklyPayment p) => _run(() async {
        await _dio.post('/milkmen/${p.milkmanId}/payments',
            data: p.toCreateJson());
      });

  Future<void> markPaymentPaid(String id) => _run(() async {
        await _dio.patch('/payments/$id/mark-paid');
      });

  /// Mark a week paid by natural key (offline-first: no server payment id needed).
  Future<void> markPaymentPaidByWeek(String milkmanId, DateTime weekStart) =>
      _run(() async {
        await _dio.patch('/milkmen/$milkmanId/payments/mark-paid',
            data: {'week_start_date': weekStart.toUtc().toIso8601String()});
      });

  // ─── PRINT JOBS ─────────────────────────────────────────────────────────────

  /// Enqueue a print job for the home print-agent (PDF is rendered server-side).
  Future<PrintJob> enqueuePrintJob(
          String jobType, Map<String, dynamic> params) =>
      _run(() async {
        final r = await _dio.post('/print-jobs/',
            data: {'job_type': jobType, 'params': params});
        return PrintJob.fromJson(r.data);
      });

  /// Recent print jobs (optionally filtered by status) — used to poll
  /// pending -> printing -> done/failed.
  Future<List<PrintJob>> getPrintJobs({String? status}) => _run(() async {
        final r = await _dio.get('/print-jobs/',
            queryParameters: status == null ? null : {'status_filter': status});
        return _asList(r.data).map(PrintJob.fromJson).toList();
      });

  /// Latest status of a single enqueued job (found within the recent list).
  Future<PrintJob?> getPrintJob(String id) async {
    final jobs = await getPrintJobs();
    for (final j in jobs) {
      if (j.id == id) return j;
    }
    return null;
  }
}
