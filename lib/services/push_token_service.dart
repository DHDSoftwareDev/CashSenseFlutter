import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_native_timezone/flutter_native_timezone.dart';

import 'aws_api_service.dart';
import 'cognito_service.dart';
import 'user_auth_service.dart';

class PushTokenService {
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
    if (Platform.isIOS) {
      token = await _getApnsToken();
    }
    token ??= await _getFcmToken();

    if (token != null && token.isNotEmpty) {
      await UserAuthService.saveDeviceToken(token);
    }

    return token;
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

    final token = await captureDeviceToken();
    if (token == null || token.isEmpty) return;

    String? timeZone;
    try {
      timeZone = await FlutterNativeTimezone.getLocalTimezone();
    } catch (_) {
      timeZone = null;
    }

    String? platform;
    if (kIsWeb) {
      platform = 'web';
    } else if (Platform.isIOS) {
      platform = 'ios';
    } else if (Platform.isAndroid) {
      platform = 'android';
    } else {
      platform = 'unknown';
    }

    await AwsApiService.registerDevice(
      deviceToken: token,
      platform: platform,
      timeZone: timeZone,
    );
  }
}
