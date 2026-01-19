import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_native_timezone/flutter_native_timezone.dart';
import 'package:flutter/services.dart';

import 'aws_api_service.dart';
import 'cognito_service.dart';
import 'user_auth_service.dart';

class PushTokenService {
  static StreamSubscription<String>? _tokenRefreshSub;
  static const MethodChannel _apnsChannel = MethodChannel('com.dhdsoftware.cashsense/notifications');

  static Future<String?> _getApnsTokenFromNative() async {
    if (!Platform.isIOS) return null;
    try {
      final token = await _apnsChannel.invokeMethod<String>('getAPNSToken');
      if (token != null && token.isNotEmpty) return token;
    } catch (_) {
      // Fall through to other token sources.
    }
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

  static Future<String?> captureDeviceToken() async {
    if (kIsWeb) {
      // Web push setup not configured here.
      return null;
    }

    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {
      // Continue; token may still be available on Android.
    }

    String? token;
    String source = 'none';
    if (Platform.isIOS) {
      token = await _getApnsTokenFromNative();
      if (token != null && token.isNotEmpty) {
        source = 'apns_native';
      }
    }
    if (Platform.isIOS && (token == null || token.isEmpty)) {
      token = await _getApnsToken();
      if (token != null && token.isNotEmpty) {
        source = 'apns';
      }
    }
    if (token == null || token.isEmpty) {
      token = await _getFcmToken();
      if (token != null && token.isNotEmpty) {
        source = 'fcm';
      }
    }

    if (token != null && token.isNotEmpty) {
      await UserAuthService.saveDeviceToken(token);
      final suffix = token.length > 6 ? token.substring(token.length - 6) : token;
      debugPrint('Captured device token via $source (len=${token.length}, suffix=$suffix)');
    } else {
      debugPrint('Failed to capture device token (source=$source)');
    }

    return token;
  }

  static void initTokenRefreshListener() {
    if (kIsWeb) return;
    _tokenRefreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen((_) async {
      debugPrint('Push token refresh event received');
      await _handleTokenRefresh();
    });
  }

  static Future<void> registerDeviceOnLogin() async {
    try {
      final currentUserId = await UserAuthService.getCurrentUserId();
      if (currentUserId.isEmpty) {
        final attrs = await CognitoService.getCurrentUserAttributes();
        await UserAuthService.saveUserInfo(
          userId: attrs['userId'] ?? '',
          email: attrs['email'] ?? '',
          displayName: attrs['name'] ?? attrs['username'],
        );
      }
    } catch (_) {
      // Continue; device registration may still succeed if backend uses JWT.
    }

    final previousToken = await UserAuthService.getDeviceToken();
    final token = await captureDeviceToken();
    if (token == null || token.isEmpty) return;

    final shouldRegister = previousToken.isEmpty || previousToken != token;
    if (!shouldRegister) {
      debugPrint('Device token unchanged; skipping device registration');
      return;
    }

    await _registerDevice(token, reason: previousToken.isEmpty ? 'initial' : 'token_changed');
  }

  static Future<void> _handleTokenRefresh() async {
    final previousToken = await UserAuthService.getDeviceToken();
    final token = await captureDeviceToken();
    if (token == null || token.isEmpty) return;
    if (token == previousToken) {
      debugPrint('Token refresh did not change device token');
      return;
    }
    await _registerDevice(token, reason: 'token_refresh');
  }

  static Future<void> _registerDevice(String token, {required String reason}) async {
    bool isSignedIn = false;
    try {
      isSignedIn = await CognitoService.isSignedIn();
    } catch (_) {
      isSignedIn = false;
    }
    if (!isSignedIn) {
      debugPrint('Skipping device registration ($reason); user not signed in');
      return;
    }

    String? timeZone;
    try {
      timeZone = await FlutterNativeTimezone.getLocalTimezone();
    } catch (_) {
      timeZone = null;
    }

    String platform;
    if (kIsWeb) {
      platform = 'web';
    } else if (Platform.isIOS) {
      platform = 'ios';
    } else if (Platform.isAndroid) {
      platform = 'android';
    } else {
      platform = 'unknown';
    }

    debugPrint('Registering device ($reason) for platform=$platform tz=${timeZone ?? "unknown"}');
    await AwsApiService.registerDevice(
      deviceToken: token,
      platform: platform,
      timeZone: timeZone,
    );
  }
}
