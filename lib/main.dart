// ignore_for_file: depend_on_referenced_packages, unused_import

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
// import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/database_service.dart';
import 'services/auto_backup_service.dart';
import 'services/notification_service.dart';
import 'services/bill_reminder_service.dart';
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
  // Load environment variables (block: required for backend config)
  await dotenv.load(fileName: ".env");

  // Initialize database with error handling BEFORE services that depend on it
  await _initDatabase();

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
    // Initialize bill reminder permissions + scheduling
    initBillReminderNotifications(),
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
    // Configure Cognito Auth Plugin
    final auth = AmplifyAuthCognito();
    await Amplify.addPlugin(auth);

    // Ensure env vars are present
    final poolId = dotenv.env['COGNITO_USER_POOL_ID'] ?? '';
    final clientId = dotenv.env['COGNITO_CLIENT_ID'] ?? '';
    final region = dotenv.env['COGNITO_REGION'] ?? '';

    if (poolId.isEmpty || clientId.isEmpty || region.isEmpty) {
      debugPrint('❌ Cognito env vars missing: pool="$poolId", client="$clientId", region="$region"');
    }

    // Correct Amplify Cognito configuration structure
    final config = '''{
      "UserAgent": "aws-amplify-cli/2.0",
      "Version": "1.0",
      "auth": {
        "plugins": {
          "awsCognitoAuthPlugin": {
            "UserAgent": "aws-amplify-cli/0.1.0",
            "Version": "0.1.0",
            "IdentityManager": { "Default": {} },
            "CognitoUserPool": {
              "Default": {
                "PoolId": "$poolId",
                "AppClientId": "$clientId",
                "Region": "$region"
              }
            },
            "Auth": {
              "Default": {
                "authenticationFlowType": "USER_SRP_AUTH",
                "socialProviders": [],
                "usernameAttributes": ["EMAIL"],
                "signupAttributes": ["EMAIL", "NAME"],
                "passwordProtectionSettings": {
                  "passwordPolicyMinLength": 8,
                  "passwordPolicyCharacters": []
                },
                "mfaConfiguration": "OFF",
                "mfaTypes": ["SMS"],
                "verificationMechanisms": ["EMAIL"],
                "OAuth": {
                  "WebDomain": "https://cashsense-auth.auth.$region.amazoncognito.com",
                  "AppClientId": "$clientId",
                  "SignInRedirectURI": "cashesense://callback/",
                  "SignOutRedirectURI": "cashesense://signout/",
                  "Scopes": ["openid","email","profile"],
                  "ResponseType": "code"
                }
              }
            }
          }
        }
      }
    }''';

    await Amplify.configure(config);
    debugPrint('✅ Amplify configured successfully');
  } on AmplifyAlreadyConfiguredException {
    debugPrint('⚠️ Amplify was already configured');
  } catch (e) {
    debugPrint('❌ Error configuring Amplify: $e');
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
