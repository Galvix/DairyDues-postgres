// lib/screens/payment/payment_screen.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' as xl;
import 'package:path_provider/path_provider.dart';
import '../../database/models.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/payment_calculator.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  DateTime _weekStart = DateHelpers.getWeekStart(DateTime.now());
  bool _loading = false;
  String? _error;
  List<WeeklyPaymentSummary> _summaries = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final provider = context.read<AppProvider>();
      final summaries = await provider.calculateWeeklyPayments(_weekStart);
      if (mounted) setState(() { _summaries = summaries; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _changeWeek(int direction) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: 7 * direction));
      _summaries = [];
      _error = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final total = _summaries.fold<double>(0.0, (s, x) => s + x.netPayable);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly Payment'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Generate Full Payslip',
            onPressed: _summaries.isEmpty || _loading ? null : _exportAllPdf,
          ),
          IconButton(
            icon: const Icon(Icons.table_chart_outlined),
            tooltip: 'Export Excel',
            onPressed: _summaries.isEmpty ? null : _exportExcel,
          ),
        ],
      ),
      body: Column(children: [
        Container(
          color: AppTheme.primary.withOpacity(0.06),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _loading ? null : () => _changeWeek(-1),
            ),
            Expanded(
              child: Column(children: [
                Text(DateHelpers.formatWeekRange(_weekStart),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                    textAlign: TextAlign.center),
                Text('Total: ${DateHelpers.formatCurrency(total)}',
                    style: const TextStyle(
                        color: AppTheme.success,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _loading ||
                      _weekStart.isAfter(
                          DateTime.now().subtract(const Duration(days: 7)))
                  ? null
                  : () => _changeWeek(1),
            ),
          ]),
        ),
        Expanded(child: _buildBody()),
      ]),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading payment data...',
              style: TextStyle(color: Colors.grey)),
        ]),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 12),
                const Text('Failed to load payments',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Text(_error!,
                    style:
                        const TextStyle(color: Colors.red, fontSize: 12),
                    textAlign: TextAlign.center),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ]),
        ),
      );
    }

    if (_summaries.isEmpty) {
      return Center(
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.payments_outlined,
                  size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text('No data for this week',
                  style: TextStyle(color: Colors.grey[500])),
              const SizedBox(height: 8),
              Text('Add milkmen and milk entries first',
                  style:
                      TextStyle(color: Colors.grey[400], fontSize: 13)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: _summaries.length,
      itemBuilder: (_, i) => _PayCard(
        summary: _summaries[i],
        weekStart: _weekStart,
        onMarkPaid: () => _markPaid(i),
        onPrint: () => _printSlip(_summaries[i]),
      ),
    );
  }

  Future<void> _markPaid(int i) async {
    try {
      final db = context.read<AppProvider>().db;
      final s = _summaries[i];
      final payment = await db.getPaymentForWeek(s.milkmanId, _weekStart);
      if (payment != null) {
        await db.markPaymentPaid(payment.id);
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─── Individual slip (simple A5 per worker) ──────────────────────────────

  Future<void> _printSlip(WeeklyPaymentSummary s) async {
    final bytes = await _buildSimpleSlip(s);
    await Printing.layoutPdf(onLayout: (_) => bytes);
  }

  Future<Uint8List> _buildSimpleSlip(WeeklyPaymentSummary s) async {
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('DAIRY PAYMENT SLIP',
                      style: pw.TextStyle(
                          fontSize: 15,
                          fontWeight: pw.FontWeight.bold)),
                  pw.Text(DateHelpers.formatWeekRange(_weekStart),
                      style: const pw.TextStyle(fontSize: 10)),
                ]),
            pw.Divider(thickness: 1.5),
            pw.SizedBox(height: 6),
            pw.Text(s.milkmanName,
                style: pw.TextStyle(
                    fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 14),
            _pRow('Milk',
                '${s.totalMilkKg.toStringAsFixed(2)} kg × ${s.milkRate.toStringAsFixed(2)}/kg'),
            _pRow('Milk Earnings',
                DateHelpers.formatCurrency(s.milkEarnings)),
            if (s.totalKhoyaKg > 0)
              _pRow('Khoya',
                  '${s.totalKhoyaKg.toStringAsFixed(2)} kg × ${s.khoyaRate.toStringAsFixed(2)}/kg'),
            if (s.totalKhoyaKg > 0)
              _pRow('Khoya Earnings',
                  DateHelpers.formatCurrency(s.khoyaEarnings)),
            pw.Divider(),
            _pRow('Total Earnings',
                DateHelpers.formatCurrency(s.totalEarnings),
                bold: true),
            if (s.carriedOverLoan > 0)
              _pRow('Carried Over Loan',
                  '- ${DateHelpers.formatCurrency(s.carriedOverLoan)}',
                  valueColor: PdfColors.red),
            if (s.thisWeekLoans > 0)
              _pRow('This Week Loans',
                  '- ${DateHelpers.formatCurrency(s.thisWeekLoans)}',
                  valueColor: PdfColors.red),
            pw.Divider(thickness: 1.5),
            _pRow('NET PAYABLE',
                DateHelpers.formatCurrency(s.netPayable),
                bold: true,
                fontSize: 14,
                valueColor: PdfColors.green800),
            if (s.loanCarryForward > 0)
              _pRow('Loan Carry Forward',
                  DateHelpers.formatCurrency(s.loanCarryForward),
                  valueColor: PdfColors.orange),
            pw.SizedBox(height: 28),
            pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _signLine('Receiver Signature'),
                  _signLine('Factory Signature'),
                ]),
          ]),
    ));
    return pdf.save();
  }

  pw.Widget _pRow(String label, String value,
      {bool bold = false,
      double fontSize = 12,
      PdfColor? valueColor}) {
    final style = bold
        ? pw.TextStyle(
            fontWeight: pw.FontWeight.bold, fontSize: fontSize)
        : pw.TextStyle(fontSize: fontSize);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: style),
            pw.Text(value,
                style: pw.TextStyle(
                    fontWeight: bold
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                    fontSize: fontSize,
                    color: valueColor)),
          ]),
    );
  }

  pw.Widget _signLine(String label) => pw.Column(children: [
        pw.Container(width: 110, height: 1, color: PdfColors.black),
        pw.SizedBox(height: 4),
        pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
      ]);

  // ─── Full payslip PDF (all milkmen) ──────────────────────────────────────

  Future<void> _exportAllPdf() async {
    setState(() => _loading = true);
    try {
      final details = await _fetchWeeklyDetails();
      final bytes = await _buildFullPdf(details);
      if (mounted) await Printing.layoutPdf(onLayout: (_) => bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('PDF error: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<_MilkmanDetail>> _fetchWeeklyDetails() async {
    final db = context.read<AppProvider>().db;
    final details = <_MilkmanDetail>[];

    for (final s in _summaries) {
      final deliveries =
          await db.getDeliveriesForWeek(s.milkmanId, _weekStart);
      final khoyaList =
          await db.getKhoyaDeliveriesForWeek(s.milkmanId, _weekStart);

      final milkByDay = <DateTime, double>{};
      for (final d in deliveries) {
        final day = DateTime(
            d.deliveryDate.year, d.deliveryDate.month, d.deliveryDate.day);
        milkByDay[day] = (milkByDay[day] ?? 0) + d.netMilk;
      }

      final khoyaByDay = <DateTime, double>{};
      for (final k in khoyaList) {
        final day = DateTime(
            k.deliveryDate.year, k.deliveryDate.month, k.deliveryDate.day);
        khoyaByDay[day] = (khoyaByDay[day] ?? 0) + k.weight;
      }

      details.add(_MilkmanDetail(
          summary: s, milkByDay: milkByDay, khoyaByDay: khoyaByDay));
    }
    return details;
  }

  Future<Uint8List> _buildFullPdf(List<_MilkmanDetail> details) async {
    final pdf = pw.Document();
    final weekEnd = DateHelpers.getWeekEnd(_weekStart);
    final fmtFull = DateFormat('dd/MM/yyyy');
    final fmtMed = DateFormat('dd MMM yyyy');

    // Aggregate totals
    final totalMilkKg =
        _summaries.fold<double>(0.0, (s, x) => s + x.totalMilkKg);
    final totalMilkValue =
        _summaries.fold<double>(0.0, (s, x) => s + x.milkEarnings);
    final totalKhoyaKg =
        _summaries.fold<double>(0.0, (s, x) => s + x.totalKhoyaKg);
    final totalKhoyaValue =
        _summaries.fold<double>(0.0, (s, x) => s + x.khoyaEarnings);
    final totalEarnings =
        _summaries.fold<double>(0.0, (s, x) => s + x.totalEarnings);
    final totalDeducted =
        _summaries.fold<double>(0.0, (s, x) => s + x.totalLoanDeducted);
    final totalNet =
        _summaries.fold<double>(0.0, (s, x) => s + x.netPayable);
    final totalLoans = _summaries.fold<double>(
        0.0, (s, x) => s + x.thisWeekLoans + x.carriedOverLoan);
    final totalCarryForward =
        _summaries.fold<double>(0.0, (s, x) => s + x.loanCarryForward);

    // ─── Page 1: Grand Summary (A5) ────────────────────────────────────────
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(20),
      build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // Header
            pw.Container(
              width: double.infinity,
              decoration: pw.BoxDecoration(
                border:
                    pw.Border.all(color: PdfColors.blueGrey, width: 1.5),
                color: PdfColors.blueGrey50,
              ),
              padding: const pw.EdgeInsets.all(10),
              child: pw.Row(
                  mainAxisAlignment:
                      pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                        crossAxisAlignment:
                            pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Shri Raggha Seth Chamcham Wale',
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 14)),
                          pw.Text(
                              '${fmtFull.format(_weekStart)} - ${fmtFull.format(weekEnd)}',
                              style: const pw.TextStyle(
                                  fontSize: 9,
                                  color: PdfColors.grey600)),
                        ]),
                    pw.Text('WEEKLY GRAND TOTALS',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10,
                            color: PdfColors.blueGrey700)),
                  ]),
            ),
            pw.SizedBox(height: 10),
            pw.Text('WEEKLY PAYSLIP SUMMARY',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 13)),
            pw.Text(
                '${fmtMed.format(_weekStart)} - ${fmtMed.format(weekEnd)}',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey600)),
            pw.SizedBox(height: 10),

            // Main table
            pw.Table(
              border: pw.TableBorder.all(
                  color: PdfColors.blueGrey200, width: 0.5),
              tableWidth: pw.TableWidth.max,
              columnWidths: const {
                0: pw.FlexColumnWidth(2.2),
                1: pw.FlexColumnWidth(1),
              },
              children: [
                _tHeader(['PARTICULARS', 'VALUES']),
                _tRow('Total Milk Collected',
                    '${totalMilkKg.toStringAsFixed(2)} kg'),
                _tRow('Total Milk Value',
                    _c(totalMilkValue)),
                if (totalKhoyaKg > 0)
                  _tRow('Total Khoya Produced',
                      '${totalKhoyaKg.toStringAsFixed(2)} kg'),
                if (totalKhoyaKg > 0)
                  _tRow('Total Khoya Value',
                      _c(totalKhoyaValue)),
                _tRow('Total Earnings', _c(totalEarnings)),
                _tRow('Deductions: Loans',
                    '- ${_c(totalDeducted)}',
                    valueColor: PdfColors.red700),
                _tRowHighlight(
                    'Net Payments Given\n(After Loan Deductions)',
                    _c(totalNet)),
              ],
            ),
            pw.SizedBox(height: 10),

            // Loan adjustments
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                    color: PdfColors.blueGrey200, width: 0.5),
              ),
              child: pw.Column(children: [
                pw.Container(
                  color: PdfColors.blueGrey100,
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  child: pw.SizedBox(
                    width: double.infinity,
                    child: pw.Text('LOAN ADJUSTMENTS',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10)),
                  ),
                ),
                pw.Table(
                  border: pw.TableBorder(
                      horizontalInside: const pw.BorderSide(
                          color: PdfColors.blueGrey100,
                          width: 0.5)),
                  tableWidth: pw.TableWidth.max,
                  columnWidths: const {
                    0: pw.FlexColumnWidth(2.2),
                    1: pw.FlexColumnWidth(1),
                  },
                  children: [
                    _tRow('Total Loans', _c(totalLoans)),
                    _tRow('Deducted This Week', _c(totalDeducted)),
                    _tRow('Remaining Loan', _c(totalCarryForward)),
                  ],
                ),
              ]),
            ),
            pw.Spacer(),

            // Footer
            pw.Row(
                mainAxisAlignment:
                    pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                      'Date: ${fmtFull.format(DateTime.now())}',
                      style: const pw.TextStyle(
                          fontSize: 8, color: PdfColors.grey500)),
                  pw.Column(
                      crossAxisAlignment:
                          pw.CrossAxisAlignment.center,
                      children: [
                        pw.SizedBox(height: 20),
                        pw.Container(
                            width: 90,
                            height: 0.5,
                            color: PdfColors.black),
                        pw.SizedBox(height: 3),
                        pw.Text('Authorized Signature',
                            style: const pw.TextStyle(
                                fontSize: 8)),
                      ]),
                ]),
          ]),
    ));

    // ─── Pages 2+: Individual Worker Breakdowns (A4, 4 per page) ───────────
    for (var i = 0; i < details.length; i += 4) {
      final batch = details.skip(i).take(4).toList();
      final pageNum = i ~/ 4 + 2;

      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(14),
        build: (_) {
          pw.Widget cell(int j) => j < batch.length
              ? _workerCard(batch[j], _letter(i + j), _weekStart)
              : pw.SizedBox();

          return pw.Column(children: [
            pw.Container(
              width: double.infinity,
              decoration: pw.BoxDecoration(
                color: PdfColors.blueGrey800,
                border: pw.Border.all(
                    color: PdfColors.blueGrey800, width: 1),
              ),
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 12, vertical: 7),
              child: pw.Center(
                  child: pw.Text(
                      'INDIVIDUAL WORKER WEEKLY BREAKDOWN',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 12,
                          color: PdfColors.white))),
            ),
            pw.SizedBox(height: 8),
            pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(child: cell(0)),
                  pw.SizedBox(width: 8),
                  pw.Expanded(child: cell(1)),
                ]),
            pw.SizedBox(height: 8),
            pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(child: cell(2)),
                  pw.SizedBox(width: 8),
                  pw.Expanded(child: cell(3)),
                ]),
            pw.Spacer(),
            pw.Row(
                mainAxisAlignment:
                    pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                      'Date generated: ${fmtFull.format(DateTime.now())}',
                      style: const pw.TextStyle(
                          fontSize: 7,
                          color: PdfColors.grey500)),
                  pw.Text('Page $pageNum',
                      style: const pw.TextStyle(
                          fontSize: 7,
                          color: PdfColors.grey500)),
                ]),
          ]);
        },
      ));
    }

    return pdf.save();
  }

  pw.Widget _workerCard(
      _MilkmanDetail detail, String letter, DateTime weekStart) {
    final s = detail.summary;
    final hasKhoya = s.totalKhoyaKg > 0;
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    const dayNames = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final fmtDate = DateFormat('dd MMM');

    pw.Widget tc(String text,
            {bool bold = false,
            double fs = 7,
            pw.TextAlign align = pw.TextAlign.left,
            PdfColor? color}) =>
        pw.Padding(
          padding:
              const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          child: pw.Text(text,
              textAlign: align,
              style: pw.TextStyle(
                  fontWeight:
                      bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                  fontSize: fs,
                  color: color)),
        );

    return pw.Container(
      decoration: pw.BoxDecoration(
          border:
              pw.Border.all(color: PdfColors.blueGrey300, width: 0.8)),
      child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Worker name header
            pw.Container(
              color: PdfColors.blueGrey100,
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6, vertical: 4),
              child: pw.SizedBox(
                width: double.infinity,
                child: pw.Text(
                    '$letter.  ${s.milkmanName.toUpperCase()}',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 9)),
              ),
            ),

            // Daily table
            pw.Table(
              border: pw.TableBorder.all(
                  color: PdfColors.blueGrey200, width: 0.4),
              columnWidths: {
                0: const pw.FixedColumnWidth(24),
                1: const pw.FixedColumnWidth(36),
                2: const pw.FlexColumnWidth(1),
                if (hasKhoya) 3: const pw.FlexColumnWidth(1),
              },
              children: [
                // Header row
                pw.TableRow(
                  decoration:
                      const pw.BoxDecoration(color: PdfColors.blueGrey50),
                  children: [
                    tc('DAY', bold: true),
                    tc('DATE', bold: true),
                    tc('MILK\n(Kg)', bold: true,
                        align: pw.TextAlign.right),
                    if (hasKhoya)
                      tc('KHOYA\n(Kg)', bold: true,
                          align: pw.TextAlign.right),
                  ],
                ),
                // One row per day
                for (var d = 0; d < 7; d++)
                  pw.TableRow(children: [
                    tc(dayNames[d]),
                    tc(fmtDate.format(days[d])),
                    tc(
                      _dayVal(detail.milkByDay, days[d]),
                      align: pw.TextAlign.right,
                    ),
                    if (hasKhoya)
                      tc(
                        _dayVal(detail.khoyaByDay, days[d]),
                        align: pw.TextAlign.right,
                      ),
                  ]),
                // Weekly total row
                pw.TableRow(
                  decoration:
                      const pw.BoxDecoration(color: PdfColors.blueGrey50),
                  children: [
                    tc(''),
                    tc('Total', bold: true),
                    tc(s.totalMilkKg.toStringAsFixed(1),
                        bold: true, align: pw.TextAlign.right),
                    if (hasKhoya)
                      tc(s.totalKhoyaKg.toStringAsFixed(1),
                          bold: true, align: pw.TextAlign.right),
                  ],
                ),
              ],
            ),

            // Summary rows
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(5, 4, 5, 2),
              child: pw.Column(children: [
                _wRow('TOTAL WAGES EARNED',
                    _c(s.totalEarnings)),
                _wRow('TOTAL LOANS TAKEN',
                    _c(s.thisWeekLoans + s.carriedOverLoan)),
                _wRow('LOAN DEDUCTION (THIS WEEK)',
                    _c(s.totalLoanDeducted)),
                _wRow('NET PAYMENT', _c(s.netPayable),
                    bold: true,
                    valueColor: PdfColors.green800),
              ]),
            ),

            // Signature
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(5, 6, 5, 5),
              child: pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                    crossAxisAlignment:
                        pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(
                          width: 65,
                          height: 0.5,
                          color: PdfColors.black),
                      pw.SizedBox(height: 2),
                      pw.Text("Worker's Signature",
                          style:
                              const pw.TextStyle(fontSize: 7)),
                    ]),
              ),
            ),
          ]),
    );
  }

  // ─── PDF helpers ─────────────────────────────────────────────────────────

  String _letter(int index) => String.fromCharCode(65 + index);

  String _c(double amount) => DateHelpers.formatCurrency(amount);

  String _dayVal(Map<DateTime, double> map, DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    final v = map[key] ?? 0;
    return v > 0 ? v.toStringAsFixed(1) : '-';
  }

  pw.TableRow _tHeader(List<String> labels) => pw.TableRow(
        decoration:
            const pw.BoxDecoration(color: PdfColors.blueGrey100),
        children: labels
            .map((l) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6, vertical: 4),
                  child: pw.Text(l,
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 9)),
                ))
            .toList(),
      );

  pw.TableRow _tRow(String label, String value,
      {PdfColor? valueColor}) =>
      pw.TableRow(children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(
              horizontal: 6, vertical: 4),
          child: pw.Text(label,
              style: const pw.TextStyle(fontSize: 9)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(
              horizontal: 6, vertical: 4),
          child: pw.Text(value,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                  fontSize: 9, color: valueColor)),
        ),
      ]);

  pw.TableRow _tRowHighlight(String label, String value) =>
      pw.TableRow(
        decoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFE8F5E9)),
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(
                horizontal: 6, vertical: 5),
            child: pw.Text(label,
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 9)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(
                horizontal: 6, vertical: 5),
            child: pw.Text(value,
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 9,
                    color: PdfColors.green800)),
          ),
        ],
      );

  pw.Widget _wRow(String label, String value,
      {bool bold = false, PdfColor? valueColor}) =>
      pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label,
                style: pw.TextStyle(
                    fontSize: 7,
                    fontWeight: bold
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal)),
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: 7,
                    fontWeight: bold
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                    color: valueColor)),
          ]);

  // ─── Excel export ─────────────────────────────────────────────────────────

  Future<void> _exportExcel() async {
    final excelFile = xl.Excel.createExcel();
    final sheet = excelFile[
        'Week ${DateFormat('dd-MM-yyyy').format(_weekStart)}'];

    final headers = [
      'Milkman',
      'Milk kg',
      'Milk Rate',
      'Milk Earnings',
      'Khoya kg',
      'Khoya Rate',
      'Khoya Earnings',
      'Total Earnings',
      'This Week Loans',
      'Carried Over',
      'Total Deducted',
      'Net Payable',
      'Carry Forward',
    ];
    for (var i = 0; i < headers.length; i++) {
      sheet
          .cell(xl.CellIndex.indexByColumnRow(
              columnIndex: i, rowIndex: 0))
          .value = xl.TextCellValue(headers[i]);
    }
    for (var r = 0; r < _summaries.length; r++) {
      final s = _summaries[r];
      final row = [
        s.milkmanName,
        s.totalMilkKg,
        s.milkRate,
        s.milkEarnings,
        s.totalKhoyaKg,
        s.khoyaRate,
        s.khoyaEarnings,
        s.totalEarnings,
        s.thisWeekLoans,
        s.carriedOverLoan,
        s.totalLoanDeducted,
        s.netPayable,
        s.loanCarryForward,
      ];
      for (var c = 0; c < row.length; c++) {
        final v = row[c];
        sheet
            .cell(xl.CellIndex.indexByColumnRow(
                columnIndex: c, rowIndex: r + 1))
            .value = v is String
            ? xl.TextCellValue(v)
            : xl.DoubleCellValue(v as double);
      }
    }

    final bytes = excelFile.save();
    if (bytes == null) return;

    final filename =
        'payment_${DateFormat('dd-MM-yyyy').format(_weekStart)}.xlsx';

    if (kIsWeb) {
      await Printing.sharePdf(
          bytes: Uint8List.fromList(bytes), filename: filename);
    } else {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$filename');
        await file.writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Saved: ${file.path}')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Export failed: $e'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}

// ─── Data class ──────────────────────────────────────────────────────────────

class _MilkmanDetail {
  final WeeklyPaymentSummary summary;
  final Map<DateTime, double> milkByDay;
  final Map<DateTime, double> khoyaByDay;

  _MilkmanDetail({
    required this.summary,
    required this.milkByDay,
    required this.khoyaByDay,
  });
}

// ─── UI Widgets ──────────────────────────────────────────────────────────────

class _PayCard extends StatelessWidget {
  final WeeklyPaymentSummary summary;
  final DateTime weekStart;
  final VoidCallback onMarkPaid;
  final VoidCallback onPrint;

  const _PayCard({
    required this.summary,
    required this.weekStart,
    required this.onMarkPaid,
    required this.onPrint,
  });

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: AppTheme.primary.withOpacity(0.12),
              child: Text(s.milkmanName[0],
                  style: const TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Text(s.milkmanName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16))),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined,
                  color: AppTheme.primary),
              tooltip: 'Print slip',
              onPressed: onPrint,
            ),
          ]),
          const Divider(height: 20),
          _Row(
              'Milk',
              '${s.totalMilkKg.toStringAsFixed(2)} kg × ${s.milkRate.toStringAsFixed(2)}',
              DateHelpers.formatCurrency(s.milkEarnings)),
          if (s.totalKhoyaKg > 0)
            _Row(
                'Khoya',
                '${s.totalKhoyaKg.toStringAsFixed(2)} kg × ${s.khoyaRate.toStringAsFixed(2)}',
                DateHelpers.formatCurrency(s.khoyaEarnings)),
          const SizedBox(height: 4),
          _Row('Total Earnings', '',
              DateHelpers.formatCurrency(s.totalEarnings),
              bold: true),
          if (s.carriedOverLoan > 0)
            _DeductRow('Carried Over Loan', s.carriedOverLoan),
          if (s.thisWeekLoans > 0)
            _DeductRow('This Week Loans', s.thisWeekLoans),
          const Divider(),
          Row(children: [
            const Expanded(
                child: Text('NET PAYABLE',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15))),
            Text(DateHelpers.formatCurrency(s.netPayable),
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: AppTheme.success)),
          ]),
          if (s.loanCarryForward > 0)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(Icons.arrow_forward,
                    size: 14, color: AppTheme.warning),
                const SizedBox(width: 6),
                Text(
                    'Carry forward: ${DateHelpers.formatCurrency(s.loanCarryForward)}',
                    style: TextStyle(
                        color: AppTheme.warning, fontSize: 12)),
              ]),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onMarkPaid,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Mark as Paid'),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String sub;
  final String value;
  final bool bold;
  const _Row(this.label, this.sub, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Text(label,
            style: TextStyle(
                fontWeight:
                    bold ? FontWeight.w600 : FontWeight.normal,
                color: Colors.grey[800])),
        if (sub.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(sub,
              style: TextStyle(
                  fontSize: 12, color: Colors.grey[500])),
        ],
        const Spacer(),
        Text(value,
            style: TextStyle(
                fontWeight:
                    bold ? FontWeight.w600 : FontWeight.normal)),
      ]),
    );
  }
}

class _DeductRow extends StatelessWidget {
  final String label;
  final double amount;
  const _DeductRow(this.label, this.amount);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Icon(Icons.remove_circle_outline,
            size: 14, color: Colors.red[400]),
        const SizedBox(width: 6),
        Expanded(
            child: Text(label,
                style: TextStyle(
                    color: Colors.grey[700], fontSize: 13))),
        Text('- ${DateHelpers.formatCurrency(amount)}',
            style: TextStyle(
                color: Colors.red[500], fontSize: 13)),
      ]),
    );
  }
}
