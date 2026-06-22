import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_native_timezone/flutter_native_timezone.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'aws_api_service.dart';
import 'cognito_service.dart';
import 'user_api_service.dart';
import 'user_auth_service.dart';

class PushTokenService {
  static StreamSubscription<String>? _tokenRefreshSub;
  static const Duration _registrationThrottle = Duration(hours: 12);

  /// Optional native APNS token bridge (if you implemented it).
  static const MethodChannel _apnsChannel = MethodChannel(
    'com.dhdsoftware.cashsense/notifications',
  );

  // ----------------------------
  // Token capture
  // ----------------------------

  static Future<String?> _getApnsTokenFromNative() async {
    if (!Platform.isIOS) return null;
    try {
      final token = await _apnsChannel.invokeMethod<String>('getAPNSToken');
      if (token != null && token.isNotEmpty) return token;
    } catch (_) {}
    return null;
  }

  static Future<String?> _getApnsToken() async {
    if (!Platform.isIOS) return null;
    try {
      return await FirebaseMessaging.instance.getAPNSToken();
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _getFcmToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  /// Returns the token we should send to the backend.
  /// IMPORTANT:
  /// - iOS + AWS SNS (APNS) requires the APNS token (not FCM).
  /// - Android can use FCM token if your backend is built for FCM.
  static Future<String?> captureDeviceToken() async {
    if (kIsWeb) return null;

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    String? token;

    if (Platform.isIOS) {
      token = await _getApnsTokenFromNative();

      token ??= await _getApnsToken();

      // 🚫 DO NOT FALL BACK TO FCM ON IOS
      if (token == null || token.isEmpty) {
        return null;
      }
    } else {
      token = await _getFcmToken();
    }

    if (token != null && token.isNotEmpty) {
      await UserAuthService.saveDeviceToken(token);
    }

    return token;
  }

  // ----------------------------
  // Lifecycle hooks
  // ----------------------------

  static void initTokenRefreshListener() {
    if (kIsWeb) return;

    _tokenRefreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen((
      _,
    ) async {
      debugPrint('Push token refresh event received');
      await _handleTokenRefresh();
    });
  }

  /// Call this right after a successful login (and whenever user re-auths).
  /// This will register:
  /// - if token changed
  /// - OR if we haven't registered recently (throttle window)
  /// - OR if you explicitly force it (see forceRegisterNow)
  static Future<void> registerDeviceOnLogin() async {
    final token = await captureDeviceToken();
    if (token == null || token.isEmpty) return;

    if (await _shouldSkipRegistration(token)) {
      debugPrint('Skipping device registration; token already synced recently');
      return;
    }

    await _ensureLocalUserContext();

    await _registerDevice(token, reason: 'login');

    // Save registration markers
    await UserAuthService.saveLastRegisteredToken(token);
    await UserAuthService.saveLastDeviceRegisterAt(DateTime.now());
  }

  /// Hook your “Sync push notifications” button to this.
  static Future<void> forceRegisterNow() async {
    final token = await captureDeviceToken();
    if (token == null || token.isEmpty) {
      return;
    }

    await _ensureLocalUserContext();
    await _registerDevice(token, reason: 'manual_force');

    // Update markers even for manual force
    await UserAuthService.saveLastRegisteredToken(token);
    await UserAuthService.saveLastDeviceRegisterAt(DateTime.now());
  }

  static Future<void> _handleTokenRefresh() async {
    final token = await captureDeviceToken();
    if (token == null || token.isEmpty) return;

    if (await _shouldSkipRegistration(token)) {
      debugPrint(
        'Skipping push token refresh registration; token already synced recently',
      );
      return;
    }

    await _registerDevice(token, reason: 'token_refresh');

    await UserAuthService.saveLastRegisteredToken(token);
    await UserAuthService.saveLastDeviceRegisterAt(DateTime.now());
  }

  // ----------------------------
  // Backend registration
  // ----------------------------

  static Future<void> _registerDevice(
    String token, {
    required String reason,
  }) async {
    bool isSignedIn = false;
    try {
      isSignedIn = await CognitoService.isSignedIn();
    } catch (_) {
      isSignedIn = false;
    }
    if (!isSignedIn) {
      debugPrint('Skipping device registration ($reason): user not signed in');
      return;
    }

    String? timeZone;
    try {
      timeZone = await FlutterNativeTimezone.getLocalTimezone();
    } catch (_) {
      timeZone = null;
    }

    bool notificationsEnabled = false;
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      notificationsEnabled =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      notificationsEnabled = false;
    }

    String? appVersion;
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = info.version.isNotEmpty ? info.version : null;
    } catch (_) {
      appVersion = null;
    }

    final osVersion = Platform.operatingSystemVersion;

    final platform = _platformString();

    // iOS: TestFlight should be production APNS for SNS.
    // If you ever want to support sandbox builds (debug), you can set sandbox when !kReleaseMode.
    final String? environment = Platform.isIOS
        ? (kReleaseMode ? 'production' : 'sandbox')
        : null;

    // IMPORTANT: make sure your AwsApiService.registerDevice sends:
    // - Authorization header (Cognito JWT)
    // - JSON body with deviceToken, platform, timeZone, environment
    await AwsApiService.registerDevice(
      deviceToken: token,
      platform: platform,
      timeZone: timeZone,
      environment: environment, // <-- add this param in AwsApiService
      notificationsEnabled: notificationsEnabled,
      appVersion: appVersion,
      osVersion: osVersion,
    );
  }

  static String _platformString() {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'unknown';
  }

  static Future<bool> _shouldSkipRegistration(String token) async {
    final lastRegisteredToken = await UserAuthService.getLastRegisteredToken();
    if (lastRegisteredToken != token) return false;

    final lastRegisteredAt = await UserAuthService.getLastDeviceRegisterAt();
    if (lastRegisteredAt == null) return false;

    return DateTime.now().difference(lastRegisteredAt) < _registrationThrottle;
  }

  static Future<void> _ensureLocalUserContext() async {
    try {
      final currentUserId = await UserAuthService.getCurrentUserId();
      if (currentUserId.isEmpty) {
        await UserApiService.fetchCurrentUser();
      }
    } catch (_) {
      // Continue; backend should still authorize via JWT.
    }
  }
}
