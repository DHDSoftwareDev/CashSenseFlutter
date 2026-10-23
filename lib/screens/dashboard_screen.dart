// ignore_for_file: unnecessary_non_null_assertion, duplicate_ignore, unused_field, unused_element, annotate_overrides, valid_regexps, unnecessary_brace_in_string_interps
// ignore_for_file: no_leading_underscores_for_local_identifiers, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'dart:convert';
import 'package:table_calendar/table_calendar.dart';
import '../widgets/banner_ad_widget.dart';
import '../utils/root_scaffold.dart';
import '../services/database_service.dart';
import '../services/bill_reminder_service.dart';
import '../services/lookups_state.dart';
import '../models/transaction.dart';
import '../models/bill.dart';
import '../models/category.dart';
import '../theme/app_theme.dart';
import '../utils/duplication_guards.dart';
import 'add_bill_screen.dart';
import 'add_transaction_screen.dart';
import 'pay_bill_screen.dart';

// ...existing code...

// Use PaymentStatus from models/bill.dart

// Wrapper to track whether a transaction is from a bill occurrence or a real transaction
class TransactionDisplayItem {
  final Transaction transaction;
  final Bill? sourceBill; // null if it's a real transaction

  TransactionDisplayItem(this.transaction, {this.sourceBill});

  bool get isBillOccurrence => sourceBill != null;
}

class DashboardTitleInline extends StatelessWidget {
  const DashboardTitleInline({super.key});

  @override
  Widget build(BuildContext context) {
    final baseStyle = Theme.of(context).textTheme.titleLarge;

    final iconWidget = Image.asset(
      'assets/images/cash_icon.png',
      width: 40,
      height: 47,
      fit: BoxFit.cover,
    );

    return SizedBox(
      width: double.infinity,
      child: Center(
        child: Text.rich(
          TextSpan(
            style: baseStyle,
            children: [
              const TextSpan(text: 'Cash'),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: EdgeInsets.zero,
                  // small left translate to pull the icon slightly into the preceding text
                  child: Transform.translate(
                    offset: const Offset(-7.5, 2),
                    child: iconWidget,
                  ),
                ),
              ),
              // Use a WidgetSpan so we can nudge the trailing text left without splitting the title
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Transform.translate(
                  offset: const Offset(-14.5, 0),
                  child: Text('ense Money Manager', style: baseStyle),
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  // Helper to determine whether a given PaymentStatus should be included
  // by the current filter selection. Treat Partial as matching Unpaid when
  // the Unpaid filter is active so users see partial payments in the
  // Unpaid category.
}

class DashboardScreen extends StatefulWidget {
  final DateTime? initialSelectedDate;

  const DashboardScreen({super.key, this.initialSelectedDate});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const String _showPaidBillsSettingKey = 'dashboardShowPaidBills';

  // Duplicate helper removed — use the top-level _buildCategoryIconOrEmoji defined earlier.
  @override
  void initState() {
    super.initState();
    final initialDate = widget.initialSelectedDate ?? DateTime.now();
    _focusedDay = _dateOnly(initialDate);
    _selectedDay = _dateOnly(initialDate);
    _showPaidBills =
        DatabaseService.getSetting<bool>(_showPaidBillsSettingKey, false) ??
        false;
    _refreshCachedData();
    DatabaseService.categoriesVersion.addListener(_onCategoriesChanged);
    DatabaseService.billsVersion.addListener(_onBillsChanged);
    DatabaseService.payeesVersion.addListener(_onPayeesChanged);
    DatabaseService.transactionsVersion.addListener(_onTransactionsChanged);

    // Add listener to search focus node to show/hide dropdown
    _searchFocusNode.addListener(() {
      if (_searchFocusNode.hasFocus &&
          _searchQuery.isNotEmpty &&
          _searchResults.isNotEmpty) {
        _showSearchDropdown();
      } else if (!_searchFocusNode.hasFocus) {
        _removeSearchDropdown();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleOccurrenceStatusBackgroundSync();
    });
  }

  void _onCategoriesChanged() {
    if (!mounted) return;
    _refreshCachedData();
    setState(() {}); // Triggers rebuild to update category names/colors/icons
  }

  void _onBillsChanged() {
    if (!mounted) return;
    _refreshCachedData();
    _occurrenceStatusCache.clear();
    if (!_suppressOccurrenceStatusSync) {
      _scheduleOccurrenceStatusBackgroundSync();
    }
    if (_searchQuery.isNotEmpty) {
      _performSearch(_searchController.text);
      return;
    }
    setState(() {});
  }

  void _onTransactionsChanged() {
    if (!mounted) return;
    _refreshCachedData();
    _occurrenceStatusCache.clear();
    if (!_suppressOccurrenceStatusSync) {
      _scheduleOccurrenceStatusBackgroundSync();
    }
    if (_searchQuery.isNotEmpty) {
      _performSearch(_searchController.text);
      return;
    }
    setState(() {});
  }

  void _onPayeesChanged() {
    if (!mounted) return;
    _refreshCachedData();
    if (_searchQuery.isNotEmpty) {
      _performSearch(_searchController.text);
      return;
    }
    setState(() {}); // Triggers rebuild to update payee names
  }

  // Compute the next occurrence date for a recurring bill after `occurrenceDate`.
  // Handles monthly recurrence with `customDays` (e.g., [1,15]) so that the
  // next occurrence may be later in the same month rather than jumping to the
  // next month.
  DateTime? _computeNextOccurrenceDate(
    Bill sourceBill,
    DateTime occurrenceDate,
  ) {
    if (sourceBill.recurrence == Recurrence.monthly) {
      final interval = sourceBill.recurrenceInterval <= 0
          ? 1
          : sourceBill.recurrenceInterval;
      final days = _normalizedMonthlyDays(sourceBill);

      // Try to find next configured day in the same month
      final year = occurrenceDate.year;
      final month = occurrenceDate.month;
      final lastDayThisMonth = DateTime(year, month + 1, 0).day;
      for (final d in days) {
        final day = d == 99 ? lastDayThisMonth : d;
        if (day > occurrenceDate.day && day <= lastDayThisMonth) {
          return DateTime(year, month, day);
        }
      }

      // No later day in this month; roll forward by `interval` months and pick
      // the first configured day in that month.
      int targetMonth = month + interval;
      int targetYear = year + (targetMonth - 1) ~/ 12;
      final adjustedMonth = ((targetMonth - 1) % 12) + 1;
      final lastDayTarget = DateTime(targetYear, adjustedMonth + 1, 0).day;
      int chosen = days.first;
      if (chosen == 99) chosen = lastDayTarget;
      if (chosen > lastDayTarget) {
        chosen = lastDayTarget; // guard for e.g., 31 in Feb
      }
      return DateTime(targetYear, adjustedMonth, chosen);
    }

    // Fallback: daily/weekly/yearly use previous logic based on occurrenceDate
    if (sourceBill.recurrence == Recurrence.daily) {
      return _addCalendarDays(
        occurrenceDate,
        sourceBill.recurrenceInterval <= 0 ? 1 : sourceBill.recurrenceInterval,
      );
    }
    if (sourceBill.recurrence == Recurrence.weekly) {
      final start = _addCalendarDays(occurrenceDate, 1);
      final occurrences = DatabaseService.generateBillOccurrenceDatesForRange(
        sourceBill,
        start,
        _addCalendarDays(start, 370),
      );
      return occurrences.isEmpty ? null : occurrences.first;
    }
    if (sourceBill.recurrence == Recurrence.yearly) {
      final yrs = sourceBill.recurrenceInterval <= 0
          ? 1
          : sourceBill.recurrenceInterval;
      try {
        return DateTime(
          occurrenceDate.year + yrs,
          occurrenceDate.month,
          occurrenceDate.day,
        );
      } catch (_) {
        // invalid (Feb 29) fallback to last day of month
        return DateTime(occurrenceDate.year + yrs, occurrenceDate.month + 1, 0);
      }
    }

    return null;
  }

  // Overlay dropdown for bill search
  OverlayEntry? _searchDropdownOverlay;
  final ScrollController _searchResultsScrollController = ScrollController();
  int? _searchInitialIndex;

  void _positionSearchResultsAtToday() {
    if (_searchResults.isEmpty) return;
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    // Anchor the dropdown at today when possible. If there is no exact
    // today match, start at the nearest past result (not a future entry).
    var idx = _searchResults.lastIndexWhere((r) {
      final d = r['date'] as DateTime;
      final normalized = DateTime(d.year, d.month, d.day);
      return !normalized.isAfter(todayStart);
    });

    if (idx < 0) idx = 0;
    _searchInitialIndex = idx;
  }

  void _showSearchDropdown() {
    if (_searchDropdownOverlay != null) {
      _searchDropdownOverlay!.markNeedsBuild();
      return;
    }

    final overlay = Overlay.of(context);
    final RenderBox? box = _searchFocusNode.hasFocus
        ? _searchFocusNode.context?.findRenderObject() as RenderBox?
        : null;
    final offset = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final width = box?.size.width ?? MediaQuery.of(context).size.width;
    _searchDropdownOverlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: offset.dx,
          top: offset.dy + (box?.size.height ?? 40),
          width: width,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                child: ListView.builder(
                  controller: _searchResultsScrollController,
                  itemExtent: 72,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final result = _searchResults[index];
                    final bill = result['bill'] as Bill;
                    final date = result['date'] as DateTime;
                    final description = result['description'] as String;
                    final dateStr = DateFormat('MM/dd/yyyy').format(date);
                    return ListTile(
                      title: Text(
                        description,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        dateStr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        _currencyFormat.format(bill.amount),
                        style: TextStyle(
                          color: bill.type == BillType.expense
                              ? Colors.red
                              : Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          _selectedDay = date;
                          _focusedDay = date;
                          _searchController.clear();
                          _performSearch('');
                          _searchFocusNode.unfocus();
                        });
                        _removeSearchDropdown();
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_searchDropdownOverlay!);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _searchDropdownOverlay == null) return;
      if (!_searchResultsScrollController.hasClients) return;
      if (_searchInitialIndex == null) return;
      final targetOffset = (_searchInitialIndex!.toDouble() * 72.0).clamp(
        0.0,
        _searchResultsScrollController.position.maxScrollExtent,
      );
      _searchResultsScrollController.jumpTo(targetOffset);
    });
  }

  void _removeSearchDropdown() {
    _searchDropdownOverlay?.remove();
    _searchDropdownOverlay = null;
  }

  void _closeSearchInteraction() {
    _removeSearchDropdown();
    if (_searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
    }
  }

  // Compute signed total paid for a list of transactions relative to a bill.
  // For expense bills: expense tx increase paid total, income tx (refunds) decrease it.
  // For income bills: income tx increase paid total, expense tx (chargebacks) decrease it.
  double _computeSignedTotalPaid(Bill bill, List<Transaction> txs) {
    double total = 0.0;
    for (final tx in txs) {
      if (bill.type == BillType.expense) {
        total += (tx.type == TransactionType.expense) ? tx.amount : -tx.amount;
      } else {
        total += (tx.type == TransactionType.income) ? tx.amount : -tx.amount;
      }
    }
    return total;
  }

  String _visibleBillText(String? raw) {
    final text = (raw ?? '').trim();
    if (text.toLowerCase() == 'bill') return '';
    return text;
  }

  String _billNoteText(Bill bill) {
    final text = _visibleBillText(bill.description);
    if (text.isEmpty) return '';

    final lowerText = text.toLowerCase();
    if (bill.payeeId != null && bill.payeeId!.isNotEmpty) {
      final payee = _allPayeesCache.firstWhere(
        (p) => p['id'] == bill.payeeId,
        orElse: () => <String, dynamic>{},
      );
      final payeeName = (payee['name'] ?? '').toString().trim().toLowerCase();
      if (payeeName.isNotEmpty && lowerText == payeeName) return '';
    }

    if (bill.type == BillType.transfer) {
      final fromName =
          (bill.fromAccountId != null && bill.fromAccountId!.isNotEmpty)
          ? DatabaseService.getAccountById(bill.fromAccountId!)?.name
          : null;
      final toName = (bill.toAccountId != null && bill.toAccountId!.isNotEmpty)
          ? DatabaseService.getAccountById(bill.toAccountId!)?.name
          : null;
      if (fromName != null && toName != null) {
        final generated = 'transfer from $fromName to $toName'.toLowerCase();
        if (lowerText == generated) return '';
      }
    }

    return text;
  }

  void dispose() {
    _searchDebounceTimer?.cancel();
    _occurrenceStatusSyncDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchResultsScrollController.dispose();
    DatabaseService.categoriesVersion.removeListener(_onCategoriesChanged);
    DatabaseService.billsVersion.removeListener(_onBillsChanged);
    DatabaseService.payeesVersion.removeListener(_onPayeesChanged);
    DatabaseService.transactionsVersion.removeListener(_onTransactionsChanged);
    super.dispose();
  }

  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: '\$');
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  // Bill visibility toggle: hide paid occurrences by default.
  bool _showPaidBills = false;
  // Track expanded transaction cards
  final Set<String> _expandedTransactionIds = <String>{};

  // Search functionality
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebounceTimer;
  String _searchQuery = '';
  final List<Map<String, dynamic>> _searchResults = [];
  final Set<String> _matchedSearchBillIds = <String>{};
  final Map<String, PaymentStatus> _occurrenceStatusCache =
      <String, PaymentStatus>{};
  List<Bill> _allBillsCache = <Bill>[];
  List<Map<String, dynamic>> _allPayeesCache = <Map<String, dynamic>>[];
  List<Transaction> _allTransactionsCache = <Transaction>[];
  List<Transaction> _visibleTransactionsCache = <Transaction>[];
  Timer? _occurrenceStatusSyncDebounce;
  bool _occurrenceStatusSyncInFlight = false;
  bool _suppressOccurrenceStatusSync = false;

  void _refreshCachedData() {
    _allBillsCache = DatabaseService.getAllBills();
    _allPayeesCache = DatabaseService.getAllPayees();
    _allTransactionsCache = DatabaseService.getAllTransactions();
    _visibleTransactionsCache = _allTransactionsCache
        .where((t) => t.hideFromCalendarDashboard != true)
        .toList();
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  List<int> _normalizedMonthlyDays(Bill bill) {
    final rawDays = bill.customDays == null || bill.customDays!.isEmpty
        ? <int>[bill.dueDate.day]
        : bill.customDays!;

    final validDays = rawDays.where((day) => day >= 1 && day <= 31).toSet();

    if (rawDays.contains(99) || validDays.containsAll(<int>{30, 31})) {
      return <int>[99];
    }

    return validDays.toList()..sort();
  }

  DateTime _addCalendarDays(DateTime date, int days) {
    return DateTime(date.year, date.month, date.day + days);
  }

  void _scheduleOccurrenceStatusBackgroundSync() {
    if (!mounted) return;
    _occurrenceStatusSyncDebounce?.cancel();
    _occurrenceStatusSyncDebounce = Timer(
      const Duration(milliseconds: 450),
      () {
        unawaited(_syncOccurrenceStatusesInBackground());
      },
    );
  }

  Future<void> _syncOccurrenceStatusesInBackground() async {
    if (!mounted ||
        _occurrenceStatusSyncInFlight ||
        _suppressOccurrenceStatusSync) {
      return;
    }
    _occurrenceStatusSyncInFlight = true;
    try {
      final DateTime start;
      final DateTime end;
      if (_selectedDay != null) {
        start = _dateOnly(_selectedDay!);
        end = start;
      } else {
        start = DateTime(_focusedDay.year, _focusedDay.month, 1);
        end = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);
      }

      var occurrences = _dedupeBillOccurrences(
        DatabaseService.getBillOccurrencesBetween(start, end),
      );

      if (_searchQuery.isNotEmpty) {
        occurrences = occurrences.where((occ) {
          final bill = occ['bill'] as Bill?;
          return bill != null && _matchedSearchBillIds.contains(bill.id);
        }).toList();
      }

      final updates = <Map<String, dynamic>>[];
      for (final occ in occurrences) {
        final bill = occ['bill'];
        final occDate = occ['date'];
        if (bill is! Bill || occDate is! DateTime) continue;

        final computed = _computeOccurrencePaymentStatus(
          bill,
          occDate,
          _allTransactionsCache,
        );
        final persisted = DatabaseService.getBillOccurrenceStatus(
          bill.id,
          occDate,
        );
        final persistedStatus = persisted?['paymentStatus'] as PaymentStatus?;
        final persistedIsPaid = persisted?['isPaid'] as bool?;
        final persistedFromBool = persistedIsPaid == null
            ? null
            : (persistedIsPaid ? PaymentStatus.paid : PaymentStatus.unpaid);

        if (persistedStatus == computed || persistedFromBool == computed) {
          continue;
        }

        updates.add({'billId': bill.id, 'date': occDate, 'status': computed});
      }

      if (updates.isEmpty) return;

      _suppressOccurrenceStatusSync = true;
      var anyPaid = false;
      for (final update in updates.take(24)) {
        final status = update['status'] as PaymentStatus;
        anyPaid = anyPaid || status == PaymentStatus.paid;
        await DatabaseService.setBillOccurrenceStatus(
          update['billId'] as String,
          update['date'] as DateTime,
          status == PaymentStatus.paid,
          status,
        );
      }
      if (anyPaid) {
        BillReminderService().refreshAllReminders().catchError((e) {
          debugPrint(
            'Bill reminder refresh failed after dashboard paid sync: $e',
          );
        });
      }
    } catch (_) {
      // Keep dashboard responsive even if backfill fails.
    } finally {
      _suppressOccurrenceStatusSync = false;
      _occurrenceStatusSyncInFlight = false;
    }
  }

  String _occurrenceStatusKey(String billId, DateTime occDate) {
    return '$billId:${occDate.year}-${occDate.month}-${occDate.day}';
  }

  String _billOccurrenceRenderKey(Bill bill, DateTime date) {
    final day = '${date.year}-${date.month}-${date.day}';
    // Include bill id so visually similar bills don't collapse into one entry.
    // Otherwise deleting one of duplicates can appear to "come back" immediately.
    final billId = bill.id.trim();
    return [billId, day, bill.type.name].join('|');
  }

  List<Map<String, dynamic>> _dedupeBillOccurrences(
    List<Map<String, dynamic>> occurrences,
  ) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final occ in occurrences) {
      final bill = occ['bill'];
      final date = occ['date'];
      if (bill is! Bill || date is! DateTime) continue;
      final key = _billOccurrenceRenderKey(bill, date);
      if (!seen.add(key)) continue;
      out.add(occ);
    }
    return out;
  }

  bool _billOccurrenceMatchesActiveFilters(Bill bill, DateTime occDate) {
    if (_searchQuery.isNotEmpty && !_matchedSearchBillIds.contains(bill.id)) {
      return false;
    }
    if (!_showPaidBills &&
        _getOccurrencePaymentStatus(bill, occDate) == PaymentStatus.paid) {
      return false;
    }
    return true;
  }

  List<Map<String, dynamic>> _visibleBillOccurrencesForDay(DateTime day) {
    final billDay = _dateOnly(day);
    final billOcc = _dedupeBillOccurrences(
      DatabaseService.getBillOccurrencesBetween(billDay, billDay),
    );

    return billOcc.where((occ) {
      final bill = occ['bill'] as Bill?;
      final occDate = occ['date'] as DateTime?;
      if (bill == null || occDate == null) return false;
      return _billOccurrenceMatchesActiveFilters(bill, occDate);
    }).toList();
  }

  DateTime _firstVisibleBillDateInMonth(DateTime month) {
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    final occurrences = _dedupeBillOccurrences(
      DatabaseService.getBillOccurrencesBetween(monthStart, monthEnd),
    );

    final visibleDates = <DateTime>[];
    for (final occurrence in occurrences) {
      final bill = occurrence['bill'];
      final occDate = occurrence['date'];
      if (bill is! Bill || occDate is! DateTime) continue;
      if (!_billOccurrenceMatchesActiveFilters(bill, occDate)) continue;
      visibleDates.add(_dateOnly(occDate));
    }

    if (visibleDates.isEmpty) return monthStart;
    visibleDates.sort();
    return visibleDates.first;
  }

  // Search bills by description, payee name, or notes
  void _performSearch(String query) {
  final normalizedQuery = query.toLowerCase().trim();

  if (normalizedQuery.isEmpty) {
    if (!mounted) return;

    setState(() {
      _searchQuery = '';
      _searchResults.clear();
      _matchedSearchBillIds.clear();
    });

    _removeSearchDropdown();
    return;
  }

  final payeeNameById = <String, String>{};

  for (final payee in _allPayeesCache) {
    final id = payee['id']?.toString();
    final name = payee['name']?.toString();

    if (id == null ||
        id.isEmpty ||
        name == null ||
        name.isEmpty) {
      continue;
    }

    payeeNameById[id] = name;
  }

  final matchedBillIds = <String>{};

  for (final bill in _allBillsCache) {
    final billDescription =
        _visibleBillText(bill.description);

    final payeeName =
        bill.payeeId != null &&
                bill.payeeId!.isNotEmpty
            ? (payeeNameById[bill.payeeId!] ?? '')
            : '';

    final searchText =
        '$billDescription $payeeName'
            .toLowerCase();

    if (searchText.contains(normalizedQuery)) {
      matchedBillIds.add(bill.id);
    }
  }

  if (!mounted) return;

  setState(() {
    _searchQuery = normalizedQuery;

    _matchedSearchBillIds
      ..clear()
      ..addAll(matchedBillIds);

    // Do not generate years of bill occurrences while typing.
    _searchResults.clear();
  });

  // The calendar and selected-day bill list already use
  // _matchedSearchBillIds, so they update automatically.
  _removeSearchDropdown();
}
  void _scheduleSearch(String query) {
    _searchDebounceTimer?.cancel();

    final normalizedQuery = query.toLowerCase().trim();
    if (normalizedQuery.isEmpty) {
      _performSearch('');
      return;
    }

    _searchDebounceTimer = Timer(
  const Duration(milliseconds: 450), () {
      if (!mounted) return;
      if (_searchController.text.toLowerCase().trim() != normalizedQuery) {
        return;
      }
      _performSearch(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SlidableAutoCloseBehavior(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: openRootDrawer,
          ),
        title: const Text(
  'CashSense',
  style: TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  ),
),
titleSpacing: 0,
centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () async {
                final isSubscriber =
                    (DatabaseService.getSetting<String>(
                          'subscriptionPlan',
                          'Free',
                        ) ??
                        'Free') !=
                    'Free';
                final bills = _allBillsCache;
                if (!isSubscriber && bills.length >= 100) {
                  await showDialog(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Bill/Payment Limit Reached'),
                      content: const Text(
                        'Free users can create up to 100 bills and payments. Subscribe for unlimited bills and payments.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                  return;
                }
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AddBillScreen(),
                  ),
                );
                if (result == true) setState(() {});
              },
            ),
          ],
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
        ),
        // Keep the calendar fixed at the top and make the bills/transactions
        // area scrollable. Use a Column with a fixed calendar area and an
        // Expanded RefreshIndicator/ListView for the scrolling content.
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: _buildCalendarCard(),
            ),
            Padding(
  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
  child: Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _selectedDay != null
                  ? DateFormat('MMMM d').format(_selectedDay!)
                  : 'Bills',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              _selectedDay != null
                  ? 'Bills scheduled for this day'
                  : 'Upcoming bills',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withAlpha(150),
              ),
            ),
          ],
        ),
      ),
      _buildFilterChips(),
    ],
  ),
),
            // The scrolling content (recent transactions, ad, divider) lives
            // inside the Expanded ListView so the calendar remains fixed.
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshData,
                child: ListView(
                  padding: const EdgeInsets.only(
                    bottom: 16,
                    left: 16,
                    right: 16,
                  ),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    _buildRecentTransactionsCard(),
                    const SizedBox(height: 8),
                    const BannerAdWidget(),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

Widget _buildCalendarCard() {
  final colorScheme = Theme.of(context).colorScheme;

  return GestureDetector(
    behavior: HitTestBehavior.translucent,
    onTap: () {
      FocusScope.of(context).unfocus();
    },
    child: Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    color: colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(
        color: colorScheme.outlineVariant.withValues(
          alpha: 0.35,
        ),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
             child: SizedBox(
  height: 48,
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
  hintText: 'Search bills...',
  hintStyle: TextStyle(
    fontSize: 15,
    color: Theme.of(context)
        .colorScheme
        .onSurfaceVariant,
  ),
  prefixIcon: Icon(
    Icons.search_rounded,
    size: 21,
    color: Theme.of(context)
        .colorScheme
        .onSurfaceVariant,
  ),
  suffixIcon: _searchQuery.isNotEmpty
      ? IconButton(
          icon: const Icon(
            Icons.close_rounded,
            size: 20,
          ),
          onPressed: () {
            _searchController.clear();
            _performSearch('');
            _closeSearchInteraction();
          },
        )
      : null,
  filled: true,
  fillColor: Theme.of(context)
      .colorScheme
      .surfaceContainerHighest
      .withValues(alpha: 0.45),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide.none,
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide.none,
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(
      color: Theme.of(context).colorScheme.primary,
      width: 1.5,
    ),
  ),
  contentPadding: const EdgeInsets.symmetric(
    horizontal: 14,
    vertical: 12,
  ),
  isDense: true,
),
                  onChanged: _scheduleSearch,
                  onTap: () {},
                  onEditingComplete: _closeSearchInteraction,
                  onSubmitted: (_) => _closeSearchInteraction(),
                ),
              ),
            ),
            // Custom header row with prev, month/year, next and Today button
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    final prevMonth = DateTime(
                      _focusedDay.year,
                      _focusedDay.month - 1,
                      1,
                    );
                    final selectedDate = _firstVisibleBillDateInMonth(
                      prevMonth,
                    );
                    setState(() {
                      _focusedDay = prevMonth;
                      _selectedDay = selectedDate;
                    });
                  },
                ),
                Expanded(
                  child: Text(
                    DateFormat.yMMMM().format(_focusedDay),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    final nextMonth = DateTime(
                      _focusedDay.year,
                      _focusedDay.month + 1,
                      1,
                    );
                    final selectedDate = _firstVisibleBillDateInMonth(
                      nextMonth,
                    );
                    setState(() {
                      _focusedDay = nextMonth;
                      _selectedDay = selectedDate;
                    });
                  },
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _focusedDay = DateTime.now();
                      _selectedDay = DateTime.now();
                    });
                  },
                  child: const Text('Today'),
                ),
              ],
            ),
            // Wrap TableCalendar in ValueListenableBuilder to rebuild when transactions or bills change
            ValueListenableBuilder<int>(
              valueListenable: DatabaseService.transactionsVersion,
              builder: (context, txVersion, _) {
                return ValueListenableBuilder<int>(
                  valueListenable: DatabaseService.billsVersion,
                  builder: (context, billVersion, _) {
                    return TableCalendar(
                      firstDay: DateTime.utc(2000, 1, 1),
                      lastDay: DateTime.utc(2100, 12, 31),
                      focusedDay: _focusedDay,
                      // When the calendar page changes (user swipes months), update focus.
                      // Only reset selected day to day 1 if we're changing to a month that
                      // doesn't contain the currently selected day.
                      onPageChanged: (focused) {
                        final shouldMoveSelection =
                            _selectedDay == null ||
                            (_selectedDay!.year != focused.year ||
                                _selectedDay!.month != focused.month);
                        final selectedDate = shouldMoveSelection
                            ? _firstVisibleBillDateInMonth(focused)
                            : _selectedDay;
                        setState(() {
                          _focusedDay = focused;
                          _selectedDay = selectedDate;
                        });
                      },
                      selectedDayPredicate: (day) =>
                          isSameDay(_selectedDay, day),
                      eventLoader: (day) {
                        // Calendar events are bill-only on dashboard.
                        final billOcc = _visibleBillOccurrencesForDay(day);

                        // Use the persisted per-occurrence status from Pay Bill as the source of truth.
                        final List<Map<String, dynamic>> updatedBillOcc = [];
                        for (final occ in billOcc) {
                          final bill = occ['bill'] as Bill;
                          final occDate = occ['date'] as DateTime;
                          final isPaid =
                              _getOccurrencePaymentStatus(bill, occDate) ==
                              PaymentStatus.paid;
                          updatedBillOcc.add({
                            'bill': bill,
                            'date': occDate,
                            'isPaid': isPaid,
                          });
                        }
                        return updatedBillOcc;
                      },
                  calendarBuilders: CalendarBuilders(
  defaultBuilder: (context, day, focusedDay) {
    final occurrences =
        _visibleBillOccurrencesForDay(day);

    return _buildCalendarDay(
      day: day,
      occurrences: occurrences,
      isSelected: false,
      isToday: false,
    );
  },

  todayBuilder: (context, day, focusedDay) {
    final occurrences =
        _visibleBillOccurrencesForDay(day);

    return _buildCalendarDay(
      day: day,
      occurrences: occurrences,
      isSelected: false,
      isToday: true,
    );
  },

  selectedBuilder: (context, day, focusedDay) {
    final occurrences =
        _visibleBillOccurrencesForDay(day);

    return _buildCalendarDay(
      day: day,
      occurrences: occurrences,
      isSelected: true,
      isToday: isSameDay(day, DateTime.now()),
    );
  },
),
                      onDaySelected: (selectedDay, focusedDay) {
                        FocusScope.of(context).unfocus();
                        setState(() {
                          _selectedDay = selectedDay;
                          _focusedDay =
                              focusedDay; // update _focusedDay here as well
                        });
                        _scheduleOccurrenceStatusBackgroundSync();
                      },
                      calendarStyle: CalendarStyle(
                        todayDecoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withAlpha((0.2 * 255).round()),
                          shape: BoxShape.circle,
                        ),
                        selectedDecoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        // Disable default marker dots since we're using colored date numbers instead
                        markersMaxCount: 0,
                        canMarkersOverflow: false,
                      ),
                      headerVisible: false,
                    ); // End TableCalendar
                  }, // End billsVersion builder
                ); // End billsVersion ValueListenableBuilder
              }, // End transactionsVersion builder
            ), // End transactionsVersion ValueListenableBuilder
          ],
        ),
      ),
    ),
    );
  }
Widget _buildCalendarDay({
  required DateTime day,
  required List<Map<String, dynamic>> occurrences,
  required bool isSelected,
  required bool isToday,
}) {
  final colorScheme = Theme.of(context).colorScheme;

  Color? markerColor;

  if (occurrences.isNotEmpty) {
    bool allPaid = true;

    for (final occurrence in occurrences) {
      final bill = occurrence['bill'] as Bill;
      final occurrenceDate =
          occurrence['date'] as DateTime;

      final status = _getOccurrencePaymentStatus(
        bill,
        occurrenceDate,
      );

      if (status != PaymentStatus.paid) {
        allPaid = false;
        break;
      }
    }

    markerColor = allPaid
        ? AppTheme.incomeGreen
        : AppTheme.expenseRed;
  }

  return Center(
    child: SizedBox(
      width: 38,
      height: 42,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isSelected
                  ? colorScheme.primary
                  : isToday
                      ? colorScheme.primary.withValues(
                          alpha: 0.14,
                        )
                      : Colors.transparent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '${day.day}',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(
                    color: isSelected
                        ? colorScheme.onPrimary
                        : isToday
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                    fontWeight:
                        isSelected || isToday
                            ? FontWeight.w600
                            : FontWeight.normal,
                  ),
            ),
          ),

          if (markerColor != null)
            Positioned(
              bottom: 0,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: markerColor,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(
                          color: colorScheme.surface,
                          width: 1,
                        )
                      : null,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
  Future<void> _refreshData() async {
    _refreshCachedData();
    _scheduleOccurrenceStatusBackgroundSync();
    setState(() {});
  }

  void _refreshAfterBillEdit({DateTime? selectedDate}) {
    if (!mounted) return;
    _refreshCachedData();
    _occurrenceStatusCache.clear();
    setState(() {
      if (selectedDate != null) {
        final date = _dateOnly(selectedDate);
        _selectedDay = date;
        _focusedDay = date;
      }
    });
    _scheduleOccurrenceStatusBackgroundSync();
  }

  // Quick stats removed: income/expense stat cards were intentionally removed from the
  // dashboard bottom area per user request.

  PaymentStatus _finalizeBillStatus(Bill bill, double totalPaid) {
    if (totalPaid <= 0) {
      return PaymentStatus.unpaid;
    }
    if (totalPaid >= (bill.amount - 0.01)) {
      return PaymentStatus.paid;
    }
    return PaymentStatus.partial;
  }

  bool _matchesBillOccurrenceForStatus(
    Bill bill,
    Transaction tx,
    DateTime occDate,
  ) {
    final dateShort = DateFormat('MM/dd/yy').format(occDate);
    final dateLong = DateFormat('MM/dd/yyyy').format(occDate);

    final txBillId = (tx.billId ?? '').trim();
    if (txBillId.isNotEmpty && txBillId != bill.id) return false;

    final paymentFor = (tx.paymentFor ?? '').trim();
    if (txBillId.isEmpty) {
      // Legacy fallback for old bill payments created before billId linkage.
      final billText = _visibleBillText(bill.description).toLowerCase();
      final paymentForLower = paymentFor.toLowerCase();
      final descriptionLower = tx.description.toLowerCase();
      final dateMatches =
          paymentFor.contains(dateLong) ||
          paymentFor.contains(dateShort) ||
          descriptionLower.contains(dateLong.toLowerCase()) ||
          descriptionLower.contains(dateShort.toLowerCase());
      final billMatches =
          billText.isNotEmpty &&
          (paymentForLower.contains(billText) ||
              descriptionLower.contains(billText));
      if (!(dateMatches && billMatches)) return false;
    }

    if (tx.occurrenceDate != null) {
      return _isSameDay(tx.occurrenceDate!, occDate);
    }

    if (_isSameDay(tx.date, occDate)) return true;
    return tx.description.contains(dateLong) ||
        tx.description.contains(dateShort) ||
        paymentFor.contains(dateLong) ||
        paymentFor.contains(dateShort);
  }

  PaymentStatus _getOccurrencePaymentStatus(Bill bill, DateTime occDate) {
    final cacheKey = _occurrenceStatusKey(bill.id, occDate);
    final cached = _occurrenceStatusCache[cacheKey];
    if (cached != null) return cached;

    final computedStatus = _computeOccurrencePaymentStatus(
      bill,
      occDate,
      _allTransactionsCache,
    );

    _occurrenceStatusCache[cacheKey] = computedStatus;
    return computedStatus;
  }

  PaymentStatus _computeOccurrencePaymentStatus(
    Bill bill,
    DateTime occDate,
    List<Transaction> allTransactions,
  ) {
    final payments = allTransactions
        .where((tx) => _matchesBillOccurrenceForStatus(bill, tx, occDate))
        .toList();
    final totalPaid = _computeSignedTotalPaid(bill, payments);
    return _finalizeBillStatus(bill, totalPaid);
  }

  // ignore: unused_element
Widget _buildFilterChips() {
  final colorScheme = Theme.of(context).colorScheme;

  return FilterChip(
    label: Text(
      _showPaidBills ? 'Paid shown' : 'Show paid',
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: _showPaidBills
            ? colorScheme.primary
            : colorScheme.onSurfaceVariant,
      ),
    ),
    selected: _showPaidBills,
    onSelected: (_) {
      setState(() {
        _showPaidBills = !_showPaidBills;
      });

      DatabaseService.setSetting(
        _showPaidBillsSettingKey,
        _showPaidBills,
      );

      _scheduleOccurrenceStatusBackgroundSync();
    },
    avatar: Icon(
      _showPaidBills
          ? Icons.visibility_rounded
          : Icons.visibility_off_outlined,
      size: 17,
      color: _showPaidBills
          ? colorScheme.primary
          : colorScheme.onSurfaceVariant,
    ),
    showCheckmark: false,
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(
      horizontal: 4,
      vertical: 2,
    ),
    backgroundColor:
        colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
    selectedColor:
        colorScheme.primary.withValues(alpha: 0.12),
    side: BorderSide(
      color: _showPaidBills
          ? colorScheme.primary.withValues(alpha: 0.35)
          : colorScheme.outlineVariant.withValues(alpha: 0.5),
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    ),
  );
}

  // _buildStatCard removed because quick stats are no longer shown on the dashboard.

  Widget _buildRecentTransactionsCard() {
    // Helper to check if a bill matches the search query.
    bool _billMatchesSearch(Bill bill) {
      if (_searchQuery.isEmpty) return true;

      String billDescription = _visibleBillText(bill.description);
      String payeeName = '';

      // Get payee name if available
      if (bill.payeeId != null) {
        final payee = _allPayeesCache.firstWhere(
          (p) => p['id'] == bill.payeeId,
          orElse: () => <String, dynamic>{},
        );
        if (payee.containsKey('name')) {
          payeeName = payee['name'] as String;
        }
      }

      // Check if query matches description or payee name
      final searchText = '$billDescription $payeeName'.toLowerCase();
      return searchText.contains(_searchQuery);
    }

    List<TransactionDisplayItem> recentTransactions;
    List<Map<String, dynamic>> billOcc;
    if (_selectedDay != null) {
      final startOfSelected = DateTime(
        _selectedDay!.year,
        _selectedDay!.month,
        _selectedDay!.day,
      );
      billOcc = DatabaseService.getBillOccurrencesBetween(
        startOfSelected,
        startOfSelected,
      );
      billOcc = _dedupeBillOccurrences(billOcc);

      // Apply search filter to bill occurrences
      if (_searchQuery.isNotEmpty) {
        billOcc = billOcc.where((b) {
          final bill = b['bill'] as Bill;
          return _billMatchesSearch(bill);
        }).toList();
      }

      // Hide paid bill occurrences by default.
      if (!_showPaidBills) {
        billOcc = billOcc.where((b) {
          final bill = b['bill'] as Bill;
          final occDate = b['date'] as DateTime;
          return _getOccurrencePaymentStatus(bill, occDate) !=
              PaymentStatus.paid;
        }).toList();
      }
      recentTransactions = <TransactionDisplayItem>[];
      for (final b in billOcc) {
        final bill = b['bill'] as Bill;
        final date = b['date'] as DateTime;
        if (bill.type == BillType.transfer) {
          final fromAcc = bill.fromAccountId != null
              ? DatabaseService.getAccountById(bill.fromAccountId!)
              : null;
          final toAcc = bill.toAccountId != null
              ? DatabaseService.getAccountById(bill.toAccountId!)
              : null;
          final fromName = fromAcc?.name ?? 'From account';
          final toName = toAcc?.name ?? 'To account';
          final cleanBillDescription = _visibleBillText(bill.description);
          final desc = cleanBillDescription.isNotEmpty
              ? cleanBillDescription
              : 'Transfer from $fromName to $toName';
          final billNote = _billNoteText(bill);
          final String? debitNote = billNote.isNotEmpty
              ? 'account: $fromName — $billNote'
              : null;
          final debit = Transaction(
            amount: bill.amount,
            categoryId: '',
            type: TransactionType.expense,
            description: desc,
            date: date,
            occurrenceDate: date,
            note: debitNote,
          );
          recentTransactions.add(
            TransactionDisplayItem(debit, sourceBill: bill),
          );
          final String? creditNote = billNote.isNotEmpty
              ? 'account: $toName — $billNote'
              : null;
          final credit = Transaction(
            amount: bill.amount,
            categoryId: '',
            type: TransactionType.income,
            description: desc,
            date: date,
            occurrenceDate: date,
            note: creditNote,
          );
          recentTransactions.add(
            TransactionDisplayItem(credit, sourceBill: bill),
          );
        } else {
          String desc = _visibleBillText(bill.description);
          if (bill.payeeId != null) {
            final p = _allPayeesCache.firstWhere(
              (p) => p['id'] == bill.payeeId,
              orElse: () => <String, dynamic>{},
            );
            if (p.containsKey('name')) desc = p['name'] as String;
          }
          // Only show dashboard note content when the bill notes field has text.
          String? noteWithAccount;
          final billNote = _billNoteText(bill);
          if (billNote.isNotEmpty && bill.accountId != null) {
            final account = DatabaseService.getAccountById(bill.accountId!);
            if (account != null) {
              noteWithAccount = 'account: ${account.name} — $billNote';
            }
          } else if (billNote.isNotEmpty) {
            noteWithAccount = billNote;
          }
          TransactionType txType = TransactionType.expense;
          if (bill.type == BillType.income) {
            txType = TransactionType.income;
          } else if (bill.type == BillType.expense) {
            txType = TransactionType.expense;
          }
          final placeholder = Transaction(
            amount: bill.amount,
            categoryId: bill.categoryId ?? '',
            type: txType,
            description: desc,
            date: date,
            occurrenceDate: date,
            note: noteWithAccount,
          );
          recentTransactions.add(
            TransactionDisplayItem(placeholder, sourceBill: bill),
          );
        }
      }
      recentTransactions.sort(
        (a, b) => b.transaction.date.compareTo(a.transaction.date),
      );
    } else {
      final allBills = _allBillsCache;
      final now = DateTime.now();
      DateTime start;
      DateTime end;
      if (allBills.isEmpty) {
        start = DateTime(now.year, now.month, now.day);
        end = start;
      } else {
        start = allBills
            .map(
              (b) => DateTime(b.dueDate.year, b.dueDate.month, b.dueDate.day),
            )
            .reduce((a, b) => a.isBefore(b) ? a : b);
        final latestBound = allBills
            .map(
              (b) =>
                  b.recurrenceEndDate ??
                  DateTime(now.year + 10, now.month, now.day),
            )
            .map((d) => DateTime(d.year, d.month, d.day))
            .reduce((a, b) => a.isAfter(b) ? a : b);
        end = latestBound;
      }
      billOcc = DatabaseService.getBillOccurrencesBetween(start, end);
      billOcc = _dedupeBillOccurrences(billOcc);

      if (_searchQuery.isNotEmpty) {
        billOcc = billOcc.where((b) {
          final bill = b['bill'] as Bill;
          return _billMatchesSearch(bill);
        }).toList();
      }

      if (!_showPaidBills) {
        billOcc = billOcc.where((b) {
          final bill = b['bill'] as Bill;
          final occDate = b['date'] as DateTime;
          return _getOccurrencePaymentStatus(bill, occDate) !=
              PaymentStatus.paid;
        }).toList();
      }

      billOcc.sort((a, b) {
        final ad = a['date'] as DateTime;
        final bd = b['date'] as DateTime;
        return ad.compareTo(bd);
      });

      recentTransactions = <TransactionDisplayItem>[];
      for (final b in billOcc) {
        final bill = b['bill'] as Bill;
        final date = b['date'] as DateTime;
        if (bill.type == BillType.transfer) {
          final fromAcc = bill.fromAccountId != null
              ? DatabaseService.getAccountById(bill.fromAccountId!)
              : null;
          final toAcc = bill.toAccountId != null
              ? DatabaseService.getAccountById(bill.toAccountId!)
              : null;
          final fromName = fromAcc?.name ?? 'From account';
          final toName = toAcc?.name ?? 'To account';
          final cleanBillDescription = _visibleBillText(bill.description);
          final desc = cleanBillDescription.isNotEmpty
              ? cleanBillDescription
              : 'Transfer from $fromName to $toName';
          String? debitNote = 'account: $fromName';
          final billNote = _billNoteText(bill);
          if (billNote.isNotEmpty) {
            debitNote = 'account: $fromName — $billNote';
          }
          final debit = Transaction(
            amount: bill.amount,
            categoryId: '',
            type: TransactionType.expense,
            description: desc,
            date: date,
            occurrenceDate: date,
            note: debitNote,
          );
          recentTransactions.add(
            TransactionDisplayItem(debit, sourceBill: bill),
          );
          String? creditNote = 'account: $toName';
          if (billNote.isNotEmpty) {
            creditNote = 'account: $toName — $billNote';
          }
          final credit = Transaction(
            amount: bill.amount,
            categoryId: '',
            type: TransactionType.income,
            description: desc,
            date: date,
            occurrenceDate: date,
            note: creditNote,
          );
          recentTransactions.add(
            TransactionDisplayItem(credit, sourceBill: bill),
          );
        } else {
          String desc = _visibleBillText(bill.description);
          if (bill.payeeId != null) {
            final p = _allPayeesCache.firstWhere(
              (p) => p['id'] == bill.payeeId,
              orElse: () => <String, dynamic>{},
            );
            if (p.containsKey('name')) desc = p['name'] as String;
          }
          String? noteWithAccount;
          final billNote = _billNoteText(bill);
          if (billNote.isNotEmpty && bill.accountId != null) {
            final account = DatabaseService.getAccountById(bill.accountId!);
            if (account != null) {
              noteWithAccount = 'account: ${account.name} — $billNote';
            }
          } else if (billNote.isNotEmpty) {
            noteWithAccount = billNote;
          }
          TransactionType txType = TransactionType.expense;
          if (bill.type == BillType.income) {
            txType = TransactionType.income;
          } else if (bill.type == BillType.expense) {
            txType = TransactionType.expense;
          }
          final placeholder = Transaction(
            amount: bill.amount,
            categoryId: bill.categoryId ?? '',
            type: txType,
            description: desc,
            date: date,
            occurrenceDate: date,
            note: noteWithAccount,
          );
          recentTransactions.add(
            TransactionDisplayItem(placeholder, sourceBill: bill),
          );
        }
      }
    }

    // We want each transaction to render as its own Card (returned by _buildTransactionItem).
    // Render a surrounding container with consistent padding and then render the item cards individually.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Optional header space
          const SizedBox(height: 4),
          if (recentTransactions.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: const Text('No Bills'),
              ),
            )
          else
            // Render each transaction item as its own Card in a Column to avoid nested scrolling issues.
            Column(
              children: [
                for (var i = 0; i < recentTransactions.length; i++) ...[
                  _buildTransactionItem(
                    recentTransactions[i].transaction,
                    recentTransactions[i].sourceBill,
                  ),
                  if (i != recentTransactions.length - 1)
                    const SizedBox(height: 4),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTransactionItem(Transaction transaction, Bill? sourceBill) {
    final lookupsState = context.watch<LookupsState>();
    final category = DatabaseService.getCategoryById(transaction.categoryId);
    final categoryText = lookupsState.categoryName(
      transaction.categoryId,
      fallbackName: transaction.categoryName ?? category?.name ?? 'Unknown',
    );
    final payeeText = lookupsState.payeeName(
      transaction.payeeId,
      fallbackName: transaction.payeeName,
    );
    final payerText = lookupsState.payerName(
      transaction.payerId,
      fallbackName: transaction.payerName,
    );
    // If transaction has splits, build a combined category string
    String categoryDisplay;
    if (transaction.splitsJson != null &&
        transaction.splitsJson!.trim().isNotEmpty) {
      try {
        final splits = json.decode(transaction.splitsJson!) as List<dynamic>;
        final parts = <String>[];
        for (final s in splits) {
          if (s is Map) {
            final cid = s['categoryId']?.toString();
            final amt = s['amount'];
            final c = cid != null ? DatabaseService.getCategoryById(cid) : null;
            final name = lookupsState.categoryName(
              cid,
              fallbackName: c?.name ?? cid ?? 'Unknown',
            );
            final amountStr = amt is num
                ? _currencyFormat.format(amt.toDouble())
                : amt?.toString() ?? '';
            parts.add('$name ${amountStr}');
          }
        }
        categoryDisplay = parts.join(', ');
      } catch (_) {
        categoryDisplay = categoryText;
      }
    } else {
      categoryDisplay = categoryText;
    }
    final fallbackCounterparty = transaction.type == TransactionType.expense
        ? payeeText
        : payerText;
    final displayTitle =
        (transaction.description.trim().isEmpty ||
            transaction.description.trim().toLowerCase() == 'transaction')
        ? (fallbackCounterparty.isEmpty
              ? transaction.description
              : fallbackCounterparty)
        : transaction.description;
    // Create unique ID for this transaction card
    final cardId =
        '${transaction.date.millisecondsSinceEpoch}_${transaction.description}_${transaction.amount}';
    final isExpanded = _expandedTransactionIds.contains(cardId);

    // Calculate  if this is a bill
    double? paymentProgress;
    double? amountPaid;
    double? amountDue;
    // Removed unused occurrenceStatus variable

    // Helper to safely build the category icon/emoji/image
    Widget safeCategoryIcon() {
      try {
        return _buildCategoryIconOrEmoji(category);
      } catch (_) {
        return const Icon(Icons.help, color: Colors.grey, size: 18);
      }
    }

   if (sourceBill != null) {
  final occDate = _transactionOccurrenceDate(transaction);

  // Use the same occurrence-matching logic as the rest of the dashboard.
  final paymentHistory = _allTransactionsCache
      .where(
        (tx) => _matchesBillOccurrenceForStatus(
          sourceBill!,
          tx,
          occDate,
        ),
      )
      .toList();

  // Use the same signed-payment calculation used for bill status.
  final totalPaid = _computeSignedTotalPaid(
    sourceBill,
    paymentHistory,
  );

  amountPaid = totalPaid < 0 ? 0 : totalPaid;

  final remaining = sourceBill.amount - totalPaid;
  amountDue = remaining > 0 ? remaining : 0;

  if (sourceBill.amount > 0) {
    paymentProgress =
        (totalPaid / sourceBill.amount).clamp(0.0, 1.0);
  } else {
    paymentProgress = 0.0;
  }
}

    // Extract account/name metadata from notes when present.
    String? accountNameFromNote;
    String? plainNote = transaction.note;
    // Strip any internal hide marker if present so it doesn't render to users.
    // Prefer the persisted hidden-ids; still remove legacy markers from notes
    // for display if they exist (we don't display the marker to users anymore).
    if (plainNote != null && plainNote.contains('__hide_from_calendar__')) {
      plainNote = plainNote.replaceAll('__hide_from_calendar__', '').trim();
      if (plainNote.isEmpty) plainNote = null;
    }
    // Remove any internal pair tokens left in notes (e.g. 'pair:<id>').
    if (plainNote != null && plainNote.contains('pair:')) {
      plainNote = plainNote
          .replaceAll(RegExp(r'pair:[A-Za-z0-9\-]+'), '')
          .trim();
      if (plainNote.isEmpty) plainNote = null;
    }
    if (plainNote != null && plainNote.startsWith('account:')) {
      final after = plainNote.substring('account:'.length).trim();
      // Em/en dashes may omit spaces, while a hyphen only acts as the
      // separator when surrounded by spaces. This preserves account names
      // such as "High-Yield Savings" in full.
      final separator = RegExp(r'\s*[—–]\s*|\s+-\s+').firstMatch(after);
      final extractedAccountName = separator == null
          ? after
          : after.substring(0, separator.start).trim();
      if (extractedAccountName.isNotEmpty) {
        accountNameFromNote = extractedAccountName;
      }
      if (separator != null) {
        plainNote = after.substring(separator.end).trim();
        if (plainNote.isEmpty) plainNote = null;
      } else {
        // No trailing note content
        plainNote = null;
      }
    }

    String? accountDisplayName;
    if (sourceBill != null) {
      accountDisplayName = accountNameFromNote;

      if (accountDisplayName == null || accountDisplayName.trim().isEmpty) {
        if (sourceBill.type == BillType.transfer) {
          final accountId = transaction.type == TransactionType.expense
              ? sourceBill.fromAccountId
              : sourceBill.toAccountId;
          if (accountId != null && accountId.isNotEmpty) {
            accountDisplayName = DatabaseService.getAccountById(
              accountId,
            )?.name;
          }
          accountDisplayName ??= transaction.type == TransactionType.expense
              ? 'From account'
              : 'To account';
        } else {
          final accountId = sourceBill.accountId ?? transaction.accountId;
          if (accountId != null && accountId.isNotEmpty) {
            accountDisplayName = DatabaseService.getAccountById(
              accountId,
            )?.name;
          }
        }
      }
    }

    final cardContent = Card(
  margin: const EdgeInsets.symmetric(
    vertical: 6,
    horizontal: 0,
  ),
  elevation: 0,
  color: Theme.of(context).colorScheme.surface,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
    side: BorderSide(
      color: Theme.of(context)
          .colorScheme
          .outlineVariant
          .withValues(alpha: 0.35),
    ),
  ),
  clipBehavior: Clip.antiAlias,
  child: InkWell(
    onTap: () async {
      await _handleEdit(transaction, sourceBill);
    },
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category icon
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: safeCategoryIcon(),
              ),

              const SizedBox(width: 12),

              // Bill information
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      categoryDisplay,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),

                    const SizedBox(height: 5),

                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 13,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          DateFormat('MMM d, yyyy')
                              .format(transaction.date),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),

                    if (plainNote != null &&
                        plainNote.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        plainNote,
                        softWrap: true,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Amount, status and account
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${transaction.type == TransactionType.income ? '+' : '-'}${_currencyFormat.format(transaction.amount)}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                          color:
                              transaction.type ==
                                  TransactionType.income
                              ? AppTheme.incomeGreen
                              : AppTheme.expenseRed,
                          fontWeight: FontWeight.w700,
                        ),
                  ),

                  if (sourceBill != null) ...[
                    const SizedBox(height: 7),

                    Builder(
                      builder: (ctx) {
                        final occDate =
                            _transactionOccurrenceDate(
                          transaction,
                        );

                        final status =
                            _getOccurrencePaymentStatus(
                          sourceBill,
                          occDate,
                        );

                        String label;
                        Color color;

                        if (status == PaymentStatus.paid) {
                          label = 'Paid';
                          color = AppTheme.incomeGreen;
                        } else if (status ==
                            PaymentStatus.partial) {
                          label = 'Partial';
                          color = Colors.orange;
                        } else {
                          label = 'Unpaid';
                          color = AppTheme.expenseRed;
                        }

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(
                              alpha: 0.10,
                            ),
                            borderRadius:
                                BorderRadius.circular(20),
                          ),
                          child: Text(
                            label,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: color,
                                  fontWeight:
                                      FontWeight.w700,
                                  fontSize: 11,
                                ),
                          ),
                        );
                      },
                    ),
                  ],

                  if (sourceBill != null &&
                      accountDisplayName != null &&
                      accountDisplayName
                          .trim()
                          .isNotEmpty) ...[
                    const SizedBox(height: 7),

                    SizedBox(
                      width: 120,
                      child: Text(
                        accountDisplayName,
                        textAlign: TextAlign.right,
                        softWrap: true,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),

          // Keep existing expandable payment progress.
          if (isExpanded &&
              paymentProgress != null &&
              sourceBill != null) ...[
            const SizedBox(height: 16),

            Divider(
              height: 1,
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant,
            ),

            const SizedBox(height: 14),

            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Payment Progress',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  '${(paymentProgress * 100).toStringAsFixed(0)}%',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: paymentProgress >= 1
                            ? AppTheme.incomeGreen
                            : AppTheme.expenseRed,
                      ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: paymentProgress,
                minHeight: 7,
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
                valueColor:
                    AlwaysStoppedAnimation<Color>(
                  paymentProgress >= 1
                      ? AppTheme.incomeGreen
                      : AppTheme.expenseRed,
                ),
              ),
            ),

            const SizedBox(height: 7),

            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Paid: ${_currencyFormat.format(amountPaid)}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall,
                ),
                Text(
                  'Due: ${_currencyFormat.format(
                    amountDue != null && amountDue > 0
                        ? amountDue
                        : 0,
                  )}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                        fontWeight: FontWeight.w600,
                        color:
                            amountDue != null &&
                                amountDue > 0
                            ? AppTheme.expenseRed
                            : AppTheme.incomeGreen,
                      ),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  ),
);

    if (sourceBill == null) {
      return cardContent;
    }

    return Slidable(
      key: ValueKey('bill-swipe-$cardId-${sourceBill.id}'),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.50,
        children: [
          CustomSlidableAction(
            onPressed: (_) {
              setState(() {
                if (isExpanded) {
                  _expandedTransactionIds.remove(cardId);
                } else {
                  _expandedTransactionIds.add(cardId);
                }
              });
            },
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isExpanded ? Icons.close : Icons.show_chart,
                  color: Colors.white,
                ),
                const SizedBox(height: 4),
                Text(
                  isExpanded ? 'Hide\nProgress' : 'Show\nProgress',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          CustomSlidableAction(
            onPressed: (_) async => _handleDuplicate(transaction, sourceBill),
            backgroundColor: Colors.blueGrey,
            foregroundColor: Colors.white,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.copy, color: Colors.white),
                SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Duplicate',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.50,
        children: [
          CustomSlidableAction(
            onPressed: (_) async => _handlePay(transaction, sourceBill),
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.payment, color: Colors.white),
                SizedBox(height: 4),
                Text(
                  'Pay',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          CustomSlidableAction(
            onPressed: (_) async => _handleDelete(transaction, sourceBill),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.delete, color: Colors.white),
                SizedBox(height: 4),
                Text(
                  'Delete',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      child: cardContent,
    );
  }

  Future<void> _handleEdit(Transaction transaction, Bill? sourceBill) async {
    final Bill? effectiveSourceBill =
        sourceBill ??
        (() {
          final billId = transaction.billId;
          if (billId == null || billId.isEmpty) return null;
          try {
            return DatabaseService.getAllBills().firstWhere(
              (b) => b.id == billId,
            );
          } catch (_) {
            return null;
          }
        })();

    sourceBill = effectiveSourceBill;

    if (sourceBill != null && sourceBill.recurrence != Recurrence.none) {
      // If this is a recurring bill, ask whether to edit only this occurrence or all future occurrences
      final choice = await showDialog<String>(
        context: context,
        builder: (context) {
          final colorScheme = Theme.of(context).colorScheme;
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            backgroundColor: Colors.transparent,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 460),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(Icons.edit_calendar_rounded, color: colorScheme.primary),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'Edit Recurring Bill',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Choose how you want to apply your changes to this recurring bill.',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context, 'this'),
                      icon: const Icon(Icons.event_rounded),
                      label: const Text('Only This Occurrence'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, 'all'),
                      icon: const Icon(Icons.event_repeat_rounded),
                      label: const Text('All Future Occurrences'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, 'cancel'),
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (choice == 'this') {
        // Edit only this occurrence: create a one-off edited bill for the occurrence date,
        // and split the existing series so it ends before this occurrence and (if applicable) recreate the future series starting after it.
        final occurrenceDate = _transactionOccurrenceDate(transaction);

        // Open add screen prefilled with this occurrence values, but save as a new bill (isDuplicate=true)
        final tempBill = Bill(
          amount: sourceBill.amount,
          description: sourceBill.description,
          dueDate: occurrenceDate,
          recurrence: Recurrence.none,
          customDays: null,
          recurrenceEndDate: null,
          recurrenceInterval: 1,
          recurrenceWeekdays: null,
          categoryId: sourceBill.categoryId,
          type: sourceBill.type,
          fromAccountId: sourceBill.fromAccountId,
          toAccountId: sourceBill.toAccountId,
          payeeId: sourceBill.payeeId,
          accountId: sourceBill.accountId,
          isPaid:
              DatabaseService.getBillOccurrenceStatus(
                    sourceBill.id,
                    occurrenceDate,
                  )?['isPaid']
                  as bool? ??
              sourceBill.isPaid,
          // per-bill reminder flag removed
        );

        final editedResult = await Navigator.push<dynamic>(
          context,
          MaterialPageRoute(
            builder: (context) =>
                AddBillScreen(existingBill: tempBill, isDuplicate: true),
          ),
        );

        // editedResult may be `true` (legacy) or a String containing the new bill id.
        final String? occurrenceBillId = (editedResult is String)
            ? editedResult
            : null;

        if (editedResult == true || occurrenceBillId != null) {
          try {
            final dayBefore = _addCalendarDays(occurrenceDate, -1);

            // "Only this occurrence" must always remain a one-time bill.
            // If the edit screen changed recurrence, normalize it back to none
            // to avoid future duplicate occurrences, while preserving any
            // date change the user made in the edit screen.
            DateTime editedOccurrenceDate = occurrenceDate;
            Bill? occurrenceBill;
            if (occurrenceBillId != null) {
              try {
                final created = DatabaseService.getAllBills().firstWhere(
                  (b) => b.id == occurrenceBillId,
                );
                occurrenceBill = created;
                if (created.recurrence != Recurrence.none) {
                  final oneOff = created.copyWith(
                    recurrence: Recurrence.none,
                    customDays: null,
                    recurrenceEndDate: null,
                    recurrenceInterval: 1,
                    recurrenceWeekdays: null,
                  );
                  await DatabaseService.updateBill(oneOff);
                  occurrenceBill = oneOff;
                }
                editedOccurrenceDate = _dateOnly(occurrenceBill.dueDate);
              } catch (_) {}
            }

            // Calculate next occurrence date based on recurrence (handles monthly custom days)
            final DateTime? nextOccurrenceDate = _computeNextOccurrenceDate(
              sourceBill,
              occurrenceDate,
            );

            // Update original bill to end before this occurrence
            final updatedBill = sourceBill.copyWith(
              recurrenceEndDate: dayBefore,
            );
            await DatabaseService.updateBill(updatedBill);
            await DatabaseService.setBillRecurrenceEndOverride(
              updatedBill.id,
              dayBefore,
            );

            // If there is a next occurrence and the original had an end date beyond it (or no end), recreate the future series
            if (nextOccurrenceDate != null &&
                (sourceBill.recurrenceEndDate == null ||
                    nextOccurrenceDate.isBefore(
                      sourceBill.recurrenceEndDate!,
                    ) ||
                    nextOccurrenceDate.isAtSameMomentAs(
                      sourceBill.recurrenceEndDate!,
                    ))) {
              final splitSourceBill = sourceBill;

              final existingSuccessor = hasEquivalentRecurringSuccessor(
                candidates: DatabaseService.getAllBills(),
                sourceBill: splitSourceBill,
                nextOccurrenceDate: nextOccurrenceDate,
                excludedBillId: occurrenceBillId,
              );

              if (!existingSuccessor) {
                final newBill = Bill(
                  amount: sourceBill.amount,
                  description: sourceBill.description,
                  dueDate: nextOccurrenceDate,
                  recurrence: sourceBill.recurrence,
                  customDays: sourceBill.customDays,
                  recurrenceEndDate: sourceBill.recurrenceEndDate,
                  recurrenceInterval: sourceBill.recurrenceInterval,
                  recurrenceWeekdays: sourceBill.recurrenceWeekdays,
                  categoryId: sourceBill.categoryId,
                  type: sourceBill.type,
                  fromAccountId: sourceBill.fromAccountId,
                  toAccountId: sourceBill.toAccountId,
                  payeeId: sourceBill.payeeId,
                  accountId: sourceBill.accountId,
                  isPaid:
                      DatabaseService.getBillOccurrenceStatus(
                            sourceBill.id,
                            occurrenceDate,
                          )?['isPaid']
                          as bool? ??
                      sourceBill.isPaid,
                  // per-bill reminder flag removed
                );
                await DatabaseService.addBill(newBill);
              }
            }

            // If the AddBillScreen returned a specific occurrence bill id,
            // migrate payments for this occurrence to that bill so history
            // remains visible even when this was the last recurring occurrence.
            var migrated = <Transaction>[];
            try {
              migrated = await _relinkBillOccurrencePayments(
                fromBillId: sourceBill.id,
                toBillId: occurrenceBillId ?? sourceBill.id,
                fromOccurrenceDate: occurrenceDate,
                toOccurrenceDate: editedOccurrenceDate,
              );
              // Persist occurrence-level status for the occurrence on the occurrence-specific bill
              if (occurrenceBillId != null) {
                final editedBillAmount =
                    occurrenceBill?.amount ?? sourceBill.amount;
                double totalPaid = _computeSignedTotalPaid(
                  sourceBill,
                  migrated,
                );
                PaymentStatus newStatus;
                if (totalPaid <= 0) {
                  newStatus = PaymentStatus.unpaid;
                } else if (totalPaid >= (editedBillAmount - 0.01)) {
                  newStatus = PaymentStatus.paid;
                } else {
                  newStatus = PaymentStatus.partial;
                }
                await DatabaseService.setBillOccurrenceStatus(
                  occurrenceBillId,
                  editedOccurrenceDate,
                  newStatus == PaymentStatus.paid,
                  newStatus,
                );
              }
            } catch (_) {}

            if (occurrenceBillId != null) {
              await _removeDuplicateBillPaymentsForBill(occurrenceBillId);
            }

            if (mounted) {
              ScaffoldMessenger.of(context).clearSnackBars();
            }
            _refreshAfterBillEdit(selectedDate: editedOccurrenceDate);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error updating occurrence: $e'),
                  backgroundColor: Colors.blueGrey[400],
                ),
              );
            }
          }
        }
      } else if (choice == 'all') {
        // Edit all future occurrences — we should not modify past occurrences.
        // To accomplish this, create a new bill starting at the selected
        // occurrence date (pre-filled from the original) and save it as a
        // duplicate (new series). Then update the original bill to end the
        // day before the occurrence so past occurrences remain linked to it.
        final occurrenceDate = _transactionOccurrenceDate(transaction);

        // Build a prefilled bill for the new (future) series that the user
        // can edit. Mark `isDuplicate=true` so AddBillScreen will create a
        // new Bill instead of updating the existing one.
        final tempNewBill = Bill(
          amount: sourceBill.amount,
          description: sourceBill.description,
          dueDate: occurrenceDate,
          recurrence: sourceBill.recurrence,
          customDays: sourceBill.customDays,
          recurrenceEndDate: sourceBill.recurrenceEndDate,
          recurrenceInterval: sourceBill.recurrenceInterval,
          recurrenceWeekdays: sourceBill.recurrenceWeekdays,
          categoryId: sourceBill.categoryId,
          type: sourceBill.type,
          fromAccountId: sourceBill.fromAccountId,
          toAccountId: sourceBill.toAccountId,
          payeeId: sourceBill.payeeId,
          accountId: sourceBill.accountId,
          isPaid:
              DatabaseService.getBillOccurrenceStatus(
                    sourceBill.id,
                    occurrenceDate,
                  )?['isPaid']
                  as bool? ??
              sourceBill.isPaid,
          // per-bill reminder flag removed
        );

        final editedResult = await Navigator.push<dynamic>(
          context,
          MaterialPageRoute(
            builder: (context) =>
                AddBillScreen(existingBill: tempNewBill, isDuplicate: true),
          ),
        );

        final String? newBillId = (editedResult is String)
            ? editedResult
            : null;

        if (editedResult == true || newBillId != null) {
          try {
            final dayBefore = _addCalendarDays(occurrenceDate, -1);
            DateTime editedFutureStartDate = occurrenceDate;
            if (newBillId != null) {
              try {
                final newBill = DatabaseService.getAllBills().firstWhere(
                  (b) => b.id == newBillId,
                );
                editedFutureStartDate = _dateOnly(newBill.dueDate);
                final recurrenceEndDate = newBill.recurrenceEndDate == null
                    ? null
                    : _dateOnly(newBill.recurrenceEndDate!);
                final shouldClearEndDate =
                    newBill.recurrence != Recurrence.none &&
                    recurrenceEndDate != null &&
                    recurrenceEndDate.isBefore(editedFutureStartDate);
                final shouldIncludeStartWeekday =
                    newBill.recurrence == Recurrence.weekly &&
                    newBill.recurrenceWeekdays != null &&
                    newBill.recurrenceWeekdays!.isNotEmpty &&
                    !newBill.recurrenceWeekdays!.contains(
                      editedFutureStartDate.weekday,
                    );
                final shouldIncludeStartMonthDay =
                    newBill.recurrence == Recurrence.monthly &&
                    newBill.customDays != null &&
                    newBill.customDays!.isNotEmpty &&
                    !newBill.customDays!.contains(editedFutureStartDate.day);
                if (shouldClearEndDate ||
                    shouldIncludeStartWeekday ||
                    shouldIncludeStartMonthDay) {
                  final updatedNewBill = newBill.copyWith(
                    recurrenceEndDate: shouldClearEndDate
                        ? null
                        : newBill.recurrenceEndDate,
                    recurrenceWeekdays: shouldIncludeStartWeekday
                        ? (<int>{
                            ...newBill.recurrenceWeekdays!,
                            editedFutureStartDate.weekday,
                          }.toList()..sort())
                        : newBill.recurrenceWeekdays,
                    customDays: shouldIncludeStartMonthDay
                        ? (<int>{
                            ...newBill.customDays!,
                            editedFutureStartDate.day,
                          }.toList()..sort())
                        : newBill.customDays,
                  );
                  await DatabaseService.updateBill(updatedNewBill);
                }
              } catch (_) {}
            }

            // Update original bill to end before this occurrence so past
            // occurrences remain associated with it and are not modified.
            final updatedBill = sourceBill.copyWith(
              recurrenceEndDate: dayBefore,
            );
            await DatabaseService.updateBill(updatedBill);
            await DatabaseService.setBillRecurrenceEndOverride(
              updatedBill.id,
              dayBefore,
            );

            // If a new bill id was returned, migrate transactions that belong
            // to this original bill but are for occurrences on/after the
            // occurrenceDate to the new bill so they reflect the edited
            // future series. Leave any past transactions untouched.
            if (newBillId != null) {
              try {
                await _relinkBillOccurrencePayments(
                  fromBillId: sourceBill.id,
                  toBillId: newBillId,
                  fromOccurrenceDate: occurrenceDate,
                  toOccurrenceDate: editedFutureStartDate,
                  includeFutureOccurrences: true,
                );
              } catch (_) {}
            }

            if (newBillId != null) {
              await _removeDuplicateBillPaymentsForBill(newBillId);
            }

            if (mounted) {
              ScaffoldMessenger.of(context).clearSnackBars();
            }
            _refreshAfterBillEdit(selectedDate: editedFutureStartDate);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error updating future occurrences: $e'),
                  backgroundColor: Colors.blueGrey[400],
                ),
              );
            }
          }
        }
      }
    } else if (sourceBill != null) {
      // Non-recurring bill: open edit screen directly
      final sourceBillId = sourceBill.id;
      final originalDueDate = _dateOnly(sourceBill.dueDate);
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AddBillScreen(existingBill: sourceBill),
        ),
      );
      if (result == true && mounted) {
        DateTime? updatedDueDate;
        try {
          updatedDueDate = DatabaseService.getAllBills()
              .firstWhere((b) => b.id == sourceBillId)
              .dueDate;
        } catch (_) {
          updatedDueDate = null;
        }
        if (updatedDueDate != null) {
          await _relinkBillOccurrencePayments(
            fromBillId: sourceBillId,
            toBillId: sourceBillId,
            fromOccurrenceDate: originalDueDate,
            toOccurrenceDate: updatedDueDate,
          );
        }
        await _removeDuplicateBillPaymentsForBill(sourceBillId);
        _refreshAfterBillEdit(selectedDate: updatedDueDate);
      }
    } else {
      // Editing a regular transaction - open transaction edit screen (placeholder)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Transaction editing coming soon'),
          backgroundColor: Colors.blueGrey[400],
        ),
      );
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime _transactionOccurrenceDate(Transaction transaction) {
    return _dateOnly(transaction.occurrenceDate ?? transaction.date);
  }

  List<Transaction> _getTransactionsForBillOccurrence(
    Bill bill,
    DateTime occurrenceDate,
  ) {
    final occDateStr = DateFormat('MM/dd/yyyy').format(occurrenceDate);
    return _allTransactionsCache.where((tx) {
      if (tx.billId != bill.id) return false;

      if (tx.occurrenceDate != null) {
        return _isSameDay(tx.occurrenceDate!, occurrenceDate);
      }

      return _isSameDay(tx.date, occurrenceDate) ||
          tx.description.contains(occDateStr);
    }).toList();
  }

  bool _transactionMatchesBillOccurrenceDate(
    Transaction tx,
    DateTime occurrenceDate,
  ) {
    final occDate = _dateOnly(occurrenceDate);
    final occDateStr = DateFormat('MM/dd/yyyy').format(occDate);
    final occDateShort = DateFormat('MM/dd/yy').format(occDate);
    final paymentFor = tx.paymentFor ?? '';

    if (tx.occurrenceDate != null) {
      return _isSameDay(tx.occurrenceDate!, occDate);
    }

    return _isSameDay(tx.date, occDate) ||
        tx.description.contains(occDateStr) ||
        tx.description.contains(occDateShort) ||
        paymentFor.contains(occDateStr) ||
        paymentFor.contains(occDateShort);
  }

  Future<List<Transaction>> _relinkBillOccurrencePayments({
    required String fromBillId,
    required String toBillId,
    required DateTime fromOccurrenceDate,
    required DateTime toOccurrenceDate,
    bool includeFutureOccurrences = false,
  }) async {
    final sourceId = fromBillId.trim();
    final targetId = toBillId.trim();
    if (sourceId.isEmpty || targetId.isEmpty) return <Transaction>[];

    final sourceDate = _dateOnly(fromOccurrenceDate);
    final targetDate = _dateOnly(toOccurrenceDate);

    bool shouldRelink(Transaction tx) {
      if ((tx.billId ?? '').trim() != sourceId) return false;

      if (!includeFutureOccurrences) {
        return _transactionMatchesBillOccurrenceDate(tx, sourceDate);
      }

      final txOccurrenceDate = _dateOnly(tx.occurrenceDate ?? tx.date);
      if (!txOccurrenceDate.isBefore(sourceDate)) return true;
      return _transactionMatchesBillOccurrenceDate(tx, sourceDate);
    }

    final relatedPayments = DatabaseService.getAllTransactions()
        .where(shouldRelink)
        .toList();

    final relinked = <Transaction>[];
    for (final tx in relatedPayments) {
      final currentOccurrenceDate = tx.occurrenceDate == null
          ? null
          : _dateOnly(tx.occurrenceDate!);
      final occurrenceDateChanged =
          currentOccurrenceDate == null ||
          !_isSameDay(currentOccurrenceDate, targetDate);

      if ((tx.billId ?? '').trim() == targetId && !occurrenceDateChanged) {
        relinked.add(tx);
        continue;
      }

      // Keep tx.date as the actual payment date. occurrenceDate is only the
      // bill occurrence this payment is linked to.
      final updatedTx = tx.copyWith(
        billId: targetId,
        occurrenceDate: targetDate,
      );
      await DatabaseService.updateTransaction(updatedTx);
      try {
        await DatabaseService.removeHiddenTransactionId(tx.id);
      } catch (_) {}
      relinked.add(updatedTx);
    }

    return relinked;
  }

  Future<void> _removeDuplicateBillPaymentsForBill(String billId) async {
    final id = billId.trim();
    if (id.isEmpty) return;

    final grouped = <String, List<Transaction>>{};
    for (final tx in DatabaseService.getAllTransactions()) {
      if ((tx.billId ?? '').trim() != id) continue;
      final occurrenceDate = tx.occurrenceDate == null
          ? null
          : _dateOnly(tx.occurrenceDate!);
      final key = [
        id,
        occurrenceDate == null
            ? ''
            : '${occurrenceDate.year}-${occurrenceDate.month}-${occurrenceDate.day}',
        '${tx.date.year}-${tx.date.month}-${tx.date.day}',
        tx.accountId ?? '',
        tx.type.name,
        tx.amount.toStringAsFixed(2),
        tx.description.trim().toLowerCase(),
        (tx.paymentFor ?? '').trim().toLowerCase(),
      ].join('|');
      grouped.putIfAbsent(key, () => <Transaction>[]).add(tx);
    }

    for (final matches in grouped.values) {
      if (matches.length < 2) continue;
      matches.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      for (final duplicate in matches.skip(1)) {
        await _deletePaymentTransactionAndReverseBalance(duplicate);
      }
    }
  }

  Future<void> _deletePaymentTransactionAndReverseBalance(
    Transaction tx,
  ) async {
    try {
      final accId = tx.accountId;
      if (accId != null) {
        final acc = DatabaseService.getAccountById(accId);
        if (acc != null) {
          final effect = tx.type == TransactionType.income
              ? tx.amount
              : -tx.amount;
          final updatedAcc = acc.copyWith(balance: acc.balance - effect);
          await DatabaseService.updateAccount(updatedAcc);
        }
      }
    } catch (_) {}

    try {
      await DatabaseService.removeHiddenTransactionId(tx.id);
    } catch (_) {}

    await DatabaseService.deleteTransaction(tx.id);
  }

  Future<void> _deleteBillPaymentsWhere(
    Bill bill,
    bool Function(Transaction tx) shouldDelete,
  ) async {
    final payments = DatabaseService.getAllTransactions()
        .where((tx) => (tx.billId ?? '').trim() == bill.id && shouldDelete(tx))
        .toList();

    for (final tx in payments) {
      await _deletePaymentTransactionAndReverseBalance(tx);
    }

    if (!mounted) return;
    _refreshCachedData();
    setState(() {});
  }

  bool _isWithinOriginalSeriesEnd(Bill bill, DateTime occurrenceDate) {
    if (bill.recurrenceEndDate == null) return true;
    final end = _dateOnly(bill.recurrenceEndDate!);
    final occ = _dateOnly(occurrenceDate);
    return !occ.isAfter(end);
  }

  bool _hasFutureOccurrences(Bill bill, DateTime occurrenceDate) {
    if (bill.recurrence == Recurrence.none) return false;
    final nextOccurrence = _computeNextOccurrenceDate(
      bill,
      _dateOnly(occurrenceDate),
    );
    if (nextOccurrence == null) return false;
    return _isWithinOriginalSeriesEnd(bill, nextOccurrence);
  }

  Future<void> _deleteSingleRecurringOccurrence(
    Bill sourceBill,
    DateTime occurrenceDate,
  ) async {
    final DateTime occ = _dateOnly(occurrenceDate);
    final DateTime start = _dateOnly(sourceBill.dueDate);
    final DateTime dayBefore = _addCalendarDays(occ, -1);
    final DateTime? nextOccurrence = _computeNextOccurrenceDate(
      sourceBill,
      occ,
    );

    final shouldCreateFutureSeries =
        nextOccurrence != null &&
        _isWithinOriginalSeriesEnd(sourceBill, nextOccurrence);

    if (occ.isAtSameMomentAs(start) || occ.isBefore(start)) {
      if (shouldCreateFutureSeries) {
        final newBill = Bill(
          amount: sourceBill.amount,
          description: sourceBill.description,
          dueDate: nextOccurrence,
          recurrence: sourceBill.recurrence,
          customDays: sourceBill.customDays,
          recurrenceEndDate: sourceBill.recurrenceEndDate,
          recurrenceInterval: sourceBill.recurrenceInterval,
          recurrenceWeekdays: sourceBill.recurrenceWeekdays,
          categoryId: sourceBill.categoryId,
          type: sourceBill.type,
          fromAccountId: sourceBill.fromAccountId,
          toAccountId: sourceBill.toAccountId,
          payeeId: sourceBill.payeeId,
          accountId: sourceBill.accountId,
          isPaid: false,
        );
        await DatabaseService.addBill(newBill);
      }

      final updatedBill = sourceBill.copyWith(recurrenceEndDate: dayBefore);
      await DatabaseService.updateBill(updatedBill);
      await DatabaseService.setBillRecurrenceEndOverride(
        updatedBill.id,
        dayBefore,
      );
      return;
    }

    final updatedBill = sourceBill.copyWith(recurrenceEndDate: dayBefore);
    await DatabaseService.updateBill(updatedBill);
    await DatabaseService.setBillRecurrenceEndOverride(
      updatedBill.id,
      dayBefore,
    );

    if (shouldCreateFutureSeries) {
      final newBill = Bill(
        amount: sourceBill.amount,
        description: sourceBill.description,
        dueDate: nextOccurrence,
        recurrence: sourceBill.recurrence,
        customDays: sourceBill.customDays,
        recurrenceEndDate: sourceBill.recurrenceEndDate,
        recurrenceInterval: sourceBill.recurrenceInterval,
        recurrenceWeekdays: sourceBill.recurrenceWeekdays,
        categoryId: sourceBill.categoryId,
        type: sourceBill.type,
        fromAccountId: sourceBill.fromAccountId,
        toAccountId: sourceBill.toAccountId,
        payeeId: sourceBill.payeeId,
        accountId: sourceBill.accountId,
        isPaid: false,
      );
      await DatabaseService.addBill(newBill);
    }
  }

  Future<bool> _deleteBillFromDashboard(
    Bill sourceBill,
    DateTime occurrenceDate,
  ) async {
    if (!_hasFutureOccurrences(sourceBill, occurrenceDate)) {
      await _deleteBillOccurrencePayments(
        sourceBill,
        occurrenceDate,
        showNoPaymentsMessage: false,
      );
      await DatabaseService.deleteBill(sourceBill.id);
      return true;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (context) {
          final colorScheme = Theme.of(context).colorScheme;
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            backgroundColor: Colors.transparent,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 460),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(Icons.delete_outline_rounded, color: colorScheme.error),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'Delete Recurring Bill',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Choose whether to delete only this bill or this bill and all future occurrences.',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: colorScheme.error,
                        foregroundColor: colorScheme.onError,
                      ),
                      onPressed: () => Navigator.pop(context, 'this'),
                      icon: const Icon(Icons.event_rounded),
                      label: const Text('Only This Occurrence'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colorScheme.error,
                      ),
                      onPressed: () => Navigator.pop(context, 'all'),
                      icon: const Icon(Icons.event_repeat_rounded),
                      label: const Text('All Future Occurrences'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, 'cancel'),
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
    );

    if (choice == 'this') {
      await _deleteBillOccurrencePayments(
        sourceBill,
        occurrenceDate,
        showNoPaymentsMessage: false,
      );
      await _deleteSingleRecurringOccurrence(sourceBill, occurrenceDate);
      return true;
    }

    if (choice == 'all') {
      final occ = _dateOnly(occurrenceDate);
      final start = _dateOnly(sourceBill.dueDate);

      if (occ.isAtSameMomentAs(start) || occ.isBefore(start)) {
        await _deleteBillPaymentsWhere(sourceBill, (_) => true);
        await DatabaseService.deleteBill(sourceBill.id);
        return true;
      }

      final dayBefore = _addCalendarDays(occ, -1);
      await _deleteBillPaymentsWhere(sourceBill, (tx) {
        final txOcc = tx.occurrenceDate == null
            ? _dateOnly(tx.date)
            : _dateOnly(tx.occurrenceDate!);
        return !txOcc.isBefore(occ);
      });
      final updatedBill = sourceBill.copyWith(recurrenceEndDate: dayBefore);
      await DatabaseService.updateBill(updatedBill);
      await DatabaseService.setBillRecurrenceEndOverride(
        updatedBill.id,
        dayBefore,
      );
      return true;
    }

    return false;
  }

  Future<void> _deleteBillOccurrencePayments(
    Bill bill,
    DateTime occurrenceDate, {
    bool showNoPaymentsMessage = true,
  }) async {
    final relatedPayments = _getTransactionsForBillOccurrence(
      bill,
      occurrenceDate,
    );
    if (relatedPayments.isEmpty) {
      if (showNoPaymentsMessage && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'No payment transaction found for this bill occurrence.',
            ),
            backgroundColor: Colors.blueGrey[400],
          ),
        );
      }
      return;
    }

    for (final tx in relatedPayments) {
      await _deletePaymentTransactionAndReverseBalance(tx);
    }

    if (!mounted) return;
    _refreshCachedData();
    setState(() {});
  }

  Future<void> _handleDelete(Transaction transaction, Bill? sourceBill) async {
    if (sourceBill != null) {
      final occurrenceDate = _transactionOccurrenceDate(transaction);
      final relatedPayments = _getTransactionsForBillOccurrence(
        sourceBill,
        occurrenceDate,
      );
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          final colorScheme = Theme.of(context).colorScheme;
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            backgroundColor: Colors.transparent,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 460),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: colorScheme.error,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'Delete Bill?',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    relatedPayments.isNotEmpty
                        ? 'This bill will be removed from the calendar along with related payment transactions for this occurrence.'
                        : 'This bill will be removed from the calendar.',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: colorScheme.error,
                              foregroundColor: colorScheme.onError,
                            ),
                            onPressed: () => Navigator.pop(context, true),
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('Delete'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (confirmed == true) {
        try {
          await _deleteBillFromDashboard(sourceBill, occurrenceDate);
          if (mounted) {
            ScaffoldMessenger.of(context).clearSnackBars();
            setState(() {});
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error deleting bill: $e'),
                backgroundColor: Colors.blueGrey[400],
              ),
            );
          }
        }
      }
    } else {
      // For non-recurring items, delete the transaction directly.
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Transaction'),
          content: Text(
            'Are you sure you want to delete "${transaction.description}"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        try {
          final accId = transaction.accountId;
          if (accId != null) {
            final acc = DatabaseService.getAccountById(accId);
            if (acc != null) {
              final effect = transaction.type == TransactionType.income
                  ? transaction.amount
                  : -transaction.amount;
              final updatedAcc = acc.copyWith(balance: acc.balance - effect);
              await DatabaseService.updateAccount(updatedAcc);
            }
          }
        } catch (_) {}

        try {
          await DatabaseService.removeHiddenTransactionId(transaction.id);
        } catch (_) {}

        try {
          await DatabaseService.deleteTransaction(transaction.id);
          if (mounted) {
            ScaffoldMessenger.of(context).clearSnackBars();
          }
          setState(() {});
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error deleting: $e'),
                backgroundColor: Colors.blueGrey[400],
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _handlePay(Transaction transaction, Bill? sourceBill) async {
    if (sourceBill != null) {
      final occurrenceDate = _transactionOccurrenceDate(transaction);
      // Open pay bill screen
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) =>
              PayBillScreen(bill: sourceBill, occurrenceDate: occurrenceDate),
        ),
      );

      if (result == true && mounted) {
        setState(() {
          // Refresh the dashboard to show updated data
        });
      }
    } else {
      // For regular transactions, show a message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('This is already a completed transaction'),
          backgroundColor: Colors.blueGrey[400],
        ),
      );
    }
  }

  Future<void> _handleDuplicate(
    Transaction transaction,
    Bill? sourceBill,
  ) async {
    if (sourceBill != null) {
      // Open add bill screen with pre-filled information from the source bill
      // Create a template bill with the same properties but use occurrence date as due date
      final occurrenceDate = _transactionOccurrenceDate(transaction);
      final billTemplate = Bill(
        amount: sourceBill.amount,
        description: sourceBill.description,
        dueDate: occurrenceDate,
        recurrence: Recurrence.none, // Duplicated bills should be one-time
        customDays: null,
        recurrenceEndDate: null,
        recurrenceInterval: 1,
        recurrenceWeekdays: null,
        categoryId: sourceBill.categoryId,
        type: sourceBill.type,
        fromAccountId: sourceBill.fromAccountId,
        toAccountId: sourceBill.toAccountId,
        payeeId: sourceBill.payeeId,
        accountId: sourceBill.accountId,
        isPaid: false, // New bill starts as unpaid
        // per-bill reminder flag removed
      );

      // Navigate to add bill screen with the template and isDuplicate flag
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              AddBillScreen(existingBill: billTemplate, isDuplicate: true),
        ),
      );

      if (result == true && mounted) {
        setState(() {
          // Refresh the dashboard to show the new bill
        });
      }
    } else {
      // For regular transactions, open add bill screen in transaction creation mode
      // with pre-filled information
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const AddTransactionScreen()),
      );

      if (result == true && mounted) {
        setState(() {
          // Refresh the dashboard to show the new transaction
        });
      }
    }
  }

  Widget _buildCategoryIconOrEmoji(Category? category) {
    if (category == null) {
      return Icon(Icons.help, color: Colors.grey, size: 18);
    }
    // Show emoji if it's a single grapheme cluster
    if (category.image != null && category.image!.isNotEmpty) {
      try {
        final chars = category.image!.characters;
        if (chars.length == 1) {
          return Text(
            category.image!,
            style: TextStyle(fontSize: 24, color: category.color),
            textAlign: TextAlign.center,
          );
        }
      } catch (_) {}
    }
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: category.color, shape: BoxShape.circle),
    );
  }
}
