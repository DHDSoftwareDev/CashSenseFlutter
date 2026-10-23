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

  void _navigateFromDrawer(int index) {
    setState(() {
      _currentIndex = index;
    });
    Navigator.of(context).pop();
  }

  Widget _drawerItem({
    required BuildContext context,
    required int index,
    required IconData icon,
    required String title,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _currentIndex == index;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: selected
            ? colorScheme.primaryContainer.withValues(alpha: 0.65)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.12)
                  : colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              icon,
              size: 21,
              color: selected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? colorScheme.primary
                  : colorScheme.onSurface,
            ),
          ),
          trailing: selected
              ? Icon(
                  Icons.check_rounded,
                  size: 20,
                  color: colorScheme.primary,
                )
              : null,
          onTap: () => _navigateFromDrawer(index),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      key: rootScaffoldKey,
      drawer: Drawer(
        backgroundColor: colorScheme.surfaceContainerLowest,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(
            right: Radius.circular(22),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  20,
                  MediaQuery.of(context).padding.top + 20,
                  20,
                  22,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: const BorderRadius.only(
                    bottomRight: Radius.circular(22),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colorScheme.onPrimary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.account_balance_wallet_outlined,
                        color: colorScheme.onPrimary,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CashSense',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  color: colorScheme.onPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Manage your finances',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: colorScheme.onPrimary
                                      .withValues(alpha: 0.82),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 7),
                      child: Text(
                        'NAVIGATION',
                        style:
                            Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                      ),
                    ),

                    _drawerItem(
                      context: context,
                      index: 0,
                      icon: Icons.dashboard_outlined,
                      title: 'Dashboard',
                    ),

                    _drawerItem(
                      context: context,
                      index: 4,
                      icon: Icons.account_balance_outlined,
                      title: 'Accounts',
                    ),

                    // Transactions intentionally remains excluded from the
                    // drawer. It is still available through the app UI and
                    // navigateToPage().
                    _drawerItem(
                      context: context,
                      index: 5,
                      icon: Icons.people_outline_rounded,
                      title: 'Payees / Payers',
                    ),

                    _drawerItem(
                      context: context,
                      index: 2,
                      icon: Icons.category_outlined,
                      title: 'Categories',
                    ),

                    _drawerItem(
                      context: context,
                      index: 3,
                      icon: Icons.analytics_outlined,
                      title: 'Reports',
                    ),

                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      child: Divider(height: 1),
                    ),

                    _drawerItem(
                      context: context,
                      index: 6,
                      icon: Icons.settings_outlined,
                      title: 'Settings',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
    );
  }

  // Allows external callers (via a GlobalKey) to request navigation into
  // one of the root indexed pages. If [accountId] is provided and the
  // target page is the Transactions index (1), it will pass the accountId
  // to that screen by rebuilding the _screens list entry.
  void navigateToPage(
    int index, {
    String? accountId,
    DateTime? selectedDate,
  }) {
    setState(() {
      _currentIndex = index;

      if (index == 0 && selectedDate != null) {
        _screens[0] =
            DashboardScreen(initialSelectedDate: selectedDate);
      }

      if (index == 1) {
        // Replace the TransactionsScreen instance so it receives
        // the accountId.
        _screens[1] =
            TransactionsScreen(accountId: accountId);
      }
    });
  }
}
