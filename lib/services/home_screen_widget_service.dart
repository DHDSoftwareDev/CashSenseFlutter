import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import '../models/bill.dart';
import '../models/transaction.dart';
import '../utils/bill_note_utils.dart';
import '../utils/root_scaffold.dart';
import 'database_service.dart';

/// Keeps the native iOS and Android home-screen widgets in sync with Hive.
///
/// Native widgets cannot open the app's Hive boxes, so this service publishes a
/// compact JSON snapshot to the storage shared by `home_widget`.
class HomeScreenWidgetService {
  HomeScreenWidgetService._();

  static const String appGroupId =
      'group.name.dhdsoftware.cashsense.CashSenseMM';
  static const String snapshotKey = 'cashsense_widget_snapshot';
  static const String hideBalancesSettingKey = 'hideAccountBalancesInWidgets';

  static const String billsIOSKind = 'ConfigurableUpcomingBillsWidget';
  static const String balancesIOSKind = 'ConfigurableAccountBalancesWidget';
  static const String billsAndroidProvider = 'UpcomingBillsWidgetProvider';
  static const String balancesAndroidProvider = 'AccountBalancesWidgetProvider';
  static const String androidPackage = 'name.dhdsoftware.cashsenseflutter';

  static StreamSubscription<Uri?>? _widgetClickSubscription;
  static Timer? _syncDebounce;
  static bool _initialized = false;
  static bool _syncing = false;
  static bool _syncAgain = false;

  static bool get _isSupported =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  static Future<void> initialize() async {
    if (_initialized || !_isSupported) return;
    _initialized = true;

    if (Platform.isIOS) {
      await HomeWidget.setAppGroupId(appGroupId);
    }

    DatabaseService.billsVersion.addListener(_scheduleSync);
    DatabaseService.accountsVersion.addListener(_scheduleSync);
    DatabaseService.transactionsVersion.addListener(_scheduleSync);

    _widgetClickSubscription = HomeWidget.widgetClicked.listen(
      _handleWidgetUri,
      onError: (Object error) {
        debugPrint('Home widget click stream failed: $error');
      },
    );

    final initialUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
    if (initialUri != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(
          const Duration(milliseconds: 250),
          () => _handleWidgetUri(initialUri),
        );
      });
    }

    await syncNow();
  }

  static void _scheduleSync() {
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 300), syncNow);
  }

  static Future<void> syncNow() async {
    if (!_isSupported) return;
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    try {
      final snapshot = buildSnapshot(now: DateTime.now());
      await HomeWidget.saveWidgetData<String>(
        snapshotKey,
        jsonEncode(snapshot),
        appGroupId: Platform.isIOS ? appGroupId : null,
      );

      await Future.wait<bool?>([
        HomeWidget.updateWidget(
          iOSName: billsIOSKind,
          qualifiedAndroidName: '$androidPackage.$billsAndroidProvider',
        ),
        HomeWidget.updateWidget(
          iOSName: balancesIOSKind,
          qualifiedAndroidName: '$androidPackage.$balancesAndroidProvider',
        ),
      ]);

      if (Platform.isAndroid) {
        final now = DateTime.now();
        final updateTimes = <DateTime>[
          for (var day = 1; day <= 7; day++)
            DateTime(now.year, now.month, now.day + day, 0, 1),
        ];
        await HomeWidget.scheduleWidgetUpdates(
          updateTimes,
          qualifiedAndroidName: '$androidPackage.$billsAndroidProvider',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Home-screen widget sync failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _syncing = false;
      if (_syncAgain) {
        _syncAgain = false;
        unawaited(syncNow());
      }
    }
  }

  @visibleForTesting
  static Map<String, dynamic> buildSnapshot({required DateTime now}) {
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime(today.year + 1, today.month, today.day);
    final storedBills = DatabaseService.getAllBills();
    final start = storedBills.isEmpty
        ? today
        : storedBills
              .map(
                (bill) => DateTime(
                  bill.dueDate.year,
                  bill.dueDate.month,
                  bill.dueDate.day,
                ),
              )
              .reduce(
                (earliest, date) => date.isBefore(earliest) ? date : earliest,
              );
    final transactions = DatabaseService.getAllTransactions();
    final occurrences = DatabaseService.getBillOccurrencesBetween(start, end);
    final pastDueBills = <Map<String, dynamic>>[];
    final currentAndFutureBills = <Map<String, dynamic>>[];

    for (final occurrence in occurrences) {
      final bill = occurrence['bill'] as Bill;
      final dueDate = occurrence['date'] as DateTime;
      final paymentStatus = _occurrenceStatus(bill, dueDate, transactions);
      final item = <String, dynamic>{
        'id': '${bill.id}:${dueDate.millisecondsSinceEpoch}',
        'name': _billDisplayName(bill),
        'note': _billNote(bill),
        'amount': bill.amount,
        'dueMillis': dueDate.millisecondsSinceEpoch,
        'type': bill.type.name,
        'paymentStatus': paymentStatus.name,
      };
      if (dueDate.isBefore(today)) {
        if (paymentStatus != PaymentStatus.paid) {
          pastDueBills.add(item);
        }
      } else {
        currentAndFutureBills.add(item);
      }
    }

    int compareByDueDate(Map<String, dynamic> a, Map<String, dynamic> b) =>
        (a['dueMillis'] as int).compareTo(b['dueMillis'] as int);
    pastDueBills.sort(compareByDueDate);
    currentAndFutureBills.sort(compareByDueDate);

    // Preserve overdue items for the overdue filters without letting a long
    // payment history crowd future items out of the native widget timeline.
    final bills = <Map<String, dynamic>>[
      ...pastDueBills.take(50),
      ...currentAndFutureBills.take(100),
    ];

    final hideBalances =
        DatabaseService.getSetting<bool>(hideBalancesSettingKey, false) ??
        false;
    final primaryColor =
        DatabaseService.getSetting<int>('primaryColor', 0xFF2E7D32) ??
        0xFF2E7D32;
    final accounts = DatabaseService.getAllAccounts()
        .map(
          (account) => {
            'id': account.id,
            'name': account.name,
            'currency': account.currency,
            'balance': DatabaseService.getDisplayBalanceForAccount(
              account.id,
              showAvailable: true,
              includeCleared: true,
            ),
            'currentBalance': DatabaseService.getDisplayBalanceForAccount(
              account.id,
              showAvailable: false,
              includeCleared: true,
            ),
          },
        )
        .toList();
    final totalAvailable = accounts.fold<double>(
      0,
      (sum, account) => sum + (account['balance'] as num).toDouble(),
    );
    final totalCurrent = accounts.fold<double>(
      0,
      (sum, account) => sum + (account['currentBalance'] as num).toDouble(),
    );
    final currencies = accounts
        .map((account) => account['currency'] as String)
        .toSet();

    return {
      'version': 1,
      'generatedAtMillis': now.millisecondsSinceEpoch,
      'hideBalances': hideBalances,
      'primaryColor': primaryColor,
      'bills': bills,
      'accounts': accounts,
      'totalAvailable': totalAvailable,
      'totalCurrent': totalCurrent,
      'totalCurrency': currencies.length == 1 ? currencies.first : 'USD',
      'hasMixedCurrencies': currencies.length > 1,
    };
  }

  static String _billDisplayName(Bill bill) {
    final payeeName = _billPayeeName(bill);
    if (payeeName.isNotEmpty) return payeeName;

    if (bill.type == BillType.transfer) {
      final fromName = _accountName(bill.fromAccountId);
      final toName = _accountName(bill.toAccountId);
      if (fromName.isNotEmpty && toName.isNotEmpty) {
        return 'Transfer from $fromName to $toName';
      }
    }

    return switch (bill.type) {
      BillType.expense => 'Bill',
      BillType.income => 'Expected income',
      BillType.transfer => 'Scheduled transfer',
    };
  }

  static String _billNote(Bill bill) {
    return editableBillNote(
      bill,
      payeeName: _billPayeeName(bill),
      fromAccountName: _accountName(bill.fromAccountId),
      toAccountName: _accountName(bill.toAccountId),
    );
  }

  static String _billPayeeName(Bill bill) {
    if (bill.payeeId == null || bill.payeeId!.isEmpty) return '';
    final payee = DatabaseService.getAllPayees().where(
      (item) => item['id'] == bill.payeeId,
    );
    if (payee.isEmpty) return '';
    return (payee.first['name'] ?? '').toString().trim();
  }

  static String _accountName(String? accountId) {
    if (accountId == null || accountId.isEmpty) return '';
    return DatabaseService.getAccountById(accountId)?.name.trim() ?? '';
  }

  static PaymentStatus _occurrenceStatus(
    Bill bill,
    DateTime occurrenceDate,
    List<Transaction> transactions,
  ) {
    final persisted = DatabaseService.getBillOccurrenceStatus(
      bill.id,
      occurrenceDate,
    );
    final persistedStatus = persisted?['paymentStatus'];
    if (persistedStatus is PaymentStatus) return persistedStatus;

    double totalPaid = 0;
    for (final transaction in transactions) {
      if (transaction.billId != bill.id) continue;
      final transactionDate = transaction.occurrenceDate ?? transaction.date;
      if (!_sameDay(transactionDate, occurrenceDate)) continue;
      if (bill.type == BillType.expense) {
        totalPaid += transaction.type == TransactionType.expense
            ? transaction.amount
            : -transaction.amount;
      } else {
        totalPaid += transaction.type == TransactionType.income
            ? transaction.amount
            : -transaction.amount;
      }
    }
    if (totalPaid <= 0) return PaymentStatus.unpaid;
    if (totalPaid >= bill.amount - 0.01) return PaymentStatus.paid;
    return PaymentStatus.partial;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static void _handleWidgetUri(Uri? uri) {
    if (uri == null || uri.scheme.toLowerCase() != 'cashsense') return;
    switch (uri.host.toLowerCase()) {
      case 'bills':
        final millis = int.tryParse(uri.queryParameters['date'] ?? '');
        final date = millis == null
            ? DateTime.now()
            : DateTime.fromMillisecondsSinceEpoch(millis);
        navigateToRootPage(0, selectedDate: date);
        break;
      case 'accounts':
        final accountId = uri.queryParameters['accountId'];
        if (accountId != null && accountId.isNotEmpty) {
          navigateToRootPage(1, accountId: accountId);
        } else {
          navigateToRootPage(4);
        }
        break;
    }
  }

  @visibleForTesting
  static Future<void> dispose() async {
    _syncDebounce?.cancel();
    DatabaseService.billsVersion.removeListener(_scheduleSync);
    DatabaseService.accountsVersion.removeListener(_scheduleSync);
    DatabaseService.transactionsVersion.removeListener(_scheduleSync);
    await _widgetClickSubscription?.cancel();
    _initialized = false;
  }
}
