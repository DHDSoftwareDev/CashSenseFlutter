// ignore_for_file: deprecated_member_use, use_build_context_synchronously, unused_import

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../utils/formatters.dart';
import '../services/database_service.dart';
import '../services/lookups_sync_helper.dart';
import '../models/category.dart';
import '../widgets/app_color_picker.dart';
import '../widgets/category_selector_sheet.dart';
import '../utils/root_scaffold.dart';

bool _isDisplayableCategory(Category category) {
  final name = category.name.trim();
  if (name.isEmpty) return false;

  final normalized = name.toLowerCase();
  if (normalized == 'unknown' || normalized == 'unknown category') {
    return false;
  }

  final uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );
  if (uuid.hasMatch(name)) return false;

  final longToken = RegExp(r'^[A-Za-z0-9_-]{16,}$');
  if (longToken.hasMatch(name)) return false;

  return true;
}

class PayeesScreen extends StatefulWidget {
  const PayeesScreen({super.key});

  @override
  State<PayeesScreen> createState() => _PayeesScreenState();
}

class _PayeesScreenState extends State<PayeesScreen> {
  // true = show payees, false = show payers
  bool _showPayee = true;
  String _searchQuery = '';
  List<Map<String, dynamic>> _payees = [];

  @override
  void initState() {
    super.initState();
    _loadPayees();
    // Listen for payee changes made elsewhere in the app (e.g. add from selector)
    DatabaseService.payeesVersion.addListener(_onPayeesChanged);
    DatabaseService.categoriesVersion.addListener(_onCategoriesChanged);
  }

  void _onPayeesChanged() {
    if (!mounted) return;
    _loadPayees();
  }

  void _onCategoriesChanged() {
    if (!mounted) return;
    setState(() {});
  }

  // Opens a dialog with a search bar and list of available categories. Returns the selected category id or null.
  Future<String?> _pickCategory(
    BuildContext parentContext,
    bool isPayeeChoice,
    String? currentSelected,
  ) async {
    final selected = await showModalBottomSheet<String?>(
      context: parentContext,
      isScrollControlled: true,
      // Use an explicit sheetContext so we can reliably pop the bottom sheet
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.85,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(sheetContext),
            ),
            title: const Text('Select Category'),
            backgroundColor: Theme.of(parentContext).colorScheme.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add Category',
                onPressed: () async {
                  final nameController = TextEditingController();
                  Color selectedColor = const Color(0xFF607D8B);
                  final result = await showDialog<Category?>(
                    context: parentContext,
                    builder: (ctx) => StatefulBuilder(
                      builder: (ctx, setState) => AlertDialog(
                        title: const Text('Add Category'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: nameController,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                labelText: 'Name',
                              ),
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () async {
                                final picked = await showAppColorPicker(
                                  context: parentContext,
                                  initialColor: selectedColor,
                                  title: 'Pick Category Color',
                                );
                                if (picked != null) {
                                  setState(() => selectedColor = picked);
                                }
                              },
                              child: Row(
                                children: [
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: selectedColor,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.black26),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text('Category Color'),
                                  const Spacer(),
                                  const Icon(
                                    Icons.color_lens_outlined,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              if (nameController.text.trim().isNotEmpty) {
                                final newCat = Category(
                                  name: nameController.text.trim(),
                                  iconCodePoint: '0xe85d',
                                  colorValue: selectedColor.value.toString(),
                                  type: isPayeeChoice
                                      ? CategoryType.expense
                                      : CategoryType.income,
                                );
                                Navigator.pop(ctx, newCat);
                              }
                            },
                            child: const Text('Add'),
                          ),
                        ],
                      ),
                    ),
                  );
                  if (result != null) {
                    final newCatId = await DatabaseService.addCategory(result);
                    // Pop the bottom sheet using the sheetContext so the
                    // returned value reliably goes back to the caller of
                    // showModalBottomSheet.
                    Navigator.pop(sheetContext, newCatId);
                  }
                },
              ),
            ],
          ),
          body: CategorySelectorSheet(
            categories: (() {
              final categories = isPayeeChoice
                  ? DatabaseService.getAllCategories()
                        .where(
                          (c) =>
                              c.type == CategoryType.expense &&
                              _isDisplayableCategory(c),
                        )
                        .toList()
                  : DatabaseService.getAllCategories()
                        .where(
                          (c) =>
                              c.type == CategoryType.income &&
                              _isDisplayableCategory(c),
                        )
                        .toList();
              categories.sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              );
              return categories;
            })(),
            hideAddButton: true,
            allowedTypes: {
              isPayeeChoice ? CategoryType.expense : CategoryType.income,
            },
          ),
        ),
      ),
    );
    return selected;
  }

  void _loadPayees() {
    setState(() {
      _payees = DatabaseService.getAllPayees();
      _payees.sort((a, b) {
        final an = (a['name'] ?? '').toString().toLowerCase();
        final bn = (b['name'] ?? '').toString().toLowerCase();
        return an.compareTo(bn);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // Placeholder UI - actual payee/payer data can be wired to DatabaseService later
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: openRootDrawer,
        ),
        title: const Text('Payees / Payers'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add payee/payer',
            onPressed: () => _showAddPayeeDialog(),
          ),
        ],
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          Center(
            child: ToggleButtons(
              isSelected: [_showPayee, !_showPayee],
              onPressed: (i) {
                setState(() {
                  _showPayee = (i == 0);
                });
              },
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('Payees'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('Payers'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Search payees or payers',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) {
                setState(() {
                  _searchQuery = v.trim();
                });
              },
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildPayeesList()),
        ],
      ),
    );
  }

  @override
  void dispose() {
    DatabaseService.payeesVersion.removeListener(_onPayeesChanged);
    DatabaseService.categoriesVersion.removeListener(_onCategoriesChanged);
    super.dispose();
  }

  String _buildPlaceholderText() {
    final base = _showPayee ? 'No payees' : 'No payers';
    if (_searchQuery.isEmpty) return '$base.';
    return "$base found for '$_searchQuery'.";
  }

  void _showAddPayeeDialog() {
    final nameCtrl = TextEditingController();
    // Type is determined by _showPayee
    String? selectedCategoryId;
    String? categoryError;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final allCats = DatabaseService.getAllCategories();
          final availableCategories = allCats.where((c) {
            return _showPayee
                ? c.type == CategoryType.expense && _isDisplayableCategory(c)
                : c.type == CategoryType.income && _isDisplayableCategory(c);
          }).toList();

          if (availableCategories.isEmpty) {
            selectedCategoryId = null;
          } else if (selectedCategoryId != null &&
              !availableCategories.any((c) => c.id == selectedCategoryId)) {
            selectedCategoryId = null;
          }

          return AlertDialog(
            actionsAlignment: MainAxisAlignment.center,
            title: Center(child: Text('Add ${_showPayee ? 'Payee' : 'Payer'}')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 8),
                if (availableCategories.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () async {
                      final picked = await _pickCategory(
                        context,
                        _showPayee,
                        selectedCategoryId,
                      );
                      if (picked != null) {
                        setState(() {
                          selectedCategoryId = picked;
                          categoryError = null;
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Category'),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              selectedCategoryId == null
                                  ? 'Select Category'
                                  : (DatabaseService.getCategoryById(
                                          selectedCategoryId ?? '',
                                        )?.name ??
                                        ''),
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ),
                  ),
                  if (categoryError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      categoryError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ] else ...[
                  const SizedBox.shrink(),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) return;
                        if (availableCategories.isEmpty) {
                          setState(() {
                            categoryError =
                                'No ${_showPayee ? 'expense' : 'income'} categories available. Create one first.';
                          });
                          return;
                        }
                        if (selectedCategoryId == null) {
                          setState(() {
                            categoryError = 'Please select a category.';
                          });
                          return;
                        }
                        setState(() => isSaving = true);
                        final newPayee = {
                          'id': DateTime.now().microsecondsSinceEpoch
                              .toString(),
                          'name': name,
                          'type': _showPayee ? 'payee' : 'payer',
                          'categoryId': selectedCategoryId,
                        };
                        try {
                          await DatabaseService.addPayee(newPayee);
                          try {
                            await LookupsSyncHelper.syncPayeeOrPayer(newPayee);
                          } catch (_) {}
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          _loadPayees();
                        } finally {
                          if (context.mounted) {
                            setState(() => isSaving = false);
                          }
                        }
                      },
                child: isSaving ? const Text('Saving...') : const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPayeesList() {
    // Filter by type and search
    final filtered = _payees.where((p) {
      final isPayee = (p['type'] == 'payee');
      if (_showPayee != isPayee) return false;
      if (_searchQuery.isEmpty) return true;
      final name = (p['name'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();
    filtered.sort((a, b) {
      final an = (a['name'] ?? '').toString().toLowerCase();
      final bn = (b['name'] ?? '').toString().toLowerCase();
      return an.compareTo(bn);
    });

    if (filtered.isEmpty) {
      return Center(child: Text(_buildPlaceholderText()));
    }

    return SlidableAutoCloseBehavior(
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final p = filtered[index];

          Future<void> deletePayeeOrPayer() async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete'),
                content: Text('Delete "${p['name']}"? This cannot be undone.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (confirm == true) {
              await DatabaseService.deletePayee(p['id']);
              _loadPayees();
            }
          }

          return Slidable(
            key: ValueKey('payee_payer_swipe_${p['id']}'),
            startActionPane: ActionPane(
              motion: const DrawerMotion(),
              extentRatio: 0.25,
              children: [
                CustomSlidableAction(
                  onPressed: (_) async =>
                      _showPayeeDetails(Map<String, dynamic>.from(p)),
                  backgroundColor: Colors.blueGrey,
                  foregroundColor: Colors.white,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.visibility, color: Colors.white),
                      SizedBox(height: 4),
                      Text(
                        'View',
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
                  onPressed: (_) async => deletePayeeOrPayer(),
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
            child: Card(
              child: ListTile(
                title: Text(p['name'] ?? ''),
                subtitle: p['categoryId'] != null
                    ? Text(
                        DatabaseService.getCategoryById(
                              p['categoryId'],
                            )?.name ??
                            '',
                      )
                    : null,
                onTap: () async =>
                    _showEditPayeeDialog(Map<String, dynamic>.from(p)),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showPayeeDetails(Map<String, dynamic> payee) async {
    // Show dialog similar to category details: only Transaction Statistics -> count + total
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        actionsAlignment: MainAxisAlignment.center,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Theme.of(
                context,
              ).colorScheme.primary.withOpacity(0.12),
              child: Text(
                ((payee['name'] ?? '') as String).isNotEmpty
                    ? (payee['name'][0] ?? '').toString()
                    : '?',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                payee['name'] ?? 'Payee',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              'Transaction Statistics',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            FutureBuilder<int>(
              future: _getPayeeTransactionCount(payee),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return Text('${snapshot.data} transactions');
                } else {
                  return const Text('Loading...');
                }
              },
            ),
            const SizedBox(height: 8),
            FutureBuilder<double>(
              future: _getPayeeTotalAmount(payee),
              builder: (context, snap) {
                if (snap.hasData) {
                  return _buildDetailRow('Total', formatCurrency(snap.data));
                } else {
                  return const SizedBox.shrink();
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<int> _getPayeeTransactionCount(Map<String, dynamic> payee) async {
    final allTx = DatabaseService.getAllTransactions();
    final id = payee['id']?.toString() ?? '';
    final name = (payee['name'] ?? '').toString().toLowerCase();
    final txs = allTx.where((t) {
      try {
        if (t.note != null && id.isNotEmpty && t.note!.contains(id)) {
          return true;
        }
      } catch (_) {}
      try {
        if (t.description.toLowerCase().contains(name) && name.isNotEmpty) {
          return true;
        }
      } catch (_) {}
      return false;
    }).toList();
    return txs.length;
  }

  Future<double> _getPayeeTotalAmount(Map<String, dynamic> payee) async {
    final allTx = DatabaseService.getAllTransactions();
    final id = payee['id']?.toString() ?? '';
    final name = (payee['name'] ?? '').toString().toLowerCase();
    final txs = allTx.where((t) {
      try {
        if (t.note != null && id.isNotEmpty && t.note!.contains(id)) {
          return true;
        }
      } catch (_) {}
      try {
        if (t.description.toLowerCase().contains(name) && name.isNotEmpty) {
          return true;
        }
      } catch (_) {}
      return false;
    }).toList();
    return txs.fold<double>(0.0, (acc, t) => acc + t.amount);
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
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

  Future<void> _showEditPayeeDialog(Map<String, dynamic> payee) async {
    final nameCtrl = TextEditingController(text: payee['name'] ?? '');
    final isPayeeChoice = (payee['type'] ?? 'payee') == 'payee';

    // Start with no preselected category so the dropdown shows the hint; keep payee's existing selection if valid
    String? selectedCategoryId = payee['categoryId'];
    String? categoryError;
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          // Re-fetch categories so edits/adds done from the picker are visible immediately
          final allCats = DatabaseService.getAllCategories();
          final availableCategories = allCats.where((c) {
            return isPayeeChoice
                ? c.type == CategoryType.expense && _isDisplayableCategory(c)
                : c.type == CategoryType.income && _isDisplayableCategory(c);
          }).toList();

          if (availableCategories.isEmpty) {
            selectedCategoryId = null;
          } else if (selectedCategoryId != null &&
              !availableCategories.any((c) => c.id == selectedCategoryId)) {
            selectedCategoryId = null;
          }

          return AlertDialog(
            actionsAlignment: MainAxisAlignment.center,
            title: Center(
              child: Text('Edit ${isPayeeChoice ? 'Payee' : 'Payer'}'),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Type: ${isPayeeChoice ? 'Payee' : 'Payer'}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 8),
                if (availableCategories.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () async {
                      final picked = await _pickCategory(
                        context,
                        isPayeeChoice,
                        selectedCategoryId,
                      );
                      if (picked != null) {
                        setState(() {
                          selectedCategoryId = picked;
                          categoryError = null;
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Category'),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              selectedCategoryId == null
                                  ? 'Select Category'
                                  : (DatabaseService.getCategoryById(
                                          selectedCategoryId ?? '',
                                        )?.name ??
                                        ''),
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ),
                  ),
                  if (categoryError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      categoryError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ] else ...[
                  const SizedBox.shrink(),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) return;
                        if (availableCategories.isEmpty) {
                          setState(() {
                            categoryError =
                                'No ${isPayeeChoice ? 'expense' : 'income'} categories available. Create one first.';
                          });
                          return;
                        }
                        if (selectedCategoryId == null) {
                          setState(() {
                            categoryError = 'Please select a category.';
                          });
                          return;
                        }
                        setState(() => isSaving = true);
                        final updated = Map<String, dynamic>.from(payee)
                          ..['name'] = name
                          ..['type'] = isPayeeChoice ? 'payee' : 'payer'
                          ..['categoryId'] = selectedCategoryId;
                        try {
                          await DatabaseService.updatePayee(updated);
                          try {
                            await LookupsSyncHelper.syncPayeeOrPayer(updated);
                          } catch (_) {}
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          _loadPayees();
                        } finally {
                          if (context.mounted) {
                            setState(() => isSaving = false);
                          }
                        }
                      },
                child: isSaving ? const Text('Saving...') : const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }
}
