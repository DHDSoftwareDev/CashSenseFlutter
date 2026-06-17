import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../screens/bill_detail_screen.dart';
import '../screens/main_navigation_screen.dart';
import '../services/cognito_service.dart';
import '../services/database_service.dart';
import '../utils/root_scaffold.dart';

class NotificationHandlerService {
  static bool _foregroundListenerInitialized = false;
  static RemoteMessage? _pendingOpenMessage;

  /// Background message handler - runs when app is terminated or in background
  /// MUST be a top-level or static function for Firebase
  static Future<void> _firebaseBackgroundMessageHandler(RemoteMessage message) async {
    debugPrint('Handling background message: ${message.messageId}');
    debugPrint('Title: ${message.notification?.title}');
    debugPrint('Body: ${message.notification?.body}');
    
    // TODO: Implement your background notification logic here
    // Examples:
    // - Save to local database
    // - Update badge count
    // - Schedule local notification
    // - Mark bill as completed if that's what the notification is about
  }

  /// Initialize all Firebase message handlers
  static Future<void> initializeMessageHandlers() async {
    // 1. Background message handler (when app is terminated/background)
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundMessageHandler);

    // 2. Foreground message handler (when app is in foreground)
    if (!_foregroundListenerInitialized) {
      _foregroundListenerInitialized = true;

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Handling foreground message: ${message.messageId}');
        debugPrint('Title: ${message.notification?.title}');
        debugPrint('Body: ${message.notification?.body}');
      });

      // 3. Message opened handler (when user taps notification)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('User tapped notification: ${message.messageId}');
        debugPrint('Title: ${message.notification?.title}');
        debugPrint('Body: ${message.notification?.body}');
        _openMessage(message);
      });
    }

    // 4. Initial message handler (app opened from notification)
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('App opened from notification: ${initialMessage.messageId}');
      _pendingOpenMessage = initialMessage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final pending = _pendingOpenMessage;
        if (pending != null) {
          _openMessage(pending);
        }
      });
    }

    // Optional: Configure foreground notification presentation options
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  static Future<void> _openMessage(RemoteMessage message) async {
    _pendingOpenMessage = message;

    try {
      final signedIn = await CognitoService.isSignedIn();
      if (!signedIn) {
        debugPrint('Skipping notification navigation; user is not signed in');
        return;
      }
    } catch (e) {
      debugPrint('Notification auth check failed: $e');
      return;
    }

    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final pending = _pendingOpenMessage;
        if (pending != null) {
          _openMessage(pending);
        }
      });
      return;
    }

    final data = message.data;
    final billId = (data['billId'] ?? '').toString().trim();
    final type = (data['type'] ?? '').toString().trim();

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => MainNavigationScreen(key: mainNavKey)),
      (route) => false,
    );

    if (type == 'bill_reminder' && billId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final bill = DatabaseService.getAllBills().cast<dynamic>().firstWhere(
          (candidate) => candidate.id == billId,
          orElse: () => null,
        );

        if (bill != null) {
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => BillDetailScreen(bill: bill),
            ),
          );
        }
        _pendingOpenMessage = null;
      });
      return;
    }

    _pendingOpenMessage = null;
  }
}
