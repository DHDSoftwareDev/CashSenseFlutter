// ignore_for_file: avoid_print, unused_field, prefer_final_fields

import '../services/account_operations.dart';
import '../widgets/banner_ad_widget.dart';
// ignore_for_file: use_build_context_synchronously

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../services/lookups_state.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../widgets/account_type_icon.dart';
import 'add_account_screen.dart';
import 'add_transaction_screen.dart';
// Reordering is handled inline in this screen.
import '../utils/root_scaffold.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  final int _accountGeneration = AccountOperations.generation;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Grouping state: 0 = type, 1 = institution
  int _groupByIndex = 0;
  // Track which account balances are hidden (local UI state)
  final Set<String> _hiddenBalances = <String>{};
  // Always show available balance; remove per-account display mode
  // final Map<String, bool> _showCurrentBalance = <String, bool>{};
  // Inline reorder mode state
  bool _isReordering = false;
  // When true, only groups are reorderable. When false, accounts within groups are reorderable.
  bool _reorderGroupsOnly = true;
  // (previously used for multi-mode reorder; now reorder is types-only)
  // Persistent ordering lists
  late List<String> _accountOrder;
  late List<String> _accountTypeOrder;
  late List<String> _institutionOrder;
  // Per-group account id order used during inline reordering
  Map<String, List<String>> _groupAccountOrder = {};
  // Track expanded/collapsed state for groups
  final Set<String> _expandedGroups = <String>{};
  @override
  void initState() {
    super.initState();
    // Load persisted group by selection
    _groupByIndex =
        DatabaseService.getSetting<int>('accountsGroupByIndex', 0) ?? 0;
    // No longer load per-account display preferences; always show available balance
    // Load persisted hidden balances so they survive app restarts
    try {
      final raw = DatabaseService.getSetting<List<dynamic>>(
        'hiddenAccountBalances',
        <dynamic>[],
      );
      if (raw != null) {
        for (final e in raw) {
          if (e != null) _hiddenBalances.add(e.toString());
        }
      }
    } catch (_) {}
    // Load persisted expanded groups so the UI remembers collapsed state between launches
    try {
      final raw = DatabaseService.getSetting<List<dynamic>>(
        'expandedAccountGroups',
        <dynamic>[],
      );
      if (raw != null) {
        for (final e in raw) {
          if (e != null) _expandedGroups.add(e.toString());
        }
      }
    } catch (_) {}
    // Listen for account changes so this screen can refresh when accounts are added/updated elsewhere
    DatabaseService.accountsVersion.addListener(_onAccountsChanged);
    // Also listen for transactions changes so available balances refresh when
    // transactions are added/updated/deleted elsewhere in the app.
    DatabaseService.transactionsVersion.addListener(_onAccountsChanged);
    // Load ordering settings
    final allAccounts = DatabaseService.getAllAccounts();
    final accIds = allAccounts.map((a) => a.id).toList();
    final savedAccountOrderRaw = DatabaseService.getSetting<List<dynamic>>(
      'accountOrder',
      accIds,
    );
    _accountOrder = (savedAccountOrderRaw ?? accIds)
        .map((e) => e.toString())
        .toList();

    final savedTypeOrderRaw = DatabaseService.getSetting<List<dynamic>>(
      'accountTypeOrder',
      <dynamic>[],
    );
    _accountTypeOrder = (savedTypeOrderRaw ?? <dynamic>[])
        .map((e) => e.toString())
        .toList();
    if (_accountTypeOrder.isEmpty) {
      _accountTypeOrder = allAccounts
          .map((a) => a.typeDisplayName)
          .toSet()
          .toList();
    }

    final savedInstRaw = DatabaseService.getSetting<List<dynamic>>(
      'accountInstitutionOrder',
      <dynamic>[],
    );
    _institutionOrder = (savedInstRaw ?? <dynamic>[])
        .map((e) => e.toString())
        .toList();
    if (_institutionOrder.isEmpty) {
      final seen = <String>{};
      final list = <String>[];
      for (final a in allAccounts) {
        final key = _institutionKey(a);
        if (!seen.contains(key)) {
          seen.add(key);
          list.add(key);
        }
      }
      _institutionOrder = list;
    }
  }

  void _onAccountsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String _institutionKey(Account account) {
    final key = (account.institution ?? account.description ?? '').trim();
    return key.isEmpty ? 'Unknown' : key;
  }

  String? _institutionLabel(Account account) {
    final label = (account.institution ?? account.description ?? '').trim();
    return label.isEmpty ? null : label;
  }

  String? _accountDetailLabel(Account account) {
    final institution = _institutionLabel(account);
    final accountNumber = (account.accountNumber ?? '').trim();
    final cardNumber = (account.cardNumber ?? '').trim();
    final numberParts = <String>[
      if (accountNumber.isNotEmpty) 'Account: $accountNumber',
      if (cardNumber.isNotEmpty) 'Card: $cardNumber',
    ];
    final number = numberParts.isNotEmpty
        ? numberParts.join(' - ')
        : _extractNumberFromDescription(institution);

    if (institution == null) return number;
    if (number == null || number.isEmpty) return institution;
    return '$institution - $number';
  }

  Widget _buildAccountTypeIcon(Account account) {
    return AccountTypeIcon(
      type: account.type,
      displayName: account.typeDisplayName,
    );
  }

  Widget _buildFittedAccountText(String text, TextStyle? style) {
    return SizedBox(
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: style,
        ),
      ),
    );
  }

  Future<void> _openAccountTransactions(Account acc) {
    return AccountOperations.bind(_accountGeneration, () async {
    navigateToRootPage(1, accountId: acc.id);
      });
  }

  Future<void> _archiveAccount(Account acc) {
    return AccountOperations.bind(_accountGeneration, () async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colors = theme.colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.archive_outlined,
              color: colors.onPrimaryContainer,
            ),
          ),
          title: const Text(
            'Archive Account',
            textAlign: TextAlign.center,
          ),
          content: Text(
            'Archive "${acc.name}"? This will hide it from your account lists.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Archive'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    final updated = acc.copyWith(isActive: false);
    await DatabaseService.updateAccount(updated);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).clearSnackBars();
      });
  }

  Future<void> _deleteAccount(Account acc) {
    return AccountOperations.bind(_accountGeneration, () async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colors = theme.colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: colors.errorContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.delete_outline_rounded,
              color: colors.onErrorContainer,
            ),
          ),
          title: const Text(
            'Delete Account',
            textAlign: TextAlign.center,
          ),
          content: Text(
            'Permanently delete "${acc.name}"? This action cannot be undone.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.error,
                        foregroundColor: colors.onError,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Delete'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await DatabaseService.deleteAccount(acc.id);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).clearSnackBars();
      });
  }

  Future<void> _editAccount(Account acc) {
    return AccountOperations.bind(_accountGeneration, () async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddAccountScreen(account: acc)),
    );
    if (!mounted) return;
    if (result == true) setState(() {});
      });
  }

  Future<void> _toggleAccountBalanceHidden(Account acc) {
    return AccountOperations.bind(_accountGeneration, () async {
    setState(() {
      if (_hiddenBalances.contains(acc.id)) {
        _hiddenBalances.remove(acc.id);
      } else {
        _hiddenBalances.add(acc.id);
      }
    });
    try {
      await DatabaseService.setSetting(
        'hiddenAccountBalances',
        _hiddenBalances.toList(),
      );
    } catch (_) {}
      });
  }

  @override
  Widget build(BuildContext context) {
    // Always fetch the latest accounts so balances update after transaction changes
    final List<Account> accounts = DatabaseService.getAllAccounts();

    return SlidableAutoCloseBehavior(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: openRootDrawer,
          ),
          title: const Text('Accounts'),
          centerTitle: true,
          actions: _isReordering
              ? [
                  TextButton(
                    onPressed: () {
                      // Cancel reorder
                      setState(() {
                        _isReordering = false;
                      });
                    },
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
               TextButton(
  onPressed: () {
    setState(() {
      _reorderGroupsOnly = !_reorderGroupsOnly;
    });
  },
  child: Text(
    _reorderGroupsOnly ? 'Groups' : 'Accounts',
    style: const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w500,
    ),
  ),
),
                  TextButton(
                    onPressed: () async {
                      // Save reorder: reconstruct accountOrder from per-group orders in current group ordering
                      final newAccountOrder = <String>[];
                      // Determine the authoritative group ordering to iterate. If the
                      // persisted group-order list is empty or doesn't contain the
                      // current group keys (edge-case when there is only one group),
                      // fall back to the keys present in _groupAccountOrder which
                      // reflect the visual groups shown to the user.
                      final groupKeys = (_groupByIndex == 0)
                          ? _accountTypeOrder
                          : _institutionOrder;
                      final availableGroupKeys = _groupAccountOrder.keys
                          .toList();
                      final useKeys =
                          (groupKeys.isNotEmpty &&
                              groupKeys.any(
                                (k) => _groupAccountOrder.containsKey(k),
                              ))
                          ? groupKeys
                          : availableGroupKeys;

                      if (_groupByIndex == 0) {
                        for (final type in useKeys) {
                          final ids = _groupAccountOrder[type] ?? [];
                          newAccountOrder.addAll(ids);
                        }
                      } else {
                        for (final inst in useKeys) {
                          final ids = _groupAccountOrder[inst] ?? [];
                          newAccountOrder.addAll(ids);
                        }
                      }
                      // Fallback: include any accounts not present yet
                      final allIds = DatabaseService.getAllAccounts()
                          .map((a) => a.id)
                          .toList();
                      for (final id in allIds) {
                        if (!newAccountOrder.contains(id)) {
                          newAccountOrder.add(id);
                        }
                      }

                      await DatabaseService.setSetting(
                        'accountOrder',
                        newAccountOrder,
                      );
                      // Persist the group ordering that was actually used so
                      // future screens apply the same visual grouping.
                      if (_groupByIndex == 0) {
                        await DatabaseService.setSetting(
                          'accountTypeOrder',
                          useKeys,
                        );
                      } else {
                        await DatabaseService.setSetting(
                          'accountInstitutionOrder',
                          useKeys,
                        );
                      }
                      DatabaseService.accountsVersion.value++;
                      if (!mounted) return;
                      setState(() {
                        _isReordering = false;
                      });
                    },
                    child: const Text(
                      'Save',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ]
              : [
                  // Reorder button: opens a dedicated reorder screen with explicit Save/Cancel
                  IconButton(
                    icon: const Icon(Icons.swap_vert),
                    tooltip: 'Reorder accounts',
                    onPressed: () {
                      // Enter inline reorder mode and prepare per-group ordering
                      final accounts = DatabaseService.getAllAccounts();
                      final orderedIds = _accountOrder;
                      final Map<String, List<String>> grouped = {};
                      final mapById = {for (var a in accounts) a.id: a};
                      if (_groupByIndex == 0) {
                        // group by type
                        for (final id in orderedIds) {
                          if (!mapById.containsKey(id)) continue;
                          final a = mapById[id]!;
                          final key = a.typeDisplayName;
                          grouped.putIfAbsent(key, () => []).add(id);
                        }
                        // Ensure all types present and include any missing accounts
                        for (final a in accounts) {
                          final key = a.typeDisplayName;
                          grouped.putIfAbsent(key, () => []);
                          if (!grouped[key]!.contains(a.id)) {
                            grouped[key]!.add(a.id);
                          }
                        }
                      } else {
                        // group by institution/description
                        for (final id in orderedIds) {
                          if (!mapById.containsKey(id)) continue;
                          final a = mapById[id]!;
                          final key = _institutionKey(a);
                          grouped.putIfAbsent(key, () => []).add(id);
                        }
                        for (final a in accounts) {
                          final key = _institutionKey(a);
                          grouped.putIfAbsent(key, () => []);
                          if (!grouped[key]!.contains(a.id)) {
                            grouped[key]!.add(a.id);
                          }
                        }
                      }
                      setState(() {
                        _groupAccountOrder = grouped;
                        _isReordering = true;
                        // Default to groups-only reordering so type headers can be reordered
                        // (matches institution behavior where groups are reordered)
                        _reorderGroupsOnly = true;
                      });
                    },
                  ),
                  // Add account button
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'Add account',
                    onPressed: () async {
                      final isSubscriber =
                          DatabaseService.subscriptionVersion.value != 'Free';
                      final accounts = DatabaseService.getAllAccounts();
                      if (!isSubscriber && accounts.length >= 3) {
                        // Show feedback dialog for free users who reached the limit
                        await showDialog(
                          context: context,
                          builder: (dialogContext) {
                            final theme = Theme.of(dialogContext);
                            final colors = theme.colorScheme;
                            return AlertDialog(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              icon: Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: colors.primaryContainer,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(
                                  Icons.workspace_premium_outlined,
                                  color: colors.onPrimaryContainer,
                                ),
                              ),
                              title: const Text(
                                'Account Limit Reached',
                                textAlign: TextAlign.center,
                              ),
                              content: Text(
                                'Free users can create up to 3 accounts. Subscribe for unlimited accounts.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  height: 1.4,
                                ),
                              ),
                              actionsPadding:
                                  const EdgeInsets.fromLTRB(20, 0, 20, 20),
                              actions: [
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: colors.primary,
                                      foregroundColor: colors.onPrimary,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text('OK'),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                        return;
                      }
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AddAccountScreen(),
                        ),
                      );
                      if (!mounted) return;
                      if (result == true) setState(() {});
                    },
                  ),
                ],
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
        ),
        body: GestureDetector(
  behavior: HitTestBehavior.translucent,
  onTap: () {
    FocusManager.instance.primaryFocus?.unfocus();
  },
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
            children: [
              TextField(
  key: const ValueKey('accounts_transaction_search'),
  controller: _searchController,
  textInputAction: TextInputAction.search,
  decoration: InputDecoration(
    hintText: 'Search transactions in all accounts',
    prefixIcon: Icon(
      Icons.search_rounded,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    suffixIcon: _searchQuery.isEmpty
        ? null
        : IconButton(
            tooltip: 'Clear search',
            icon: const Icon(Icons.close_rounded),
            onPressed: () {
              _searchController.clear();
              setState(() => _searchQuery = '');
            },
          ),
    filled: true,
    fillColor: Theme.of(context)
        .colorScheme
        .surfaceContainerHighest
        .withValues(alpha: 0.35),
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
      horizontal: 16,
      vertical: 15,
    ),
  ),
  onChanged: (value) {
    setState(() => _searchQuery = value.trim());
  },
),
              const SizedBox(height: 12),
             // Group by toggle (centered)
if (_searchQuery.isEmpty) ...[
  Center(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Group by',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
        ),

        const SizedBox(width: 10),

        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildGroupByOption(
                label: 'Type',
                index: 0,
              ),
              _buildGroupByOption(
                label: 'Institution',
                index: 1,
              ),
            ],
          ),
        ),
      ],
    ),
  ),
],
              Expanded(
                child: _searchQuery.isEmpty
                    ? _buildGroupedAccountsList(accounts)
                    : _buildTransactionSearchResults(accounts),
              ),
              const SizedBox(height: 16),
              // You can swap BannerAdWidget with NativeAdWidget if you want native ads
              const BannerAdWidget(),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildGroupByOption({
    required String label,
    required int index,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = _groupByIndex == index;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        if (_groupByIndex == index) return;

        setState(() {
          _groupByIndex = index;
        });

        await DatabaseService.setSetting(
          'accountsGroupByIndex',
          index,
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    DatabaseService.accountsVersion.removeListener(_onAccountsChanged);
    DatabaseService.transactionsVersion.removeListener(_onAccountsChanged);
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesTransactionSearch(
    Transaction transaction,
    String query,
    String accountName,
  ) {
    final categoryName =
        DatabaseService.getCategoryById(transaction.categoryId)?.name ?? '';
    final searchableValues = <String>[
      transaction.description,
      transaction.note ?? '',
      transaction.paymentFor ?? '',
      transaction.payeeName ?? '',
      transaction.payerName ?? '',
      transaction.categoryName ?? '',
      categoryName,
      accountName,
      transaction.amount.toString(),
      formatCurrency(transaction.amount),
      DateFormat('MM/dd/yyyy').format(transaction.date),
      DateFormat.yMMMd().format(transaction.date),
    ];
    return searchableValues.any((value) => value.toLowerCase().contains(query));
  }

  Widget _buildTransactionSearchResults(List<Account> accounts) {
    final query = _searchQuery.toLowerCase();
    final accountsById = <String, Account>{for (final a in accounts) a.id: a};
    final grouped = <String, List<Transaction>>{};

    for (final transaction in DatabaseService.getAllTransactions()) {
      final accountId = transaction.accountId;
      final account = accountId == null
          ? null
          : accountsById[accountId] ??
                DatabaseService.getAccountById(accountId);
      final accountName = account?.name ?? 'Unassigned';
      if (_matchesTransactionSearch(transaction, query, accountName)) {
        grouped
            .putIfAbsent(accountId ?? '', () => <Transaction>[])
            .add(transaction);
      }
    }

    if (grouped.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.4,
            child: Center(
              child: Text(
                'No matching transactions',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
              ),
            ),
          ),
        ],
      );
    }

    final accountIds = grouped.keys.toList()
      ..sort((a, b) {
        final aOrder = _accountOrder.indexOf(a);
        final bOrder = _accountOrder.indexOf(b);
        if (aOrder >= 0 && bOrder >= 0) return aOrder.compareTo(bOrder);
        if (aOrder >= 0) return -1;
        if (bOrder >= 0) return 1;
        final aName =
            accountsById[a]?.name ??
            DatabaseService.getAccountById(a)?.name ??
            'Unassigned';
        final bName =
            accountsById[b]?.name ??
            DatabaseService.getAccountById(b)?.name ??
            'Unassigned';
        return aName.toLowerCase().compareTo(bName.toLowerCase());
      });

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: accountIds.length,
      itemBuilder: (context, index) {
        final accountId = accountIds[index];
        final accountName =
            accountsById[accountId]?.name ??
            DatabaseService.getAccountById(accountId)?.name ??
            'Unassigned';
        final transactions = grouped[accountId]!
          ..sort((a, b) => b.date.compareTo(a.date));
        return _buildTransactionSearchGroup(accountName, transactions);
      },
    );
  }

  Widget _buildTransactionSearchGroup(
    String accountName,
    List<Transaction> transactions,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: colors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              accountName,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (var index = 0; index < transactions.length; index++) ...[
            _buildTransactionSearchTile(transactions[index]),
            if (index < transactions.length - 1)
              const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildTransactionSearchTile(Transaction transaction) {
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

    var categoryDisplay = categoryText;
    if (transaction.splitsJson != null &&
        transaction.splitsJson!.trim().isNotEmpty) {
      try {
        final splits = json.decode(transaction.splitsJson!) as List<dynamic>;
        final parts = <String>[];
        for (final split in splits) {
          if (split is Map) {
            final categoryId = split['categoryId']?.toString().trim();
            final amount = split['amount'];
            final splitCategory =
                categoryId != null && categoryId.isNotEmpty
                ? DatabaseService.getCategoryById(categoryId)
                : null;
            final name =
                splitCategory?.name != null &&
                    splitCategory!.name.trim().isNotEmpty
                ? splitCategory.name
                : lookupsState.categoryName(
                    categoryId,
                    fallbackName: categoryId ?? 'Unknown',
                  );
            final amountText = amount is num
                ? formatCurrency(amount.toDouble())
                : amount?.toString() ?? '';
            parts.add('$name $amountText');
          }
        }
        categoryDisplay = parts.join(', ');
      } catch (_) {
        categoryDisplay = categoryText;
      }
    }

    final fallbackCounterparty = transaction.type == TransactionType.expense
        ? payeeText
        : payerText;
    final isPayment = transaction.description.toLowerCase().startsWith(
      'payment for ',
    );
    var title = isPayment
        ? (fallbackCounterparty.isNotEmpty
              ? fallbackCounterparty
              : _extractTransactionPayeeName(transaction.description))
        : transaction.description;
    title = title.replaceFirst(
      RegExp(r'^\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\s+'),
      '',
    );
    final categorySuffix = categoryText.trim();
    if (categorySuffix.isNotEmpty &&
        title.toLowerCase().endsWith(' ${categorySuffix.toLowerCase()}')) {
      title = title
          .substring(0, title.length - categorySuffix.length - 1)
          .trim();
    }
    if ((title.trim().isEmpty || title.trim().toLowerCase() == 'transaction') &&
        fallbackCounterparty.isNotEmpty) {
      title = fallbackCounterparty;
    }

    final note = _transactionDisplayNote(transaction.note);
    final isIncome = transaction.type == TransactionType.income;

    return Material(
      key: ValueKey('account_search_transaction_${transaction.id}'),
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddTransactionScreen(
                existingTransaction: transaction,
                hideFromCalendarDashboard: true,
              ),
            ),
          );
          if (mounted) setState(() {});
        },
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          title: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Tooltip(
                          message: transaction.cleared == true
                              ? 'Cleared'
                              : 'Uncleared',
                          child: Icon(
                            transaction.cleared == true
                                ? Icons.check_circle
                                : Icons.pending_outlined,
                            size: 12,
                            color: transaction.cleared == true
                                ? AppTheme.incomeGreen
                                : Colors.red,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          DateFormat('MM/dd/yy').format(transaction.date),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      categoryDisplay,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
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
                    '${isIncome ? '+' : '-'}${formatCurrency(transaction.amount)}',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: isIncome
                          ? AppTheme.incomeGreen
                          : AppTheme.expenseRed,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 140,
                      child: Text(
                        note,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _extractTransactionPayeeName(String description) {
    var name = description.trim();
    if (name.toLowerCase().startsWith('payment for ')) {
      name = name.substring('payment for '.length).trim();
    }
    return name
        .replaceAll(
          RegExp(r'[(\[]?\d{1,2}[/-]\d{1,2}[/-]\d{2,4}[)\]]?$'),
          '',
        )
        .trim();
  }

  String _transactionDisplayNote(String? note) {
    if (note == null || note.trim().isEmpty) return '';

    var display = note.trim();
    final lower = display.toLowerCase();
    final isTransfer =
        lower.startsWith('__transfer_manual__') ||
        lower.startsWith('__transfer_bill__');
    if (isTransfer &&
        (display == '__transfer_manual__' || display == '__transfer_bill__')) {
      return '';
    }
    if (isTransfer) {
      display = display
          .replaceFirst(RegExp(r'^__transfer_(manual|bill)__'), '')
          .trim();
    }
    display = display
        .replaceAll(
          RegExp(r'__hide_from_calendar__', caseSensitive: false),
          '',
        )
        .trim();
    if (display.toLowerCase().startsWith('account:')) {
      final afterAccount = display.substring('account:'.length).trim();
      final parts = afterAccount.split(RegExp(r'\s*[—–-]\s*'));
      display = parts.length > 1
          ? parts.sublist(1).join(' — ').trim()
          : '';
    }
    return display
        .replaceAll(RegExp(r'_transfer|_bill_', caseSensitive: false), '')
        .replaceAll(RegExp(r'pair:[A-Za-z0-9\-]+'), '')
        .trim();
  }

  // Attempt to extract a short account/card number from the freeform description.
  // Returns null if none found. This is a best-effort helper because the
  // data model doesn't currently have a dedicated account-number field.
  String? _extractNumberFromDescription(String? desc) {
    if (desc == null || desc.isEmpty) return null;
    // Find a run of digits of length >= 3 (e.g., '1234' or '000123')
    final reg = RegExp(r"(\d{3,})");
    final match = reg.firstMatch(desc);
    if (match == null) return null;
    final digits = match.group(0)!;
    // Prefer showing the last 4 digits masked like '••••1234' when possible
    if (digits.length >= 4) {
      return '••••${digits.substring(digits.length - 4)}';
    }
    return digits;
  }

  Widget _buildGroupedAccountsList(List<Account> accounts) {
    if (_groupByIndex == 0) {
      // Group by AccountType (use display name string to avoid enum null issues)
      // Apply saved order for account types when grouping
      // persisted type order is loaded into `_accountTypeOrder` in initState
      final Map<String, List<Account>> groups = {};
      for (final a in accounts) {
        final key = a.typeDisplayName;
        groups.putIfAbsent(key, () => <Account>[]).add(a);
      }

      final entries = groups.entries.toList();
      // Apply persisted type order if present
      if (_accountTypeOrder.isNotEmpty) {
        entries.sort((a, b) {
          final ai = _accountTypeOrder.indexWhere(
            (e) => e.toLowerCase() == a.key.toLowerCase(),
          );
          final bi = _accountTypeOrder.indexWhere(
            (e) => e.toLowerCase() == b.key.toLowerCase(),
          );
          if (ai == -1 && bi == -1) return a.key.compareTo(b.key);
          if (ai == -1) return 1;
          if (bi == -1) return -1;
          return ai.compareTo(bi);
        });
      }

      if (!_isReordering) {
        return ListView.separated(
          itemCount: entries.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (context, index) {
            final title = entries[index].key;
            final items = entries[index].value;
            return _buildAccountGroup(title: title, accounts: items);
          },
        );
      }

      // Reordering mode: either groups are reorderable, or accounts within groups are reorderable
      if (_reorderGroupsOnly) {
        return ReorderableListView(
          // Reorder the local entries list (the visual order) and then sync
          // the persisted _accountTypeOrder to match the new ordering. This
          // avoids relying on indices into _accountTypeOrder which can get
          // out-of-sync with the visual entries list and cause items to snap back.
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex -= 1;
              // Move the entry in the visual list
              final moved = entries.removeAt(oldIndex);
              entries.insert(newIndex, moved);
              // Sync the persisted type order to the new visual order
              _accountTypeOrder = entries.map((e) => e.key).toList();
            });
            // Persist immediately
            final newAccountOrder = <String>[];
            for (final type in _accountTypeOrder) {
              final ids = _groupAccountOrder[type] ?? [];
              newAccountOrder.addAll(ids);
            }
            final allIds = DatabaseService.getAllAccounts()
                .map((a) => a.id)
                .toList();
            for (final id in allIds) {
              if (!newAccountOrder.contains(id)) newAccountOrder.add(id);
            }
            DatabaseService.setSetting('accountOrder', newAccountOrder);
            DatabaseService.setSetting('accountTypeOrder', _accountTypeOrder);
            DatabaseService.accountsVersion.value++;
          },
          children: [
            for (final entry in entries)
              Card(
                key: ValueKey('group_${entry.key}'),
                margin: const EdgeInsets.symmetric(vertical: 6.0),
                child: _buildAccountGroup(
                  title: entry.key,
                  accounts: entry.value,
                ),
              ),
          ],
        );
      }

      // Accounts-only reorder: render groups in order, but each group's list is reorderable (handled in _buildAccountGroup)
      return ListView.separated(
        itemCount: entries.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (context, index) {
          final title = entries[index].key;
          final items = entries[index].value;
          return _buildAccountGroup(title: title, accounts: items);
        },
      );
    }

    // Group by institution (fallback to legacy description)
    final Map<String, List<Account>> groups = {};
    for (final a in accounts) {
      final key = _institutionKey(a);
      groups.putIfAbsent(key, () => <Account>[]).add(a);
    }

    final entries = groups.entries.toList();
    // Apply persisted institution order
    if (_institutionOrder.isNotEmpty) {
      entries.sort((a, b) {
        final ai = _institutionOrder.indexWhere(
          (e) => e.toLowerCase() == a.key.toLowerCase(),
        );
        final bi = _institutionOrder.indexWhere(
          (e) => e.toLowerCase() == b.key.toLowerCase(),
        );
        if (ai == -1 && bi == -1) return a.key.compareTo(b.key);
        if (ai == -1) return 1;
        if (bi == -1) return -1;
        return ai.compareTo(bi);
      });
    }

    if (!_isReordering) {
      return ListView.separated(
        itemCount: entries.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (context, index) {
          final title = entries[index].key;
          final items = entries[index].value;
          return _buildAccountGroup(title: title, accounts: items);
        },
      );
    }

    // Reordering mode: make groups reorderable
    return ReorderableListView(
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          // Move the entry in the visual list and sync persisted ordering
          final moved = entries.removeAt(oldIndex);
          entries.insert(newIndex, moved);
          _institutionOrder = entries.map((e) => e.key).toList();
        });
        // Persist immediately
        final newAccountOrder = <String>[];
        for (final inst in _institutionOrder) {
          final ids = _groupAccountOrder[inst] ?? [];
          newAccountOrder.addAll(ids);
        }
        final allIds = DatabaseService.getAllAccounts()
            .map((a) => a.id)
            .toList();
        for (final id in allIds) {
          if (!newAccountOrder.contains(id)) newAccountOrder.add(id);
        }
        DatabaseService.setSetting('accountOrder', newAccountOrder);
        DatabaseService.setSetting(
          'accountInstitutionOrder',
          _institutionOrder,
        );
        DatabaseService.accountsVersion.value++;
      },
      children: [
        for (final entry in entries)
          Card(
            key: ValueKey('group_${entry.key}'),
            margin: const EdgeInsets.symmetric(vertical: 6.0),
            child: _buildAccountGroup(title: entry.key, accounts: entry.value),
          ),
      ],
    );
  }

  Widget _buildAccountGroup({
    required String title,
    required List<Account> accounts,
  }) {
    // Determine display order for this group. When reordering, use the
    // _groupAccountOrder that was initialized when entering reorder mode so
    // the visual list remains stable across rebuilds while dragging.
    List<Account> displayAccounts = accounts;
    if (_isReordering && _groupAccountOrder.containsKey(title)) {
      final orderedIds = _groupAccountOrder[title]!;
      final map = {for (var a in accounts) a.id: a};
      final ordered = <Account>[];
      for (final id in orderedIds) {
        if (map.containsKey(id)) ordered.add(map[id]!);
      }
      for (final a in accounts) {
        if (!ordered.any((x) => x.id == a.id)) ordered.add(a);
      }
      displayAccounts = ordered;
    }

    final expanded = _expandedGroups.contains(title);
    final primary = Theme.of(context).colorScheme.primary;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    // Make the Card use the primary color so the header row can fill the
    // entire width; the children area is placed in a separate container
    // with the normal card color so only the header looks colored.
    return Card(
      color: primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        key: ValueKey('expansion_$title'),
        initiallyExpanded: expanded,
        // Make the tile background transparent; header container will show
        // the card's primary color
        tilePadding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        trailing: const SizedBox.shrink(),
        onExpansionChanged: (isOpen) async {
          // While reordering we normally block expansion changes because
          // dragging items while the list changes can be confusing. However
          // when we're in per-group reordering mode (i.e. accounts are
          // reorderable within each group) it's useful to allow the user to
          // expand/collapse groups so they can focus on a particular group.
          // Only block expansion when the UI is in "groups-only" reorder mode.
          if (_isReordering && _reorderGroupsOnly) return;
          setState(() {
            if (isOpen) {
              _expandedGroups.add(title);
            } else {
              _expandedGroups.remove(title);
            }
          });
          // Persist expanded group list
          try {
            await DatabaseService.setSetting(
              'expandedAccountGroups',
              _expandedGroups.toList(),
            );
          } catch (_) {}
        },
        title: Container(
          width: double.infinity,
          // leave color transparent so Card's primary shows through
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Custom chevron so the colored background covers the full header row
              AnimatedRotation(
                turns: expanded ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.expand_more, color: onPrimary),
              ),
            ],
          ),
        ),
        children: [
          // Children area sits on a separate container with card color so it
          // appears as the normal content area while the header is primary.
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(12),
              ),
            ),
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Compute totals for this group
                Builder(
                  builder: (context) {
                    // Calculate total based on available balances only
                    final double groupTotal = displayAccounts.fold(0.0, (s, a) {
                      if (_hiddenBalances.contains(a.id) || !a.isActive) {
                        return s;
                      }
                      final displayAmount =
                          DatabaseService.getDisplayBalanceForAccount(
                            a.id,
                            showAvailable: true,
                            includeCleared: true,
                          );
                      return s + displayAmount;
                    });
                    final totalColor = groupTotal >= 0
                        ? Colors.green
                        : Theme.of(context).colorScheme.error;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SizedBox.shrink(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Total: ${formatCurrency(groupTotal)}',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: totalColor),
                            ),
                            Text(
                              'Available Balance',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.grey,
                                    fontStyle: FontStyle.italic,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                if (!_isReordering)
                  ...displayAccounts.map<Widget>((acc) {
                    final displayAmount =
                        _hiddenBalances.contains(acc.id) || !acc.isActive
                        ? 0.0
                        : DatabaseService.getDisplayBalanceForAccount(
                            acc.id,
                            showAvailable: true,
                            includeCleared: true,
                          );
                    final balanceText = _hiddenBalances.contains(acc.id)
                        ? '•••'
                        : formatCurrency(displayAmount);
                    try {
                      final card = Card(
                        margin: const EdgeInsets.symmetric(vertical: 6.0),
                        child: ListTile(
                          leading: _buildAccountTypeIcon(acc),
                          title: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildFittedAccountText(
                                      acc.name,
                                      Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    if (_accountDetailLabel(acc) != null)
                                      _buildFittedAccountText(
                                        _accountDetailLabel(acc)!,
                                        Theme.of(context).textTheme.bodySmall,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    balanceText,
                                    style: _hiddenBalances.contains(acc.id)
                                        ? null
                                        : Theme.of(
                                            context,
                                          ).textTheme.bodyMedium?.copyWith(
                                            color: (displayAmount >= 0)
                                                ? Colors.green
                                                : Theme.of(
                                                    context,
                                                  ).colorScheme.error,
                                          ),
                                  ),
                                  if (!_hiddenBalances.contains(acc.id))
                                    Text(
                                      'Available',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Colors.grey,
                                            fontSize: 10,
                                            fontStyle: FontStyle.italic,
                                          ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          onTap: () async {
                            await _openAccountTransactions(acc);
                          },
                        ),
                      );

                      final isHidden = _hiddenBalances.contains(acc.id);
                      return Slidable(
                        key: ValueKey('account_swipe_${acc.id}'),
                        startActionPane: ActionPane(
                          motion: const DrawerMotion(),
                          extentRatio: 0.50,
                          children: [
                            CustomSlidableAction(
                              onPressed: (_) async => _editAccount(acc),
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              foregroundColor: Colors.white,
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.edit, color: Colors.white),
                                  SizedBox(height: 4),
                                  Text(
                                    'Edit',
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
                              onPressed: (_) async =>
                                  _toggleAccountBalanceHidden(acc),
                              backgroundColor: Colors.blueGrey,
                              foregroundColor: Colors.white,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isHidden
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isHidden
                                        ? 'Show\nBalance'
                                        : 'Hide\nBalance',
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
                          ],
                        ),
                        endActionPane: ActionPane(
                          motion: const DrawerMotion(),
                          extentRatio: 0.50,
                          children: [
                            CustomSlidableAction(
                              onPressed: (_) async => _archiveAccount(acc),
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.archive, color: Colors.white),
                                  SizedBox(height: 4),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'Archive',
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
                              onPressed: (_) async => _deleteAccount(acc),
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
                    } catch (e, st) {
                      print('Error rendering account list tile: $e\n$st');
                      return const SizedBox.shrink();
                    }
                  })
                else ...[
                  // In reordering mode, allow reordering accounts within this group if not in groups-only mode
                  if (!_reorderGroupsOnly)
                    SizedBox(
                      height: displayAccounts.length * 78.0 + 8,
                      child: ReorderableListView(
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) newIndex -= 1;
                            final item = displayAccounts.removeAt(oldIndex);
                            displayAccounts.insert(newIndex, item);
                            // Update group-specific ordering
                            final ids = displayAccounts
                                .map((a) => a.id)
                                .toList();
                            _groupAccountOrder[title] = ids;
                          });
                          // Persist immediately
                          final newAccountOrder = <String>[];
                          if (_groupByIndex == 0) {
                            for (final type in _accountTypeOrder) {
                              final ids = _groupAccountOrder[type] ?? [];
                              newAccountOrder.addAll(ids);
                            }
                          } else {
                            for (final inst in _institutionOrder) {
                              final ids = _groupAccountOrder[inst] ?? [];
                              newAccountOrder.addAll(ids);
                            }
                          }
                          final allIds = DatabaseService.getAllAccounts()
                              .map((a) => a.id)
                              .toList();
                          for (final id in allIds) {
                            if (!newAccountOrder.contains(id)) {
                              newAccountOrder.add(id);
                            }
                          }
                          DatabaseService.setSetting(
                            'accountOrder',
                            newAccountOrder,
                          );
                          // Persist the current group ordering as well so institution/type
                          // orders remain in sync when users reorder accounts while
                          // grouped by a specific key.
                          if (_groupByIndex == 0) {
                            DatabaseService.setSetting(
                              'accountTypeOrder',
                              _accountTypeOrder,
                            );
                          } else {
                            DatabaseService.setSetting(
                              'accountInstitutionOrder',
                              _institutionOrder,
                            );
                          }
                          DatabaseService.accountsVersion.value++;
                        },
                        children: [
                          for (final acc in displayAccounts)
                            ListTile(
                              key: ValueKey(acc.id),
                              leading: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.drag_handle),
                                  const SizedBox(width: 10),
                                  _buildAccountTypeIcon(acc),
                                ],
                              ),
                              title: Text(
                                acc.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              trailing: Text(formatCurrency(acc.balance)),
                            ),
                        ],
                      ),
                    )
                  else
                    // If groups-only reorder is active, show the regular list but without drag handles
                    ...displayAccounts.map<Widget>((acc) {
                      try {
                        final displayAmount =
                            _hiddenBalances.contains(acc.id) || !acc.isActive
                            ? 0.0
                            : DatabaseService.getDisplayBalanceForAccount(
                                acc.id,
                                showAvailable: true,
                                includeCleared: false,
                              );
                        final balanceText = _hiddenBalances.contains(acc.id)
                            ? '•••'
                            : formatCurrency(displayAmount);
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6.0),
                          child: ListTile(
                            leading: _buildAccountTypeIcon(acc),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildFittedAccountText(
                                        acc.name,
                                        Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      if (_accountDetailLabel(acc) != null)
                                        _buildFittedAccountText(
                                          _accountDetailLabel(acc)!,
                                          Theme.of(context).textTheme.bodySmall,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      balanceText,
                                      style: _hiddenBalances.contains(acc.id)
                                          ? null
                                          : Theme.of(
                                              context,
                                            ).textTheme.bodyMedium?.copyWith(
                                              color: (displayAmount >= 0)
                                                  ? Colors.green
                                                  : Theme.of(
                                                      context,
                                                    ).colorScheme.error,
                                            ),
                                    ),
                                    if (!_hiddenBalances.contains(acc.id))
                                      Text(
                                        'Available',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Colors.grey,
                                              fontSize: 10,
                                              fontStyle: FontStyle.italic,
                                            ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      } catch (e, st) {
                        print(
                          'Error rendering account list tile (groups-only): $e\n$st',
                        );
                        return const SizedBox.shrink();
                      }
                    }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Reorder UI is integrated directly into the grouped list; no separate body needed.
}
