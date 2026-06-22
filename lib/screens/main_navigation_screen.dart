import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import 'transactions_screen.dart';
import 'categories_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'accounts_screen.dart';
import 'payees_screen.dart';
import '../utils/root_scaffold.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => MainNavigationScreenState();
}

class MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  late final List<Widget> _screens = [
    const DashboardScreen(),
    const TransactionsScreen(),
    const CategoriesScreen(),
    const ReportsScreen(),
    const AccountsScreen(),
    const PayeesScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: rootScaffoldKey,
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              height: MediaQuery.of(context).padding.top + kToolbarHeight,
              color: Theme.of(context).colorScheme.primary,
            ),
            if (_currentIndex != 0)
              ListTile(
                leading: const Icon(Icons.dashboard),
                title: const Text('Dashboard'),
                onTap: () {
                  setState(() {
                    _currentIndex = 0;
                  });
                  Navigator.of(context).pop();
                },
              ),
            if (_currentIndex != 4)
              ListTile(
                leading: const Icon(Icons.account_balance),
                title: const Text('Accounts'),
                onTap: () {
                  setState(() {
                    _currentIndex = 4; // accounts index
                  });
                  Navigator.of(context).pop();
                },
              ),
            // Transactions entry removed per request - navigation to
            // transactions still available from app UI (Accounts, Dashboard, etc.)
            if (_currentIndex != 5)
              ListTile(
                leading: const Icon(Icons.people),
                title: const Text('Payees / Payers'),
                onTap: () {
                  setState(() {
                    _currentIndex = 5; // payees index
                  });
                  Navigator.of(context).pop();
                },
              ),
            if (_currentIndex != 2)
              ListTile(
                leading: const Icon(Icons.category),
                title: const Text('Categories'),
                onTap: () {
                  setState(() {
                    _currentIndex = 2;
                  });
                  Navigator.of(context).pop();
                },
              ),
            if (_currentIndex != 3)
              ListTile(
                leading: const Icon(Icons.analytics),
                title: const Text('Reports'),
                onTap: () {
                  setState(() {
                    _currentIndex = 3;
                  });
                  Navigator.of(context).pop();
                },
              ),
            if (_currentIndex != 6)
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Settings'),
                onTap: () {
                  setState(() {
                    _currentIndex = 6;
                  });
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
      body: IndexedStack(index: _currentIndex, children: _screens),
    );
  }

  // Allows external callers (via a GlobalKey) to request navigation into
  // one of the root indexed pages. If [accountId] is provided and the
  // target page is the Transactions index (1), it will pass the accountId
  // to that screen by rebuilding the _screens list entry.
  void navigateToPage(int index, {String? accountId, DateTime? selectedDate}) {
    setState(() {
      _currentIndex = index;
      if (index == 0 && selectedDate != null) {
        _screens[0] = DashboardScreen(initialSelectedDate: selectedDate);
      }
      if (index == 1) {
        // Replace the TransactionsScreen instance so it receives the accountId
        _screens[1] = TransactionsScreen(accountId: accountId);
      }
    });
  }
}
