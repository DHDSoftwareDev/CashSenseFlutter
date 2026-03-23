import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/account.dart';
import '../utils/formatters.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reorder Accounts & Types'),
        actions: [
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              await _saveOrder();
              if (!mounted) return;
              navigator.pop(true);
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Mode toggle: Accounts | Types | Institutions
            Center(
              child: ToggleButtons(
                isSelected: [_modeIndex == 0, _modeIndex == 1, _modeIndex == 2],
                onPressed: (i) => setState(() => _modeIndex = i),
                children: const [
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Accounts')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Types')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Institutions')),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_modeIndex == 0) ...[
              const Text('Drag to reorder individual accounts'),
              const SizedBox(height: 8),
              Expanded(
                child: ReorderableListView.builder(
                  itemCount: _accounts.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = _accounts.removeAt(oldIndex);
                      _accounts.insert(newIndex, item);
                    });
                  },
                  itemBuilder: (context, index) {
                    final a = _accounts[index];
                    return ListTile(
                      key: ValueKey(a.id),
                      leading: const Icon(Icons.drag_handle),
                      title: Text(a.name),
                      subtitle: Text(a.typeDisplayName),
                      trailing: Text(formatCurrency(a.balance)),
                    );
                  },
                ),
              ),
            ] else if (_modeIndex == 1) ...[
              const SizedBox(height: 12),
              const Text('Drag to reorder account types (groups)'),
              const SizedBox(height: 8),
              Expanded(
                child: ReorderableListView(
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = _accountTypeOrder.removeAt(oldIndex);
                      _accountTypeOrder.insert(newIndex, item);
                    });
                  },
                  children: [
                    for (final t in _accountTypeOrder)
                      Card(
                        key: ValueKey('type_$t'),
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.drag_handle),
                              title: Text(t),
                              trailing: IconButton(
                                icon: Icon(_expandedTypes.contains(t) ? Icons.expand_less : Icons.expand_more),
                                onPressed: () {
                                  setState(() {
                                    if (_expandedTypes.contains(t)) {
                                      _expandedTypes.remove(t);
                                    } else {
                                      _expandedTypes.add(t);
                                    }
                                  });
                                },
                              ),
                            ),
                            if (_expandedTypes.contains(t))
                              Padding(
                                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                                child: Column(
                                  children: _accounts
                                      .where((a) => a.typeDisplayName == t)
                                      .map((a) => ListTile(
                                            title: Text(a.name),
                                          subtitle: Text(_institutionLabel(a) ?? ''),
                                            trailing: Text(formatCurrency(a.balance)),
                                          ))
                                      .toList(),
                                ),
                              ),
                          ],
                        ),
                      )
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              const Text('Drag to reorder institution groups'),
              const SizedBox(height: 8),
              Expanded(
                child: ReorderableListView(
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = _institutionOrder.removeAt(oldIndex);
                      _institutionOrder.insert(newIndex, item);
                    });
                  },
                  children: [
                    for (final inst in _institutionOrder)
                      Card(
                        key: ValueKey('inst_$inst'),
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.drag_handle),
                              title: Text(inst),
                              trailing: IconButton(
                                icon: Icon(_expandedInstitutions.contains(inst) ? Icons.expand_less : Icons.expand_more),
                                onPressed: () {
                                  setState(() {
                                    if (_expandedInstitutions.contains(inst)) {
                                      _expandedInstitutions.remove(inst);
                                    } else {
                                      _expandedInstitutions.add(inst);
                                    }
                                  });
                                },
                              ),
                            ),
                            if (_expandedInstitutions.contains(inst))
                              Padding(
                                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                                child: Column(
                  children: _accounts
                    .where((a) => _institutionKey(a) == inst)
                                      .map((a) => ListTile(
                                            title: Text(a.name),
                                            subtitle: Text(a.typeDisplayName),
                                            trailing: Text(formatCurrency(a.balance)),
                                          ))
                                      .toList(),
                                ),
                              ),
                          ],
                        ),
                      )
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
