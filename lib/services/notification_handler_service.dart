import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class NotificationHandlerService {
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
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Handling foreground message: ${message.messageId}');
      debugPrint('Title: ${message.notification?.title}');
      debugPrint('Body: ${message.notification?.body}');
      
      // TODO: Show a local notification or update UI
      // Example: show a snackbar or update app state
    });

    // 3. Message opened handler (when user taps notification)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('User tapped notification: ${message.messageId}');
      debugPrint('Title: ${message.notification?.title}');
      debugPrint('Body: ${message.notification?.body}');
      
      // TODO: Navigate to appropriate screen based on notification data
      // Example: navigate to bill detail screen, transaction screen, etc.
    });

    // 4. Initial message handler (app opened from notification)
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('App opened from notification: ${initialMessage.messageId}');
      // TODO: Handle initial message when app is launched from notification
    }

    // Optional: Configure foreground notification presentation options
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }
}
