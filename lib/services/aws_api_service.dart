// ignore_for_file: unused_import, unreachable_switch_default, unnecessary_null_comparison

import 'dart:convert';

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart' hide Category;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/account.dart';
import '../models/bill.dart';
import '../models/category.dart';
import '../models/reminder_offset.dart';
import '../models/transaction.dart';
import 'device_id_service.dart';
import 'http_service.dart';
import 'user_auth_service.dart';

class AwsApiService {
  static String get _baseUrl => (dotenv.env['API_BASE_URL'] ?? '').trim();
  static String get baseUrl => _baseUrl;

  static Future<String> getIdToken() async {
    return _getIdToken();
  }

  static bool get isConfigured => _baseUrl.isNotEmpty;

  static String _joinPaths(String basePath, String path) {
    final cleanBase =
        basePath.endsWith('/') ? basePath.substring(0, basePath.length - 1) : basePath;
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

      if (session is CognitoAuthSession) {
        final tokensResult = session.userPoolTokensResult;

        try {
          final tokens = tokensResult.value;
          if (tokens != null) {
            return tokens.idToken.raw;
          }
        } catch (_) {}

        safePrint('userPoolTokensResult: $tokensResult');
        return '';
      }

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

  /// Canonical cross-device user ID.
  /// Always prefer Cognito current user instead of local cache.
  static Future<String> _resolveUserId() async {
    try {
      final user = await Amplify.Auth.getCurrentUser();
      final userId = user.userId.trim();
      if (userId.isNotEmpty) {
        return userId;
      }
    } catch (e) {
      debugPrint('Failed to resolve userId from Cognito current user: $e');
    }

    // Fallback only if Cognito lookup fails for some reason.
    try {
      final localUserId = await UserAuthService.getCurrentUserId();
      if (localUserId.isNotEmpty) {
        debugPrint('Falling back to locally stored userId: $localUserId');
        return localUserId;
      }
    } catch (e) {
      debugPrint('Failed to resolve userId from local storage fallback: $e');
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

    final userId = await _resolveUserId();
    if (userId.isNotEmpty) {
      headers['x-user-id'] = userId;
    }

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

    try {
      final isSignedIn =
          await Amplify.Auth.fetchAuthSession().then((session) => session.isSignedIn);
      if (!isSignedIn) {
        throw StateError('User not signed in - cannot make API requests');
      }
    } catch (e) {
      debugPrint('Auth check failed: $e');
      throw StateError('Authentication required for API requests');
    }

    final resolvedUserId = await _resolveUserId();

    final mergedQueryParams = <String, String>{
      ...?queryParameters,
    };

    // Always send canonical userId when available.
    if (resolvedUserId.isNotEmpty && !mergedQueryParams.containsKey('userId')) {
      mergedQueryParams['userId'] = resolvedUserId;
    }

    final mergedBody = <String, dynamic>{
      ...?body,
    };

    // Always include canonical userId in body when not already supplied.
    if (resolvedUserId.isNotEmpty && !mergedBody.containsKey('userId')) {
      mergedBody['userId'] = resolvedUserId;
    }

    final uri = _buildUri(
      path,
      queryParameters: mergedQueryParams.isEmpty ? null : mergedQueryParams,
    );
    final headers = await _buildHeaders();
    final encodedBody = mergedBody.isEmpty ? null : jsonEncode(mergedBody);

    debugPrint('AWS API ${method.toUpperCase()} -> $uri');
    debugPrint('AWS API userId -> ${resolvedUserId.isEmpty ? "(empty)" : resolvedUserId}');

    switch (method) {
      case 'GET':
        return HttpService.execute(
          () => http.get(uri, headers: headers),
          maxAttempts: 2,
          retryOnFailure: true,
        );
      case 'POST':
        return HttpService.execute(
          () => http.post(uri, headers: headers, body: encodedBody),
        );
      case 'PUT':
        return HttpService.execute(
          () => http.put(uri, headers: headers, body: encodedBody),
        );
      case 'DELETE':
        return HttpService.execute(
          () => http.delete(uri, headers: headers, body: encodedBody),
          maxAttempts: 2,
          retryOnFailure: true,
        );
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
    final balance = ((json['balance'] ?? json['initialBalance']) as num?)?.toDouble() ?? 0.0;
    final statusRaw = json['status']?.toString().trim().toLowerCase();
    final isActiveRaw =
      json['isActive'] ??
      json['active'] ??
      json['enabled'] ??
      ((statusRaw == 'archived' || statusRaw == 'inactive') ? false : null);
    final isActive = _parseNullableBool(isActiveRaw) ?? true;
    final institutionRaw = (
      json['institution'] ??
      json['bankName'] ??
      json['provider'] ??
      json['description'] ??
      ''
    ).toString().trim();
    final descriptionRaw = (
      json['description'] ??
      json['institution'] ??
      ''
    ).toString().trim();

    return Account(
      id: id.toString(),
      name: name.toString(),
      type: type,
      balance: balance,
      currency: currency.toString(),
      isActive: isActive,
      description: descriptionRaw.isEmpty ? null : descriptionRaw,
      institution: institutionRaw.isEmpty ? null : institutionRaw,
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
      recurrenceWeekdays:
          (json['recurrenceWeekdays'] as List?)?.map((e) => (e as num).toInt()).toList(),
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
    final categoryIdRaw = (
      json['categoryId'] ??
      json['category_id'] ??
      json['category'] ??
      ''
    ).toString();
    String? categoryName = json['categoryName']?.toString() ??
        json['category_name']?.toString() ??
        json['categoryDisplayName']?.toString() ??
        json['categoryLabel']?.toString();
    final categoryField = json['category']?.toString();
    if ((categoryName == null || categoryName.trim().isEmpty) &&
        categoryField != null &&
        categoryField.isNotEmpty &&
        categoryField != categoryIdRaw) {
      categoryName = categoryField;
    }
    final clearedRaw =
        json['cleared'] ?? json['isCleared'] ?? json['is_cleared'] ?? json['clearedStatus'];
    bool? cleared = _parseNullableBool(clearedRaw);
    if (cleared == null) {
      final status = clearedRaw?.toString().trim().toLowerCase() ?? '';
      if (status == 'cleared' || status == 'posted' || status == 'reconciled') {
        cleared = true;
      } else if (status == 'uncleared' || status == 'pending') {
        cleared = false;
      }
    }

    final createdAt =
      _parseDateTime(json['createdAt'] ?? json['created_at'] ?? json['timestamp']) ??
      date;
    final updatedAt =
      _parseDateTime(json['updatedAt'] ?? json['updated_at'] ?? json['lastModified'] ?? json['last_modified']) ??
      createdAt;

    final payeeNameRaw = json['payeeName']?.toString() ?? json['payee_name']?.toString();
    final payerNameRaw = json['payerName']?.toString() ?? json['payer_name']?.toString();

    return Transaction(
      id: id.toString(),
      amount: amount.abs(),
      categoryId: categoryIdRaw,
      categoryName: (categoryName == null || categoryName.trim().isEmpty)
          ? null
          : categoryName.trim(),
      type: type,
      description: (json['description'] ?? json['merchant'] ?? '').toString(),
      date: date,
      note: json['notes']?.toString(),
      accountId: json['accountId']?.toString(),
      cleared: cleared,
      createdAt: createdAt,
      updatedAt: updatedAt,
      billId: json['billId']?.toString(),
      payerId: json['payerId']?.toString(),
      payeeId: json['payeeId']?.toString(),
      paymentFor: json['paymentFor']?.toString() ?? json['payment_for']?.toString(),
      payeeName: (payeeNameRaw == null || payeeNameRaw.trim().isEmpty) ? null : payeeNameRaw.trim(),
      payerName: (payerNameRaw == null || payerNameRaw.trim().isEmpty) ? null : payerNameRaw.trim(),
    );
  }

  // Accounts
  static Future<List<Account>> fetchAccounts() async {
    final response = await _request('GET', '/accounts');
    _throwIfNotOk(response);
    final decoded = jsonDecode(response.body);
    if (decoded is List) {
      return decoded
          .map<Account>((e) => _accountFromItem(Map<String, dynamic>.from(e)))
          .toList();
    }
    if (decoded is Map && decoded['items'] is List) {
      return (decoded['items'] as List)
          .map<Account>((e) => _accountFromItem(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }

  static Future<void> createAccount(Account account) async {
    final payload = account.toJson();
    final response = await _request('POST', '/accounts', body: payload);
    _throwIfNotOk(response);
  }

  static Future<void> updateAccount(Account account) async {
    final payload = account.toJson();
    final response = await _request('PUT', '/accounts/${account.id}', body: payload);
    _throwIfNotOk(response);
  }

  static Future<void> deleteAccount(String accountId) async {
    final response = await _request(
      'DELETE',
      '/accounts/$accountId',
      body: {'accountId': accountId},
    );
    _throwIfNotOk(response);
  }

  // Bills
  static Future<List<Bill>> fetchBills() async {
    final response = await _request('GET', '/bills');
    _throwIfNotOk(response);
    final decoded = jsonDecode(response.body);
    if (decoded is List) {
      return decoded
          .map<Bill>((e) => _billFromItem(Map<String, dynamic>.from(e)))
          .toList();
    }
    if (decoded is Map && decoded['items'] is List) {
      return (decoded['items'] as List)
          .map<Bill>((e) => _billFromItem(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }

  static Future<void> createBill(Bill bill, {List<ReminderOffset> reminderOffsets = const []}) async {
    final userId = await _resolveUserId();
    if (userId.isEmpty) {
      throw StateError('No userId available for bill creation');
    }
    final payload = _billToApiPayload(bill, userId, reminderOffsets: reminderOffsets);
    final response = await _request('POST', '/bills', body: payload);
    _throwIfNotOk(response);
  }

  static Future<void> updateBill(Bill bill, {List<ReminderOffset> reminderOffsets = const []}) async {
    final userId = await _resolveUserId();
    if (userId.isEmpty) {
      throw StateError('No userId available for bill update');
    }
    final payload = _billToApiPayload(bill, userId, reminderOffsets: reminderOffsets);
    final response = await _request('PUT', '/bills/${bill.id}', body: payload);
    _throwIfNotOk(response);
  }

  static Future<void> deleteBill(String billId) async {
    final response = await _request(
      'DELETE',
      '/bills/$billId',
      body: {'billId': billId},
    );
    _throwIfNotOk(response);
  }

  // Transactions
  static Future<List<Transaction>> fetchTransactions() async {
    final response = await _request('GET', '/transactions');
    _throwIfNotOk(response);
    final decoded = jsonDecode(response.body);
    if (decoded is List) {
      return decoded
          .map<Transaction>((e) => _transactionFromItem(Map<String, dynamic>.from(e)))
          .toList();
    }
    if (decoded is Map && decoded['items'] is List) {
      return (decoded['items'] as List)
          .map<Transaction>((e) => _transactionFromItem(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }

  static Future<void> createTransaction(Transaction transaction) async {
    final payload = _transactionToApiPayload(transaction)
      ..['transactionId'] = transaction.id;
    final response = await _request('POST', '/transactions', body: payload);
    _throwIfNotOk(response);
  }

  static Future<void> updateTransaction(Transaction transaction) async {
    final payload = _transactionToApiPayload(transaction)
      ..['transactionId'] = transaction.id;
    final response =
        await _request('PUT', '/transactions/${transaction.id}', body: payload);
    _throwIfNotOk(response);
  }

  static Future<void> deleteTransaction(String transactionId) async {
    final response = await _request(
      'DELETE',
      '/transactions/$transactionId',
      body: {'transactionId': transactionId},
    );
    _throwIfNotOk(response);
  }

  // Payments
  static Future<void> createPayment(Map<String, dynamic> payload) async {
    final response = await _request('POST', '/billpayments', body: payload);
    _throwIfNotOk(response);
  }

  // Categories / Payees / Payers / Payments (pull sync)
  static Future<List<Category>> fetchCategories() async {
    final decoded = await _fetchCollectionOptional(
      '/lookups',
      queryParameters: {'type': 'category'},
    );
    return decoded.map(_categoryFromItem).toList();
  }

  static Future<List<Map<String, dynamic>>> fetchPayees() async {
    final decoded = await _fetchCollectionOptional(
      '/lookups',
      queryParameters: {'type': 'payee'},
    );
    return decoded.map((e) => _contactFromItem(e, forcedType: 'payee')).toList();
  }

  static Future<List<Map<String, dynamic>>> fetchPayers() async {
    final decoded = await _fetchCollectionOptional(
      '/lookups',
      queryParameters: {'type': 'payer'},
    );
    return decoded.map((e) => _contactFromItem(e, forcedType: 'payer')).toList();
  }

  static Future<List<Map<String, dynamic>>> fetchPayments() async {
    return _fetchCollectionOptional('/billpayments');
  }

  static Future<void> createCategory(Category category) async {
    final response = await _request('POST', '/lookups', body: {
      'type': 'category',
      'id': category.id,
      'name': category.name,
      'color': category.colorValue,
      'isIncome': category.type == CategoryType.income,
    });
    _throwIfNotOk(response);
  }

  static Future<void> updateCategory(Category category) async {
    final response = await _request('PUT', '/lookups', body: {
      'type': 'category',
      'id': category.id,
      'name': category.name,
      'color': category.colorValue,
      'isIncome': category.type == CategoryType.income,
    });
    _throwIfNotOk(response);
  }

  static Future<void> deleteCategory(String id) async {
    final response = await _request('DELETE', '/lookups', body: {
      'type': 'category',
      'id': id,
    });
    _throwIfNotOk(response);
  }

  static Future<List<Map<String, dynamic>>> _fetchCollectionOptional(
    String path, {
    Map<String, String>? queryParameters,
  }
  ) async {
    try {
      final response = await _request(
        'GET',
        path,
        queryParameters: queryParameters,
      );
      if (response.statusCode == 404) {
        return [];
      }
      _throwIfNotOk(response);
      final decoded = jsonDecode(response.body);

      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      if (decoded is Map && decoded['items'] is List) {
        return (decoded['items'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      if (decoded is Map && decoded['data'] is List) {
        return (decoded['data'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('Optional fetch failed for $path: $e');
      return [];
    }
  }

  // Notifications
  static Future<void> registerDevice({
    required String deviceToken,
    String? platform,
    String? environment,
    String? timeZone,
    bool? notificationsEnabled,
    String? appVersion,
    String? osVersion,
  }) async {
    final userId = await _resolveUserId();
    final deviceId = await DeviceIdService.getOrCreate();

    final payload = <String, dynamic>{
      'deviceToken': deviceToken,
      'deviceId': deviceId,
      if (platform != null) 'platform': platform,
      if (environment != null) 'environment': environment,
      if (timeZone != null) 'timeZone': timeZone,
      if (notificationsEnabled != null) 'notificationsEnabled': notificationsEnabled,
      if (appVersion != null && appVersion.isNotEmpty) 'appVersion': appVersion,
      if (osVersion != null && osVersion.isNotEmpty) 'osVersion': osVersion,
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

static Future<void> refreshBillNotificationSchedules(
  Map<String, dynamic> payload,
) async {
  final response = await _request('POST', '/send-notification', body: payload);
  _throwIfNotOk(response);
}

static Future<void> cancelReminder(Map<String, dynamic> payload) async {
  final scheduleId = payload['scheduleId']?.toString() ?? '';

  if (scheduleId.isEmpty) {
    throw Exception('scheduleId is required to cancel a reminder');
  }

  final response = await _request(
    'DELETE',
    '/notification-schedules/$scheduleId',
  );

  _throwIfNotOk(response);
  }

  /// Optional backend verification hook for Google Play purchases.
  /// Returns canonical plan id when backend resolves entitlement, else null.
  static Future<String?> verifyAndroidPurchase({
    required String productId,
    required String purchaseToken,
    String? purchaseId,
    String? source,
  }) async {
    try {
      final response = await _request(
        'POST',
        '/billing/google-play/verify',
        body: {
          'productId': productId,
          'purchaseToken': purchaseToken,
          if (purchaseId != null && purchaseId.isNotEmpty) 'purchaseId': purchaseId,
          if (source != null && source.isNotEmpty) 'source': source,
        },
      );

      if (response.statusCode == 404) {
        // Endpoint not deployed yet; caller should fall back locally.
        return null;
      }

      _throwIfNotOk(response);

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;

      final planRaw = (
        decoded['plan'] ??
        decoded['subscriptionPlan'] ??
        decoded['entitlement'] ??
        decoded['tier']
      )?.toString();

      if (planRaw == null || planRaw.trim().isEmpty) return null;

      final normalized = planRaw.trim().toLowerCase();
      if (normalized == 'monthly') return 'Monthly';
      if (normalized == 'annual' || normalized == 'yearly') return 'Annual';
      if (normalized == 'lifetime') return 'Lifetime';

      return planRaw;
    } catch (e) {
      debugPrint('verifyAndroidPurchase failed: $e');
      return null;
    }
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

  static Category _categoryFromItem(Map<String, dynamic> json) {
    final id = (json['categoryId'] ?? json['id'] ?? '').toString();
    final name = (json['name'] ?? json['title'] ?? 'Category').toString();
    final iconCodePoint = (json['iconCodePoint'] ?? '0xe88a').toString();
    final colorValue = (json['colorValue'] ?? '0xFF4CAF50').toString();
    final typeRaw = (json['type'] ?? '').toString().toLowerCase();
    final isIncomeRaw = json['isIncome'];
    final normalizedIncome = isIncomeRaw?.toString().trim().toLowerCase();
    final isIncome =
      isIncomeRaw == true ||
      isIncomeRaw == 1 ||
      normalizedIncome == 'true' ||
      normalizedIncome == '1' ||
      typeRaw == 'income';

    return Category(
      id: id,
      name: name,
      iconCodePoint: iconCodePoint,
      colorValue: colorValue,
      isDefault: json['isDefault'] == true,
      budgetLimit: (json['budgetLimit'] as num?)?.toDouble(),
      image: json['image']?.toString(),
      type: isIncome ? CategoryType.income : CategoryType.expense,
    );
  }

  static Map<String, dynamic> _contactFromItem(
    Map<String, dynamic> json, {
    required String forcedType,
  }) {
    final id = (json['id'] ?? json['payeeId'] ?? json['payerId'] ?? '').toString();
    final name = (json['name'] ?? json['displayName'] ?? json['merchant'] ?? '').toString();
    return {
      'id': id,
      'name': name,
      'type': forcedType,
      'categoryId': json['categoryId']?.toString(),
    };
  }

  static Recurrence _recurrenceFromString(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'none':
      case 'one-time':
      case 'one_time':
      case 'onetime':
      case 'once':
      case 'single':
        return Recurrence.none;
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

  static Map<String, dynamic> _billToApiPayload(
    Bill bill,
    String userId, {
    required List<ReminderOffset> reminderOffsets,
  }) {
    final sanitizedName = ((bill.description ?? '').trim().toLowerCase() == 'bill')
        ? ''
        : (bill.description ?? '');
    return {
      'userId': userId,
      'billId': bill.id,
      'name': sanitizedName,
      'amount': bill.amount,
      'dueDate': _formatDateMMDDYYYY(bill.dueDate),
      'frequency': _recurrenceToApi(bill.recurrence),
      'status': 'active',
      'notes': bill.description,
      'accountId': bill.accountId,
      'categoryId': bill.categoryId,
      'type': bill.type.name,
      'payeeId': bill.payeeId,
      'fromAccountId': bill.fromAccountId,
      'toAccountId': bill.toAccountId,
      'remindersEnabled': reminderOffsets.isNotEmpty,
      'reminderOffsets': reminderOffsets.map((r) => r.toJson()).toList(),
      'reminderDaysBefore': reminderOffsets.isNotEmpty ? reminderOffsets.first.daysBefore : 0,
    };
  }

  static Map<String, dynamic> _transactionToApiPayload(Transaction transaction) {
    return {
      'amount': transaction.amount,
      'direction': transaction.type == TransactionType.income ? 'income' : 'expense',
      'category': transaction.categoryId,
      'categoryId': transaction.categoryId,
      'category_id': transaction.categoryId,
      'categoryName': transaction.categoryName,
      'merchant': transaction.payeeId ?? transaction.payerId,
      'description': transaction.description,
      'transactionDate': transaction.date.toIso8601String(),
      'accountId': transaction.accountId,
      'billId': transaction.billId,
      'notes': transaction.note,
      'paymentFor': transaction.paymentFor,
      'payment_for': transaction.paymentFor,
      'cleared': transaction.cleared,
      'isCleared': transaction.cleared,
    };
  }

  static bool? _parseNullableBool(dynamic raw) {
    if (raw == null) return null;
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final value = raw.toString().trim().toLowerCase();
    if (value.isEmpty) return null;
    if (value == 'true' || value == '1' || value == 'yes' || value == 'y') {
      return true;
    }
    if (value == 'false' || value == '0' || value == 'no' || value == 'n') {
      return false;
    }
    return null;
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    final value = raw.toString().trim();

    final mmddyyyy = RegExp(r'^(\d{2})\/(\d{2})\/(\d{4})$');
    final m1 = mmddyyyy.firstMatch(value);
    if (m1 != null) {
      final mm = int.tryParse(m1.group(1)!);
      final dd = int.tryParse(m1.group(2)!);
      final yyyy = int.tryParse(m1.group(3)!);
      if (mm != null && dd != null && yyyy != null) {
        return DateTime(yyyy, mm, dd);
      }
    }

    final ymd = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
    final m2 = ymd.firstMatch(value);
    if (m2 != null) {
      final yyyy = int.tryParse(m2.group(1)!);
      final mm = int.tryParse(m2.group(2)!);
      final dd = int.tryParse(m2.group(3)!);
      if (mm != null && dd != null && yyyy != null) {
        return DateTime(yyyy, mm, dd);
      }
    }

    try {
      final isoDateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
      if (isoDateOnly != null) {
        final yyyy = int.parse(isoDateOnly.group(1)!);
        final mm = int.parse(isoDateOnly.group(2)!);
        final dd = int.parse(isoDateOnly.group(3)!);
        return DateTime(yyyy, mm, dd);
      }
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  static DateTime? _parseDateTime(dynamic raw) {
    if (raw == null) return null;
    final value = raw.toString().trim();
    if (value.isEmpty) return null;
    try {
      return DateTime.parse(value);
    } catch (_) {
      return _parseDate(raw);
    }
  }

  static String _formatDateMMDDYYYY(DateTime date) {
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    final yyyy = date.year.toString().padLeft(4, '0');
    return '$mm/$dd/$yyyy';
  }
}
