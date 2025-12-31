import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';

import 'aws_service.dart';
import 'device_id_service.dart';
import 'user_auth_service.dart';

/// Handles push registration for APNS/FCM and keeps the backend in sync when
/// the device token refreshes.
class PushRegistrationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final AWSService _awsService = AWSService();

  bool _listeningForRefresh = false;

  Future<void> initAndRegister({
    required String userId,
    void Function(String token)? onToken,
  }) async {
    // 1) Permissions (iOS)
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    // 2) Get token
    final token = await _messaging.getToken();
    if (token == null || token.isEmpty) return;
    onToken?.call(token);

    // Persist token locally so future runs can detect changes
    final storedToken = await UserAuthService.getDeviceToken();
    if (storedToken != token) {
      await UserAuthService.saveDeviceToken(token);
      await UserAuthService.clearEndpointArn(); // ensure backend updates
    }

    // 3) Stable deviceId
    final deviceId = await DeviceIdService.getOrCreate();

    // 4) Send to backend
    final endpointArn = await _registerWithBackend(
      userId: userId,
      token: token,
      deviceId: deviceId,
    );
    if (endpointArn != null && endpointArn.isNotEmpty) {
      await UserAuthService.saveEndpointArn(endpointArn);
    }

    // 5) Listen for token refresh and re-register
    if (!_listeningForRefresh) {
      _listeningForRefresh = true;
      _messaging.onTokenRefresh.listen((newToken) async {
        onToken?.call(newToken);
        await UserAuthService.saveDeviceToken(newToken);
        await UserAuthService.clearEndpointArn();

        final refreshedDeviceId = await DeviceIdService.getOrCreate();
        final refreshedArn = await _registerWithBackend(
          userId: userId,
          token: newToken,
          deviceId: refreshedDeviceId,
        );
        if (refreshedArn != null && refreshedArn.isNotEmpty) {
          await UserAuthService.saveEndpointArn(refreshedArn);
        }
      });
    }
  }

  Future<String?> _registerWithBackend({
    required String userId,
    required String token,
    required String deviceId,
  }) async {
    final platform = Platform.isIOS ? 'ios' : 'android';
    final apnsEnv = Platform.isIOS ? AWSService.currentApnsEnv() : null;

    return _awsService.registerDevice(
      userId: userId,
      deviceToken: token,
      platform: platform,
      deviceId: deviceId,
      apnsEnv: apnsEnv,
    );
  }
}
