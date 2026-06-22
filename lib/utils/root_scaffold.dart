// ignore_for_file: unused_import

import 'package:flutter/material.dart';
import '../screens/main_navigation_screen.dart';

// Global scaffold key for the app's root scaffold (MainNavigationScreen)
final GlobalKey<ScaffoldState> rootScaffoldKey = GlobalKey<ScaffoldState>();

/// Public key that references the MainNavigationScreen state so other
/// screens can request navigation (e.g. show Transactions inside the root
/// scaffold instead of pushing a new route). This keeps the root Drawer
/// visible/usable from child screens.
final GlobalKey mainNavKey = GlobalKey();

/// Global navigator key to allow navigation from outside widget context
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Helper to open the root drawer safely
void openRootDrawer() {
  try {
    rootScaffoldKey.currentState?.openDrawer();
  } catch (_) {}
}

/// Request the root navigation to switch to [index]. Optionally pass
/// [accountId] which the Transactions screen will use to filter its list.
void navigateToRootPage(
  int index, {
  String? accountId,
  DateTime? selectedDate,
}) {
  try {
    (mainNavKey.currentState as dynamic)?.navigateToPage(
      index,
      accountId: accountId,
      selectedDate: selectedDate,
    );
  } catch (_) {}
}
