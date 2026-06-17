// lib/services/user_auth_service.dart
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage user authentication state
/// Stores user ID + basic profile locally after login
class UserAuthService {
  static const String _userIdKey = 'userId';
  static const String _userEmailKey = 'userEmail';
  static const String _userDisplayNameKey = 'userDisplayName';
  static const String _endpointArnKey = 'endpointArn';
  static const String _deviceTokenKey = 'deviceToken';
  static const String _lastRegisteredTokenKey = 'lastRegisteredToken';
  static const String _lastDeviceRegisterAtKey = 'lastDeviceRegisterAt';

  /// Get the current user ID
  /// Returns empty string if no user is logged in
  static Future<String> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIdKey) ?? '';
  }

  /// Save user ID after successful login
  static Future<void> saveUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userIdKey, userId);
  }

  /// Get the current user email
  static Future<String> getCurrentUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userEmailKey) ?? '';
  }

  /// Save user email after successful login
  static Future<void> saveUserEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userEmailKey, email);
  }

  /// Get the current user display name
  static Future<String> getCurrentUserDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userDisplayNameKey) ?? '';
  }

  /// Save user display name after successful login
  static Future<void> saveUserDisplayName(String displayName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userDisplayNameKey, displayName);
  }

  /// Save complete user info after login
  static Future<void> saveUserInfo({
    required String userId,
    required String email,
    String? displayName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userIdKey, userId);
    await prefs.setString(_userEmailKey, email);

    // Don’t overwrite with null
    if (displayName != null && displayName.trim().isNotEmpty) {
      await prefs.setString(_userDisplayNameKey, displayName.trim());
    }
  }

  /// Check if a user is currently logged in
  static Future<bool> isLoggedIn() async {
    final userId = await getCurrentUserId();
    return userId.isNotEmpty;
  }

  /// Save the SNS endpoint ARN returned by backend when registering device
  static Future<void> saveEndpointArn(String endpointArn) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_endpointArnKey, endpointArn);
  }

  /// Get stored SNS endpoint ARN
  static Future<String> getEndpointArn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_endpointArnKey) ?? '';
  }

  /// Clear stored endpoint ARN
  static Future<void> clearEndpointArn() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_endpointArnKey);
  }

  /// Save the platform device token (APNS/FCM)
  static Future<void> saveDeviceToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceTokenKey, token);
  }

  /// Get stored device token
  static Future<String> getDeviceToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_deviceTokenKey) ?? '';
  }

  /// Clear stored device token
  static Future<void> clearDeviceToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deviceTokenKey);
  }

  /// Save the last device token that was successfully registered with backend
  static Future<void> saveLastRegisteredToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastRegisteredTokenKey, token);
  }

  /// Get the last device token that was registered with backend
  /// Returns empty string if none saved
  static Future<String> getLastRegisteredToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastRegisteredTokenKey) ?? '';
  }

  /// Save the timestamp when we last registered the device with backend
  static Future<void> saveLastDeviceRegisterAt(DateTime at) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastDeviceRegisterAtKey, at.toIso8601String());
  }

  /// Get the timestamp when we last registered the device with backend
  /// Returns null if no timestamp saved or parse fails
  static Future<DateTime?> getLastDeviceRegisterAt() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_lastDeviceRegisterAtKey);
    if (s == null || s.isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  /// Clear user data on logout
  ///
  /// ✅ IMPORTANT:
  /// Also clears deviceToken so next login re-registers the device (prevents "token unchanged" skip).
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_userDisplayNameKey);
    await prefs.remove(_endpointArnKey);
    await prefs.remove(_deviceTokenKey);
    await prefs.remove(_lastRegisteredTokenKey);
    await prefs.remove(_lastDeviceRegisterAtKey);
  }

  /// Optional convenience: clears everything this service owns
  static Future<void> clearAll() async {
    await logout();
  }

  /// Get all user info as a map
  static Future<Map<String, String>> getUserInfo() async {
    return {
      'userId': await getCurrentUserId(),
      'email': await getCurrentUserEmail(),
      'displayName': await getCurrentUserDisplayName(),
    };
  }
}
