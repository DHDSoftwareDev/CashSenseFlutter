
// ignore_for_file: annotate_overrides, valid_regexps, unnecessary_brace_in_string_interps
// ignore_for_file: no_leading_underscores_for_local_identifiers, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:table_calendar/table_calendar.dart';
import '../widgets/banner_ad_widget.dart';
import '../utils/root_scaffold.dart';
import '../services/database_service.dart';
import '../models/transaction.dart';
import '../models/bill.dart';
import '../models/category.dart';
import '../theme/app_theme.dart';
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
  // Duplicate helper removed — use the top-level _buildCategoryIconOrEmoji defined earlier.
  @override
  void initState() {
    super.initState();
    DatabaseService.categoriesVersion.addListener(_onCategoriesChanged);
    DatabaseService.payeesVersion.addListener(_onPayeesChanged);
    
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

  void _onPayeesChanged() {
    if (!mounted) return;
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
    var idx = _searchResults.indexWhere(
      (r) {
        final d = r['date'] as DateTime;
        final normalized = DateTime(d.year, d.month, d.day);
        return !normalized.isBefore(todayStart);
      },
    );

    // If there are no upcoming results, start near the most recent past result.
    if (idx < 0) idx = _searchResults.length - 1;
    _searchInitialIndex = idx;
  }

  void _showSearchDropdown() {
    // Remove existing overlay if present to rebuild with updated results
    if (_searchDropdownOverlay != null) {
      _removeSearchDropdown();
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

  void dispose() {
  _searchController.dispose();
  _searchFocusNode.dispose();
  _searchResultsScrollController.dispose();
  DatabaseService.categoriesVersion.removeListener(_onCategoriesChanged);
  DatabaseService.payeesVersion.removeListener(_onPayeesChanged);
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
  String _searchQuery = '';
  final List<Map<String, dynamic>> _searchResults = [];

  // Search bills by description, payee name, or notes
  void _performSearch(String query) {
    setState(() {
      _searchQuery = query.toLowerCase().trim();
      _searchResults.clear();
      if (_searchQuery.isEmpty) {
        _removeSearchDropdown();
        return;
      }
      final allBills = DatabaseService.getAllBills();
      final allPayees = DatabaseService.getAllPayees();
      for (final bill in allBills) {
        String billDescription = bill.description ?? '';
        String payeeName = '';
        if (bill.payeeId != null) {
          final payee = allPayees.firstWhere(
            (p) => p['id'] == bill.payeeId,
            orElse: () => <String, dynamic>{},
          );
          if (payee.containsKey('name')) {
            payeeName = payee['name'] as String;
          }
        }
        final searchText = '$billDescription $payeeName'.toLowerCase();
        if (searchText.contains(_searchQuery)) {
          final now = DateTime.now();
          final startDate = DateTime(now.year - 1, now.month, now.day);
          final endDate = DateTime(now.year + 1, now.month, now.day);
          final occurrences = DatabaseService.getBillOccurrencesBetween(startDate, endDate)
              .where((occ) => (occ['bill'] as Bill).id == bill.id)
              .toList();
          for (final occ in occurrences) {
            _searchResults.add({
              'bill': bill,
              'date': occ['date'] as DateTime,
              'description': payeeName.isNotEmpty ? payeeName : billDescription,
            });
          }
        }
      }
      _searchResults.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
      _positionSearchResultsAtToday();
      if (_searchResults.isNotEmpty && _searchFocusNode.hasFocus) {
        _showSearchDropdown();
      } else {
        _removeSearchDropdown();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
  return Scaffold(
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
                              _searchFocusNode.unfocus();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    isDense: true,
                  ),
                  onChanged: _performSearch,
                  onTap: () {
                    if (_searchQuery.isNotEmpty && _searchResults.isNotEmpty) {
                      _showSearchDropdown();
                    }
                  },
                  onEditingComplete: _removeSearchDropdown,
                  onSubmitted: (_) => _removeSearchDropdown(),
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
                // Return a non-empty list when we have transactions on this day so the calendar considers it an 'event' day.
                final start = DateTime(day.year, day.month, day.day);
                final end = start.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
                final hiddenIds = DatabaseService.getHiddenTransactionIds().toSet();
                final txs = DatabaseService.getTransactionsByDateRange(start, end)
                    .where((t) {
                      if (hiddenIds.contains(t.id)) return false;
                      if (t.note != null && t.note!.contains('__hide_from_calendar__')) return false;

                      // 🚫 Hide all bill-payment transactions from the calendar
                      if (t.billId != null && t.billId!.isNotEmpty) return false;

                      // Exclude all transfers (manual or bill) from calendar dashboard
                      final isTransfer =
                        (t.note != null && (t.note!.contains('__transfer_manual__') || t.note!.contains('__transfer_bill__')))
                        || t.categoryId.isEmpty
                        || t.description.toLowerCase().contains('transfer')
                        || (t.note != null && t.note!.toLowerCase().contains('transfer'));

                      if (isTransfer) return false;

                      return true;
                    })
                    .toList();
                var billOcc = DatabaseService.getBillOccurrencesBetween(start, end);
                
                // Apply search filter if search query is not empty
                if (_searchQuery.isNotEmpty) {
                  final allPayees = DatabaseService.getAllPayees();
                  billOcc = billOcc.where((occ) {
                    final bill = occ['bill'] as Bill;
                    String billDescription = bill.description ?? '';
                    String payeeName = '';
                    
                    if (bill.payeeId != null) {
                      final payee = allPayees.firstWhere(
                        (p) => p['id'] == bill.payeeId,
                        orElse: () => <String, dynamic>{},
                      );
                      if (payee.containsKey('name')) {
                        payeeName = payee['name'] as String;
                      }
                    }
                    
                    final searchText = '$billDescription $payeeName'.toLowerCase();
                    return searchText.contains(_searchQuery);
                  }).toList();
                }
                
                // For each bill occurrence, check if paid in full (sum of payments >= bill.amount)
                final List<Map<String, dynamic>> updatedBillOcc = [];
                for (final occ in billOcc) {
                  final bill = occ['bill'] as Bill;
                  final occDate = occ['date'] as DateTime;
                  // Get all transactions for this bill occurrence. Include
                  // transactions whose description references the occurrence
                  // date so payments made on a different date still count.
                  final occDateStr = DateFormat('MM/dd/yyyy').format(occDate);
                  final payments = DatabaseService.getAllTransactions()
                      .where((tx) => tx.billId == bill.id && (
                        (tx.occurrenceDate != null
                          ? (tx.occurrenceDate!.year == occDate.year && tx.occurrenceDate!.month == occDate.month && tx.occurrenceDate!.day == occDate.day)
                          : ((tx.date.year == occDate.year && tx.date.month == occDate.month && tx.date.day == occDate.day) || tx.description.contains(occDateStr))
                        )
                      ))
                      .toList();
                  final totalPaid = payments.fold<double>(0.0, (sum, tx) => sum + tx.amount);
                  // Mark as paid if totalPaid >= bill.amount, even if paid in installments
                  // Use tolerance of 0.01 to handle floating-point precision issues
                  final isPaid = totalPaid >= (bill.amount - 0.01);
                  updatedBillOcc.add({
                    'bill': bill,
                    'date': occDate,
                    'isPaid': isPaid,
                  });
                }
                return [...txs, ...updatedBillOcc];
              },
              calendarBuilders: CalendarBuilders(
                defaultBuilder: (context, day, focusedDay) {
                  // Color the date if a bill (including transfer bills) is present
                  var billOcc = DatabaseService.getBillOccurrencesBetween(
                        DateTime(day.year, day.month, day.day),
                        DateTime(day.year, day.month, day.day).add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1)));
                  
                  // Apply search filter if search query is not empty
                  if (_searchQuery.isNotEmpty) {
                    final allPayees = DatabaseService.getAllPayees();
                    billOcc = billOcc.where((occ) {
                      final bill = occ['bill'] as Bill;
                      String billDescription = bill.description ?? '';
                      String payeeName = '';
                      
                      if (bill.payeeId != null) {
                        final payee = allPayees.firstWhere(
                          (p) => p['id'] == bill.payeeId,
                          orElse: () => <String, dynamic>{},
                        );
                        if (payee.containsKey('name')) {
                          payeeName = payee['name'] as String;
                        }
                      }
                      
                      final searchText = '$billDescription $payeeName'.toLowerCase();
                      return searchText.contains(_searchQuery);
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
                        DateTime(day.year, day.month, day.day).add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1)));
                  
                  // Apply search filter if search query is not empty
                  if (_searchQuery.isNotEmpty) {
                    final allPayees = DatabaseService.getAllPayees();
                    billOcc = billOcc.where((occ) {
                      final bill = occ['bill'] as Bill;
                      String billDescription = bill.description ?? '';
                      String payeeName = '';
                      
                      if (bill.payeeId != null) {
                        final payee = allPayees.firstWhere(
                          (p) => p['id'] == bill.payeeId,
                          orElse: () => <String, dynamic>{},
                        );
                        if (payee.containsKey('name')) {
                          payeeName = payee['name'] as String;
                        }
                      }
                      
                      final searchText = '$billDescription $payeeName'.toLowerCase();
                      return searchText.contains(_searchQuery);
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

  PaymentStatus? _inferBillStatusFromMetadata(Bill bill) {
    if (bill.paymentStatus != null) return bill.paymentStatus;
    if (bill.isPaid) return PaymentStatus.paid;
    final text = (bill.description ?? '').toLowerCase();
    if (text.contains('unpaid') || text.contains('due') || text.contains('pending')) return PaymentStatus.unpaid;
    if (text.contains('partial') || text.contains('partially')) return PaymentStatus.partial;
    if (text.contains('paid') || text.contains('settled') || text.contains('cleared')) return PaymentStatus.paid;
    return null;
  }

  PaymentStatus _finalizeBillStatus(Bill bill, double totalPaid) {
    if (totalPaid <= 0) {
      return _inferBillStatusFromMetadata(bill) ?? PaymentStatus.unpaid;
    }
    if (totalPaid >= (bill.amount - 0.01)) {
      return PaymentStatus.paid;
    }
    return PaymentStatus.partial;
  }

  PaymentStatus _getOccurrencePaymentStatus(Bill bill, DateTime occDate) {
    final occStatus = DatabaseService.getBillOccurrenceStatus(bill.id, occDate);
    if (occStatus != null) {
      return occStatus['paymentStatus'] as PaymentStatus? ??
          ((occStatus['isPaid'] as bool? ?? false)
              ? PaymentStatus.paid
              : PaymentStatus.unpaid);
    }

    final occDateStr = DateFormat('MM/dd/yyyy').format(occDate);
    final payments = DatabaseService.getAllTransactions()
        .where((tx) =>
            tx.billId == bill.id &&
            ((tx.occurrenceDate != null)
                ? (tx.occurrenceDate!.year == occDate.year &&
                    tx.occurrenceDate!.month == occDate.month &&
                    tx.occurrenceDate!.day == occDate.day)
                : ((tx.date.year == occDate.year &&
                        tx.date.month == occDate.month &&
                        tx.date.day == occDate.day) ||
                    tx.description.contains(occDateStr))))
        .toList();

    final totalPaid = _computeSignedTotalPaid(bill, payments);
    return _finalizeBillStatus(bill, totalPaid);
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
      },
      selectedColor: theme.colorScheme.primary.withAlpha((0.18 * 255).round()),
      checkmarkColor: theme.colorScheme.primary,
      side: BorderSide(color: theme.colorScheme.outline),
    );
  }

  // _buildStatCard removed because quick stats are no longer shown on the dashboard.

  

  Widget _buildRecentTransactionsCard() {
    // Retrieve and apply filters
    final allTransactions = DatabaseService.getAllTransactions();

    List<Transaction> filtered = allTransactions;

    // (Today filter removed — controlled via calendar header's Today button)

    // Helper to identify manual payments from Pay Bill or Add Transaction screens
    bool _isManualPayment(Transaction tx) {
      // Any transaction with a billId is a bill payment and should be hidden
      if (tx.billId != null && tx.billId!.isNotEmpty) return true;
      // If description starts with 'Payment for' and note contains 'account:' it's likely from Pay Bill
      if (tx.description.startsWith('Payment for') && (tx.note?.contains('account:') ?? false)) return true;
      // Transactions created via Add Transaction screen are now tracked by id in
      // the DatabaseService hidden list. Fall back to the legacy note marker if
      // present to maintain behavior for older records.
      final hiddenIds = DatabaseService.getHiddenTransactionIds().toSet();
      if (hiddenIds.contains(tx.id)) return true;
      if (tx.note != null && tx.note!.contains('__hide_from_calendar__')) return true;
      return false;
    }

    // Helper to check if a bill matches the search query
    bool _billMatchesSearch(Bill bill) {
      if (_searchQuery.isEmpty) return true;
      
      String billDescription = bill.description ?? '';
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

    // Helper to check if a transaction matches the search query
    bool _transactionMatchesSearch(Transaction tx) {
      if (_searchQuery.isEmpty) return true;
      
      final allPayees = DatabaseService.getAllPayees();
      
      String txDescription = tx.description.toLowerCase();
      String payeeName = '';
      String payerName = '';
      String note = (tx.note ?? '').toLowerCase();
      
      // Get payee name if available
      if (tx.payeeId != null) {
        final payee = allPayees.firstWhere(
          (p) => p['id'] == tx.payeeId,
          orElse: () => <String, dynamic>{},
        );
        if (payee.containsKey('name')) {
          payeeName = (payee['name'] as String).toLowerCase();
        }
      }
      
      // Get payer name if available (payers are also stored in the payees list)
      if (tx.payerId != null) {
        final payer = allPayees.firstWhere(
          (p) => p['id'] == tx.payerId,
          orElse: () => <String, dynamic>{},
        );
        if (payer.containsKey('name')) {
          payerName = (payer['name'] as String).toLowerCase();
        }
      }
      
      // Check if query matches description, payee, payer, or note
      final searchText = '$txDescription $payeeName $payerName $note';
      return searchText.contains(_searchQuery);
    }

    List<TransactionDisplayItem> recentTransactions;
    if (_selectedDay != null) {
      final startOfSelected = DateTime(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day);
      final endOfSelected = startOfSelected.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
      // Get transactions for the selected date
      var txList = DatabaseService.getTransactionsByDateRange(startOfSelected, endOfSelected)
        .where((tx) => !_isManualPayment(tx))
        .toList();
      
      // Apply search filter to transactions
      if (_searchQuery.isNotEmpty) {
        txList = txList.where((tx) => _transactionMatchesSearch(tx)).toList();
      }
      
      // Add recurring bill occurrences as transaction placeholders
      var billOcc = DatabaseService.getBillOccurrencesBetween(startOfSelected, endOfSelected);
      
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
      // ...existing code for billOcc and sorting...
      // Filter out ALL transactions that are bill payments (have a billId set)
      // regardless of whether there's a matching bill occurrence on this day
      final filteredTxList = txList.where((tx) => tx.billId == null || tx.billId!.isEmpty).toList();
      recentTransactions = filteredTxList.map((tx) => TransactionDisplayItem(tx)).toList();
      for (final b in billOcc) {
        final bill = b['bill'] as Bill;
  final date = b['date'] as DateTime;
  // ...existing code for bill types...
        if (bill.type == BillType.transfer) {
          final fromAcc = bill.fromAccountId != null ? DatabaseService.getAccountById(bill.fromAccountId!) : null;
          final toAcc = bill.toAccountId != null ? DatabaseService.getAccountById(bill.toAccountId!) : null;
          final fromName = fromAcc?.name ?? 'From account';
          final toName = toAcc?.name ?? 'To account';
          final desc = bill.description ?? 'Transfer from $fromName to $toName';
          // Prefer including any bill notes in the placeholder note so the dashboard
          // shows the bill's notes under the amount. Format: 'account: Name — note'
          String? debitNote = 'account: $fromName';
          if ((bill.description ?? '').isNotEmpty) debitNote = 'account: $fromName — ${bill.description}';
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
          if ((bill.description ?? '').isNotEmpty) creditNote = 'account: $toName — ${bill.description}';
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
          String desc = bill.description ?? 'Bill';
          if (bill.payeeId != null) {
            final payees = DatabaseService.getAllPayees();
            final p = payees.firstWhere((p) => p['id'] == bill.payeeId, orElse: () => <String, dynamic>{});
            if (p.containsKey('name')) desc = p['name'] as String;
          }
          // Build note combining account and bill description so it displays under amount.
          String? noteWithAccount;
          final billNote = (bill.description ?? '').trim();
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
      recentTransactions.sort((a, b) => b.transaction.date.compareTo(a.transaction.date));
    } else {
      // Non-selected behavior: limit to 5 recent items (don't filter out future items).
      final dashboardTxs = filtered.where((tx) => !_isManualPayment(tx)).toList();
      recentTransactions = dashboardTxs.take(5).map((tx) => TransactionDisplayItem(tx)).toList();
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
                child: Text(_selectedDay != null ? 'No Bills' : 'No transactions'),
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
    final category = DatabaseService.getCategoryById(transaction.categoryId);
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
            final name = c?.name ?? (cid ?? 'Unknown');
            final amountStr = amt is num ? _currencyFormat.format(amt.toDouble()) : amt?.toString() ?? '';
            parts.add('$name ${amountStr}');
          }
        }
        categoryDisplay = parts.join(', ');
      } catch (_) {
        categoryDisplay = category?.name ?? 'Unknown';
      }
    } else {
      categoryDisplay = category?.name ?? 'Unknown';
    }
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
      final allTransactions = DatabaseService.getAllTransactions();
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
    
  // Try to extract account info if we embedded it in the note as 'account: NAME — rest'
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
      if (parts.length > 1) {
        plainNote = parts.sublist(1).join(' — ').trim();
        if (plainNote.isEmpty) plainNote = null;
      } else {
        // No trailing note content
        plainNote = null;
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
      child: InkWell(
        onTap: () async {
          final menuItems = <PopupMenuEntry<String>>[];
          if (paymentProgress != null && sourceBill != null) {
            if (isExpanded) {
              menuItems.add(
                const PopupMenuItem(
                  value: 'hide_progress',
                  child: Row(
                    children: [
                      Icon(Icons.close, size: 18),
                      SizedBox(width: 8),
                      Text('Hide payment progress'),
                    ],
                  ),
                ),
              );
            } else {
              menuItems.add(
                const PopupMenuItem(
                  value: 'show_progress',
                  child: Row(
                    children: [
                      Icon(Icons.show_chart, size: 18),
                      SizedBox(width: 8),
                      Text('Show payment progress'),
                    ],
                  ),
                ),
              );
            }
          }
          // Add common actions. Allow editing bills even if paid/partial to enable safe updates
          // that preserve payment history.
          final items = <PopupMenuEntry<String>>[];
          if (paymentProgress != null && sourceBill != null) {
            // Preserve the progress show/hide item that may have been added above
            // (they were added directly to menuItems earlier)
          }
          // Always allow editing bills from the calendar
          items.add(
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 18),
                  SizedBox(width: 8),
                  Text('Edit'),
                ],
              ),
            ),
          );
          items.addAll([
            const PopupMenuItem(
              value: 'duplicate',
              child: Row(
                children: [
                  Icon(Icons.copy, size: 18),
                  SizedBox(width: 8),
                  Text('Duplicate'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 18),
                  SizedBox(width: 8),
                  Text('Delete'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'pay',
              child: Row(
                children: [
                  Icon(Icons.payment, size: 18),
                  SizedBox(width: 8),
                  Text('Pay'),
                ],
              ),
            ),
          ]);
          menuItems.addAll(items);
          final value = await showMenu<String>(
            context: context,
            position: RelativeRect.fromLTRB(100, 400, 100, 100),
            items: menuItems,
            color: Theme.of(context).colorScheme.primary,
          );
          if (value == 'show_progress') {
            setState(() {
              _expandedTransactionIds.add(cardId);
            });
          } else if (value == 'hide_progress') {
            setState(() {
              _expandedTransactionIds.remove(cardId);
            });
          } else if (value == 'edit') {
            await _handleEdit(transaction, sourceBill);
          } else if (value == 'delete') {
            await _handleDelete(transaction, sourceBill);
          } else if (value == 'pay') {
            await _handlePay(transaction, sourceBill);
          } else if (value == 'duplicate') {
            await _handleDuplicate(transaction, sourceBill);
          }
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
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: (category != null) ? category.color.withAlpha(0x33) : Colors.grey.withAlpha(0x33),
                          child: safeCategoryIcon(),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(DateFormat('MM/dd/yyyy').format(transaction.date), style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 4),
                            Text(
                              transaction.description,
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
                    // Always show account name above the note, even if note is empty
                    if (transaction.note != null && transaction.note!.startsWith('account:')) ...[
                      SizedBox(
                        width: 160,
                        child: Text(
                          (() {
                            final after = transaction.note!.substring('account:'.length).trim();
                            final parts = after.split(RegExp(r'\s*[—–-]\s*'));
                            return parts.isNotEmpty ? parts.first : '';
                          })(),
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
                    SizedBox(
                      width: 160,
                      child: Text(
                        plainNote ?? '',
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
                        } else {
                          // Treat partial as unpaid in the dashboard list until fully paid.
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
  }

  Future<void> _handleEdit(Transaction transaction, Bill? sourceBill) async {
    if (sourceBill != null && sourceBill.recurrence != Recurrence.none) {
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

            // If there is a next occurrence and the original had an end date beyond it (or no end), recreate the future series
            if (nextOccurrenceDate != null && (sourceBill.recurrenceEndDate == null || nextOccurrenceDate.isBefore(sourceBill.recurrenceEndDate!) || nextOccurrenceDate.isAtSameMomentAs(sourceBill.recurrenceEndDate!))) {
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
              // If the AddBillScreen returned a specific occurrence bill id, migrate
              // payments for this occurrence to that bill so history remains visible.
              try {
                final allTx = DatabaseService.getAllTransactions();
                final occDateStr = DateFormat('MM/dd/yyyy').format(occurrenceDate);
                final migrated = allTx.where((tx) =>
                  tx.billId == sourceBill.id && (
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Occurrence updated'),
                  backgroundColor: Colors.blueGrey[400],
                ),
              );
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

            // If a new bill id was returned, migrate transactions that belong
            // to this original bill but are for occurrences on/after the
            // occurrenceDate to the new bill so they reflect the edited
            // future series. Leave any past transactions untouched.
            if (newBillId != null) {
              try {
                final allTx = DatabaseService.getAllTransactions();
                final occDateStr = DateFormat('MM/dd/yyyy').format(occurrenceDate);
                final toMigrate = allTx.where((tx) {
                  if (tx.billId != sourceBill.id) return false;
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Future occurrences updated'),
                  backgroundColor: Colors.blueGrey[400],
                ),
              );
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

  Future<void> _handleDelete(Transaction transaction, Bill? sourceBill) async {
    if (sourceBill != null && sourceBill.recurrence != Recurrence.none) {
      // For recurring bills, show options to delete this occurrence or all occurrences
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Recurring Bill'),
          content: const Text('This is a recurring bill. What would you like to delete?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'this'),
              child: const Text('Only This Occurrence'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'all'),
              child: const Text('All Future Occurrences', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (result == 'this') {
        // Delete only this occurrence by ending the current bill before this date
        // and creating a new bill that starts after this occurrence
        try {
          final occurrenceDate = transaction.date;
          final dayBefore = occurrenceDate.subtract(const Duration(days: 1));
          
          // Calculate the next occurrence date based on recurrence type (handles monthly custom days)
          final DateTime? nextOccurrenceDate = _computeNextOccurrenceDate(sourceBill, occurrenceDate);
          
          // Only create a new bill if there's a next occurrence and it's before the original end date (if any)
          if (nextOccurrenceDate != null && 
              (sourceBill.recurrenceEndDate == null || nextOccurrenceDate.isBefore(sourceBill.recurrenceEndDate!) || 
               nextOccurrenceDate.isAtSameMomentAs(sourceBill.recurrenceEndDate!))) {
            
            // Update the current bill to end before this occurrence
            final updatedBill = sourceBill.copyWith(
              recurrenceEndDate: dayBefore,
            );
            await DatabaseService.updateBill(updatedBill);
            
            // Create a new bill starting from the next occurrence
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
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('This occurrence removed'),
                  backgroundColor: Colors.blueGrey[400],
                ),
              );
            }
          } else {
            // This is the last occurrence, just end the bill
            final updatedBill = sourceBill.copyWith(
              recurrenceEndDate: dayBefore,
            );
            await DatabaseService.updateBill(updatedBill);
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Last occurrence removed'),
                  backgroundColor: Colors.blueGrey[400],
                ),
              );
            }
          }
          
          setState(() {}); // Refresh the list
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error removing occurrence: $e'),
                backgroundColor: Colors.blueGrey[400],
              ),
            );
          }
        }
      } else if (result == 'all') {
        // End the series before this occurrence so past occurrences remain and this+future are removed
        try {
          final occurrenceDate = transaction.date;
          final dayBefore = occurrenceDate.subtract(const Duration(days: 1));

          final updatedBill = sourceBill.copyWith(recurrenceEndDate: dayBefore);
          await DatabaseService.updateBill(updatedBill);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('This and all future occurrences removed'),
                backgroundColor: Colors.blueGrey[400],
              ),
            );
          }
          setState(() {}); // Refresh the list
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error removing occurrences: $e'),
                backgroundColor: Colors.blueGrey[400],
              ),
            );
          }
        }
      }
    } else {
      // For non-recurring bills, show simple delete confirmation
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete'),
          content: Text(sourceBill != null 
            ? 'Delete this bill?'
            : 'Delete this transaction?'),
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
          if (sourceBill != null) {
            // Delete the bill
            await DatabaseService.deleteBill(sourceBill.id);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Bill deleted'),
                  backgroundColor: Colors.blueGrey[400],
                ),
              );
            }
          } else {
            // Delete the transaction
            await DatabaseService.deleteTransaction(transaction.id);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Transaction deleted'),
                  backgroundColor: Colors.grey[400],
                ),
              );
            }
          }
          setState(() {}); // Refresh the list
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
    final codePointStr = category.iconCodePoint;
    final codePoint = int.tryParse(codePointStr);
    if (codePoint != null && codePoint > 0 && codePoint < 0x10FFFF) {
      return Icon(category.icon, color: category.color, size: 18);
    }
    if (codePointStr.isNotEmpty) {
      return Text(
        codePointStr,
        style: TextStyle(fontSize: 24, color: category.color),
        textAlign: TextAlign.center,
      );
    }
    return Icon(Icons.help, color: category.color, size: 18);
  }
}
