import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/main_navigation_screen.dart';
import '../services/cognito_service.dart';
import '../utils/root_scaffold.dart';

class NotificationHandlerService {
  static bool _foregroundListenerInitialized = false;
  static RemoteMessage? _pendingOpenMessage;

  /// Background message handler - runs when app is terminated or in background
  /// MUST be a top-level or static function for Firebase
  static Future<void> _firebaseBackgroundMessageHandler(
    RemoteMessage message,
  ) async {
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

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {});

      // 3. Message opened handler (when user taps notification)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _openMessage(message);
      });
    }

    // 4. Initial message handler (app opened from notification)
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _pendingOpenMessage = initialMessage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final pending = _pendingOpenMessage;
        if (pending != null) {
          _openMessage(pending);
        }
      });
    }

    // Optional: Configure foreground notification presentation options
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
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
    final type = (data['type'] ?? '').toString().trim();
    final selectedDate = _notificationDate(data);

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => MainNavigationScreen(key: mainNavKey)),
      (route) => false,
    );

    if (type == 'bill_reminder') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigateToRootPage(0, selectedDate: selectedDate);
        _pendingOpenMessage = null;
      });
      return;
    }

    _pendingOpenMessage = null;
  }

  static DateTime? _notificationDate(Map<String, dynamic> data) {
    final occurrenceDate = (data['occurrenceDate'] ?? '').toString().trim();
    if (occurrenceDate.isNotEmpty) {
      try {
        return DateTime.parse(occurrenceDate);
      } catch (_) {}
    }

    final dueDate = (data['dueDate'] ?? '').toString().trim();
    if (dueDate.isEmpty || dueDate.toLowerCase() == 'today') {
      return DateTime.now();
    }

    try {
      return DateFormat('MM/dd/yyyy').parseStrict(dueDate);
    } catch (_) {
      return null;
    }
  }
}
