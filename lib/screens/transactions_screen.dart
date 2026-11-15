// ignore_for_file: unused_local_variable, deprecated_member_use, unused_element, use_build_context_synchronously, dead_code, unnecessary_brace_in_string_interps

import '../services/account_operations.dart';
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
import '../utils/account_ledger.dart';

class TransactionsScreen extends StatefulWidget {
  final String? accountId;

  const TransactionsScreen({super.key, this.accountId});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

enum _TransferClearChoice { bothSides, oneSide }

class _TransactionsScreenState extends State<TransactionsScreen> {
  final int _accountGeneration = AccountOperations.generation;
  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: '\$');
  List<Transaction> _transactions = [];
  String _selectedFilter = 'All';
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  String? _accountName;
  bool _showAvailableBalance =
      false; // Toggle between current and available balance
  final Set<String> _expandedMonths =
      {}; // Track which month groups are expanded
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  int _compareTransactionsForDisplay(Transaction a, Transaction b) {
    return AccountLedger.compareTransactions(b, a);
  }

  String _reorderGroupKey(Transaction transaction) {
    final date = DateFormat('yyyy-MM-dd').format(transaction.date);
    final status = transaction.cleared == true ? 'cleared' : 'pending';
    return '$date|$status';
  }

  String _reorderGroupLabel(String key) {
    final parts = key.split('|');
    final date = DateFormat('yyyy-MM-dd').parse(parts.first);
    final status = parts.length > 1 && parts[1] == 'cleared'
        ? 'Cleared'
        : 'Pending';
    return '${DateFormat.yMMMd().format(date)} · $status';
  }

  Future<void> _rearrangeTransactions() {
    return AccountOperations.bind(_accountGeneration, () async {
    final groups = <String, List<Transaction>>{};
    for (final transaction in _transactions) {
      final group = groups.putIfAbsent(
        _reorderGroupKey(transaction),
        () => <Transaction>[],
      );
      group.add(transaction);
    }
    groups.removeWhere((_, transactions) => transactions.length < 2);

    if (groups.isEmpty) {
      final colorScheme = Theme.of(context).colorScheme;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: colorScheme.inverseSurface,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            content: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    Icons.swap_vert_rounded,
                    color: colorScheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'You need at least two transactions on the same date to rearrange them.',
                    style: TextStyle(
                      color: colorScheme.onInverseSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      return;
    }

    for (final transactions in groups.values) {
      transactions.sort(_compareTransactionsForDisplay);
    }
    final groupKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    var selectedGroup = groupKeys.first;

    final reordered = await showDialog<Map<String, List<Transaction>>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final colorScheme = Theme.of(context).colorScheme;
          final selectedTransactions = groups[selectedGroup]!;

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 28,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 520,
                maxHeight: MediaQuery.sizeOf(context).height * 0.78,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 22, 16, 18),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer.withValues(
                                alpha: 0.60,
                              ),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(
                              Icons.swap_vert_rounded,
                              color: colorScheme.primary,
                              size: 25,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'Rearrange Transactions',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),

                    Divider(
                      height: 1,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.30),
                    ),

                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'DATE & STATUS',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.7,
                                  ),
                            ),
                            const SizedBox(height: 8),

                            DropdownButtonFormField<String>(
                              initialValue: selectedGroup,
                              isExpanded: true,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.45),
                                prefixIcon: const Icon(
                                  Icons.calendar_month_outlined,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 17,
                                ),
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
                                    color: colorScheme.primary,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              items: groupKeys
                                  .map(
                                    (key) => DropdownMenuItem<String>(
                                      value: key,
                                      child: Text(
                                        _reorderGroupLabel(key),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setDialogState(() => selectedGroup = value);
                              },
                            ),

                            const SizedBox(height: 18),

                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer.withValues(
                                  alpha: 0.28,
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.drag_indicator_rounded,
                                    color: colorScheme.primary,
                                    size: 21,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Drag transactions into the order you want displayed. '
                                      'Running balances will be recalculated when you save.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                            height: 1.4,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 18),

                            Text(
                              'TRANSACTIONS',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.7,
                                  ),
                            ),
                            const SizedBox(height: 8),

                            SizedBox(
                              height: selectedTransactions.length <= 3
                                  ? selectedTransactions.length * 84.0
                                  : 300,
                              child: ReorderableListView.builder(
                                buildDefaultDragHandles: false,
                                padding: EdgeInsets.zero,
                                itemCount: selectedTransactions.length,
                                onReorder: (oldIndex, newIndex) {
                                  setDialogState(() {
                                    if (newIndex > oldIndex) newIndex--;
                                    final moved = selectedTransactions.removeAt(
                                      oldIndex,
                                    );
                                    selectedTransactions.insert(
                                      newIndex,
                                      moved,
                                    );
                                  });
                                },
                                itemBuilder: (context, index) {
                                  final transaction =
                                      selectedTransactions[index];
                                  final signedAmount =
                                      transaction.type == TransactionType.income
                                      ? transaction.amount
                                      : -transaction.amount;

                                  return Container(
                                    key: ValueKey(transaction.id),
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      12,
                                      10,
                                      12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainerHighest
                                          .withValues(alpha: 0.38),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: colorScheme.outlineVariant
                                            .withValues(alpha: 0.28),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                transaction.description,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _currencyFormat.format(
                                                  signedAmount,
                                                ),
                                                style: TextStyle(
                                                  color: signedAmount >= 0
                                                      ? Colors.green
                                                      : colorScheme.error,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        ReorderableDragStartListener(
                                          index: index,
                                          child: Container(
                                            width: 42,
                                            height: 42,
                                            decoration: BoxDecoration(
                                              color: colorScheme
                                                  .primaryContainer
                                                  .withValues(alpha: 0.50),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Icon(
                                              Icons.drag_handle_rounded,
                                              color: colorScheme.primary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    Divider(
                      height: 1,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.30),
                    ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 50,
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(),
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 50,
                              child: FilledButton.icon(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(groups),
                                style: FilledButton.styleFrom(
                                  backgroundColor: colorScheme.primary,
                                  foregroundColor: colorScheme.onPrimary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: const Icon(Icons.check_rounded, size: 20),
                                label: const Text(
                                  'Save Order',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (reordered == null) return;

    try {
      for (final transactions in reordered.values) {
        for (var index = 0; index < transactions.length; index++) {
          final transaction = transactions[index];
          final nextSortOrder = transactions.length - index;
          if (transaction.sortOrder == nextSortOrder) continue;
          await DatabaseService.updateTransaction(
            transaction.copyWith(sortOrder: nextSortOrder),
          );
        }
      }
      if (!mounted) return;
      _loadTransactions();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Transaction order saved.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save transaction order: $error')),
      );
    }
      });
  }

  @override
  void initState() {
    super.initState();
    // Restore saved filter selection
    final savedFilter = DatabaseService.getSetting<String>(
      'transactionsFilter',
      'All',
    );
    if (savedFilter != null && savedFilter.isNotEmpty) {
      _selectedFilter = savedFilter;
    }
    _loadTransactions();
    _runLegacyCalendarHideMigrationIfNeeded();
    DatabaseService.transactionsVersion.addListener(_onTransactionsChanged);
    DatabaseService.accountsVersion.addListener(_onAccountsChanged);
    DatabaseService.categoriesVersion.addListener(_onCategoriesChanged);
  }

  Future<void> _runLegacyCalendarHideMigrationIfNeeded() {
    return AccountOperations.bind(_accountGeneration, () async {
    if (widget.accountId == null || widget.accountId!.isEmpty) return;
    try {
      final updated =
          await DatabaseService.migrateLegacyAccountTransactionsHiddenFromCalendar();
      final accountUpdated =
          await DatabaseService.hideTransactionsForAccountFromDashboard(
            widget.accountId!,
          );
      if (updated > 0 && mounted) {
        _loadTransactions();
      } else if (accountUpdated > 0 && mounted) {
        _loadTransactions();
      }
    } catch (_) {
      // Non-blocking migration: ignore failures and keep screen usable.
    }
      });
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
    final pairMatch = RegExp(
      r'pair:([A-Za-z0-9\-]+)',
      caseSensitive: false,
    ).firstMatch(note);
    if (pairMatch != null) {
      final linkedId = pairMatch.group(1);
      if (linkedId != null && linkedId.isNotEmpty) {
        try {
          return allTransactions.firstWhere(
            (candidate) => candidate.id == linkedId,
          );
        } catch (_) {}
      }
    }

    try {
      return allTransactions.firstWhere(
        (candidate) =>
            candidate.id != transaction.id &&
            candidate.note != null &&
            (candidate.note!.contains(transaction.id) ||
                (transaction.note != null &&
                    transaction.note!.contains(candidate.id))),
      );
    } catch (_) {}

    final candidates = allTransactions.where((candidate) {
      if (candidate.id == transaction.id) return false;
      final sameAmount = candidate.amount == transaction.amount;
      final sameDate =
          candidate.date.year == transaction.date.year &&
          candidate.date.month == transaction.date.month &&
          candidate.date.day == transaction.date.day;
      final sameCategory = candidate.categoryId == transaction.categoryId;
      final differentAccount = candidate.accountId != transaction.accountId;
      return sameAmount && sameDate && sameCategory && differentAccount;
    }).toList();

    if (candidates.isEmpty) return null;
    return candidates.first;
  }

  Future<void> _reverseAccountBalanceForDeletedTransaction(
    Transaction transaction,
  ) {
    return AccountOperations.bind(_accountGeneration, () async {
    final accId = transaction.accountId;
    if (accId == null) return;

    final acc = DatabaseService.getAccountById(accId);
    if (acc == null) return;

    final effect = transaction.type == TransactionType.income
        ? transaction.amount
        : -transaction.amount;
    final updatedAcc = acc.copyWith(balance: acc.balance - effect);
    await DatabaseService.updateAccount(updatedAcc);
      });
  }

  Future<void> _deleteTransferTransaction(
    Transaction transaction, {
    required bool deleteBothSides,
  }) {
    return AccountOperations.bind(_accountGeneration, () async {
    try {
      final linked = deleteBothSides
          ? _findLinkedTransferTransaction(transaction)
          : null;

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
      });
  }

  Future<_TransferClearChoice?> _askTransferClearChoice({
    required bool newCleared,
  }) {
    return AccountOperations.bind(_accountGeneration, () async {
    final actionLabel = newCleared ? 'cleared' : 'uncleared';

    return showDialog<_TransferClearChoice>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;

        return AlertDialog(
          backgroundColor: colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 24,
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          actionsPadding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  newCleared
                      ? Icons.check_circle_outline_rounded
                      : Icons.pending_outlined,
                  color: colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Update Transfer Status',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
                ),
              ),
            ],
          ),
          content: Text(
            'Do you want to mark just this side or both sides of the transfer as $actionLabel?',
            style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          actions: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: () => Navigator.of(
                      dialogContext,
                    ).pop(_TransferClearChoice.bothSides),
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Both Sides',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(
                      dialogContext,
                    ).pop(_TransferClearChoice.oneSide),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                      side: BorderSide(color: colorScheme.outlineVariant),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Just This Side',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        );
      },
    );
      });
  }

  List<Transaction> get _searchResults {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return <Transaction>[];
    // Base set: if viewing a specific account, limit to that account's transactions
    final base = (widget.accountId != null && widget.accountId!.isNotEmpty)
        ? _transactions.where((t) => t.accountId == widget.accountId).toList()
        : List<Transaction>.from(_transactions);
    final results = base.where(_matchesSelectedFilter).where((t) {
      final desc = t.description.toLowerCase();
      if (desc.contains(q)) return true;
      if (t.note != null && t.note!.toLowerCase().contains(q)) return true;
      final cat = DatabaseService.getCategoryById(t.categoryId);
      if (cat != null && cat.name.toLowerCase().contains(q)) return true;
      // match amount strings (simple)
      if (t.amount.toString().contains(q)) return true;
      return false;
    }).toList();
    results.sort(_compareTransactionsForDisplay);
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
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
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
        _transactions = all
            .where((t) => t.accountId == widget.accountId)
            .toList();
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
    final filtered = _transactions.where(_matchesSelectedFilter).toList();

    // Always include both cleared and uncleared transactions.
    filtered.sort(_compareTransactionsForDisplay);
    return filtered;
  }

  bool _matchesSelectedFilter(Transaction transaction) {
    switch (_selectedFilter) {
      case 'Income':
        return transaction.type == TransactionType.income;
      case 'Expense':
        return transaction.type == TransactionType.expense;
      case 'Transfers':
        try {
          final category = DatabaseService.getCategoryById(
            transaction.categoryId,
          );
          if (category != null && category.name.toLowerCase() == 'transfer') {
            return true;
          }
        } catch (_) {}
        return _isTransferTransaction(transaction);
      case 'Custom Dates':
        if (_customStartDate != null && _customEndDate != null) {
          return transaction.date.isAfter(
                _customStartDate!.subtract(const Duration(days: 1)),
              ) &&
              transaction.date.isBefore(
                _customEndDate!.add(const Duration(days: 1)),
              );
        }
        return true;
      default:
        return true;
    }
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
          toolbarHeight: _accountName == null ? null : 96,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Transactions'),
              if (_accountName != null) ...[
                const SizedBox(height: 2),
                Flexible(
                  child: Text(
                    _accountName!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w400,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          actions: [
            TextButton(
              onPressed: () async {
                final selected = await showModalBottomSheet<String>(
                  context: context,
                  showDragHandle: true,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  builder: (sheetContext) {
                    final colorScheme = Theme.of(sheetContext).colorScheme;

                    Widget option({
                      required String value,
                      required String label,
                      required IconData icon,
                    }) {
                      final isSelected = _selectedFilter == value;

                      return ListTile(
                        leading: Icon(
                          icon,
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        title: Text(
                          label,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(
                                Icons.check_rounded,
                                color: colorScheme.primary,
                              )
                            : null,
                        onTap: () {
                          Navigator.pop(sheetContext, value);
                        },
                      );
                    }

                    return SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Filter Transactions',
                                      style: Theme.of(sheetContext)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            option(
                              value: 'All',
                              label: 'All',
                              icon: Icons.list_alt_rounded,
                            ),

                            option(
                              value: 'Income',
                              label: 'Income',
                              icon: Icons.arrow_downward_rounded,
                            ),

                            option(
                              value: 'Expense',
                              label: 'Expense',
                              icon: Icons.arrow_upward_rounded,
                            ),

                            option(
                              value: 'Transfers',
                              label: 'Transfers',
                              icon: Icons.swap_horiz_rounded,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );

                if (selected == null || !mounted) return;

                setState(() {
                  _selectedFilter = selected;
                });
              },

              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),

              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    switch (_selectedFilter) {
                      'Income' => 'Income',
                      'Expense' => 'Expense',
                      'Transfers' => 'Transfers',
                      _ => 'All',
                    },
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(width: 2),

                  const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: TextField(
                  controller: _searchController,

                  onTapOutside: (_) {
                    FocusScope.of(context).unfocus();
                  },

                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.trim();
                    });
                  },

                  decoration: InputDecoration(
                    hintText: 'Search transactions',
                    hintStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),

                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),

                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                                _searchQuery = '';
                              });

                              FocusScope.of(context).unfocus();
                            },
                          )
                        : null,

                    filled: true,
                    fillColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.35),

                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),

                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),

                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1.5,
                      ),
                    ),

                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 15,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _searchQuery.isNotEmpty
                    ? _buildSearchResults()
                    : (hasAnyTransactions
                          ? _buildTransactionsList(showHeader: false)
                          : _buildEmptyState()),
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
          Icon(Icons.receipt_long, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No transactions',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the + button to add your first transaction',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsList({bool showHeader = true}) {
    final filteredTransactions = _transactions
        .where(_matchesSelectedFilter)
        .toList();

    if (filteredTransactions.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.45,
            child: Center(
              child: Text(
                'No $_selectedFilter transactions',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
              ),
            ),
          ),
        ],
      );
    }

    // Group only transactions matching the selected type filter.
    final groupedTransactions = <String, List<Transaction>>{};
    for (final transaction in filteredTransactions) {
      final monthKey = DateFormat('yyyy-MM').format(transaction.date);
      groupedTransactions[monthKey] ??= [];
      groupedTransactions[monthKey]!.add(transaction);
    }
    final sortedMonths = groupedTransactions.keys.toList()
      ..sort((a, b) => b.compareTo(a)); // Most recent first

    final showPendingSection =
        widget.accountId != null && widget.accountId!.isNotEmpty;
    final pendingTxs = showPendingSection
        ? filteredTransactions.where((t) => t.cleared != true).toList()
        : <Transaction>[];
    pendingTxs.sort(_compareTransactionsForDisplay);
    final pendingTotal = pendingTxs.fold<double>(
      0.0,
      (sum, tx) =>
          sum + (tx.type == TransactionType.income ? tx.amount : -tx.amount),
    );
    // Precompute the two ledgers represented by this screen. Cleared
    // transactions are the historical ledger; pending transactions are a
    // projection from the final cleared balance.
    Map<String, double>? runningMap;
    Map<String, double>? pendingRunningMap;
    if (widget.accountId != null && widget.accountId!.isNotEmpty) {
      final account = DatabaseService.getAccountById(widget.accountId!);
      if (account != null) {
        final ledger = AccountLedger.calculate(
          initialBalance: DatabaseService.getInitialBalance(account.id),
          transactions: _transactions,
        );
        runningMap = ledger.clearedRunningBalances;
        pendingRunningMap = ledger.pendingRunningBalances;
      }
    }

    return ListView(
      children: [
        if (showPendingSection && pendingTxs.isNotEmpty) ...[
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Pending',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),

                      Text(
                        '${pendingTxs.length} transaction${pendingTxs.length != 1 ? 's' : ''}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),

                      const SizedBox(width: 10),

                      Text(
                        _currencyFormat.format(pendingTotal),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: pendingTotal >= 0
                              ? AppTheme.incomeGreen
                              : AppTheme.expenseRed,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),

                Divider(
                  height: 1,
                  thickness: 1,
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),

                for (var i = 0; i < pendingTxs.length; i++) ...[
                  _buildTransactionItem(
                    pendingTxs[i],
                    runningBalance: pendingRunningMap?[pendingTxs[i].id],
                  ),

                  if (i != pendingTxs.length - 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Divider(
                        height: 1,
                        thickness: 1,
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.25),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
        if (showPendingSection)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _rearrangeTransactions,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.swap_vert_rounded, size: 18),
                label: const Text(
                  'Rearrange',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        for (final monthKey in sortedMonths) ...[
          () {
            List<Transaction> allGroupTxs = groupedTransactions[monthKey]!;
            final groupTxsForDisplay = showPendingSection
                ? allGroupTxs.where((t) => t.cleared == true).toList()
                : List<Transaction>.from(allGroupTxs);

            // Pending transactions are shown only in the Pending section.
            // Expanded month groups show all non-pending transactions.
            groupTxsForDisplay.sort(_compareTransactionsForDisplay);
            final displayTxs = groupTxsForDisplay;
            final parsedDate = DateTime.parse('$monthKey-01');
            // Always show the group, even if displayTxs is empty
            return _buildMonthGroup(
              monthKey,
              parsedDate,
              displayTxs,
              runningBalances: runningMap,
              allGroupTransactions: showPendingSection
                  ? groupTxsForDisplay
                  : allGroupTxs,
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
    // Only show balance header when viewing a specific account.
    if (widget.accountId == null || widget.accountId!.isEmpty) {
      return const SizedBox.shrink();
    }

    final account = DatabaseService.getAccountById(widget.accountId!);
    if (account == null) {
      return const SizedBox.shrink();
    }

    final ledger = AccountLedger.calculate(
      initialBalance: DatabaseService.getInitialBalance(account.id),
      transactions: _transactions,
    );
    final displayBalance = _showAvailableBalance
        ? ledger.availableBalance
        : ledger.currentBalance;
    final balanceLabel = _showAvailableBalance
        ? 'Available Balance'
        : 'Current Balance';

    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                setState(() {
                  _showAvailableBalance = !_showAvailableBalance;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        balanceLabel,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Icon(
                      Icons.swap_horiz_rounded,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            _currencyFormat.format(displayBalance),
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: displayBalance >= 0
                  ? AppTheme.incomeGreen
                  : AppTheme.expenseRed,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthGroup(
    String monthKey,
    DateTime date,
    List<Transaction> transactions, {
    Map<String, double>? runningBalances,
    List<Transaction>? allGroupTransactions,
  }) {
    final monthName = DateFormat(
      'MMMM yyyy',
    ).format(date); // Full month name and year
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
      ..sort(
        (a, b) => DateFormat(
          'MM/dd/yyyy',
        ).parse(b).compareTo(DateFormat('MM/dd/yyyy').parse(a)),
      );
    for (final dateStr in sortedDates) {
      final allTxsForDate = allDateGroups[dateStr]!;
      // Find the last transaction for this date (since list is newest first, it's the first in the group)
      final lastTx = allTxsForDate.first;
      final lastRunning = runningBalances != null
          ? runningBalances[lastTx.id]
          : null;
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
      final visibleTxs = transactions
          .where((t) => DateFormat('MM/dd/yyyy').format(t.date) == dateStr)
          .toList();

      if (visibleTxs.isNotEmpty) {
        children.addAll(
          visibleTxs.map(
            (transaction) => _buildTransactionItem(
              transaction,
              runningBalance: runningBalances != null
                  ? runningBalances[transaction.id]
                  : null,
            ),
          ),
        );
      }
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey<String>('transactions_month_$monthKey'),
          initiallyExpanded: _expandedMonths.contains(monthKey),

          onExpansionChanged: (expanded) {
            setState(() {
              if (expanded) {
                _expandedMonths.add(monthKey);
              } else {
                _expandedMonths.remove(monthKey);
              }
            });
          },

          maintainState: true,

          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),

          childrenPadding: const EdgeInsets.only(bottom: 8),

          iconColor: Theme.of(context).colorScheme.primary,
          collapsedIconColor: Theme.of(context).colorScheme.onSurfaceVariant,

          title: Row(
            children: [
              Expanded(
                child: Text(
                  monthName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              Text(
                '${txsForHeader.length} transaction${txsForHeader.length != 1 ? 's' : ''}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),

          children: children.isNotEmpty ? children : const [],
        ),
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

  String _transactionDisplayNote(String? note) {
    var displayNote = (note ?? '').trim();
    if (displayNote.isEmpty) return '';

    displayNote = displayNote
        .replaceFirst(RegExp(r'^__transfer_(manual|bill)__'), '')
        .replaceAll(RegExp(r'__hide_from_calendar__', caseSensitive: false), '')
        .trim();

    if (displayNote.toLowerCase().startsWith('account:')) {
      final afterAccount = displayNote.substring('account:'.length).trim();
      final parts = afterAccount.split(RegExp(r'\s*[—–-]\s*'));
      displayNote = parts.length > 1 ? parts.sublist(1).join(' — ').trim() : '';
    }

    return displayNote
        .replaceAll(RegExp(r'_transfer|_bill_', caseSensitive: false), '')
        .replaceAll(RegExp(r'pair:[A-Za-z0-9\-]+'), '')
        .trim();
  }

  Widget _buildClearedStatusBadge(Transaction transaction) {
    final isCleared = transaction.cleared == true;
    final label = isCleared ? 'Cleared' : 'Uncleared';

    return Tooltip(
      message: label,
      child: Icon(
        isCleared ? Icons.check_circle : Icons.pending_outlined,
        size: 12,
        color: isCleared ? AppTheme.incomeGreen : Colors.red,
      ),
    );
  }

  Widget _buildTransactionItem(
    Transaction transaction, {
    double? runningBalance,
  }) {
    final lookupsState = context.watch<LookupsState>();
    final normalizedCategoryId = transaction.categoryId.trim();
    final category = normalizedCategoryId.isEmpty
        ? null
        : DatabaseService.getCategoryById(normalizedCategoryId);
    final categoryText =
        (category?.name != null && category!.name.trim().isNotEmpty)
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
    if (transaction.splitsJson != null &&
        transaction.splitsJson!.trim().isNotEmpty) {
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
              .substring(
                0,
                paymentForDisplay.length - lowerCategorySuffix.length,
              )
              .trim();
        }
      }
    }
    final displayNote = _transactionDisplayNote(transaction.note);
    final isPayment = transaction.description.toLowerCase().startsWith(
      'payment for ',
    );
    final fallbackCounterparty = transaction.type == TransactionType.expense
        ? payeeText
        : payerText;
    var displayTitle = isPayment
        ? (fallbackCounterparty.isNotEmpty
              ? fallbackCounterparty
              : _extractPayeeName(transaction.description))
        : transaction.description;
    displayTitle = displayTitle.replaceFirst(
      RegExp(r'^\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\s+'),
      '',
    );
    final titleCategory = categoryText.trim();
    if (titleCategory.isNotEmpty &&
        displayTitle.toLowerCase().endsWith(
          ' ${titleCategory.toLowerCase()}',
        )) {
      displayTitle = displayTitle
          .substring(0, displayTitle.length - titleCategory.length - 1)
          .trim();
    }
    if ((displayTitle.trim().isEmpty ||
            displayTitle.trim().toLowerCase() == 'transaction') &&
        fallbackCounterparty.isNotEmpty) {
      displayTitle = fallbackCounterparty;
    }

    // Search results do not receive the precomputed map, so use the same
    // ledger calculation here rather than maintaining a second formula.
    if (runningBalance == null &&
        widget.accountId != null &&
        widget.accountId!.isNotEmpty) {
      final account = DatabaseService.getAccountById(widget.accountId!);
      if (account != null) {
        final ledger = AccountLedger.calculate(
          initialBalance: DatabaseService.getInitialBalance(account.id),
          transactions: _transactions,
        );
        runningBalance = transaction.cleared == true
            ? ledger.clearedRunningBalances[transaction.id]
            : ledger.pendingRunningBalances[transaction.id];
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

    Future<void> createRefund() async {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AddTransactionScreen(
            prefillTransaction: transaction,
            isRefund: true,
            hideFromCalendarDashboard: true,
          ),
        ),
      );
      if (result == true) _loadTransactions();
    }

    Future<void> toggleClearStatus() async {
      final newCleared = !(transaction.cleared ?? false);
      Transaction? linked;
      var shouldApplyToBothSides = false;

      if (_isTransferTransaction(transaction)) {
        linked = _findLinkedTransferTransaction(transaction);

        if (linked != null) {
          final choice = await _askTransferClearChoice(newCleared: newCleared);
          if (choice == null) return;
          shouldApplyToBothSides = choice == _TransferClearChoice.bothSides;
        }
      }

      await DatabaseService.updateTransaction(
        transaction.copyWith(cleared: newCleared),
      );

      if (shouldApplyToBothSides &&
          linked != null &&
          linked.cleared != newCleared) {
        await DatabaseService.updateTransaction(
          linked.copyWith(cleared: newCleared),
        );
      }

      _loadTransactions();
    }

    final card = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await openEditTransaction();
        },
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildClearedStatusBadge(transaction),
                  const SizedBox(width: 5),
                  Text(
                    DateFormat('MM/dd/yy').format(transaction.date),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
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
                      if (runningBalance != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _currencyFormat.format(runningBalance),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
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
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: Text(
                  displayTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  softWrap: true,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                categoryDisplay,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                softWrap: true,
              ),
              if (displayNote.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    displayNote,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                    softWrap: true,
                  ),
                ),
              ],
              if (widget.accountId != null &&
                  widget.accountId!.isNotEmpty &&
                  paymentForDisplay.isNotEmpty &&
                  (transaction.billId?.trim().isNotEmpty ?? false)) ...[
                const SizedBox(height: 8),
                Text(
                  'Payment for $paymentForDisplay',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
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
        extentRatio: _isTransferTransaction(transaction) ? 0.50 : 0.75,
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
          CustomSlidableAction(
            onPressed: (_) async => toggleClearStatus(),
            backgroundColor: Colors.blueGrey,
            foregroundColor: Colors.white,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  transaction.cleared == true
                      ? Icons.undo
                      : Icons.check_circle_outline,
                  color: Colors.white,
                ),
                const SizedBox(height: 4),
                Text(
                  transaction.cleared == true ? 'Mark Unclear' : 'Mark Cleared',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          if (!_isTransferTransaction(transaction))
            CustomSlidableAction(
              onPressed: (_) async => createRefund(),
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.currency_exchange_rounded, color: Colors.white),
                  SizedBox(height: 4),
                  Text(
                    'Refund',
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
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  void _deleteTransaction(Transaction transaction) {
    final note = transaction.note ?? '';
    final isTransfer =
        note.toLowerCase().startsWith('__transfer_manual__') ||
        note.toLowerCase().startsWith('__transfer_bill__');
    if (isTransfer) {
      showDialog(
        context: context,
        builder: (dialogContext) {
          final colorScheme = Theme.of(dialogContext).colorScheme;

          return AlertDialog(
            backgroundColor: colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 28,
              vertical: 24,
            ),
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            actionsPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            title: Row(
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
                    color: colorScheme.onErrorContainer,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Delete Transfer?',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
                  ),
                ),
              ],
            ),
            content: Text(
              'Are you sure you want to delete this transfer? Both sides of the transfer will be deleted.',
              style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          _deleteTransferTransaction(
                            transaction,
                            deleteBothSides: true,
                          );
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.error,
                          foregroundColor: colorScheme.onError,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Delete',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      );
    } else {
      final isBillPayment =
          transaction.billId != null && transaction.billId!.isNotEmpty;

      Future<void> confirmDelete(BuildContext dialogContext) async {
        final nav = Navigator.of(dialogContext);
        final messenger = ScaffoldMessenger.of(dialogContext);
        nav.pop();
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
        await DatabaseService.deleteTransaction(transaction.id);
        if (!mounted) return;
        _loadTransactions();
        messenger.clearSnackBars();
      }

      showDialog(
        context: context,
        builder: (dialogContext) {
          if (!isBillPayment) {
            return AlertDialog(
              title: const Text('Delete Transaction'),
              content: Text(
                'Are you sure you want to delete "${transaction.description}"?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => confirmDelete(dialogContext),
                  child: const Text(
                    'Delete',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            );
          }

          final colorScheme = Theme.of(dialogContext).colorScheme;

          return AlertDialog(
            backgroundColor: colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 28,
              vertical: 24,
            ),
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            actionsPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            title: Row(
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
                    color: colorScheme.onErrorContainer,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Delete Bill Payment?',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
                  ),
                ),
              ],
            ),
            content: Text(
              'This payment will be removed from the bill payment history and the bill status will be updated.',
              style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: () => confirmDelete(dialogContext),
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.error,
                          foregroundColor: colorScheme.onError,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text(
                          'Delete',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      );
    }
  }
}
