// lib/services/cognito_service.dart
// ignore_for_file: dead_code, unnecessary_import, unused_import, unused_element

import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'user_auth_service.dart';
import 'push_token_service.dart';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

/// Service to handle AWS Cognito authentication
class CognitoService {
  /// Sign up a new user with Cognito
  static Future<SignUpResult> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final userAttributes = <AuthUserAttributeKey, String>{
        AuthUserAttributeKey.email: email,
        AuthUserAttributeKey.name: displayName,
      };

      final result = await Amplify.Auth.signUp(
        username: email,
        password: password,
        options: SignUpOptions(userAttributes: userAttributes),
      );

      return result;
    } on AuthException catch (e) {
      safePrint('Error signing up user: ${e.message}');
      rethrow;
    }
  }

  /// Confirm sign up with verification code
  static Future<SignUpResult> confirmSignUp({
    required String email,
    required String confirmationCode,
  }) async {
    try {
      final result = await Amplify.Auth.confirmSignUp(
        username: email,
        confirmationCode: confirmationCode,
      );
      return result;
    } on AuthException catch (e) {
      safePrint('Error confirming sign up: ${e.message}');
      rethrow;
    }
  }

  /// Resend confirmation code
  static Future<void> resendConfirmationCode(String email) async {
    try {
      await Amplify.Auth.resendSignUpCode(username: email);
    } on AuthException catch (e) {
      safePrint('Error resending code: ${e.message}');
      rethrow;
    }
  }

  /// Sign in with email and password
  static Future<SignInResult> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final result = await Amplify.Auth.signIn(
        username: email,
        password: password,
      );

      // If sign in successful, sync with local storage
      if (result.isSignedIn) {
        await _syncUserToLocal();
        // Register device for push notifications after login
        try {
          await PushTokenService.registerDeviceOnLogin();
        } catch (e) {
          debugPrint('Device registration failed: $e');
        }
      }

      return result;
    } on AuthException catch (e) {
      safePrint('Error signing in: ${e.message}');
      rethrow;
    }
  }

  /// Sign out the current user
  static Future<void> signOut() async {
    try {
      await Amplify.Auth.signOut();
      // Clear local storage
      await UserAuthService.logout();
    } on AuthException catch (e) {
      safePrint('Error signing out: ${e.message}');
      rethrow;
    }
  }

  

  static String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final rnd = Random.secure();
    return List.generate(length, (_) => charset[rnd.nextInt(charset.length)]).join();
  }

  static String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
  /// Check if user is currently signed in
  static Future<bool> isSignedIn() async {
    try {
      final session = await Amplify.Auth.fetchAuthSession();
      return session.isSignedIn;
    } on AuthException catch (e) {
      safePrint('Error checking auth status: ${e.message}');
      return false;
    }
  }

  /// Get current user attributes
  static Future<Map<String, String>> getCurrentUserAttributes() async {
    try {
      final user = await Amplify.Auth.getCurrentUser();
      final attributes = await Amplify.Auth.fetchUserAttributes();

      final Map<String, String> attributeMap = {};
      for (final attribute in attributes) {
        attributeMap[attribute.userAttributeKey.key] = attribute.value;
      }

      attributeMap['userId'] = user.userId;
      attributeMap['username'] = user.username;

      return attributeMap;
    } on AuthException catch (e) {
      safePrint('Error fetching user attributes: ${e.message}');
      rethrow;
    }
  }

  /// Sync Cognito user info to local storage
  static Future<void> _syncUserToLocal() async {
    try {
      final attributes = await getCurrentUserAttributes();
      
      await UserAuthService.saveUserInfo(
        userId: attributes['userId'] ?? '',
        email: attributes['email'] ?? '',
        displayName: attributes['name'] ?? attributes['username'] ?? '',
      );
    } catch (e) {
      safePrint('Error syncing user to local storage: $e');
    }
  }

  /// Reset password - send reset code
  static Future<void> resetPassword(String email) async {
    try {
      await Amplify.Auth.resetPassword(username: email);
    } on AuthException catch (e) {
      safePrint('Error resetting password: ${e.message}');
      rethrow;
    }
  }

  /// Confirm password reset with code and new password
  static Future<void> confirmResetPassword({
    required String email,
    required String newPassword,
    required String confirmationCode,
  }) async {
    try {
      await Amplify.Auth.confirmResetPassword(
        username: email,
        newPassword: newPassword,
        confirmationCode: confirmationCode,
      );
    } on AuthException catch (e) {
      safePrint('Error confirming password reset: ${e.message}');
      rethrow;
    }
  }

  /// Change password for signed-in user
  static Future<void> updatePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      await Amplify.Auth.updatePassword(
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
    } on AuthException catch (e) {
      safePrint('Error updating password: ${e.message}');
      rethrow;
    }
  }

  /// Update user attributes such as `email` and `name`.
  /// Pass a map of attributeName -> value. Supported keys: 'email', 'name', 'preferred_username'.
  static Future<void> updateUserAttributes(Map<String, String> attributes) async {
    try {
      for (final entry in attributes.entries) {
        final key = entry.key;
        final value = entry.value;
        AuthUserAttributeKey attrKey;
        if (key == 'email') {
          attrKey = AuthUserAttributeKey.email;
        } else if (key == 'name') {
          attrKey = AuthUserAttributeKey.name;
        } else if (key == 'preferred_username') {
          attrKey = AuthUserAttributeKey.preferredUsername;
        } else {
          // Unsupported custom attribute keys are ignored in this helper.
          // Only common attributes are supported here for simplicity.
          safePrint('Skipping unsupported attribute key: $key');
          continue;
        }

        // Amplify Flutter expects the attribute key and value separately.
        await Amplify.Auth.updateUserAttribute(userAttributeKey: attrKey, value: value);
      }
    } on AuthException catch (e) {
      safePrint('Error updating user attributes: ${e.message}');
      rethrow;
    }
  }

  /// Confirm the verification code for an attribute that was updated (e.g. email).
  static Future<void> confirmAttributeVerification(String attributeName, String confirmationCode) async {
    try {
      AuthUserAttributeKey key;
      if (attributeName == 'email') {
        key = AuthUserAttributeKey.email;
      } else if (attributeName == 'phone_number') {
        key = AuthUserAttributeKey.phoneNumber;
      } else {
        throw Exception('Unsupported attribute: $attributeName');
      }

      // Use dynamic dispatch to avoid SDK static signature mismatches across versions.
      await (Amplify.Auth as dynamic).confirmUpdateUserAttribute(userAttributeKey: key, confirmationCode: confirmationCode);
    } on AuthException catch (e) {
      safePrint('Error confirming attribute verification: ${e.message}');
      rethrow;
    }
  }

  /// Delete user account
  static Future<void> deleteUser() async {
    try {
      await Amplify.Auth.deleteUser();
      // Clear local storage
      await UserAuthService.logout();
    } on AuthException catch (e) {
      safePrint('Error deleting user: ${e.message}');
      rethrow;
    }
  }

  /// Get user-friendly error message
  static String getErrorMessage(AuthException exception) {
    final message = exception.message.toLowerCase();
    
    if (message.contains('user not found') || message.contains('user does not exist')) {
      return 'No account found with this email.';
    } else if (message.contains('incorrect') || message.contains('not authorized')) {
      return 'Incorrect email or password.';
    } else if (message.contains('not confirmed') || message.contains('confirmation')) {
      return 'Please verify your email first.';
    } else if (message.contains('code mismatch') || message.contains('invalid code')) {
      return 'Invalid verification code.';
    } else if (message.contains('expired')) {
      return 'Verification code has expired.';
    } else if (message.contains('password') && (message.contains('invalid') || message.contains('requirement'))) {
      return 'Password does not meet requirements (min 8 characters).';
    } else if (message.contains('already exists') || message.contains('username exists')) {
      return 'An account with this email already exists.';
    } else if (message.contains('limit exceeded') || message.contains('too many')) {
      return 'Too many attempts. Please try again later.';
    } else if (message.contains('network')) {
      return 'Network error. Please check your connection.';
    } else {
      return exception.message;
    }
  }
}
