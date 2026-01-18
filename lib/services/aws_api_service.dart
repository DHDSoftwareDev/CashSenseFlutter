// ignore_for_file: unused_import, unreachable_switch_default, unnecessary_null_comparison

import 'dart:convert';

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/account.dart';
import '../models/bill.dart';
import '../models/transaction.dart';
import 'cognito_service.dart';
import 'device_id_service.dart';
import 'user_auth_service.dart';

class AwsApiService {
  static String get _baseUrl => (dotenv.env['API_BASE_URL'] ?? '').trim();
  static String get baseUrl => _baseUrl;

  static Future<String> getIdToken() async {
    return _getIdToken();
  }

  static bool get isConfigured => _baseUrl.isNotEmpty;

  static String _joinPaths(String basePath, String path) {
    final cleanBase = basePath.endsWith('/') ? basePath.substring(0, basePath.length - 1) : basePath;
    final cleanPath = path.startsWith('/') ? path : '/$path';
    if (cleanBase.isEmpty) return cleanPath;
    return '$cleanBase$cleanPath';
  }

  static Uri _buildUri(String path, {Map<String, String>? queryParameters}) {
    final base = Uri.parse(_baseUrl);
    final fullPath = _joinPaths(base.path, path);
    return base.replace(path: fullPath, queryParameters: queryParameters);
  }

  static Future<String> _getIdToken() async {
    try {
      final session = await Amplify.Auth.fetchAuthSession();

      if (!session.isSignedIn) return '';

      // Best path for Amplify Auth Cognito
      if (session is CognitoAuthSession) {
        final tokensResult = session.userPoolTokensResult;

        // Some versions expose `value` as nullable.
        // Some versions may throw if you access value when it's an error.
        try {
          final tokens = tokensResult.value;
          if (tokens != null) {
            return tokens.idToken.raw;
          }
        } catch (_) {
          // ignore, we'll log error below
        }

        safePrint('userPoolTokensResult: $tokensResult');
        return '';
      }

      // Fallback: dynamic probing for older/newer shapes
      final dyn = session as dynamic;
      try {
        final t = dyn.userPoolTokens?.idToken?.raw;
        if (t is String && t.isNotEmpty) return t;
      } catch (_) {}
      try {
        final t = dyn.tokens?.idToken?.raw;
        if (t is String && t.isNotEmpty) return t;
      } catch (_) {}
    } catch (e) {
      debugPrint('Failed to fetch ID token: $e');
    }
    return '';
  }

  static Future<Map<String, String>> _buildHeaders() async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    final token = await _getIdToken();
    if (token.isEmpty) {
      throw StateError('Missing ID token. User may not be signed in yet.');
    }

    headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  static Future<http.Response> _request(
    String method,
    String path, {
    Map<String, String>? queryParameters,
    Map<String, dynamic>? body,
  }) async {
    if (!isConfigured) {
      throw StateError('AWS API base URL not configured');
    }

    // ✅ Don't make API calls if the user is not signed in
    try {
      final isSignedIn = await Amplify.Auth.fetchAuthSession().then((session) => session.isSignedIn);
      if (!isSignedIn) {
        throw StateError('User not signed in - cannot make API requests');
      }
    } catch (e) {
      debugPrint('Auth check failed: $e');
      throw StateError('Authentication required for API requests');
    }

    final uri = _buildUri(path, queryParameters: queryParameters);
    final headers = await _buildHeaders();
    final encodedBody = body == null ? null : jsonEncode(body);
    debugPrint('AWS API ${method.toUpperCase()} -> $uri');

    switch (method) {
      case 'GET':
        return http.get(uri, headers: headers);
      case 'POST':
        return http.post(uri, headers: headers, body: encodedBody);
      case 'PUT':
        return http.put(uri, headers: headers, body: encodedBody);
      case 'DELETE':
        return http.delete(uri, headers: headers, body: encodedBody);
      default:
        throw UnsupportedError('Unsupported HTTP method: $method');
    }
  }

  static void _throwIfNotOk(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw Exception('AWS API error ${response.statusCode}: ${response.body}');
  }

  static Account _accountFromItem(Map<String, dynamic> json) {
    final id = json['accountId'] ?? json['id'] ?? '';
    final name = json['name'] ?? 'Account';
    final typeRaw = (json['type'] ?? 'bank').toString();
    final type = _accountTypeFromString(typeRaw);
    final currency = json['currency'] ?? 'USD';
    final balance = (json['balance'] as num?)?.toDouble() ?? 0.0;
    final isActive = json['isActive'] ?? true;

    return Account(
      id: id.toString(),
      name: name.toString(),
      type: type,
      balance: balance,
      currency: currency.toString(),
      isActive: isActive == true,
      description: json['description']?.toString(),
      accountNumber: json['accountNumber']?.toString(),
      availableBalance: (json['availableBalance'] as num?)?.toDouble(),
      customType: json['customType']?.toString(),
    );
  }

  static Bill _billFromItem(Map<String, dynamic> json) {
    final id = json['billId'] ?? json['id'] ?? '';
    final amount = (json['amount'] as num?)?.toDouble() ?? 0.0;
    final due = _parseDate(json['dueDate']) ?? DateTime.now();
    final recurrence = _recurrenceFromString(json['frequency']?.toString());

    return Bill(
      id: id.toString(),
      amount: amount,
      description: (json['name'] ?? json['description'])?.toString(),
      dueDate: due,
      recurrence: recurrence,
      recurrenceInterval: json['recurrenceInterval'] ?? 1,
      recurrenceWeekdays: (json['recurrenceWeekdays'] as List?)?.map((e) => (e as num).toInt()).toList(),
      customDays: (json['customDays'] as List?)?.map((e) => (e as num).toInt()).toList(),
      recurrenceEndDate: _parseDate(json['recurrenceEndDate']),
      categoryId: json['categoryId']?.toString(),
      type: _billTypeFromString(json['type']?.toString()),
      payeeId: json['payeeId']?.toString(),
      accountId: json['accountId']?.toString(),
      fromAccountId: json['fromAccountId']?.toString(),
      toAccountId: json['toAccountId']?.toString(),
      isPaid: json['isPaid'] ?? false,
      paymentStatus: _paymentStatusFromString(json['paymentStatus']?.toString()),
    );
  }

  static Transaction _transactionFromItem(Map<String, dynamic> json) {
    final id = json['transactionId'] ?? json['id'] ?? '';
    final amount = (json['amount'] as num?)?.toDouble() ?? 0.0;
    final direction = (json['direction'] ?? '').toString();
    final type = direction == 'income'
        ? TransactionType.income
        : direction == 'expense'
            ? TransactionType.expense
            : (amount >= 0 ? TransactionType.income : TransactionType.expense);
    final date = _parseDate(json['transactionDate']) ?? DateTime.now();

    return Transaction(
      id: id.toString(),
      amount: amount.abs(),
      categoryId: (json['categoryId'] ?? json['category'] ?? '').toString(),
      type: type,
      description: (json['description'] ?? json['merchant'] ?? '').toString(),
      date: date,
      note: json['notes']?.toString(),
      accountId: json['accountId']?.toString(),
      billId: json['billId']?.toString(),
      payerId: json['payerId']?.toString(),
      payeeId: json['payeeId']?.toString(),
    );
  }

  // Accounts
  static Future<List<Account>> fetchAccounts() async {
    final userId = await UserAuthService.getCurrentUserId();
    final response = await _request('GET', '/accounts', queryParameters: userId.isEmpty ? null : {'userId': userId});
    _throwIfNotOk(response);
    final decoded = jsonDecode(response.body);
    if (decoded is List) {
      return decoded.map<Account>((e) => _accountFromItem(Map<String, dynamic>.from(e))).toList();
    }
    if (decoded is Map && decoded['items'] is List) {
      return (decoded['items'] as List).map<Account>((e) => _accountFromItem(Map<String, dynamic>.from(e))).toList();
    }
    return [];
  }

  static Future<void> createAccount(Account account) async {
    final userId = await UserAuthService.getCurrentUserId();
    final payload = <String, dynamic>{
      'accountId': account.id,
      'name': account.name,
      'type': _accountTypeToApi(account.type),
      'currency': account.currency,
    };
    if (userId.isNotEmpty) {
      payload['userId'] = userId;
    }
    final response = await _request('POST', '/accounts', body: payload);
    _throwIfNotOk(response);
  }

  static Future<void> updateAccount(Account account) async {
    final userId = await UserAuthService.getCurrentUserId();
    final payload = <String, dynamic>{
      'accountId': account.id,
      'name': account.name,
      'type': _accountTypeToApi(account.type),
      'currency': account.currency,
    };
    if (userId.isNotEmpty) {
      payload['userId'] = userId;
    }
    final response = await _request('PUT', '/accounts/${account.id}', body: payload);
    _throwIfNotOk(response);
  }

  static Future<void> deleteAccount(String accountId) async {
    final userId = await UserAuthService.getCurrentUserId();
    final response = await _request(
      'DELETE',
      '/accounts/$accountId',
      body: userId.isEmpty ? null : {'userId': userId, 'accountId': accountId},
    );
    _throwIfNotOk(response);
  }

  // Bills
  static Future<List<Bill>> fetchBills() async {
    final userId = await UserAuthService.getCurrentUserId();
    if (userId.isEmpty) return [];
    final response = await _request('GET', '/bills', queryParameters: {'userId': userId});
    _throwIfNotOk(response);
    final decoded = jsonDecode(response.body);
    if (decoded is List) {
      return decoded.map<Bill>((e) => _billFromItem(Map<String, dynamic>.from(e))).toList();
    }
    if (decoded is Map && decoded['items'] is List) {
      return (decoded['items'] as List).map<Bill>((e) => _billFromItem(Map<String, dynamic>.from(e))).toList();
    }
    return [];
  }

  static Future<void> createBill(Bill bill) async {
    final userId = await UserAuthService.getCurrentUserId();
    if (userId.isEmpty) {
      throw StateError('No userId available for bill creation');
    }
    final payload = _billToApiPayload(bill, userId);
    final response = await _request('POST', '/bills', body: payload);
    _throwIfNotOk(response);
  }

  static Future<void> updateBill(Bill bill) async {
    final userId = await UserAuthService.getCurrentUserId();
    if (userId.isEmpty) {
      throw StateError('No userId available for bill update');
    }
    final payload = _billToApiPayload(bill, userId);
    final response = await _request('PUT', '/bills/${bill.id}', body: payload);
    _throwIfNotOk(response);
  }

  static Future<void> deleteBill(String billId) async {
    final userId = await UserAuthService.getCurrentUserId();
    if (userId.isEmpty) {
      throw StateError('No userId available for bill delete');
    }
    final response = await _request(
      'DELETE',
      '/bills/$billId',
      body: {'userId': userId, 'billId': billId},
    );
    _throwIfNotOk(response);
  }

  // Transactions
  static Future<List<Transaction>> fetchTransactions() async {
    final userId = await UserAuthService.getCurrentUserId();
    final response = await _request('GET', '/transactions', queryParameters: userId.isEmpty ? null : {'userId': userId});
    _throwIfNotOk(response);
    final decoded = jsonDecode(response.body);
    if (decoded is List) {
      return decoded.map<Transaction>((e) => _transactionFromItem(Map<String, dynamic>.from(e))).toList();
    }
    if (decoded is Map && decoded['items'] is List) {
      return (decoded['items'] as List).map<Transaction>((e) => _transactionFromItem(Map<String, dynamic>.from(e))).toList();
    }
    return [];
  }

  static Future<void> createTransaction(Transaction transaction) async {
    final userId = await UserAuthService.getCurrentUserId();
    final payload = _transactionToApiPayload(transaction)
      ..['transactionId'] = transaction.id;
    if (userId.isNotEmpty) {
      payload['userId'] = userId;
    }
    final response = await _request('POST', '/transactions', body: payload);
    _throwIfNotOk(response);
  }

  static Future<void> updateTransaction(Transaction transaction) async {
    final userId = await UserAuthService.getCurrentUserId();
    final payload = _transactionToApiPayload(transaction)
      ..['transactionId'] = transaction.id;
    if (userId.isNotEmpty) {
      payload['userId'] = userId;
    }
    final response = await _request('PUT', '/transactions/${transaction.id}', body: payload);
    _throwIfNotOk(response);
  }

  static Future<void> deleteTransaction(String transactionId) async {
    final userId = await UserAuthService.getCurrentUserId();
    final response = await _request(
      'DELETE',
      '/transactions/$transactionId',
      body: userId.isEmpty ? null : {'userId': userId, 'transactionId': transactionId},
    );
    _throwIfNotOk(response);
  }

  // Payments
  static Future<void> createPayment(Map<String, dynamic> payload) async {
    final response = await _request('POST', '/billpayments', body: payload);
    _throwIfNotOk(response);
  }

  // Notifications
  static Future<void> registerDevice({
    required String deviceToken,
    String? platform,
    String? timeZone,
  }) async {
    final userId = await UserAuthService.getCurrentUserId();
    final deviceId = await DeviceIdService.getOrCreate();
    final payload = <String, dynamic>{
      'deviceToken': deviceToken,
      'deviceId': deviceId,
      if (platform != null) 'platform': platform,
      if (timeZone != null) 'timeZone': timeZone,
      if (userId.isNotEmpty) 'userId': userId,
    };
    final response = await _request('POST', '/devices', body: payload);
    debugPrint('POST /devices -> ${response.statusCode} ${response.body}');
    _throwIfNotOk(response);
  }

  static Future<void> sendNotification(Map<String, dynamic> payload) async {
    final response = await _request('POST', '/send-notification', body: payload);
    _throwIfNotOk(response);
  }

  static Future<void> scheduleBillReminder(Map<String, dynamic> payload) async {
    final response = await _request('POST', '/schedule-bill-reminder', body: payload);
    _throwIfNotOk(response);
  }

  static Future<void> cancelReminder(Map<String, dynamic> payload) async {
    final scheduleId = payload['scheduleId']?.toString() ?? '';
    final response = await _request(
      'DELETE',
      scheduleId.isNotEmpty ? '/schedules/$scheduleId' : '/schedules',
      body: payload,
    );
    _throwIfNotOk(response);
  }

  static AccountType _accountTypeFromString(String raw) {
    switch (raw.toLowerCase()) {
      case 'cash':
        return AccountType.cash;
      case 'card':
        return AccountType.card;
      case 'investment':
      case 'savings':
        return AccountType.investment;
      case 'bank':
      case 'checking':
      default:
        return AccountType.bank;
    }
  }

  static String _accountTypeToApi(AccountType type) {
    switch (type) {
      case AccountType.cash:
        return 'cash';
      case AccountType.card:
        return 'card';
      case AccountType.investment:
        return 'savings';
      case AccountType.bank:
      default:
        return 'checking';
    }
  }

  static Recurrence _recurrenceFromString(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'daily':
        return Recurrence.daily;
      case 'weekly':
        return Recurrence.weekly;
      case 'yearly':
        return Recurrence.yearly;
      case 'custom':
        return Recurrence.custom;
      case 'monthly':
      default:
        return Recurrence.monthly;
    }
  }

  static String _recurrenceToApi(Recurrence recurrence) {
    switch (recurrence) {
      case Recurrence.daily:
        return 'daily';
      case Recurrence.weekly:
        return 'weekly';
      case Recurrence.yearly:
        return 'yearly';
      case Recurrence.custom:
        return 'custom';
      case Recurrence.none:
        return 'one-time';
      case Recurrence.monthly:
      default:
        return 'monthly';
    }
  }

  static BillType _billTypeFromString(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'income':
        return BillType.income;
      case 'transfer':
        return BillType.transfer;
      case 'expense':
      default:
        return BillType.expense;
    }
  }

  static PaymentStatus? _paymentStatusFromString(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'paid':
        return PaymentStatus.paid;
      case 'partial':
        return PaymentStatus.partial;
      case 'unpaid':
      default:
        return PaymentStatus.unpaid;
    }
  }

  static Map<String, dynamic> _billToApiPayload(Bill bill, String userId) {
    return {
      'userId': userId,
      'billId': bill.id,
      'name': bill.description ?? 'Bill',
      'amount': bill.amount,
      'dueDate': _formatDateYmd(bill.dueDate),
      'frequency': _recurrenceToApi(bill.recurrence),
      'status': 'active',
      'notes': bill.description,
      'accountId': bill.accountId,
      'categoryId': bill.categoryId,
      'type': bill.type.name,
      'payeeId': bill.payeeId,
      'fromAccountId': bill.fromAccountId,
      'toAccountId': bill.toAccountId,
    };
  }

  static Map<String, dynamic> _transactionToApiPayload(Transaction transaction) {
    return {
      'amount': transaction.amount,
      'direction': transaction.type == TransactionType.income ? 'income' : 'expense',
      'category': transaction.categoryId,
      'merchant': transaction.payeeId ?? transaction.payerId,
      'description': transaction.description,
      'transactionDate': transaction.date.toIso8601String(),
      'accountId': transaction.accountId,
      'billId': transaction.billId,
      'notes': transaction.note,
    };
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    final value = raw.toString();
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  static String _formatDateYmd(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
