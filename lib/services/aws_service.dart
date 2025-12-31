// lib/services/aws_service.dart
// ignore_for_file: avoid_print

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class AWSService {
  /// Returns the current APNS environment based on build mode.
  /// Debug/profile => sandbox, Release => prod.
  static String currentApnsEnv() => kReleaseMode ? 'prod' : 'sandbox';

  // Update this URL based on your setup:
  // For local testing: 'https://d-dx8q9o5bja.execute-api.us-east-1.amazonaws.com/api'
  // For Android emulator: 'http://10.0.2.2:3000/api' // (keep for emulator local development)
  // For production: 'https://d-dx8q9o5bja.execute-api.us-east-1.amazonaws.com/api'
  static const String baseUrl = 'https://q9b8i2izx6.execute-api.us-east-1.amazonaws.com/prod';
  
  // Timeout duration
  static const Duration timeoutDuration = Duration(seconds: 30);
  
  // ============================================
  // USER OPERATIONS
  // ============================================
  
  Future<Map<String, dynamic>?> getUser(String userId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/users/$userId'))
          .timeout(timeoutDuration);
      
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('Failed to get user: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error getting user: $e');
      rethrow;
    }
  }
  
  Future<Map<String, dynamic>> createUser({
    required String userId,
    required String email,
    required String displayName,
    Map<String, dynamic>? settings,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/users'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'userId': userId,
              'email': email,
              'displayName': displayName,
              'settings': settings ?? {},
            }),
          )
          .timeout(timeoutDuration);
      
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to create user: ${response.body}');
      }
    } catch (e) {
      print('❌ Error creating user: $e');
      rethrow;
    }
  }
  
  Future<Map<String, dynamic>> updateUser(
    String userId,
    Map<String, dynamic> updates,
  ) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/users/$userId'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(updates),
          )
          .timeout(timeoutDuration);
      
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to update user: ${response.body}');
      }
    } catch (e) {
      print('❌ Error updating user: $e');
      rethrow;
    }
  }
  
  // ============================================
  // TRANSACTION OPERATIONS
  // ============================================
  
  Future<List<Map<String, dynamic>>> getTransactions(
    String userId, {
    String? accountId,
    String? from,
    String? to,
  }) async {
    try {
      final queryParams = <String, String>{
        if (accountId != null) 'accountId': accountId,
        if (from != null) 'from': from,
        if (to != null) 'to': to,
      };

      final uri = Uri.parse('$baseUrl/users/$userId/transactions').replace(queryParameters: queryParams.isEmpty ? null : queryParams);

      final response = await http.get(uri).timeout(timeoutDuration);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data);
      } else {
        throw Exception('Failed to get transactions: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error getting transactions: $e');
      rethrow;
    }
  }

  Future<void> createTransaction(
    String userId,
    Map<String, dynamic> transaction,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/users/$userId/transactions'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(transaction),
          )
          .timeout(timeoutDuration);

      if (response.statusCode != 200) {
        throw Exception('Failed to create transaction');
      }
    } catch (e) {
      print('❌ Error creating transaction: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getAccounts(String userId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/users/$userId/accounts'),
          )
          .timeout(timeoutDuration);

      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(
          json.decode(response.body),
        );
      } else {
        throw Exception('Failed to load accounts');
      }
    } catch (e) {
      print('❌ Error getting accounts: $e');
      rethrow;
    }
  }

  Future<void> createAccount(
    String userId,
    Map<String, dynamic> account,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/users/$userId/accounts'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(account),
          )
          .timeout(timeoutDuration);

      if (response.statusCode != 200) {
        throw Exception('Failed to create account');
      }
    } catch (e) {
      print('❌ Error creating account: $e');
      rethrow;
    }
  }
  
  Future<Map<String, dynamic>> createTransactionDetailed({
    required String userId,
    required double amount,
    required String category,
    required String type, // 'income' or 'expense'
    String? description,
    DateTime? date,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/users/$userId/transactions'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'amount': amount,
              'category': category,
              'type': type,
              'description': description ?? '',
              'date': (date ?? DateTime.now()).toIso8601String(),
            }),
          )
          .timeout(timeoutDuration);
      
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to create transaction: ${response.body}');
      }
    } catch (e) {
      print('❌ Error creating transaction: $e');
      rethrow;
    }
  }
  
  Future<Map<String, dynamic>> updateTransaction({
    required String userId,
    required String transactionId,
    required Map<String, dynamic> updates,
  }) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/users/$userId/transactions/$transactionId'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(updates),
          )
          .timeout(timeoutDuration);
      
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to update transaction: ${response.body}');
      }
    } catch (e) {
      print('❌ Error updating transaction: $e');
      rethrow;
    }
  }
  
  Future<bool> deleteTransaction({
    required String userId,
    required String transactionId,
  }) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/users/$userId/transactions/$transactionId'),
          )
          .timeout(timeoutDuration);
      
      return response.statusCode == 200;
    } catch (e) {
      print('❌ Error deleting transaction: $e');
      rethrow;
    }
  }
  
  // ============================================
  // BACKUP OPERATIONS
  // ============================================
  
  Future<String> createBackup(String userId) async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/users/$userId/backup'))
          .timeout(timeoutDuration);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return data['backupKey'] as String;
      } else {
        throw Exception('Failed to create backup: ${response.body}');
      }
    } catch (e) {
      print('❌ Error creating backup: $e');
      rethrow;
    }
  }
  
  Future<List<Map<String, dynamic>>> listBackups(String userId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/users/$userId/backups'))
          .timeout(timeoutDuration);
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data);
      } else {
        throw Exception('Failed to list backups: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error listing backups: $e');
      rethrow;
    }
  }
  
  Future<Map<String, dynamic>> restoreBackup(
    String userId, {
    String? backupKey,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/users/$userId/restore'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              if (backupKey != null) 'backupKey': backupKey,
            }),
          )
          .timeout(Duration(seconds: 60)); // Longer timeout for restore
      
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to restore backup: ${response.body}');
      }
    } catch (e) {
      print('❌ Error restoring backup: $e');
      rethrow;
    }
  }
  
  // ============================================
  // NOTIFICATION OPERATIONS
  // ============================================
  
  Future<String> registerDevice({
    required String userId,
    required String deviceToken,
    required String platform, // 'android' or 'ios'
    String? deviceId,
    String? apnsEnv,
  }) async {
    try {
      final resolvedApnsEnv = apnsEnv ?? currentApnsEnv();
      // Backend expects device registration at /api/users/:userId/device
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/users/$userId/device'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              // Send both keys to be compatible with backend expectations.
              // Backend currently expects `apnsToken` for iOS.
              'deviceToken': deviceToken,
              'apnsToken': deviceToken,
              'apnsEnv': resolvedApnsEnv,
              if (deviceId != null) 'deviceId': deviceId,
              'platform': platform,
            }),
          )
          .timeout(timeoutDuration);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return data['endpointArn'] as String;
      } else {
        throw Exception('Failed to register device: ${response.body}');
      }
    } catch (e) {
      print('❌ Error registering device: $e');
      rethrow;
    }
  }
  
  Future<Map<String, dynamic>> sendNotification({
    required String userId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/send-notification'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'userId': userId,
              'title': title,
              'body': body,
              'data': data ?? {},
            }),
          )
          .timeout(timeoutDuration);
      
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to send notification: ${response.body}');
      }
    } catch (e) {
      print('❌ Error sending notification: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> scheduleBillReminder({
    required String userId,
    required String billId,
    required DateTime scheduledAt,
    Map<String, dynamic>? meta,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/schedule-bill-reminder'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'userId': userId,
              'billId': billId,
              'scheduledAt': scheduledAt.toIso8601String(),
              'meta': meta ?? {},
            }),
          )
          .timeout(timeoutDuration);

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to schedule reminder: ${response.body}');
      }
    } catch (e) {
      print('❌ Error scheduling reminder: $e');
      rethrow;
    }
  }

  Future<bool> cancelReminder({
    required String userId,
    required String reminderId,
  }) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/cancel-reminder'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'userId': userId,
              'reminderId': reminderId,
            }),
          )
          .timeout(timeoutDuration);

      return response.statusCode == 200;
    } catch (e) {
      print('❌ Error cancelling reminder: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getBillPayments(
    String userId,
    String billId,
  ) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/users/$userId/bills/$billId/payments'),
          )
          .timeout(timeoutDuration);

      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(
          json.decode(response.body),
        );
      } else {
        throw Exception('Failed to load bill payments: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error getting bill payments: $e');
      rethrow;
    }
  }

  Future<void> addBillPayment(
    String userId,
    String billId,
    Map<String, dynamic> payment,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/users/$userId/bills/$billId/payments'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(payment),
          )
          .timeout(timeoutDuration);

      if (response.statusCode != 200) {
        throw Exception('Failed to add payment: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error adding bill payment: $e');
      rethrow;
    }
  }
  
  // ============================================
  // HEALTH CHECK
  // ============================================
  
  Future<bool> checkHealth() async {
    try {
      final response = await http
          .get(Uri.parse('${baseUrl.replaceAll('/api', '')}/health'))
          .timeout(Duration(seconds: 5));
      
      return response.statusCode == 200;
    } catch (e) {
      print('❌ Health check failed: $e');
      return false;
    }
  }

  // ============================================
  // BILLS
  // ============================================

  Future<List<Map<String, dynamic>>> getBills(String userId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/users/$userId/bills'))
          .timeout(timeoutDuration);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data);
      } else {
        throw Exception('Failed to get bills: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error getting bills: $e');
      rethrow;
    }
  }

  static bool _didInitializeUserData = false;

  /// Run once after login to prime local caches. Returns a map with
  /// keys: `accounts`, `bills`, `transactions`.
  Future<Map<String, List<Map<String, dynamic>>>> initializeUserDataOnce(
    String userId,
  ) async {
    if (_didInitializeUserData) {
      return {
        'accounts': [],
        'bills': [],
        'transactions': [],
      };
    }

    try {
      final accounts = await getAccounts(userId);
      final bills = await getBills(userId);
      final transactions = await getTransactions(userId);

      _didInitializeUserData = true;

      return {
        'accounts': accounts,
        'bills': bills,
        'transactions': transactions,
      };
    } catch (e) {
      // If any fetch fails, allow retry later.
      _didInitializeUserData = false;
      print('❌ Error initializing user data: $e');
      rethrow;
    }
  }
}
