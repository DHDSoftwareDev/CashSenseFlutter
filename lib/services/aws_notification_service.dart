// lib/services/aws_notification_service.dart
// ignore_for_file: unnecessary_null_comparison, prefer_conditional_assignment, unused_import, unused_element

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive/hive.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'aws_service.dart';
import 'user_auth_service.dart';
import 'push_registration_service.dart';
import '../models/bill.dart';
import '../screens/bill_detail_screen.dart';
import '../utils/root_scaffold.dart';

/// AWS SNS-based notification service
/// Replaces Firebase Cloud Messaging with AWS SNS
class AWSNotificationService {
  static final AWSNotificationService _instance = AWSNotificationService._internal();
  factory AWSNotificationService() => _instance;
  AWSNotificationService._internal();

  final AWSService _awsService = AWSService();
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final PushRegistrationService _pushRegistrationService = PushRegistrationService();
  
  String? _deviceToken;
  bool _initialized = false;
  bool _didRegisterDevice = false;

  /// Initialize AWS SNS notifications
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await _initLocalNotifications();
    // Always attempt registration on app start so tokens stay fresh and get
    // sent to the backend even if the user never explicitly re-auths.
    await registerDeviceForCurrentUser(force: true);
  }

  /// Initialize local notifications for displaying received push notifications
  Future<void> _initLocalNotifications() async {
    // Android notification channel
    const androidChannel = AndroidNotificationChannel(
      'cashsense_push',
      'Push Notifications',
      description: 'Bill reminders and updates from CashSense',
      importance: Importance.high,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    // Initialize settings
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    debugPrint('✅ Local notifications initialized');
  }

  /// Ensure the device is registered for the current logged-in user.
  /// Call this after user signs in to attempt registration if the token
  /// was received earlier or to fetch it now.
  Future<void> registerDeviceForCurrentUser({bool force = false}) async {
    try {
      final isLoggedIn = await UserAuthService.isLoggedIn();
      if (!isLoggedIn) {
        debugPrint('⏭️ User not logged in, skipping push registration');
        return;
      }

      final userId = await UserAuthService.getCurrentUserId();
      await _pushRegistrationService.initAndRegister(
        userId: userId,
        onToken: (token) => _deviceToken = token,
      );
      debugPrint('✅ Push registration attempted on app start');
    } catch (e) {
      debugPrint('❌ registerDeviceForCurrentUser failed: $e');
    }
  }

  /// Get APNS token from iOS native code via MethodChannel
  Future<String?> _getAPNSTokenFromNative() async {
    try {
      final channel = const MethodChannel('com.dhdsoftware.cashsense/notifications');
      
      // Set up method call handler to receive token
      channel.setMethodCallHandler((call) async {
          if (call.method == 'onAPNSToken') {
          final token = call.arguments as String;
          // If token changed since last persisted value, clear endpointArn so backend will re-create
          final stored = await UserAuthService.getDeviceToken();
          if (stored != token) {
            debugPrint('📱 APNS token changed (or first run). Updating stored token and clearing endpointArn.');
            await UserAuthService.saveDeviceToken(token);
            await UserAuthService.clearEndpointArn();
          }

          _deviceToken = token;
          debugPrint('📱 Received APNS token from native: ${token.substring(0, 20)}...');

          // Register device with AWS SNS now that we have the token
          if (await UserAuthService.isLoggedIn()) {
            await registerOnce();
          }
        }
      });
      
      // Try to get token from UserDefaults if already registered
      final token = await channel.invokeMethod<String>('getAPNSToken');
      if (token != null && token.isNotEmpty) {
        final stored = await UserAuthService.getDeviceToken();
        if (stored != token) {
          debugPrint('📱 APNS token from native differs from stored token. Persisting and clearing endpointArn.');
          await UserAuthService.saveDeviceToken(token);
          await UserAuthService.clearEndpointArn();
        }
      }
      return token;
    } catch (e) {
      debugPrint('Error getting APNS token from native: $e');
      return null;
    }
  }

  /// Ensure the device registration runs only once in-memory. If it fails,
  /// allow retry by resetting the guard.
  Future<void> registerOnce() async {
    if (_didRegisterDevice) return;
    _didRegisterDevice = true;
    try {
      await registerDeviceForCurrentUser(force: false);
    } catch (e) {
      debugPrint('❌ registerOnce failed: $e');
      _didRegisterDevice = false; // allow retry on failure
    }
  }

  /// Handle notification tap
  void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    debugPrint('Notification tapped: $payload');

    if (payload != null && payload.startsWith('bill_')) {
      final billId = payload.replaceFirst('bill_', '');
      _navigateToBill(billId);
    }
  }

  /// Navigate to bill detail screen
  void _navigateToBill(String billId) {
    try {
      final billsBox = Hive.box<Bill>('bills');
      final bill = billsBox.get(billId);
      if (bill == null) return;

      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BillDetailScreen(bill: bill),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error navigating to bill: $e');
    }
  }

  /// Send test notification (for debugging)
  Future<void> sendTestNotification() async {
    try {
      final userId = await UserAuthService.getCurrentUserId();
      
      await _awsService.sendNotification(
        userId: userId,
        title: 'Test Notification',
        body: 'This is a test notification from CashSense',
        data: {'type': 'test'},
      );

      debugPrint('✅ Test notification sent');
    } catch (e) {
      debugPrint('❌ Failed to send test notification: $e');
    }
  }

  /// Display local notification (when app is in foreground)
  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'cashsense_push',
      'Push Notifications',
      channelDescription: 'Bill reminders and updates',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  String? get deviceToken => _deviceToken;
  bool get isInitialized => _initialized;
}
