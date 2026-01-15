// ignore_for_file: await_only_futures, unused_import, unnecessary_import

import 'dart:convert';
import 'dart:io';

import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_api/amplify_api.dart';
import 'package:amplify_storage_s3/amplify_storage_s3.dart';
import 'package:flutter/foundation.dart';

/// Lightweight wrapper around common Amplify operations used by the app.
class AmplifyService {
  /// Sign in with username (email) and password.
  /// Returns true when signed in successfully.
  static Future<bool> signIn(String username, String password) async {
    try {
      final result = await Amplify.Auth.signIn(username: username, password: password);
      return result.isSignedIn;
    } on AuthException catch (e) {
      debugPrint('Amplify signIn error: ${e.message}');
      return false;
    }
  }

  /// Returns the current authenticated user, or null when not signed in.
  static Future<AuthUser?> getCurrentUser() async {
    try {
      return await Amplify.Auth.getCurrentUser();
    } on AuthException catch (_) {
      return null;
    }
  }

  /// Sign out the current user.
  static Future<void> signOut() async {
    try {
      await Amplify.Auth.signOut();
    } on AuthException catch (e) {
      debugPrint('Amplify signOut error: ${e.message}');
    }
  }

  /// Perform a REST GET request using Amplify.API.
  /// Returns the raw response (may be a typed response depending on Amplify version).
  static Future<dynamic> apiGet(String path, {Map<String, String>? queryParameters}) async {
    try {
      final operation = Amplify.API.get(path, queryParameters: queryParameters);
      final response = await operation.response;
      return response;
    } on ApiException catch (e) {
      debugPrint('Amplify API GET error: ${e.message}');
      rethrow;
    }
  }

  /// Upload a local file to S3. `filePath` is the absolute path to the local file.
  /// Returns true on success.
  static Future<bool> uploadFile(String filePath, String key) async {
    try {
      final local = AWSFile.fromPath(filePath);
      await Amplify.Storage.uploadFile(localFile: local, path: StoragePath.fromString(key));
      return true;
    } on StorageException catch (e) {
      debugPrint('Amplify Storage upload error: ${e.message}');
      return false;
    }
  }

  /// Download a file from S3 to the provided local path. Returns true on success.
  static Future<bool> downloadFile(String key, String downloadPath) async {
    try {
      final local = AWSFile.fromPath(downloadPath);
      await Amplify.Storage.downloadFile(path: StoragePath.fromString(key), localFile: local);
      return true;
    } on StorageException catch (e) {
      debugPrint('Amplify Storage download error: ${e.message}');
      return false;
    }
  }
}
