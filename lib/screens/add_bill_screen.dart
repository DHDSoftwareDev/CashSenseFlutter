// ignore_for_file: unused_element, deprecated_member_use, no_leading_underscores_for_local_identifiers, curly_braces_in_flow_control_structures, unused_import

import '../services/account_operations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/bill.dart';
import '../utils/bill_note_utils.dart';
import '../models/transaction.dart';
import '../models/category.dart';
import '../models/account.dart';
import '../services/database_service.dart';
import '../services/bill_reminder_service.dart';
import '../services/lookups_sync_helper.dart';
import '../widgets/app_color_picker.dart';
import '../widgets/account_type_icon.dart';
import 'package:uuid/uuid.dart';

Category? _findCategoryById(Iterable<Category> categories, String? id) {
  if (id == null || id.isEmpty) return null;
  for (final category in categories) {
    if (category.id == id) return category;
  }
  return null;
}

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

class AddBillScreen extends StatefulWidget {
  final Bill? existingBill;
  final bool isDuplicate;

  const AddBillScreen({super.key, this.existingBill, this.isDuplicate = false});

  @override
  State<AddBillScreen> createState() => _AddBillScreenState();
}

// Top-level category selector page with search and add
class _CategorySelectorSheet extends StatefulWidget {
  final List<Category> categories;
  final String? initialSelectedId;
  final BillType billType;

  const _CategorySelectorSheet({
    required this.categories,
    this.initialSelectedId,
    required this.billType,
  });

  @override
  State<_CategorySelectorSheet> createState() =>
      _CategorySelectorSheetState();
}

class _CategorySelectorSheetState
    extends State<_CategorySelectorSheet> {
  late List<Category> _all;
  late List<Category> _filtered;

  String _query = '';
  String? _selectedId;

  @override
  void initState() {
    super.initState();

    _selectedId = widget.initialSelectedId;

    _all = widget.categories
        .where(_isDisplayableCategory)
        .toList()
      ..sort(
        (a, b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

    _filtered = List<Category>.from(_all);
  }

  void _reloadCategories() {
    final expectedType = widget.billType == BillType.income
        ? CategoryType.income
        : CategoryType.expense;

    final updated = DatabaseService.getAllCategories()
        .where((category) => category.type == expectedType)
        .where(_isDisplayableCategory)
        .toList()
      ..sort(
        (a, b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

    if (!mounted) return;

    setState(() {
      _all = updated;

      _filtered = _all
          .where(
            (category) => category.name
                .toLowerCase()
                .contains(_query),
          )
          .toList();
    });
  }

  void _onSearch(String value) {
    final query = value.trim().toLowerCase();

    setState(() {
      _query = query;

      _filtered = _all
          .where(
            (category) => category.name
                .toLowerCase()
                .contains(query),
          )
          .toList();
    });
  }

 Future<void> _addCategory() async {
  FocusScope.of(context).unfocus();

  final result = await Navigator.of(context).push<Category>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _AddCategoryPage(
        billType: widget.billType,
      ),
    ),
  );

  if (result == null) return;

  try {
    final newCategoryId =
        await DatabaseService.addCategory(result);

    try {
      await LookupsSyncHelper.syncCategory(
        result.copyWith(id: newCategoryId),
      );
    } catch (_) {}

    if (!mounted) return;

    _selectedId = newCategoryId;

    _reloadCategories();

    if (!mounted) return;

    Navigator.pop(context, newCategoryId);
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Unable to save category: $e',
        ),
        backgroundColor: Colors.blueGrey[400],
      ),
    );
  }
}

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        Theme.of(context).colorScheme;

    final searchHint =
        widget.billType == BillType.income
            ? 'Search income categories'
            : 'Search expense categories';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Select Category'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Add category',
            icon: const Icon(Icons.add_rounded),
            onPressed: _addCategory,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(
                16,
                16,
                16,
                10,
              ),
              child: TextField(
                onChanged: _onSearch,
                decoration: InputDecoration(
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                  ),
                  hintText: searchHint,
                  filled: true,
                  fillColor:
                      colorScheme.surfaceContainerLow,
                  contentPadding:
                      const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder:
                      OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: colorScheme
                          .outlineVariant
                          .withValues(alpha: 0.45),
                    ),
                  ),
                  focusedBorder:
                      OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: colorScheme.primary,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),

            Expanded(
              child: _filtered.isEmpty
                  ? _buildEmptyState(
                      colorScheme,
                    )
                  : ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior
                              .onDrag,
                      padding:
                          const EdgeInsets.fromLTRB(
                        16,
                        6,
                        16,
                        24,
                      ),
                      itemCount:
                          _filtered.length,
                      separatorBuilder:
                          (_, __) =>
                              const SizedBox(
                        height: 8,
                      ),
                      itemBuilder:
                          (context, index) {
                        final category =
                            _filtered[index];

                        return _buildCategoryRow(
                          colorScheme:
                              colorScheme,
                          category:
                              category,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    ColorScheme colorScheme,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.category_outlined,
              size: 48,
              color:
                  colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              _query.isEmpty
                  ? 'No categories yet'
                  : 'No categories found',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _query.isEmpty
                  ? 'Tap + to add your first category.'
                  : 'Try a different search.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color:
                    colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryRow({
    required ColorScheme colorScheme,
    required Category category,
  }) {
    final isSelected =
        _selectedId == category.id;

    return Material(
      color: isSelected
          ? colorScheme.primaryContainer
              .withValues(alpha: 0.45)
          : colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.pop(
            context,
            category.id,
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                      .withValues(alpha: 0.55)
                  : colorScheme.outlineVariant
                      .withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: category.color
                      .withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: category.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Text(
                  category.name,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color:
                        colorScheme.onSurface,
                  ),
                ),
              ),

              const SizedBox(width: 10),

              if (isSelected)
                Icon(
                  Icons.check_circle_rounded,
                  color: colorScheme.primary,
                  size: 24,
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme
                      .onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
class _AddCategoryPage extends StatefulWidget {
  final BillType billType;

  const _AddCategoryPage({
    required this.billType,
  });

  @override
  State<_AddCategoryPage> createState() =>
      _AddCategoryPageState();
}

class _AddCategoryPageState
    extends State<_AddCategoryPage> {
  final int _accountGeneration = AccountOperations.generation;
  final TextEditingController _nameController =
      TextEditingController();

  Color _selectedColor = const Color(0xFF607D8B);

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _cancel() {
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop();
  }

  void _save() {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter a category name',
          ),
        ),
      );
      return;
    }

    final type = widget.billType == BillType.income
        ? CategoryType.income
        : CategoryType.expense;

    final category = Category(
      name: name,
      iconCodePoint: '0xe85d',
      colorValue: _selectedColor.value.toString(),
      type: type,
    );

    FocusScope.of(context).unfocus();

    Navigator.of(context).pop(category);
  }

  Future<void> _pickColor() {
    return AccountOperations.bind(_accountGeneration, () async {
    FocusScope.of(context).unfocus();

    final picked = await showAppColorPicker(
      context: context,
      initialColor: _selectedColor,
      title: 'Pick Category Color',
    );

    if (!mounted || picked == null) return;

    setState(() {
      _selectedColor = picked;
    });
      });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        Theme.of(context).colorScheme;

    final isIncome =
        widget.billType == BillType.income;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Cancel',
          onPressed: _cancel,
          icon: const Icon(
            Icons.close_rounded,
          ),
        ),
        title: const Text(
          'Add Category',
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior:
              ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            20,
            24,
            20,
            32,
          ),
          children: [
            Text(
              isIncome
                  ? 'Create a category for your income.'
                  : 'Create a category for your expenses.',
              style: TextStyle(
                fontSize: 15,
                color:
                    colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 28),

            Text(
              'NAME',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color:
                    colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 8),

            TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization:
                  TextCapitalization.sentences,
              textInputAction:
                  TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                hintText: 'Category name',
                prefixIcon: const Icon(
                  Icons.category_outlined,
                ),
                filled: true,
                fillColor:
                    colorScheme.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder:
                    OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: colorScheme
                        .outlineVariant
                        .withValues(
                          alpha: 0.45,
                        ),
                  ),
                ),
                focusedBorder:
                    OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 28),

            Text(
              'COLOR',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color:
                    colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 8),

            Material(
              color:
                  colorScheme.surfaceContainerLow,
              borderRadius:
                  BorderRadius.circular(14),
              child: InkWell(
                borderRadius:
                    BorderRadius.circular(14),
                onTap: _pickColor,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(14),
                    border: Border.all(
                      color: colorScheme
                          .outlineVariant
                          .withValues(
                            alpha: 0.45,
                          ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _selectedColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.black12,
                          ),
                        ),
                      ),

                      const SizedBox(width: 14),

                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Category Color',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight:
                                    FontWeight.w600,
                                color: colorScheme
                                    .onSurface,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Tap to choose a color',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),

                      Icon(
                        Icons.color_lens_outlined,
                        color:
                            colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 36),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancel,
                    style:
                        OutlinedButton.styleFrom(
                      minimumSize:
                          const Size.fromHeight(
                        52,
                      ),
                      shape:
                          RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(
                          12,
                        ),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: ElevatedButton(
                    onPressed: _save,
                    style:
                        ElevatedButton.styleFrom(
                      minimumSize:
                          const Size.fromHeight(
                        52,
                      ),
                      backgroundColor:
                          colorScheme.primary,
                      foregroundColor:
                          colorScheme.onPrimary,
                      shape:
                          RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(
                          12,
                        ),
                      ),
                    ),
                    child: const Text(
                      'Add Category',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
// Top-level payee selector sheet widget
class _PayeeSelectorSheet extends StatefulWidget {
  final List<Map<String, dynamic>> payees;
  final String? initialSelectedId;
  final BillType billType;

  const _PayeeSelectorSheet({
    required this.payees,
    this.initialSelectedId,
    required this.billType,
  });

  @override
  State<_PayeeSelectorSheet> createState() => _PayeeSelectorSheetState();
}

class _PayeeSelectorSheetState extends State<_PayeeSelectorSheet> {
  late List<Map<String, dynamic>> _all;
  late List<Map<String, dynamic>> _filtered;
  String _query = '';
  String? _selectedId;
  VoidCallback? _categoriesListener;

  @override
  void initState() {
    super.initState();
    _all = List<Map<String, dynamic>>.from(widget.payees)
      ..sort((a, b) {
        final an = (a['name'] ?? '').toString().toLowerCase();
        final bn = (b['name'] ?? '').toString().toLowerCase();
        return an.compareTo(bn);
      });
    _filtered = _all;
    _selectedId = widget.initialSelectedId;
    _categoriesListener = () {
      if (!mounted) return;
      setState(() {});
    };
    DatabaseService.categoriesVersion.addListener(_categoriesListener!);
  }

  @override
  void dispose() {
    if (_categoriesListener != null) {
      DatabaseService.categoriesVersion.removeListener(_categoriesListener!);
    }
    super.dispose();
  }

  void _onSearch(String q) {
    setState(() {
      _query = q.toLowerCase();
      _filtered = _all
          .where((p) => (p['name'] as String).toLowerCase().contains(_query))
          .toList();
    });
  }

Future<void> _addPayee() async {
  FocusScope.of(context).unfocus();

  final isIncome = widget.billType == BillType.income;

  final result = await Navigator.of(context).push<Map<String, dynamic>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _AddPayeePage(
        billType: widget.billType,
      ),
    ),
  );

  if (result == null) return;

  final type = isIncome ? 'payer' : 'payee';

  final newPayee = <String, dynamic>{
    'id': const Uuid().v4(),
    'name': result['name'],
    'type': type,
    'categoryId': result['categoryId'],
  };

  try {
    await DatabaseService.addPayee(newPayee);

    try {
      await LookupsSyncHelper.syncPayeeOrPayer(newPayee);
    } catch (_) {}

    await DatabaseService.updatePayeeReferences(newPayee);

    if (!mounted) return;

    _all = DatabaseService.getAllPayees()
        .where(
          (p) => (p['type'] ?? '').toString() == type,
        )
        .toList()
      ..sort((a, b) {
        final an = (a['name'] ?? '').toString().toLowerCase();
        final bn = (b['name'] ?? '').toString().toLowerCase();
        return an.compareTo(bn);
      });

    setState(() {
      _filtered = _all
          .where(
            (p) => (p['name'] ?? '')
                .toString()
                .toLowerCase()
                .contains(_query),
          )
          .toList();

      _selectedId = newPayee['id'] as String;
    });

    if (!mounted) return;

    // Return the newly created payee/payer to Add Bill.
    Navigator.pop(context, _selectedId);
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isIncome
              ? 'Unable to save payer: $e'
              : 'Unable to save payee: $e',
        ),
        backgroundColor: Colors.blueGrey[400],
      ),
    );
  }
}
@override
Widget build(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;

  final String titleText = widget.billType == BillType.expense
      ? 'Select Payee'
      : widget.billType == BillType.income
          ? 'Select Payer'
          : '';

  final String searchHint = widget.billType == BillType.income
      ? 'Search payers'
      : 'Search payees';

  return Scaffold(
    backgroundColor: colorScheme.surface,
    appBar: AppBar(
      title: Text(titleText),
      centerTitle: true,
      actions: [
        IconButton(
          tooltip: widget.billType == BillType.income
              ? 'Add payer'
              : 'Add payee',
          icon: const Icon(Icons.add_rounded),
          onPressed: _addPayee,
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: searchHint,
                filled: true,
                fillColor: colorScheme.surfaceContainerLow,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: colorScheme.outlineVariant.withValues(
                      alpha: 0.45,
                    ),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
              onChanged: _onSearch,
            ),
          ),

          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_search_outlined,
                            size: 48,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _query.isEmpty
                                ? widget.billType == BillType.income
                                    ? 'No payers yet'
                                    : 'No payees yet'
                                : 'No matches found',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _query.isEmpty
                                ? 'Tap + to add one.'
                                : 'Try a different search.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      6,
                      16,
                      24,
                    ),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final p = _filtered[idx];

                      final String name =
                          (p['name'] ?? '').toString();

                      String? categoryName;
                      Color? categoryColor;

                      if (p['categoryId'] != null &&
                          p['categoryId'].toString().isNotEmpty) {
                        final cat = DatabaseService.getCategoryById(
                          p['categoryId'],
                        );

                        categoryName = cat?.name;
                        categoryColor = cat?.color;
                      }

                      final bool isSelected =
                          _selectedId == p['id'];

                      return Material(
                        color: isSelected
                            ? colorScheme.primaryContainer.withValues(
                                alpha: 0.45,
                              )
                            : colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => Navigator.pop(
                            context,
                            p['id'] as String,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 13,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? colorScheme.primary.withValues(
                                        alpha: 0.55,
                                      )
                                    : colorScheme.outlineVariant
                                        .withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: colorScheme
                                        .surfaceContainerHighest,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    widget.billType == BillType.income
                                        ? Icons.person_outline_rounded
                                        : Icons.storefront_outlined,
                                    size: 22,
                                    color: colorScheme.primary,
                                  ),
                                ),

                                const SizedBox(width: 14),

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        maxLines: 1,
                                        overflow:
                                            TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),

                                      if (categoryName != null &&
                                          categoryName
                                              .trim()
                                              .isNotEmpty) ...[
                                        const SizedBox(height: 5),
                                        Row(
                                          children: [
                                            if (categoryColor !=
                                                null) ...[
                                              Container(
                                                width: 8,
                                                height: 8,
                                                decoration:
                                                    BoxDecoration(
                                                  color: categoryColor,
                                                  shape:
                                                      BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                            ],
                                            Expanded(
                                              child: Text(
                                                categoryName,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),

                                const SizedBox(width: 10),

                                if (isSelected)
                                  Icon(
                                    Icons.check_circle_rounded,
                                    color: colorScheme.primary,
                                    size: 24,
                                  )
                                else
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color:
                                        colorScheme.onSurfaceVariant,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}
}
class _AddPayeePage extends StatefulWidget {
  final BillType billType;

  const _AddPayeePage({
    required this.billType,
  });

  @override
  State<_AddPayeePage> createState() => _AddPayeePageState();
}

class _AddPayeePageState extends State<_AddPayeePage> {
  final int _accountGeneration = AccountOperations.generation;
  final TextEditingController _nameController = TextEditingController();

  String? _categoryId;

  bool get _isIncome => widget.billType == BillType.income;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _cancel() {
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop();
  }

  void _save() {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isIncome
                ? 'Please enter a payer name'
                : 'Please enter a payee name',
          ),
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();

    Navigator.of(context).pop(<String, dynamic>{
      'name': name,
      'categoryId': _categoryId,
    });
  }

  Future<void> _selectCategory() {
    return AccountOperations.bind(_accountGeneration, () async {
    FocusScope.of(context).unfocus();

    final expectedType = _isIncome
        ? CategoryType.income
        : CategoryType.expense;

    final categories = DatabaseService.getAllCategories()
        .where((category) => category.type == expectedType)
        .where(_isDisplayableCategory)
        .toList()
      ..sort(
        (a, b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

    final selected = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _CategorySelectorSheet(
          categories: categories,
          initialSelectedId: _categoryId,
          billType: widget.billType,
        ),
      ),
    );

    if (!mounted || selected == null) return;

    setState(() {
      _categoryId = selected;
    });
      });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final selectedCategory = _categoryId == null
        ? null
        : DatabaseService.getCategoryById(_categoryId!);

    return Scaffold(
      backgroundColor: colorScheme.surface,

      // Same page-style presentation as Add Category.
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Cancel',
          onPressed: _cancel,
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(
          _isIncome ? 'Add Payer' : 'Add Payee',
        ),
        centerTitle: true,
      ),

      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior:
              ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            20,
            24,
            20,
            32,
          ),
          children: [
            Text(
              _isIncome
                  ? 'Add a person or business that pays you.'
                  : 'Add a person or business you pay.',
              style: TextStyle(
                fontSize: 15,
                color: colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 28),

            // NAME
            Text(
              'NAME',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 8),

            TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                hintText: _isIncome
                    ? 'Payer name'
                    : 'Payee name',
                prefixIcon: Icon(
                  _isIncome
                      ? Icons.person_outline_rounded
                      : Icons.storefront_outlined,
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: colorScheme.outlineVariant.withValues(
                      alpha: 0.45,
                    ),
                  ),
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

            const SizedBox(height: 28),

            // CATEGORY
            Text(
              'CATEGORY',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 8),

            Material(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _selectCategory,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(
                        alpha: 0.45,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (selectedCategory != null)
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: selectedCategory.color,
                            shape: BoxShape.circle,
                          ),
                        )
                      else
                        Icon(
                          Icons.label_outline_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),

                      const SizedBox(width: 14),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Category',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              selectedCategory?.name ?? 'Select category',
                              style: TextStyle(
                                fontSize: 13,
                                color: selectedCategory == null
                                    ? colorScheme.onSurfaceVariant
                                    : colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),

                      Icon(
                        Icons.chevron_right_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 36),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancel,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _isIncome ? 'Add Payer' : 'Add Payee',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
// Top-level calculator bottom sheet widget
class _AddAccountPage extends StatefulWidget {
  const _AddAccountPage();

  @override
  State<_AddAccountPage> createState() => _AddAccountPageState();
}

class _AddAccountPageState extends State<_AddAccountPage> {
  final int _accountGeneration = AccountOperations.generation;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _institutionController = TextEditingController();
  final TextEditingController _accountNumberController = TextEditingController();
  final TextEditingController _cardNumberController = TextEditingController();
  final TextEditingController _balanceController =
      TextEditingController(text: '0.0');
  final TextEditingController _availableBalanceController =
      TextEditingController(text: '0.0');

  AccountType _selectedType = AccountType.cash;
  String? _customType;

  @override
  void dispose() {
    _nameController.dispose();
    _institutionController.dispose();
    _accountNumberController.dispose();
    _cardNumberController.dispose();
    _balanceController.dispose();
    _availableBalanceController.dispose();
    super.dispose();
  }

  void _cancel() {
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop();
  }

  Future<void> _addCustomType() {
    return AccountOperations.bind(_accountGeneration, () async {
    FocusScope.of(context).unfocus();
    final controller = TextEditingController();

    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add account type'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Type name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(dialogContext, text);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (!mounted || value == null || value.trim().isEmpty) return;

    DatabaseService.addCustomAccountType(value.trim());

    setState(() {
      _customType = value.trim();
    });
      });
  }

  void _save() {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an account name'),
        ),
      );
      return;
    }

    final institution = _institutionController.text.trim();
    final accountNumber = _accountNumberController.text.trim();
    final cardNumber = _cardNumberController.text.trim();
    final balance = double.tryParse(_balanceController.text.trim()) ?? 0.0;
    final availableBalance =
        double.tryParse(_availableBalanceController.text.trim());

    FocusScope.of(context).unfocus();

    final account = Account(
      name: name,
      type: _selectedType,
      institution: institution.isEmpty ? null : institution,
      accountNumber: accountNumber.isEmpty ? null : accountNumber,
      cardNumber: cardNumber.isEmpty ? null : cardNumber,
      balance: balance,
      availableBalance: availableBalance,
      customType: _customType,
    );

    Navigator.of(context).pop(account);
  }

  String _formatType(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  Widget _sectionLabel(BuildContext context, String text) {
    final colorScheme = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required BuildContext context,
    required String hintText,
    required IconData icon,
    String? labelText,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: colorScheme.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: colorScheme.primary,
          width: 1.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final typeNames = <String>{
      ...AccountType.values.map((type) => type.name),
      ...DatabaseService.getAllCustomAccountTypes(),
    }.toList();

    final selectedValue = _customType ?? _selectedType.name;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Cancel',
          onPressed: _cancel,
          icon: const Icon(Icons.close_rounded),
        ),
        title: const Text('Add Account'),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Text(
              'Add an account to track bills, income, and balances.',
              style: TextStyle(
                fontSize: 15,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            _sectionLabel(context, 'ACCOUNT TYPE'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              padding: const EdgeInsets.only(left: 16, right: 6),
              child: Row(
                children: [
                  AccountTypeIcon(
                    type: _selectedType,
                    displayName: _formatType(selectedValue),
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedValue,
                        isExpanded: true,
                        items: typeNames
                            .map((type) {
                              final match = AccountType.values.where(
                                (candidate) =>
                                    candidate.name.toLowerCase() ==
                                    type.toLowerCase(),
                              );
                              final displayType = _formatType(type);
                              return DropdownMenuItem<String>(
                                value: type,
                                child: Row(
                                  children: [
                                    AccountTypeIcon(
                                      type: match.isNotEmpty
                                          ? match.first
                                          : AccountType.cash,
                                      displayName: displayType,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(displayType),
                                  ],
                                ),
                              );
                            })
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;

                          final enumNames = AccountType.values
                              .map((type) => type.name.toLowerCase())
                              .toSet();

                          setState(() {
                            if (enumNames.contains(value.toLowerCase())) {
                              _selectedType = AccountType.values.firstWhere(
                                (type) =>
                                    type.name.toLowerCase() ==
                                    value.toLowerCase(),
                              );
                              _customType = null;
                            } else {
                              _customType = value;
                            }
                          });
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add custom type',
                    onPressed: _addCustomType,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            _sectionLabel(context, 'ACCOUNT DETAILS'),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.organizationName],
              decoration: _fieldDecoration(
                context: context,
                hintText: 'Account name',
                icon: Icons.account_balance_wallet_outlined,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _institutionController,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.organizationName],
              decoration: _fieldDecoration(
                context: context,
                hintText: 'Institution',
                icon: Icons.account_balance_outlined,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _accountNumberController,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.username],
              decoration: _fieldDecoration(
                context: context,
                hintText: 'Account number',
                icon: Icons.numbers_rounded,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cardNumberController,
              keyboardType: TextInputType.number,
              decoration: _fieldDecoration(
                context: context,
                hintText: 'Card number',
                icon: Icons.credit_card_rounded,
              ),
            ),
            const SizedBox(height: 28),
            _sectionLabel(context, 'BALANCES'),
            const SizedBox(height: 8),
            TextField(
              controller: _balanceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: _fieldDecoration(
                context: context,
                labelText: 'Initial balance',
                hintText: '0.0',
                icon: Icons.account_balance_wallet_outlined,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _availableBalanceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: _fieldDecoration(
                context: context,
                labelText: 'Available balance',
                hintText: '0.0',
                icon: Icons.payments_outlined,
              ),
            ),
            const SizedBox(height: 36),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancel,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Add Account'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CalculatorSheet extends StatefulWidget {
  final String? initialValue;
  const _CalculatorSheet({this.initialValue});

  @override
  State<_CalculatorSheet> createState() => _CalculatorSheetState();
}

class _CalculatorSheetState extends State<_CalculatorSheet> {
  String _expression = '';

  @override
  void initState() {
    super.initState();
    if ((widget.initialValue ?? '').isNotEmpty) {
      _expression = widget.initialValue!;
    }
  }

  void _append(String s) {
    setState(() => _expression += s);
  }

  void _backspace() {
    if (_expression.isNotEmpty)
      setState(
        () => _expression = _expression.substring(0, _expression.length - 1),
      );
  }

  void _clear() {
    setState(() => _expression = '');
  }

  double? _evaluate() {
    try {
      // Very small expression evaluator supporting + - * /
      final tokens = <String>[];
      String numBuf = '';
      for (var i = 0; i < _expression.length; i++) {
        final ch = _expression[i];
        if ('0123456789.'.contains(ch)) {
          numBuf += ch;
        } else if ('+-*/'.contains(ch)) {
          if (numBuf.isNotEmpty) {
            tokens.add(numBuf);
            numBuf = '';
          }
          tokens.add(ch);
        }
      }
      if (numBuf.isNotEmpty) tokens.add(numBuf);

      if (tokens.isEmpty) return null;

      // first pass: *,/
      final stack = <String>[];
      for (var i = 0; i < tokens.length; i++) {
        final t = tokens[i];
        if (t == '*' || t == '/') {
          final prev = stack.removeLast();
          final next = tokens[++i];
          final a = double.parse(prev);
          final b = double.parse(next);
          final res = t == '*' ? a * b : a / b;
          stack.add(res.toString());
        } else {
          stack.add(t);
        }
      }

      // second pass: +,-
      var result = double.parse(stack[0]);
      for (var i = 1; i < stack.length; i += 2) {
        final op = stack[i];
        final val = double.parse(stack[i + 1]);
        if (op == '+') result += val;
        if (op == '-') result -= val;
      }
      return result;
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final eval = _evaluate();
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _expression,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
                IconButton(
                  onPressed: _backspace,
                  icon: const Icon(Icons.backspace),
                ),
              ],
            ),
          ),
          if (eval != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                children: [
                  const Text(
                    'Result:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    eval.toStringAsFixed(2),
                    style: const TextStyle(fontSize: 20),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.count(
              crossAxisCount: 4,
              childAspectRatio: 1.6,
              padding: const EdgeInsets.all(12),
              children:
                  [
                    '7',
                    '8',
                    '9',
                    '/',
                    '4',
                    '5',
                    '6',
                    '*',
                    '1',
                    '2',
                    '3',
                    '-',
                    '.',
                    '0',
                    '=',
                    '+',
                  ].map((label) {
                    return Padding(
                      padding: const EdgeInsets.all(6.0),
                      child: ElevatedButton(
                        onPressed: () {
                          if (label == '=') {
                            final value = _evaluate();
                            if (value != null) Navigator.of(context).pop(value);
                            return;
                          }
                          _append(label);
                        },
                        child: Text(
                          label,
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                TextButton(onPressed: _clear, child: const Text('Clear')),
                const Spacer(),
                ElevatedButton(
                  onPressed: () {
                    final value = _evaluate();
                    if (value != null) Navigator.of(context).pop(value);
                  },
                  child: const Text('Accept'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddBillScreenState extends State<AddBillScreen> {
  final int _accountGeneration = AccountOperations.generation;
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isSaving = false;
  bool _didUserEditNotes = false;
  String _initialNotes = '';

  // New: bill type (expense/income/transfer)
  BillType _billType = BillType.expense;

  DateTime _dueDate = DateTime.now();
  Recurrence _recurrence = Recurrence.none;
  List<int>? _customDays;
  DateTime? _recurrenceEndDate;
  bool _recurrenceForever = true;
  // recurrence interval (every N days/weeks/months/years)
  int _recurrenceInterval = 1;
  // selected weekdays for weekly recurrence (1=Mon .. 7=Sun)
  List<int>? _recurrenceWeekdays = [];
  String? _selectedPayeeId;
  String? _selectedAccountId;
  // Transfer-specific accounts
  String? _fromAccountId;
  String? _toAccountId;

  List<Map<String, dynamic>> _payees = [];
  List accountList = [];
  List<Category> _categories = [];
  String? _selectedCategoryId;

  Account? _accountForId(String? accountId) {
    if (accountId == null) return null;
    for (final account in accountList) {
      if (account is Account && account.id == accountId) return account;
    }
    return null;
  }

  Widget _accountIconForId(String? accountId, IconData fallbackIcon) {
    final account = _accountForId(accountId);
    if (account == null) return Icon(fallbackIcon);
    return AccountTypeIcon(
      type: account.type,
      displayName: account.typeDisplayName,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadLookups();
    _loadExistingBillData();
  }

  void _loadExistingBillData() {
    final bill = widget.existingBill;
    if (bill != null) {
      _amountController.text = bill.amount.toString();
      _initialNotes = _extractEditableNotes(bill);
      _notesController.text = _initialNotes;
      _dueDate = bill.dueDate;
      _recurrence = bill.recurrence;
      _customDays = bill.customDays;
      _recurrenceEndDate = bill.recurrenceEndDate;
      _recurrenceForever = bill.recurrenceEndDate == null;
      _recurrenceInterval = bill.recurrenceInterval <= 0
          ? 1
          : bill.recurrenceInterval;
      _recurrenceWeekdays = bill.recurrenceWeekdays ?? [];
      _selectedCategoryId = bill.categoryId;
      _billType = bill.type;
      _fromAccountId = bill.fromAccountId;
      _toAccountId = bill.toAccountId;
      _selectedPayeeId = bill.payeeId;
      _selectedAccountId = bill.accountId;
    }
  }

  void _loadLookups() {
    _payees = DatabaseService.getAllPayees();
    accountList = DatabaseService.getAllAccounts();
    _categories =
        DatabaseService.getAllCategories()
            .where(_isDisplayableCategory)
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
  }

  String _extractEditableNotes(Bill bill) {
    String? payeeName;
    if (bill.payeeId != null && bill.payeeId!.isNotEmpty) {
      final payee = _payees.firstWhere(
        (p) => p['id'] == bill.payeeId,
        orElse: () => const <String, dynamic>{},
      );
      payeeName = (payee['name'] ?? '').toString().trim();
    }

    final fromName =
        (bill.fromAccountId != null && bill.fromAccountId!.isNotEmpty)
        ? DatabaseService.getAccountById(bill.fromAccountId!)?.name
        : null;
    final toName = (bill.toAccountId != null && bill.toAccountId!.isNotEmpty)
        ? DatabaseService.getAccountById(bill.toAccountId!)?.name
        : null;

    return editableBillNote(
      bill,
      payeeName: payeeName,
      fromAccountName: fromName,
      toAccountName: toName,
    );
  }

  List<Map<String, dynamic>> get _visiblePayees {
    if (_billType == BillType.expense) {
      return _payees.where((p) => (p['type'] as String?) == 'payee').toList();
    } else if (_billType == BillType.income) {
      return _payees.where((p) => (p['type'] as String?) == 'payer').toList();
    }
    return _payees;
  }

  List<Category> get _visibleCategories {
    if (_billType == BillType.expense) {
      return _categories.where((c) => c.type == CategoryType.expense).toList();
    } else if (_billType == BillType.income) {
      return _categories.where((c) => c.type == CategoryType.income).toList();
    }
    return _categories;
  }

 @override
Widget build(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;
  final bottomClearance = MediaQuery.paddingOf(context).bottom + 32;

  final screenTitle = widget.isDuplicate
      ? 'Duplicate Bill'
      : widget.existingBill != null
          ? 'Edit Bill'
          : 'Add Bill';

  return Scaffold(
    resizeToAvoidBottomInset: true,
    backgroundColor: colorScheme.surface,
    appBar: AppBar(
      leading: const BackButton(),
      title: Text(screenTitle),
      centerTitle: true,
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      elevation: 0,
    ),
    body: SafeArea(
      top: false,
      child: Form(
        key: _formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16,
            20,
            16,
            bottomClearance,
          ),
          children: [
            _buildSectionLabel('TYPE'),
            const SizedBox(height: 8),
            _buildTypeToggle(),

            const SizedBox(height: 24),

            _buildSectionLabel('AMOUNT'),
            const SizedBox(height: 8),
            _buildAmountField(),

            const SizedBox(height: 24),

            if (_billType == BillType.transfer) ...[
              _buildSectionLabel('TRANSFER'),
              const SizedBox(height: 8),
              _buildFormSection(
                children: [
                  _buildFromAccountSelector(),
                  _buildSectionDivider(),
                  _buildToAccountSelector(),
                ],
              ),
            ] else ...[
              _buildSectionLabel(
                _billType == BillType.income
                    ? 'INCOME DETAILS'
                    : 'BILL DETAILS',
              ),
              const SizedBox(height: 8),
              _buildFormSection(
                children: [
                  _buildPayeeSelector(),
                  _buildSectionDivider(),
                  _buildCategorySelector(),
                  _buildSectionDivider(),
                  _buildAccountSelector(),
                ],
              ),
            ],

            const SizedBox(height: 24),

            _buildSectionLabel('SCHEDULE'),
            const SizedBox(height: 8),
            _buildFormSection(
              children: [
                _buildDueDateSelector(),
                _buildSectionDivider(),
                _buildRecurrenceField(),
              ],
            ),

            const SizedBox(height: 24),

            _buildSectionLabel('NOTES'),
            const SizedBox(height: 8),
            _buildNotesField(),

            const SizedBox(height: 28),

            _buildSaveButton(),

            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );
}

Widget _buildSectionLabel(String text) {
  final colorScheme = Theme.of(context).colorScheme;

  return Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

Widget _buildFormSection({
  required List<Widget> children,
}) {
  final colorScheme = Theme.of(context).colorScheme;

  return Container(
    decoration: BoxDecoration(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: colorScheme.outlineVariant.withValues(alpha: 0.45),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: children,
    ),
  );
}

Widget _buildSectionDivider() {
  final colorScheme = Theme.of(context).colorScheme;

  return Divider(
    height: 1,
    thickness: 1,
    indent: 56,
    color: colorScheme.outlineVariant.withValues(alpha: 0.45),
  );
}

 Widget _buildTypeToggle() {
  final colorScheme = Theme.of(context).colorScheme;

  Widget buildOption({
    required BillType type,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _billType == type;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (_billType == type) return;

          setState(() {
            _billType = type;

            _selectedPayeeId = null;
            _selectedCategoryId = null;
            _selectedAccountId = null;
            _fromAccountId = null;
            _toAccountId = null;

            _notesController.clear();
            _didUserEditNotes = true;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 13,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  return Row(
    children: [
      buildOption(
        type: BillType.expense,
        label: 'Expense',
        icon: Icons.arrow_upward_rounded,
      ),
      const SizedBox(width: 10),
      buildOption(
        type: BillType.income,
        label: 'Income',
        icon: Icons.arrow_downward_rounded,
      ),
    ],
  );
}

  Widget _buildAmountField() {
  final colorScheme = Theme.of(context).colorScheme;

  final amountColor = _billType == BillType.income
      ? AppTheme.incomeGreen
      : AppTheme.expenseRed;

  return Container(
    decoration: BoxDecoration(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: colorScheme.outlineVariant.withValues(alpha: 0.45),
      ),
    ),
    child: TextFormField(
      controller: _amountController,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
      ),
      textInputAction: TextInputAction.done,
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        hintText: '0.00',
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 20,
        ),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(
            left: 18,
            right: 12,
          ),
          child: Text(
            '\$',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: amountColor,
            ),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 0,
          minHeight: 0,
        ),
        suffixIcon: IconButton(
          tooltip: 'Calculator',
          icon: const Icon(
            Icons.calculate_outlined,
            size: 26,
          ),
          onPressed: () async {
            FocusScope.of(context).unfocus();

            final result = await showModalBottomSheet<double?>(
              context: context,
              isScrollControlled: true,
              builder: (_) => FractionallySizedBox(
                heightFactor: 0.6,
                child: _CalculatorSheet(
                  initialValue: _amountController.text,
                ),
              ),
            );

            if (!mounted || result == null) return;

            setState(() {
              _amountController.text = result.toStringAsFixed(2);
            });
          },
        ),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please enter an amount';
        }

        final amount = double.tryParse(value.trim());

        if (amount == null || amount <= 0) {
          return 'Please enter a valid amount';
        }

        return null;
      },
    ),
  );
}

  Widget _buildDueDateSelector() {
   return ListTile(
        leading: const Icon(Icons.calendar_today),
        title: const Text('Due Date'),
        subtitle: Text(DateFormat.yMMMd().format(_dueDate)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: _selectDueDate,
    );
  }

  Future<void> _selectDueDate() {
    return AccountOperations.bind(_accountGeneration, () async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null && picked != _dueDate) {
      final previousDueDate = _dueDate;
      setState(() {
        _dueDate = picked;
        if (_recurrence == Recurrence.weekly) {
          final weekdays = {...?_recurrenceWeekdays};
          if (weekdays.isEmpty) {
            _recurrenceWeekdays = null;
          } else {
            if (weekdays.length == 1 &&
                weekdays.contains(previousDueDate.weekday)) {
              _recurrenceWeekdays = <int>[picked.weekday];
            } else {
              weekdays.add(picked.weekday);
              _recurrenceWeekdays = weekdays.toList()..sort();
            }
          }
        } else if (_recurrence == Recurrence.monthly) {
          final days = {...?_customDays};
          if (days.isEmpty) {
            _customDays = null;
          } else if (days.contains(99)) {
            _customDays = <int>[99];
          } else if (days.length == 1 && days.contains(previousDueDate.day)) {
            _customDays = <int>[picked.day];
          } else {
            days.add(picked.day);
            _customDays = days.toList()..sort();
          }
        }
      });
    }
      });
  }

  // _buildRecurrenceSelector removed in favor of _buildRecurrenceField

 Widget _buildRecurrenceField() {
  return ListTile(
    leading: const Icon(Icons.repeat),
    title: const Text('Recurrence'),
    subtitle: Text(_recurrenceSummary()),
    trailing: const Icon(
      Icons.arrow_forward_ios,
      size: 16,
    ),
    onTap: () async {
      final result =
          await Navigator.of(context).push<_RecurrenceResult>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _RecurrencePage(
            recurrence: _recurrence,
            forever: _recurrenceForever,
            endDate: _recurrenceEndDate,
            interval: _recurrenceInterval,
            weekdays: _recurrenceWeekdays,
            customDays: _customDays,
          ),
        ),
      );

      if (!mounted || result == null) return;

      setState(() {
        _recurrence = result.recurrence;
        _recurrenceForever = result.forever;
        _recurrenceEndDate =
            result.forever ? null : result.endDate;
        _recurrenceInterval = result.interval;

        _recurrenceWeekdays =
            result.recurrence == Recurrence.weekly
                ? (result.weekdays.isEmpty
                    ? null
                    : (result.weekdays.toList()..sort()))
                : null;

        if (result.recurrence == Recurrence.monthly) {
          _customDays =
              _normalizeMonthlyCustomDays(result.customDays);
        } else {
          _customDays = null;
        }
      });
    },
  );
}

  String _recurrenceSummary() {
    final interval = _recurrenceInterval <= 0 ? 1 : _recurrenceInterval;
    switch (_recurrence) {
      case Recurrence.none:
        return 'None';
      case Recurrence.daily:
        return interval == 1 ? 'Every day' : 'Every $interval days';
      case Recurrence.weekly:
        return interval == 1 ? 'Every week' : 'Every $interval weeks';
      case Recurrence.monthly:
        return interval == 1 ? 'Every month' : 'Every $interval months';
      case Recurrence.yearly:
        return interval == 1 ? 'Every year' : 'Every $interval years';
      default:
        // For any other (legacy) recurrence values, fallback to a generic label
        final s = _recurrence.toString().split('.').last;
        return s.isEmpty
            ? s
            : (s[0].toUpperCase() + s.substring(1).toLowerCase());
    }
  }

  String _pluralForRecurrenceUnit(Recurrence r, int interval) {
    final unit = switch (r) {
      Recurrence.daily => 'day',
      Recurrence.weekly => 'week',
      Recurrence.monthly => 'month',
      Recurrence.yearly => 'year',
      _ => 'period',
    };
    return interval == 1 ? unit : '${unit}s';
  }

  List<int>? _normalizeMonthlyCustomDays(Set<int> days) {
    final normalized = days.where((day) => day >= 1 && day <= 31).toSet();

    if (days.contains(99) || normalized.containsAll(<int>{30, 31})) {
      return <int>[99];
    }

    if (normalized.isEmpty) return null;

    return normalized.toList()..sort();
  }

  // recurrence end date selection is handled inside the recurrence modal

Widget _buildNotesField() {
  final colorScheme = Theme.of(context).colorScheme;

  return TextFormField(
    controller: _notesController,
    textCapitalization: TextCapitalization.sentences,
    minLines: 2,
    maxLines: 3,
    onChanged: (_) {
      if (!_didUserEditNotes) {
        setState(() => _didUserEditNotes = true);
      }
    },
    decoration: InputDecoration(
      hintText: 'Optional notes about this bill',
      hintStyle: TextStyle(
        color: colorScheme.onSurfaceVariant,
      ),
      filled: true,
      fillColor: colorScheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.all(16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: colorScheme.outlineVariant.withValues(
            alpha: 0.45,
          ),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: colorScheme.primary,
          width: 1.5,
        ),
      ),
    ),
  );
}

  Widget _buildPayeeSelector() {
    return ListTile(
        leading: const Icon(Icons.person),
        title: Text(_billType == BillType.income ? 'Payer' : 'Payee'),
        subtitle: Text(
          _selectedPayeeId == null
              ? (_billType == BillType.income ? 'Select payer' : 'Select payee')
              : (_payees.firstWhere(
                      (p) => p['id'] == _selectedPayeeId,
                      orElse: () => {'name': 'Unknown'},
                    )['name']
                    as String),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () async {
          final selected = await showModalBottomSheet<String?>(
            context: context,
            isScrollControlled: true,
            builder: (_) => FractionallySizedBox(
              heightFactor: 0.85,
              child: _PayeeSelectorSheet(
                payees: _visiblePayees,
                initialSelectedId: _selectedPayeeId,
                billType: _billType,
              ),
            ),
          );
          if (selected != null) {
            // Refresh payees from storage so newly added payees are present
            final updatedPayees = DatabaseService.getAllPayees();
            setState(() {
              _payees = updatedPayees;
              _selectedPayeeId = selected;
            });

            // Ensure our categories list is up-to-date so the category lookup
            // used by the UI can find newly created categories.
            final updatedCategories = DatabaseService.getAllCategories();
            try {
              final p = _payees.firstWhere(
                (p) => p['id'] == selected,
                orElse: () => <String, dynamic>{},
              );
              if (p.containsKey('categoryId') && p['categoryId'] != null) {
                setState(() {
                  _categories = updatedCategories;
                  _selectedCategoryId = p['categoryId'] as String?;
                });
              } else {
                // Update categories list even if payee has no category
                setState(() {
                  _categories = updatedCategories;
                });
              }
            } catch (_) {
              setState(() {
                _categories = updatedCategories;
              });
            }
          }
        },
    );
  }

  Widget _buildAccountSelector() {
    return ListTile(
      leading: _accountIconForId(
        _selectedAccountId,
        Icons.account_balance_wallet_outlined,
      ),
      title: const Text('Account'),
      subtitle: Text(
        _selectedAccountId == null
            ? 'Select'
            : (() {
                try {
                  final found = accountList.firstWhere(
                    (a) => a is Account
                        ? a.id == _selectedAccountId
                        : (a['id'] == _selectedAccountId),
                  );
                  if (found is Account) return found.name;
                  if (found is Map && found.containsKey('name')) {
                    return found['name'] as String;
                  }
                } catch (_) {}
                return 'Unknown';
              }()),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () async {
        final selected = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (selectorContext) => StatefulBuilder(
              builder: (selectorContext, setSelectorState) {
                final currentAccounts = DatabaseService.getAllAccounts();

                return Scaffold(
                  appBar: AppBar(
                    title: const Text('Select Account'),
                    centerTitle: true,
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.add_rounded),
                        tooltip: 'Add account',
                        onPressed: () async {
                          final plan =
                              DatabaseService.subscriptionVersion.value;
                          final accounts = DatabaseService.getAllAccounts();

                          if (plan == 'Free' && accounts.length >= 3) {
                            await showDialog<void>(
                              context: selectorContext,
                              builder: (dialogContext) => AlertDialog(
                                title: const Text('Account Limit Reached'),
                                content: const Text(
                                  'Free users can create up to 3 accounts. Subscribe for unlimited accounts.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext),
                                    child: const Text('OK'),
                                  ),
                                ],
                              ),
                            );
                            return;
                          }

                          final newAccount =
                              await Navigator.of(selectorContext).push<Account>(
                            MaterialPageRoute(
                              fullscreenDialog: true,
                              builder: (_) => const _AddAccountPage(),
                            ),
                          );

                          if (newAccount == null) return;

                          await DatabaseService.addAccount(newAccount);
                          final updated = DatabaseService.getAllAccounts();

                          if (!mounted) return;

                          setState(() {
                            accountList = updated;
                            _selectedAccountId = newAccount.id;
                          });

                          if (!selectorContext.mounted) return;
                          Navigator.pop(selectorContext, newAccount.id);
                        },
                      ),
                    ],
                  ),
                  body: currentAccounts.isEmpty
                      ? Center(
                          child: Text(
                            'No accounts yet',
                            style: TextStyle(
                              color: Theme.of(selectorContext)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          itemCount: currentAccounts.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final account = currentAccounts[index];
                            final accountName = account.name;
                            final accountId = account.id;
                            final isSelected = accountId == _selectedAccountId;

                            final accountType = account.typeDisplayName;

                            final colorScheme =
                                Theme.of(selectorContext).colorScheme;
                            final primary = colorScheme.primary;

                            return Material(
                              color: isSelected
                                  ? Colors.green.withValues(alpha: 0.28)
                                  : colorScheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => Navigator.pop(
                                  selectorContext,
                                  accountId,
                                ),
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minHeight: 68,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isSelected
                                          ? primary.withValues(alpha: 0.75)
                                          : colorScheme.outlineVariant
                                              .withValues(alpha: 0.75),
                                      width: isSelected ? 1.2 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? colorScheme.surface
                                              : Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        alignment: Alignment.center,
                                        child: AccountTypeIcon(
                                          type: account.type,
                                          displayName: account.typeDisplayName,
                                          color: primary,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              accountName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(selectorContext)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                            if (accountType.isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                accountType,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(selectorContext)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      color: colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Icon(
                                        isSelected
                                            ? Icons.check_circle_rounded
                                            : Icons.chevron_right_rounded,
                                        color: isSelected
                                            ? primary
                                            : colorScheme.onSurface,
                                        size: isSelected ? 26 : 24,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                );
              },
            ),
          ),
        );

        if (selected != null && mounted) {
          setState(() {
            accountList = DatabaseService.getAllAccounts();
            _selectedAccountId = selected;
          });
        }
      },
    );
  }

  Widget _buildFromAccountSelector() {
    return ListTile(
        leading: _accountIconForId(_fromAccountId, Icons.arrow_forward),
        title: const Text('From'),
        subtitle: Text(
          _fromAccountId == null
              ? 'Select from'
              : (() {
                  try {
                    final found = accountList.firstWhere(
                      (a) => a is Account
                          ? a.id == _fromAccountId
                          : (a['id'] == _fromAccountId),
                    );
                    if (found is Account) return found.name;
                    if (found is Map && found.containsKey('name'))
                      return found['name'] as String;
                  } catch (_) {}
                  return 'Unknown';
                }()),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () async {
          final selected = await showModalBottomSheet<String?>(
            context: context,
            isScrollControlled: true,
            builder: (ctx) => FractionallySizedBox(
              heightFactor: 0.85,
              child: StatefulBuilder(
                builder: (ctx2, setState2) {
                  return Scaffold(
                    appBar: AppBar(
                      title: const Text('Select Account'),
                      backgroundColor: Theme.of(ctx2).colorScheme.primary,
                      foregroundColor: Colors.white,
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () async {
                            // delegate to same add flow as account selector
                            final nameCtrl = TextEditingController();
                            final institutionCtrl = TextEditingController();
                            final accNumCtrl = TextEditingController();
                            final cardNumCtrl = TextEditingController();
                            AccountType selectedType = AccountType.cash;
                            final balCtrl = TextEditingController(text: '0.0');
                            final availCtrl = TextEditingController(
                              text: '0.0',
                            );
                            String? customType;
                            final res = await showDialog<Account?>(
                              context: ctx2,
                              builder: (dctx) => StatefulBuilder(
                                builder: (dctx, dset) {
                                  return AlertDialog(
                                    title: const Center(
                                      child: Text('Add Account'),
                                    ),
                                    content: SingleChildScrollView(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            children: [
                                              const Text('Type:'),
                                              const SizedBox(width: 12),
                                              DropdownButton<AccountType>(
                                                value: selectedType,
                                                onChanged: (v) {
                                                  if (v != null)
                                                    dset(
                                                      () => selectedType = v,
                                                    );
                                                },
                                                items: AccountType.values
                                                    .map(
                                                      (t) => DropdownMenuItem(
                                                        value: t,
                                                        child: Row(
                                                          children: [
                                                            AccountTypeIcon(
                                                              type: t,
                                                            ),
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            Text(
                                                              t == AccountType.bank
                                                                  ? 'Checking'
                                                                  : t == AccountType.investment
                                                                  ? 'Savings'
                                                                  : t.name,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    )
                                                    .toList(),
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.add_circle_outline,
                                                ),
                                                tooltip: 'Add custom type',
                                                onPressed: () async {
                                                  final textCtrl =
                                                      TextEditingController();
                                                  final res = await showDialog<String?>(
                                                    context: dctx,
                                                    builder: (tctx) => AlertDialog(
                                                      title: const Text(
                                                        'Add account type',
                                                      ),
                                                      content: TextField(
                                                        controller: textCtrl,
                                                        textCapitalization:
                                                            TextCapitalization
                                                                .sentences,
                                                        decoration:
                                                            const InputDecoration(
                                                              labelText:
                                                                  'Type name',
                                                            ),
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                tctx,
                                                              ),
                                                          child: const Text(
                                                            'Cancel',
                                                          ),
                                                        ),
                                                        TextButton(
                                                          onPressed: () {
                                                            final v = textCtrl
                                                                .text
                                                                .trim();
                                                            if (v.isEmpty)
                                                              return;
                                                            Navigator.pop(
                                                              tctx,
                                                              v,
                                                            );
                                                          },
                                                          child: const Text(
                                                            'Add',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  if (res != null)
                                                    dset(
                                                      () => customType = res,
                                                    );
                                                },
                                              ),
                                              if (customType != null)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        left: 8.0,
                                                      ),
                                                  child: Text(
                                                    '($customType)',
                                                    style: const TextStyle(
                                                      fontStyle:
                                                          FontStyle.italic,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          TextField(
                                            controller: nameCtrl,
                                            textCapitalization:
                                                TextCapitalization.words,
                                            autofillHints: const [
                                              AutofillHints.organizationName,
                                            ],
                                            decoration: const InputDecoration(
                                              labelText: 'Account',
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          TextField(
                                            controller: institutionCtrl,
                                            textCapitalization:
                                                TextCapitalization.words,
                                            autofillHints: const [
                                              AutofillHints.organizationName,
                                            ],
                                            decoration: const InputDecoration(
                                              labelText: 'Institution',
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          TextField(
                                            controller: accNumCtrl,
                                            autofillHints: const [
                                              AutofillHints.username,
                                            ],
                                            decoration: const InputDecoration(
                                              labelText: 'Account number',
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          TextField(
                                            controller: cardNumCtrl,
                                            decoration: const InputDecoration(
                                              labelText: 'Card number',
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          const SizedBox(height: 8),
                                          TextField(
                                            controller: balCtrl,
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            decoration: const InputDecoration(
                                              labelText: 'Initial balance',
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          TextField(
                                            controller: availCtrl,
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            decoration: const InputDecoration(
                                              labelText: 'Available balance',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(dctx),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          final name = nameCtrl.text.trim();
                                          if (name.isEmpty) return;
                                          final institution = institutionCtrl
                                              .text
                                              .trim();
                                          final accNum =
                                              accNumCtrl.text.trim().isEmpty
                                              ? null
                                              : accNumCtrl.text.trim();
                                          final cardNum =
                                              cardNumCtrl.text.trim().isEmpty
                                              ? null
                                              : cardNumCtrl.text.trim();
                                          final bal =
                                              double.tryParse(balCtrl.text) ??
                                              0.0;
                                          final avail = double.tryParse(
                                            availCtrl.text,
                                          );
                                          // Add custom type to database if provided
                                          if (customType != null &&
                                              customType!.isNotEmpty) {
                                            DatabaseService.addCustomAccountType(
                                              customType!,
                                            );
                                          }
                                          final acc = Account(
                                            name: name,
                                            type: selectedType,
                                            institution: institution.isEmpty
                                                ? null
                                                : institution,
                                            accountNumber: accNum,
                                            cardNumber: cardNum,
                                            balance: bal,
                                            availableBalance: avail,
                                            customType: customType,
                                          );
                                          Navigator.pop(dctx, acc);
                                        },
                                        child: const Text('Add'),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            );

                            if (res != null) {
                              await DatabaseService.addAccount(res);
                              final updated = DatabaseService.getAllAccounts();
                              setState2(() {});
                              setState(() {
                                accountList = updated;
                                _fromAccountId = res.id;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    body: ListView.builder(
                      itemCount: accountList.length,
                      itemBuilder: (context, idx) {
                        final a = accountList[idx];
                        return ListTile(
                          leading: a is Account
                              ? AccountTypeIcon(
                                  type: a.type,
                                  displayName: a.typeDisplayName,
                                )
                              : const Icon(
                                  Icons.account_balance_wallet_outlined,
                                ),
                          title: Text(
                            (a is Account) ? a.name : (a['name'] as String),
                          ),
                          onTap: () => Navigator.pop(
                            context,
                            (a is Account) ? a.id : (a['id'] as String),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          );
          if (selected != null) setState(() => _fromAccountId = selected);
        },
    );
  }

  Widget _buildToAccountSelector() {
    return ListTile(
        leading: _accountIconForId(_toAccountId, Icons.call_received),
        title: const Text('To'),
        subtitle: Text(
          _toAccountId == null
              ? 'Select to'
              : (() {
                  try {
                    final found = accountList.firstWhere(
                      (a) => a is Account
                          ? a.id == _toAccountId
                          : (a['id'] == _toAccountId),
                    );
                    if (found is Account) return found.name;
                    if (found is Map && found.containsKey('name'))
                      return found['name'] as String;
                  } catch (_) {}
                  return 'Unknown';
                }()),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () async {
          final selected = await showModalBottomSheet<String?>(
            context: context,
            isScrollControlled: true,
            builder: (ctx) => FractionallySizedBox(
              heightFactor: 0.85,
              child: StatefulBuilder(
                builder: (ctx2, setState2) {
                  return Scaffold(
                    appBar: AppBar(
                      title: const Text('Select Account'),
                      backgroundColor: Theme.of(ctx2).colorScheme.primary,
                      foregroundColor: Colors.white,
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () async {
                            final nameCtrl = TextEditingController();
                            final institutionCtrl = TextEditingController();
                            final accNumCtrl = TextEditingController();
                            final cardNumCtrl = TextEditingController();
                            AccountType selectedType = AccountType.cash;
                            final balCtrl = TextEditingController(text: '0.0');
                            final availCtrl = TextEditingController(
                              text: '0.0',
                            );
                            String? customType;
                            final res = await showDialog<Account?>(
                              context: ctx2,
                              builder: (dctx) => StatefulBuilder(
                                builder: (dctx, dset) {
                                  return AlertDialog(
                                    title: const Center(
                                      child: Text('Add Account'),
                                    ),
                                    content: SingleChildScrollView(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            children: [
                                              const Text('Type:'),
                                              const SizedBox(width: 12),
                                              DropdownButton<AccountType>(
                                                value: selectedType,
                                                onChanged: (v) {
                                                  if (v != null)
                                                    dset(
                                                      () => selectedType = v,
                                                    );
                                                },
                                                items: AccountType.values
                                                    .map(
                                                      (t) => DropdownMenuItem(
                                                        value: t,
                                                        child: Row(
                                                          children: [
                                                            AccountTypeIcon(
                                                              type: t,
                                                            ),
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            Text(
                                                              t == AccountType.bank
                                                                  ? 'Checking'
                                                                  : t == AccountType.investment
                                                                  ? 'Savings'
                                                                  : t.name,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    )
                                                    .toList(),
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.add_circle_outline,
                                                ),
                                                tooltip: 'Add custom type',
                                                onPressed: () async {
                                                  final textCtrl =
                                                      TextEditingController();
                                                  final res = await showDialog<String?>(
                                                    context: dctx,
                                                    builder: (tctx) => AlertDialog(
                                                      title: const Text(
                                                        'Add account type',
                                                      ),
                                                      content: TextField(
                                                        controller: textCtrl,
                                                        textCapitalization:
                                                            TextCapitalization
                                                                .sentences,
                                                        decoration:
                                                            const InputDecoration(
                                                              labelText:
                                                                  'Type name',
                                                            ),
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                tctx,
                                                              ),
                                                          child: const Text(
                                                            'Cancel',
                                                          ),
                                                        ),
                                                        TextButton(
                                                          onPressed: () {
                                                            final v = textCtrl
                                                                .text
                                                                .trim();
                                                            if (v.isEmpty)
                                                              return;
                                                            Navigator.pop(
                                                              tctx,
                                                              v,
                                                            );
                                                          },
                                                          child: const Text(
                                                            'Add',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  if (res != null)
                                                    dset(
                                                      () => customType = res,
                                                    );
                                                },
                                              ),
                                              if (customType != null)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        left: 8.0,
                                                      ),
                                                  child: Text(
                                                    '($customType)',
                                                    style: const TextStyle(
                                                      fontStyle:
                                                          FontStyle.italic,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          TextField(
                                            controller: nameCtrl,
                                            textCapitalization:
                                                TextCapitalization.words,
                                            autofillHints: const [
                                              AutofillHints.organizationName,
                                            ],
                                            decoration: const InputDecoration(
                                              labelText: 'Account',
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          TextField(
                                            controller: institutionCtrl,
                                            textCapitalization:
                                                TextCapitalization.words,
                                            autofillHints: const [
                                              AutofillHints.organizationName,
                                            ],
                                            decoration: const InputDecoration(
                                              labelText: 'Institution',
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          TextField(
                                            controller: accNumCtrl,
                                            autofillHints: const [
                                              AutofillHints.username,
                                            ],
                                            decoration: const InputDecoration(
                                              labelText: 'Account number',
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          TextField(
                                            controller: cardNumCtrl,
                                            decoration: const InputDecoration(
                                              labelText: 'Card number',
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          const SizedBox(height: 8),
                                          TextField(
                                            controller: balCtrl,
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            decoration: const InputDecoration(
                                              labelText: 'Initial balance',
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          TextField(
                                            controller: availCtrl,
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            decoration: const InputDecoration(
                                              labelText: 'Available balance',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(dctx),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          final name = nameCtrl.text.trim();
                                          if (name.isEmpty) return;
                                          final institution = institutionCtrl
                                              .text
                                              .trim();
                                          final accNum =
                                              accNumCtrl.text.trim().isEmpty
                                              ? null
                                              : accNumCtrl.text.trim();
                                          final cardNum =
                                              cardNumCtrl.text.trim().isEmpty
                                              ? null
                                              : cardNumCtrl.text.trim();
                                          final bal =
                                              double.tryParse(balCtrl.text) ??
                                              0.0;
                                          final avail = double.tryParse(
                                            availCtrl.text,
                                          );
                                          // Add custom type to database if provided
                                          if (customType != null &&
                                              customType!.isNotEmpty) {
                                            DatabaseService.addCustomAccountType(
                                              customType!,
                                            );
                                          }
                                          final acc = Account(
                                            name: name,
                                            type: selectedType,
                                            institution: institution.isEmpty
                                                ? null
                                                : institution,
                                            accountNumber: accNum,
                                            cardNumber: cardNum,
                                            balance: bal,
                                            availableBalance: avail,
                                            customType: customType,
                                          );
                                          Navigator.pop(dctx, acc);
                                        },
                                        child: const Text('Add'),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            );

                            if (res != null) {
                              await DatabaseService.addAccount(res);
                              final updated = DatabaseService.getAllAccounts();
                              setState2(() {});
                              setState(() {
                                accountList = updated;
                                _toAccountId = res.id;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    body: ListView.builder(
                      itemCount: accountList.length,
                      itemBuilder: (context, idx) {
                        final a = accountList[idx];
                        return ListTile(
                          leading: a is Account
                              ? AccountTypeIcon(
                                  type: a.type,
                                  displayName: a.typeDisplayName,
                                )
                              : const Icon(
                                  Icons.account_balance_wallet_outlined,
                                ),
                          title: Text(
                            (a is Account) ? a.name : (a['name'] as String),
                          ),
                          onTap: () => Navigator.pop(
                            context,
                            (a is Account) ? a.id : (a['id'] as String),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          );
          if (selected != null) setState(() => _toAccountId = selected);
        },
    );
  }

  Widget _buildCategorySelector() {
    final categoryForDisplay = _findCategoryById(
      _categories,
      _selectedCategoryId,
    );

    return ListTile(
        leading: categoryForDisplay == null
            ? const Icon(Icons.label)
            : Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: categoryForDisplay.color,
                  shape: BoxShape.circle,
                ),
              ),
        title: const Text('Category'),
        subtitle: Text(
          _selectedCategoryId == null
              ? 'Select'
              : (categoryForDisplay?.name ?? 'Select'),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () async {
         final selected = await Navigator.of(context).push<String>(
  MaterialPageRoute(
    builder: (_) => _CategorySelectorSheet(
      categories: _visibleCategories,
      initialSelectedId: _selectedCategoryId,
      billType: _billType,
    ),
  ),
);
          if (selected != null) {
            // refresh categories from storage in case new were added
            final updated = DatabaseService.getAllCategories();
            setState(() {
              _categories = updated;
              _selectedCategoryId = selected;
            });
          }
        },
    );
  }
  // Reminder toggle intentionally removed. Reminder state remains on the
  // Bill model but is not editable from the Add/Edit screen.

  Widget _buildSaveButton() {
  final colorScheme = Theme.of(context).colorScheme;

  return SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: _isSaving ? null : _saveBill,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: _isSaving
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                const Text('Saving...'),
              ],
            )
          : Text(
              widget.existingBill != null && !widget.isDuplicate
                  ? 'Save Changes'
                  : 'Save Bill',
            ),
    ),
  );
}

  void _refreshBillReminders() {
    BillReminderService().refreshAllReminders().catchError((e) {
      debugPrint('Reminder refresh failed after bill save: $e');
    });
  }

  Future<void> _saveBill() {
    return AccountOperations.bind(_accountGeneration, () async {
    if (_isSaving) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final cleanedAmountText = _amountController.text.replaceAll(
      RegExp(r'[^0-9.]'),
      '',
    );
    final amount = double.tryParse(cleanedAmountText);

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a valid amount'),
          backgroundColor: Colors.blueGrey[400],
        ),
      );
      return;
    }

    if ((_billType == BillType.expense || _billType == BillType.income) &&
        _selectedCategoryId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please select a category'),
            backgroundColor: Colors.blueGrey[400],
          ),
        );
      }
      return;
    }

    setState(() => _isSaving = true);

    final normalizedDueDate = DateTime(
      _dueDate.year,
      _dueDate.month,
      _dueDate.day,
    );

    final normalizedRecurrence = _recurrence;

    final normalizedRecurrenceEndDate = normalizedRecurrence == Recurrence.none
        ? null
        : (_recurrenceForever
              ? null
              : (_recurrenceEndDate == null
                    ? null
                    : DateTime(
                        _recurrenceEndDate!.year,
                        _recurrenceEndDate!.month,
                        _recurrenceEndDate!.day,
                      )));

    final List<int>? normalizedRecurrenceWeekdays =
        normalizedRecurrence == Recurrence.weekly
        ? (((_recurrenceWeekdays == null || _recurrenceWeekdays!.isEmpty)
                  ? <int>{normalizedDueDate.weekday}
                  : <int>{..._recurrenceWeekdays!, normalizedDueDate.weekday})
              .toList()
            ..sort())
        : null;

    final List<int>? normalizedCustomDays =
        normalizedRecurrence == Recurrence.monthly
        ? _normalizeMonthlyCustomDays(
            ((_customDays == null || _customDays!.isEmpty)
                ? <int>{normalizedDueDate.day}
                : <int>{..._customDays!}),
          )
        : null;

    final notes = _notesController.text.trim();
    final existingNotes = _initialNotes;

    String? description;

    if (_didUserEditNotes) {
      description = notes.isEmpty ? null : notes;
    } else if (existingNotes.isNotEmpty) {
      description = existingNotes;
    } else {
      description = null;
    }

    final Bill bill;

    if (widget.existingBill != null) {
      bill = widget.existingBill!.copyWith(
        amount: amount,
        description: description,
        dueDate: normalizedDueDate,
        recurrence: normalizedRecurrence,
        customDays: normalizedCustomDays,
        recurrenceEndDate: normalizedRecurrenceEndDate,
        recurrenceInterval: _recurrenceInterval,
        recurrenceWeekdays: normalizedRecurrenceWeekdays,
        categoryId: _selectedCategoryId,
        type: _billType,
        fromAccountId: _billType == BillType.transfer ? _fromAccountId : null,
        toAccountId: _billType == BillType.transfer ? _toAccountId : null,
        payeeId: _selectedPayeeId,
        accountId: _selectedAccountId,
      );
    } else {
      bill = Bill(
        amount: amount,
        description: description,
        dueDate: normalizedDueDate,
        recurrence: normalizedRecurrence,
        customDays: normalizedCustomDays,
        recurrenceEndDate: normalizedRecurrenceEndDate,
        recurrenceInterval: _recurrenceInterval,
        recurrenceWeekdays: normalizedRecurrenceWeekdays,
        categoryId: _selectedCategoryId,
        type: _billType,
        fromAccountId: _billType == BillType.transfer ? _fromAccountId : null,
        toAccountId: _billType == BillType.transfer ? _toAccountId : null,
        payeeId: _selectedPayeeId,
        accountId: _selectedAccountId,
        isPaid: false,
      );
    }

    try {
      if (widget.existingBill != null && !widget.isDuplicate) {
        await DatabaseService.updateBill(bill);
      } else {
        await DatabaseService.addBill(bill);
      }

      try {
        DatabaseService.billsVersion.value++;
      } catch (_) {}

      _refreshBillReminders();

      if (mounted) {
        Navigator.pop(context, widget.isDuplicate ? bill.id : true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving bill: $e'),
            backgroundColor: Colors.blueGrey[400],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
      });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }
}

class _RecurrenceResult {
  final Recurrence recurrence;
  final bool forever;
  final DateTime? endDate;
  final int interval;
  final Set<int> weekdays;
  final Set<int> customDays;

  const _RecurrenceResult({
    required this.recurrence,
    required this.forever,
    required this.endDate,
    required this.interval,
    required this.weekdays,
    required this.customDays,
  });
}

class _RecurrencePage extends StatefulWidget {
  final Recurrence recurrence;
  final bool forever;
  final DateTime? endDate;
  final int interval;
  final List<int>? weekdays;
  final List<int>? customDays;

  const _RecurrencePage({
    required this.recurrence,
    required this.forever,
    required this.endDate,
    required this.interval,
    required this.weekdays,
    required this.customDays,
  });

  @override
  State<_RecurrencePage> createState() =>
      _RecurrencePageState();
}

class _RecurrencePageState extends State<_RecurrencePage> {
  final int _accountGeneration = AccountOperations.generation;
  late Recurrence _recurrence;
  late bool _forever;
  DateTime? _endDate;
  late int _interval;

  late Set<int> _weekdays;
  late Set<int> _customDays;

  bool _showMonthlyDays = false;

  @override
  void initState() {
    super.initState();

    _recurrence = widget.recurrence;
    _forever = widget.forever;
    _endDate = widget.endDate;

    _interval =
        widget.interval <= 0 ? 1 : widget.interval;

    _weekdays = {
      ...?widget.weekdays,
    };

    _customDays = {
      ...?widget.customDays,
    };
  }

  void _cancel() {
    Navigator.of(context).pop();
  }

  void _save() {
    Navigator.of(context).pop(
      _RecurrenceResult(
        recurrence: _recurrence,
        forever: _forever,
        endDate: _forever ? null : _endDate,
        interval: _interval,
        weekdays: Set<int>.from(_weekdays),
        customDays: Set<int>.from(_customDays),
      ),
    );
  }

  String _unitName() {
    final singular = switch (_recurrence) {
      Recurrence.daily => 'day',
      Recurrence.weekly => 'week',
      Recurrence.monthly => 'month',
      Recurrence.yearly => 'year',
      _ => 'period',
    };

    return _interval == 1
        ? singular
        : '${singular}s';
  }

  Future<void> _chooseEndDate() {
    return AccountOperations.bind(_accountGeneration, () async {
    final now = DateTime.now();

    final initialDate =
        _endDate != null && _endDate!.isAfter(now)
            ? _endDate!
            : now.add(const Duration(days: 30));

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: now.add(
        const Duration(days: 3650),
      ),
    );

    if (!mounted || picked == null) return;

    setState(() {
      _endDate = picked;
      _forever = false;
    });
      });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Cancel',
          onPressed: _cancel,
          icon: const Icon(
            Icons.close_rounded,
          ),
        ),
        title: const Text('Recurrence'),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            20,
            24,
            20,
            32,
          ),
          children: [
            Text(
              'Choose how often this bill repeats.',
              style: TextStyle(
                fontSize: 15,
                color:
                    colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 28),

            _sectionLabel(
              context,
              'REPEATS',
            ),

            const SizedBox(height: 8),

            _buildRepeatCard(
              context,
            ),

            if (_recurrence != Recurrence.none) ...[
              const SizedBox(height: 24),

              _sectionLabel(
                context,
                'EVERY',
              ),

              const SizedBox(height: 8),

              _buildIntervalCard(
                context,
              ),

              if (_recurrence ==
                  Recurrence.weekly) ...[
                const SizedBox(height: 24),

                _sectionLabel(
                  context,
                  'ON THESE DAYS',
                ),

                const SizedBox(height: 8),

                _buildWeekdayCard(
                  context,
                ),
              ],

              if (_recurrence ==
                  Recurrence.monthly) ...[
                const SizedBox(height: 24),

                _sectionLabel(
                  context,
                  'ON THESE DATES',
                ),

                const SizedBox(height: 8),

                _buildMonthlyCard(
                  context,
                ),
              ],

              const SizedBox(height: 24),

              _sectionLabel(
                context,
                'ENDS',
              ),

              const SizedBox(height: 8),

              _buildEndCard(
                context,
              ),
            ],

            const SizedBox(height: 36),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancel,
                    style:
                        OutlinedButton.styleFrom(
                      minimumSize:
                          const Size.fromHeight(
                        52,
                      ),
                      shape:
                          RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(
                          12,
                        ),
                      ),
                    ),
                    child:
                        const Text('Cancel'),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: ElevatedButton(
                    onPressed: _save,
                    style:
                        ElevatedButton.styleFrom(
                      minimumSize:
                          const Size.fromHeight(
                        52,
                      ),
                      backgroundColor:
                          colorScheme.primary,
                      foregroundColor:
                          colorScheme.onPrimary,
                      shape:
                          RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(
                          12,
                        ),
                      ),
                    ),
                    child:
                        const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(
    BuildContext context,
    String text,
  ) {
    final colorScheme =
        Theme.of(context).colorScheme;

    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color:
            colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildRepeatCard(
    BuildContext context,
  ) {
    final colorScheme =
        Theme.of(context).colorScheme;

    final options = <Map<String, dynamic>>[
      {
        'value': Recurrence.none,
        'label': 'None',
        'icon': Icons.block_rounded,
      },
      {
        'value': Recurrence.daily,
        'label': 'Daily',
        'icon': Icons.today_outlined,
      },
      {
        'value': Recurrence.weekly,
        'label': 'Weekly',
        'icon':
            Icons.view_week_outlined,
      },
      {
        'value': Recurrence.monthly,
        'label': 'Monthly',
        'icon':
            Icons.calendar_month_outlined,
      },
      {
        'value': Recurrence.yearly,
        'label': 'Yearly',
        'icon': Icons.event_outlined,
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color:
            colorScheme.surfaceContainerLow,
        borderRadius:
            BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant
              .withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        children:
            List.generate(options.length, (index) {
          final option = options[index];

          final value =
              option['value'] as Recurrence;

          final selected =
              _recurrence == value;

          return Column(
            children: [
              InkWell(
                borderRadius:
                    BorderRadius.circular(
                  14,
                ),
                onTap: () {
                  setState(() {
                    _recurrence = value;
                  });
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 15,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        option['icon']
                            as IconData,
                        color: selected
                            ? colorScheme
                                .primary
                            : colorScheme
                                .onSurfaceVariant,
                      ),

                      const SizedBox(
                        width: 14,
                      ),

                      Expanded(
                        child: Text(
                          option['label']
                              as String,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight:
                                selected
                                    ? FontWeight
                                        .w600
                                    : FontWeight
                                        .w500,
                          ),
                        ),
                      ),

                      if (selected)
                        Icon(
                          Icons
                              .check_circle_rounded,
                          color: colorScheme
                              .primary,
                        )
                      else
                        Icon(
                          Icons
                              .circle_outlined,
                          color: colorScheme
                              .outline,
                        ),
                    ],
                  ),
                ),
              ),

              if (index !=
                  options.length - 1)
                Divider(
                  height: 1,
                  indent: 54,
                  color: colorScheme
                      .outlineVariant
                      .withValues(
                    alpha: 0.4,
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildIntervalCard(
    BuildContext context,
  ) {
    final colorScheme =
        Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color:
            colorScheme.surfaceContainerLow,
        borderRadius:
            BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant
              .withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          const Text(
            'Every',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),

          const Spacer(),

          IconButton(
            tooltip: 'Decrease',
            onPressed: _interval > 1
                ? () {
                    setState(() {
                      _interval--;
                    });
                  }
                : null,
            icon: const Icon(
              Icons
                  .remove_circle_outline_rounded,
            ),
          ),

          Container(
            constraints:
                const BoxConstraints(
              minWidth: 44,
            ),
            padding:
                const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius:
                  BorderRadius.circular(
                10,
              ),
              border: Border.all(
                color: colorScheme
                    .outlineVariant,
              ),
            ),
            child: Text(
              '$_interval',
              style: const TextStyle(
                fontSize: 16,
                fontWeight:
                    FontWeight.w600,
              ),
            ),
          ),

          IconButton(
            tooltip: 'Increase',
            onPressed: () {
              setState(() {
                _interval++;
              });
            },
            icon: const Icon(
              Icons
                  .add_circle_outline_rounded,
            ),
          ),

          SizedBox(
            width: 62,
            child: Text(
              _unitName(),
              style: TextStyle(
                fontSize: 15,
                color: colorScheme
                    .onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekdayCard(
    BuildContext context,
  ) {
    final colorScheme =
        Theme.of(context).colorScheme;

    const names = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            colorScheme.surfaceContainerLow,
        borderRadius:
            BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant
              .withValues(alpha: 0.45),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children:
            List.generate(7, (index) {
          final day = index + 1;

          return ChoiceChip(
            label: Text(names[index]),
            selected:
                _weekdays.contains(day),
            onSelected: (selected) {
              setState(() {
                if (selected) {
                  _weekdays.add(day);
                } else {
                  _weekdays.remove(day);
                }
              });
            },
          );
        }),
      ),
    );
  }

  Widget _buildMonthlyCard(
    BuildContext context,
  ) {
    final colorScheme =
        Theme.of(context).colorScheme;

    String summary;

    if (_customDays.isEmpty) {
      summary = 'Uses the bill due date';
    } else if (_customDays.contains(99)) {
      summary = 'Last day of the month';
    } else {
      final days =
          _customDays.toList()..sort();

      summary = days.join(', ');
    }

    return Container(
      decoration: BoxDecoration(
        color:
            colorScheme.surfaceContainerLow,
        borderRadius:
            BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant
              .withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius:
                BorderRadius.circular(14),
            onTap: () {
              setState(() {
                _showMonthlyDays =
                    !_showMonthlyDays;
              });
            },
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons
                        .calendar_today_outlined,
                    color: colorScheme
                        .onSurfaceVariant,
                  ),

                  const SizedBox(width: 14),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        const Text(
                          'Monthly dates',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight:
                                FontWeight
                                    .w600,
                          ),
                        ),
                        const SizedBox(
                          height: 3,
                        ),
                        Text(
                          summary,
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Icon(
                    _showMonthlyDays
                        ? Icons
                            .expand_less_rounded
                        : Icons
                            .expand_more_rounded,
                  ),
                ],
              ),
            ),
          ),

          if (_showMonthlyDays) ...[
            Divider(
              height: 1,
              color: colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.4),
            ),

            Padding(
              padding:
                  const EdgeInsets.all(14),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ...List.generate(
                    31,
                    (index) {
                      final day =
                          index + 1;

                      return FilterChip(
                        label: Text(
                          '$day',
                        ),
                        selected:
                            _customDays
                                .contains(day),
                        onSelected:
                            (selected) {
                          setState(() {
                            if (selected) {
                              _customDays
                                  .remove(99);
                              _customDays
                                  .add(day);
                            } else {
                              _customDays
                                  .remove(day);
                            }
                          });
                        },
                      );
                    },
                  ),

                  FilterChip(
                    label:
                        const Text(
                      'Last day',
                    ),
                    selected:
                        _customDays
                            .contains(99),
                    onSelected:
                        (selected) {
                      setState(() {
                        if (selected) {
                          _customDays
                            ..clear()
                            ..add(99);
                        } else {
                          _customDays
                              .remove(99);
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEndCard(
    BuildContext context,
  ) {
    final colorScheme =
        Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color:
            colorScheme.surfaceContainerLow,
        borderRadius:
            BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant
              .withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius:
                const BorderRadius.vertical(
              top: Radius.circular(14),
            ),
            onTap: () {
              setState(() {
                _forever = true;
                _endDate = null;
              });
            },
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons
                        .all_inclusive_rounded,
                  ),

                  const SizedBox(width: 14),

                  const Expanded(
                    child: Text(
                      'Forever',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight:
                            FontWeight.w500,
                      ),
                    ),
                  ),

                  Icon(
                    _forever
                        ? Icons
                            .check_circle_rounded
                        : Icons
                            .circle_outlined,
                    color: _forever
                        ? colorScheme.primary
                        : colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),

          Divider(
            height: 1,
            indent: 54,
            color: colorScheme
                .outlineVariant
                .withValues(alpha: 0.4),
          ),

          InkWell(
            borderRadius:
                const BorderRadius.vertical(
              bottom: Radius.circular(14),
            ),
            onTap: () async {
              if (_forever ||
                  _endDate == null) {
                await _chooseEndDate();
              } else {
                setState(() {
                  _forever = false;
                });
              }
            },
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.event_outlined,
                  ),

                  const SizedBox(width: 14),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        const Text(
                          'On date',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight:
                                FontWeight
                                    .w500,
                          ),
                        ),

                        if (!_forever &&
                            _endDate !=
                                null) ...[
                          const SizedBox(
                            height: 3,
                          ),
                          Text(
                            DateFormat.yMMMd()
                                .format(
                              _endDate!,
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  if (!_forever)
                    IconButton(
                      tooltip:
                          'Change end date',
                      onPressed:
                          _chooseEndDate,
                      icon: Icon(
                        Icons
                            .calendar_month_outlined,
                        color: colorScheme
                            .primary,
                      ),
                    )
                  else
                    Icon(
                      Icons.circle_outlined,
                      color: colorScheme
                          .outline,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
