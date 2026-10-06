// ignore_for_file: depend_on_referenced_packages, unused_import, unused_element

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
// import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_api/amplify_api.dart';
import 'package:amplify_storage_s3/amplify_storage_s3.dart';
import 'amplifyconfiguration.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/database_service.dart';
import 'services/auto_backup_service.dart';
import 'services/bill_reminder_service.dart';
import 'services/push_token_service.dart';
import 'services/biometric_auth_service.dart';
import 'services/remote_sync_service.dart';
import 'timezone_init.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'services/cognito_service.dart';
import 'services/aws_api_service.dart';
import 'services/user_api_service.dart';
import 'services/lookups_api.dart';
import 'services/lookups_repository.dart';
import 'services/lookups_local_store.dart';
import 'services/lookups_state.dart';
import 'services/notification_handler_service.dart';
import 'services/home_screen_widget_service.dart';
import 'widgets/app_system_insets.dart';
// Auth screens temporarily hidden
import 'utils/root_scaffold.dart';
import 'theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'providers/theme_provider.dart';
import 'providers/user_session_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await _safeInitStep(
    'Timezone initialization',
    () => TimezoneInit.ensureInitialized(),
  );
  // Load environment variables (block: required for backend config)
  await _safeInitStep('Load .env', () => dotenv.load(fileName: ".env"));

  // Initialize database with error handling BEFORE services that depend on it
  await _initDatabase();

  // Run one-time upgrade migrations when build number increases
  await _safeInitStep('Run upgrade migrations', () => runUpgradeMigrations());

  // Initialize Firebase early so Firebase-dependent services can use it
  await _safeInitStep('Firebase initialization', () async {
    await Firebase.initializeApp();
    debugPrint('✅ Firebase initialized');
    // Initialize Firebase message handlers right after Firebase is set up
    await NotificationHandlerService.initializeMessageHandlers();
    debugPrint('✅ Notification handlers initialized');
  });

  // Initialize AWS Amplify with Cognito (required for auth)
  await _safeInitStep(
    'Amplify configuration',
    () => _configureAmplify(),
    timeout: const Duration(seconds: 12),
  );

  // Decide initial home: show auth screens at startup when enabled and user not signed in
  final bool enableAuthUI =
      DatabaseService.getSetting<bool>('enableAuthUI', true) ?? true;
  final bool isSignedIn =
      await _safeInitValue<bool>(
        'Check Cognito sign-in',
        () => CognitoService.isSignedIn(),
        timeout: const Duration(seconds: 8),
      ) ??
      false;

  final shouldShowLogin = enableAuthUI && !isSignedIn;
  final Widget initialHome = shouldShowLogin
      ? const LoginScreen()
      : MainNavigationScreen(key: mainNavKey);
  final userSession = UserSessionController(
    api: CashSenseUserApi(baseUrl: AwsApiService.baseUrl),
  );
  final lookupsState = LookupsState(
    LookupsRepository(
      api: LookupsApi(
        baseUrl: AwsApiService.baseUrl,
        authHeadersBuilder: () async {
          final token = await AwsApiService.getIdToken();
          final headers = <String, String>{};
          if (token.isNotEmpty) {
            headers['Authorization'] = 'Bearer $token';
          }
          return headers;
        },
      ),
      localStore: SettingsLookupsLocalStore(),
    ),
  );

  // Local-first: hydrate lookups before first frame when already authenticated.
  if (isSignedIn) {
    await _safeInitStep(
      'Load local lookups',
      () => lookupsState.loadFromLocal(),
    );
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<UserSessionController>.value(value: userSession),
        ChangeNotifierProvider<LookupsState>.value(value: lookupsState),
      ],
      child: CashSenseApp(initialHome: initialHome),
    ),
  );

  unawaited(HomeScreenWidgetService.initialize());

  // Kick off non-critical initializations after first frame so UI can render fast.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _startDeferredInits(isSignedIn, userSession, lookupsState);
  });

  // Remove splash screen after app is ready
  // FlutterNativeSplash.remove();
}

Future<void> _safeInitStep(
  String label,
  Future<void> Function() step, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  try {
    await step().timeout(timeout);
  } on TimeoutException {
    debugPrint('⚠️ Startup step timed out: $label');
  } catch (e) {
    debugPrint('⚠️ Startup step failed ($label): $e');
  }
}

Future<T?> _safeInitValue<T>(
  String label,
  Future<T> Function() step, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  try {
    return await step().timeout(timeout);
  } on TimeoutException {
    debugPrint('⚠️ Startup step timed out: $label');
  } catch (e) {
    debugPrint('⚠️ Startup step failed ($label): $e');
  }
  return null;
}

Future<void> _startDeferredInits(
  bool isSignedIn,
  UserSessionController userSession,
  LookupsState lookupsState,
) async {
  await Future.wait([
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
    if (isSignedIn)
      _refreshCurrentUserSession(userSession).catchError((e) {
        debugPrint('Refresh current user session failed: $e');
        return null;
      }),
  ]);

  // Sequence remote sync before lookups sync so subscription plan refresh has
  // happened; otherwise lookups can be skipped as "Free" on one device.
  if (isSignedIn) {
    try {
      await RemoteSyncService.syncUserDataOnLogin();
    } catch (e) {
      debugPrint('Remote data sync failed: $e');
    }

    await lookupsState.syncRemote().catchError((e) {
      debugPrint('Lookup sync failed: $e');
      return null;
    });
  }
}

Future<void> _refreshCurrentUserSession(
  UserSessionController userSession,
) async {
  final idToken = await AwsApiService.getIdToken();
  if (idToken.isEmpty) return;
  await userSession.refreshUser(idToken: idToken);
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
    await Hive.deleteBoxFromDisk('bill_occurrence_status');
    await Hive.deleteBoxFromDisk('settings');

    // Retry initialization
    await DatabaseService.init();
  }
}

Future<void> _configureAmplify() async {
  try {
    final bucketRaw = (dotenv.env['S3_BUCKET'] ?? '').trim();
    final bucket = _normalizeBucketName(bucketRaw);
    final region =
        (dotenv.env['AWS_REGION'] ?? dotenv.env['COGNITO_REGION'] ?? '').trim();
    final identityPoolId = (dotenv.env['COGNITO_IDENTITY_POOL_ID'] ?? '')
        .trim();
    final storageEnabled = bucket.isNotEmpty && region.isNotEmpty;

    final List<AmplifyPluginInterface> plugins = [
      AmplifyAuthCognito(),
      AmplifyAPI(),
      if (storageEnabled) AmplifyStorageS3(),
    ];

    await Amplify.addPlugins(plugins);

    final config = storageEnabled
        ? _withStorageConfig(
            amplifyconfig,
            bucket: bucket,
            region: region,
            identityPoolId: identityPoolId,
          )
        : amplifyconfig;

    await Amplify.configure(config);
    safePrint('Successfully configured Amplify 🎉');
  } on AmplifyAlreadyConfiguredException {
    debugPrint('⚠️ Amplify was already configured');
  } on Exception catch (e) {
    safePrint('Error configuring Amplify: $e');
  }
}

String _withStorageConfig(
  String baseConfig, {
  required String bucket,
  required String region,
  String identityPoolId = '',
}) {
  final decoded = jsonDecode(baseConfig) as Map<String, dynamic>;

  if (identityPoolId.isNotEmpty) {
    final auth =
        (decoded['auth'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final plugins =
        (auth['plugins'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final cognito =
        (plugins['awsCognitoAuthPlugin'] as Map<String, dynamic>?) ??
        <String, dynamic>{};

    cognito['CognitoIdentity'] = {
      'Default': {'PoolId': identityPoolId, 'Region': region},
    };

    plugins['awsCognitoAuthPlugin'] = cognito;
    auth['plugins'] = plugins;
    decoded['auth'] = auth;
  }

  decoded['storage'] = {
    'plugins': {
      'awsS3StoragePlugin': {'bucket': bucket, 'region': region},
    },
  };
  return jsonEncode(decoded);
}

String _normalizeBucketName(String value) {
  final v = value.trim();
  if (v.isEmpty) return '';
  if (v.startsWith('arn:aws:s3:::')) {
    return v.substring('arn:aws:s3:::'.length);
  }
  if (v.startsWith('s3://')) {
    final withoutScheme = v.substring('s3://'.length);
    final slash = withoutScheme.indexOf('/');
    return slash == -1 ? withoutScheme : withoutScheme.substring(0, slash);
  }
  return v;
}

class CashSenseApp extends StatelessWidget {
  final Widget initialHome;

  const CashSenseApp({super.key, required this.initialHome});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'CashSense',
          theme: AppTheme.lightThemeFor(themeProvider.primaryColor),
          darkTheme: AppTheme.darkThemeFor(themeProvider.primaryColor),
          themeMode: themeProvider.themeMode,
          builder: (context, child) =>
              AppSystemInsets(child: child ?? const SizedBox.shrink()),
          home: AppLifecycleBiometricLock(child: initialHome),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

class AppLifecycleBiometricLock extends StatefulWidget {
  final Widget child;

  const AppLifecycleBiometricLock({super.key, required this.child});

  @override
  State<AppLifecycleBiometricLock> createState() =>
      _AppLifecycleBiometricLockState();
}

class _AppLifecycleBiometricLockState extends State<AppLifecycleBiometricLock>
    with WidgetsBindingObserver {
  bool _isAuthenticating = false;
  bool _showBiometricLockOverlay = false;
  bool _isStartupAuthCheckPending = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _authenticateOnAppOpen().timeout(const Duration(seconds: 10));
      } on TimeoutException {
        debugPrint(
          '⚠️ Biometric startup auth timed out; continuing app startup',
        );
      } catch (e) {
        debugPrint('⚠️ Biometric startup auth failed: $e');
      }
      if (!mounted) return;
      setState(() {
        _isStartupAuthCheckPending = false;
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      PushTokenService.resetBadgeCount();
      unawaited(HomeScreenWidgetService.syncNow());
    }
  }

  Future<void> _authenticateOnResume() async {
    if (_isAuthenticating) return;
    _isAuthenticating = true;

    try {
      final biometricEnabled = await BiometricAuthService.isBiometricEnabled();
      if (!biometricEnabled) {
        if (mounted && _showBiometricLockOverlay) {
          setState(() {
            _showBiometricLockOverlay = false;
          });
        }
        return;
      }

      final signedIn = await CognitoService.isSignedIn();
      if (!signedIn) {
        if (mounted && _showBiometricLockOverlay) {
          setState(() {
            _showBiometricLockOverlay = false;
          });
        }
        return;
      }

      if (mounted && !_showBiometricLockOverlay) {
        setState(() {
          _showBiometricLockOverlay = true;
        });
      }

      final canUseBiometrics = await BiometricAuthService.canUseBiometrics();
      if (!canUseBiometrics) {
        await BiometricAuthService.setBiometricEnabled(false);
        if (mounted && _showBiometricLockOverlay) {
          setState(() {
            _showBiometricLockOverlay = false;
          });
        }
        return;
      }

      final unlocked = await BiometricAuthService.authenticate(
        reason: 'Authenticate to continue using CashSense',
      );

      if (!mounted) return;

      if (unlocked) {
        if (_showBiometricLockOverlay) {
          setState(() {
            _showBiometricLockOverlay = false;
          });
        }
      } else {
        setState(() {
          _showBiometricLockOverlay = true;
        });
      }
    } catch (e) {
      debugPrint('Biometric lock on resume failed: $e');
    } finally {
      _isAuthenticating = false;
    }
  }

  Future<void> _authenticateOnAppOpen() async {
    await _authenticateOnResume();
  }

  Future<void> _unlockFromOverlay() async {
    if (_isAuthenticating) return;
    await _authenticateOnResume();
  }

  @override
  Widget build(BuildContext context) {
    if (_isStartupAuthCheckPending) {
      return Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/cash_icon.png',
                    width: 72,
                    height: 72,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'CashSense is locked',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Checking biometric authentication…',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  const CircularProgressIndicator(),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        widget.child,
        if (_showBiometricLockOverlay)
          Positioned.fill(
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          'CashSense is locked',
                          style: Theme.of(context).textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Authenticate with biometrics to continue.',
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _unlockFromOverlay,
                            icon: const Icon(Icons.fingerprint),
                            label: const Text('Unlock'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () {
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (_) => const LoginScreen(),
                                ),
                                (route) => false,
                              );
                            },
                            child: const Text('Use Username & Password'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
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
  final bool notifEnabled =
      DatabaseService.getSetting<bool>('notif_billReminders', false) ?? false;
  if (!notifEnabled) return;

  final info = await PackageInfo.fromPlatform();
  final currentBuild = int.tryParse(info.buildNumber) ?? 0;
  final lastRegisteredBuild =
      DatabaseService.getSetting<int>('lastDeviceRegisterBuild', 0) ?? 0;
  if (currentBuild <= lastRegisteredBuild) return;

  await PushTokenService.registerDeviceOnLogin();
  PushTokenService.initTokenRefreshListener();
  await DatabaseService.setSetting('lastDeviceRegisterBuild', currentBuild);
}

/// Register device on every app launch (if notifications enabled).
Future<void> _registerDeviceEveryLaunch() async {
  final bool notifEnabled =
      DatabaseService.getSetting<bool>('notif_billReminders', false) ?? false;
  if (!notifEnabled) return;

  await PushTokenService.registerDeviceOnLogin();
  PushTokenService.initTokenRefreshListener();
}
