// lib/screens/loans/loans_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../database/models.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/payment_calculator.dart';

class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key});

  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen> {
  late Future<List<Milkman>> _future;
  // Bumped to make the per-milkman loan tiles reload after add/delete.
  int _reloadToken = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Milkman>> _load() =>
      context.read<AppProvider>().db.getActiveMilkmen();

  Future<void> _refresh() async {
    final f = _load();
    setState(() {
      _future = f;
      _reloadToken++;
    });
    await f.catchError((_) => <Milkman>[]);
  }

  Future<void> _addLoan() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AppProvider>(),
        child: const _AddLoanSheet(),
      ),
    );
    if (added == true) setState(() => _reloadToken++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loans')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addLoan,
        icon: const Icon(Icons.add),
        label: const Text('Record Loan'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Milkman>>(
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
            final milkmen = snap.data ?? [];
            if (milkmen.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 120),
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.people_outline, size: 56, color: Colors.grey[300]),
                  const SizedBox(height: 12),
                  Text('No milkmen found',
                      style: TextStyle(color: Colors.grey[500])),
                  const SizedBox(height: 4),
                  Text('Add milkmen first',
                      style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                ]),
              ]);
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              children: milkmen
                  .map((m) =>
                      _MilkmanLoanTile(milkman: m, reloadToken: _reloadToken))
                  .toList(),
            );
          },
        ),
      ),
    );
  }
}

class _MilkmanLoanTile extends StatefulWidget {
  final Milkman milkman;
  final int reloadToken;
  const _MilkmanLoanTile({required this.milkman, required this.reloadToken});

  @override
  State<_MilkmanLoanTile> createState() => _MilkmanLoanTileState();
}

class _MilkmanLoanTileState extends State<_MilkmanLoanTile> {
  late Future<List<Loan>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(_MilkmanLoanTile old) {
    super.didUpdateWidget(old);
    if (old.reloadToken != widget.reloadToken) {
      setState(() => _future = _load());
    }
  }

  Future<List<Loan>> _load() =>
      context.read<AppProvider>().db.getLoansForMilkman(widget.milkman.id);

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: FutureBuilder<List<Loan>>(
        future: _future,
        builder: (context, snap) {
          final loans = snap.data ?? [];
          final loading = snap.connectionState == ConnectionState.waiting;
          final weekStart = DateHelpers.getWeekStart(DateTime.now());
          final weekEnd = weekStart.add(const Duration(days: 7));
          final thisWeekTotal = loans
              .where((l) =>
                  !l.loanDate.isBefore(weekStart) &&
                  l.loanDate.isBefore(weekEnd))
              .fold<double>(0.0, (s, l) => s + l.amount);

          return ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.warning.withOpacity(0.12),
              child: Text(widget.milkman.name[0],
                  style: const TextStyle(
                      color: AppTheme.warning, fontWeight: FontWeight.bold)),
            ),
            title: Text(widget.milkman.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              snap.hasError
                  ? 'Failed to load loans'
                  : thisWeekTotal > 0
                      ? 'This week: ${DateHelpers.formatCurrency(thisWeekTotal)}'
                      : 'No loans this week',
              style: TextStyle(
                  fontSize: 12,
                  color: snap.hasError
                      ? Colors.red
                      : thisWeekTotal > 0
                          ? AppTheme.warning
                          : AppTheme.success),
            ),
            children: [
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                )
              else if (loans.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No loan records',
                      style: TextStyle(color: Colors.grey)),
                )
              else
                ...loans.map((l) => ListTile(
                      dense: true,
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                            Icons.account_balance_wallet_outlined,
                            color: AppTheme.warning,
                            size: 18),
                      ),
                      title: Text(DateHelpers.formatCurrency(l.amount),
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(DateHelpers.formatDate(l.loanDate)),
                      trailing: IconButton(
                        icon: Icon(Icons.delete_outline,
                            color: Colors.red[300], size: 20),
                        onPressed: () => _confirmDelete(context, l),
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, Loan l) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Loan?'),
        content:
            Text('Remove ${DateHelpers.formatCurrency(l.amount)} from records?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await context.read<AppProvider>().db.deleteLoan(l.id);
              if (ctx.mounted) Navigator.pop(ctx);
              _reload();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _AddLoanSheet extends StatefulWidget {
  const _AddLoanSheet();

  @override
  State<_AddLoanSheet> createState() => _AddLoanSheetState();
}

class _AddLoanSheetState extends State<_AddLoanSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _milkmanId;
  DateTime _date = DateTime.now();
  bool _saving = false;

  // FIX: Load milkmen once in initState, not via FutureBuilder on every build
  List<Milkman>? _milkmen;

  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback so context is available
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMilkmen());
  }

  Future<void> _loadMilkmen() async {
    final milkmen = await context.read<AppProvider>().db.getActiveMilkmen();
    if (mounted) setState(() => _milkmen = milkmen);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Text('Record Loan',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 12),
            if (_milkmen == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Milkman'),
                value: _milkmanId,
                items: _milkmen!
                    .map((m) =>
                        DropdownMenuItem(value: m.id, child: Text(m.name)))
                    .toList(),
                onChanged: (v) => setState(() => _milkmanId = v),
                validator: (v) => v == null ? 'Select milkman' : null,
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountCtrl,
              decoration: const InputDecoration(
                  labelText: 'Amount (₹)', prefixText: '₹ '),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
              ],
              validator: (v) =>
                  double.tryParse(v ?? '') == null ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final p = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now());
                if (p != null) setState(() => _date = p);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Date'),
                child: Row(children: [
                  Text(DateHelpers.formatDate(_date)),
                  const Spacer(),
                  const Icon(Icons.calendar_today,
                      size: 16, color: Colors.grey),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              decoration:
                  const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Save Loan'),
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
    await context.read<AppProvider>().db.addLoan(Loan(
          id: '',
          milkmanId: _milkmanId!,
          loanDate: _date,
          amount: double.parse(_amountCtrl.text),
          notes: _notesCtrl.text,
        ));
    if (mounted) Navigator.pop(context, true);
  }
}
