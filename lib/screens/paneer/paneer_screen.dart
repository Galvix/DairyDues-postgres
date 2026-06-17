// lib/screens/paneer/paneer_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../database/models.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/payment_calculator.dart';

class PaneerScreen extends StatefulWidget {
  const PaneerScreen({super.key});

  @override
  State<PaneerScreen> createState() => _PaneerScreenState();
}

class _PaneerData {
  final List<MilkDelivery> deliveries;
  final Map<String, Milkman> milkmanMap;
  final List<PaneerEntry> paneerForDate;
  final List<PaneerEntry> recent;
  _PaneerData(this.deliveries, this.milkmanMap, this.paneerForDate, this.recent);
}

class _PaneerScreenState extends State<PaneerScreen> {
  DateTime _date = DateTime.now();
  late Future<_PaneerData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_PaneerData> _load() async {
    final db = context.read<AppProvider>().db;
    final dateOnly = DateTime(_date.year, _date.month, _date.day);
    final results = await Future.wait([
      db.getDeliveriesForDate(dateOnly),
      db.getActiveMilkmen(),
      db.getPaneerEntriesForDate(dateOnly),
      db.getRecentPaneerEntries(limit: 20),
    ]);
    final deliveries = results[0] as List<MilkDelivery>;
    final milkmen = results[1] as List<Milkman>;
    final paneerForDate = results[2] as List<PaneerEntry>;
    final recent = results[3] as List<PaneerEntry>;
    return _PaneerData(
      deliveries,
      {for (final m in milkmen) m.id: m},
      paneerForDate,
      recent,
    );
  }

  Future<void> _refresh() async {
    await context.read<AppProvider>().db.syncNow();
    final f = _load();
    setState(() => _future = f);
    await f.catchError((_) => _PaneerData([], {}, [], []));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paneer Entry'),
        actions: [
          IconButton(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh'),
          TextButton.icon(
            onPressed: () async {
              final p = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now());
              if (p != null) {
                setState(() => _date = p);
                _refresh();
              }
            },
            icon: const Icon(Icons.calendar_today, color: Colors.white, size: 16),
            label: Text(DateFormat('dd MMM').format(_date),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_PaneerData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(children: [
                const SizedBox(height: 80),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(children: [
                      const Icon(Icons.cloud_off, color: Colors.red, size: 44),
                      const SizedBox(height: 12),
                      Text('${snap.error}',
                          textAlign: TextAlign.center,
                          style:
                              const TextStyle(color: Colors.red, fontSize: 12)),
                    ]),
                  ),
                ),
              ]);
            }

            final data = snap.data!;
            final deliveries = data.deliveries;
            final milkmanMap = data.milkmanMap;
            final dateOnly = DateTime(_date.year, _date.month, _date.day);
            final totalMilk =
                deliveries.fold<double>(0.0, (s, d) => s + d.netMilk);

            final Map<String, double> milkPerMan = {};
            for (final d in deliveries) {
              milkPerMan[d.milkmanId] = (milkPerMan[d.milkmanId] ?? 0) + d.netMilk;
            }

            final paneerByMilkman = <String, PaneerEntry>{};
            for (final e in data.paneerForDate) {
              if (e.milkmanId != null) paneerByMilkman[e.milkmanId!] = e;
            }

            final doneCount = paneerByMilkman.length;
            final total = milkPerMan.length;
            final recentEntries =
                data.recent.where((e) => e.milkmanId != null).toList();

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Summary ──────────────────────────────────────
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('dd MMM yyyy').format(_date),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(height: 8),
                            Row(children: [
                              _StatusChip(
                                '${totalMilk.toStringAsFixed(1)} kg total',
                                Colors.blue,
                              ),
                              const SizedBox(width: 8),
                              _StatusChip(
                                '$doneCount / $total done',
                                doneCount == total && total > 0
                                    ? AppTheme.success
                                    : AppTheme.warning,
                              ),
                            ]),
                            const SizedBox(height: 6),
                            Text(
                              'Standard: ${provider.sampleMilkKg.toStringAsFixed(0)} kg milk → ${provider.standardPaneerKg.toStringAsFixed(2)} kg paneer',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                            ),
                          ]),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Milkman list ──────────────────────────────────
                  if (milkPerMan.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: Column(children: [
                          Icon(Icons.local_drink_outlined,
                              size: 56, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          Text('No milk entries for this date',
                              style: TextStyle(color: Colors.grey[500])),
                        ]),
                      ),
                    )
                  else ...[
                    const SectionHeader(title: 'MILKMEN'),
                    const SizedBox(height: 8),
                    ...milkPerMan.entries.map((entry) {
                      final milkman = milkmanMap[entry.key];
                      final paneerEntry = paneerByMilkman[entry.key];
                      return _MilkmanPaneerCard(
                        milkmanName: milkman?.name ?? '?',
                        netMilk: entry.value,
                        paneerEntry: paneerEntry,
                        standardPaneerKg: provider.standardPaneerKg,
                        onTap: paneerEntry == null
                            ? () => _enterPaneerFor(
                                  context,
                                  milkman?.name ?? '?',
                                  entry.key,
                                  entry.value,
                                  dateOnly,
                                )
                            : null,
                      );
                    }),
                  ],

                  const SizedBox(height: 16),
                  const SectionHeader(title: 'RECENT HISTORY'),
                  const SizedBox(height: 8),
                  if (recentEntries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('No history yet',
                          style: TextStyle(color: Colors.grey[500])),
                    )
                  else
                    Column(
                      children: recentEntries
                          .map((e) => Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: Icon(
                                    e.adjustmentApplied
                                        ? Icons.warning_amber_outlined
                                        : Icons.check_circle_outline,
                                    color: e.adjustmentApplied
                                        ? AppTheme.warning
                                        : AppTheme.success,
                                  ),
                                  title: Text(
                                    '${milkmanMap[e.milkmanId]?.name ?? e.milkmanId ?? '?'}  —  ${DateFormat('dd MMM yyyy').format(e.entryDate)}',
                                  ),
                                  subtitle: Text(
                                    'Milk: ${e.totalMilkUsed.toStringAsFixed(1)} kg  •  Sample: ${e.actualPaneer.toStringAsFixed(3)} / ${e.expectedPaneer.toStringAsFixed(2)} kg',
                                  ),
                                  trailing: e.adjustmentApplied
                                      ? Chip(
                                          label: Text('Adjusted',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: AppTheme.warning)),
                                          backgroundColor:
                                              AppTheme.warning.withOpacity(0.1),
                                        )
                                      : null,
                                ),
                              ))
                          .toList(),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _enterPaneerFor(
    BuildContext context,
    String milkmanName,
    String milkmanId,
    double netMilk,
    DateTime date,
  ) async {
    final provider = context.read<AppProvider>();
    final result = await showModalBottomSheet<PaneerValidation>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ChangeNotifierProvider.value(
        value: provider,
        child: _PaneerEntrySheet(
          milkmanName: milkmanName,
          milkmanId: milkmanId,
          netMilk: netMilk,
          date: date,
        ),
      ),
    );

    if (result != null && mounted) {
      _showResult(context, milkmanName, result);
      _refresh();
    }
  }

  void _showResult(
      BuildContext context, String milkmanName, PaneerValidation v) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(
            v.adjustmentNeeded ? Icons.warning_amber : Icons.check_circle,
            color: v.adjustmentNeeded ? AppTheme.warning : AppTheme.success,
          ),
          const SizedBox(width: 8),
          Expanded(
              child: Text(milkmanName, overflow: TextOverflow.ellipsis)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (v.adjustmentNeeded) ...[
            _ResultBanner('Milk has been reduced', AppTheme.warning),
            const SizedBox(height: 12),
            _InfoRow('Original milk',
                '${v.netMilkTotal.toStringAsFixed(2)} kg'),
            _InfoRow(
              'Adjusted milk',
              '${v.adjustedMilkTotal.toStringAsFixed(2)} kg',
              valueColor: AppTheme.warning,
            ),
            _InfoRow(
              'Reduction',
              '−${v.milkReduction.toStringAsFixed(2)} kg',
              valueColor: Colors.red[400]!,
            ),
            const Divider(height: 16),
            _InfoRow('Sample paneer',
                '${v.samplePaneerKg.toStringAsFixed(3)} kg'),
            _InfoRow('Standard',
                '${v.standardPaneerKg.toStringAsFixed(2)} kg'),
            _InfoRow('Ratio',
                '${(v.effectiveRatio * 100).toStringAsFixed(2)}%'),
          ] else ...[
            _ResultBanner('No adjustment needed', AppTheme.success),
            const SizedBox(height: 12),
            _InfoRow('Sample paneer',
                '${v.samplePaneerKg.toStringAsFixed(3)} kg'),
            _InfoRow('Standard',
                '${v.standardPaneerKg.toStringAsFixed(2)} kg'),
            _InfoRow('Net milk',
                '${v.netMilkTotal.toStringAsFixed(2)} kg (unchanged)'),
          ],
        ]),
        actions: [
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'))
        ],
      ),
    );
  }
}

// ── Milkman paneer card ──────────────────────────────────────────────────────

class _MilkmanPaneerCard extends StatelessWidget {
  final String milkmanName;
  final double netMilk;
  final PaneerEntry? paneerEntry;
  final double standardPaneerKg;
  final VoidCallback? onTap;

  const _MilkmanPaneerCard({
    required this.milkmanName,
    required this.netMilk,
    required this.paneerEntry,
    required this.standardPaneerKg,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final done = paneerEntry != null;
    final adjusted = done && paneerEntry!.adjustmentApplied;
    final avatarColor =
        done ? (adjusted ? AppTheme.warning : AppTheme.success) : AppTheme.primary;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: avatarColor.withOpacity(0.12),
              child: Text(
                milkmanName.isNotEmpty ? milkmanName[0].toUpperCase() : '?',
                style: TextStyle(
                    color: avatarColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(milkmanName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text('Net milk: ${netMilk.toStringAsFixed(2)} kg',
                        style: TextStyle(
                            color: Colors.grey[600], fontSize: 13)),
                    if (done) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Sample: ${paneerEntry!.actualPaneer.toStringAsFixed(3)} / ${standardPaneerKg.toStringAsFixed(2)} kg  •  ${(paneerEntry!.yieldRatio * 100).toStringAsFixed(2)}%',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                      if (adjusted)
                        Text(
                          'Adjusted → ${(paneerEntry!.adjustedMilkTotal ?? 0).toStringAsFixed(2)} kg',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.warning,
                              fontWeight: FontWeight.w500),
                        ),
                    ],
                  ]),
            ),
            const SizedBox(width: 8),
            if (done)
              Icon(
                adjusted ? Icons.warning_amber : Icons.check_circle,
                color: adjusted ? AppTheme.warning : AppTheme.success,
              )
            else
              Icon(Icons.chevron_right, color: Colors.grey[400]),
          ]),
        ),
      ),
    );
  }
}

// ── Paneer entry bottom sheet ────────────────────────────────────────────────

class _PaneerEntrySheet extends StatefulWidget {
  final String milkmanName;
  final String milkmanId;
  final double netMilk;
  final DateTime date;

  const _PaneerEntrySheet({
    required this.milkmanName,
    required this.milkmanId,
    required this.netMilk,
    required this.date,
  });

  @override
  State<_PaneerEntrySheet> createState() => _PaneerEntrySheetState();
}

class _PaneerEntrySheetState extends State<_PaneerEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final _sampleCtrl = TextEditingController();
  bool _saving = false;

  double? get _sample => double.tryParse(_sampleCtrl.text);

  @override
  void dispose() {
    _sampleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final standardPaneerKg = provider.standardPaneerKg;
    final sampleMilkKg = provider.sampleMilkKg;
    final sample = _sample;

    PaneerValidation? preview;
    if (sample != null) {
      preview = PaneerValidation.validate(
        netMilkTotal: widget.netMilk,
        samplePaneerKg: sample,
        standardPaneerKg: standardPaneerKg,
      );
    }

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Header
            Row(children: [
              CircleAvatar(
                backgroundColor: AppTheme.primary.withOpacity(0.12),
                child: Text(
                  widget.milkmanName.isNotEmpty
                      ? widget.milkmanName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      color: AppTheme.primary, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.milkmanName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('Net milk: ${widget.netMilk.toStringAsFixed(2)} kg',
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 13)),
                    ]),
              ),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 14),

            // Standard info
            Container(
              padding:
                  const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.science_outlined,
                    size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Standard: ${sampleMilkKg.toStringAsFixed(0)} kg milk → ${standardPaneerKg.toStringAsFixed(2)} kg paneer',
                  style: const TextStyle(fontSize: 13, color: Colors.blue),
                ),
              ]),
            ),
            const SizedBox(height: 14),

            // Input — setState here only rebuilds the sheet, not the parent
            TextFormField(
              controller: _sampleCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText:
                    'Sample Paneer (from ${sampleMilkKg.toStringAsFixed(0)} kg milk)',
                suffixText: 'kg',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,3}'))
              ],
              onChanged: (_) => setState(() {}),
              validator: (v) =>
                  double.tryParse(v ?? '') == null ? 'Enter a valid weight' : null,
            ),

            // Live preview (inside sheet only — no parent rebuild)
            if (preview != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: (preview.adjustmentNeeded
                          ? AppTheme.warning
                          : AppTheme.success)
                      .withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(
                    preview.adjustmentNeeded
                        ? Icons.warning_amber_outlined
                        : Icons.check_circle_outline,
                    color: preview.adjustmentNeeded
                        ? AppTheme.warning
                        : AppTheme.success,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      preview.adjustmentNeeded
                          ? '${widget.netMilk.toStringAsFixed(2)} → ${preview.adjustedMilkTotal.toStringAsFixed(2)} kg  (−${preview.milkReduction.toStringAsFixed(2)} kg)'
                          : 'No adjustment — milk stays ${widget.netMilk.toStringAsFixed(2)} kg',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: preview.adjustmentNeeded
                            ? AppTheme.warning
                            : AppTheme.success,
                      ),
                    ),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.check),
                label: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Apply'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final v = await context.read<AppProvider>().validateAndSavePaneerForMilkman(
          date: widget.date,
          milkmanId: widget.milkmanId,
          samplePaneerKg: double.parse(_sampleCtrl.text),
        );

    if (mounted) Navigator.pop(context, v);
  }
}

// ── Shared helpers ───────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  final String text;
  final Color color;
  const _ResultBanner(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style:
              TextStyle(color: color, fontWeight: FontWeight.bold)),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoRow(this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(
            child: Text(label,
                style: TextStyle(color: Colors.grey[600], fontSize: 13))),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w500,
                color: valueColor ?? Colors.black87,
                fontSize: 13)),
      ]),
    );
  }
}
