// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'database/api_service.dart';
import 'providers/app_provider.dart';
import 'theme/app_theme.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/milkmen/milkmen_screen.dart';
import 'screens/daily_entry/daily_entry_screen.dart';
import 'screens/paneer/paneer_screen.dart';
import 'screens/loans/loans_screen.dart';
import 'screens/payment/payment_screen.dart';
import 'screens/settings/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load API base URL + token from the gitignored .env (see .env.example).
  await dotenv.load(fileName: '.env');

  final db = ApiService();
  final provider = AppProvider(db);
  // Settings come from the backend; if it's unreachable at launch we still open
  // the app with sensible defaults and each screen surfaces its own retry.
  try {
    await provider.loadSettings();
  } catch (_) {
    // ignored — defaults stand until the next successful settings load
  }

  runApp(
    ChangeNotifierProvider.value(
      value: provider,
      child: const DairyApp(),
    ),
  );
}

class DairyApp extends StatelessWidget {
  const DairyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hisaab — Dairy Manager',
      theme: AppTheme.theme,
      debugShowCheckedModeBanner: false,
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  final List<_NavItem> _navItems = const [
    _NavItem(icon: Icons.dashboard_outlined, label: 'Dashboard'),
    _NavItem(icon: Icons.people_outline, label: 'Milkmen'),
    _NavItem(icon: Icons.local_drink_outlined, label: 'Daily Entry'),
    _NavItem(icon: Icons.scale_outlined, label: 'Paneer'),
    _NavItem(icon: Icons.account_balance_wallet_outlined, label: 'Loans'),
    _NavItem(icon: Icons.payments_outlined, label: 'Payment'),
    _NavItem(icon: Icons.settings_outlined, label: 'Settings'),
  ];

  final List<Widget> _screens = const [
    DashboardScreen(),
    MilkmenScreen(),
    DailyEntryScreen(),
    PaneerScreen(),
    LoansScreen(),
    PaymentScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 720;

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: MediaQuery.of(context).size.width > 1100,
              selectedIndex: _selectedIndex,
              onDestinationSelected: (i) => setState(() => _selectedIndex = i),
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(children: [
                  //const Icon(Icons.water_drop, color: Colors.white, size: 32),
                  Container(
                    width: 128,
                    height: 128,
                    child: Image.asset('assets/logo.png'),
                  ),
                  const SizedBox(height: 4),
                  if (MediaQuery.of(context).size.width > 1100)
                    const Text('DairyDues',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                ]),
              ),
              destinations: _navItems
                  .map((item) => NavigationRailDestination(
                        icon: Icon(item.icon),
                        label: Text(item.label),
                      ))
                  .toList(),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _screens[_selectedIndex]),
          ],
        ),
      );
    }

    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: _navItems
            .map((item) => NavigationDestination(
                  icon: Icon(item.icon),
                  label: item.label,
                ))
            .toList(),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
