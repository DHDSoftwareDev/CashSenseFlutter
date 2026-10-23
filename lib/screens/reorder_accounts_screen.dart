import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/account.dart';
import '../utils/formatters.dart';
import '../widgets/account_type_icon.dart';

class ReorderAccountsScreen extends StatefulWidget {
  const ReorderAccountsScreen({super.key});

  @override
  State<ReorderAccountsScreen> createState() => _ReorderAccountsScreenState();
}

class _ReorderAccountsScreenState extends State<ReorderAccountsScreen> {
  late List<Account> _accounts;
  late List<String> _accountOrder;
  late List<String> _accountTypeOrder;
  late List<String> _institutionOrder;
  final Set<String> _expandedInstitutions = {};
  final Set<String> _expandedTypes = {};
  int _modeIndex = 0; // 0 = accounts, 1 = types, 2 = institutions

  String? _institutionLabel(Account account) {
    final label = (account.institution ?? account.description ?? '').trim();
    return label.isEmpty ? null : label;
  }

  String? _institutionKey(Account account) => _institutionLabel(account);

  Widget _typeIcon(String typeName) {
    for (final account in _accounts) {
      if (account.typeDisplayName == typeName) {
        return AccountTypeIcon(
          type: account.type,
          displayName: account.typeDisplayName,
        );
      }
    }
    final normalized = typeName.toLowerCase();
    final fallbackType = normalized.contains('saving')
        ? AccountType.investment
        : normalized.contains('check')
        ? AccountType.bank
        : normalized.contains('card')
        ? AccountType.card
        : AccountType.cash;
    return AccountTypeIcon(type: fallbackType, displayName: typeName);
  }

  @override
  void initState() {
    super.initState();
    _accounts = DatabaseService.getAllAccounts();
    // Load saved order or default to current ordering by name
    final saved = DatabaseService.getSetting<List<dynamic>>('accountOrder', <dynamic>[]);
    if (saved != null && saved.isNotEmpty) {
      _accountOrder = saved.map((e) => e.toString()).toList();
      // Sort accounts to match saved order
      _accounts.sort((a, b) {
        final ai = _accountOrder.indexOf(a.id);
        final bi = _accountOrder.indexOf(b.id);
        if (ai == -1 && bi == -1) return a.name.compareTo(b.name);
        if (ai == -1) return 1;
        if (bi == -1) return -1;
        return ai.compareTo(bi);
      });
    } else {
      _accountOrder = _accounts.map((a) => a.id).toList();
    }

    final savedTypes = DatabaseService.getSetting<List<dynamic>>('accountTypeOrder', <dynamic>[]);
    // Build the discovered type list based on accounts the user has created
    final discovered = <String>[];
    final discoveredSeen = <String>{};
    for (final a in _accounts) {
      final display = a.typeDisplayName;
      if (!discoveredSeen.contains(display)) {
        discoveredSeen.add(display);
        discovered.add(display);
      }
    }

    if (savedTypes != null && savedTypes.isNotEmpty) {
      // Preserve saved order but only include types that are actually present
      // on accounts; then append any discovered types not in the saved order.
      final savedList = savedTypes.map((e) => e.toString()).toList();
      final merged = <String>[];
      final added = <String>{};
      for (final s in savedList) {
        if (discovered.contains(s) && !added.contains(s)) {
          merged.add(s);
          added.add(s);
        }
      }
      for (final d in discovered) {
        if (!added.contains(d)) {
          merged.add(d);
          added.add(d);
        }
      }
      _accountTypeOrder = merged;
    } else {
      _accountTypeOrder = discovered;
    }
    // Institution order (groups)
    final savedInst = DatabaseService.getSetting<List<dynamic>>('accountInstitutionOrder', <dynamic>[]);
    if (savedInst != null && savedInst.isNotEmpty) {
      // Merge saved institution order with any currently-seen institutions so
      // that previously persisted groups remain visible even if no accounts
      // currently belong to them. Preserve the saved ordering and append
      // any newly discovered institutions.
      final savedList = savedInst.map((e) => e.toString()).toList();
      final seen = <String>{};
      final merged = <String>[];
      for (final s in savedList) {
        merged.add(s);
        seen.add(s);
      }
      for (final a in _accounts) {
        // Only include accounts that have an explicit user-provided institution
        final key = _institutionKey(a);
        if (key != null) {
          if (!seen.contains(key)) {
            seen.add(key);
            merged.add(key);
          }
        }
      }
      _institutionOrder = merged;
    } else {
      // Build unique institution keys in encountered order.
      final seen = <String>{};
      final list = <String>[];
      for (final a in _accounts) {
        final key = _institutionKey(a);
        if (key != null) {
          if (!seen.contains(key)) {
            seen.add(key);
            list.add(key);
          }
        }
      }
      _institutionOrder = list;
    }
  }

  Future<void> _saveOrder() async {
    // Rebuild account order to reflect the current group ordering so that
    // accounts are shown in the same grouped order everywhere in the app.
    final allAccounts = DatabaseService.getAllAccounts();
    final newAccountOrder = <String>[];
    if (_accountTypeOrder.isNotEmpty) {
      for (final type in _accountTypeOrder) {
        for (final a in allAccounts) {
          if (a.typeDisplayName.toLowerCase() == type.toLowerCase()) {
            newAccountOrder.add(a.id);
          }
        }
      }
    }
    // If institution order is present, also ensure those groups are respected
    if (newAccountOrder.isEmpty && _institutionOrder.isNotEmpty) {
      for (final inst in _institutionOrder) {
        for (final a in allAccounts) {
          // Only match accounts that have an explicit, non-empty institution
          final key = _institutionKey(a);
          if (key != null && key.toLowerCase() == inst.toLowerCase()) {
            newAccountOrder.add(a.id);
          }
        }
      }
    }
    // Fallback: include any accounts not already included
    for (final a in allAccounts) {
      if (!newAccountOrder.contains(a.id)) newAccountOrder.add(a.id);
    }

    await DatabaseService.setSetting('accountOrder', newAccountOrder);
    await DatabaseService.setSetting('accountTypeOrder', _accountTypeOrder);
    await DatabaseService.setSetting('accountInstitutionOrder', _institutionOrder);
    // notify accountsVersion so screens refresh
    DatabaseService.accountsVersion.value++;
  }

  BoxDecoration _cardDecoration(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BoxDecoration(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: colorScheme.outlineVariant.withValues(alpha: 0.35),
      ),
    );
  }

  Widget _modeOption({
    required BuildContext context,
    required int index,
    required String label,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _modeIndex == index;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: () => setState(() => _modeIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 46,
          decoration: BoxDecoration(
            color: selected ? colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: selected
                  ? colorScheme.onPrimary
                  : colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _accountRow(Account account) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      key: ValueKey(account.id),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: _cardDecoration(context),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 6,
        ),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.drag_handle_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            AccountTypeIcon(
              type: account.type,
              displayName: account.typeDisplayName,
            ),
          ],
        ),
        title: Text(
          account.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        trailing: Text(
          formatCurrency(account.balance),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text(
          'Reorder Accounts',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              await _saveOrder();
              if (!mounted) return;
              navigator.pop(true);
            },
            child: const Text(
              'Save',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Column(
          children: [
            // MODERN MODE SELECTOR
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  _modeOption(
                    context: context,
                    index: 0,
                    label: 'Accounts',
                  ),
                  const SizedBox(width: 4),
                  _modeOption(
                    context: context,
                    index: 1,
                    label: 'Types',
                  ),
                  const SizedBox(width: 4),
                  _modeOption(
                    context: context,
                    index: 2,
                    label: 'Institutions',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            Row(
              children: [
                Icon(
                  Icons.drag_indicator_rounded,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _modeIndex == 0
                        ? 'Drag to reorder individual accounts'
                        : _modeIndex == 1
                            ? 'Drag to reorder account types'
                            : 'Drag to reorder institution groups',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            if (_modeIndex == 0)
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: _accounts.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = _accounts.removeAt(oldIndex);
                      _accounts.insert(newIndex, item);
                    });
                  },
                  itemBuilder: (context, index) {
                    return _accountRow(_accounts[index]);
                  },
                ),
              )
            else if (_modeIndex == 1)
              Expanded(
                child: ReorderableListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = _accountTypeOrder.removeAt(oldIndex);
                      _accountTypeOrder.insert(newIndex, item);
                    });
                  },
                  children: [
                    for (final type in _accountTypeOrder)
                      Container(
                        key: ValueKey('type_$type'),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: _cardDecoration(context),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 5,
                              ),
                              leading: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.drag_handle_rounded,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  _typeIcon(type),
                                ],
                              ),
                              title: Text(
                                type,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              trailing: IconButton(
                                tooltip: _expandedTypes.contains(type)
                                    ? 'Collapse'
                                    : 'Expand',
                                icon: Icon(
                                  _expandedTypes.contains(type)
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                ),
                                onPressed: () {
                                  setState(() {
                                    if (_expandedTypes.contains(type)) {
                                      _expandedTypes.remove(type);
                                    } else {
                                      _expandedTypes.add(type);
                                    }
                                  });
                                },
                              ),
                            ),
                            if (_expandedTypes.contains(type))
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  12,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.28),
                                  border: Border(
                                    top: BorderSide(
                                      color: colorScheme.outlineVariant
                                          .withValues(alpha: 0.30),
                                    ),
                                  ),
                                ),
                                child: Column(
                                  children: _accounts
                                      .where(
                                        (a) =>
                                            a.typeDisplayName == type,
                                      )
                                      .map(
                                        (a) => ListTile(
                                          dense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          leading: AccountTypeIcon(
                                            type: a.type,
                                            displayName: a.typeDisplayName,
                                          ),
                                          title: Text(a.name),
                                          subtitle: Text(
                                            _institutionLabel(a) ?? '',
                                          ),
                                          trailing: Text(
                                            formatCurrency(a.balance),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              )
            else
              Expanded(
                child: ReorderableListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = _institutionOrder.removeAt(oldIndex);
                      _institutionOrder.insert(newIndex, item);
                    });
                  },
                  children: [
                    for (final institution in _institutionOrder)
                      Container(
                        key: ValueKey('inst_$institution'),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: _cardDecoration(context),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 5,
                              ),
                              leading: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(
                                  Icons.drag_handle_rounded,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              title: Text(
                                institution,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              trailing: IconButton(
                                tooltip:
                                    _expandedInstitutions.contains(institution)
                                        ? 'Collapse'
                                        : 'Expand',
                                icon: Icon(
                                  _expandedInstitutions.contains(institution)
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                ),
                                onPressed: () {
                                  setState(() {
                                    if (_expandedInstitutions
                                        .contains(institution)) {
                                      _expandedInstitutions
                                          .remove(institution);
                                    } else {
                                      _expandedInstitutions.add(institution);
                                    }
                                  });
                                },
                              ),
                            ),
                            if (_expandedInstitutions.contains(institution))
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  12,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.28),
                                  border: Border(
                                    top: BorderSide(
                                      color: colorScheme.outlineVariant
                                          .withValues(alpha: 0.30),
                                    ),
                                  ),
                                ),
                                child: Column(
                                  children: _accounts
                                      .where(
                                        (a) =>
                                            _institutionKey(a) ==
                                            institution,
                                      )
                                      .map(
                                        (a) => ListTile(
                                          dense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          leading: AccountTypeIcon(
                                            type: a.type,
                                            displayName: a.typeDisplayName,
                                          ),
                                          title: Text(a.name),
                                          trailing: Text(
                                            formatCurrency(a.balance),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
