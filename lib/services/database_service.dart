import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../models/category.dart';
import '../models/account.dart';
import '../models/bill.dart';
import '../models/reminder_offset.dart';
import 'aws_api_service.dart';
import 'cloud_sync_policy.dart';

class DatabaseService {
  static const String _hideFromCalendarMarker = '__hide_from_calendar__';
  static const String _legacyAccountCalendarMigrationKey =
      'migratedLegacyAccountCalendarHiddenV1';
  static const String _legacyCategoryNameMigrationKey =
      'migratedLegacyTransactionCategoryNamesV1';
  static const String _legacyCategoryResolutionMigrationKey =
      'migratedLegacyTransactionCategoryResolutionV1';
  static const String _legacyPaymentForMigrationKey =
      'migratedLegacyTransactionPaymentForV1';
  static const String _legacyRecurringSplitOverlapMigrationKey =
      'migratedLegacyRecurringSplitOverlapV1';
  static const String _postFixRecurringSplitRepairKey =
      'postFixRecurringSplitRepairV2';
  static const String _legacyBillPlaceholderTextMigrationKey =
      'migratedLegacyBillPlaceholderTextV1';
  static const String _deletedAccountsKey = 'deletedAccountIds';
  static const String _deletedBillsKey = 'deletedBillIds';
  static const String _deletedCategoriesKey = 'deletedCategoryIds';
  static const String _deletedTransactionsKey = 'deletedTransactionIds';
  static const String _billRecurrenceEndOverridesKey =
      'billRecurrenceEndOverrides';
  static const String _locallyModifiedBillsKey = 'locallyModifiedBillIds';

  static List<ReminderOffset> _selectedReminderOffsetsForApi() {
    try {
      final raw = getSetting<String>('notif_billReminderOffsets', null);
      if (raw == null || raw.trim().isEmpty) return const <ReminderOffset>[];

      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <ReminderOffset>[];

      final out = <ReminderOffset>[];
      for (final entry in decoded) {
        if (entry is Map<String, dynamic>) {
          out.add(
            ReminderOffset(
              daysBefore: (entry['daysBefore'] as num?)?.toInt() ?? 1,
              hour: (entry['hour'] as num?)?.toInt() ?? 9,
              minute: (entry['minute'] as num?)?.toInt() ?? 0,
            ),
          );
          continue;
        }

        if (entry is Map) {
          out.add(
            ReminderOffset(
              daysBefore: (entry['daysBefore'] as num?)?.toInt() ?? 1,
              hour: (entry['hour'] as num?)?.toInt() ?? 9,
              minute: (entry['minute'] as num?)?.toInt() ?? 0,
            ),
          );
        }
      }
      return out;
    } catch (_) {
      return const <ReminderOffset>[];
    }
  }

  static List<String> _getDeletedAccountIds() {
    try {
      final raw =
          _settingsBox.get(_deletedAccountsKey, defaultValue: <dynamic>[])
              as List<dynamic>;
      return raw.map((e) => e.toString()).toList();
    } catch (_) {
      return <String>[];
    }
  }

  static Future<void> _addDeletedAccountId(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    final ids = _getDeletedAccountIds();
    if (!ids.contains(trimmed)) {
      ids.add(trimmed);
      await _settingsBox.put(_deletedAccountsKey, ids);
      await _settingsBox.flush();
    }
  }

  static Future<void> _removeDeletedAccountId(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    final ids = _getDeletedAccountIds();
    if (ids.remove(trimmed)) {
      await _settingsBox.put(_deletedAccountsKey, ids);
      await _settingsBox.flush();
    }
  }

  static List<String> _getDeletedBillIds() {
    try {
      final raw =
          _settingsBox.get(_deletedBillsKey, defaultValue: <dynamic>[])
              as List<dynamic>;
      return raw.map((e) => e.toString()).toList();
    } catch (_) {
      return <String>[];
    }
  }

  static List<String> _getDeletedCategoryIds() {
    try {
      final raw =
          _settingsBox.get(_deletedCategoriesKey, defaultValue: <dynamic>[])
              as List<dynamic>;
      return raw.map((e) => e.toString()).toList();
    } catch (_) {
      return <String>[];
    }
  }

  static Future<void> _addDeletedCategoryId(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    final ids = _getDeletedCategoryIds();
    if (!ids.contains(trimmed)) {
      ids.add(trimmed);
      await _settingsBox.put(_deletedCategoriesKey, ids);
      await _settingsBox.flush();
    }
  }

  static Future<void> _removeDeletedCategoryId(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    final ids = _getDeletedCategoryIds();
    if (ids.remove(trimmed)) {
      await _settingsBox.put(_deletedCategoriesKey, ids);
      await _settingsBox.flush();
    }
  }

  static List<String> _getDeletedTransactionIds() {
    try {
      final raw =
          _settingsBox.get(_deletedTransactionsKey, defaultValue: <dynamic>[])
              as List<dynamic>;
      return raw.map((e) => e.toString()).toList();
    } catch (_) {
      return <String>[];
    }
  }

  static Future<void> _addDeletedTransactionId(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    final ids = _getDeletedTransactionIds();
    if (!ids.contains(trimmed)) {
      ids.add(trimmed);
      await _settingsBox.put(_deletedTransactionsKey, ids);
      await _settingsBox.flush();
    }
  }

  static Future<void> _removeDeletedTransactionId(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    final ids = _getDeletedTransactionIds();
    if (ids.remove(trimmed)) {
      await _settingsBox.put(_deletedTransactionsKey, ids);
      await _settingsBox.flush();
    }
  }

  static Future<void> _addDeletedBillId(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    final ids = _getDeletedBillIds();
    if (!ids.contains(trimmed)) {
      ids.add(trimmed);
      await _settingsBox.put(_deletedBillsKey, ids);
      await _settingsBox.flush();
    }
  }

  static Future<void> _removeDeletedBillId(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    final ids = _getDeletedBillIds();
    if (ids.remove(trimmed)) {
      await _settingsBox.put(_deletedBillsKey, ids);
      await _settingsBox.flush();
    }
  }

  static List<String> _getLocallyModifiedBillIds() {
    try {
      final raw =
          _settingsBox.get(_locallyModifiedBillsKey, defaultValue: <dynamic>[])
              as List<dynamic>;
      return raw.map((e) => e.toString()).toList();
    } catch (_) {
      return <String>[];
    }
  }

  static Future<void> _addLocallyModifiedBillId(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    final ids = _getLocallyModifiedBillIds();
    if (!ids.contains(trimmed)) {
      ids.add(trimmed);
      await _settingsBox.put(_locallyModifiedBillsKey, ids);
      await _settingsBox.flush();
    }
  }

  static Future<void> _removeLocallyModifiedBillId(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    final ids = _getLocallyModifiedBillIds();
    if (ids.remove(trimmed)) {
      await _settingsBox.put(_locallyModifiedBillsKey, ids);
      await _settingsBox.flush();
    }
  }

  static Map<String, DateTime> _getBillRecurrenceEndOverrides() {
    try {
      final raw = _settingsBox.get(
        _billRecurrenceEndOverridesKey,
        defaultValue: <String, dynamic>{},
      );
      if (raw is! Map) return <String, DateTime>{};
      final out = <String, DateTime>{};
      for (final entry in raw.entries) {
        final billId = entry.key.toString().trim();
        if (billId.isEmpty) continue;
        final parsed = DateTime.tryParse(entry.value.toString());
        if (parsed == null) continue;
        out[billId] = DateTime(parsed.year, parsed.month, parsed.day);
      }
      return out;
    } catch (_) {
      return <String, DateTime>{};
    }
  }

  static Future<void> setBillRecurrenceEndOverride(
    String billId,
    DateTime recurrenceEndDate,
  ) async {
    final id = billId.trim();
    if (id.isEmpty) return;
    final current = _getBillRecurrenceEndOverrides();
    current[id] = DateTime(
      recurrenceEndDate.year,
      recurrenceEndDate.month,
      recurrenceEndDate.day,
    );
    final encoded = <String, String>{
      for (final e in current.entries) e.key: e.value.toIso8601String(),
    };
    await _settingsBox.put(_billRecurrenceEndOverridesKey, encoded);
    await _settingsBox.flush();
  }

  static Future<void> clearBillRecurrenceEndOverride(String billId) async {
    final id = billId.trim();
    if (id.isEmpty) return;
    final current = _getBillRecurrenceEndOverrides();
    if (current.remove(id) == null) return;
    final encoded = <String, String>{
      for (final e in current.entries) e.key: e.value.toIso8601String(),
    };
    await _settingsBox.put(_billRecurrenceEndOverridesKey, encoded);
    await _settingsBox.flush();
  }

  static Future<int> clearStaleForeverBillRecurrenceEndOverrides() async {
    final current = _getBillRecurrenceEndOverrides();
    if (current.isEmpty) return 0;

    var removed = 0;
    for (final bill in _billsBox.values) {
      if (bill.recurrence == Recurrence.none) continue;
      if (bill.recurrenceEndDate != null) continue;
      if (current.remove(bill.id) != null) {
        removed++;
      }
    }

    if (removed == 0) return 0;

    final encoded = <String, String>{
      for (final e in current.entries) e.key: e.value.toIso8601String(),
    };
    await _settingsBox.put(_billRecurrenceEndOverridesKey, encoded);
    await _settingsBox.flush();
    billsVersion.value++;
    return removed;
  }

  static void _registerAdapterIfNeeded<T>(int typeId, TypeAdapter<T> adapter) {
    try {
      Hive.registerAdapter<T>(adapter, override: true);
    } catch (e) {
      try {
        if (!Hive.isAdapterRegistered(typeId)) {
          Hive.registerAdapter<T>(adapter);
          return;
        }
      } catch (_) {}
      if (e.toString().contains('already a TypeAdapter')) return;
      rethrow;
    }
  }

  static void _registerHiveAdapters() {
    _registerAdapterIfNeeded(1, TransactionAdapter());
    _registerAdapterIfNeeded(0, TransactionTypeAdapter());
    _registerAdapterIfNeeded(2, CategoryAdapter());
    _registerAdapterIfNeeded(42, CategoryTypeAdapter());
    _registerAdapterIfNeeded(3, AccountTypeAdapter());
    _registerAdapterIfNeeded(4, AccountAdapter());
    _registerAdapterIfNeeded(5, RecurrenceAdapter());
    _registerAdapterIfNeeded(8, PaymentStatusAdapter());
    _registerAdapterIfNeeded(7, BillTypeAdapter());
    _registerAdapterIfNeeded(6, BillAdapter());
  }

  static Future<Box<T>> _openTypedBoxWithRecovery<T>(String boxName) async {
    // Never reuse an already-open box instance for a different generic type.
    // Even when `Hive.box<T>()` compiles, the underlying box may still have
    // been opened with a different adapter context, causing runtime mismatches
    // like `Category is not a subtype of Transaction` on writes.
    if (Hive.isBoxOpen(boxName)) {
      try {
        await Hive.box(boxName).close();
      } catch (_) {}
    }

    try {
      return await Hive.openBox<T>(boxName);
    } catch (e) {
      foundation.debugPrint('Failed to open $boxName box, rebuilding it: $e');
      try {
        if (Hive.isBoxOpen(boxName)) {
          await Hive.box(boxName).close();
        }
      } catch (_) {}
      await Hive.deleteBoxFromDisk(boxName);
      return await Hive.openBox<T>(boxName);
    }
  }

  static Future<Box> _openBoxWithRecovery(String boxName) async {
    try {
      return await Hive.openBox(boxName);
    } catch (e) {
      foundation.debugPrint('Failed to open $boxName box, rebuilding it: $e');
      try {
        if (Hive.isBoxOpen(boxName)) {
          await Hive.box(boxName).close();
        }
      } catch (_) {}
      await Hive.deleteBoxFromDisk(boxName);
      return await Hive.openBox(boxName);
    }
  }

  /// Returns the transfer category, creating it if it doesn't exist.
  static Future<Category> getOrCreateTransferCategory() async {
    // Try to find an existing transfer category (case-insensitive)
    final existing = getAllCategories().firstWhere(
      (c) => c.name.trim().toLowerCase() == 'transfer',
      orElse: () => Category(
        name: 'Transfer',
        iconCodePoint: '0xe5c8', // Icons.swap_horiz
        colorValue: '0xFF607D8B',
        isDefault: true,
        type: CategoryType.expense, // Could be expense or a new type if needed
      ),
    );
    if (existing.id.isNotEmpty && getCategoryById(existing.id) != null) {
      return existing;
    }
    // If not found, add it
    final transferCat = Category(
      name: 'Transfer',
      iconCodePoint: '0xe5c8', // Icons.swap_horiz
      colorValue: '0xFF607D8B',
      isDefault: true,
      type: CategoryType.expense,
    );
    await addCategory(transferCat);
    return transferCat;
  }

  // Update all transactions, bills, etc. that reference a category when the category is edited
  static Future<void> updateCategoryReferences(Category updatedCategory) async {
    final normalizedName = updatedCategory.name.trim();

    final txs = getAllTransactions()
        .where((t) => t.categoryId == updatedCategory.id)
        .toList();
    var updatedCount = 0;
    for (final tx in txs) {
      if ((tx.categoryName ?? '').trim() == normalizedName) continue;
      final updated = tx.copyWith(
        categoryId: updatedCategory.id,
        categoryName: normalizedName,
        updatedAt: DateTime.now(),
      );
      await _transactionBox.put(updated.id, updated);
      updatedCount++;
    }

    if (updatedCount > 0) {
      await _transactionBox.flush();
      transactionsVersion.value++;
    }

    // Bills reference categoryId directly; no denormalized name to rewrite.
    // Keep existing IDs unchanged so all bill/category lookups stay consistent.
  }

  // Update all transactions, bills, etc. that reference a payee/payer when edited
  static Future<void> updatePayeeReferences(
    Map<String, dynamic> updatedPayee,
  ) async {
    final payeeId = (updatedPayee['id'] ?? '').toString().trim();
    if (payeeId.isEmpty) return;

    final updatedName = (updatedPayee['name'] ?? '').toString().trim();
    final updatedType = (updatedPayee['type'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final rawCategoryId = updatedPayee['categoryId']?.toString().trim();
    final updatedCategoryId =
        (rawCategoryId == null ||
            rawCategoryId.isEmpty ||
            rawCategoryId.toLowerCase() == 'null')
        ? null
        : rawCategoryId;
    final updatedCategoryName = updatedCategoryId == null
        ? null
        : getCategoryById(updatedCategoryId)?.name;

    final txs = getAllTransactions()
        .where((t) => t.payeeId == payeeId || t.payerId == payeeId)
        .toList();
    var transactionsUpdated = 0;
    for (final tx in txs) {
      final bool matchesPayee = tx.payeeId == payeeId;
      final bool matchesPayer = tx.payerId == payeeId;

      String? nextPayeeName = tx.payeeName;
      String? nextPayerName = tx.payerName;
      if (updatedName.isNotEmpty) {
        if (matchesPayee) nextPayeeName = updatedName;
        if (matchesPayer) nextPayerName = updatedName;
      }

      String nextCategoryId = tx.categoryId;
      String? nextCategoryName = tx.categoryName;
      if (updatedCategoryId != null) {
        nextCategoryId = updatedCategoryId;
        nextCategoryName = updatedCategoryName;
      }

      final samePayeeName = (nextPayeeName ?? '') == (tx.payeeName ?? '');
      final samePayerName = (nextPayerName ?? '') == (tx.payerName ?? '');
      final sameCategoryId = nextCategoryId == tx.categoryId;
      final sameCategoryName =
          (nextCategoryName ?? '') == (tx.categoryName ?? '');
      if (samePayeeName &&
          samePayerName &&
          sameCategoryId &&
          sameCategoryName) {
        continue;
      }

      final updated = tx.copyWith(
        payeeName: nextPayeeName,
        payerName: nextPayerName,
        categoryId: nextCategoryId,
        categoryName: nextCategoryName,
        updatedAt: DateTime.now(),
      );
      await _transactionBox.put(updated.id, updated);
      transactionsUpdated++;
    }

    if (transactionsUpdated > 0) {
      await _transactionBox.flush();
      transactionsVersion.value++;
    }

    final bills = getAllBills().where((b) => b.payeeId == payeeId).toList();
    var billsUpdated = 0;
    for (final bill in bills) {
      final nextBillType = updatedType == 'payer'
          ? BillType.income
          : updatedType == 'payee'
          ? BillType.expense
          : bill.type;
      final nextBillCategoryId = updatedCategoryId ?? bill.categoryId;
      if (nextBillType == bill.type && nextBillCategoryId == bill.categoryId) {
        continue;
      }
      final updated = bill.copyWith(
        type: nextBillType,
        categoryId: nextBillCategoryId,
      );
      await _billsBox.put(updated.id, updated);
      billsUpdated++;
    }

    if (billsUpdated > 0) {
      await _billsBox.flush();
      billsVersion.value++;
    }
  }

  // ...existing code...
  static const String _transactionBoxName = 'transactions';
  static const String _categoryBoxName = 'categories';
  static const String _accountBoxName = 'accounts';
  static const String _settingsBoxName = 'settings';
  static const String _billsBoxName = 'bills';
  static const String _billOccurrenceBoxName = 'bill_occurrence_status';

  static late Box<Transaction> _transactionBox;
  static late Box<Category> _categoryBox;
  static late Box<Account> _accountBox;
  static late Box _settingsBox;
  static late Box<Bill> _billsBox;
  static late Box _billOccurrenceBox;

  // Notifiers used by UI to refresh when underlying data changes
  static final foundation.ValueNotifier<int> categoriesVersion =
      foundation.ValueNotifier<int>(0);
  static final foundation.ValueNotifier<int> billsVersion =
      foundation.ValueNotifier<int>(0);
  static final foundation.ValueNotifier<int> payeesVersion =
      foundation.ValueNotifier<int>(0);
  static final foundation.ValueNotifier<int> accountsVersion =
      foundation.ValueNotifier<int>(0);
  static final foundation.ValueNotifier<int> transactionsVersion =
      foundation.ValueNotifier<int>(0);
  static final foundation.ValueNotifier<String> subscriptionVersion =
      foundation.ValueNotifier<String>('Free');

  static Future<bool> _safeAwsCall(
    Future<void> Function() task,
    String label,
  ) async {
    if (!CloudSyncPolicy.syncUserFinanceDataToAws) return true;
    if (!AwsApiService.isConfigured) return true;
    try {
      await task();
      return true;
    } catch (e) {
      foundation.debugPrint('AWS sync failed ($label): $e');
      return false;
    }
  }

  static bool _isBillTransactionTypeMismatch(Object error) {
    final msg = error.toString();
    return msg.contains('Bill') && msg.contains('Transaction');
  }

  static bool _isCategoryTransactionTypeMismatch(Object error) {
    final msg = error.toString();
    return msg.contains('Category') && msg.contains('Transaction');
  }

  static Future<void> _reopenCoreBoxes() async {
    _registerHiveAdapters();
    try {
      if (Hive.isBoxOpen(_transactionBoxName)) {
        await Hive.box(_transactionBoxName).close();
      }
    } catch (_) {}
    try {
      if (Hive.isBoxOpen(_billsBoxName)) {
        await Hive.box(_billsBoxName).close();
      }
    } catch (_) {}

    _transactionBox = await _openTypedBoxWithRecovery<Transaction>(
      _transactionBoxName,
    );
    _billsBox = await _openTypedBoxWithRecovery<Bill>(_billsBoxName);
  }

  static Future<void> _reopenCategoryAndTransactionBoxes() async {
    _registerHiveAdapters();
    try {
      if (Hive.isBoxOpen(_categoryBoxName)) {
        await Hive.box(_categoryBoxName).close();
      }
    } catch (_) {}
    try {
      if (Hive.isBoxOpen(_transactionBoxName)) {
        await Hive.box(_transactionBoxName).close();
      }
    } catch (_) {}

    _categoryBox = await _openTypedBoxWithRecovery<Category>(_categoryBoxName);
    _transactionBox = await _openTypedBoxWithRecovery<Transaction>(
      _transactionBoxName,
    );
  }

  // Bill operations
  static Future<void> addBill(
    Bill bill, {
    List<ReminderOffset>? reminderOffsets,
  }) async {
    try {
      await _billsBox.put(bill.id, bill);
      await _billsBox.flush();
    } catch (e) {
      if (_isBillTransactionTypeMismatch(e)) {
        await _reopenCoreBoxes();
        await _billsBox.put(bill.id, bill);
        await _billsBox.flush();
      } else {
        rethrow;
      }
    }
    await _removeDeletedBillId(bill.id);
    await clearBillRecurrenceEndOverride(bill.id);
    billsVersion.value++;
    final synced = await _safeAwsCall(
      () => AwsApiService.createBill(
        bill,
        reminderOffsets: reminderOffsets ?? _selectedReminderOffsetsForApi(),
      ),
      'create bill',
    );
    if (synced) {
      await _removeLocallyModifiedBillId(bill.id);
    } else {
      await _addLocallyModifiedBillId(bill.id);
    }
  }

  // Per-occurrence bill status helpers
  static String _occurrenceKey(String billId, DateTime date) {
    // Normalize to Y-M-D to avoid time portion differences
    return '${billId}_${date.year}-${date.month}-${date.day}';
  }

  /// Persist a per-occurrence paid flag and payment status.
  /// Stored in a simple box keyed by `${billId}_YYYY-M-D` with value
  /// {'isPaid': bool, 'paymentStatus': int}
  static Future<void> setBillOccurrenceStatus(
    String billId,
    DateTime date,
    bool isPaid,
    PaymentStatus status,
  ) async {
    final key = _occurrenceKey(billId, date);
    await _billOccurrenceBox.put(key, {
      'isPaid': isPaid,
      'paymentStatus': status.index,
    });
    await _billOccurrenceBox.flush();
    // Notify UI that bills have changed so calendars refresh
    billsVersion.value++;
  }

  /// Remove all persisted per-occurrence statuses for a bill.
  /// Useful when bill amount or recurrence changes so stale paid flags do not linger.
  static Future<void> clearBillOccurrenceStatusesForBill(String billId) async {
    final id = billId.trim();
    if (id.isEmpty) return;
    try {
      final keysToRemove = <dynamic>[];
      for (final key in _billOccurrenceBox.keys) {
        try {
          if (key is String && key.startsWith('${id}_')) {
            keysToRemove.add(key);
          }
        } catch (_) {}
      }
      if (keysToRemove.isEmpty) return;
      for (final key in keysToRemove) {
        await _billOccurrenceBox.delete(key);
      }
      await _billOccurrenceBox.flush();
      billsVersion.value++;
    } catch (_) {}
  }

  /// Return occurrence-level status if present. Null if no persisted occurrence record exists.
  static Map<String, dynamic>? getBillOccurrenceStatus(
    String billId,
    DateTime date,
  ) {
    final key = _occurrenceKey(billId, date);
    final v = _billOccurrenceBox.get(key);
    if (v == null) return null;
    try {
      final bool isPaid = v['isPaid'] as bool? ?? false;
      final int? rawIdx = v['paymentStatus'] as int?;
      PaymentStatus status;
      if (isPaid) {
        status = PaymentStatus.paid;
      } else if (rawIdx == null) {
        status = PaymentStatus.unpaid;
      } else {
        status = PaymentStatus
            .values[rawIdx.clamp(0, PaymentStatus.values.length - 1)];
      }
      return {'isPaid': isPaid, 'paymentStatus': status};
    } catch (_) {
      return null;
    }
  }

  static Future<void> updateBill(
    Bill bill, {
    List<ReminderOffset>? reminderOffsets,
  }) async {
    try {
      await _billsBox.put(bill.id, bill);
      await _billsBox.flush();
    } catch (e) {
      if (_isBillTransactionTypeMismatch(e)) {
        await _reopenCoreBoxes();
        await _billsBox.put(bill.id, bill);
        await _billsBox.flush();
      } else {
        rethrow;
      }
    }
    await _removeDeletedBillId(bill.id);
    await clearBillRecurrenceEndOverride(bill.id);
    billsVersion.value++;
    final synced = await _safeAwsCall(
      () => AwsApiService.updateBill(
        bill,
        reminderOffsets: reminderOffsets ?? _selectedReminderOffsetsForApi(),
      ),
      'update bill',
    );
    if (!synced) {
      await _addLocallyModifiedBillId(bill.id);
    }
  }

  static Future<void> deleteBill(String id) async {
    await _addDeletedBillId(id);
    await clearBillRecurrenceEndOverride(id);
    // Remove any per-occurrence status entries for this bill
    try {
      final keysToRemove = <dynamic>[];
      for (final key in _billOccurrenceBox.keys) {
        try {
          if (key is String && key.startsWith('${id}_')) keysToRemove.add(key);
        } catch (_) {}
      }
      for (final k in keysToRemove) {
        await _billOccurrenceBox.delete(k);
      }
      await _billOccurrenceBox.flush();
    } catch (_) {}

    // Delete any transactions that were recorded as payments for this bill.
    // This keeps the transaction list and payment history in sync when a
    // bill is removed. We also attempt to remove them from the hidden
    // transaction list so there are no dangling references.
    try {
      final related = _transactionBox.values
          .where((t) => t.billId == id)
          .toList();
      for (final tx in related) {
        try {
          await removeHiddenTransactionId(tx.id);
        } catch (_) {}
        await _addDeletedTransactionId(tx.id);
        await _transactionBox.delete(tx.id);
      }
      await _transactionBox.flush();
      // Notify transaction listeners that multiple items may have been removed
      transactionsVersion.value++;
    } catch (_) {}

    // Finally delete the bill itself
    await _billsBox.delete(id);
    await _billsBox.flush();
    billsVersion.value++;
    await _safeAwsCall(
      () => AwsApiService.deleteNotificationSchedulesForBill(id),
      'delete bill notification schedules',
    );
    await _safeAwsCall(() => AwsApiService.deleteBill(id), 'delete bill');
  }

  static List<Bill> getAllBills() {
    return _billsBox.values.toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  static Future<void> syncLocallyModifiedBills() async {
    if (!AwsApiService.isConfigured) return;
    final ids = _getLocallyModifiedBillIds();
    if (ids.isEmpty) return;

    for (final id in List<String>.from(ids)) {
      final bill = _billsBox.get(id);
      if (bill == null) {
        await _removeLocallyModifiedBillId(id);
        continue;
      }

      final synced = await _safeAwsCall(
        () => AwsApiService.updateBill(
          bill,
          reminderOffsets: _selectedReminderOffsetsForApi(),
        ),
        'retry bill update',
      );
      if (synced) {
        // Keep the local edit marked until the next remote hydrate confirms the
        // server copy has caught up. Otherwise a stale remote fetch can
        // overwrite the freshly edited local bill on app restart.
      }
    }
  }

  static bool _billMatches(Bill a, Bill b) {
    DateTime? normalize(DateTime? value) {
      if (value == null) return null;
      return DateTime(value.year, value.month, value.day);
    }

    bool listEquals(List<int>? left, List<int>? right) {
      if (left == null || right == null) return left == right;
      if (left.length != right.length) return false;
      for (var i = 0; i < left.length; i++) {
        if (left[i] != right[i]) return false;
      }
      return true;
    }

    return a.amount == b.amount &&
        a.description == b.description &&
        normalize(a.dueDate) == normalize(b.dueDate) &&
        a.recurrence == b.recurrence &&
        listEquals(a.customDays, b.customDays) &&
        normalize(a.recurrenceEndDate) == normalize(b.recurrenceEndDate) &&
        a.recurrenceInterval == b.recurrenceInterval &&
        listEquals(a.recurrenceWeekdays, b.recurrenceWeekdays) &&
        a.categoryId == b.categoryId &&
        a.type == b.type &&
        a.fromAccountId == b.fromAccountId &&
        a.toAccountId == b.toAccountId &&
        a.payeeId == b.payeeId &&
        a.accountId == b.accountId &&
        a.isPaid == b.isPaid &&
        a.paymentStatus == b.paymentStatus;
  }

  // Transaction operations
  static Future<void> addTransaction(Transaction transaction) async {
    await _transactionBox.put(transaction.id, transaction);
    // Ensure the transaction box is flushed so UI/readers see the new transaction
    // immediately and any persistence occurs if the app exits.
    await _transactionBox.flush();
    await _removeDeletedTransactionId(transaction.id);
    transactionsVersion.value++;
    await _safeAwsCall(
      () => AwsApiService.createTransaction(transaction),
      'create transaction',
    );
  }

  static Future<void> updateTransaction(Transaction transaction) async {
    final toPersist = transaction.copyWith(updatedAt: DateTime.now());
    // Capture previous value so we can update occurrence status if bill linkage
    // changed or if amount/date was edited.
    final Transaction? previous = _transactionBox.get(transaction.id);

    await _transactionBox.put(toPersist.id, toPersist);
    // Ensure the transaction box is flushed so readers (UI/listeners)
    // observe the updated value when transactionsVersion is incremented.
    await _transactionBox.flush();
    await _removeDeletedTransactionId(toPersist.id);
    transactionsVersion.value++;
    await _safeAwsCall(
      () => AwsApiService.updateTransaction(toPersist),
      'update transaction',
    );

    // Keep bill occurrence paid/partial/unpaid state synchronized whenever a
    // linked payment transaction is edited from any screen.
    try {
      final affectedBillIds = <String>{};
      if (previous?.billId != null && previous!.billId!.isNotEmpty) {
        affectedBillIds.add(previous.billId!);
      }
      if (toPersist.billId != null && toPersist.billId!.isNotEmpty) {
        affectedBillIds.add(toPersist.billId!);
      }

      for (final billId in affectedBillIds) {
        final bill = _billsBox.get(billId);
        if (bill == null) continue;

        final allTx = getAllTransactions();
        final occDates = <DateTime>{};

        void addDatesFromText(String? text) {
          if (text == null || text.trim().isEmpty) return;
          final raw = text.trim();
          final matches = <String>{};
          final longMatch = RegExp(
            r'(0[1-9]|1[0-2])/(0[1-9]|[12][0-9]|3[01])/\d{4}',
          ).allMatches(raw);
          for (final match in longMatch) {
            matches.add(match.group(0)!);
          }
          final shortMatch = RegExp(
            r'(0?[1-9]|1[0-2])/(0?[1-9]|[12][0-9]|3[01])/\d{2}',
          ).allMatches(raw);
          for (final match in shortMatch) {
            matches.add(match.group(0)!);
          }
          for (final token in matches) {
            try {
              final parsed = DateFormat('MM/dd/yyyy').parseLoose(token);
              occDates.add(DateTime(parsed.year, parsed.month, parsed.day));
            } catch (_) {
              try {
                final parsed = DateFormat('MM/dd/yy').parseLoose(token);
                occDates.add(DateTime(parsed.year, parsed.month, parsed.day));
              } catch (_) {}
            }
          }
        }

        void addOccSeed(
          DateTime? occDate,
          DateTime? date,
          String? description,
          String? paymentFor,
        ) {
          if (occDate != null) {
            occDates.add(DateTime(occDate.year, occDate.month, occDate.day));
            return;
          }
          if (date != null) {
            occDates.add(DateTime(date.year, date.month, date.day));
            return;
          }
          addDatesFromText(description);
          addDatesFromText(paymentFor);
        }

        if (previous?.billId == billId) {
          addOccSeed(
            previous!.occurrenceDate,
            previous.date,
            previous.description,
            previous.paymentFor,
          );
        }
        if (toPersist.billId == billId) {
          addOccSeed(
            toPersist.occurrenceDate,
            toPersist.date,
            toPersist.description,
            toPersist.paymentFor,
          );
        }

        for (final t in allTx) {
          if (t.billId != billId) continue;
          if (t.occurrenceDate != null) {
            occDates.add(
              DateTime(
                t.occurrenceDate!.year,
                t.occurrenceDate!.month,
                t.occurrenceDate!.day,
              ),
            );
          } else {
            occDates.add(DateTime(t.date.year, t.date.month, t.date.day));
          }
        }

        for (final occ in occDates) {
          final occDateStr = DateFormat('MM/dd/yyyy').format(occ);
          final occDateShort = DateFormat('MM/dd/yy').format(occ);
          double totalPaid = 0.0;

          for (final t in allTx) {
            if (t.billId != billId) continue;
            final matchesOccurrence = (t.occurrenceDate != null)
                ? (t.occurrenceDate!.year == occ.year &&
                      t.occurrenceDate!.month == occ.month &&
                      t.occurrenceDate!.day == occ.day)
                : ((t.date.year == occ.year &&
                          t.date.month == occ.month &&
                          t.date.day == occ.day) ||
                      t.description.contains(occDateStr) ||
                      t.description.contains(occDateShort) ||
                      (t.paymentFor ?? '').contains(occDateStr) ||
                      (t.paymentFor ?? '').contains(occDateShort));
            if (!matchesOccurrence) continue;

            if (bill.type == BillType.expense) {
              totalPaid += (t.type == TransactionType.expense)
                  ? t.amount
                  : -t.amount;
            } else {
              totalPaid += (t.type == TransactionType.income)
                  ? t.amount
                  : -t.amount;
            }
          }

          PaymentStatus newStatus;
          if (totalPaid <= 0) {
            newStatus = PaymentStatus.unpaid;
          } else if (totalPaid >= (bill.amount - 0.01)) {
            newStatus = PaymentStatus.paid;
          } else {
            newStatus = PaymentStatus.partial;
          }

          await setBillOccurrenceStatus(
            billId,
            occ,
            newStatus == PaymentStatus.paid,
            newStatus,
          );
        }
      }
    } catch (_) {
      // Non-critical: do not block transaction edits if status sync fails.
    }
  }

  /// One-time best-effort migration for legacy account-context transactions.
  ///
  /// Older records created from account-specific transaction views may have
  /// missed the boolean hide flag. This migration backfills both the
  /// `hideFromCalendarDashboard` flag and the note marker so dashboard
  /// filtering is robust.
  static Future<int> migrateLegacyAccountTransactionsHiddenFromCalendar({
    bool force = false,
  }) async {
    final alreadyMigrated =
        getSetting<bool>(_legacyAccountCalendarMigrationKey, false) ?? false;
    if (!force && alreadyMigrated) return 0;

    int updatedCount = 0;
    for (final tx in _transactionBox.values) {
      if (tx.hideFromCalendarDashboard == true) continue;
      if (tx.billId != null && tx.billId!.isNotEmpty) continue;

      final note = tx.note ?? '';
      final lowerNote = note.toLowerCase();
      final looksLikeAccountContext =
          lowerNote.contains('account:') ||
          note.contains(_hideFromCalendarMarker);
      if (!looksLikeAccountContext) continue;

      final nextNote = note.contains(_hideFromCalendarMarker)
          ? note
          : (note.trim().isEmpty
                ? _hideFromCalendarMarker
                : '$note $_hideFromCalendarMarker');

      final updated = tx.copyWith(
        hideFromCalendarDashboard: true,
        note: nextNote,
        updatedAt: DateTime.now(),
      );

      await _transactionBox.put(updated.id, updated);
      updatedCount++;
    }

    if (updatedCount > 0) {
      await _transactionBox.flush();
      transactionsVersion.value++;
    }

    if (!force) {
      await setSetting(_legacyAccountCalendarMigrationKey, true);
    }
    return updatedCount;
  }

  /// Force-hide all non-bill transactions for a specific account from the
  /// dashboard calendar/list. This is used as a targeted repair for account-
  /// scoped transaction flows where older entries may have been saved before
  /// hide markers were consistently applied.
  static Future<int> hideTransactionsForAccountFromDashboard(
    String accountId,
  ) async {
    final normalized = accountId.trim();
    if (normalized.isEmpty) return 0;

    int updatedCount = 0;
    for (final tx in _transactionBox.values) {
      if ((tx.accountId ?? '').trim() != normalized) continue;
      if (tx.billId != null && tx.billId!.isNotEmpty) continue;
      if (tx.hideFromCalendarDashboard == true) continue;

      final note = tx.note ?? '';
      final nextNote = note.contains(_hideFromCalendarMarker)
          ? note
          : (note.trim().isEmpty
                ? _hideFromCalendarMarker
                : '$note $_hideFromCalendarMarker');

      await _transactionBox.put(
        tx.id,
        tx.copyWith(
          hideFromCalendarDashboard: true,
          note: nextNote,
          updatedAt: DateTime.now(),
        ),
      );
      updatedCount++;
    }

    if (updatedCount > 0) {
      await _transactionBox.flush();
      transactionsVersion.value++;
    }
    return updatedCount;
  }

  static bool _looksLikeOpaqueId(String value) {
    final v = value.trim();
    if (v.isEmpty) return false;
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    if (uuid.hasMatch(v)) return true;
    final longToken = RegExp(r'^[A-Za-z0-9_-]{16,}$');
    return longToken.hasMatch(v) && !v.contains(' ');
  }

  static String? _extractCounterpartyFromPaymentDescription(
    String description,
  ) {
    final trimmed = description.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.toLowerCase().startsWith('payment for ')) return null;

    var raw = trimmed.substring('payment for '.length).trim();
    if (raw.isEmpty) return null;

    // Strip trailing date patterns from legacy descriptions.
    raw = raw
        .replaceFirst(RegExp(r'\s*\(\d{1,2}/\d{1,2}/\d{2,4}\)\s*$'), '')
        .trim();
    raw = raw
        .replaceFirst(RegExp(r'\s+\d{1,2}/\d{1,2}/\d{2,4}\s*$'), '')
        .trim();
    return raw.isEmpty ? null : raw;
  }

  static DateTime? _extractDateFromPaymentDescription(String description) {
    final trimmed = description.trim();
    if (trimmed.isEmpty) return null;

    final match = RegExp(r'(\d{1,2}/\d{1,2}/\d{2,4})').firstMatch(trimmed);
    if (match == null) return null;

    final raw = match.group(1);
    if (raw == null) return null;

    DateTime? parsed;
    try {
      parsed = DateFormat('MM/dd/yyyy').parseStrict(raw);
    } catch (_) {
      try {
        parsed = DateFormat('M/d/yyyy').parseStrict(raw);
      } catch (_) {
        try {
          parsed = DateFormat('MM/dd/yy').parseStrict(raw);
        } catch (_) {
          try {
            parsed = DateFormat('M/d/yy').parseStrict(raw);
          } catch (_) {
            parsed = null;
          }
        }
      }
    }
    return parsed;
  }

  /// One-time backfill for legacy payment transactions so [Transaction.paymentFor]
  /// is available for historical entries.
  static Future<int> migrateLegacyTransactionPaymentFor({
    bool force = false,
  }) async {
    final alreadyMigrated =
        getSetting<bool>(_legacyPaymentForMigrationKey, false) ?? false;
    if (!force && alreadyMigrated) return 0;

    final contacts = getAllPayees();
    int updatedCount = 0;

    for (final tx in _transactionBox.values) {
      final existing = (tx.paymentFor ?? '').trim();
      if (existing.isNotEmpty) continue;

      final hasPaymentDescription = tx.description
          .trim()
          .toLowerCase()
          .startsWith('payment for ');
      final hasBillLink = tx.billId != null && tx.billId!.trim().isNotEmpty;
      if (!hasPaymentDescription && !hasBillLink) continue;

      final DateTime baseDate =
          tx.occurrenceDate ??
          _extractDateFromPaymentDescription(tx.description) ??
          tx.date;
      final dateText = DateFormat('MM/dd/yy').format(baseDate);

      String counterparty = (tx.payeeName ?? '').trim();
      if (counterparty.isEmpty) {
        counterparty = (tx.payerName ?? '').trim();
      }

      if (counterparty.isEmpty) {
        final contactId = (tx.payeeId ?? tx.payerId ?? '').trim();
        if (contactId.isNotEmpty) {
          final match = contacts.where(
            (c) => (c['id'] ?? '').toString().trim() == contactId,
          );
          if (match.isNotEmpty) {
            counterparty = (match.first['name'] ?? '').toString().trim();
          }
        }
      }

      if (counterparty.isEmpty) {
        counterparty =
            _extractCounterpartyFromPaymentDescription(tx.description) ??
            'Unknown';
      }

      String category = (tx.categoryName ?? '').trim();
      if (category.isEmpty || _looksLikeOpaqueId(category)) {
        final categoryId = tx.categoryId.trim();
        if (categoryId.isNotEmpty) {
          final cat = _categoryBox.get(categoryId);
          final catName = (cat?.name ?? '').trim();
          if (catName.isNotEmpty && !_looksLikeOpaqueId(catName)) {
            category = catName;
          }
        }
      }
      if (category.isEmpty) {
        category = 'Uncategorized';
      }

      final paymentFor = '$dateText $counterparty $category'
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (paymentFor.isEmpty) continue;

      await _transactionBox.put(
        tx.id,
        tx.copyWith(paymentFor: paymentFor, updatedAt: DateTime.now()),
      );
      updatedCount++;
    }

    if (updatedCount > 0) {
      await _transactionBox.flush();
      transactionsVersion.value++;
    }

    if (!force) {
      await setSetting(_legacyPaymentForMigrationKey, true);
    }
    return updatedCount;
  }

  /// One-time best-effort migration to ensure transactions display category
  /// names (not raw category IDs) in dashboard and account transaction lists.
  static Future<int> migrateLegacyTransactionCategoryNames({
    bool force = false,
  }) async {
    final alreadyMigrated =
        getSetting<bool>(_legacyCategoryNameMigrationKey, false) ?? false;
    if (!force && alreadyMigrated) return 0;

    int updatedCount = 0;
    for (final tx in _transactionBox.values) {
      final existingName = (tx.categoryName ?? '').trim();
      final hasFriendlyName =
          existingName.isNotEmpty && !_looksLikeOpaqueId(existingName);
      if (hasFriendlyName) continue;

      String? nextCategoryName;
      final categoryId = tx.categoryId.trim();
      if (categoryId.isNotEmpty) {
        final cat = _categoryBox.get(categoryId);
        final candidate = (cat?.name ?? '').trim();
        if (candidate.isNotEmpty && !_looksLikeOpaqueId(candidate)) {
          nextCategoryName = candidate;
        }
      }

      if (nextCategoryName == null &&
          existingName.isNotEmpty &&
          _looksLikeOpaqueId(existingName)) {
        nextCategoryName = 'Unknown Category';
      }

      if (nextCategoryName == null || nextCategoryName == existingName) {
        continue;
      }

      await _transactionBox.put(
        tx.id,
        tx.copyWith(categoryName: nextCategoryName, updatedAt: DateTime.now()),
      );
      updatedCount++;
    }

    if (updatedCount > 0) {
      await _transactionBox.flush();
      transactionsVersion.value++;
    }

    if (!force) {
      await setSetting(_legacyCategoryNameMigrationKey, true);
    }
    return updatedCount;
  }

  /// One-time best-effort migration to repair legacy transaction category
  /// linkage for old records that may show as `Unknown` in list views.
  ///
  /// Repairs include:
  /// - Trimming whitespace around categoryId
  /// - Re-linking by category name when categoryId is missing/invalid
  /// - Resolving cases where categoryName accidentally stored an ID
  /// - Refreshing categoryName from the resolved category record
  static Future<int> migrateLegacyTransactionCategoryResolution({
    bool force = false,
  }) async {
    final alreadyMigrated =
        getSetting<bool>(_legacyCategoryResolutionMigrationKey, false) ?? false;
    if (!force && alreadyMigrated) return 0;

    int updatedCount = 0;
    final categories = _categoryBox.values.toList();
    final nameToCategory = <String, Category>{};
    for (final c in categories) {
      final key = c.name.trim().toLowerCase();
      if (key.isNotEmpty) {
        nameToCategory.putIfAbsent(key, () => c);
      }
    }

    for (final tx in _transactionBox.values) {
      final originalId = tx.categoryId;
      final originalName = tx.categoryName;

      String resolvedId = originalId.trim();
      String? resolvedName = originalName?.trim();
      if (resolvedName != null && resolvedName.isEmpty) resolvedName = null;

      Category? resolvedCategory;
      if (resolvedId.isNotEmpty) {
        resolvedCategory = _categoryBox.get(resolvedId);
      }

      // If the saved categoryName is actually an ID, resolve it.
      if (resolvedCategory == null &&
          resolvedName != null &&
          _looksLikeOpaqueId(resolvedName)) {
        final byNameAsId = _categoryBox.get(resolvedName);
        if (byNameAsId != null) {
          resolvedCategory = byNameAsId;
          resolvedId = byNameAsId.id;
          resolvedName = byNameAsId.name;
        }
      }

      // If ID is invalid/missing, try to resolve by friendly categoryName.
      if (resolvedCategory == null && resolvedName != null) {
        final byFriendlyName = nameToCategory[resolvedName.toLowerCase()];
        if (byFriendlyName != null) {
          resolvedCategory = byFriendlyName;
          resolvedId = byFriendlyName.id;
          resolvedName = byFriendlyName.name;
        }
      }

      // If we have a valid category, ensure display name matches latest name.
      if (resolvedCategory != null) {
        resolvedId = resolvedCategory.id;
        resolvedName = resolvedCategory.name;
      }

      final idChanged = resolvedId != originalId;
      final nameChanged = (resolvedName ?? '') != ((originalName ?? '').trim());
      if (!idChanged && !nameChanged) continue;

      await _transactionBox.put(
        tx.id,
        tx.copyWith(
          categoryId: resolvedId,
          categoryName: resolvedName,
          updatedAt: DateTime.now(),
        ),
      );
      updatedCount++;
    }

    if (updatedCount > 0) {
      await _transactionBox.flush();
      transactionsVersion.value++;
    }

    if (!force) {
      await setSetting(_legacyCategoryResolutionMigrationKey, true);
    }
    return updatedCount;
  }

  static DateTime? _earliestDate(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isBefore(b) ? a : b;
  }

  static DateTime _addCalendarDays(DateTime date, int days) {
    return DateTime(date.year, date.month, date.day + days);
  }

  static List<DateTime> generateBillOccurrenceDatesForRange(
    Bill bill,
    DateTime startDate,
    DateTime endDate, {
    DateTime? recurrenceEndOverride,
  }) {
    final normalizedStart = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );
    final normalizedEnd = DateTime(endDate.year, endDate.month, endDate.day);
    final effectiveRecurrenceEndDate = bill.recurrence == Recurrence.none
        ? null
        : _earliestDate(recurrenceEndOverride, bill.recurrenceEndDate);
    final out = <DateTime>[];
    final seen = <String>{};

    if (effectiveRecurrenceEndDate != null &&
        effectiveRecurrenceEndDate.isBefore(normalizedStart)) {
      return out;
    }

    void addIfInRange(DateTime rawDate) {
      final occ = DateTime(rawDate.year, rawDate.month, rawDate.day);
      if (occ.isBefore(normalizedStart) || occ.isAfter(normalizedEnd)) return;
      final key = '${occ.year}-${occ.month}-${occ.day}';
      if (!seen.add(key)) return;
      out.add(occ);
    }

    switch (bill.recurrence) {
      case Recurrence.none:
        addIfInRange(
          DateTime(bill.dueDate.year, bill.dueDate.month, bill.dueDate.day),
        );
        break;
      case Recurrence.daily:
        final interval = bill.recurrenceInterval <= 0
            ? 1
            : bill.recurrenceInterval;
        var cur = DateTime(
          bill.dueDate.year,
          bill.dueDate.month,
          bill.dueDate.day,
        );
        while (!(effectiveRecurrenceEndDate != null &&
                cur.isAfter(effectiveRecurrenceEndDate)) &&
            !cur.isAfter(normalizedEnd)) {
          addIfInRange(cur);
          cur = _addCalendarDays(cur, interval);
        }
        break;
      case Recurrence.weekly:
        final intervalWeeks = bill.recurrenceInterval <= 0
            ? 1
            : bill.recurrenceInterval;
        final weekdays =
            ((bill.recurrenceWeekdays == null ||
                        bill.recurrenceWeekdays!.isEmpty)
                    ? <int>[bill.dueDate.weekday]
                    : bill.recurrenceWeekdays!)
                .where((weekday) => weekday >= 1 && weekday <= 7)
                .toSet()
                .toList()
              ..sort();

        final due = DateTime(
          bill.dueDate.year,
          bill.dueDate.month,
          bill.dueDate.day,
        );
        if (due.isAfter(normalizedEnd)) break;

        final dueWeekStart = _addCalendarDays(due, -(due.weekday - 1));
        var cycle = 0;
        while (true) {
          final weekStart = _addCalendarDays(
            dueWeekStart,
            7 * intervalWeeks * cycle,
          );
          if (weekStart.isAfter(normalizedEnd)) break;
          if (effectiveRecurrenceEndDate != null &&
              weekStart.isAfter(effectiveRecurrenceEndDate)) {
            break;
          }

          for (final weekday in weekdays) {
            final occ = _addCalendarDays(weekStart, weekday - 1);
            if (occ.isBefore(due)) continue;
            if (effectiveRecurrenceEndDate != null &&
                occ.isAfter(effectiveRecurrenceEndDate)) {
              continue;
            }
            addIfInRange(occ);
          }
          cycle++;
        }
        break;
      case Recurrence.monthly:
        final intervalMonths = bill.recurrenceInterval <= 0
            ? 1
            : bill.recurrenceInterval;
        final days =
            ((bill.customDays == null || bill.customDays!.isEmpty)
                    ? <int>[bill.dueDate.day]
                    : bill.customDays!)
                .toSet()
                .toList()
              ..sort();
        final billStartDate = DateTime(
          bill.dueDate.year,
          bill.dueDate.month,
          bill.dueDate.day,
        );
        var currentYear = bill.dueDate.year;
        var currentMonth = bill.dueDate.month;
        while (true) {
          final monthStart = DateTime(currentYear, currentMonth, 1);
          if (monthStart.isAfter(normalizedEnd)) break;
          if (effectiveRecurrenceEndDate != null &&
              monthStart.isAfter(effectiveRecurrenceEndDate)) {
            break;
          }
          for (final configuredDay in days) {
            final day = configuredDay == 99
                ? DateTime(currentYear, currentMonth + 1, 0).day
                : configuredDay;
            final lastDay = DateTime(currentYear, currentMonth + 1, 0).day;
            if (day < 1 || day > lastDay) continue;
            final occ = DateTime(currentYear, currentMonth, day);
            if (occ.isBefore(billStartDate)) continue;
            if (effectiveRecurrenceEndDate != null &&
                occ.isAfter(effectiveRecurrenceEndDate)) {
              continue;
            }
            addIfInRange(occ);
          }
          currentMonth += intervalMonths;
          while (currentMonth > 12) {
            currentMonth -= 12;
            currentYear += 1;
          }
        }
        break;
      case Recurrence.yearly:
        final intervalYears = bill.recurrenceInterval <= 0
            ? 1
            : bill.recurrenceInterval;
        var cur = DateTime(
          bill.dueDate.year,
          bill.dueDate.month,
          bill.dueDate.day,
        );
        while (!(effectiveRecurrenceEndDate != null &&
                cur.isAfter(effectiveRecurrenceEndDate)) &&
            !cur.isAfter(normalizedEnd)) {
          addIfInRange(cur);
          cur = DateTime(cur.year + intervalYears, cur.month, cur.day);
        }
        break;
      case Recurrence.custom:
        addIfInRange(
          DateTime(bill.dueDate.year, bill.dueDate.month, bill.dueDate.day),
        );
        break;
    }

    out.sort();
    return out;
  }

  static bool _billOccursOnDate(
    Bill bill,
    DateTime date, {
    DateTime? effectiveEndDate,
  }) {
    final target = DateTime(date.year, date.month, date.day);
    return generateBillOccurrenceDatesForRange(
      bill,
      target,
      target,
      recurrenceEndOverride: effectiveEndDate,
    ).isNotEmpty;
  }

  static String _normalizedBillName(Bill bill) {
    return (bill.description ?? '').trim().toLowerCase();
  }

  static bool _sameIntListValues(List<int>? a, List<int>? b) {
    final left = (a ?? <int>[]).toList()..sort();
    final right = (b ?? <int>[]).toList()..sort();
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  static bool _sameBillSchedule(Bill a, Bill b) {
    return a.recurrence == b.recurrence &&
        a.recurrenceInterval == b.recurrenceInterval &&
        _sameIntListValues(a.customDays, b.customDays) &&
        _sameIntListValues(a.recurrenceWeekdays, b.recurrenceWeekdays);
  }

  static bool _hasAmbiguousLegacyBillNameMatch(
    Bill bill,
    DateTime occurrenceDate,
    Iterable<Bill> candidates,
  ) {
    final billName = _normalizedBillName(bill);
    if (billName.isEmpty || billName == 'bill') return false;

    for (final candidate in candidates) {
      if (candidate.id == bill.id) continue;
      if (_normalizedBillName(candidate) != billName) continue;
      if (_sameBillSchedule(candidate, bill)) continue;
      if (!_billOccursOnDate(candidate, occurrenceDate)) continue;
      return true;
    }

    return false;
  }

  static String _recurringBillSignature(Bill bill) {
    final customDays = (bill.customDays ?? <int>[]).toList()..sort();
    final weekdays = (bill.recurrenceWeekdays ?? <int>[]).toList()..sort();
    return [
      (bill.description ?? '').trim().toLowerCase(),
      bill.type.name,
      bill.amount.toStringAsFixed(4),
      bill.categoryId ?? '',
      bill.payeeId ?? '',
      bill.accountId ?? '',
      bill.fromAccountId ?? '',
      bill.toAccountId ?? '',
      bill.recurrence.name,
      bill.recurrenceInterval.toString(),
      customDays.join(','),
      weekdays.join(','),
    ].join('|');
  }

  /// One-time migration to repair legacy recurring-series splits where both
  /// the old and new series may still generate the same occurrence date.
  static Future<int> migrateLegacyRecurringBillSplitOverlaps({
    bool force = false,
  }) async {
    final alreadyMigrated =
        getSetting<bool>(_legacyRecurringSplitOverlapMigrationKey, false) ??
        false;
    if (!force && alreadyMigrated) return 0;

    final overrides = _getBillRecurrenceEndOverrides();
    final recurringBills = _billsBox.values
        .where((b) => b.recurrence != Recurrence.none)
        .toList();
    final grouped = <String, List<Bill>>{};
    for (final bill in recurringBills) {
      if ((bill.description ?? '').trim().isEmpty) continue;
      final signature = _recurringBillSignature(bill);
      grouped.putIfAbsent(signature, () => <Bill>[]).add(bill);
    }

    int updatedCount = 0;

    for (final entry in grouped.entries) {
      final bills = entry.value..sort((a, b) => a.dueDate.compareTo(b.dueDate));
      if (bills.length < 2) continue;

      for (int i = 0; i < bills.length - 1; i++) {
        var older = bills[i];
        final newer = bills[i + 1];

        final newerStart = DateTime(
          newer.dueDate.year,
          newer.dueDate.month,
          newer.dueDate.day,
        );
        final olderEffectiveEnd = _earliestDate(
          overrides[older.id],
          older.recurrenceEndDate,
        );

        if (!_billOccursOnDate(
          older,
          newerStart,
          effectiveEndDate: olderEffectiveEnd,
        )) {
          continue;
        }

        final cutoff = _addCalendarDays(newerStart, -1);
        final normalizedCutoff = DateTime(
          cutoff.year,
          cutoff.month,
          cutoff.day,
        );
        final normalizedOlderEnd = olderEffectiveEnd == null
            ? null
            : DateTime(
                olderEffectiveEnd.year,
                olderEffectiveEnd.month,
                olderEffectiveEnd.day,
              );

        if (normalizedOlderEnd != null &&
            !normalizedOlderEnd.isAfter(normalizedCutoff)) {
          continue;
        }

        if (older.recurrenceEndDate == null ||
            older.recurrenceEndDate!.isAfter(normalizedCutoff)) {
          older = older.copyWith(recurrenceEndDate: normalizedCutoff);
          await _billsBox.put(older.id, older);
          bills[i] = older;
          updatedCount++;
        }

        overrides[older.id] = normalizedCutoff;
      }
    }

    if (updatedCount > 0) {
      await _billsBox.flush();
      billsVersion.value++;
    }

    final encoded = <String, String>{
      for (final e in overrides.entries) e.key: e.value.toIso8601String(),
    };
    await _settingsBox.put(_billRecurrenceEndOverridesKey, encoded);
    await _settingsBox.flush();

    if (!force) {
      await setSetting(_legacyRecurringSplitOverlapMigrationKey, true);
    }
    return updatedCount;
  }

  /// Runs the recurring split overlap repair without migration gating.
  /// Safe to call repeatedly; only applies changes when overlaps exist.
  static Future<int> repairRecurringBillSplitOverlaps() async {
    return migrateLegacyRecurringBillSplitOverlaps(force: true);
  }

  static Future<void> runPostFixRecurringSplitRepairIfNeeded() async {
    final alreadyRan =
        getSetting<bool>(_postFixRecurringSplitRepairKey, false) ?? false;
    if (alreadyRan) return;
    try {
      await repairRecurringBillSplitOverlaps();
    } finally {
      await setSetting(_postFixRecurringSplitRepairKey, true);
    }
  }

  static Future<int> migrateLegacyBillPlaceholderText({
    bool force = false,
  }) async {
    final alreadyMigrated =
        getSetting<bool>(_legacyBillPlaceholderTextMigrationKey, false) ??
        false;
    if (!force && alreadyMigrated) return 0;

    int updatedCount = 0;

    for (final bill in _billsBox.values) {
      final description = (bill.description ?? '').trim();
      if (description.toLowerCase() != 'bill') continue;

      final updatedBill = bill.copyWith(description: null);
      await _billsBox.put(updatedBill.id, updatedBill);
      updatedCount++;
    }

    for (final tx in _transactionBox.values) {
      final desc = tx.description.trim();
      String? updatedDescription;

      if (desc.toLowerCase() == 'bill') {
        updatedDescription = 'Payment';
      } else {
        final match = RegExp(
          r'^payment\s+for\s+bill\b\s*(.*)$',
          caseSensitive: false,
        ).firstMatch(desc);
        if (match != null) {
          final suffix = (match.group(1) ?? '').trim();
          updatedDescription = suffix.isEmpty
              ? 'Payment'
              : 'Payment for $suffix';
        }
      }

      if (updatedDescription == null || updatedDescription == tx.description) {
        continue;
      }

      final updatedTx = tx.copyWith(
        description: updatedDescription,
        updatedAt: DateTime.now(),
      );
      await _transactionBox.put(updatedTx.id, updatedTx);
      updatedCount++;
    }

    if (updatedCount > 0) {
      await _billsBox.flush();
      await _transactionBox.flush();
      billsVersion.value++;
      transactionsVersion.value++;
    }

    if (!force) {
      await setSetting(_legacyBillPlaceholderTextMigrationKey, true);
    }

    return updatedCount;
  }

  static Future<void> deleteTransaction(String id) async {
    // Read the transaction before deleting so we can update any linked
    // bill occurrence status if this transaction represented a bill payment.
    final Transaction? tx = _transactionBox.get(id);
    DateTime? txOccDate;
    DateTime? txDate;
    String? txDescription;
    if (tx != null) {
      txOccDate = tx.occurrenceDate;
      txDate = tx.date;
      txDescription = tx.description;
    }

    await _addDeletedTransactionId(id);
    await _transactionBox.delete(id);
    // Flush so the deletion is persisted and any subsequent reads from
    // the Hive box return the updated set of transactions. Notify
    // listeners only after flush so UI can rebuild with the latest data.
    await _transactionBox.flush();
    transactionsVersion.value++;
    await _safeAwsCall(
      () => AwsApiService.deleteTransaction(id),
      'delete transaction',
    );

    // If this transaction was linked to a bill, recompute the per-occurrence
    // paid totals for the affected occurrence(s) and persist the new status.
    try {
      final allTx = getAllTransactions();
      final bills = _billsBox.values.toList();
      final affectedDates = <DateTime>{};

      void addAffectedDate(DateTime? sourceDate) {
        if (sourceDate == null) return;
        affectedDates.add(
          DateTime(sourceDate.year, sourceDate.month, sourceDate.day),
        );
      }

      void addDatesFromText(String? text) {
        if (text == null || text.trim().isEmpty) return;
        final raw = text.trim();
        final matches = <String>{};
        final longMatch = RegExp(
          r'(0[1-9]|1[0-2])/(0[1-9]|[12][0-9]|3[01])/\d{4}',
        ).allMatches(raw);
        for (final match in longMatch) {
          matches.add(match.group(0)!);
        }
        final shortMatch = RegExp(
          r'(0?[1-9]|1[0-2])/(0?[1-9]|[12][0-9]|3[01])/\d{2}',
        ).allMatches(raw);
        for (final match in shortMatch) {
          matches.add(match.group(0)!);
        }
        for (final token in matches) {
          try {
            final parsed = DateFormat('MM/dd/yyyy').parseLoose(token);
            addAffectedDate(parsed);
          } catch (_) {
            try {
              final parsed = DateFormat('MM/dd/yy').parseLoose(token);
              addAffectedDate(parsed);
            } catch (_) {}
          }
        }
      }

      addAffectedDate(txOccDate);
      addAffectedDate(txDate);
      addDatesFromText(txDescription);
      addDatesFromText(tx is Transaction ? tx.paymentFor : null);

      bool matchesBillOccurrence(
        Transaction candidate,
        Bill bill,
        DateTime occ,
      ) {
        final sameOcc = (candidate.occurrenceDate != null)
            ? (candidate.occurrenceDate!.year == occ.year &&
                  candidate.occurrenceDate!.month == occ.month &&
                  candidate.occurrenceDate!.day == occ.day)
            : ((candidate.date.year == occ.year &&
                      candidate.date.month == occ.month &&
                      candidate.date.day == occ.day) ||
                  candidate.description.contains(
                    DateFormat('MM/dd/yyyy').format(occ),
                  ) ||
                  candidate.description.contains(
                    DateFormat('MM/dd/yy').format(occ),
                  ) ||
                  (candidate.paymentFor ?? '').contains(
                    DateFormat('MM/dd/yyyy').format(occ),
                  ) ||
                  (candidate.paymentFor ?? '').contains(
                    DateFormat('MM/dd/yy').format(occ),
                  ));

        if (!sameOcc) return false;

        final candidateBillId = candidate.billId?.trim() ?? '';
        if (candidateBillId.isNotEmpty) {
          return candidateBillId == bill.id;
        }

        if (_hasAmbiguousLegacyBillNameMatch(bill, occ, bills)) {
          return false;
        }

        // Legacy/partial link: allow paymentFor-based matches to keep old bill
        // history entries and account transactions synchronized.
        final paymentFor = (candidate.paymentFor ?? '').trim().toLowerCase();
        final description = candidate.description.trim().toLowerCase();
        if (paymentFor.isEmpty && description.isEmpty) return false;

        final billName = (bill.description ?? '').trim().toLowerCase();
        final billPayee = bill.payeeId?.trim().toLowerCase() ?? '';
        final billAccountId = bill.accountId?.trim().toLowerCase() ?? '';
        final billFromAccountId =
            bill.fromAccountId?.trim().toLowerCase() ?? '';
        final billToAccountId = bill.toAccountId?.trim().toLowerCase() ?? '';

        bool textMatchesBill = false;
        if (billName.isNotEmpty && billName != 'bill') {
          textMatchesBill =
              paymentFor.contains(billName) || description.contains(billName);
        }
        if (!textMatchesBill && billPayee.isNotEmpty) {
          textMatchesBill =
              paymentFor.contains(billPayee) || description.contains(billPayee);
        }
        if (!textMatchesBill && billAccountId.isNotEmpty) {
          textMatchesBill =
              candidate.accountId?.trim().toLowerCase() == billAccountId;
        }
        if (!textMatchesBill && billFromAccountId.isNotEmpty) {
          textMatchesBill =
              candidate.accountId?.trim().toLowerCase() == billFromAccountId;
        }
        if (!textMatchesBill && billToAccountId.isNotEmpty) {
          textMatchesBill =
              candidate.accountId?.trim().toLowerCase() == billToAccountId;
        }

        return textMatchesBill;
      }

      for (final occ in affectedDates) {
        for (final bill in bills) {
          // Only recompute bills that plausibly occur on this date.
          if (!_billOccursOnDate(bill, occ)) continue;

          double totalPaid = 0.0;
          for (final t in allTx) {
            if (!matchesBillOccurrence(t, bill, occ)) continue;

            if (bill.type == BillType.expense) {
              totalPaid += (t.type == TransactionType.expense)
                  ? t.amount
                  : -t.amount;
            } else {
              totalPaid += (t.type == TransactionType.income)
                  ? t.amount
                  : -t.amount;
            }
          }

          PaymentStatus newStatus;
          if (totalPaid <= 0) {
            newStatus = PaymentStatus.unpaid;
          } else if (totalPaid >= (bill.amount - 0.01)) {
            newStatus = PaymentStatus.paid;
          } else {
            newStatus = PaymentStatus.partial;
          }

          await setBillOccurrenceStatus(
            bill.id,
            occ,
            newStatus == PaymentStatus.paid,
            newStatus,
          );
        }
      }
    } catch (_) {
      // Non-critical: don't block deletion on status update errors
    }
  }

  static List<Transaction> getAllTransactions() {
    return _transactionBox.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  static Future<void> init() async {
    // Use application support directory for Hive files to keep them hidden from users
    final supportDir = await getApplicationSupportDirectory();
    final hiveDir = Directory('${supportDir.path}/.hive');
    final migratedTransactionsFile = File('${hiveDir.path}/transactions.hive');
    await hiveDir.create(recursive: true);

    // Migrate from old location if exists
    final docsDir = await getApplicationDocumentsDirectory();
    final oldHiveDir = Directory('${docsDir.path}/CashSense/.hive');
    if (await oldHiveDir.exists() && !await migratedTransactionsFile.exists()) {
      // Copy old files to new location
      try {
        await for (final file in oldHiveDir.list()) {
          if (file is File) {
            final newFile = File(
              '${hiveDir.path}/${file.uri.pathSegments.last}',
            );
            await file.copy(newFile.path);
          }
        }
        // Optionally delete old directory after successful copy
        await oldHiveDir.delete(recursive: true);
      } catch (e) {
        foundation.debugPrint('Failed to migrate Hive files: $e');
      }
    }

    Hive.init(hiveDir.path);

    // Register adapters (safe across retries/restarts in same process)
    _registerHiveAdapters();

    // Open boxes with recovery for corrupted/legacy data.
    _transactionBox = await _openTypedBoxWithRecovery<Transaction>(
      _transactionBoxName,
    );
    _categoryBox = await _openTypedBoxWithRecovery<Category>(_categoryBoxName);
    _accountBox = await _openTypedBoxWithRecovery<Account>(_accountBoxName);
    _billsBox = await _openTypedBoxWithRecovery<Bill>(_billsBoxName);
    _billOccurrenceBox = await _openBoxWithRecovery(_billOccurrenceBoxName);
    _settingsBox = await _openBoxWithRecovery(_settingsBoxName);

    // Restore subscription plan from settings if present
    final savedPlan = _settingsBox.get('subscriptionPlan') as String?;
    if (savedPlan != null && savedPlan.isNotEmpty) {
      subscriptionVersion.value = savedPlan;
    } else {
      subscriptionVersion.value = 'Free';
    }

    // Initialize default data if boxes are empty
    await _initializeDefaultData();
    await migrateLegacyAccountTransactionsHiddenFromCalendar(force: true);
    await migrateLegacyTransactionCategoryNames();
    await migrateLegacyTransactionCategoryResolution();
    await migrateLegacyTransactionPaymentFor();
    await migrateLegacyRecurringBillSplitOverlaps();
    await runPostFixRecurringSplitRepairIfNeeded();
    await clearStaleForeverBillRecurrenceEndOverrides();
    await migrateLegacyBillPlaceholderText();
  }

  static Future<void> _initializeDefaultData() async {
    if (_categoryBox.isEmpty) {
      for (final category in DefaultCategories.expenseCategories) {
        final fresh = Category(
          name: category.name,
          iconCodePoint: category.iconCodePoint,
          colorValue: category.colorValue,
          isDefault: category.isDefault,
          budgetLimit: category.budgetLimit,
          image: category.image,
          type: category.type,
        );
        await _categoryBox.put(fresh.id, fresh);
      }

      for (final category in DefaultCategories.incomeCategories) {
        final fresh = Category(
          name: category.name,
          iconCodePoint: category.iconCodePoint,
          colorValue: category.colorValue,
          isDefault: category.isDefault,
          budgetLimit: category.budgetLimit,
          image: category.image,
          type: category.type,
        );
        await _categoryBox.put(fresh.id, fresh);
      }
    }

    if (_accountBox.isEmpty) {
      final defaultAccount = Account(
        name: 'Cash',
        type: AccountType.cash,
        balance: 0.0,
      );
      await _accountBox.put(defaultAccount.id, defaultAccount);
    }
  }

  static List<Transaction> getTransactionsByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) {
    // Treat the provided startDate and endDate as inclusive bounds. This
    // ensures callers can pass exact day-start/day-end values and only
    // transactions that fall within that exact range are returned.
    return _transactionBox.values
        .where(
          (transaction) =>
              (transaction.date.isAtSameMomentAs(startDate) ||
                  transaction.date.isAfter(startDate)) &&
              (transaction.date.isAtSameMomentAs(endDate) ||
                  transaction.date.isBefore(endDate)),
        )
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  static List<Transaction> getTransactionsByCategory(String categoryId) {
    return _transactionBox.values
        .where((transaction) => transaction.categoryId == categoryId)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  static List<Transaction> getTransactionsByType(TransactionType type) {
    return _transactionBox.values
        .where((transaction) => transaction.type == type)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  // Category operations
  static Future<String> addCategory(Category category) async {
    try {
      await _categoryBox.put(category.id, category);
      await _categoryBox.flush();
    } catch (e) {
      if (_isCategoryTransactionTypeMismatch(e)) {
        await _reopenCategoryAndTransactionBoxes();
        await _categoryBox.put(category.id, category);
        await _categoryBox.flush();
      } else {
        rethrow;
      }
    }
    await _removeDeletedCategoryId(category.id);
    categoriesVersion.value++;
    await _safeAwsCall(
      () => AwsApiService.createCategory(category),
      'create category',
    );
    return category.id;
  }

  static Future<void> updateCategory(Category category) async {
    try {
      await _categoryBox.put(category.id, category);
      await _categoryBox.flush();
    } catch (e) {
      if (_isCategoryTransactionTypeMismatch(e)) {
        await _reopenCategoryAndTransactionBoxes();
        await _categoryBox.put(category.id, category);
        await _categoryBox.flush();
      } else {
        rethrow;
      }
    }
    await _removeDeletedCategoryId(category.id);
    await updateCategoryReferences(category);
    categoriesVersion.value++;
    await _safeAwsCall(
      () => AwsApiService.updateCategory(category),
      'update category',
    );
  }

  static Future<void> deleteCategory(String id) async {
    await _addDeletedCategoryId(id);
    await _categoryBox.delete(id);
    await _categoryBox.flush();
    categoriesVersion.value++;
    await _safeAwsCall(
      () => AwsApiService.deleteCategory(id),
      'delete category',
    );
  }

  static List<Category> getAllCategories() {
    return _categoryBox.values.toList();
  }

  static Category? getCategoryById(String id) {
    return _categoryBox.get(id);
  }

  // Account operations
  static Future<void> addAccount(Account account) async {
    await _accountBox.put(account.id, account);
    // Ensure the box is flushed to disk so the account is persisted even if the
    // app is closed immediately after saving.
    await _accountBox.flush();
    // Persist the account's initial balance so the UI can display the
    // original initial balance later even if transactions update the
    // account's running/current balance.
    try {
      await setSetting('initialBalance:${account.id}', account.balance);
    } catch (_) {}
    // Notify listeners that accounts changed
    accountsVersion.value++;
    await _removeDeletedAccountId(account.id);
    await _safeAwsCall(
      () => AwsApiService.createAccount(account),
      'create account',
    );
  }

  static Future<void> updateAccount(Account account) async {
    await _accountBox.put(account.id, account);
    await _accountBox.flush();
    // Notify listeners that accounts changed
    accountsVersion.value++;
    if (account.isActive) {
      await _removeDeletedAccountId(account.id);
    }
    await _safeAwsCall(
      () => AwsApiService.updateAccount(account),
      'update account',
    );
  }

  /// Persist or update the stored initial balance for an account.
  static Future<void> setInitialBalance(String accountId, double value) async {
    try {
      await setSetting('initialBalance:$accountId', value);
    } catch (e) {
      // ignore: avoid_print
      print('Failed to set initial balance for $accountId: $e');
    }
  }

  /// Retrieve the persisted initial balance for an account.
  /// Falls back to the account's current balance if not explicitly set.
  static double getInitialBalance(String accountId) {
    try {
      final key = 'initialBalance:$accountId';
      final raw = getSetting<dynamic>(key, null);
      if (raw != null) {
        if (raw is num) return raw.toDouble();
        return double.tryParse(raw.toString()) ?? 0.0;
      }
    } catch (_) {}
    final acc = getAccountById(accountId);
    return acc?.balance ?? 0.0;
  }

  static Future<void> deleteAccount(String id) async {
    await _accountBox.delete(id);
    await _accountBox.flush();
    await _addDeletedAccountId(id);
    // Notify listeners that accounts changed
    accountsVersion.value++;
    await _safeAwsCall(() => AwsApiService.deleteAccount(id), 'delete account');
  }

  static List<Account> getAllAccounts() {
    final list = _accountBox.values
        .where((account) => account.isActive)
        .toList();
    // Apply saved order if present
    try {
      final saved = getSetting<List<dynamic>>('accountOrder', <dynamic>[]);
      if (saved != null && saved.isNotEmpty) {
        final order = saved.map((e) => e.toString()).toList();
        list.sort((a, b) {
          final ai = order.indexOf(a.id);
          final bi = order.indexOf(b.id);
          if (ai == -1 && bi == -1) return a.name.compareTo(b.name);
          if (ai == -1) return 1;
          if (bi == -1) return -1;
          return ai.compareTo(bi);
        });
      }
    } catch (_) {
      // ignore and return natural order
    }
    return list;
  }

  static List<Account> getArchivedAccounts() {
    return _accountBox.values
        .where((account) => account.isActive == false)
        .toList();
  }

  static Account? getAccountById(String id) {
    return _accountBox.get(id);
  }

  /// Compute an account's available balance.
  /// If the account has an explicit `availableBalance` set, return that.
  /// Otherwise compute availability as: balance - pendingExpenses + pendingIncome
  /// where "pending" means transactions for the account that are not marked cleared.
  static double getComputedAvailableBalance(String accountId) {
    final acc = getAccountById(accountId);
    if (acc == null) return 0.0;
    if (acc.availableBalance != null) return acc.availableBalance!;

    // Sum pending (uncleared) transactions for this account
    final pending = _transactionBox.values
        .where((t) => t.accountId == accountId && t.cleared != true)
        .toList();
    final pendingExpenses = pending
        .where((t) => t.type == TransactionType.expense)
        .fold<double>(0.0, (s, t) => s + t.amount);
    final pendingIncome = pending
        .where((t) => t.type == TransactionType.income)
        .fold<double>(0.0, (s, t) => s + t.amount);

    return acc.balance - pendingExpenses + pendingIncome;
  }

  /// Compute the display/final running balance for an account using the same
  /// approach as the transactions screen header so different screens match.
  ///
  /// - [showAvailable]: when true, prefer `account.availableBalance` if set,
  ///   otherwise compute availability from visible transactions.
  /// - [includeCleared]: whether to include cleared transactions in the
  ///   computation (TransactionsScreen allows toggling this); default false.
  static double getDisplayBalanceForAccount(
    String accountId, {
    bool showAvailable = false,
    bool includeCleared = false,
  }) {
    final acc = getAccountById(accountId);
    if (acc == null) return 0.0;

    // Build visible transactions for this account according to includeCleared
    final visible = _transactionBox.values
        .where((t) => t.accountId == accountId)
        .toList();
    if (!includeCleared) visible.removeWhere((t) => t.cleared == true);
    // Sort oldest -> newest for running-balance iteration
    visible.sort((a, b) {
      final cmp = a.date.compareTo(b.date);
      return cmp != 0 ? cmp : a.id.compareTo(b.id);
    });

    double cum;
    if (showAvailable) {
      final pendingExpenses = visible
          .where((t) => t.type == TransactionType.expense)
          .fold<double>(0.0, (s, t) => s + t.amount);
      final pendingIncome = visible
          .where((t) => t.type == TransactionType.income)
          .fold<double>(0.0, (s, t) => s + t.amount);
      final computedAvailable = acc.balance - pendingExpenses + pendingIncome;
      final base = acc.availableBalance ?? computedAvailable;
      cum = base;
      for (final tx in visible) {
        final effect = (tx.type == TransactionType.income
            ? tx.amount
            : -tx.amount);
        cum += effect;
      }
    } else {
      final initial = getInitialBalance(accountId);
      cum = initial;
      for (final tx in visible) {
        final effect = (tx.type == TransactionType.income
            ? tx.amount
            : -tx.amount);
        cum += effect;
      }
    }

    return cum;
  }

  // Settings operations
  static Box? _settingsBoxOrNull() {
    try {
      return _settingsBox;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setSetting(String key, dynamic value) async {
    final box = _settingsBoxOrNull();
    if (box == null) {
      foundation.debugPrint(
        'DatabaseService.setSetting skipped before init for key: $key',
      );
      return;
    }
    await box.put(key, value);
    await box.flush();
  }

  static T? getSetting<T>(String key, [T? defaultValue]) {
    final box = _settingsBoxOrNull();
    if (box == null) return defaultValue;
    return box.get(key, defaultValue: defaultValue) as T?;
  }

  /// Sanitize a value so it's safe to encode as JSON for backups.
  /// Converts DateTime to ISO strings, recursively sanitizes Maps/Lists,
  /// uses `toJson()` if available, and falls back to primitive types or
  /// `toString()` for unknown objects.
  static dynamic _sanitizeForJson(dynamic v) {
    try {
      if (v == null) return null;
      if (v is String || v is num || v is bool) return v;
      if (v is DateTime) return v.toIso8601String();
      if (v is Map) {
        final out = <String, dynamic>{};
        for (final e in v.entries) {
          out[e.key.toString()] = _sanitizeForJson(e.value);
        }
        return out;
      }
      if (v is Iterable) {
        return v.map((e) => _sanitizeForJson(e)).toList();
      }
      // Try common JSON helpers
      if (v is List || v is Set) {
        return (v as Iterable).map((e) => _sanitizeForJson(e)).toList();
      }
      // If object has toJson method, use it
      try {
        // Use dynamic invocation to call toJson if it exists
        final result = (v as dynamic).toJson();
        return _sanitizeForJson(result);
      } catch (_) {
        // No toJson method or it failed, continue to fallback
      }
      // Fallback: attempt to convert to primitive via toString
      return v.toString();
    } catch (_) {
      return v.toString();
    }
  }

  // Helpers to persist a list of transaction ids that should be hidden from
  // calendar/dashboard views. We store them in settings under
  // 'hiddenFromCalendarTransactions'. Keep these helpers small and defensive.
  static const String _hiddenTransactionsKey = 'hiddenFromCalendarTransactions';

  static List<String> getHiddenTransactionIds() {
    try {
      final raw =
          _settingsBox.get(_hiddenTransactionsKey, defaultValue: <dynamic>[])
              as List<dynamic>;
      return raw.map((e) => e.toString()).toList();
    } catch (e) {
      // ignore: avoid_print
      print('DatabaseService.getHiddenTransactionIds failed: $e');
      return <String>[];
    }
  }

  static Future<void> addHiddenTransactionId(String id) async {
    try {
      final list = getHiddenTransactionIds();
      if (!list.contains(id)) {
        list.add(id);
        await _settingsBox.put(_hiddenTransactionsKey, list);
        await _settingsBox.flush();
        // Trigger transactionsVersion so UI that depends on transactions can refresh
        transactionsVersion.value++;
      }
    } catch (e) {
      // ignore: avoid_print
      print('DatabaseService.addHiddenTransactionId failed: $e');
    }
  }

  static Future<void> removeHiddenTransactionId(String id) async {
    try {
      final list = getHiddenTransactionIds();
      list.removeWhere((e) => e == id);
      await _settingsBox.put(_hiddenTransactionsKey, list);
      await _settingsBox.flush();
      transactionsVersion.value++;
    } catch (e) {
      // ignore: avoid_print
      print('DatabaseService.removeHiddenTransactionId failed: $e');
    }
  }

  // Custom account types operations (stored as a list of strings in settings)
  static List<String> getAllCustomAccountTypes() {
    try {
      final raw =
          _settingsBox.get('customAccountTypes', defaultValue: <dynamic>[])
              as List<dynamic>;
      return raw.map((e) => e.toString()).toList();
    } catch (e) {
      // ignore: avoid_print
      print('DatabaseService.getAllCustomAccountTypes failed: $e');
      return <String>[];
    }
  }

  static Future<void> addCustomAccountType(String typeName) async {
    try {
      final list = getAllCustomAccountTypes();
      // Only add if it doesn't already exist (case-insensitive check)
      if (!list.any((t) => t.toLowerCase() == typeName.toLowerCase())) {
        list.add(typeName);
        await _settingsBox.put('customAccountTypes', list);
        await _settingsBox.flush();
        accountsVersion.value++;
      }
    } catch (e) {
      // ignore: avoid_print
      print('DatabaseService.addCustomAccountType failed: $e');
    }
  }

  static Future<void> deleteCustomAccountType(String typeName) async {
    try {
      final list = getAllCustomAccountTypes();
      list.removeWhere((t) => t.toLowerCase() == typeName.toLowerCase());
      await _settingsBox.put('customAccountTypes', list);
      await _settingsBox.flush();
      accountsVersion.value++;
    } catch (e) {
      // ignore: avoid_print
      print('DatabaseService.deleteCustomAccountType failed: $e');
    }
  }

  // Payee/Payer operations (stored as simple maps in settings to avoid
  // adding a new Hive adapter). Each payee is a Map<String, dynamic> with
  // keys: id, name, type ('payee'|'payer'), categoryId (nullable)
  static Map<String, dynamic> _normalizePayeeMap(Map<dynamic, dynamic> raw) {
    final out = <String, dynamic>{};

    for (final entry in raw.entries) {
      final key = entry.key.toString();
      final value = entry.value;

      if (value == null) {
        out[key] = null;
        continue;
      }

      if (value is String) {
        final trimmed = value.trim();
        out[key] = trimmed.toLowerCase() == 'null' ? null : trimmed;
        continue;
      }

      out[key] = value.toString();
    }

    return out;
  }

  static List<Map<String, dynamic>> getAllPayees() {
    try {
      final raw =
          _settingsBox.get('payees', defaultValue: <dynamic>[])
              as List<dynamic>;
      final out = <Map<String, dynamic>>[];
      for (final e in raw) {
        if (e is Map) {
          out.add(_normalizePayeeMap(e));
        } else if (e is String) {
          try {
            final decoded = json.decode(e) as Map<String, dynamic>;
            out.add(_normalizePayeeMap(decoded));
          } catch (_) {
            // fallback: skip invalid entry
          }
        } else {
          // unknown type, skip
        }
      }
      return out;
    } catch (e) {
      // If reading fails, return empty list and log for debugging
      // ignore: avoid_print
      print('DatabaseService.getAllPayees failed: $e');
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> addPayee(Map<String, dynamic> payee) async {
    try {
      final list = getAllPayees();
      final normalized = _normalizePayeeMap(payee);
      list.add(normalized);
      await _settingsBox.put('payees', list);
      await _settingsBox.flush();
      // Notify listeners
      payeesVersion.value++;
      // ignore: avoid_print
      print(
        'DatabaseService.addPayee stored payees: ${_settingsBox.get('payees')}',
      );
    } catch (e) {
      // ignore: avoid_print
      print('DatabaseService.addPayee failed: $e');
    }
  }

  static Future<void> updatePayee(Map<String, dynamic> payee) async {
    try {
      final list = getAllPayees();
      final idx = list.indexWhere((p) => p['id'] == payee['id']);
      if (idx >= 0) {
        final normalized = _normalizePayeeMap(payee);
        list[idx] = normalized;
        await _settingsBox.put('payees', list);
        await _settingsBox.flush();
        await updatePayeeReferences(normalized);
        // Notify listeners
        payeesVersion.value++;
        // ignore: avoid_print
        print(
          'DatabaseService.updatePayee stored payees: ${_settingsBox.get('payees')}',
        );
      }
    } catch (e) {
      // ignore: avoid_print
      print('DatabaseService.updatePayee failed: $e');
    }
  }

  static Future<void> deletePayee(String id) async {
    try {
      final list = getAllPayees();
      list.removeWhere((p) => p['id'] == id);
      await _settingsBox.put('payees', list);
      await _settingsBox.flush();
      // Notify listeners
      payeesVersion.value++;
      // ignore: avoid_print
      print(
        'DatabaseService.deletePayee stored payees: ${_settingsBox.get('payees')}',
      );
    } catch (e) {
      // ignore: avoid_print
      print('DatabaseService.deletePayee failed: $e');
    }
  }

  // Analytics helpers
  static double getTotalBalance() {
    return _accountBox.values.fold(
      0.0,
      (sum, account) => sum + account.balance,
    );
  }

  static double getTotalIncomeForPeriod(DateTime startDate, DateTime endDate) {
    return getTransactionsByDateRange(startDate, endDate)
        .where((transaction) => transaction.type == TransactionType.income)
        .fold(0.0, (sum, transaction) => sum + transaction.amount);
  }

  static double getTotalExpenseForPeriod(DateTime startDate, DateTime endDate) {
    return getTransactionsByDateRange(startDate, endDate)
        .where((transaction) => transaction.type == TransactionType.expense)
        .fold(0.0, (sum, transaction) => sum + transaction.amount);
  }

  static Map<String, double> getCategoryExpensesForPeriod(
    DateTime startDate,
    DateTime endDate,
  ) {
    final expenses = getTransactionsByDateRange(
      startDate,
      endDate,
    ).where((transaction) => transaction.type == TransactionType.expense);

    final categoryExpenses = <String, double>{};
    for (final transaction in expenses) {
      final category = getCategoryById(transaction.categoryId);
      if (category != null) {
        categoryExpenses[category.name] =
            (categoryExpenses[category.name] ?? 0) + transaction.amount;
      }
    }
    return categoryExpenses;
  }

  // Compute bill occurrences between startDate and endDate (inclusive).
  // Returns a list of maps: {'bill': Bill, 'date': DateTime}.
  // This is a non-persistent view used for calendar rendering and quick checks.
  static List<Map<String, dynamic>> getBillOccurrencesBetween(
    DateTime startDate,
    DateTime endDate,
  ) {
    final normalizedStart = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );
    final normalizedEnd = DateTime(endDate.year, endDate.month, endDate.day);
    final recurrenceEndOverrides = _getBillRecurrenceEndOverrides();
    final out = <Map<String, dynamic>>[];
    final seenAcrossBills = <String>{};
    final bills = getAllBills();
    for (final bill in bills) {
      final occurrences = generateBillOccurrenceDatesForRange(
        bill,
        normalizedStart,
        normalizedEnd,
        recurrenceEndOverride: recurrenceEndOverrides[bill.id],
      );
      for (final occ in occurrences) {
        final key = '${occ.year}-${occ.month}-${occ.day}';
        final globalKey = '${bill.id}|$key|${bill.type.name}';
        if (!seenAcrossBills.add(globalKey)) continue;
        out.add({'bill': bill, 'date': occ});
      }
    }
    return out;
  }

  /// Compute and persist per-occurrence payment status for all bills within
  /// the given date range. This is intended as a one-off migration utility
  /// to ensure legacy bills (created before occurrence-level statuses were
  /// stored) have correct persisted statuses so UI filters behave
  /// consistently. If `from` or `to` are omitted, the function will use
  /// the earliest bill due date and `DateTime.now()` respectively.
  static Future<void> persistBillOccurrenceStatuses({
    DateTime? from,
    DateTime? to,
  }) async {
    final bills = getAllBills();
    if (bills.isEmpty) return;

    final earliest = bills
        .map((b) => b.dueDate)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final start = from ?? DateTime(earliest.year, earliest.month, earliest.day);
    final end = to ?? DateTime.now();

    final allTransactions = getAllTransactions();

    for (final bill in bills) {
      final occurrences = getBillOccurrencesBetween(
        start,
        end,
      ).where((o) => o['bill'].id == bill.id).toList();
      for (final occ in occurrences) {
        final occDate = occ['date'] as DateTime;
        final occDateStr = DateFormat('MM/dd/yyyy').format(occDate);

        // Sum matching payments for this occurrence
        double totalPaid = 0.0;
        for (final tx in allTransactions) {
          if (tx.billId != bill.id) continue;
          if (tx.occurrenceDate != null) {
            if (tx.occurrenceDate!.year == occDate.year &&
                tx.occurrenceDate!.month == occDate.month &&
                tx.occurrenceDate!.day == occDate.day) {
              if (bill.type == BillType.expense) {
                totalPaid += (tx.type == TransactionType.expense)
                    ? tx.amount
                    : -tx.amount;
              } else {
                totalPaid += (tx.type == TransactionType.income)
                    ? tx.amount
                    : -tx.amount;
              }
            }
          } else if (tx.date.year == occDate.year &&
              tx.date.month == occDate.month &&
              tx.date.day == occDate.day) {
            if (bill.type == BillType.expense) {
              totalPaid += (tx.type == TransactionType.expense)
                  ? tx.amount
                  : -tx.amount;
            } else {
              totalPaid += (tx.type == TransactionType.income)
                  ? tx.amount
                  : -tx.amount;
            }
          } else if (tx.description.contains(occDateStr)) {
            if (bill.type == BillType.expense) {
              totalPaid += (tx.type == TransactionType.expense)
                  ? tx.amount
                  : -tx.amount;
            } else {
              totalPaid += (tx.type == TransactionType.income)
                  ? tx.amount
                  : -tx.amount;
            }
          }
        }

        PaymentStatus newStatus;
        if (totalPaid <= 0) {
          newStatus = PaymentStatus.unpaid;
        } else if (totalPaid >= (bill.amount - 0.01)) {
          newStatus = PaymentStatus.paid;
        } else {
          newStatus = PaymentStatus.partial;
        }

        // Persist the occurrence status
        await setBillOccurrenceStatus(
          bill.id,
          occDate,
          newStatus == PaymentStatus.paid,
          newStatus,
        );
      }
    }
  }

  /// Upsert remote snapshot data into local storage without triggering
  /// create/update API calls.
  static Future<void> hydrateFromRemoteSnapshot({
    List<Account> accounts = const [],
    List<Bill> bills = const [],
    List<Transaction> transactions = const [],
    List<Category> categories = const [],
    List<Map<String, dynamic>> payees = const [],
    List<Map<String, dynamic>> payers = const [],
    List<Map<String, dynamic>> payments = const [],
  }) async {
    bool accountsChanged = false;
    bool billsChanged = false;
    bool transactionsChanged = false;
    bool categoriesChanged = false;
    bool payeesChanged = false;
    final deletedAccountIds = _getDeletedAccountIds().toSet();
    final deletedBillIds = _getDeletedBillIds().toSet();
    final deletedCategoryIds = _getDeletedCategoryIds().toSet();
    final deletedTransactionIds = _getDeletedTransactionIds().toSet();
    final recurrenceEndOverrides = _getBillRecurrenceEndOverrides();
    final locallyModifiedBillIds = _getLocallyModifiedBillIds().toSet();

    if (accounts.isNotEmpty) {
      for (final account in accounts) {
        final accountId = account.id.trim();
        if (accountId.isEmpty) continue;
        if (deletedAccountIds.contains(accountId)) {
          // Keep local delete authoritative until explicitly recreated.
          if (_accountBox.containsKey(accountId)) {
            await _accountBox.delete(accountId);
          }
          continue;
        }
        final existing = _accountBox.get(account.id);
        final incomingInstitution = (account.institution ?? '').trim();
        final incomingDescription = (account.description ?? '').trim();
        final existingInstitution = (existing?.institution ?? '').trim();
        final existingDescription = (existing?.description ?? '').trim();
        final shouldKeepArchivedLocal =
            existing != null &&
            existing.isActive == false &&
            account.isActive == true;

        Account toPersist = account;
        if (existing != null &&
            incomingInstitution.isEmpty &&
            incomingDescription.isEmpty) {
          toPersist = toPersist.copyWith(
            institution: existingInstitution.isNotEmpty
                ? existingInstitution
                : null,
            description: existingDescription.isNotEmpty
                ? existingDescription
                : null,
          );
        }
        if (shouldKeepArchivedLocal) {
          toPersist = toPersist.copyWith(isActive: false);
        }

        await _accountBox.put(toPersist.id, toPersist);
      }
      await _accountBox.flush();
      accountsChanged = true;
    }

    if (categories.isNotEmpty) {
      bool looksOpaque(String value) {
        final v = value.trim();
        if (v.isEmpty) return false;
        final uuid = RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
        );
        if (uuid.hasMatch(v)) return true;
        final longToken = RegExp(r'^[A-Za-z0-9_-]{16,}$');
        return longToken.hasMatch(v);
      }

      for (final category in categories) {
        final categoryId = category.id.trim();
        if (categoryId.isEmpty) continue;
        if (deletedCategoryIds.contains(categoryId)) {
          if (_categoryBox.containsKey(categoryId)) {
            await _categoryBox.delete(categoryId);
          }
          continue;
        }
        final existing = _categoryBox.get(category.id);
        final incomingName = category.name.trim();
        final existingName = (existing?.name ?? '').trim();

        final incomingLooksLikeId =
            incomingName.isEmpty ||
            incomingName == category.id ||
            looksOpaque(incomingName);
        final existingIsReadable =
            existingName.isNotEmpty &&
            existingName != category.id &&
            !looksOpaque(existingName);

        final toPersist =
            (existing != null && incomingLooksLikeId && existingIsReadable)
            ? category.copyWith(name: existingName)
            : category;

        await _categoryBox.put(category.id, toPersist);
      }
      await _categoryBox.flush();
      categoriesChanged = true;
    }

    if (bills.isNotEmpty) {
      for (final bill in bills) {
        final billId = bill.id.trim();
        if (billId.isEmpty) continue;
        if (deletedBillIds.contains(billId)) {
          if (_billsBox.containsKey(billId)) {
            await _billsBox.delete(billId);
          }
          continue;
        }
        final existing = _billsBox.get(billId);
        if (existing != null && locallyModifiedBillIds.contains(billId)) {
          if (_billMatches(existing, bill)) {
            await _removeLocallyModifiedBillId(billId);
          } else {
            continue;
          }
        }
        Bill toPersist = bill;
        final localCutoff = bill.recurrence == Recurrence.none
            ? null
            : recurrenceEndOverrides[billId];
        if (localCutoff != null) {
          final remoteEnd = bill.recurrenceEndDate;
          if (remoteEnd == null || remoteEnd.isAfter(localCutoff)) {
            toPersist = bill.copyWith(recurrenceEndDate: localCutoff);
          }
        }
        await _billsBox.put(toPersist.id, toPersist);
      }
      await _billsBox.flush();
      billsChanged = true;
    }

    if (transactions.isNotEmpty) {
      for (final tx in transactions) {
        final txId = tx.id.trim();
        if (txId.isEmpty) continue;
        if (deletedTransactionIds.contains(txId)) {
          if (_transactionBox.containsKey(txId)) {
            await _transactionBox.delete(txId);
          }
          continue;
        }
        final existing = _transactionBox.get(tx.id);
        Transaction toPersist =
            (tx.cleared == null && existing?.cleared != null)
            ? tx.copyWith(cleared: existing!.cleared)
            : tx;

        if (existing != null) {
          final incomingCategoryId = tx.categoryId.trim();
          final existingCategoryId = existing.categoryId.trim();
          final incomingCategoryName = (tx.categoryName ?? '').trim();
          final existingCategoryName = (existing.categoryName ?? '').trim();

          final remoteCategoryMissingOrOpaque =
              incomingCategoryId.isEmpty ||
              (incomingCategoryName.isEmpty &&
                  _looksLikeOpaqueId(incomingCategoryId));

          final localCategoryIsNewer =
              existing.updatedAt.isAfter(tx.updatedAt) &&
              existingCategoryId.isNotEmpty &&
              existingCategoryId != incomingCategoryId;

          if (remoteCategoryMissingOrOpaque || localCategoryIsNewer) {
            toPersist = toPersist.copyWith(
              categoryId: existingCategoryId,
              categoryName: existingCategoryName.isEmpty
                  ? null
                  : existingCategoryName,
            );
          }
        }

        await _transactionBox.put(toPersist.id, toPersist);
      }
      await _transactionBox.flush();
      transactionsChanged = true;
    }

    // Ensure imported transactions have friendly category names after
    // categories and transactions are written.
    final categoryNamesUpdated = await migrateLegacyTransactionCategoryNames(
      force: true,
    );
    if (categoryNamesUpdated > 0) {
      transactionsChanged = true;
    }

    final categoryLinksUpdated =
        await migrateLegacyTransactionCategoryResolution(force: true);
    if (categoryLinksUpdated > 0) {
      transactionsChanged = true;
    }

    if (payments.isNotEmpty) {
      for (final raw in payments) {
        try {
          final billId = (raw['billId'] ?? raw['bill_id'] ?? '').toString();
          final dateRaw =
              raw['occurrenceDate'] ??
              raw['paymentDate'] ??
              raw['date'] ??
              raw['dueDate'];
          if (billId.isEmpty || dateRaw == null) continue;

          final date = DateTime.tryParse(dateRaw.toString());
          if (date == null) continue;

          final statusRaw = (raw['paymentStatus'] ?? raw['status'] ?? '')
              .toString()
              .toLowerCase();
          final isPaidRaw = raw['isPaid'];
          final bool isPaid = isPaidRaw == true || statusRaw == 'paid';
          final PaymentStatus status = statusRaw == 'partial'
              ? PaymentStatus.partial
              : (isPaid ? PaymentStatus.paid : PaymentStatus.unpaid);

          final key = _occurrenceKey(
            billId,
            DateTime(date.year, date.month, date.day),
          );
          await _billOccurrenceBox.put(key, {
            'isPaid': isPaid,
            'paymentStatus': status.index,
          });
          billsChanged = true;
        } catch (_) {}
      }
      await _billOccurrenceBox.flush();
    }

    if (payees.isNotEmpty || payers.isNotEmpty) {
      final merged = <String, Map<String, dynamic>>{};

      bool looksOpaque(String value) {
        final v = value.trim();
        if (v.isEmpty) return false;
        final uuid = RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
        );
        if (uuid.hasMatch(v)) return true;
        final longToken = RegExp(r'^[A-Za-z0-9_-]{16,}$');
        return longToken.hasMatch(v);
      }

      void mergeContacts(
        List<Map<String, dynamic>> entries,
        String defaultType,
      ) {
        for (final item in entries) {
          final id = (item['id'] ?? '').toString().trim();
          final name = (item['name'] ?? '').toString().trim();
          if (id.isEmpty || name.isEmpty) continue;
          final existing = merged[id];
          final rawCategoryId = item['categoryId']?.toString().trim();
          final incomingCategoryId =
              rawCategoryId == null ||
                  rawCategoryId.isEmpty ||
                  rawCategoryId.toLowerCase() == 'null'
              ? null
              : rawCategoryId;
          final rawExistingCategoryId = existing?['categoryId']
              ?.toString()
              .trim();
          final existingCategoryId =
              rawExistingCategoryId == null ||
                  rawExistingCategoryId.isEmpty ||
                  rawExistingCategoryId.toLowerCase() == 'null'
              ? null
              : rawExistingCategoryId;
          final incomingLooksLikeId = name == id || looksOpaque(name);
          final existingName = (existing?['name'] ?? '').toString().trim();
          final existingIsGood =
              existingName.isNotEmpty &&
              existingName != id &&
              !looksOpaque(existingName);

          // Keep existing readable names; do not replace with opaque/id-like names.
          if (existing != null && incomingLooksLikeId && existingIsGood) {
            continue;
          }

          merged[id] = {
            'id': id,
            'name': name,
            'type': (item['type'] ?? defaultType).toString(),
            'categoryId': incomingCategoryId ?? existingCategoryId,
          };
        }
      }

      mergeContacts(getAllPayees(), 'payee');
      mergeContacts(payees, 'payee');
      mergeContacts(payers, 'payer');

      await _settingsBox.put('payees', merged.values.toList());
      await _settingsBox.flush();
      payeesChanged = true;
    }

    if (accountsChanged) accountsVersion.value++;
    if (categoriesChanged) categoriesVersion.value++;
    if (billsChanged) billsVersion.value++;
    if (transactionsChanged) transactionsVersion.value++;
    if (payeesChanged) payeesVersion.value++;
  }

  static Future<void> clearAccountsOnly() async {
    final bills = _billsBox.values.toList();
    var billsChanged = 0;
    for (final bill in bills) {
      final hasAccountLink =
          (bill.accountId ?? '').trim().isNotEmpty ||
          (bill.fromAccountId ?? '').trim().isNotEmpty ||
          (bill.toAccountId ?? '').trim().isNotEmpty;
      if (!hasAccountLink) continue;

      await _billsBox.put(
        bill.id,
        bill.copyWith(accountId: null, fromAccountId: null, toAccountId: null),
      );
      billsChanged++;
    }

    final hadTransactions = _transactionBox.isNotEmpty;
    await _transactionBox.clear();
    await _transactionBox.flush();
    await _billOccurrenceBox.clear();
    await _billOccurrenceBox.flush();
    await _settingsBox.put(_hiddenTransactionsKey, <dynamic>[]);

    await _accountBox.clear();
    await _accountBox.flush();

    if (billsChanged > 0) {
      await _billsBox.flush();
      billsVersion.value++;
    }
    if (hadTransactions) {
      transactionsVersion.value++;
    }

    final keysToDelete = _settingsBox.keys
        .where((key) => key.toString().startsWith('initialBalance:'))
        .toList();
    for (final key in keysToDelete) {
      await _settingsBox.delete(key);
    }
    await _settingsBox.put('accountOrder', <dynamic>[]);
    await _settingsBox.flush();

    accountsVersion.value++;
  }

  static Future<void> clearTransactionsOnly() async {
    await _transactionBox.clear();
    await _transactionBox.flush();
    await _billOccurrenceBox.clear();
    await _billOccurrenceBox.flush();
    await _settingsBox.put(_hiddenTransactionsKey, <dynamic>[]);
    await _settingsBox.flush();

    transactionsVersion.value++;
  }

  static Future<void> clearBillsOnly({required bool includePayments}) async {
    var transactionsChanged = 0;

    if (includePayments) {
      final idsToDelete = _transactionBox.values
          .where((tx) => (tx.billId ?? '').trim().isNotEmpty)
          .map((tx) => tx.id)
          .toSet();
      for (final id in idsToDelete) {
        await _transactionBox.delete(id);
      }
      if (idsToDelete.isNotEmpty) {
        final hidden = getHiddenTransactionIds()
            .where((id) => !idsToDelete.contains(id))
            .toList();
        await _settingsBox.put(_hiddenTransactionsKey, hidden);
        transactionsChanged = idsToDelete.length;
      }
    } else {
      for (final tx in _transactionBox.values) {
        if ((tx.billId ?? '').trim().isEmpty) continue;
        await _transactionBox.put(
          tx.id,
          tx.copyWith(
            billId: null,
            occurrenceDate: null,
            paymentFor: null,
            updatedAt: DateTime.now(),
          ),
        );
        transactionsChanged++;
      }
    }

    await _billsBox.clear();
    await _billsBox.flush();
    await _billOccurrenceBox.clear();
    await _billOccurrenceBox.flush();
    await _settingsBox.put(_billRecurrenceEndOverridesKey, <String, String>{});
    await _settingsBox.put(_locallyModifiedBillsKey, <dynamic>[]);
    await _settingsBox.flush();

    if (transactionsChanged > 0) {
      await _transactionBox.flush();
      transactionsVersion.value++;
    }
    billsVersion.value++;
  }

  static Future<void> clearPayeesAndPayersOnly() async {
    var transactionsChanged = 0;
    for (final tx in _transactionBox.values) {
      final hasPayee = (tx.payeeId ?? '').trim().isNotEmpty;
      final hasPayer = (tx.payerId ?? '').trim().isNotEmpty;
      if (!hasPayee && !hasPayer) continue;
      await _transactionBox.put(
        tx.id,
        tx.copyWith(payeeId: null, payerId: null, updatedAt: DateTime.now()),
      );
      transactionsChanged++;
    }

    var billsChanged = 0;
    for (final bill in _billsBox.values) {
      if ((bill.payeeId ?? '').trim().isEmpty) continue;
      await _billsBox.put(bill.id, bill.copyWith(payeeId: null));
      billsChanged++;
    }

    await _settingsBox.put('payees', <dynamic>[]);
    await _settingsBox.flush();

    if (transactionsChanged > 0) {
      await _transactionBox.flush();
      transactionsVersion.value++;
    }
    if (billsChanged > 0) {
      await _billsBox.flush();
      billsVersion.value++;
    }
    payeesVersion.value++;
  }

  static Future<void> clearCategoriesOnly() async {
    await _categoryBox.clear();
    await _categoryBox.flush();
    categoriesVersion.value++;
  }

  // Clear all data (useful for testing or reset)
  static Future<void> clearAllData() async {
    // Clear all data boxes
    await _transactionBox.clear();
    await _categoryBox.clear();
    await _accountBox.clear();
    await _billsBox.clear();
    await _billOccurrenceBox.clear();

    // Clear all settings
    await _settingsBox.clear();

    // Reset specific settings to defaults
    await _settingsBox.put('payees', <dynamic>[]);
    await _settingsBox.put('customAccountTypes', <dynamic>[]);
    await _settingsBox.put('subscriptionPlan', 'Free');
    subscriptionVersion.value = 'Free';
    await _settingsBox.put('appliedPromoCode', null);
    await _settingsBox.put('activeTrialExpiresAt', null);
    await _settingsBox.put('lastPurchase', null);

    // Clear auto-backup settings
    await _settingsBox.put('autoBackupEnabled', false);
    await _settingsBox.put('autoBackupFrequency', 'Weekly');
    await _settingsBox.put('lastAutoBackupAt', null);

    // Clear other app settings
    await _settingsBox.put('accountOrder', <dynamic>[]);
    await _settingsBox.put(_hiddenTransactionsKey, <dynamic>[]);

    // Flush all boxes to ensure data is persisted
    await _transactionBox.flush();
    await _categoryBox.flush();
    await _accountBox.flush();
    await _billsBox.flush();
    await _billOccurrenceBox.flush();
    await _settingsBox.flush();

    // Notify all listeners
    transactionsVersion.value++;
    categoriesVersion.value++;
    accountsVersion.value++;
    billsVersion.value++;
    payeesVersion.value++;

    // Reinitialize default data
    await _initializeDefaultData();
  }

  // Set subscription plan and notify listeners
  static Future<void> setSubscriptionPlan(String plan) async {
    await _settingsBox.put('subscriptionPlan', plan);
    subscriptionVersion.value = plan;
  }

  /// Export all settings (key -> value) as a JSON-encodable map.
  /// This is used by the backup service to include app settings in backups.
  static Map<String, dynamic> exportAllSettings() {
    final out = <String, dynamic>{};
    try {
      for (final key in _settingsBox.keys) {
        try {
          out[key.toString()] = _sanitizeForJson(_settingsBox.get(key));
        } catch (_) {
          // skip non-serializable entries
        }
      }
    } catch (_) {}
    return out;
  }

  /// Export all bill occurrence persisted statuses as a map keyed by
  /// `${billId}_YYYY-M-D` with value being the stored map.
  static Map<String, dynamic> exportBillOccurrenceStatuses() {
    final out = <String, dynamic>{};
    try {
      for (final key in _billOccurrenceBox.keys) {
        try {
          final v = _billOccurrenceBox.get(key);
          out[key.toString()] = _sanitizeForJson(v);
        } catch (_) {}
      }
    } catch (_) {}
    return out;
  }

  /// Import bill occurrence statuses from a map into the internal box.
  static Future<void> importBillOccurrenceStatuses(
    Map<String, dynamic> data,
  ) async {
    if (data.isEmpty) return;
    try {
      for (final entry in data.entries) {
        try {
          await _billOccurrenceBox.put(entry.key, entry.value);
        } catch (_) {}
      }
      await _billOccurrenceBox.flush();
    } catch (_) {}
  }
}
