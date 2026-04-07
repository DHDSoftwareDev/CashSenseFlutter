// ignore_for_file: deprecated_member_use, unused_element, use_build_context_synchronously, dead_code, unnecessary_brace_in_string_interps

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'dart:convert';
import '../services/database_service.dart';
import '../services/lookups_state.dart';
import '../models/transaction.dart';
import '../theme/app_theme.dart';
import 'add_transaction_screen.dart';
import '../utils/root_scaffold.dart';

class TransactionsScreen extends StatefulWidget {
  final String? accountId;

  const TransactionsScreen({super.key, this.accountId});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

enum _TransferClearChoice { bothSides, oneSide }

class _TransactionsScreenState extends State<TransactionsScreen> {
  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: '\$');
  List<Transaction> _transactions = [];
  String _selectedFilter = 'All';
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  String? _accountName;
  bool _showAvailableBalance = false; // Toggle between current and available balance
  final Set<String> _expandedMonths = {}; // Track which month groups are expanded
  bool _showCleared = true; // Toggle for showing/hiding cleared transactions
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // Restore saved filter selection
    final savedFilter = DatabaseService.getSetting<String>('transactionsFilter', 'All');
    if (savedFilter != null && savedFilter.isNotEmpty) {
      _selectedFilter = savedFilter;
    }
    // Restore hide/show cleared preference
    _showCleared = DatabaseService.getSetting<bool>('transactionsShowCleared', true) ?? true;
    _loadTransactions();
    _runLegacyCalendarHideMigrationIfNeeded();
    DatabaseService.transactionsVersion.addListener(_onTransactionsChanged);
    DatabaseService.accountsVersion.addListener(_onAccountsChanged);
    DatabaseService.categoriesVersion.addListener(_onCategoriesChanged);
  }

  Future<void> _runLegacyCalendarHideMigrationIfNeeded() async {
    if (widget.accountId == null || widget.accountId!.isEmpty) return;
    try {
      final updated = await DatabaseService.migrateLegacyAccountTransactionsHiddenFromCalendar();
      final accountUpdated = await DatabaseService.hideTransactionsForAccountFromDashboard(widget.accountId!);
      if (updated > 0 && mounted) {
        _loadTransactions();
      } else if (accountUpdated > 0 && mounted) {
        _loadTransactions();
      }
    } catch (_) {
      // Non-blocking migration: ignore failures and keep screen usable.
    }
  }

  void _onCategoriesChanged() {
    if (!mounted) return;
    setState(() {}); // Triggers rebuild to update category names/colors/icons
  }

  void _onTransactionsChanged() {
    if (!mounted) return;
    _loadTransactions();
  }

  @override
  void didUpdateWidget(covariant TransactionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the accountId provided to this screen changes (for example when the
    // root navigation replaces the TransactionsScreen instance), reload so
    // the UI reflects the selected account name and filtered transactions.
    if (oldWidget.accountId != widget.accountId) {
      _loadTransactions();
    }
  }

  bool _isTransferTransaction(Transaction transaction) {
    final note = (transaction.note ?? '').trim().toLowerCase();
    final description = transaction.description.trim().toLowerCase();
    return note.startsWith('__transfer_manual__') ||
        note.startsWith('__transfer_bill__') ||
        description.startsWith('transfer from ');
  }

  Transaction? _findLinkedTransferTransaction(Transaction transaction) {
    final allTransactions = DatabaseService.getAllTransactions();
    final note = transaction.note ?? '';
    final pairMatch = RegExp(r'pair:([A-Za-z0-9\-]+)', caseSensitive: false).firstMatch(note);
    if (pairMatch != null) {
      final linkedId = pairMatch.group(1);
      if (linkedId != null && linkedId.isNotEmpty) {
        try {
          return allTransactions.firstWhere((candidate) => candidate.id == linkedId);
        } catch (_) {}
      }
    }

    try {
      return allTransactions.firstWhere(
        (candidate) =>
            candidate.id != transaction.id &&
            candidate.note != null &&
            (candidate.note!.contains(transaction.id) ||
                (transaction.note != null && transaction.note!.contains(candidate.id))),
      );
    } catch (_) {}

    final candidates = allTransactions.where((candidate) {
      if (candidate.id == transaction.id) return false;
      final sameAmount = candidate.amount == transaction.amount;
      final sameDate = candidate.date.year == transaction.date.year &&
          candidate.date.month == transaction.date.month &&
          candidate.date.day == transaction.date.day;
      final sameCategory = candidate.categoryId == transaction.categoryId;
      final differentAccount = candidate.accountId != transaction.accountId;
      return sameAmount && sameDate && sameCategory && differentAccount;
    }).toList();

    if (candidates.isEmpty) return null;
    return candidates.first;
  }

  Future<void> _reverseAccountBalanceForDeletedTransaction(Transaction transaction) async {
    final accId = transaction.accountId;
    if (accId == null) return;

    final acc = DatabaseService.getAccountById(accId);
    if (acc == null) return;

    final effect = transaction.type == TransactionType.income ? transaction.amount : -transaction.amount;
    final updatedAcc = acc.copyWith(balance: acc.balance - effect);
    await DatabaseService.updateAccount(updatedAcc);
  }

  Future<void> _deleteTransferTransaction(Transaction transaction, {required bool deleteBothSides}) async {
    try {
      final linked = deleteBothSides ? _findLinkedTransferTransaction(transaction) : null;

      await _reverseAccountBalanceForDeletedTransaction(transaction);
      if (linked != null) {
        await _reverseAccountBalanceForDeletedTransaction(linked);
      }

      if (linked != null) {
        await DatabaseService.deleteTransaction(linked.id);
      }
      await DatabaseService.deleteTransaction(transaction.id);

      if (!mounted) return;
      _loadTransactions();
      ScaffoldMessenger.of(context).clearSnackBars();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting transfer: $e'),
          backgroundColor: Colors.blueGrey[400],
        ),
      );
    }
  }

  Future<_TransferClearChoice?> _askTransferClearChoice({required bool newCleared}) async {
    final actionLabel = newCleared ? 'cleared' : 'uncleared';
    return showDialog<_TransferClearChoice>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Apply status to transfer?'),
          content: Text('Do you want to mark both sides of this transfer as $actionLabel?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(_TransferClearChoice.oneSide),
              child: const Text('One Side'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(_TransferClearChoice.bothSides),
              child: const Text('Both Sides'),
            ),
          ],
        );
      },
    );
  }
  
    List<Transaction> get _searchResults {
      final q = _searchQuery.trim().toLowerCase();
      if (q.isEmpty) return <Transaction>[];
      // Base set: if viewing a specific account, limit to that account's transactions
      final base = (widget.accountId != null && widget.accountId!.isNotEmpty)
          ? _transactions.where((t) => t.accountId == widget.accountId).toList()
          : List<Transaction>.from(_transactions);
      final results = base.where((t) {
        final desc = t.description.toLowerCase();
        if (desc.contains(q)) return true;
        if (t.note != null && t.note!.toLowerCase().contains(q)) return true;
        final cat = DatabaseService.getCategoryById(t.categoryId);
        if (cat != null && cat.name.toLowerCase().contains(q)) return true;
        // match amount strings (simple)
        if (t.amount.toString().contains(q)) return true;
        return false;
      }).toList();
      results.sort((a, b) {
        final cmp = b.date.compareTo(a.date);
        if (cmp != 0) return cmp;
        final createdCmp = b.createdAt.compareTo(a.createdAt);
        if (createdCmp != 0) return createdCmp;
        return b.id.compareTo(a.id);
      });
      return results;
    }

    Widget _buildSearchResults() {
      final results = _searchResults;
      if (results.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              'No matching transactions',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
            ),
          ),
        );
      }
      return ListView.builder(
        itemCount: results.length,
        itemBuilder: (context, i) {
          final tx = results[i];
          return _buildTransactionItem(tx);
        },
      );
    }

  void _loadTransactions() {
    setState(() {
      // If opened for a specific account, try to resolve its display name
      if (widget.accountId != null && widget.accountId!.isNotEmpty) {
        final acc = DatabaseService.getAccountById(widget.accountId!);
        _accountName = acc?.name;
      } else {
        _accountName = null;
      }
      final all = DatabaseService.getAllTransactions();
      if (widget.accountId != null && widget.accountId!.isNotEmpty) {
        // Filter transactions that belong to this account
        _transactions = all.where((t) => t.accountId == widget.accountId).toList();
      } else {
        _transactions = all;
      }
    });
  }

  @override
  void dispose() {
    DatabaseService.transactionsVersion.removeListener(_onTransactionsChanged);
    DatabaseService.accountsVersion.removeListener(_onAccountsChanged);
    DatabaseService.categoriesVersion.removeListener(_onCategoriesChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onAccountsChanged() {
    if (!mounted) return;
    // Reload transactions to refresh the account name and header balances
    _loadTransactions();
  }

  List<Transaction> get _filteredTransactions {
    List<Transaction> filtered;
    switch (_selectedFilter) {
      case 'Income':
        filtered = _transactions.where((t) => t.type == TransactionType.income).toList();
        break;
      case 'Expense':
        filtered = _transactions.where((t) => t.type == TransactionType.expense).toList();
        break;
      case 'Transfers':
        filtered = _transactions.where((t) {
          try {
            final cat = DatabaseService.getCategoryById(t.categoryId);
            if (cat != null && cat.name.toLowerCase() == 'transfer') return true;
          } catch (_) {}
          final desc = t.description.toLowerCase();
          if (desc.contains('transfer')) return true;
          if (t.note != null && t.note!.toLowerCase().contains('transfer')) return true;
          return false;
        }).toList();
        break;
      case 'Custom Dates':
        if (_customStartDate != null && _customEndDate != null) {
          filtered = _transactions.where((t) =>
            t.date.isAfter(_customStartDate!.subtract(const Duration(days: 1))) &&
            t.date.isBefore(_customEndDate!.add(const Duration(days: 1)))
          ).toList();
        } else {
          filtered = _transactions;
        }
        break;
      default:
        filtered = _transactions;
    }
    if (!_showCleared) {
      filtered = filtered.where((t) => t.cleared != true).toList();
    }
    // Sort newest to oldest (date descending, then createdAt descending, then id descending)
    filtered.sort((a, b) {
      final cmp = b.date.compareTo(a.date);
      if (cmp != 0) return cmp;
      final createdCmp = b.createdAt.compareTo(a.createdAt);
      if (createdCmp != 0) return createdCmp;
      return b.id.compareTo(a.id);
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
  final bool hasAnyTransactions = _transactions.isNotEmpty;
  return SlidableAutoCloseBehavior(
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Switch to accounts list root page (index 4)
            navigateToRootPage(4);
          },
        ),
  centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Transactions'),
            if (_accountName != null) ...[
              const SizedBox(height: 2),
              Text(_accountName!, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() {
                _selectedFilter = value;
                // Persist selection
                DatabaseService.setSetting('transactionsFilter', value);
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'All', child: Text('All')),
              const PopupMenuItem(value: 'Income', child: Text('Income')),
              const PopupMenuItem(value: 'Expense', child: Text('Expense')),
              const PopupMenuItem(value: 'Transfers', child: Text('Transfers')),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_selectedFilter),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addTransaction,
            tooltip: 'Add transaction',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _loadTransactions();
        },
        child: Column(
          children: [
            _buildBalanceHeader(),
            // Search bar under the balance header. When a search query is entered
            // we show a flat list of matching transactions (includes cleared),
            // otherwise we show the normal grouped transactions list which
            // respects the Show/Hide Cleared toggle.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search',
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
              ),
            ),
            Expanded(
              child: _searchQuery.isNotEmpty
                  ? _buildSearchResults()
                  : (hasAnyTransactions ? _buildTransactionsList(showHeader: false) : _buildEmptyState()),
            ),
          ],
        ),
      ),
      // FloatingActionButton removed; add button is now in the AppBar actions
    ),
  );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No transactions',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the + button to add your first transaction',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsList({bool showHeader = true}) {
    // Group by all transactions so month headers always show.
    final groupedTransactions = <String, List<Transaction>>{};
    for (final transaction in _transactions) {
      final monthKey = DateFormat('yyyy-MM').format(transaction.date);
      groupedTransactions[monthKey] ??= [];
      groupedTransactions[monthKey]!.add(transaction);
    }

    final sortedMonths = groupedTransactions.keys.toList()
      ..sort((a, b) => b.compareTo(a)); // Most recent first

    // Expand the most recent month by default
    if (_expandedMonths.isEmpty && sortedMonths.isNotEmpty) {
      _expandedMonths.add(sortedMonths.first);
    }
    // Precompute running balances for account view (oldest -> newest)
    Map<String, double>? runningMap;
    Map<String, double>? pendingRunningMap;
    if (widget.accountId != null && widget.accountId!.isNotEmpty) {
      // Always use all transactions for running balance, not just visible ones
      var allForBalance = List<Transaction>.from(_transactions);
      // Sort oldest to newest: date ASC, then createdAt ASC, then id ASC
      allForBalance.sort((a, b) {
        final cmp = a.date.compareTo(b.date);
        if (cmp != 0) return cmp;
        final createdCmp = a.createdAt.compareTo(b.createdAt);
        if (createdCmp != 0) return createdCmp;
        return a.id.compareTo(b.id);
      });

      final account = DatabaseService.getAccountById(widget.accountId!);
      if (account != null) {
        final initialBalance = DatabaseService.getInitialBalance(account.id);
        if (_showAvailableBalance) {
          final pendingExpenses = allForBalance.where((t) => t.type == TransactionType.expense).fold<double>(0.0, (s, t) => s + t.amount);
          final pendingIncome = allForBalance.where((t) => t.type == TransactionType.income).fold<double>(0.0, (s, t) => s + t.amount);
          final computedAvailable = account.balance - pendingExpenses + pendingIncome;
          final displayBase = account.availableBalance ?? computedAvailable;
          runningMap = <String, double>{};
          pendingRunningMap = <String, double>{};
          double cum = displayBase;
          double cumWithPending = displayBase;
          for (final tx in allForBalance) {
            final effect = (tx.type == TransactionType.income ? tx.amount : -tx.amount);
            if (tx.cleared == true) {
              cum += effect;
            }
            cumWithPending += effect;
            runningMap[tx.id] = cum;
            pendingRunningMap[tx.id] = cumWithPending;
          }
        } else {
          runningMap = <String, double>{};
          pendingRunningMap = <String, double>{};
          double cum = initialBalance;
          double cumWithPending = initialBalance;
          for (final tx in allForBalance) {
            final effect = (tx.type == TransactionType.income ? tx.amount : -tx.amount);
            if (tx.cleared == true) {
              cum += effect;
            }
            cumWithPending += effect;
            runningMap[tx.id] = cum;
            pendingRunningMap[tx.id] = cumWithPending;
          }
        }
      }
    }

    final showPendingSection = widget.accountId != null && widget.accountId!.isNotEmpty;
    final pendingTxs = showPendingSection
        ? _transactions.where((t) => t.cleared != true).toList()
        : <Transaction>[];
    pendingTxs.sort((a, b) {
      final cmp = b.date.compareTo(a.date);
      if (cmp != 0) return cmp;
      final createdCmp = b.createdAt.compareTo(a.createdAt);
      if (createdCmp != 0) return createdCmp;
      return b.id.compareTo(a.id);
    });
    final pendingTotal = pendingTxs.fold<double>(
      0.0,
      (sum, tx) => sum + (tx.type == TransactionType.income ? tx.amount : -tx.amount),
    );

    return ListView(
      children: [
        if (showPendingSection && pendingTxs.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Pending',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Card(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Pending',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Text(
                        '${pendingTxs.length} transaction${pendingTxs.length != 1 ? 's' : ''}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _currencyFormat.format(pendingTotal),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: pendingTotal >= 0 ? AppTheme.incomeGreen : AppTheme.expenseRed,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                for (var i = 0; i < pendingTxs.length; i++) ...[
                  _buildTransactionItem(pendingTxs[i], runningBalance: pendingRunningMap?[pendingTxs[i].id]),
                  if (i != pendingTxs.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
        ],
        for (final monthKey in sortedMonths) ...[
          () {
            List<Transaction> allGroupTxs = groupedTransactions[monthKey]!;
            final groupTxsForDisplay = showPendingSection
                ? allGroupTxs.where((t) => t.cleared == true).toList()
                : allGroupTxs;
            // Sort transactions within month by date (newest first), then createdAt DESC for same date (newest first)
            groupTxsForDisplay.sort((a, b) {
              final cmp = b.date.compareTo(a.date);
              if (cmp != 0) return cmp;
              final createdCmp = b.createdAt.compareTo(a.createdAt);
              if (createdCmp != 0) return createdCmp;
              return b.id.compareTo(a.id);
            });
            // Always build the month group, even if all transactions are cleared
            // Only show cleared transactions in the main list (pending are shown separately)
            var displayTxs = showPendingSection
                ? (_showCleared ? groupTxsForDisplay : <Transaction>[])
                : (_showCleared ? groupTxsForDisplay : groupTxsForDisplay.where((t) => t.cleared != true).toList());
            final parsedDate = DateTime.parse('$monthKey-01');
            // Always show the group, even if displayTxs is empty
            return _buildMonthGroup(
              monthKey,
              parsedDate,
              displayTxs,
              runningBalances: runningMap,
              allGroupTransactions: showPendingSection ? groupTxsForDisplay : allGroupTxs,
            );
          }(),
        ],
      ],
    );
    // Fallback in case no transactions exist (should not be reached, but required for non-nullable return)
    // This ensures the function always returns a Widget.
    return const SizedBox.shrink();
  }

  Widget _buildBalanceHeader() {
    // Only show balance header when viewing a specific account
    if (widget.accountId == null || widget.accountId!.isEmpty) {
      return const SizedBox.shrink();
    }
    
    final account = DatabaseService.getAccountById(widget.accountId!);
    if (account == null) {
      return const SizedBox.shrink();
    }
    
  // Compute the final running balance using the same visible transaction set
  // and starting base as the list computation so the header matches the
  // per-transaction running values (i.e., the cumulative balance after
  // applying all visible transactions).
  // Always include all transactions for running balance calculation, even if 'hide cleared' is selected
  final List<Transaction> allForHeader = _transactions.where((t) => t.accountId == account.id).toList();
  // Only filter for display, not for running balance
  // (visibleForHeader is not needed in this function)
  // Sort oldest -> newest to match running-balance iteration
  allForHeader.sort((a, b) {
    final cmp = a.date.compareTo(b.date);
    return cmp != 0 ? cmp : a.id.compareTo(b.id);
  });
  double finalCum;
  if (_showAvailableBalance) {
    final pendingExpenses = allForHeader.where((t) => t.type == TransactionType.expense).fold<double>(0.0, (s, t) => s + t.amount);
    final pendingIncome = allForHeader.where((t) => t.type == TransactionType.income).fold<double>(0.0, (s, t) => s + t.amount);
    final computedAvailable = account.balance - pendingExpenses + pendingIncome;
    double base = account.availableBalance ?? computedAvailable;
    finalCum = base;
    for (final tx in allForHeader) {
      final effect = (tx.type == TransactionType.income ? tx.amount : -tx.amount);
      finalCum += effect;
    }
  } else {
    final initialBalance = DatabaseService.getInitialBalance(account.id);
    finalCum = initialBalance;
    for (final tx in allForHeader) {
      final effect = (tx.type == TransactionType.income ? tx.amount : -tx.amount);
      finalCum += effect;
    }
  }
  final displayBalance = finalCum;
    final balanceLabel = _showAvailableBalance ? 'Available Balance' : 'Current Balance';
    
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      _showAvailableBalance = !_showAvailableBalance;
                    });
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        balanceLabel,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.swap_horiz,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _currencyFormat.format(displayBalance),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: displayBalance >= 0 ? AppTheme.incomeGreen : AppTheme.expenseRed,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          // Add clickable Show/Hide Cleared text on the right
          InkWell(
            onTap: () {
              setState(() {
                _showCleared = !_showCleared;
              });
              DatabaseService.setSetting('transactionsShowCleared', _showCleared);
            },
            child: Text(
              _showCleared ? 'Hide Cleared' : 'Show Cleared',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthGroup(String monthKey, DateTime date, List<Transaction> transactions, {Map<String, double>? runningBalances, List<Transaction>? allGroupTransactions}) {
  final monthName = DateFormat('MMMM yyyy').format(date); // Full month name and year
  final txsForHeader = allGroupTransactions ?? transactions;
  List<Widget> children = [];
  // Group all transactions in the group by date (descending)
  final allTxs = allGroupTransactions ?? transactions;
  final allDateGroups = <String, List<Transaction>>{};
  for (final tx in allTxs) {
    final dateStr = DateFormat('MM/dd/yyyy').format(tx.date);
    allDateGroups.putIfAbsent(dateStr, () => []).add(tx);
  }

  final sortedDates = allDateGroups.keys.toList()
    ..sort((a, b) => DateFormat('MM/dd/yyyy').parse(b).compareTo(DateFormat('MM/dd/yyyy').parse(a)));
  for (final dateStr in sortedDates) {
    final allTxsForDate = allDateGroups[dateStr]!;
    // Find the last transaction for this date (since list is newest first, it's the first in the group)
    final lastTx = allTxsForDate.first;
    final lastRunning = runningBalances != null ? runningBalances[lastTx.id] : null;
    // Add a divider before each date group except the first
    if (children.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Divider(
            thickness: 2,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.18),
            height: 18,
          ),
        ),
      );
    }
    // Now show only visible (uncleared) transactions for this date
    final visibleTxs = transactions.where((t) => DateFormat('MM/dd/yyyy').format(t.date) == dateStr).toList();
    children.add(
      Padding(
        padding: const EdgeInsets.only(left: 12, right: 12, bottom: 4, top: 4),
        child: Row(
          children: [
            // Left: date
            Text(
              dateStr,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            ),
            const Spacer(),
            // Right: running balance
            if (lastRunning != null)
              Text(
                _currencyFormat.format(lastRunning),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
    if (visibleTxs.isNotEmpty) {
      children.addAll(visibleTxs.map((transaction) => _buildTransactionItem(transaction, runningBalance: runningBalances != null ? runningBalances[transaction.id] : null)));
    }
  }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        maintainState: true,
        title: Row(
          children: [
            Expanded(
              child: Text(
                monthName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              // Show count and amount for all transactions in group, not just visible
              '${txsForHeader.length} transaction${txsForHeader.length != 1 ? 's' : ''}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        children: children.isNotEmpty
            ? children
            : const [],
      ),
    );
  }

  // Extract a normalized payee/payer name from a transaction description by
  // removing "Payment for" prefix and any trailing date pattern.
  String _extractPayeeName(String desc) {
    var name = desc.trim();
    if (name.toLowerCase().startsWith('payment for ')) {
      name = name.substring('payment for '.length).trim();
    }
    // Remove trailing date patterns like (MM/dd/yyyy) or MM/dd/yyyy
    final dateRegex = RegExp(r'[(\[]?\d{1,2}[/-]\d{1,2}[/-]\d{2,4}[)\]]?$');
    name = name.replaceAll(dateRegex, '').trim();
    return name;
  }

  String _extractPaymentForValue(String description) {
    final trimmed = description.trim();
    if (!trimmed.toLowerCase().startsWith('payment for ')) return '';
    return trimmed.substring('payment for '.length).trim();
  }

  Widget _buildTransactionItem(Transaction transaction, {double? runningBalance}) {
    final lookupsState = context.watch<LookupsState>();
    final normalizedCategoryId = transaction.categoryId.trim();
    final category = normalizedCategoryId.isEmpty
        ? null
        : DatabaseService.getCategoryById(normalizedCategoryId);
    final categoryText = (category?.name != null && category!.name.trim().isNotEmpty)
        ? category.name
        : lookupsState.categoryName(
            normalizedCategoryId,
            fallbackName: transaction.categoryName ?? 'Unknown Category',
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
            final cidRaw = s['categoryId']?.toString();
            final cid = cidRaw?.trim();
            final amt = s['amount'];
            final c = (cid != null && cid.isNotEmpty)
                ? DatabaseService.getCategoryById(cid)
                : null;
            final name = (c?.name != null && c!.name.trim().isNotEmpty)
                ? c.name
                : lookupsState.categoryName(
                    cid,
                    fallbackName: cid ?? 'Unknown',
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

    String paymentForDisplay = '';
    final rawPaymentFor = (transaction.paymentFor ?? '').trim();
    if (rawPaymentFor.isNotEmpty) {
      paymentForDisplay = rawPaymentFor;
    } else {
      paymentForDisplay = _extractPaymentForValue(transaction.description);
    }
    if (paymentForDisplay.isNotEmpty) {
      final cat = categoryText.trim();
      if (cat.isNotEmpty) {
        final lowerValue = paymentForDisplay.toLowerCase();
        final lowerCategorySuffix = ' ${cat.toLowerCase()}';
        if (lowerValue.endsWith(lowerCategorySuffix)) {
          paymentForDisplay = paymentForDisplay
              .substring(0, paymentForDisplay.length - lowerCategorySuffix.length)
              .trim();
        }
      }
    }
    
    // Calculate running balance if viewing a specific account and no
    // precomputed runningBalance was passed in. Compute from oldest -> newest
    // to match the account history progression.
    if (runningBalance == null && widget.accountId != null && widget.accountId!.isNotEmpty) {
      final account = DatabaseService.getAccountById(widget.accountId!);
      if (account != null) {
        final allForBalance = List<Transaction>.from(_transactions)
          ..sort((a, b) => a.date.compareTo(b.date));

        final initialBalance = DatabaseService.getInitialBalance(account.id);

        if (_showAvailableBalance) {
          final displayBase = account.availableBalance ?? DatabaseService.getComputedAvailableBalance(account.id);
          double cum = displayBase;
          for (final tx in allForBalance) {
            final effect = (tx.type == TransactionType.income ? tx.amount : -tx.amount);
            if (tx.cleared == true) {
              cum += effect;
            }
            if (tx.id == transaction.id) {
              runningBalance = cum;
              break;
            }
          }
        } else {
          double cum = initialBalance;
          for (final tx in allForBalance) {
            final effect = (tx.type == TransactionType.income ? tx.amount : -tx.amount);
            if (tx.cleared == true) {
              cum += effect;
            }
            if (tx.id == transaction.id) {
              runningBalance = cum;
              break;
            }
          }
        }
      }
    }
    
    Future<void> openEditTransaction() async {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AddTransactionScreen(
            existingTransaction: transaction,
            hideFromCalendarDashboard: true,
          ),
        ),
      );
      if (result == true || result is Transaction) _loadTransactions();
    }

    Future<void> duplicateTransaction() async {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AddTransactionScreen(
            prefillTransaction: transaction,
            isDuplicate: true,
            hideFromCalendarDashboard: true,
          ),
        ),
      );
      if (result == true) _loadTransactions();
    }

    Future<void> toggleClearStatus() async {
      final newCleared = !(transaction.cleared ?? false);
      Transaction? linked;
      var shouldApplyToBothSides = true;

      if (_isTransferTransaction(transaction)) {
        linked = _findLinkedTransferTransaction(transaction);

        if (linked != null) {
          final choice = await _askTransferClearChoice(newCleared: newCleared);
          if (choice == null) return;
          shouldApplyToBothSides = choice == _TransferClearChoice.bothSides;
        }
      }

      await DatabaseService.updateTransaction(transaction.copyWith(cleared: newCleared));

      if (shouldApplyToBothSides && linked != null && linked.cleared != newCleared) {
        await DatabaseService.updateTransaction(linked.copyWith(cleared: newCleared));
      }

      _loadTransactions();
    }

    final card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () async {
          await openEditTransaction();
        },
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                DateFormat('MM/dd/yy').format(transaction.date),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 4),
                              // Extract clean payee/payer name for payment transactions,
                              // removing "Payment for" prefix and trailing date
                              Builder(
                                builder: (context) {
                                  final isPayment = transaction.description.toLowerCase().startsWith('payment for ');
                                  final fallbackCounterparty =
                                      transaction.type == TransactionType.expense
                                          ? payeeText
                                          : payerText;
                                  var baseTitle = isPayment
                                      ? (fallbackCounterparty.isNotEmpty
                                          ? fallbackCounterparty
                                          : _extractPayeeName(transaction.description))
                                      : transaction.description;
                                  baseTitle = baseTitle.replaceFirst(
                                    RegExp(r'^\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\s+'),
                                    '',
                                  );
                                  final cat = categoryText.trim();
                                  if (cat.isNotEmpty && baseTitle.toLowerCase().endsWith(' ${cat.toLowerCase()}')) {
                                    baseTitle = baseTitle.substring(0, baseTitle.length - cat.length - 1).trim();
                                  }
                                  final displayTitle =
                                      (baseTitle.trim().isEmpty || baseTitle.trim().toLowerCase() == 'transaction')
                                          ? (fallbackCounterparty.isEmpty ? baseTitle : fallbackCounterparty)
                                          : baseTitle;
                                  return Text(
                                    displayTitle,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 4),
                              // Make the account/category name smaller. If transaction is split,
                              // show each category and allocated amount in-line.
                              Text(
                                categoryDisplay,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${transaction.type == TransactionType.income ? '+' : '-'}${_currencyFormat.format(transaction.amount)}',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: transaction.type == TransactionType.income
                                    ? AppTheme.incomeGreen
                                    : AppTheme.expenseRed,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            if (transaction.note != null && transaction.note!.trim().isNotEmpty) ...[
                          Builder(
                            builder: (ctx) {
                              String raw = transaction.note!;
                              String lower = raw.toLowerCase();
                              final isTransfer = lower.startsWith('__transfer_manual__') || lower.startsWith('__transfer_bill__');
                              // Only show note for transfers if user entered a note (not just marker)
                              if (isTransfer && (raw.trim() == '__transfer_manual__' || raw.trim() == '__transfer_bill__')) {
                                return const SizedBox.shrink();
                              }
                              // Remove transfer marker prefix if present
                              if (isTransfer) {
                                raw = raw.replaceFirst(RegExp(r'^__transfer_(manual|bill)__'), '').trim();
                                lower = raw.toLowerCase();
                              }
                              // Remove hide marker used for legacy dashboard filtering.
                              raw = raw.replaceAll(RegExp(r'__hide_from_calendar__', caseSensitive: false), '').trim();
                              lower = raw.toLowerCase();
                              // Remove account: prefix if present
                              if (lower.startsWith('account:')) {
                                final after = raw.substring('account:'.length).trim();
                                final parts = after.split(RegExp(r'\s*[—–-]\s*'));
                                raw = parts.length > 1 ? parts.sublist(1).join(' — ').trim() : '';
                              }
                              // Remove any leftover _transfer or _bill_ markers
                              raw = raw.replaceAll(RegExp(r'_transfer|_bill_', caseSensitive: false), '').trim();
                              // Remove any internal pair tokens added to link transfer sides (e.g. 'pair:<id>')
                              raw = raw.replaceAll(RegExp(r'pair:[A-Za-z0-9\-]+'), '').trim();
                              if (raw.isEmpty) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: SizedBox(
                                  width: 140,
                                  child: Text(
                                    raw,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                                    textAlign: TextAlign.right,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              );
                            },
                          ),
                            ],
                            const SizedBox(height: 4),
                            if (runningBalance != null) ...[
                              Text(
                                _currencyFormat.format(runningBalance),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey[600],
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (widget.accountId != null &&
                  widget.accountId!.isNotEmpty &&
                  paymentForDisplay.isNotEmpty &&
                  (transaction.billId?.trim().isNotEmpty ?? false)) ...[
                const SizedBox(height: 8),
                Text(
                  'Payment for $paymentForDisplay',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return Slidable(
      key: ValueKey('transaction_swipe_${transaction.id}'),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.50,
        children: [
          CustomSlidableAction(
            onPressed: (_) async => duplicateTransaction(),
            backgroundColor: Theme.of(context).colorScheme.primary,
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
          CustomSlidableAction(
            onPressed: (_) async => toggleClearStatus(),
            backgroundColor: Colors.blueGrey,
            foregroundColor: Colors.white,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  transaction.cleared == true ? Icons.undo : Icons.check_circle_outline,
                  color: Colors.white,
                ),
                const SizedBox(height: 4),
                Text(
                  transaction.cleared == true ? 'Mark Unclear' : 'Mark Cleared',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.1),
                ),
              ],
            ),
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.25,
        children: [
          CustomSlidableAction(
            onPressed: (_) => _deleteTransaction(transaction),
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
      child: card,
    );
  }

  void _addTransaction() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddTransactionScreen(
          initialAccountId: widget.accountId,
          hideFromCalendarDashboard: true,
        ),
      ),
    );
    if (result == true) {
      _loadTransactions();
    }
  }

  // Transaction details popup removed; actions now in menu

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  void _deleteTransaction(Transaction transaction) {
    final note = transaction.note ?? '';
    final isTransfer = note.toLowerCase().startsWith('__transfer_manual__') || note.toLowerCase().startsWith('__transfer_bill__');
    if (isTransfer) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Transfer'),
          content: Text('Do you want to delete just this side or both sides of the transfer?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final nav = Navigator.of(context);
                nav.pop();
                _deleteTransferTransaction(transaction, deleteBothSides: false);
              },
              child: const Text('Just this side', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () async {
                final nav = Navigator.of(context);
                nav.pop();
                _deleteTransferTransaction(transaction, deleteBothSides: true);
              },
              child: const Text('Both sides', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            transaction.billId != null && transaction.billId!.isNotEmpty
                ? 'Delete Bill Payment'
                : 'Delete Transaction',
          ),
          content: Text(
            transaction.billId != null && transaction.billId!.isNotEmpty
                ? 'Delete this payment? It will also be removed from the bill payment history and the bill status will be updated.'
                : 'Are you sure you want to delete "${transaction.description}"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final nav = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                nav.pop();
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
                await DatabaseService.deleteTransaction(transaction.id);
                if (!mounted) return;
                _loadTransactions();
                messenger.clearSnackBars();
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
    }
  }
}
