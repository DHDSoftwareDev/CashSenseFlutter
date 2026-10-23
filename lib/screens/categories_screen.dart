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
      _categories.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
            onPressed: _showAddCategoryDialog,
          ),
        ],
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(11),
                      onTap: () {
                        setState(() {
                          _showExpense = true;
                          _applyCategoryFilter();
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        height: 46,
                        decoration: BoxDecoration(
                          color: _showExpense ? colorScheme.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_showExpense) ...[
                              Icon(Icons.check_rounded, size: 19, color: colorScheme.onPrimary),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              'Expense',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _showExpense ? colorScheme.onPrimary : colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(11),
                      onTap: () {
                        setState(() {
                          _showExpense = false;
                          _applyCategoryFilter();
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        height: 46,
                        decoration: BoxDecoration(
                          color: !_showExpense ? colorScheme.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (!_showExpense) ...[
                              Icon(Icons.check_rounded, size: 19, color: colorScheme.onPrimary),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              'Income',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: !_showExpense ? colorScheme.onPrimary : colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search categories',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
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
                  borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onChanged: (v) {
                setState(() {
                  _searchQuery = v.trim().toLowerCase();
                  _applyCategoryFilter();
                });
              },
            ),
          ),
          const SizedBox(height: 12),
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
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                leading: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: category.color.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: category.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                title: Text(
                  category.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: category.budgetLimit != null
                    ? Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text('Budget: ${formatCurrency(category.budgetLimit)}'),
                      )
                    : null,
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async => _handleCategoryMenuSelection('edit', category),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleCategoryMenuSelection(String value, Category category) async {
    if (value == 'edit') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _CategoryFormPage(
            title: 'Edit Category',
            buttonLabel: 'Save Category',
            initialName: category.name,
            initialColor: category.color,
            onSave: (name, selectedColor) async {
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
            },
          ),
        ),
      );
      if (mounted) _loadCategories();
      return;
    }

    if (value == 'delete') {
      final confirm = await showDialog<bool>(
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
                    'Delete Category?',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                    ),
                  ),
                ),
              ],
            ),
            content: Text(
              'Permanently delete "${category.name}"? This action cannot be undone.',
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
                        onPressed: () => Navigator.pop(dialogContext, false),
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
                        onPressed: () => Navigator.pop(dialogContext, true),
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
      if (confirm == true) {
        await DatabaseService.deleteCategory(category.id);
        _loadCategories();
      }
      return;
    }
  }

  void _showAddCategoryDialog() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => _CategoryFormPage(
              title: 'Add Category',
              buttonLabel: 'Add Category',
              initialColor: const Color(0xFFEF5350),
              onSave: (name, selectedColor) async {
                final newCat = Category(
                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                  name: name,
                  iconCodePoint: Icons.category.codePoint.toString(),
                  colorValue: selectedColor.value.toString(),
                  type: _showExpense ? CategoryType.expense : CategoryType.income,
                );
                await DatabaseService.addCategory(newCat);
              },
            ),
          ),
        )
        .then((_) {
          if (mounted) _loadCategories();
        });
  }

}


class _CategoryFormPage extends StatefulWidget {
  final String title;
  final String buttonLabel;
  final String initialName;
  final Color initialColor;
  final Future<void> Function(String name, Color color) onSave;

  const _CategoryFormPage({
    required this.title,
    required this.buttonLabel,
    required this.initialColor,
    required this.onSave,
    this.initialName = '',
  });

  @override
  State<_CategoryFormPage> createState() => _CategoryFormPageState();
}

class _CategoryFormPageState extends State<_CategoryFormPage> {
  late final TextEditingController _nameCtrl;
  late Color _selectedColor;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _selectedColor = widget.initialColor;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      await widget.onSave(name, _selectedColor);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'CATEGORY DETAILS',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Name',
                      hintText: 'Category name',
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
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
                        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Material(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () async {
                        final picked = await showAppColorPicker(
                          context: context,
                          initialColor: _selectedColor,
                          title: 'Pick Category Color',
                        );
                        if (picked != null && mounted) {
                          setState(() => _selectedColor = picked);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        child: Row(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: _selectedColor,
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(color: colorScheme.outlineVariant),
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Text(
                                'Category Color',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            Icon(Icons.palette_outlined, color: colorScheme.primary),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSaving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(_isSaving ? 'Saving...' : widget.buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}
