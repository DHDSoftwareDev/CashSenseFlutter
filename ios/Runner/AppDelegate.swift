#if canImport(UIKit)
import UIKit
import Flutter
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var notificationChannel: FlutterMethodChannel?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // Set UNUserNotificationCenter delegate for handling notifications
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
      
      // Request authorization for notifications
      let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
      UNUserNotificationCenter.current().requestAuthorization(
        options: authOptions,
        completionHandler: { granted, error in
          if let error = error {
            print("❌ Error requesting notification authorization: \(error)")
          } else {
            print("✅ Notification authorization granted: \(granted)")
          }
        }
      )
    }
    
    GeneratedPluginRegistrant.register(with: self)
    
    // Set up method channel for APNS token communication
    if let controller = window?.rootViewController as? FlutterViewController {
      notificationChannel = FlutterMethodChannel(
        name: "com.dhdsoftware.cashsense/notifications",
        binaryMessenger: controller.binaryMessenger
      )
      
      notificationChannel?.setMethodCallHandler { [weak self] (call, result) in
        if call.method == "getAPNSToken" {
          let token = UserDefaults.standard.string(forKey: "apns_device_token")
          result(token)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
    
    // Register for remote notifications (APNS)
    application.registerForRemoteNotifications()
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // Handle notification when app is in foreground
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Show notification even when app is in foreground
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }
  
  // Handle notification tap
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    completionHandler()
  }
  
  // Handle remote notification registration - APNS token for AWS SNS
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    // Convert token to hex string for AWS SNS
    let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
    let token = tokenParts.joined()
    print("✅ APNS Device Token: \(token)")
    
    // Store token in UserDefaults to be accessed by Flutter
    UserDefaults.standard.set(token, forKey: "apns_device_token")
    
    // Send token to Flutter via MethodChannel
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.dhdsoftware.cashsense/notifications",
        binaryMessenger: controller.binaryMessenger
      )
      channel.invokeMethod("onAPNSToken", arguments: token)
    }
  }
  
  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("Failed to register for remote notifications: \(error)")
  }
  
  // Background fetch handling removed — handled on Flutter side now
}
#endif
