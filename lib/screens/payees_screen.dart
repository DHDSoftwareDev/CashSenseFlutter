// ignore_for_file: deprecated_member_use, use_build_context_synchronously, unused_import

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
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
    final colorScheme = Theme.of(context).colorScheme;

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
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
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
                  Expanded(child: _buildTypeOption('Payees', true)),
                  const SizedBox(width: 4),
                  Expanded(child: _buildTypeOption('Payers', false)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Search payees or payers',
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
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildPayeesList()),
        ],
      ),
    );
  }

  Widget _buildTypeOption(String label, bool payeeOption) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _showPayee == payeeOption;

    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: () => setState(() => _showPayee = payeeOption),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 46,
        decoration: BoxDecoration(
          color: selected ? colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (selected) ...[
              Icon(Icons.check_rounded, size: 19, color: colorScheme.onPrimary),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
              ),
            ),
          ],
        ),
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PayeeFormPage(
          isPayee: _showPayee,
          pickCategory: _pickCategory,
          onSaved: _loadPayees,
        ),
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
              builder: (dialogContext) {
                final colorScheme = Theme.of(dialogContext).colorScheme;
                final itemType = p['type'] == 'payer' ? 'Payer' : 'Payee';

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
                      Expanded(
                        child: Text(
                          'Delete $itemType?',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                  content: Text(
                    'Permanently delete "${p['name']}"? This action cannot be undone.',
                    style: Theme.of(dialogContext).textTheme.bodyMedium
                        ?.copyWith(
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
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
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
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
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
              await DatabaseService.deletePayee(p['id']);
              _loadPayees();
            }
          }

          return Slidable(
            key: ValueKey('payee_payer_swipe_${p['id']}'),
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
              elevation: 0,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.35),
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.55),
                  child: Text(
                    ((p['name'] ?? '') as String).isNotEmpty
                        ? (p['name'] as String)[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                title: Text(
                  p['name'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: p['categoryId'] != null
                    ? Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          DatabaseService.getCategoryById(p['categoryId'])?.name ?? '',
                        ),
                      )
                    : null,
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async =>
                    _showEditPayeeDialog(Map<String, dynamic>.from(p)),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showEditPayeeDialog(Map<String, dynamic> payee) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _EditPayeeFormPage(
          payee: payee,
          pickCategory: _pickCategory,
          onSaved: _loadPayees,
        ),
      ),
    );
  }

}

class _PayeeFormPage extends StatefulWidget {
  const _PayeeFormPage({
    required this.isPayee,
    required this.pickCategory,
    required this.onSaved,
  });

  final bool isPayee;
  final Future<String?> Function(BuildContext, bool, String?) pickCategory;
  final VoidCallback onSaved;

  @override
  State<_PayeeFormPage> createState() => _PayeeFormPageState();
}

class _PayeeFormPageState extends State<_PayeeFormPage> {
  final TextEditingController _nameCtrl = TextEditingController();
  String? _selectedCategoryId;
  String? _categoryError;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final availableCategories = DatabaseService.getAllCategories().where((c) {
      return widget.isPayee
          ? c.type == CategoryType.expense && _isDisplayableCategory(c)
          : c.type == CategoryType.income && _isDisplayableCategory(c);
    }).toList();

    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    if (availableCategories.isEmpty) {
      setState(() {
        _categoryError =
            'No ${widget.isPayee ? 'expense' : 'income'} categories available. Create one first.';
      });
      return;
    }

    if (_selectedCategoryId == null) {
      setState(() => _categoryError = 'Please select a category.');
      return;
    }

    setState(() => _isSaving = true);
    final newPayee = <String, dynamic>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'name': name,
      'type': widget.isPayee ? 'payee' : 'payer',
      'categoryId': _selectedCategoryId,
    };

    try {
      await DatabaseService.addPayee(newPayee);
      try {
        await LookupsSyncHelper.syncPayeeOrPayer(newPayee);
      } catch (_) {}
      if (!mounted) return;
      widget.onSaved();
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final category = _selectedCategoryId == null
        ? null
        : DatabaseService.getCategoryById(_selectedCategoryId!);

    return Scaffold(
      appBar: AppBar(
        title: Text('Add ${widget.isPayee ? 'Payee' : 'Payer'}'),
        centerTitle: true,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.isPayee ? 'PAYEE DETAILS' : 'PAYER DETAILS',
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
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: 'Name',
                        hintText: widget.isPayee ? 'Payee name' : 'Payer name',
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
                          final picked = await widget.pickCategory(
                            context,
                            widget.isPayee,
                            _selectedCategoryId,
                          );
                          if (picked != null && mounted) {
                            setState(() {
                              _selectedCategoryId = picked;
                              _categoryError = null;
                            });
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Icon(Icons.category_outlined, color: colorScheme.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Category',
                                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      category?.name ?? 'Select Category',
                                      style: Theme.of(context).textTheme.bodyLarge,
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_categoryError != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _categoryError!,
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ),
                    ],
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
                child: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('Add ${widget.isPayee ? 'Payee' : 'Payer'}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
class _EditPayeeFormPage extends StatefulWidget {
  const _EditPayeeFormPage({
    required this.payee,
    required this.pickCategory,
    required this.onSaved,
  });

  final Map<String, dynamic> payee;
  final Future<String?> Function(BuildContext, bool, String?) pickCategory;
  final VoidCallback onSaved;

  @override
  State<_EditPayeeFormPage> createState() => _EditPayeeFormPageState();
}

class _EditPayeeFormPageState extends State<_EditPayeeFormPage> {
  late final TextEditingController _nameCtrl;
  late final bool _isPayee;
  String? _selectedCategoryId;
  String? _categoryError;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.payee['name'] ?? '');
    _isPayee = (widget.payee['type'] ?? 'payee') == 'payee';
    _selectedCategoryId = widget.payee['categoryId'] as String?;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  List<Category> _availableCategories() {
    return DatabaseService.getAllCategories().where((c) {
      return _isPayee
          ? c.type == CategoryType.expense && _isDisplayableCategory(c)
          : c.type == CategoryType.income && _isDisplayableCategory(c);
    }).toList();
  }

  Future<void> _save() async {
    final availableCategories = _availableCategories();
    final name = _nameCtrl.text.trim();

    if (name.isEmpty) return;

    if (availableCategories.isEmpty) {
      setState(() {
        _categoryError =
            'No ${_isPayee ? 'expense' : 'income'} categories available. Create one first.';
      });
      return;
    }

    if (_selectedCategoryId == null ||
        !availableCategories.any((c) => c.id == _selectedCategoryId)) {
      setState(() => _categoryError = 'Please select a category.');
      return;
    }

    setState(() => _isSaving = true);

    final updated = Map<String, dynamic>.from(widget.payee)
      ..['name'] = name
      ..['type'] = _isPayee ? 'payee' : 'payer'
      ..['categoryId'] = _selectedCategoryId;

    try {
      await DatabaseService.updatePayee(updated);
      try {
        await LookupsSyncHelper.syncPayeeOrPayer(updated);
      } catch (_) {}

      if (!mounted) return;
      widget.onSaved();
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final category = _selectedCategoryId == null
        ? null
        : DatabaseService.getCategoryById(_selectedCategoryId!);

    return Scaffold(
      appBar: AppBar(
        title: Text('Edit ${_isPayee ? 'Payee' : 'Payer'}'),
        centerTitle: true,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isPayee ? 'PAYEE DETAILS' : 'PAYER DETAILS',
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
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: 'Name',
                        hintText: _isPayee ? 'Payee name' : 'Payer name',
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.55),
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
                    ),
                    const SizedBox(height: 14),
                    Material(
                      color: colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () async {
                          final picked = await widget.pickCategory(
                            context,
                            _isPayee,
                            _selectedCategoryId,
                          );
                          if (picked != null && mounted) {
                            setState(() {
                              _selectedCategoryId = picked;
                              _categoryError = null;
                            });
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.category_outlined,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Category',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      category?.name ?? 'Select Category',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge,
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_categoryError != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _categoryError!,
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ),
                    ],
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
                child: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('Save ${_isPayee ? 'Payee' : 'Payer'}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
