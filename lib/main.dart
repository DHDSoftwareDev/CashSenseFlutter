// ignore_for_file: depend_on_referenced_packages, unused_import, unused_element

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
// import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_api/amplify_api.dart';
import 'amplifyconfiguration.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/database_service.dart';
import 'services/auto_backup_service.dart';
import 'services/bill_reminder_service.dart';
import 'services/push_token_service.dart';
import 'timezone_init.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'services/cognito_service.dart';
// Auth screens temporarily hidden
import 'utils/root_scaffold.dart';
import 'theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'providers/theme_provider.dart';

void main() async {
 WidgetsFlutterBinding.ensureInitialized();
  await TimezoneInit.ensureInitialized();
  // Load environment variables (block: required for backend config)
  await dotenv.load(fileName: ".env");

  // Initialize database with error handling BEFORE services that depend on it
  await _initDatabase();

  // Run one-time upgrade migrations when build number increases
  try {
    await runUpgradeMigrations();
  } catch (e) {
    debugPrint('runUpgradeMigrations failed: $e');
  }

  // Initialize Firebase early so Firebase-dependent services can use it
  try {
    await Firebase.initializeApp();
    debugPrint('✅ Firebase initialized');
  } catch (e) {
    debugPrint('⚠️ Firebase.initializeApp() failed: $e');
  }

  // Initialize AWS Amplify with Cognito (required for auth)
  await _configureAmplify();

  // Decide initial home: show auth screens at startup when enabled and user not signed in
  final bool enableAuthUI = DatabaseService.getSetting<bool>('enableAuthUI', true) ?? true;
  bool isSignedIn = false;
  try {
    isSignedIn = await CognitoService.isSignedIn();
  } catch (_) {
    isSignedIn = false;
  }

  final Widget initialHome = (enableAuthUI && !isSignedIn) ? const LoginScreen() : MainNavigationScreen(key: mainNavKey);

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: CashSenseApp(initialHome: initialHome),
    ),
  );

  // Kick off non-critical initializations after first frame so UI can render fast.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _startDeferredInits(isSignedIn);
  });

  // Remove splash screen after app is ready
  // FlutterNativeSplash.remove();
}

Future<void> _startDeferredInits(bool isSignedIn) async {
  await Future.wait([
    BillReminderService().init().catchError((e) {
      debugPrint('BillReminderService.init failed: $e');
      return null;
    }),
    // Initialize Google Mobile Ads
    MobileAds.instance.initialize(),
    // Initialize automatic backup/background tasks
    AutoBackupService.initialize().catchError((e) {
      debugPrint('AutoBackupService.initialize failed: $e');
      return null;
    }),
    if (isSignedIn)
      _registerDeviceEveryLaunch().catchError((e) {
        debugPrint('Register device failed: $e');
        return null;
      }),
  ]);
}

Future<void> _initDatabase() async {
  try {
    await DatabaseService.init();
  } catch (e) {
    // If there's a Hive error (e.g., unknown typeId), clear all boxes and reinitialize
    debugPrint('Database initialization error: $e');
    debugPrint('Clearing corrupted database...');

    await Hive.initFlutter();
    await Hive.deleteBoxFromDisk('transactions');
    await Hive.deleteBoxFromDisk('categories');
    await Hive.deleteBoxFromDisk('accounts');
    await Hive.deleteBoxFromDisk('bills');
    await Hive.deleteBoxFromDisk('settings');

    // Retry initialization
    await DatabaseService.init();
  }
}

Future<void> _configureAmplify() async {
  try {
    // Add plugins
    await Amplify.addPlugins([
      AmplifyAuthCognito(),
      AmplifyAPI(),
    ]);

    // Configure Amplify using generated configuration
    await Amplify.configure(amplifyconfig);
    safePrint('Successfully configured Amplify 🎉');
  } on AmplifyAlreadyConfiguredException {
    debugPrint('⚠️ Amplify was already configured');
  } on Exception catch (e) {
    safePrint('Error configuring Amplify: $e');
  }
}

class CashSenseApp extends StatelessWidget {
  final Widget initialHome;

  const CashSenseApp({super.key, required this.initialHome});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(builder: (context, themeProvider, _) {
      return MaterialApp(
        navigatorKey: navigatorKey,
        title: 'CashSense',
        theme: AppTheme.lightThemeFor(themeProvider.primaryColor),
        darkTheme: AppTheme.darkThemeFor(themeProvider.primaryColor),
        themeMode: themeProvider.themeMode,
        home: initialHome,
        debugShowCheckedModeBanner: false,
      );
    });
  }
}

/// Decides initial screen based on whether the user is logged in.
// SplashDecider removed — auth screens hidden temporarily

/// Run one-time migrations after database init when app build changes.
Future<void> runUpgradeMigrations() async {
  final info = await PackageInfo.fromPlatform();
  final currentBuild = int.tryParse(info.buildNumber) ?? 0;

  final lastBuild = DatabaseService.getSetting<int>('lastBuild', 0) ?? 0;

  if (currentBuild > lastBuild) {
    // Ensure auth UI is not accidentally disabled from prior builds
    await DatabaseService.setSetting('enableAuthUI', true);

    // (Optional) If a specific settings box or key is masking UI, reset that here.
    // Example: await DatabaseService.setSetting('someOtherFlag', null);

    await DatabaseService.setSetting('lastBuild', currentBuild);
    debugPrint('Ran upgrade migrations: lastBuild -> $currentBuild');
  }
}

Future<void> _registerDeviceAfterUpgradeIfNeeded() async {
  final bool notifEnabled = DatabaseService.getSetting<bool>('notif_billReminders', false) ?? false;
  if (!notifEnabled) return;

  final info = await PackageInfo.fromPlatform();
  final currentBuild = int.tryParse(info.buildNumber) ?? 0;
  final lastRegisteredBuild = DatabaseService.getSetting<int>('lastDeviceRegisterBuild', 0) ?? 0;
  if (currentBuild <= lastRegisteredBuild) return;

  await PushTokenService.registerDeviceOnLogin();
  PushTokenService.initTokenRefreshListener();
  await DatabaseService.setSetting('lastDeviceRegisterBuild', currentBuild);
}

/// Register device on every app launch (if notifications enabled).
Future<void> _registerDeviceEveryLaunch() async {
  final bool notifEnabled = DatabaseService.getSetting<bool>('notif_billReminders', false) ?? false;
  if (!notifEnabled) return;

  await PushTokenService.registerDeviceOnLogin();
  PushTokenService.initTokenRefreshListener();
}
