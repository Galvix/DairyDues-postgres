// lib/screens/settings/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _sampleMilkCtrl;
  late TextEditingController _standardPaneerCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = context.read<AppProvider>();
    _sampleMilkCtrl = TextEditingController(text: p.sampleMilkKg.toString());
    _standardPaneerCtrl = TextEditingController(text: p.standardPaneerKg.toString());
  }

  @override
  void dispose() {
    _sampleMilkCtrl.dispose();
    _standardPaneerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Paneer Settings',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text('Update when milk yield changes by season',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _sampleMilkCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Sample Milk Size (kg)',
                    helperText: 'Fixed amount of milk taken as sample each day',
                    suffixText: 'kg',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _standardPaneerCtrl,
                  decoration: InputDecoration(
                    labelText: 'Standard Paneer from Sample (kg)',
                    helperText:
                        'Expected paneer from ${provider.sampleMilkKg.toStringAsFixed(0)} kg milk — e.g. 6.5 kg',
                    suffixText: 'kg',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: _saving
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save Settings'),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: Colors.blue.withOpacity(0.04),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 18),
                  SizedBox(width: 8),
                  Text('Paneer Validation Logic',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                ]),
                const SizedBox(height: 10),
                _Bullet('A sample (e.g. 24 kg) is taken from each milkman\'s milk and paneer is weighed'),
                _Bullet('Effective ratio = sample paneer ÷ standard paneer (e.g. 6.33 ÷ 6.5)'),
                _Bullet('If sample < standard → billable milk = netMilk × ratio (milk reduced)'),
                _Bullet('If sample ≥ standard → full milk billable, no change'),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.water_drop, color: AppTheme.primary),
              title: const Text('Hisaab — Dairy Manager'),
              subtitle: const Text('Version 2.0 • Firebase Edition'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final sampleMilk = double.tryParse(_sampleMilkCtrl.text);
    final standardPaneer = double.tryParse(_standardPaneerCtrl.text);

    if (sampleMilk == null || sampleMilk <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sample milk size must be greater than 0')),
      );
      return;
    }
    if (standardPaneer == null || standardPaneer <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Standard paneer must be greater than 0')),
      );
      return;
    }

    setState(() => _saving = true);
    final p = context.read<AppProvider>();
    await p.updateSampleMilkKg(sampleMilk);
    await p.updateStandardPaneerKg(standardPaneer);
    setState(() => _saving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved ✓'), backgroundColor: AppTheme.success),
      );
    }
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('• ', style: TextStyle(color: Colors.blue)),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }
}
