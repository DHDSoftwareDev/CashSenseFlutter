// ignore_for_file: avoid_print, unused_field, prefer_final_fields

import '../widgets/banner_ad_widget.dart';
// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../services/database_service.dart';
import '../utils/formatters.dart';
import '../models/account.dart';
import 'add_account_screen.dart';
// Reordering is handled inline in this screen.
import '../utils/root_scaffold.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
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
    _groupByIndex = DatabaseService.getSetting<int>('accountsGroupByIndex', 0) ?? 0;
    // No longer load per-account display preferences; always show available balance
    // Load persisted hidden balances so they survive app restarts
    try {
      final raw = DatabaseService.getSetting<List<dynamic>>('hiddenAccountBalances', <dynamic>[]);
      if (raw != null) {
        for (final e in raw) {
          if (e != null) _hiddenBalances.add(e.toString());
        }
      }
    } catch (_) {}
    // Load persisted expanded groups so the UI remembers collapsed state between launches
    try {
      final raw = DatabaseService.getSetting<List<dynamic>>('expandedAccountGroups', <dynamic>[]);
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
    final savedAccountOrderRaw = DatabaseService.getSetting<List<dynamic>>('accountOrder', accIds);
    _accountOrder = (savedAccountOrderRaw ?? accIds).map((e) => e.toString()).toList();

    final savedTypeOrderRaw = DatabaseService.getSetting<List<dynamic>>('accountTypeOrder', <dynamic>[]);
    _accountTypeOrder = (savedTypeOrderRaw ?? <dynamic>[]).map((e) => e.toString()).toList();
    if (_accountTypeOrder.isEmpty) {
      _accountTypeOrder = allAccounts.map((a) => a.typeDisplayName).toSet().toList();
    }

    final savedInstRaw = DatabaseService.getSetting<List<dynamic>>('accountInstitutionOrder', <dynamic>[]);
    _institutionOrder = (savedInstRaw ?? <dynamic>[]).map((e) => e.toString()).toList();
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

  Future<void> _openAccountTransactions(Account acc) async {
    navigateToRootPage(1, accountId: acc.id);
  }

  Future<void> _archiveAccount(Account acc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive account'),
        content: Text('Archive "${acc.name}"? This will hide it from lists.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Archive')),
        ],
      ),
    );
    if (confirmed != true) return;
    final updated = acc.copyWith(isActive: false);
    await DatabaseService.updateAccount(updated);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).clearSnackBars();
  }

  Future<void> _deleteAccount(Account acc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account'),
        content: Text('Are you sure you want to permanently delete "${acc.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    await DatabaseService.deleteAccount(acc.id);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).clearSnackBars();
  }

  Future<void> _editAccount(Account acc) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddAccountScreen(account: acc)),
    );
    if (!mounted) return;
    if (result == true) setState(() {});
  }

  Future<void> _toggleAccountBalanceHidden(Account acc) async {
    setState(() {
      if (_hiddenBalances.contains(acc.id)) {
        _hiddenBalances.remove(acc.id);
      } else {
        _hiddenBalances.add(acc.id);
      }
    });
    try {
      await DatabaseService.setSetting('hiddenAccountBalances', _hiddenBalances.toList());
    } catch (_) {}
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
                  child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                ),
                // Toggle between reordering groups (headers) and accounts within groups
                IconButton(
                  icon: Icon(_reorderGroupsOnly ? Icons.view_module : Icons.list),
                  tooltip: _reorderGroupsOnly ? 'Reorder groups' : 'Reorder accounts',
                  onPressed: () {
                    setState(() {
                      _reorderGroupsOnly = !_reorderGroupsOnly;
                    });
                  },
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
                    final groupKeys = (_groupByIndex == 0) ? _accountTypeOrder : _institutionOrder;
                    final availableGroupKeys = _groupAccountOrder.keys.toList();
                    final useKeys = (groupKeys.isNotEmpty && groupKeys.any((k) => _groupAccountOrder.containsKey(k)))
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
                    final allIds = DatabaseService.getAllAccounts().map((a) => a.id).toList();
                    for (final id in allIds) {
                      if (!newAccountOrder.contains(id)) newAccountOrder.add(id);
                    }

                    await DatabaseService.setSetting('accountOrder', newAccountOrder);
                    // Persist the group ordering that was actually used so
                    // future screens apply the same visual grouping.
                    if (_groupByIndex == 0) {
                      await DatabaseService.setSetting('accountTypeOrder', useKeys);
                    } else {
                      await DatabaseService.setSetting('accountInstitutionOrder', useKeys);
                    }
                    DatabaseService.accountsVersion.value++;
                    if (!mounted) return;
                    setState(() {
                      _isReordering = false;
                    });
                  },
                  child: const Text('Save', style: TextStyle(color: Colors.white)),
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
                        if (!grouped[key]!.contains(a.id)) grouped[key]!.add(a.id);
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
                        if (!grouped[key]!.contains(a.id)) grouped[key]!.add(a.id);
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
                    final isSubscriber = DatabaseService.subscriptionVersion.value != 'Free';
                    final accounts = DatabaseService.getAllAccounts();
                    if (!isSubscriber && accounts.length >= 3) {
                      // Show feedback dialog for free users who reached the limit
                      await showDialog(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Account Limit Reached'),
                          content: const Text('Free users can create up to 3 accounts. Subscribe for unlimited accounts.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('OK')),
                          ],
                        ),
                      );
                      return;
                    }
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AddAccountScreen()),
                    );
                    if (!mounted) return;
                    if (result == true) setState(() {});
                  },
                ),
              ],
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Group by toggle (centered)
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Group by:'),
                  const SizedBox(width: 8),
                  ToggleButtons(
                    isSelected: [_groupByIndex == 0, _groupByIndex == 1],
                    onPressed: (i) async {
                      setState(() => _groupByIndex = i);
                      await DatabaseService.setSetting('accountsGroupByIndex', i);
                    },
                    children: const [
                      Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Type')),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Institution')),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _buildGroupedAccountsList(accounts),
            ),
            const SizedBox(height: 16),
            // You can swap BannerAdWidget with NativeAdWidget if you want native ads
            const BannerAdWidget(),
          ],
        ),
      ),
      ),
    );
  }

  @override
  void dispose() {
    DatabaseService.accountsVersion.removeListener(_onAccountsChanged);
    DatabaseService.transactionsVersion.removeListener(_onAccountsChanged);
    super.dispose();
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
          final ai = _accountTypeOrder.indexWhere((e) => e.toLowerCase() == a.key.toLowerCase());
          final bi = _accountTypeOrder.indexWhere((e) => e.toLowerCase() == b.key.toLowerCase());
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
            final allIds = DatabaseService.getAllAccounts().map((a) => a.id).toList();
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
                child: _buildAccountGroup(title: entry.key, accounts: entry.value),
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
        final ai = _institutionOrder.indexWhere((e) => e.toLowerCase() == a.key.toLowerCase());
        final bi = _institutionOrder.indexWhere((e) => e.toLowerCase() == b.key.toLowerCase());
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
        final allIds = DatabaseService.getAllAccounts().map((a) => a.id).toList();
        for (final id in allIds) {
          if (!newAccountOrder.contains(id)) newAccountOrder.add(id);
        }
        DatabaseService.setSetting('accountOrder', newAccountOrder);
        DatabaseService.setSetting('accountInstitutionOrder', _institutionOrder);
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

  Widget _buildAccountGroup({required String title, required List<Account> accounts}) {
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
            await DatabaseService.setSetting('expandedAccountGroups', _expandedGroups.toList());
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
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
        // Compute totals for this group
        Builder(builder: (context) {
              // Calculate total based on available balances only
              final double groupTotal = displayAccounts.fold(0.0, (s, a) {
                if (_hiddenBalances.contains(a.id) || !a.isActive) return s;
                final displayAmount = DatabaseService.getDisplayBalanceForAccount(a.id, showAvailable: true, includeCleared: true);
                return s + displayAmount;
              });
              final totalColor = groupTotal >= 0 ? Colors.green : Theme.of(context).colorScheme.error;
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox.shrink(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Total: ${formatCurrency(groupTotal)}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: totalColor)),
                      Text('Available Balance', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey, fontStyle: FontStyle.italic)),
                    ],
                  ),
                ],
              );
        }),
        const SizedBox(height: 8),
        if (!_isReordering) ...displayAccounts.map<Widget>((acc) {
      final displayAmount = _hiddenBalances.contains(acc.id) || !acc.isActive
        ? 0.0
        : DatabaseService.getDisplayBalanceForAccount(acc.id, showAvailable: true, includeCleared: true);
      final balanceText = _hiddenBalances.contains(acc.id)
        ? '•••'
        : formatCurrency(displayAmount);
          try {
            final card = Card(
              margin: const EdgeInsets.symmetric(vertical: 6.0),
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet),
                title: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(acc.name, style: Theme.of(context).textTheme.titleMedium),
                          if (_institutionLabel(acc) != null)
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    acc.accountNumber != null && acc.accountNumber!.isNotEmpty
                                        ? '${_institutionLabel(acc)!} - ${acc.accountNumber!}'
                                        : (_extractNumberFromDescription(_institutionLabel(acc)) != null
                                            ? '${_institutionLabel(acc)!} - ${_extractNumberFromDescription(_institutionLabel(acc))!}'
                                            : _institutionLabel(acc)!),
                                    style: Theme.of(context).textTheme.bodySmall,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(acc.typeDisplayName),
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
                              : Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: (displayAmount >= 0) ? Colors.green : Theme.of(context).colorScheme.error,
                                ),
                        ),
                        if (!_hiddenBalances.contains(acc.id))
                          Text(
                            'Available',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                    backgroundColor: Theme.of(context).colorScheme.primary,
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
                          style: TextStyle(color: Colors.white, fontSize: 11, height: 1.1),
                        ),
                      ],
                    ),
                  ),
                  CustomSlidableAction(
                    onPressed: (_) async => _toggleAccountBalanceHidden(acc),
                    backgroundColor: Colors.blueGrey,
                    foregroundColor: Colors.white,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isHidden ? Icons.visibility : Icons.visibility_off,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isHidden ? 'Show\nBalance' : 'Hide\nBalance',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          softWrap: false,
                          overflow: TextOverflow.visible,
                          style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.1),
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
                            style: TextStyle(color: Colors.white, fontSize: 11, height: 1.1),
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
                          style: TextStyle(color: Colors.white, fontSize: 11, height: 1.1),
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
                        final ids = displayAccounts.map((a) => a.id).toList();
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
                      final allIds = DatabaseService.getAllAccounts().map((a) => a.id).toList();
                      for (final id in allIds) {
                        if (!newAccountOrder.contains(id)) newAccountOrder.add(id);
                      }
                      DatabaseService.setSetting('accountOrder', newAccountOrder);
                      // Persist the current group ordering as well so institution/type
                      // orders remain in sync when users reorder accounts while
                      // grouped by a specific key.
                      if (_groupByIndex == 0) {
                        DatabaseService.setSetting('accountTypeOrder', _accountTypeOrder);
                      } else {
                        DatabaseService.setSetting('accountInstitutionOrder', _institutionOrder);
                      }
                      DatabaseService.accountsVersion.value++;
                    },
                    children: [
                      for (final acc in displayAccounts)
                        ListTile(
                          key: ValueKey(acc.id),
                          leading: const Icon(Icons.drag_handle),
                          title: Text(acc.name, style: Theme.of(context).textTheme.titleMedium),
                          subtitle: Text(acc.typeDisplayName),
                          trailing: Text(formatCurrency(acc.balance)),
                        )
                    ],
                  ),
                )
              else
                // If groups-only reorder is active, show the regular list but without drag handles
                ...displayAccounts.map<Widget>((acc) {
                  try {
                    final displayAmount = _hiddenBalances.contains(acc.id) || !acc.isActive
                        ? 0.0
                        : DatabaseService.getDisplayBalanceForAccount(acc.id, showAvailable: true, includeCleared: false);
                    final balanceText = _hiddenBalances.contains(acc.id) ? '•••' : formatCurrency(displayAmount);
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6.0),
                      child: ListTile(
                        leading: const Icon(Icons.account_balance_wallet),
                        title: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(acc.name, style: Theme.of(context).textTheme.titleMedium),
                                  if (_institutionLabel(acc) != null)
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            acc.accountNumber != null && acc.accountNumber!.isNotEmpty
                                                ? '${_institutionLabel(acc)!} - ${acc.accountNumber!}'
                                                : (_extractNumberFromDescription(_institutionLabel(acc)) != null
                                                    ? '${_institutionLabel(acc)!} - ${_extractNumberFromDescription(_institutionLabel(acc))!}'
                                                    : _institutionLabel(acc)!),
                                            style: Theme.of(context).textTheme.bodySmall,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(acc.typeDisplayName),
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
                                      : Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: (displayAmount >= 0) ? Colors.green : Theme.of(context).colorScheme.error,
                                        ),
                                ),
                                if (!_hiddenBalances.contains(acc.id))
                                  Text(
                                    'Available',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                    print('Error rendering account list tile (groups-only): $e\n$st');
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
