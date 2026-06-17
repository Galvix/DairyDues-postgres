// lib/screens/dashboard/dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../database/models.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/payment_calculator.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final db = provider.db;
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('DairyDues — Dairy Manager',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text(DateFormat('EEEE, dd MMMM yyyy').format(today),
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Today's milk
            StreamBuilder<List<MilkDelivery>>(
              stream: db.watchDeliveriesForDate(todayStart),
              builder: (context, snap) {
                final deliveries = snap.data ?? [];
                final totalMilk =
                    deliveries.fold<double>(0.0, (s, d) => s + d.netMilk);
                final totalBillable =
                    deliveries.fold<double>(0.0, (s, d) => s + d.billableMilk);
                final hasAdjustment = deliveries.any((d) => d.paneerAdjusted);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: "TODAY'S MILK"),
                    Row(children: [
                      Expanded(
                        child: StatCard(
                          label: 'Total Milk',
                          value: DateHelpers.formatWeight(totalMilk),
                          icon: Icons.local_drink,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatCard(
                          label: hasAdjustment
                              ? 'Billable (Adjusted)'
                              : 'Billable',
                          value: DateHelpers.formatWeight(totalBillable),
                          icon: Icons.check_circle_outline,
                          color: hasAdjustment
                              ? AppTheme.warning
                              : AppTheme.success,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    StatCard(
                      label: 'Entries Today',
                      value:
                          '${deliveries.length} from ${deliveries.map((d) => d.milkmanId).toSet().length} milkmen',
                      icon: Icons.local_shipping_outlined,
                    ),
                  ],
                );
              },
            ),

            // Today's paneer
            StreamBuilder<List<PaneerEntry>>(
              stream: db.watchRecentPaneerEntries(limit: 1),
              builder: (context, snap) {
                final entries = snap.data ?? [];
                final todayStart2 =
                    DateTime(today.year, today.month, today.day);
                final todayEntry = entries.isNotEmpty &&
                        entries.first.entryDate.isAfter(todayStart2)
                    ? entries.first
                    : null;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: "TODAY'S PANEER"),
                    if (todayEntry == null)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.scale_outlined,
                              color: Colors.orange),
                          title: const Text('Paneer not entered yet'),
                          subtitle: const Text(
                              'Go to Paneer tab to record today\'s yield'),
                        ),
                      )
                    else ...[
                      Row(children: [
                        Expanded(
                          child: StatCard(
                            label: 'Expected',
                            value: DateHelpers.formatWeight(
                                todayEntry.expectedPaneer),
                            icon: Icons.scale,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatCard(
                            label: 'Actual',
                            value: DateHelpers.formatWeight(
                                todayEntry.actualPaneer),
                            icon: todayEntry.adjustmentApplied
                                ? Icons.warning_amber
                                : Icons.check_circle,
                            color: todayEntry.adjustmentApplied
                                ? AppTheme.warning
                                : AppTheme.success,
                          ),
                        ),
                      ]),
                      if (todayEntry.adjustmentApplied)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.warning.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: AppTheme.warning.withOpacity(0.4)),
                          ),
                          child: Row(children: [
                            Icon(Icons.info_outline,
                                color: AppTheme.warning, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Milk adjusted to ${DateHelpers.formatWeight(todayEntry.adjustedMilkTotal ?? 0)} (from ${DateHelpers.formatWeight(todayEntry.totalMilkUsed)})',
                                style: TextStyle(
                                    color: AppTheme.warning, fontSize: 13),
                              ),
                            ),
                          ]),
                        ),
                    ],
                  ],
                );
              },
            ),

            // This week
            const SectionHeader(title: 'THIS WEEK'),
            // FIX: Use a StatefulWidget that loads data once instead of
            // FutureBuilder which creates new futures on every rebuild
            _WeekSummaryCard(weekStart: DateHelpers.getWeekStart(today)),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// FIX: Converted from StatelessWidget to StatefulWidget to prevent infinite rebuilds.
// Previously, using context.watch<AppProvider>() with FutureBuilder caused:
// notifyListeners() -> rebuild -> new future -> loading forever
class _WeekSummaryCard extends StatefulWidget {
  final DateTime weekStart;
  const _WeekSummaryCard({required this.weekStart});

  @override
  State<_WeekSummaryCard> createState() => _WeekSummaryCardState();
}

class _WeekSummaryCardState extends State<_WeekSummaryCard> {
  List<WeeklyPaymentSummary>? _summaries;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(_WeekSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.weekStart != widget.weekStart) {
      _load();
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final provider = context.read<AppProvider>();
      final summaries =
          await provider.calculateWeeklyPayments(widget.weekStart);
      if (mounted)
        setState(() {
          _summaries = summaries;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Text('Error: $_error',
                style: const TextStyle(color: Colors.red, fontSize: 12)),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ]),
        ),
      );
    }

    final summaries = _summaries ?? [];
    final totalPayable =
        summaries.fold<double>(0.0, (s, x) => s + x.netPayable);
    final totalMilk = summaries.fold<double>(0.0, (s, x) => s + x.totalMilkKg);
    final totalLoans =
        summaries.fold<double>(0.0, (s, x) => s + x.totalLoanDeducted);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(DateHelpers.formatWeekRange(widget.weekStart),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
              ),
              InkWell(
                onTap: _load,
                child: Icon(Icons.refresh, size: 18, color: Colors.grey[500]),
              ),
            ]),
            const SizedBox(height: 12),
            _Row('Total Milk', DateHelpers.formatWeight(totalMilk),
                Icons.local_drink_outlined),
            _Row('Total Loans', DateHelpers.formatCurrency(totalLoans),
                Icons.account_balance_wallet_outlined,
                color: AppTheme.warning),
            const Divider(),
            _Row('Total Payable', DateHelpers.formatCurrency(totalPayable),
                Icons.payments_outlined,
                color: AppTheme.success, bold: true),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final bool bold;
  const _Row(this.label, this.value, this.icon,
      {this.color, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, size: 16, color: color ?? Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                style: TextStyle(color: Colors.grey[700], fontSize: 13))),
        Text(value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: color ?? Colors.black87,
              fontSize: bold ? 16 : 14,
            )),
      ]),
    );
  }
}
