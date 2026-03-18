
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
import 'aws_api_service.dart';


class DatabaseService {
  static void _registerAdapterIfNeeded(int typeId, TypeAdapter<dynamic> adapter) {
    if (Hive.isAdapterRegistered(typeId)) return;
    try {
      Hive.registerAdapter(adapter);
    } catch (e) {
      // In rare retry paths, adapter may already be registered in this process.
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
    // Update transactions
    final txs = getAllTransactions().where((t) => t.categoryId == updatedCategory.id).toList();
    for (final tx in txs) {
      await updateTransaction(tx.copyWith(categoryId: updatedCategory.id));
    }
    // Update bills
    final bills = getAllBills().where((b) => b.categoryId == updatedCategory.id).toList();
    for (final bill in bills) {
      await updateBill(bill.copyWith(categoryId: updatedCategory.id));
    }
    // Notify listeners
    categoriesVersion.value++;
    billsVersion.value++;
    transactionsVersion.value++;
  }

  // Update all transactions, bills, etc. that reference a payee/payer when edited
  static Future<void> updatePayeeReferences(Map<String, dynamic> updatedPayee) async {
    final payeeId = updatedPayee['id'] as String?;
    if (payeeId == null) return;
    // Update transactions
    final txs = getAllTransactions().where((t) => t.note != null && t.note!.contains(payeeId)).toList();
    for (final tx in txs) {
      // Optionally update note or other fields if needed
      await updateTransaction(tx);
    }
    // Update bills
    final bills = getAllBills().where((b) => b.payeeId == payeeId).toList();
    for (final bill in bills) {
      await updateBill(bill.copyWith(payeeId: payeeId));
    }
    // Notify listeners
    billsVersion.value++;
    transactionsVersion.value++;
    payeesVersion.value++;
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
  static final foundation.ValueNotifier<int> categoriesVersion = foundation.ValueNotifier<int>(0);
  static final foundation.ValueNotifier<int> billsVersion = foundation.ValueNotifier<int>(0);
  static final foundation.ValueNotifier<int> payeesVersion = foundation.ValueNotifier<int>(0);
  static final foundation.ValueNotifier<int> accountsVersion = foundation.ValueNotifier<int>(0);
  static final foundation.ValueNotifier<int> transactionsVersion = foundation.ValueNotifier<int>(0);
  static final foundation.ValueNotifier<String> subscriptionVersion = foundation.ValueNotifier<String>('Free');

  static Future<void> _safeAwsCall(Future<void> Function() task, String label) async {
    if (!AwsApiService.isConfigured) return;
    try {
      await task();
    } catch (e) {
      foundation.debugPrint('AWS sync failed ($label): $e');
    }
  }

  // Bill operations
  static Future<void> addBill(Bill bill) async {
    await _billsBox.put(bill.id, bill);
    await _billsBox.flush();
    billsVersion.value++;
    await _safeAwsCall(() => AwsApiService.createBill(bill), 'create bill');
  }

  // Per-occurrence bill status helpers
  static String _occurrenceKey(String billId, DateTime date) {
    // Normalize to Y-M-D to avoid time portion differences
    return '${billId}_${date.year}-${date.month}-${date.day}';
  }

  /// Persist a per-occurrence paid flag and payment status.
  /// Stored in a simple box keyed by `${billId}_YYYY-M-D` with value
  /// {'isPaid': bool, 'paymentStatus': int}
  static Future<void> setBillOccurrenceStatus(String billId, DateTime date, bool isPaid, PaymentStatus status) async {
    final key = _occurrenceKey(billId, date);
    await _billOccurrenceBox.put(key, {'isPaid': isPaid, 'paymentStatus': status.index});
    await _billOccurrenceBox.flush();
    // Notify UI that bills have changed so calendars refresh
    billsVersion.value++;
  }

  /// Return occurrence-level status if present. Null if no persisted occurrence record exists.
  static Map<String, dynamic>? getBillOccurrenceStatus(String billId, DateTime date) {
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
        status = PaymentStatus.values[rawIdx.clamp(0, PaymentStatus.values.length - 1)];
      }
      return {'isPaid': isPaid, 'paymentStatus': status};
    } catch (_) {
      return null;
    }
  }

  static Future<void> updateBill(Bill bill) async {
    await _billsBox.put(bill.id, bill);
    await _billsBox.flush();
    billsVersion.value++;
    await _safeAwsCall(() => AwsApiService.updateBill(bill), 'update bill');
  }

  static Future<void> deleteBill(String id) async {
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
      final related = _transactionBox.values.where((t) => t.billId == id).toList();
      for (final tx in related) {
        try {
          await removeHiddenTransactionId(tx.id);
        } catch (_) {}
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
    await _safeAwsCall(() => AwsApiService.deleteBill(id), 'delete bill');
  }

  static List<Bill> getAllBills() {
    return _billsBox.values.toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  // Transaction operations
  static Future<void> addTransaction(Transaction transaction) async {
    await _transactionBox.put(transaction.id, transaction);
    // Ensure the transaction box is flushed so UI/readers see the new transaction
    // immediately and any persistence occurs if the app exits.
    await _transactionBox.flush();
    transactionsVersion.value++;
    await _safeAwsCall(() => AwsApiService.createTransaction(transaction), 'create transaction');
  }

  static Future<void> updateTransaction(Transaction transaction) async {
    // Capture previous value so we can update occurrence status if bill linkage
    // changed or if amount/date was edited.
    final Transaction? previous = _transactionBox.get(transaction.id);

    await _transactionBox.put(transaction.id, transaction);
    // Ensure the transaction box is flushed so readers (UI/listeners)
    // observe the updated value when transactionsVersion is incremented.
    await _transactionBox.flush();
    transactionsVersion.value++;
    await _safeAwsCall(() => AwsApiService.updateTransaction(transaction), 'update transaction');

    // Keep bill occurrence paid/partial/unpaid state synchronized whenever a
    // linked payment transaction is edited from any screen.
    try {
      final affectedBillIds = <String>{};
      if (previous?.billId != null && previous!.billId!.isNotEmpty) {
        affectedBillIds.add(previous.billId!);
      }
      if (transaction.billId != null && transaction.billId!.isNotEmpty) {
        affectedBillIds.add(transaction.billId!);
      }

      for (final billId in affectedBillIds) {
        final bill = _billsBox.get(billId);
        if (bill == null) continue;

        final allTx = getAllTransactions();
        final occDates = <DateTime>{};

        void addOccSeed(DateTime? occDate, DateTime? date, String? description) {
          if (occDate != null) {
            occDates.add(DateTime(occDate.year, occDate.month, occDate.day));
            return;
          }
          if (date != null) {
            occDates.add(DateTime(date.year, date.month, date.day));
            return;
          }
          if (description != null) {
            final match = RegExp(r"(0[1-9]|1[0-2])/(0[1-9]|[12][0-9]|3[01])/\d{4}").firstMatch(description);
            if (match != null) {
              try {
                final parsed = DateFormat('MM/dd/yyyy').parse(match.group(0)!);
                occDates.add(DateTime(parsed.year, parsed.month, parsed.day));
              } catch (_) {}
            }
          }
        }

        if (previous?.billId == billId) {
          addOccSeed(previous!.occurrenceDate, previous.date, previous.description);
        }
        if (transaction.billId == billId) {
          addOccSeed(transaction.occurrenceDate, transaction.date, transaction.description);
        }

        for (final t in allTx) {
          if (t.billId != billId) continue;
          if (t.occurrenceDate != null) {
            occDates.add(DateTime(t.occurrenceDate!.year, t.occurrenceDate!.month, t.occurrenceDate!.day));
          } else {
            occDates.add(DateTime(t.date.year, t.date.month, t.date.day));
          }
        }

        for (final occ in occDates) {
          final occDateStr = DateFormat('MM/dd/yyyy').format(occ);
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
                    t.description.contains(occDateStr));
            if (!matchesOccurrence) continue;

            if (bill.type == BillType.expense) {
              totalPaid += (t.type == TransactionType.expense) ? t.amount : -t.amount;
            } else {
              totalPaid += (t.type == TransactionType.income) ? t.amount : -t.amount;
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

          await setBillOccurrenceStatus(billId, occ, newStatus == PaymentStatus.paid, newStatus);
        }
      }
    } catch (_) {
      // Non-critical: do not block transaction edits if status sync fails.
    }
  }

  static Future<void> deleteTransaction(String id) async {
    // Read the transaction before deleting so we can update any linked
    // bill occurrence status if this transaction represented a bill payment.
    final Transaction? tx = _transactionBox.get(id);
    String? billId;
    DateTime? txOccDate;
    DateTime? txDate;
    String? txDescription;
    if (tx != null) {
      billId = tx.billId;
      txOccDate = tx.occurrenceDate;
      txDate = tx.date;
      txDescription = tx.description;
    }

    await _transactionBox.delete(id);
    // Flush so the deletion is persisted and any subsequent reads from
    // the Hive box return the updated set of transactions. Notify
    // listeners only after flush so UI can rebuild with the latest data.
    await _transactionBox.flush();
    transactionsVersion.value++;
    await _safeAwsCall(() => AwsApiService.deleteTransaction(id), 'delete transaction');

    // If this transaction was linked to a bill, recompute the per-occurrence
    // paid totals for the affected occurrence(s) and persist the new status.
    try {
      if (billId != null && billId.isNotEmpty) {
  final Bill? bill = _billsBox.get(billId);
        if (bill == null) return;

        // Build a set of occurrence dates to update: include the deleted
        // transaction's occurrence/date and any occurrence dates present
        // in the remaining transactions for this bill.
        final allTx = getAllTransactions();
        final occDates = <DateTime>{};

        // Add deleted tx's occurrence/date (normalize to Y-M-D)
        if (txOccDate != null) {
          occDates.add(DateTime(txOccDate.year, txOccDate.month, txOccDate.day));
        } else if (txDate != null) {
          occDates.add(DateTime(txDate.year, txDate.month, txDate.day));
        } else if (txDescription != null) {
          // Best-effort: try to extract a MM/dd/yyyy substring and parse it
          final match = RegExp(r"(0[1-9]|1[0-2])/(0[1-9]|[12][0-9]|3[01])/\d{4}").firstMatch(txDescription);
          if (match != null) {
            try {
              final parsed = DateFormat('MM/dd/yyyy').parse(match.group(0)!);
              occDates.add(DateTime(parsed.year, parsed.month, parsed.day));
            } catch (_) {}
          }
        }

        // Add occurrence dates from remaining transactions for this bill
        for (final t in allTx) {
          if (t.billId != billId) continue;
          if (t.occurrenceDate != null) {
            occDates.add(DateTime(t.occurrenceDate!.year, t.occurrenceDate!.month, t.occurrenceDate!.day));
          } else {
            occDates.add(DateTime(t.date.year, t.date.month, t.date.day));
          }
        }

        // For each affected occurrence date, recompute the paid total and
        // persist the new PaymentStatus.
        for (final occ in occDates) {
          final occDateStr = DateFormat('MM/dd/yyyy').format(occ);
          double totalPaid = 0.0;

          for (final t in allTx) {
            if (t.billId != billId) continue;
            // Match same occurrence by explicit occurrenceDate or by date/string
            if (t.occurrenceDate != null) {
              if (t.occurrenceDate!.year == occ.year && t.occurrenceDate!.month == occ.month && t.occurrenceDate!.day == occ.day) {
                if (bill.type == BillType.expense) {
                  totalPaid += (t.type == TransactionType.expense) ? t.amount : -t.amount;
                } else {
                  totalPaid += (t.type == TransactionType.income) ? t.amount : -t.amount;
                }
              }
            } else if (t.date.year == occ.year && t.date.month == occ.month && t.date.day == occ.day) {
              if (bill.type == BillType.expense) {
                totalPaid += (t.type == TransactionType.expense) ? t.amount : -t.amount;
              } else {
                totalPaid += (t.type == TransactionType.income) ? t.amount : -t.amount;
              }
            } else if (t.description.contains(occDateStr)) {
              if (bill.type == BillType.expense) {
                totalPaid += (t.type == TransactionType.expense) ? t.amount : -t.amount;
              } else {
                totalPaid += (t.type == TransactionType.income) ? t.amount : -t.amount;
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

          await setBillOccurrenceStatus(billId, occ, newStatus == PaymentStatus.paid, newStatus);
        }
      }
    } catch (_) {
      // Non-critical: don't block deletion on status update errors
    }
  }

  static List<Transaction> getAllTransactions() {
    return _transactionBox.values.toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  static Future<void> init() async {
    // Use application support directory for Hive files to keep them hidden from users
    final supportDir = await getApplicationSupportDirectory();
    final hiveDir = Directory('${supportDir.path}/.hive');
    await hiveDir.create(recursive: true);

    // Migrate from old location if exists
    final docsDir = await getApplicationDocumentsDirectory();
    final oldHiveDir = Directory('${docsDir.path}/CashSense/.hive');
    if (await oldHiveDir.exists() && !(await hiveDir.exists() || await Directory('${hiveDir.path}/transactions.hive').exists())) {
      // Copy old files to new location
      try {
        await for (final file in oldHiveDir.list()) {
          if (file is File) {
            final newFile = File('${hiveDir.path}/${file.uri.pathSegments.last}');
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
    _transactionBox = await _openTypedBoxWithRecovery<Transaction>(_transactionBoxName);
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
  }

  static Future<void> _initializeDefaultData() async {
    // Initialize default categories if empty
    if (_categoryBox.isEmpty) {
      for (final category in DefaultCategories.expenseCategories) {
        await _categoryBox.put(category.id, category);
      }
      for (final category in DefaultCategories.incomeCategories) {
        await _categoryBox.put(category.id, category);
      }
    }

    // Initialize default account if empty
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
        .where((transaction) =>
            (transaction.date.isAtSameMomentAs(startDate) || transaction.date.isAfter(startDate)) &&
            (transaction.date.isAtSameMomentAs(endDate) || transaction.date.isBefore(endDate)))
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
    await _categoryBox.put(category.id, category);
    await _categoryBox.flush();
    categoriesVersion.value++;
    return category.id;
  }

  static Future<void> updateCategory(Category category) async {
    await _categoryBox.put(category.id, category);
    await _categoryBox.flush();
  categoriesVersion.value++;
  }

  static Future<void> deleteCategory(String id) async {
    await _categoryBox.delete(id);
    await _categoryBox.flush();
  categoriesVersion.value++;
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
    await _safeAwsCall(() => AwsApiService.createAccount(account), 'create account');
  }

  static Future<void> updateAccount(Account account) async {
    await _accountBox.put(account.id, account);
    await _accountBox.flush();
    // Notify listeners that accounts changed
    accountsVersion.value++;
    await _safeAwsCall(() => AwsApiService.updateAccount(account), 'update account');
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
    // Notify listeners that accounts changed
    accountsVersion.value++;
    await _safeAwsCall(() => AwsApiService.deleteAccount(id), 'delete account');
  }

  static List<Account> getAllAccounts() {
    final list = _accountBox.values.where((account) => account.isActive).toList();
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
    return _accountBox.values.where((account) => account.isActive == false).toList();
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
    final pending = _transactionBox.values.where((t) => t.accountId == accountId && t.cleared != true).toList();
    final pendingExpenses = pending.where((t) => t.type == TransactionType.expense).fold<double>(0.0, (s, t) => s + t.amount);
    final pendingIncome = pending.where((t) => t.type == TransactionType.income).fold<double>(0.0, (s, t) => s + t.amount);

    return acc.balance - pendingExpenses + pendingIncome;
  }

  /// Compute the display/final running balance for an account using the same
  /// approach as the transactions screen header so different screens match.
  ///
  /// - [showAvailable]: when true, prefer `account.availableBalance` if set,
  ///   otherwise compute availability from visible transactions.
  /// - [includeCleared]: whether to include cleared transactions in the
  ///   computation (TransactionsScreen allows toggling this); default false.
  static double getDisplayBalanceForAccount(String accountId, {bool showAvailable = false, bool includeCleared = false}) {
    final acc = getAccountById(accountId);
    if (acc == null) return 0.0;

    // Build visible transactions for this account according to includeCleared
    final visible = _transactionBox.values.where((t) => t.accountId == accountId).toList();
    if (!includeCleared) visible.removeWhere((t) => t.cleared == true);
    // Sort oldest -> newest for running-balance iteration
    visible.sort((a, b) {
      final cmp = a.date.compareTo(b.date);
      return cmp != 0 ? cmp : a.id.compareTo(b.id);
    });

    double cum;
    if (showAvailable) {
      final pendingExpenses = visible.where((t) => t.type == TransactionType.expense).fold<double>(0.0, (s, t) => s + t.amount);
      final pendingIncome = visible.where((t) => t.type == TransactionType.income).fold<double>(0.0, (s, t) => s + t.amount);
      final computedAvailable = acc.balance - pendingExpenses + pendingIncome;
      final base = acc.availableBalance ?? computedAvailable;
      cum = base;
      for (final tx in visible) {
        final effect = (tx.type == TransactionType.income ? tx.amount : -tx.amount);
        cum += effect;
      }
    } else {
      final initial = getInitialBalance(accountId);
      cum = initial;
      for (final tx in visible) {
        final effect = (tx.type == TransactionType.income ? tx.amount : -tx.amount);
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
      foundation.debugPrint('DatabaseService.setSetting skipped before init for key: $key');
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
      if (v is List || v is Set) return (v as Iterable).map((e) => _sanitizeForJson(e)).toList();
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
      final raw = _settingsBox.get(_hiddenTransactionsKey, defaultValue: <dynamic>[]) as List<dynamic>;
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
      final raw = _settingsBox.get('customAccountTypes', defaultValue: <dynamic>[]) as List<dynamic>;
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
  static List<Map<String, dynamic>> getAllPayees() {
    try {
      final raw = _settingsBox.get('payees', defaultValue: <dynamic>[]) as List<dynamic>;
      final out = <Map<String, dynamic>>[];
      for (final e in raw) {
        if (e is Map) {
          out.add(Map<String, dynamic>.from(e));
        } else if (e is String) {
          try {
            final decoded = json.decode(e) as Map<String, dynamic>;
            out.add(decoded);
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
      // Ensure we only write primitive / JSON-encodable maps
      final normalized = Map<String, dynamic>.from(payee.map((k, v) => MapEntry(k, v?.toString())));
      list.add(normalized);
  await _settingsBox.put('payees', list);
  await _settingsBox.flush();
  // Notify listeners
  payeesVersion.value++;
  // ignore: avoid_print
  print('DatabaseService.addPayee stored payees: ${_settingsBox.get('payees')}');
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
        final normalized = Map<String, dynamic>.from(payee.map((k, v) => MapEntry(k, v?.toString())));
        list[idx] = normalized;
        await _settingsBox.put('payees', list);
        await _settingsBox.flush();
        // Notify listeners
        payeesVersion.value++;
        // ignore: avoid_print
        print('DatabaseService.updatePayee stored payees: ${_settingsBox.get('payees')}');
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
  print('DatabaseService.deletePayee stored payees: ${_settingsBox.get('payees')}');
    } catch (e) {
      // ignore: avoid_print
      print('DatabaseService.deletePayee failed: $e');
    }
  }

  // Analytics helpers
  static double getTotalBalance() {
    return _accountBox.values.fold(0.0, (sum, account) => sum + account.balance);
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
    final expenses = getTransactionsByDateRange(startDate, endDate)
        .where((transaction) => transaction.type == TransactionType.expense);

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
  static List<Map<String, dynamic>> getBillOccurrencesBetween(DateTime startDate, DateTime endDate) {
    final out = <Map<String, dynamic>>[];
    final bills = getAllBills();
    for (final bill in bills) {
      final seenForBill = <String>{};
      // Skip bills that end before the requested range
      if (bill.recurrenceEndDate != null && bill.recurrenceEndDate!.isBefore(startDate)) continue;

      // Helper to add an occurrence if within bounds
      void addIfInRange(DateTime occ) {
        if ((occ.isAtSameMomentAs(startDate) || occ.isAfter(startDate)) &&
            (occ.isAtSameMomentAs(endDate) || occ.isBefore(endDate))) {
          final key = '${occ.year}-${occ.month}-${occ.day}';
          if (seenForBill.contains(key)) return;
          seenForBill.add(key);
          out.add({'bill': bill, 'date': occ});
        }
      }

      switch (bill.recurrence) {
        case Recurrence.none:
          addIfInRange(DateTime(bill.dueDate.year, bill.dueDate.month, bill.dueDate.day));
          break;
        case Recurrence.daily:
          {
            final interval = bill.recurrenceInterval <= 0 ? 1 : bill.recurrenceInterval;
            DateTime cur = DateTime(bill.dueDate.year, bill.dueDate.month, bill.dueDate.day);
            // iterate until the earlier of recurrenceEndDate (if any) or endDate
            while (!(bill.recurrenceEndDate != null && cur.isAfter(bill.recurrenceEndDate!)) && !cur.isAfter(endDate)) {
              if (!cur.isBefore(startDate)) addIfInRange(cur);
              cur = cur.add(Duration(days: interval));
            }
          }
          break;
        case Recurrence.weekly:
          {
            final intervalWeeks = bill.recurrenceInterval <= 0 ? 1 : bill.recurrenceInterval;
            final weekdays = (bill.recurrenceWeekdays == null || bill.recurrenceWeekdays!.isEmpty) ? [bill.dueDate.weekday] : bill.recurrenceWeekdays!;
            
            // Start from the bill's due date
            DateTime cur = DateTime(bill.dueDate.year, bill.dueDate.month, bill.dueDate.day);
            
            // If the due date is after our range, we need to find earlier occurrences
            // Otherwise start from due date and go forward
            if (cur.isAfter(endDate)) break;
            
            // Generate occurrences week by week
            while (!cur.isAfter(endDate) && !(bill.recurrenceEndDate != null && cur.isAfter(bill.recurrenceEndDate!))) {
              // Check each weekday in the current week
              for (int i = 0; i < 7; i++) {
                final checkDate = cur.add(Duration(days: i));
                if (weekdays.contains(checkDate.weekday)) {
                  if (!checkDate.isAfter(endDate) && 
                      !(bill.recurrenceEndDate != null && checkDate.isAfter(bill.recurrenceEndDate!))) {
                    addIfInRange(checkDate);
                  }
                }
              }
              // Move to next interval
              cur = cur.add(Duration(days: 7 * intervalWeeks));
            }
          }
          break;
        case Recurrence.monthly:
          {
            final intervalMonths = bill.recurrenceInterval <= 0 ? 1 : bill.recurrenceInterval;
            final days = ((bill.customDays == null || bill.customDays!.isEmpty)
                    ? <int>[bill.dueDate.day]
                    : bill.customDays!)
                .toSet()
                .toList()
              ..sort();
            int currentYear = bill.dueDate.year;
            int currentMonth = bill.dueDate.month;
            while (true) {
              final monthStart = DateTime(currentYear, currentMonth, 1);
              if (monthStart.isAfter(endDate)) break;
              if (bill.recurrenceEndDate != null && monthStart.isAfter(bill.recurrenceEndDate!)) break;
              for (final d in days) {
                try {
                  int day = d;
                  if (d == 99) {
                    // Calculate last day of the month
                    day = DateTime(currentYear, currentMonth + 1, 0).day;
                  }
                  final occ = DateTime(currentYear, currentMonth, day);

                  // IMPORTANT: Do not generate occurrences in the bill's starting
                  // month that are before the bill's original due date. Example:
                  // bill.dueDate = 15th, customDays = [1,15] -> do not create
                  // an occurrence for the 1st of the same month as the dueDate.
                  final billStartDate = DateTime(bill.dueDate.year, bill.dueDate.month, bill.dueDate.day);
                  if (currentYear == bill.dueDate.year && currentMonth == bill.dueDate.month && occ.isBefore(billStartDate)) {
                    continue; // skip past-day occurrences in the first month
                  }

                  if (!occ.isAfter(endDate) && (bill.recurrenceEndDate == null || !occ.isAfter(bill.recurrenceEndDate!))) {
                    addIfInRange(occ);
                  }
                } catch (_) {
                  // invalid day (e.g., Feb 30) — skip
                }
              }
              currentMonth += intervalMonths;
              while (currentMonth > 12) {
                currentMonth -= 12;
                currentYear += 1;
              }
            }
          }
          break;
        case Recurrence.yearly:
          {
            final intervalYears = bill.recurrenceInterval <= 0 ? 1 : bill.recurrenceInterval;
            DateTime cur = DateTime(bill.dueDate.year, bill.dueDate.month, bill.dueDate.day);
            while (!(bill.recurrenceEndDate != null && cur.isAfter(bill.recurrenceEndDate!)) && !cur.isAfter(endDate)) {
              if (!cur.isBefore(startDate)) addIfInRange(cur);
              cur = DateTime(cur.year + intervalYears, cur.month, cur.day);
            }
          }
          break;
        case Recurrence.custom:
          // custom recurrence semantics not implemented — fallback to dueDate
          addIfInRange(DateTime(bill.dueDate.year, bill.dueDate.month, bill.dueDate.day));
          break;
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
  static Future<void> persistBillOccurrenceStatuses({DateTime? from, DateTime? to}) async {
    final bills = getAllBills();
    if (bills.isEmpty) return;

    final earliest = bills.map((b) => b.dueDate).reduce((a, b) => a.isBefore(b) ? a : b);
    final start = from ?? DateTime(earliest.year, earliest.month, earliest.day);
    final end = to ?? DateTime.now();

    final allTransactions = getAllTransactions();

    for (final bill in bills) {
      final occurrences = getBillOccurrencesBetween(start, end).where((o) => o['bill'].id == bill.id).toList();
      for (final occ in occurrences) {
        final occDate = occ['date'] as DateTime;
        final occDateStr = DateFormat('MM/dd/yyyy').format(occDate);

        // Sum matching payments for this occurrence
        double totalPaid = 0.0;
        for (final tx in allTransactions) {
          if (tx.billId != bill.id) continue;
          if (tx.occurrenceDate != null) {
            if (tx.occurrenceDate!.year == occDate.year && tx.occurrenceDate!.month == occDate.month && tx.occurrenceDate!.day == occDate.day) {
              if (bill.type == BillType.expense) {
                totalPaid += (tx.type == TransactionType.expense) ? tx.amount : -tx.amount;
              } else {
                totalPaid += (tx.type == TransactionType.income) ? tx.amount : -tx.amount;
              }
            }
          } else if (tx.date.year == occDate.year && tx.date.month == occDate.month && tx.date.day == occDate.day) {
            if (bill.type == BillType.expense) {
              totalPaid += (tx.type == TransactionType.expense) ? tx.amount : -tx.amount;
            } else {
              totalPaid += (tx.type == TransactionType.income) ? tx.amount : -tx.amount;
            }
          } else if (tx.description.contains(occDateStr)) {
            if (bill.type == BillType.expense) {
              totalPaid += (tx.type == TransactionType.expense) ? tx.amount : -tx.amount;
            } else {
              totalPaid += (tx.type == TransactionType.income) ? tx.amount : -tx.amount;
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
        await setBillOccurrenceStatus(bill.id, occDate, newStatus == PaymentStatus.paid, newStatus);
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

    if (accounts.isNotEmpty) {
      for (final account in accounts) {
        if (account.id.trim().isEmpty) continue;
        await _accountBox.put(account.id, account);
      }
      await _accountBox.flush();
      accountsChanged = true;
    }

    if (categories.isNotEmpty) {
      for (final category in categories) {
        if (category.id.trim().isEmpty) continue;
        await _categoryBox.put(category.id, category);
      }
      await _categoryBox.flush();
      categoriesChanged = true;
    }

    if (bills.isNotEmpty) {
      for (final bill in bills) {
        if (bill.id.trim().isEmpty) continue;
        await _billsBox.put(bill.id, bill);
      }
      await _billsBox.flush();
      billsChanged = true;
    }

    if (transactions.isNotEmpty) {
      for (final tx in transactions) {
        if (tx.id.trim().isEmpty) continue;
        await _transactionBox.put(tx.id, tx);
      }
      await _transactionBox.flush();
      transactionsChanged = true;
    }

    if (payments.isNotEmpty) {
      for (final raw in payments) {
        try {
          final billId = (raw['billId'] ?? raw['bill_id'] ?? '').toString();
          final dateRaw =
              raw['occurrenceDate'] ?? raw['paymentDate'] ?? raw['date'] ?? raw['dueDate'];
          if (billId.isEmpty || dateRaw == null) continue;

          final date = DateTime.tryParse(dateRaw.toString());
          if (date == null) continue;

          final statusRaw = (raw['paymentStatus'] ?? raw['status'] ?? '').toString().toLowerCase();
          final isPaidRaw = raw['isPaid'];
          final bool isPaid = isPaidRaw == true || statusRaw == 'paid';
          final PaymentStatus status = statusRaw == 'partial'
              ? PaymentStatus.partial
              : (isPaid ? PaymentStatus.paid : PaymentStatus.unpaid);

          final key = _occurrenceKey(
            billId,
            DateTime(date.year, date.month, date.day),
          );
          await _billOccurrenceBox.put(
            key,
            {'isPaid': isPaid, 'paymentStatus': status.index},
          );
          billsChanged = true;
        } catch (_) {}
      }
      await _billOccurrenceBox.flush();
    }

    if (payees.isNotEmpty || payers.isNotEmpty) {
      final merged = <String, Map<String, dynamic>>{};

      void mergeContacts(List<Map<String, dynamic>> entries, String defaultType) {
        for (final item in entries) {
          final id = (item['id'] ?? '').toString().trim();
          final name = (item['name'] ?? '').toString().trim();
          if (id.isEmpty || name.isEmpty) continue;
          merged[id] = {
            'id': id,
            'name': name,
            'type': (item['type'] ?? defaultType).toString(),
            'categoryId': item['categoryId']?.toString(),
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
  static Future<void> importBillOccurrenceStatuses(Map<String, dynamic> data) async {
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
