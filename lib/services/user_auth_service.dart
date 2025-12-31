// lib/services/user_auth_service.dart
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage user authentication state without Firebase
/// Stores user ID locally after login
class UserAuthService {
  static const String _userIdKey = 'userId';
  static const String _userEmailKey = 'userEmail';
  static const String _userDisplayNameKey = 'userDisplayName';
  static const String _endpointArnKey = 'endpointArn';
  static const String _deviceTokenKey = 'deviceToken';

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
    if (displayName != null) {
      await prefs.setString(_userDisplayNameKey, displayName);
    }
  }

  /// Check if a user is currently logged in
  static Future<bool> isLoggedIn() async {
    final userId = await getCurrentUserId();
    return userId.isNotEmpty;
  }

  /// Clear user data on logout
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_userDisplayNameKey);
    await prefs.remove(_endpointArnKey);
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

  /// Save the platform device token (APNS/FCM equivalent)
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

  /// Get all user info as a map
  static Future<Map<String, String>> getUserInfo() async {
    return {
      'userId': await getCurrentUserId(),
      'email': await getCurrentUserEmail(),
      'displayName': await getCurrentUserDisplayName(),
    };
  }
}
