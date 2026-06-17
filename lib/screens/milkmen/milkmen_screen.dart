// lib/screens/milkmen/milkmen_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../database/models.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_theme.dart';

class MilkmenScreen extends StatelessWidget {
  const MilkmenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.watch<AppProvider>().db;

    return Scaffold(
      appBar: AppBar(title: const Text('Milkmen')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Milkman'),
      ),
      body: StreamBuilder<List<Milkman>>(
        stream: db.watchActiveMilkmen(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 12),
                  const Text('Firestore Error:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('${snap.error}',
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  const Text(
                    'Fix: Firebase Console → Firestore → Rules\nSet: allow read, write: if true;',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ]),
              ),
            );
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data ?? [];
          if (list.isEmpty) {
            return Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text('No milkmen added yet', style: TextStyle(color: Colors.grey[500])),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => _showDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add First Milkman'),
                ),
              ]),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            itemCount: list.length,
            itemBuilder: (context, i) => _MilkmanCard(
              milkman: list[i],
              onEdit: () => _showDialog(context, existing: list[i]),
              onDelete: () => _confirmDelete(context, list[i]),
            ),
          );
        },
      ),
    );
  }

  void _showDialog(BuildContext context, {Milkman? existing}) {
    showDialog(
      context: context,
      builder: (_) => _MilkmanDialog(existing: existing),
    );
  }

  void _confirmDelete(BuildContext context, Milkman m) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Milkman?'),
        content: Text('${m.name} will be deactivated. Records are preserved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () async {
              await context.read<AppProvider>().db.deactivateMilkman(m.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

class _MilkmanCard extends StatelessWidget {
  final Milkman milkman;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MilkmanCard({required this.milkman, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppTheme.primary.withOpacity(0.12),
          child: Text(milkman.name[0].toUpperCase(),
              style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
        ),
        title: Text(milkman.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(spacing: 8, children: [
            _Chip('Milk: ₹${milkman.milkRate.toStringAsFixed(2)}/kg', Colors.blue),
            if (milkman.suppliesKhoya)
              _Chip('Khoya: ₹${milkman.khoyaRate.toStringAsFixed(2)}/kg', Colors.orange),
          ]),
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
          IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red[400]),
              onPressed: onDelete),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    );
  }
}

class _MilkmanDialog extends StatefulWidget {
  final Milkman? existing;
  const _MilkmanDialog({this.existing});

  @override
  State<_MilkmanDialog> createState() => _MilkmanDialogState();
}

class _MilkmanDialogState extends State<_MilkmanDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _milkRateCtrl;
  late final TextEditingController _khoyaRateCtrl;
  bool _suppliesKhoya = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.existing;
    _nameCtrl = TextEditingController(text: m?.name ?? '');
    _milkRateCtrl = TextEditingController(text: m?.milkRate.toString() ?? '');
    _khoyaRateCtrl = TextEditingController(text: m?.khoyaRate.toString() ?? '');
    _suppliesKhoya = m?.suppliesKhoya ?? false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _milkRateCtrl.dispose();
    _khoyaRateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing != null ? 'Edit Milkman' : 'Add Milkman'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.words,
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _milkRateCtrl,
              decoration: const InputDecoration(labelText: 'Milk Rate (₹/kg)', prefixText: '₹ '),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
              validator: (v) => double.tryParse(v ?? '') == null ? 'Enter valid rate' : null,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Supplies Khoya'),
              value: _suppliesKhoya,
              onChanged: (v) => setState(() => _suppliesKhoya = v),
            ),
            if (_suppliesKhoya)
              TextFormField(
                controller: _khoyaRateCtrl,
                decoration: const InputDecoration(labelText: 'Khoya Rate (₹/kg)', prefixText: '₹ '),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                validator: (v) {
                  if (!_suppliesKhoya) return null;
                  return double.tryParse(v ?? '') == null ? 'Enter valid rate' : null;
                },
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(widget.existing != null ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final db = context.read<AppProvider>().db;
    final milkman = Milkman(
      id: widget.existing?.id ?? '',
      name: _nameCtrl.text.trim(),
      milkRate: double.parse(_milkRateCtrl.text),
      khoyaRate: _suppliesKhoya ? double.parse(_khoyaRateCtrl.text) : 0.0,
      suppliesKhoya: _suppliesKhoya,
    );

    if (widget.existing != null) {
      await db.updateMilkman(milkman);
    } else {
      await db.addMilkman(milkman);
    }

    if (mounted) Navigator.pop(context);
  }
}
