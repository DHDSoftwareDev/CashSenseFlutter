// ignore_for_file: deprecated_member_use

import '../services/account_operations.dart';
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/home_screen_widget_service.dart';
import '../theme/app_theme.dart';

class ThemeProvider extends ChangeNotifier {
  static const _settingKey = 'themeMode';
  static const _primaryColorKey = 'primaryColor';

  ThemeMode _themeMode = ThemeMode.system;
  Color _primaryColor = AppTheme.primaryGreen;

  ThemeProvider() {
    // Load persisted theme from settings box
    final stored = DatabaseService.getSetting<String>(_settingKey, 'system');
    _themeMode = _themeModeFromString(stored);
    // Load persisted primary color (stored as int)
    final storedColor = DatabaseService.getSetting<int>(
      _primaryColorKey,
      AppTheme.primaryGreen.value,
    );
    _primaryColor = Color(storedColor ?? AppTheme.primaryGreen.value);
  }

  ThemeMode get themeMode => _themeMode;

  Color get primaryColor => _primaryColor;

  Future<void> setThemeMode(ThemeMode mode) {
    return AccountOperations.run(() async {
    _themeMode = mode;
    await DatabaseService.setSetting(_settingKey, _themeModeToString(mode));
    notifyListeners();
      });
  }

  Future<void> setPrimaryColor(Color color) {
    return AccountOperations.run(() async {
    _primaryColor = color;
    await DatabaseService.setSetting(_primaryColorKey, color.value);
    await HomeScreenWidgetService.syncNow();
    notifyListeners();
      });
  }

  static ThemeMode _themeModeFromString(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
    }
    return ThemeMode.system;
  }

  static String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
