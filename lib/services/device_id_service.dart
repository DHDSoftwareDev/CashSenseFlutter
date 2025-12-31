import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Provides a stable, hashed device identifier stored in secure storage.
class DeviceIdService {
  static const _storage = FlutterSecureStorage();
  static const _key = 'cashsense_device_id_v1';

  /// Returns a stable deviceId saved in Keychain/Keystore.
  /// - Survives app restarts.
  /// - Usually survives reinstall on iOS (Keychain) depending on settings.
  static Future<String> getOrCreate() async {
    final existing = await _storage.read(key: _key);
    if (existing != null && existing.isNotEmpty) return existing;

    final id = await _buildDeterministicId();
    await _storage.write(key: _key, value: id);
    return id;
  }

  static Future<String> _buildDeterministicId() async {
    final info = DeviceInfoPlugin();

    // Use platform identifiers that exist, then hash them (don’t send raw values)
    String raw;
    if (Platform.isIOS) {
      final ios = await info.iosInfo;
      raw = 'ios:${ios.identifierForVendor ?? ''}';
    } else if (Platform.isAndroid) {
      final android = await info.androidInfo;
      raw = 'android:${android.id}';
    } else {
      raw = 'other:${DateTime.now().millisecondsSinceEpoch}';
    }

    // Hash to normalize and avoid exposing device identifiers directly
    final bytes = utf8.encode(raw);
    final digest = sha256.convert(bytes).toString();
    return digest.substring(0, 32); // short stable id
  }
}
