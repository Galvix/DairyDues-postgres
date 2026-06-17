// lib/screens/daily_entry/daily_entry_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../database/models.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/payment_calculator.dart';

class DailyEntryScreen extends StatefulWidget {
  const DailyEntryScreen({super.key});

  @override
  State<DailyEntryScreen> createState() => _DailyEntryScreenState();
}

class _DailyEntryScreenState extends State<DailyEntryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final sel = provider.selectedDate;
    final dateOnly = DateTime(sel.year, sel.month, sel.day);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Entry'),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: sel,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (picked != null) provider.setSelectedDate(picked);
            },
            icon: const Icon(Icons.calendar_today, color: Colors.white, size: 16),
            label: Text(DateFormat('dd MMM').format(sel),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: AppTheme.secondary,
          tabs: const [
            Tab(icon: Icon(Icons.local_drink_outlined), text: 'Milk'),
            Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Khoya'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_tabController.index == 0) {
            _showAddMilk(context, dateOnly);
          } else {
            _showAddKhoya(context, dateOnly);
          }
        },
        icon: const Icon(Icons.add),
        label: Text(_tabController.index == 0 ? 'Add Milk' : 'Add Khoya'),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _MilkTab(date: dateOnly),
          _KhoyaTab(date: dateOnly),
        ],
      ),
    );
  }

  void _showAddMilk(BuildContext context, DateTime date) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      // FIX: Pass provider to modal via ChangeNotifierProvider.value
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AppProvider>(),
        child: _AddMilkSheet(date: date),
      ),
    );
  }

  void _showAddKhoya(BuildContext context, DateTime date) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      // FIX: Pass provider to modal via ChangeNotifierProvider.value
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AppProvider>(),
        child: _AddKhoyaSheet(date: date),
      ),
    );
  }
}

// ─── MILK TAB ─────────────────────────────────────────────────────────────────

class _MilkTab extends StatelessWidget {
  final DateTime date;
  const _MilkTab({required this.date});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppProvider>().db;

    return StreamBuilder<List<MilkDelivery>>(
      stream: db.watchDeliveriesForDate(date),
      builder: (context, snap) {
        final deliveries = snap.data ?? [];
        final total = deliveries.fold<double>(0.0, (s, d) => s + d.netMilk);
        final billable = deliveries.fold<double>(0.0, (s, d) => s + d.billableMilk);
        final hasAdj = deliveries.any((d) => d.paneerAdjusted);

        return Column(children: [
          // Summary bar
          Container(
            color: AppTheme.primary.withOpacity(0.06),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              _Chip('Total: ${DateHelpers.formatWeight(total)}', Colors.blue),
              const SizedBox(width: 12),
              _Chip('Billable: ${DateHelpers.formatWeight(billable)}',
                  hasAdj ? AppTheme.warning : AppTheme.success),
              const SizedBox(width: 12),
              _Chip('${deliveries.length} entries', AppTheme.primary),
            ]),
          ),
          Expanded(
            // FIX: Use StreamBuilder for milkmen too, or load once
            child: StreamBuilder<List<Milkman>>(
              stream: db.watchActiveMilkmen(),
              builder: (context, ms) {
                final milkmenMap = {for (var m in (ms.data ?? [])) m.id: m};
                if (deliveries.isEmpty) {
                  return Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.local_drink_outlined, size: 56, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text('No milk entries', style: TextStyle(color: Colors.grey[500])),
                    ]),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  itemCount: deliveries.length,
                  itemBuilder: (context, i) {
                    final d = deliveries[i];
                    return _MilkCard(
                      delivery: d,
                      milkmanName: milkmenMap[d.milkmanId]?.name ?? '?',
                      onDelete: () => db.deleteMilkDelivery(d.id),
                    );
                  },
                );
              },
            ),
          ),
        ]);
      },
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color));
  }
}

class _MilkCard extends StatelessWidget {
  final MilkDelivery delivery;
  final String milkmanName;
  final VoidCallback onDelete;
  const _MilkCard({required this.delivery, required this.milkmanName, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppTheme.primary.withOpacity(0.12),
            child: Text(milkmanName[0],
                style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(milkmanName, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(
                'Gross: ${delivery.grossWeight.toStringAsFixed(2)}  Can: ${delivery.canWeight.toStringAsFixed(2)}  Net: ${delivery.netMilk.toStringAsFixed(2)} kg',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              if (delivery.paneerAdjusted)
                Text('Billable: ${delivery.billableMilk.toStringAsFixed(2)} kg (adjusted)',
                    style: TextStyle(fontSize: 11, color: AppTheme.warning)),
              if (delivery.notes.isNotEmpty)
                Text(delivery.notes, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ]),
          ),
          Column(children: [
            Text('${delivery.netMilk.toStringAsFixed(2)} kg',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.primary)),
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red[300], size: 20),
              onPressed: onDelete,
            ),
          ]),
        ]),
      ),
    );
  }
}

// ─── KHOYA TAB ────────────────────────────────────────────────────────────────

class _KhoyaTab extends StatelessWidget {
  final DateTime date;
  const _KhoyaTab({required this.date});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppProvider>().db;

    return StreamBuilder<List<KhoyaDelivery>>(
      stream: db.watchKhoyaForDate(date),
      builder: (context, snap) {
        final entries = snap.data ?? [];
        if (entries.isEmpty) {
          return Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.inventory_2_outlined, size: 56, color: Colors.grey[300]),
              const SizedBox(height: 12),
              Text('No khoya entries', style: TextStyle(color: Colors.grey[500])),
            ]),
          );
        }
        return StreamBuilder<List<Milkman>>(
          stream: db.watchActiveMilkmen(),
          builder: (context, ms) {
            final milkmenMap = {for (var m in (ms.data ?? [])) m.id: m};
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final k = entries[i];
                final name = milkmenMap[k.milkmanId]?.name ?? '?';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.orange.withOpacity(0.12),
                      child: Text(name[0], style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                    ),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${k.weight.toStringAsFixed(2)} kg'),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline, color: Colors.red[300], size: 20),
                      onPressed: () => db.deleteKhoyaDelivery(k.id),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

// ─── ADD MILK SHEET ──────────────────────────────────────────────────────────

class _AddMilkSheet extends StatefulWidget {
  final DateTime date;
  const _AddMilkSheet({required this.date});

  @override
  State<_AddMilkSheet> createState() => _AddMilkSheetState();
}

class _AddMilkSheetState extends State<_AddMilkSheet> {
  final _formKey = GlobalKey<FormState>();
  final _grossCtrl = TextEditingController();
  final _canCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _milkmanId;
  bool _saving = false;

  // FIX: Load milkmen once in initState instead of via FutureBuilder on every build
  List<Milkman>? _milkmen;

  double get _net {
    final g = double.tryParse(_grossCtrl.text) ?? 0;
    final c = double.tryParse(_canCtrl.text) ?? 0;
    return (g - c).clamp(0.0, double.infinity);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMilkmen());
  }

  Future<void> _loadMilkmen() async {
    final milkmen = await context.read<AppProvider>().db.getActiveMilkmen();
    if (mounted) setState(() => _milkmen = milkmen);
  }

  @override
  void dispose() {
    _grossCtrl.dispose();
    _canCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Text('Add Milk Entry',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
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
                    .map((m) => DropdownMenuItem(value: m.id, child: Text(m.name)))
                    .toList(),
                onChanged: (v) => setState(() => _milkmanId = v),
                validator: (v) => v == null ? 'Select milkman' : null,
              ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _grossCtrl,
                  decoration: const InputDecoration(labelText: 'Gross (kg)', suffixText: 'kg'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,3}'))],
                  onChanged: (_) => setState(() {}),
                  validator: (v) => double.tryParse(v ?? '') == null ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _canCtrl,
                  decoration: const InputDecoration(labelText: 'Can (kg)', suffixText: 'kg'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,3}'))],
                  onChanged: (_) => setState(() {}),
                  validator: (v) => double.tryParse(v ?? '') == null ? 'Required' : null,
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.calculate_outlined, size: 18, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text('Net Milk: ', style: TextStyle(color: Colors.grey[700])),
                Text('${_net.toStringAsFixed(3)} kg',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primary)),
              ]),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Entry'),
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
    final now = DateTime.now();
    await context.read<AppProvider>().addMilkDelivery(
          milkmanId: _milkmanId!,
          deliveryDate: DateTime(widget.date.year, widget.date.month,
              widget.date.day, now.hour, now.minute),
          grossWeight: double.parse(_grossCtrl.text),
          canWeight: double.parse(_canCtrl.text),
          notes: _notesCtrl.text,
        );
    if (mounted) Navigator.pop(context);
  }
}

class _AddKhoyaSheet extends StatefulWidget {
  final DateTime date;
  const _AddKhoyaSheet({required this.date});

  @override
  State<_AddKhoyaSheet> createState() => _AddKhoyaSheetState();
}

class _AddKhoyaSheetState extends State<_AddKhoyaSheet> {
  final _formKey = GlobalKey<FormState>();
  final _weightCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _milkmanId;
  bool _saving = false;

  // FIX: Load milkmen once
  List<Milkman>? _milkmen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMilkmen());
  }

  Future<void> _loadMilkmen() async {
    final milkmen = await context.read<AppProvider>().db.getActiveMilkmen();
    // Filter to only khoya suppliers
    if (mounted) setState(() => _milkmen = milkmen.where((m) => m.suppliesKhoya).toList());
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Text('Add Khoya Entry',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
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
                    .map((m) => DropdownMenuItem(value: m.id, child: Text(m.name)))
                    .toList(),
                onChanged: (v) => setState(() => _milkmanId = v),
                validator: (v) => v == null ? 'Select milkman' : null,
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _weightCtrl,
              decoration: const InputDecoration(labelText: 'Khoya Weight (kg)', suffixText: 'kg'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,3}'))],
              validator: (v) => double.tryParse(v ?? '') == null ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Khoya Entry'),
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
    await context.read<AppProvider>().db.addKhoyaDelivery(KhoyaDelivery(
      id: '',
      milkmanId: _milkmanId!,
      deliveryDate: widget.date,
      weight: double.parse(_weightCtrl.text),
      notes: _notesCtrl.text,
    ));
    if (mounted) Navigator.pop(context);
  }
}
