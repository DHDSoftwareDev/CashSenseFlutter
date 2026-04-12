
// ignore_for_file: annotate_overrides, valid_regexps, unnecessary_brace_in_string_interps
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
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const String _showPaidBillsSettingKey = 'dashboardShowPaidBills';

  // Duplicate helper removed — use the top-level _buildCategoryIconOrEmoji defined earlier.
  @override
  void initState() {
    super.initState();
    _showPaidBills =
        DatabaseService.getSetting<bool>(_showPaidBillsSettingKey, false) ?? false;
    DatabaseService.categoriesVersion.addListener(_onCategoriesChanged);
    DatabaseService.billsVersion.addListener(_onBillsChanged);
    DatabaseService.payeesVersion.addListener(_onPayeesChanged);
    DatabaseService.transactionsVersion.addListener(_onTransactionsChanged);
    
    // Add listener to search focus node to show/hide dropdown
    _searchFocusNode.addListener(() {
      if (_searchFocusNode.hasFocus && _searchQuery.isNotEmpty && _searchResults.isNotEmpty) {
        _showSearchDropdown();
      } else if (!_searchFocusNode.hasFocus) {
        _removeSearchDropdown();
      }
    });
  }

  void _onCategoriesChanged() {
    if (!mounted) return;
    setState(() {}); // Triggers rebuild to update category names/colors/icons
  }

  void _onBillsChanged() {
    if (!mounted) return;
    _occurrenceStatusCache.clear();
    if (_searchQuery.isNotEmpty) {
      _performSearch(_searchController.text);
      return;
    }
    setState(() {});
  }

  void _onTransactionsChanged() {
    if (!mounted) return;
    _occurrenceStatusCache.clear();
    if (_searchQuery.isNotEmpty) {
      _performSearch(_searchController.text);
      return;
    }
    setState(() {});
  }

  void _onPayeesChanged() {
    if (!mounted) return;
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
  DateTime? _computeNextOccurrenceDate(Bill sourceBill, DateTime occurrenceDate) {
    if (sourceBill.recurrence == Recurrence.monthly) {
      final interval = sourceBill.recurrenceInterval <= 0 ? 1 : sourceBill.recurrenceInterval;
      final days = sourceBill.customDays == null || sourceBill.customDays!.isEmpty
          ? [sourceBill.dueDate.day]
          : (sourceBill.customDays!..sort());

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
      if (chosen > lastDayTarget) chosen = lastDayTarget; // guard for e.g., 31 in Feb
      return DateTime(targetYear, adjustedMonth, chosen);
    }

    // Fallback: daily/weekly/yearly use previous logic based on occurrenceDate
    if (sourceBill.recurrence == Recurrence.daily) {
      return occurrenceDate.add(Duration(days: sourceBill.recurrenceInterval <= 0 ? 1 : sourceBill.recurrenceInterval));
    }
    if (sourceBill.recurrence == Recurrence.weekly) {
      return occurrenceDate.add(Duration(days: 7 * (sourceBill.recurrenceInterval <= 0 ? 1 : sourceBill.recurrenceInterval)));
    }
    if (sourceBill.recurrence == Recurrence.yearly) {
      final yrs = sourceBill.recurrenceInterval <= 0 ? 1 : sourceBill.recurrenceInterval;
      try {
        return DateTime(occurrenceDate.year + yrs, occurrenceDate.month, occurrenceDate.day);
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
    var idx = _searchResults.lastIndexWhere(
      (r) {
        final d = r['date'] as DateTime;
        final normalized = DateTime(d.year, d.month, d.day);
        return !normalized.isAfter(todayStart);
      },
    );

    if (idx < 0) idx = 0;
    _searchInitialIndex = idx;
  }

  void _showSearchDropdown() {
    if (_searchDropdownOverlay != null) {
      _searchDropdownOverlay!.markNeedsBuild();
      return;
    }

    final overlay = Overlay.of(context);
    final RenderBox? box = _searchFocusNode.hasFocus ? _searchFocusNode.context?.findRenderObject() as RenderBox? : null;
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
                      title: Text(description, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(dateStr),
                      trailing: Text(
                        _currencyFormat.format(bill.amount),
                        style: TextStyle(
                          color: bill.type == BillType.expense ? Colors.red : Colors.green,
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
      final targetOffset = (_searchInitialIndex!.toDouble() * 72.0)
          .clamp(0.0, _searchResultsScrollController.position.maxScrollExtent);
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

  void dispose() {
    _searchDebounceTimer?.cancel();
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
  DateTime? _selectedDay = DateTime.now(); // Initialize to today to show today's transactions immediately
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
  final Map<String, PaymentStatus> _occurrenceStatusCache = <String, PaymentStatus>{};
  final Set<String> _occurrenceStatusBackfillInFlight = <String>{};

  String _occurrenceStatusKey(String billId, DateTime occDate) {
    return '$billId:${occDate.year}-${occDate.month}-${occDate.day}';
  }

  String _billOccurrenceRenderKey(Bill bill, DateTime date) {
    final day = '${date.year}-${date.month}-${date.day}';
    // Include bill id so visually similar bills don't collapse into one entry.
    // Otherwise deleting one of duplicates can appear to "come back" immediately.
    final billId = bill.id.trim();
    return [
      billId,
      day,
      bill.type.name,
    ].join('|');
  }

  List<Map<String, dynamic>> _dedupeBillOccurrences(List<Map<String, dynamic>> occurrences) {
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

  // Search bills by description, payee name, or notes
  void _performSearch(String query) {
    final normalizedQuery = query.toLowerCase().trim();
    if (normalizedQuery.isEmpty) {
      setState(() {
        _searchQuery = '';
        _searchResults.clear();
        _matchedSearchBillIds.clear();
      });
      _removeSearchDropdown();
      return;
    }

    final allBills = DatabaseService.getAllBills();
    final allPayees = DatabaseService.getAllPayees();

    final payeeNameById = <String, String>{};
    for (final payee in allPayees) {
      final id = payee['id']?.toString();
      final name = payee['name']?.toString();
      if (id == null || id.isEmpty || name == null) continue;
      payeeNameById[id] = name;
    }

    final matchedBillIds = <String>{};
    final displayByBillId = <String, String>{};
    for (final bill in allBills) {
      final billDescription = _visibleBillText(bill.description);
      final payeeName = (bill.payeeId != null && bill.payeeId!.isNotEmpty)
          ? (payeeNameById[bill.payeeId!] ?? '')
          : '';
      final searchText = '$billDescription $payeeName'.toLowerCase();
      if (!searchText.contains(normalizedQuery)) continue;
      matchedBillIds.add(bill.id);
      displayByBillId[bill.id] = payeeName.isNotEmpty ? payeeName : billDescription;
    }

    final results = <Map<String, dynamic>>[];
    if (matchedBillIds.isNotEmpty) {
      final now = DateTime.now();
      final startDate = DateTime(now.year - 1, now.month, now.day);
      final endDate = DateTime(now.year + 1, now.month, now.day);

      final allOccurrences = _dedupeBillOccurrences(
        DatabaseService.getBillOccurrencesBetween(startDate, endDate),
      );

      for (final occ in allOccurrences) {
        final bill = occ['bill'];
        final date = occ['date'];
        if (bill is! Bill || date is! DateTime) continue;
        if (!matchedBillIds.contains(bill.id)) continue;
        if (!_showPaidBills) {
          // Fast path for search typing: rely on persisted occurrence state to
          // avoid expensive recomputation for every keypress.
          final persisted = DatabaseService.getBillOccurrenceStatus(bill.id, date);
          final persistedStatus = persisted?['paymentStatus'] as PaymentStatus?;
          final persistedIsPaid = persisted?['isPaid'] as bool?;
          final isPaid = persistedStatus == PaymentStatus.paid ||
              (persistedStatus == null && persistedIsPaid == true);
          if (isPaid) continue;
        }
        results.add({
          'bill': bill,
          'date': date,
          'description': displayByBillId[bill.id] ?? _visibleBillText(bill.description),
        });
      }
    }

    results.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

    setState(() {
      _searchQuery = normalizedQuery;
      _searchResults
        ..clear()
        ..addAll(results);
      _matchedSearchBillIds
        ..clear()
        ..addAll(matchedBillIds);
      _positionSearchResultsAtToday();
    });

    if (_searchResults.isNotEmpty && _searchFocusNode.hasFocus) {
      _showSearchDropdown();
    } else {
      _removeSearchDropdown();
    }
  }

  void _scheduleSearch(String query) {
    _searchDebounceTimer?.cancel();

    final normalizedQuery = query.toLowerCase().trim();
    if (normalizedQuery.isEmpty) {
      _performSearch('');
      return;
    }

    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      if (_searchController.text.toLowerCase().trim() != normalizedQuery) return;
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
      title: const DashboardTitleInline(),
      titleSpacing: 0,
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: () async {
            final isSubscriber = (DatabaseService.getSetting<String>('subscriptionPlan', 'Free') ?? 'Free') != 'Free';
            final bills = DatabaseService.getAllBills();
            if (!isSubscriber && bills.length >= 100) {
              await showDialog(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Bill/Payment Limit Reached'),
                  content: const Text('Free users can create up to 100 bills and payments. Subscribe for unlimited bills and payments.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('OK')),
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
        const SizedBox(height: 16),
        Center(child: _buildFilterChips()),
        const SizedBox(height: 12),
        // The scrolling content (recent transactions, ad, divider) lives
        // inside the Expanded ListView so the calendar remains fixed.
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _buildRecentTransactionsCard(),
                const SizedBox(height: 8),
                const BannerAdWidget(),
                const Divider(height: 1),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search bills...',
                    hintStyle: const TextStyle(fontSize: 14),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              _searchController.clear();
                              _performSearch('');
                              _closeSearchInteraction();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    isDense: true,
                  ),
                  onChanged: _scheduleSearch,
                  onTap: () {
                    if (_searchQuery.isNotEmpty && _searchResults.isNotEmpty) {
                      _showSearchDropdown();
                    }
                  },
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
                    setState(() {
                      // Move focus to the previous month and select its first day
                      final prevMonth = DateTime(_focusedDay.year, _focusedDay.month - 1, 1);
                      _focusedDay = prevMonth;
                      _selectedDay = DateTime(prevMonth.year, prevMonth.month, 1);
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
                    setState(() {
                      // Move focus to the next month and select its first day
                      final nextMonth = DateTime(_focusedDay.year, _focusedDay.month + 1, 1);
                      _focusedDay = nextMonth;
                      _selectedDay = DateTime(nextMonth.year, nextMonth.month, 1);
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
                setState(() {
                  _focusedDay = focused;
                  // Only change selected day to the 1st if the selected day is in a different month
                  // than the focused month AND the focused day itself isn't a specific selected date
                  if (_selectedDay == null || 
                      (_selectedDay!.year != focused.year || _selectedDay!.month != focused.month)) {
                    // Don't reset if the focused date IS the selected date (e.g., from search or Today button)
                    if (!isSameDay(_selectedDay, focused)) {
                      _selectedDay = DateTime(focused.year, focused.month, 1);
                    }
                  }
                });
              },
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              eventLoader: (day) {
                // Calendar events are bill-only on dashboard.
                final billDay = DateTime(day.year, day.month, day.day);
                var billOcc = DatabaseService.getBillOccurrencesBetween(billDay, billDay);
                billOcc = _dedupeBillOccurrences(billOcc);
                
                // Apply search filter if search query is not empty
                if (_searchQuery.isNotEmpty) {
                  billOcc = billOcc.where((occ) {
                    final bill = occ['bill'] as Bill;
                    return _matchedSearchBillIds.contains(bill.id);
                  }).toList();
                }
                
                // Use the persisted per-occurrence status from Pay Bill as the source of truth.
                final List<Map<String, dynamic>> updatedBillOcc = [];
                for (final occ in billOcc) {
                  final bill = occ['bill'] as Bill;
                  final occDate = occ['date'] as DateTime;
                  final isPaid = _getOccurrencePaymentStatus(bill, occDate) == PaymentStatus.paid;
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
                  // Color the date if a bill (including transfer bills) is present
                  var billOcc = DatabaseService.getBillOccurrencesBetween(
                        DateTime(day.year, day.month, day.day),
                        DateTime(day.year, day.month, day.day));
                  billOcc = _dedupeBillOccurrences(billOcc);
                  
                  // Apply search filter if search query is not empty
                  if (_searchQuery.isNotEmpty) {
                    billOcc = billOcc.where((occ) {
                      final bill = occ['bill'] as Bill;
                      return _matchedSearchBillIds.contains(bill.id);
                    }).toList();
                  }
                  
                  final hasOutstandingBills = billOcc.any((occ) {
                    final bill = occ['bill'] as Bill?;
                    final occDate = occ['date'] as DateTime?;
                    if (bill == null || occDate == null) return false;
                    return _getOccurrencePaymentStatus(bill, occDate) != PaymentStatus.paid;
                  });
                  final textStyle = hasOutstandingBills
                      ? Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.primary)
                      : Theme.of(context).textTheme.bodyMedium;
                  return Center(child: Text('${day.day}', style: textStyle));
                },
                todayBuilder: (context, day, focusedDay) {
                  var billOcc = DatabaseService.getBillOccurrencesBetween(
                        DateTime(day.year, day.month, day.day),
                        DateTime(day.year, day.month, day.day));
                  billOcc = _dedupeBillOccurrences(billOcc);
                  
                  // Apply search filter if search query is not empty
                  if (_searchQuery.isNotEmpty) {
                    billOcc = billOcc.where((occ) {
                      final bill = occ['bill'] as Bill;
                      return _matchedSearchBillIds.contains(bill.id);
                    }).toList();
                  }
                  
                  final hasOutstandingBills = billOcc.any((occ) {
                    final bill = occ['bill'] as Bill?;
                    final occDate = occ['date'] as DateTime?;
                    if (bill == null || occDate == null) return false;
                    return _getOccurrencePaymentStatus(bill, occDate) != PaymentStatus.paid;
                  });
                  final base = BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withAlpha((0.2 * 255).round()),
                    shape: BoxShape.circle,
                  );
                  final textStyle = hasOutstandingBills
                      ? Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.primary)
                      : Theme.of(context).textTheme.bodyMedium;
                  return Center(
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: base,
                      alignment: Alignment.center,
                      child: Text('${day.day}', style: textStyle),
                    ),
                  );
                },
                selectedBuilder: (context, day, focusedDay) {
                  // Selected day should still stand out; use onPrimary color for contrast
                  return Center(
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Text('${day.day}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onPrimary)),
                    ),
                  );
                },
              ),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay; // update _focusedDay here as well
                });
              },
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withAlpha((0.2 * 255).round()),
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
    );
  }

  Future<void> _refreshData() async {
    setState(() {});
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

  bool _matchesBillOccurrenceForStatus(Bill bill, Transaction tx, DateTime occDate) {
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
      final dateMatches = paymentFor.contains(dateLong) ||
          paymentFor.contains(dateShort) ||
          descriptionLower.contains(dateLong.toLowerCase()) ||
          descriptionLower.contains(dateShort.toLowerCase());
      final billMatches = billText.isNotEmpty &&
          (paymentForLower.contains(billText) || descriptionLower.contains(billText));
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

    final persisted = DatabaseService.getBillOccurrenceStatus(bill.id, occDate);
    final persistedStatus = persisted?['paymentStatus'] as PaymentStatus?;
    final persistedIsPaid = persisted?['isPaid'] as bool?;

    final payments = DatabaseService.getAllTransactions()
        .where((tx) => _matchesBillOccurrenceForStatus(bill, tx, occDate))
        .toList();

    final totalPaid = _computeSignedTotalPaid(bill, payments);
    final computedStatus = _finalizeBillStatus(bill, totalPaid);

    // Keep persisted status in sync with computed status, but always return
    // the computed value so dashboard matches Pay Bill status immediately.
    final persistedFromBool = persistedIsPaid == null
        ? null
        : (persistedIsPaid ? PaymentStatus.paid : PaymentStatus.unpaid);
    if (persistedStatus != computedStatus && persistedFromBool != computedStatus) {
      _backfillOccurrenceStatus(bill, occDate, computedStatus);
    }

    _occurrenceStatusCache[cacheKey] = computedStatus;
    return computedStatus;
  }

  void _backfillOccurrenceStatus(Bill bill, DateTime occDate, PaymentStatus status) {
    final key = '${bill.id}_${occDate.year}-${occDate.month}-${occDate.day}';
    if (!_occurrenceStatusBackfillInFlight.add(key)) return;

    DatabaseService
        .setBillOccurrenceStatus(
          bill.id,
          occDate,
          status == PaymentStatus.paid,
          status,
        )
        .catchError((_) {})
        .whenComplete(() {
          _occurrenceStatusBackfillInFlight.remove(key);
        });
  }

  // ignore: unused_element
  Widget _buildFilterChips() {
    final theme = Theme.of(context);

    return FilterChip(
      label: Text(_showPaidBills ? 'Hide Paid Bills' : 'Show Paid Bills'),
      selected: _showPaidBills,
      onSelected: (_) {
        setState(() {
          _showPaidBills = !_showPaidBills;
        });
        DatabaseService.setSetting(_showPaidBillsSettingKey, _showPaidBills);
      },
      selectedColor: theme.colorScheme.primary.withAlpha((0.18 * 255).round()),
      checkmarkColor: theme.colorScheme.primary,
      side: BorderSide(color: theme.colorScheme.outline),
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
        final allPayees = DatabaseService.getAllPayees();
        final payee = allPayees.firstWhere(
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
      final startOfSelected = DateTime(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day);
      billOcc = DatabaseService.getBillOccurrencesBetween(startOfSelected, startOfSelected);
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
          return _getOccurrencePaymentStatus(bill, occDate) != PaymentStatus.paid;
        }).toList();
      }
      recentTransactions = <TransactionDisplayItem>[];
      for (final b in billOcc) {
        final bill = b['bill'] as Bill;
        final date = b['date'] as DateTime;
        if (bill.type == BillType.transfer) {
          final fromAcc = bill.fromAccountId != null ? DatabaseService.getAccountById(bill.fromAccountId!) : null;
          final toAcc = bill.toAccountId != null ? DatabaseService.getAccountById(bill.toAccountId!) : null;
          final fromName = fromAcc?.name ?? 'From account';
          final toName = toAcc?.name ?? 'To account';
            final cleanBillDescription = _visibleBillText(bill.description);
            final desc = cleanBillDescription.isNotEmpty
              ? cleanBillDescription
              : 'Transfer from $fromName to $toName';
            final billNote = cleanBillDescription;
          final String? debitNote = billNote.isNotEmpty ? 'account: $fromName — $billNote' : null;
          final debit = Transaction(
            amount: bill.amount,
            categoryId: '',
            type: TransactionType.expense,
            description: desc,
            date: date,
            note: debitNote,
          );
          recentTransactions.add(TransactionDisplayItem(debit, sourceBill: bill));
          final String? creditNote = billNote.isNotEmpty ? 'account: $toName — $billNote' : null;
          final credit = Transaction(
            amount: bill.amount,
            categoryId: '',
            type: TransactionType.income,
            description: desc,
            date: date,
            note: creditNote,
          );
          recentTransactions.add(TransactionDisplayItem(credit, sourceBill: bill));
        } else {
          String desc = _visibleBillText(bill.description);
          if (bill.payeeId != null) {
            final payees = DatabaseService.getAllPayees();
            final p = payees.firstWhere((p) => p['id'] == bill.payeeId, orElse: () => <String, dynamic>{});
            if (p.containsKey('name')) desc = p['name'] as String;
          }
          // Only show dashboard note content when the bill notes field has text.
          String? noteWithAccount;
          final billNote = _visibleBillText(bill.description);
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
            note: noteWithAccount,
          );
          recentTransactions.add(TransactionDisplayItem(placeholder, sourceBill: bill));
        }
      }
      recentTransactions.sort((a, b) => b.transaction.date.compareTo(a.transaction.date));
    } else {
      final allBills = DatabaseService.getAllBills();
      final now = DateTime.now();
      DateTime start;
      DateTime end;
      if (allBills.isEmpty) {
        start = DateTime(now.year, now.month, now.day);
        end = start;
      } else {
        start = allBills
            .map((b) => DateTime(b.dueDate.year, b.dueDate.month, b.dueDate.day))
            .reduce((a, b) => a.isBefore(b) ? a : b);
        final latestBound = allBills
            .map((b) => b.recurrenceEndDate ?? DateTime(now.year + 10, now.month, now.day))
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
          return _getOccurrencePaymentStatus(bill, occDate) != PaymentStatus.paid;
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
          final fromAcc = bill.fromAccountId != null ? DatabaseService.getAccountById(bill.fromAccountId!) : null;
          final toAcc = bill.toAccountId != null ? DatabaseService.getAccountById(bill.toAccountId!) : null;
          final fromName = fromAcc?.name ?? 'From account';
          final toName = toAcc?.name ?? 'To account';
            final cleanBillDescription = _visibleBillText(bill.description);
            final desc = cleanBillDescription.isNotEmpty
              ? cleanBillDescription
              : 'Transfer from $fromName to $toName';
          String? debitNote = 'account: $fromName';
            if (cleanBillDescription.isNotEmpty) debitNote = 'account: $fromName — $cleanBillDescription';
          final debit = Transaction(
            amount: bill.amount,
            categoryId: '',
            type: TransactionType.expense,
            description: desc,
            date: date,
            note: debitNote,
          );
          recentTransactions.add(TransactionDisplayItem(debit, sourceBill: bill));
          String? creditNote = 'account: $toName';
          if (cleanBillDescription.isNotEmpty) creditNote = 'account: $toName — $cleanBillDescription';
          final credit = Transaction(
            amount: bill.amount,
            categoryId: '',
            type: TransactionType.income,
            description: desc,
            date: date,
            note: creditNote,
          );
          recentTransactions.add(TransactionDisplayItem(credit, sourceBill: bill));
        } else {
          String desc = _visibleBillText(bill.description);
          if (bill.payeeId != null) {
            final payees = DatabaseService.getAllPayees();
            final p = payees.firstWhere((p) => p['id'] == bill.payeeId, orElse: () => <String, dynamic>{});
            if (p.containsKey('name')) desc = p['name'] as String;
          }
          String? noteWithAccount;
          final billNote = _visibleBillText(bill.description);
          if (bill.accountId != null) {
            final account = DatabaseService.getAccountById(bill.accountId!);
            if (account != null) {
              if (billNote.isNotEmpty) {
                noteWithAccount = 'account: ${account.name} — $billNote';
              } else {
                noteWithAccount = 'account: ${account.name}';
              }
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
            note: noteWithAccount,
          );
          recentTransactions.add(TransactionDisplayItem(placeholder, sourceBill: bill));
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
                  _buildTransactionItem(recentTransactions[i].transaction, recentTransactions[i].sourceBill),
                  if (i != recentTransactions.length - 1) const SizedBox(height: 4),
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
    if (transaction.splitsJson != null && transaction.splitsJson!.trim().isNotEmpty) {
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
            final amountStr = amt is num ? _currencyFormat.format(amt.toDouble()) : amt?.toString() ?? '';
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
    final fallbackCounterparty =
        transaction.type == TransactionType.expense ? payeeText : payerText;
    final displayTitle = (transaction.description.trim().isEmpty ||
            transaction.description.trim().toLowerCase() == 'transaction')
        ? (fallbackCounterparty.isEmpty ? transaction.description : fallbackCounterparty)
        : transaction.description;
    // Create unique ID for this transaction card
    final cardId = '${transaction.date.millisecondsSinceEpoch}_${transaction.description}_${transaction.amount}';
    final isExpanded = _expandedTransactionIds.contains(cardId);

    // Calculate payment progress if this is a bill
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
      // Only count payments for this bill occurrence (billId + occurrence date)
        final allTransactions = DatabaseService.getAllTransactions()
          .where((t) => t.hideFromCalendarDashboard != true)
          .toList();
      final occDate = transaction.date;
      final occDateStr = DateFormat('MM/dd/yyyy').format(occDate);
      final paymentHistory = allTransactions.where((tx) =>
        tx.billId == sourceBill.id && (
          (tx.occurrenceDate != null
            ? (tx.occurrenceDate!.year == occDate.year && tx.occurrenceDate!.month == occDate.month && tx.occurrenceDate!.day == occDate.day)
            : ((tx.date.year == occDate.year && tx.date.month == occDate.month && tx.date.day == occDate.day) || tx.description.contains(occDateStr))
          )
        )
      ).toList();
      final totalPaid = paymentHistory.fold<double>(0.0, (sum, tx) => sum + tx.amount);
      amountPaid = totalPaid;
      amountDue = sourceBill.amount - totalPaid;

      // Calculate progress (0.0 to 1.0)
      if (sourceBill.amount > 0) {
        paymentProgress = (totalPaid / sourceBill.amount).clamp(0.0, 1.0);
      }

      // Status is now tracked in sourceBill.paymentStatus
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
      plainNote = plainNote.replaceAll(RegExp(r'pair:[A-Za-z0-9\-]+'), '').trim();
      if (plainNote.isEmpty) plainNote = null;
    }
    if (plainNote != null && plainNote.startsWith('account:')) {
      // Accept several dash separators (em-dash, en-dash, hyphen) with optional spaces
      // Examples:
      //  'account: Name — notes'
      //  'account: Name - notes'
      //  'account: Name–notes'
      final after = plainNote.substring('account:'.length).trim();
      // split on em-dash (—), en-dash (–), or hyphen (-) with optional surrounding whitespace
      final parts = after.split(RegExp(r'\s*[—–-]\s*'));
      if (parts.isNotEmpty) {
        final extractedAccountName = parts.first.trim();
        if (extractedAccountName.isNotEmpty) {
          accountNameFromNote = extractedAccountName;
        }
      }
      if (parts.length > 1) {
        plainNote = parts.sublist(1).join(' — ').trim();
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
            accountDisplayName = DatabaseService.getAccountById(accountId)?.name;
          }
          accountDisplayName ??= transaction.type == TransactionType.expense
              ? 'From account'
              : 'To account';
        } else {
          final accountId = sourceBill.accountId ?? transaction.accountId;
          if (accountId != null && accountId.isNotEmpty) {
            accountDisplayName = DatabaseService.getAccountById(accountId)?.name;
          }
        }
      }
    }

    final cardContent = Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
      child: InkWell(
        onTap: () async {
          await _handleEdit(transaction, sourceBill);
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Row(
                children: [
                  // Left column: date, name (description), category
                  Expanded(
                    child: Row(
                      children: [
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: Center(
                            child: safeCategoryIcon(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(DateFormat('MM/dd/yyyy').format(transaction.date), style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 4),
                            Text(
                              displayTitle,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12.5),
                            ),
                            const SizedBox(height: 2),
                            Text(categoryDisplay, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Right column: amount, optional note, payment status
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${transaction.type == TransactionType.income ? '+' : '-'}${_currencyFormat.format(transaction.amount)}',
                      style: sourceBill != null
                          ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: transaction.type == TransactionType.income
                                  ? AppTheme.incomeGreen.withValues(alpha: 0.9)
                                  : AppTheme.expenseRed.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            )
                          : Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: transaction.type == TransactionType.income ? AppTheme.incomeGreen : AppTheme.expenseRed,
                              fontWeight: FontWeight.bold,
                            ),
                    ),
                    const SizedBox(height: 6),
                    if (sourceBill != null &&
                        accountDisplayName != null &&
                        accountDisplayName.trim().isNotEmpty) ...[
                      SizedBox(
                        width: 160,
                        child: Text(
                          accountDisplayName,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.right,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    if (plainNote != null && plainNote.trim().isNotEmpty)
                      SizedBox(
                        width: 160,
                        child: Text(
                          plainNote,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                          textAlign: TextAlign.right,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(height: 6),
                    // Payment status (for bills) — compute from transactions at display time
                    if (sourceBill != null) ...[
                      Builder(builder: (ctx) {
                        final occDate = transaction.date;
                        final status = _getOccurrencePaymentStatus(sourceBill, occDate);
                        String label;
                        Color color;
                        if (status == PaymentStatus.paid) {
                          label = 'Paid';
                          color = AppTheme.incomeGreen;
                        } else if (status == PaymentStatus.partial) {
                          label = 'Partial';
                          color = Colors.orange;
                        } else {
                          label = 'Unpaid';
                          color = AppTheme.expenseRed;
                        }
                        return Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.bold));
                      }),
                    ],
                  ],
                ),
                // Add menu button for edit, delete, pay options
              ],
            ),
            // Payment Progress Bar (only show for bills when expanded)
            if (isExpanded && paymentProgress != null && sourceBill != null) ...[
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Payment Progress',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      Text(
                        '${(paymentProgress * 100).toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: paymentProgress >= 1.0 ? AppTheme.incomeGreen : AppTheme.expenseRed,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: paymentProgress,
                      minHeight: 8,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        paymentProgress >= 1.0 ? AppTheme.incomeGreen : AppTheme.expenseRed,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Paid: ${_currencyFormat.format(amountPaid)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        'Due: ${_currencyFormat.format(amountDue != null && amountDue > 0 ? amountDue : 0)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: amountDue != null && amountDue > 0 ? AppTheme.expenseRed : AppTheme.incomeGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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
                  style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.1),
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
                    style: TextStyle(color: Colors.white, fontSize: 11, height: 1.1),
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
                  style: TextStyle(color: Colors.white, fontSize: 11, height: 1.1),
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
                  style: TextStyle(color: Colors.white, fontSize: 11, height: 1.1),
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
    final Bill? effectiveSourceBill = sourceBill ?? (() {
      final billId = transaction.billId;
      if (billId == null || billId.isEmpty) return null;
      try {
        return DatabaseService.getAllBills().firstWhere((b) => b.id == billId);
      } catch (_) {
        return null;
      }
    })();

    sourceBill = effectiveSourceBill;

    if (sourceBill != null && _hasFutureOccurrences(sourceBill, transaction.date)) {
      // If this is a recurring bill, ask whether to edit only this occurrence or all future occurrences
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Edit Recurring Bill'),
          content: const Text('This is a recurring bill. Do you want to edit only this occurrence or all future occurrences?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, 'cancel'), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, 'this'), child: const Text('Only This Occurrence')),
            TextButton(onPressed: () => Navigator.pop(context, 'all'), child: const Text('All Future Occurrences')),
          ],
        ),
      );

      if (choice == 'this') {
        // Edit only this occurrence: create a one-off edited bill for the occurrence date,
        // and split the existing series so it ends before this occurrence and (if applicable) recreate the future series starting after it.
        final occurrenceDate = transaction.date;

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
          isPaid: DatabaseService.getBillOccurrenceStatus(sourceBill.id, occurrenceDate)?['isPaid'] as bool? ?? sourceBill.isPaid,
          // per-bill reminder flag removed
        );

        final editedResult = await Navigator.push<dynamic>(
          context,
          MaterialPageRoute(builder: (context) => AddBillScreen(existingBill: tempBill, isDuplicate: true)),
        );

        // editedResult may be `true` (legacy) or a String containing the new bill id.
        final String? occurrenceBillId = (editedResult is String) ? editedResult : null;

        if (editedResult == true || occurrenceBillId != null) {
          try {
            final dayBefore = occurrenceDate.subtract(const Duration(days: 1));

            // "Only this occurrence" must always remain a one-time bill.
            // If the edit screen changed recurrence, normalize it back to none
            // to avoid future duplicate occurrences.
            if (occurrenceBillId != null) {
              try {
                final created = DatabaseService.getAllBills().firstWhere((b) => b.id == occurrenceBillId);
                if (created.recurrence != Recurrence.none) {
                  final oneOff = created.copyWith(
                    dueDate: occurrenceDate,
                    recurrence: Recurrence.none,
                    customDays: null,
                    recurrenceEndDate: null,
                    recurrenceInterval: 1,
                    recurrenceWeekdays: null,
                  );
                  await DatabaseService.updateBill(oneOff);
                }
              } catch (_) {}
            }

            // Calculate next occurrence date based on recurrence (handles monthly custom days)
            final DateTime? nextOccurrenceDate = _computeNextOccurrenceDate(sourceBill, occurrenceDate);

            // Update original bill to end before this occurrence
            final updatedBill = sourceBill.copyWith(recurrenceEndDate: dayBefore);
            await DatabaseService.updateBill(updatedBill);
            await DatabaseService.setBillRecurrenceEndOverride(updatedBill.id, dayBefore);

            // If there is a next occurrence and the original had an end date beyond it (or no end), recreate the future series
            if (nextOccurrenceDate != null && (sourceBill.recurrenceEndDate == null || nextOccurrenceDate.isBefore(sourceBill.recurrenceEndDate!) || nextOccurrenceDate.isAtSameMomentAs(sourceBill.recurrenceEndDate!))) {
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
                isPaid: DatabaseService.getBillOccurrenceStatus(sourceBill.id, occurrenceDate)?['isPaid'] as bool? ?? sourceBill.isPaid,
                // per-bill reminder flag removed
              );
              await DatabaseService.addBill(newBill);
              }
              // If the AddBillScreen returned a specific occurrence bill id, migrate
              // payments for this occurrence to that bill so history remains visible.
              try {
                final allTx = DatabaseService.getAllTransactions()
                  .where((t) => t.hideFromCalendarDashboard != true)
                  .toList();
                final occDateStr = DateFormat('MM/dd/yyyy').format(occurrenceDate);
                final migrated = allTx.where((tx) =>
                  tx.billId == sourceBill!.id && (
                    (tx.occurrenceDate != null
                      ? (tx.occurrenceDate!.year == occurrenceDate.year && tx.occurrenceDate!.month == occurrenceDate.month && tx.occurrenceDate!.day == occurrenceDate.day)
                      : ((tx.date.year == occurrenceDate.year && tx.date.month == occurrenceDate.month && tx.date.day == occurrenceDate.day) || tx.description.contains(occDateStr))
                    )
                  )
                ).toList();
                for (final tx in migrated) {
                  final targetBillId = occurrenceBillId ?? tx.billId; // migrate to occurrence bill if available
                  final updatedTx = tx.copyWith(billId: targetBillId);
                  await DatabaseService.updateTransaction(updatedTx);
                  try {
                    await DatabaseService.removeHiddenTransactionId(tx.id);
                  } catch (_) {}
                }
                // Persist occurrence-level status for the occurrence on the occurrence-specific bill
                if (occurrenceBillId != null) {
                  double totalPaid = _computeSignedTotalPaid(sourceBill, migrated);
                  PaymentStatus newStatus;
                  if (totalPaid <= 0) {
                    newStatus = PaymentStatus.unpaid;
                  } else if (totalPaid >= (sourceBill.amount - 0.01)) {
                    newStatus = PaymentStatus.paid;
                  } else {
                    newStatus = PaymentStatus.partial;
                  }
                  await DatabaseService.setBillOccurrenceStatus(occurrenceBillId, occurrenceDate, newStatus == PaymentStatus.paid, newStatus);
                }
              } catch (_) {}
            }

            if (mounted) {
              ScaffoldMessenger.of(context).clearSnackBars();
            }
            setState(() {});
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
        final occurrenceDate = transaction.date;

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
          isPaid: DatabaseService.getBillOccurrenceStatus(sourceBill.id, occurrenceDate)?['isPaid'] as bool? ?? sourceBill.isPaid,
          // per-bill reminder flag removed
        );

        final editedResult = await Navigator.push<dynamic>(
          context,
          MaterialPageRoute(builder: (context) => AddBillScreen(existingBill: tempNewBill, isDuplicate: true)),
        );

        final String? newBillId = (editedResult is String) ? editedResult : null;

        if (editedResult == true || newBillId != null) {
          try {
            final dayBefore = occurrenceDate.subtract(const Duration(days: 1));

            // Update original bill to end before this occurrence so past
            // occurrences remain associated with it and are not modified.
            final updatedBill = sourceBill.copyWith(recurrenceEndDate: dayBefore);
            await DatabaseService.updateBill(updatedBill);
            await DatabaseService.setBillRecurrenceEndOverride(updatedBill.id, dayBefore);

            // If a new bill id was returned, migrate transactions that belong
            // to this original bill but are for occurrences on/after the
            // occurrenceDate to the new bill so they reflect the edited
            // future series. Leave any past transactions untouched.
            if (newBillId != null) {
              try {
                final allTx = DatabaseService.getAllTransactions()
                  .where((t) => t.hideFromCalendarDashboard != true)
                  .toList();
                final occDateStr = DateFormat('MM/dd/yyyy').format(occurrenceDate);
                final toMigrate = allTx.where((tx) {
                  if (tx.billId != sourceBill!.id) return false;
                  // If tx has an explicit occurrenceDate, compare that.
                  if (tx.occurrenceDate != null) {
                    final od = DateTime(tx.occurrenceDate!.year, tx.occurrenceDate!.month, tx.occurrenceDate!.day);
                    return !od.isBefore(DateTime(occurrenceDate.year, occurrenceDate.month, occurrenceDate.day));
                  }
                  // Otherwise, treat transactions on/after the occurrenceDate
                  // or those with descriptions indicating the occurrence date
                  // as part of the future series.
                  final td = DateTime(tx.date.year, tx.date.month, tx.date.day);
                  if (!td.isBefore(DateTime(occurrenceDate.year, occurrenceDate.month, occurrenceDate.day))) return true;
                  if (tx.description.contains(occDateStr)) return true;
                  return false;
                }).toList();

                for (final tx in toMigrate) {
                  final updatedTx = tx.copyWith(billId: newBillId);
                  await DatabaseService.updateTransaction(updatedTx);
                  try {
                    await DatabaseService.removeHiddenTransactionId(tx.id);
                  } catch (_) {}
                }
              } catch (_) {}
            }

            if (mounted) {
              ScaffoldMessenger.of(context).clearSnackBars();
            }
            setState(() {});
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
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AddBillScreen(existingBill: sourceBill),
        ),
      );
      if (result == true && mounted) setState(() {});
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

  List<Transaction> _getTransactionsForBillOccurrence(Bill bill, DateTime occurrenceDate) {
    final occDateStr = DateFormat('MM/dd/yyyy').format(occurrenceDate);
    return DatabaseService.getAllTransactions().where((tx) {
      if (tx.billId != bill.id) return false;

      if (tx.occurrenceDate != null) {
        return _isSameDay(tx.occurrenceDate!, occurrenceDate);
      }

      return _isSameDay(tx.date, occurrenceDate) || tx.description.contains(occDateStr);
    }).toList();
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  bool _isWithinOriginalSeriesEnd(Bill bill, DateTime occurrenceDate) {
    if (bill.recurrenceEndDate == null) return true;
    final end = _dateOnly(bill.recurrenceEndDate!);
    final occ = _dateOnly(occurrenceDate);
    return !occ.isAfter(end);
  }

  bool _hasFutureOccurrences(Bill bill, DateTime occurrenceDate) {
    if (bill.recurrence == Recurrence.none) return false;
    final nextOccurrence = _computeNextOccurrenceDate(bill, _dateOnly(occurrenceDate));
    if (nextOccurrence == null) return false;
    return _isWithinOriginalSeriesEnd(bill, nextOccurrence);
  }

  Future<void> _deleteSingleRecurringOccurrence(Bill sourceBill, DateTime occurrenceDate) async {
    final DateTime occ = _dateOnly(occurrenceDate);
    final DateTime start = _dateOnly(sourceBill.dueDate);
    final DateTime dayBefore = occ.subtract(const Duration(days: 1));
    final DateTime? nextOccurrence = _computeNextOccurrenceDate(sourceBill, occ);

    final shouldCreateFutureSeries =
        nextOccurrence != null && _isWithinOriginalSeriesEnd(sourceBill, nextOccurrence);

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

      await DatabaseService.deleteBill(sourceBill.id);
      return;
    }

    final updatedBill = sourceBill.copyWith(recurrenceEndDate: dayBefore);
    await DatabaseService.updateBill(updatedBill);
    await DatabaseService.setBillRecurrenceEndOverride(updatedBill.id, dayBefore);

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

  Future<bool> _deleteBillFromDashboard(Bill sourceBill, DateTime occurrenceDate) async {
    if (!_hasFutureOccurrences(sourceBill, occurrenceDate)) {
      await DatabaseService.deleteBill(sourceBill.id);
      return true;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Recurring Bill'),
        content: const Text('Do you want to delete only this occurrence or all future occurrences?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'cancel'), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, 'this'), child: const Text('Only This Occurrence')),
          TextButton(onPressed: () => Navigator.pop(context, 'all'), child: const Text('All Future Occurrences')),
        ],
      ),
    );

    if (choice == 'this') {
      await _deleteSingleRecurringOccurrence(sourceBill, occurrenceDate);
      return true;
    }

    if (choice == 'all') {
      final occ = _dateOnly(occurrenceDate);
      final start = _dateOnly(sourceBill.dueDate);

      if (occ.isAtSameMomentAs(start) || occ.isBefore(start)) {
        await DatabaseService.deleteBill(sourceBill.id);
        return true;
      }

      final dayBefore = occ.subtract(const Duration(days: 1));
      final updatedBill = sourceBill.copyWith(recurrenceEndDate: dayBefore);
      await DatabaseService.updateBill(updatedBill);
      await DatabaseService.setBillRecurrenceEndOverride(updatedBill.id, dayBefore);
      return true;
    }

    return false;
  }

  Future<void> _deleteBillOccurrencePayments(Bill bill, DateTime occurrenceDate, {bool showNoPaymentsMessage = true}) async {
    final relatedPayments = _getTransactionsForBillOccurrence(bill, occurrenceDate);
    if (relatedPayments.isEmpty) {
      if (showNoPaymentsMessage && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No payment transaction found for this bill occurrence.'),
            backgroundColor: Colors.blueGrey[400],
          ),
        );
      }
      return;
    }

    for (final tx in relatedPayments) {
      try {
        final accId = tx.accountId;
        if (accId != null) {
          final acc = DatabaseService.getAccountById(accId);
          if (acc != null) {
            final effect = tx.type == TransactionType.income ? tx.amount : -tx.amount;
            final updatedAcc = acc.copyWith(balance: acc.balance - effect);
            await DatabaseService.updateAccount(updatedAcc);
          }
        }
      } catch (_) {
        // Ignore balance rollback failures and continue deleting the payment.
      }

      try {
        await DatabaseService.removeHiddenTransactionId(tx.id);
      } catch (_) {}

      await DatabaseService.deleteTransaction(tx.id);
    }

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _handleDelete(Transaction transaction, Bill? sourceBill) async {
    if (sourceBill != null) {
      final relatedPayments = _getTransactionsForBillOccurrence(sourceBill, transaction.date);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Bill'),
          content: Text(
            relatedPayments.isNotEmpty
                ? 'Delete this bill from the calendar and remove related payment transaction(s) for this occurrence?'
                : 'Delete this bill from the calendar?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        try {
          final billDeleted = await _deleteBillFromDashboard(sourceBill, transaction.date);
          if (billDeleted && relatedPayments.isNotEmpty) {
            await _deleteBillOccurrencePayments(
              sourceBill,
              transaction.date,
              showNoPaymentsMessage: false,
            );
          }
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
          content: Text('Are you sure you want to delete "${transaction.description}"?'),
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
              final effect = transaction.type == TransactionType.income ? transaction.amount : -transaction.amount;
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
      // Open pay bill screen
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => PayBillScreen(
            bill: sourceBill,
            occurrenceDate: transaction.date,
          ),
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

  Future<void> _handleDuplicate(Transaction transaction, Bill? sourceBill) async {
    if (sourceBill != null) {
      // Open add bill screen with pre-filled information from the source bill
      // Create a template bill with the same properties but use occurrence date as due date
      final billTemplate = Bill(
        amount: sourceBill.amount,
        description: sourceBill.description,
        dueDate: transaction.date, // Use the occurrence date as the new due date
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
          builder: (context) => AddBillScreen(existingBill: billTemplate, isDuplicate: true),
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
        MaterialPageRoute(
          builder: (context) => const AddTransactionScreen(),
        ),
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
      decoration: BoxDecoration(
        color: category.color,
        shape: BoxShape.circle,
      ),
    );
  }
}
