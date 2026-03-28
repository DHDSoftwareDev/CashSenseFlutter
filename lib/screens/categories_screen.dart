// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../utils/formatters.dart';
import '../services/database_service.dart';
import '../models/category.dart';
import '../widgets/app_color_picker.dart';
import '../utils/root_scaffold.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  List<Category> _allCategories = [];
  List<Category> _categories = [];
  // true = show expense categories, false = show income categories
  bool _showExpense = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadCategories();
    // Listen for category changes happening elsewhere (e.g. from payee picker)
    DatabaseService.categoriesVersion.addListener(_onCategoriesVersionChanged);
  }

  @override
  void dispose() {
    DatabaseService.categoriesVersion.removeListener(_onCategoriesVersionChanged);
    super.dispose();
  }

  void _onCategoriesVersionChanged() {
    // Reload categories when the global version increments
    _loadCategories();
  }

  void _loadCategories() {
    setState(() {
      _allCategories = DatabaseService.getAllCategories();
      _applyCategoryFilter();
    });
  }

  void _applyCategoryFilter() {
    setState(() {
      bool isUnknownCategoryName(String value) {
        final normalized = value.trim().toLowerCase();
        return normalized.isEmpty || normalized == 'unknown category' || normalized == 'unknown';
      }

      bool looksOpaqueId(String value) {
        final v = value.trim();
        if (v.isEmpty) return false;
        final uuid = RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
        );
        if (uuid.hasMatch(v)) return true;
        final longToken = RegExp(r'^[A-Za-z0-9_-]{16,}$');
        return longToken.hasMatch(v);
      }

      // Prefer an explicit kind/type field on Category if available.
      // If `Category` has a `kind` or `isIncome` field, use it. Otherwise
      // fall back to the seeded DefaultCategories lists (heuristic).
      bool categoryIsIncome(Category c) {
        try {
          // Try common field names safely using `dynamic` access.
          final dyn = c as dynamic;
          if (dyn.type != null) {
            final t = dyn.type;
            if (t is CategoryType) return t == CategoryType.income;
            if (t is String) return t.toLowerCase().contains('income');
          }
          if (dyn.kind != null) {
            // Accept enum/string values: 'income' or CategoryKind.income
            final k = dyn.kind;
            if (k is String) return k.toLowerCase() == 'income';
            if (k.toString().toLowerCase().contains('income')) return true;
          }
          if (dyn.isIncome != null) return dyn.isIncome == true;
        } catch (_) {}

        // Fallback heuristic: match against seeded DefaultCategories lists.
        return DefaultCategories.incomeCategories.any((d) => d.name == c.name);
      }

      final query = _searchQuery.toLowerCase();
      if (_showExpense) {
        _categories = _allCategories.where((c) {
          final name = c.name.trim();
          final isDisplayable = !isUnknownCategoryName(name) && !looksOpaqueId(name);
          final isIncome = categoryIsIncome(c);
          final matchesQuery = query.isEmpty || name.toLowerCase().contains(query);
          return isDisplayable && !isIncome && matchesQuery;
        }).toList();
      } else {
        _categories = _allCategories.where((c) {
          final name = c.name.trim();
          final isDisplayable = !isUnknownCategoryName(name) && !looksOpaqueId(name);
          final isIncome = categoryIsIncome(c);
          final matchesQuery = query.isEmpty || name.toLowerCase().contains(query);
          return isDisplayable && isIncome && matchesQuery;
        }).toList();
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
  title: const Text('Categories'),
  centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add category',
            onPressed: () => _showAddCategoryDialog(),
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
              isSelected: [_showExpense, !_showExpense],
              onPressed: (i) {
                setState(() {
                  _showExpense = (i == 0);
                  _applyCategoryFilter();
                });
              },
              children: const [
                Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Expense')),
                Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Income')),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search categories',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) {
                setState(() {
                  _searchQuery = v.trim().toLowerCase();
                  _applyCategoryFilter();
                });
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _categories.isEmpty ? _buildEmptyState() : _buildCategoriesList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.category,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No categories found',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Default categories should be available',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesList() {
    return SlidableAutoCloseBehavior(
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          return Slidable(
            key: ValueKey('category_swipe_${category.id}'),
            startActionPane: ActionPane(
              motion: const DrawerMotion(),
              extentRatio: 0.25,
              children: [
                CustomSlidableAction(
                  onPressed: (_) async => _handleCategoryMenuSelection('view', category),
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
                        style: TextStyle(color: Colors.white, fontSize: 11, height: 1.1),
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
                  onPressed: (_) async => _handleCategoryMenuSelection('delete', category),
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
                        style: TextStyle(color: Colors.white, fontSize: 11, height: 1.1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            child: Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: category.color,
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(category.name),
                subtitle: category.budgetLimit != null
                    ? Text('Budget: ${formatCurrency(category.budgetLimit)}')
                    : null,
                onTap: () async => _handleCategoryMenuSelection('edit', category),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleCategoryMenuSelection(String value, Category category) async {
    if (value == 'view') {
      _showCategoryDetails(category);
      return;
    }

    if (value == 'edit') {
  final nameCtrl = TextEditingController(text: category.name);
  Color selectedColor = category.color;
      await showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            actionsAlignment: MainAxisAlignment.center,
            title: const Center(child: Text('Edit Category')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final picked = await showAppColorPicker(
                      context: context,
                      initialColor: selectedColor,
                      title: 'Pick Category Color',
                    );
                    if (picked != null) setState(() => selectedColor = picked);
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
                      const Icon(Icons.color_lens_outlined, size: 20),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  final edited = Category(
                    id: category.id,
                    name: name,
                    iconCodePoint: category.iconCodePoint,
                    colorValue: selectedColor.value.toString(),
                    isDefault: category.isDefault,
                    budgetLimit: null,
                    image: null,
                    type: _showExpense ? CategoryType.expense : CategoryType.income,
                  );
                  await DatabaseService.updateCategory(edited);
                  await DatabaseService.updateCategoryReferences(edited);
                  if (!mounted) return;
                  Navigator.pop(context);
                  _loadCategories();
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
      return;
    }

    if (value == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete category'),
          content: Text('Delete "${category.name}"? This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
          ],
        ),
      );
      if (confirm == true) {
        await DatabaseService.deleteCategory(category.id);
        _loadCategories();
      }
      return;
    }
  }

  void _showCategoryDetails(Category category) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        actionsAlignment: MainAxisAlignment.center,
        title: Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: category.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                category.name,
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
            if (category.budgetLimit != null)
              _buildDetailRow('Budget Limit', '\$${category.budgetLimit!.toStringAsFixed(2)}'),
            const SizedBox(height: 16),
            Text(
              'Transaction Statistics',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            FutureBuilder<int>(
              future: _getCategoryTransactionCount(category.id),
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
              future: _getCategoryTotalAmount(category.id),
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

  Future<int> _getCategoryTransactionCount(String categoryId) async {
    return DatabaseService.getTransactionsByCategory(categoryId).length;
  }
  
  Future<double> _getCategoryTotalAmount(String categoryId) async {
    final txs = DatabaseService.getTransactionsByCategory(categoryId);
    return txs.fold<double>(0.0, (acc, t) => acc + (t.amount));
  }

  void _showAddCategoryDialog() {
  final nameCtrl = TextEditingController();
  Color selectedColor = Color(0xFFEF5350);
  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        actionsAlignment: MainAxisAlignment.center,
        title: const Center(child: Text('Add Category')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final picked = await showAppColorPicker(
                  context: context,
                  initialColor: selectedColor,
                  title: 'Pick Category Color',
                );
                if (picked != null) setState(() => selectedColor = picked);
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
                  const Icon(Icons.color_lens_outlined, size: 20),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final nav = Navigator.of(context);
              try {
                final iconCodePoint = Icons.category.codePoint.toString();
                final colorValue = selectedColor.value.toString();
                final newCat = Category(
                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                  name: name,
                  iconCodePoint: iconCodePoint,
                  colorValue: colorValue,
                  type: _showExpense ? CategoryType.expense : CategoryType.income,
                );
                await DatabaseService.addCategory(newCat);
                nav.pop();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.blueGrey[400]));
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}

}