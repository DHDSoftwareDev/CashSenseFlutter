// ignore_for_file: deprecated_member_use, unused_element, unused_local_variable, unnecessary_null_comparison, unused_field, use_build_context_synchronously, prefer_conditional_assignment, unrelated_type_equality_checks, prefer_null_aware_operators, prefer_interpolation_to_compose_strings, dead_code, unnecessary_null_in_if_null_operators

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/transaction.dart';
import '../models/category.dart';
import '../models/bill.dart';
import '../models/account.dart';
import '../services/database_service.dart';
import '../widgets/app_color_picker.dart';
import '../widgets/splits_editor.dart';
import '../utils/split_utils.dart';
import 'dart:convert';

// Marker used to indicate a transaction should not appear on the calendar/dashboard
const String _hideFromCalendarMarker = '__hide_from_calendar__';

enum TransactionScreenType { expense, income, transfer }

class AddTransactionScreen extends StatefulWidget {
  final Transaction? existingTransaction;
  final Transaction? prefillTransaction;
  final bool isDuplicate;
  final bool preserveDescriptionAndDate;
  final String? initialAccountId;
  final bool hideFromCalendarDashboard;
  const AddTransactionScreen({
    super.key,
    this.existingTransaction,
    this.prefillTransaction,
    this.isDuplicate = false,
    this.preserveDescriptionAndDate = false,
    this.initialAccountId,
    this.hideFromCalendarDashboard = false,
  });

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  // Add back the missing _buildNotesField method
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  List<Map<String, dynamic>> _splits = [];
  bool _useSplits = false;
  bool _isSaving = false;

  TransactionScreenType _transactionType = TransactionScreenType.expense;

  DateTime _transactionDate = DateTime.now();
  String? _selectedPayeeId;
  String? _selectedAccountId;
  // Transfer-specific accounts
  String? _fromAccountId;
  String? _toAccountId;

  List<Map<String, dynamic>> get _payees => DatabaseService.getAllPayees();
  List<Account> get accountList => DatabaseService.getAllAccounts();
  List<Category> get _categories => DatabaseService.getAllCategories();
  String? _selectedCategoryId;

  List<Map<String, dynamic>> get _visiblePayees {
    if (_transactionType == TransactionScreenType.expense) {
      return _payees.where((p) => (p['type'] as String?) == 'payee').toList();
    } else if (_transactionType == TransactionScreenType.income) {
      return _payees.where((p) => (p['type'] as String?) == 'payer').toList();
    }
    return _payees;
  }

  List<Category> get _visibleCategories {
    if (_transactionType == TransactionScreenType.expense) {
      return _categories.where((c) => c.type == CategoryType.expense).toList();
    } else if (_transactionType == TransactionScreenType.income) {
      return _categories.where((c) => c.type == CategoryType.income).toList();
    }
    return _categories;
  }

  VoidCallback? _categoriesListener;
  bool _cleared = false;
  bool _showInReports = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
  title: Text(widget.existingTransaction != null ? 'Edit Transaction' : (widget.isDuplicate ? 'Add Transaction' : 'Add Transaction')),
  centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildTypeToggle(),
            const SizedBox(height: 12),
            _buildAmountField(),
            const SizedBox(height: 16),
            if (_transactionType == TransactionScreenType.transfer) ...[
              _buildFromAccountSelector(),
              const SizedBox(height: 12),
              _buildToAccountSelector(),
            ] else ...[
              _buildPayeeSelector(),
              const SizedBox(height: 12),
              _buildCategorySelector(),
              const SizedBox(height: 12),
              if (_useSplits)
                SplitsEditor(
                  initialSplits: _splits,
                  transactionAmount: double.tryParse(_amountController.text) ?? null,
                  onChanged: (s) => _splits = s,
                  categoryTypeFilter: _transactionType == TransactionScreenType.income ? CategoryType.income : CategoryType.expense,
                ),
              const SizedBox(height: 12),
              _buildAccountSelector(),
            ],
            const SizedBox(height: 8),
              _buildClearedToggle(),
            const SizedBox(height: 8),
            _buildShowInReportsToggle(),
            _buildDateSelector(),
            const SizedBox(height: 12),
            _buildNotesField(),
            const SizedBox(height: 16),
            const SizedBox(height: 32),
            _buildSaveButton(),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (_categoriesListener != null) DatabaseService.categoriesVersion.removeListener(_categoriesListener!);
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Widget _buildTypeToggle() {
    return Card(
      child: ListTile(
        title: Center(
          child: ToggleButtons(
            isSelected: [
              _transactionType == TransactionScreenType.expense,
              _transactionType == TransactionScreenType.income,
              _transactionType == TransactionScreenType.transfer,
            ],
            onPressed: (index) {
              setState(() {
                _transactionType = TransactionScreenType.values[index];
                _selectedPayeeId = null;
                _selectedCategoryId = null;
                // Only clear account selections when switching to/from transfer
                if (_transactionType == TransactionScreenType.transfer) {
                  _showInReports = false;
                  _selectedAccountId = null;
                  _fromAccountId = null;
                  _toAccountId = null;
                }
                // Otherwise, preserve _selectedAccountId for expense/income
              });
            },
            children: const [
              Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Expense')),
              Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Income')),
              Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Transfer')),
            ],
          ),
        ),
        onTap: () {
          // No-op tap so it visually behaves like other list tiles
        },
      ),
    );
  }

  Widget _buildAmountField() {
    return TextFormField(
      controller: _amountController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: 'Amount',
        prefixText: '\$ ',
        hintText: '0.00',
        prefixStyle: TextStyle(
          color: _transactionType == TransactionScreenType.income
              ? AppTheme.incomeGreen
              : (_transactionType == TransactionScreenType.expense ? AppTheme.expenseRed : null),
        ),
        suffixIcon: IconButton(
          icon: const Icon(Icons.calculate),
          onPressed: () async {
            final result = await showModalBottomSheet<double?>(
              context: context,
              isScrollControlled: true,
              builder: (_) => FractionallySizedBox(
                heightFactor: 0.6,
                child: _CalculatorSheet(initialValue: _amountController.text),
              ),
            );
            if (result != null) {
              setState(() {
                _amountController.text = result.toStringAsFixed(2);
              });
            }
          },
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return 'Please enter an amount';
        final v = double.tryParse(value);
        if (v == null || v <= 0) return 'Please enter a valid amount';
        return null;
      },
    );
  }

  Widget _buildPayeeSelector() {
  // Always refresh payees before showing selector
  List<Map<String, dynamic>> payees = DatabaseService.getAllPayees();
  final payeeName = _selectedPayeeId != null
    ? payees.firstWhere((p) => p['id'].toString() == _selectedPayeeId, orElse: () => {'name': 'Unknown'})['name']
    : null;

    return Card(
      child: ListTile(
        leading: const Icon(Icons.person),
        title: Text(_transactionType == TransactionScreenType.expense ? 'Payee' : 'Payer'),
        subtitle: Text(
          payeeName ?? (_transactionType == TransactionScreenType.expense ? 'Select payee' : 'Select payer'),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () async {
          // Always refresh payees before showing selector
          payees = DatabaseService.getAllPayees();
          final selected = await showModalBottomSheet<String?>(
            context: context,
            isScrollControlled: true,
            builder: (_) => FractionallySizedBox(
              heightFactor: 0.85,
              child: Scaffold(
                appBar: AppBar(
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  title: Text('Select ${_transactionType == TransactionScreenType.expense ? 'Payee' : 'Payer'}'),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: 'Add',
                      onPressed: () async {
                        final nameController = TextEditingController();
                        String? selectedCatId;
                        Color selectedColor = const Color(0xFF607D8B);
                        final categories = _transactionType == TransactionScreenType.expense
                            ? DatabaseService.getAllCategories().where((cat) => cat.type == CategoryType.expense).toList()
                            : DatabaseService.getAllCategories().where((cat) => cat.type == CategoryType.income).toList();
                        final result = await showDialog<Map<String, dynamic>?>(
                          context: context,
                          builder: (ctx) {
                            String? dialogCatId = selectedCatId;
                            return StatefulBuilder(
                              builder: (ctx, setState) => AlertDialog(
                                title: Text('Add ${_transactionType == TransactionScreenType.expense ? 'Payee' : 'Payer'}'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextField(
                                      controller: nameController,
                                      textCapitalization: TextCapitalization.sentences,
                                      decoration: const InputDecoration(labelText: 'Name'),
                                    ),
                                    const SizedBox(height: 12),
                                    InkWell(
                                      onTap: () async {
                                        final allCategories = DatabaseService.getAllCategories();
                                        final filteredCats = _transactionType == TransactionScreenType.expense
                                            ? allCategories.where((c) => c.type == CategoryType.expense).toList()
                                            : allCategories.where((c) => c.type == CategoryType.income).toList();
                                        final picked = await showModalBottomSheet<String?>(
                                          context: ctx,
                                          isScrollControlled: true,
                                          builder: (_) => FractionallySizedBox(
                                            heightFactor: 0.85,
                                            child: Scaffold(
                                              appBar: AppBar(
                                                leading: IconButton(
                                                  icon: const Icon(Icons.arrow_back),
                                                  onPressed: () => Navigator.pop(ctx),
                                                ),
                                                title: const Text('Select Category'),
                                                backgroundColor: Theme.of(ctx).colorScheme.primary,
                                                foregroundColor: Colors.white,
                                                elevation: 0,
                                                actions: [
                                                  IconButton(
                                                    icon: const Icon(Icons.add),
                                                    tooltip: 'Add',
                                                    onPressed: () async {
                                                      final nameController = TextEditingController();
                                                      final imageController = TextEditingController();
                                                      Color selectedColor = const Color(0xFF607D8B);
                                                      final result = await showDialog<Category?>(
                                                        context: ctx,
                                                        builder: (dctx) => StatefulBuilder(
                                                          builder: (dctx, setState) => AlertDialog(
                                                            title: const Text('Add Category'),
                                                            content: Column(
                                                              mainAxisSize: MainAxisSize.min,
                                                              children: [
                                                                TextField(
                                                                  controller: nameController,
                                                                  textCapitalization: TextCapitalization.sentences,
                                                                  decoration: const InputDecoration(labelText: 'Name'),
                                                                ),
                                                                const SizedBox(height: 8),
                                                                TextField(
                                                                  controller: imageController,
                                                                  decoration: const InputDecoration(labelText: 'Emoji (optional)', hintText: 'Emoji'),
                                                                ),
                                                                const SizedBox(height: 8),
                                                                GestureDetector(
                                                                  onTap: () async {
                                                                    final picked = await showAppColorPicker(
                                                                      context: dctx,
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
                                                                      const Text('Color'),
                                                                      const Spacer(),
                                                                      const Icon(Icons.color_lens_outlined, size: 20),
                                                                    ],
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                            actions: [
                                                              TextButton(
                                                                onPressed: () => Navigator.pop(dctx),
                                                                child: const Text('Cancel'),
                                                              ),
                                                              TextButton(
                                                                onPressed: () {
                                                                  final name = nameController.text.trim();
                                                                  if (name.isEmpty) return;
                                                                  final newCat = Category(
                                                                    name: name,
                                                                    iconCodePoint: '0xe85d',
                                                                    colorValue: selectedColor.value.toString(),
                                                                    type: _transactionType == TransactionScreenType.expense ? CategoryType.expense : CategoryType.income,
                                                                    image: imageController.text.trim().isNotEmpty ? imageController.text.trim() : null,
                                                                  );
                                                                  Navigator.pop(dctx, newCat);
                                                                },
                                                                child: const Text('Add'),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      );
                                                      if (result != null) {
                                                        await DatabaseService.addCategory(result);
                                                        setState(() {});
                                                      }
                                                    },
                                                  ),
                                                ],
                                              ),
                                              body: _CategorySelectorSheet(
                                                categories: filteredCats,
                                                hideAddButton: true,
                                              ),
                                            ),
                                          ),
                                        );
                                        if (picked != null) setState(() => dialogCatId = picked);
                                      },
                                      child: InputDecorator(
                                        decoration: const InputDecoration(labelText: 'Category'),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(child: Text(dialogCatId == null ? 'Select Category' : (DatabaseService.getCategoryById(dialogCatId ?? '')?.name ?? ''))),
                                            const Icon(Icons.arrow_drop_down),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    GestureDetector(
                                      onTap: () async {
                                        final picked = await showAppColorPicker(
                                          context: ctx,
                                          initialColor: selectedColor,
                                          title: 'Pick Payee/Payer Color',
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
                                          const Text('Color'),
                                          const Spacer(),
                                          const Icon(Icons.color_lens_outlined, size: 20),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      final name = nameController.text.trim();
                                      if (name.isEmpty) return;
                                      final newId = DateTime.now().millisecondsSinceEpoch.toString();
                                      Navigator.pop(ctx, {
                                        'id': newId,
                                        'name': nameController.text.trim(),
                                        'type': _transactionType == TransactionScreenType.expense ? 'payee' : 'payer',
                                        'categoryId': dialogCatId,
                                        'color': selectedColor.value.toString(),
                                      });
                                    },
                                    child: const Text('Add'),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                        if (result != null) {
                          await DatabaseService.addPayee(result);
                          // Refresh payees after adding
                          payees = DatabaseService.getAllPayees();
                          Navigator.pop(context, result['id'] as String?);
                        }
                      },
                    ),
                  ],
                ),
                body: _PayeeSelectorSheet(
                  payees: _transactionType == TransactionScreenType.expense
                      ? payees.where((p) => (p['type'] as String?) == 'payee').toList()
                      : payees.where((p) => (p['type'] as String?) == 'payer').toList(),
                  type: _transactionType == TransactionScreenType.expense ? 'payee' : 'payer',
                ),
              ),
            ),
          );
          // Always refresh payees in case user added one. If a payee id was returned, select it and autofill category.
          if (mounted) {
            setState(() {
              // Force re-evaluation of getters that read DatabaseService
              payees = DatabaseService.getAllPayees();
            });
          }
          if (selected != null) {
            // selected may be the id of a newly added payee or an existing id returned from the sheet
            final payee = payees.firstWhere((p) => p['id'].toString() == selected, orElse: () => <String, dynamic>{});
            String? rawCatId;
            if (payee.isNotEmpty && payee.containsKey('categoryId')) rawCatId = payee['categoryId'] as String?;
            String? catId;
            if (rawCatId != null) {
              final lower = rawCatId.toLowerCase();
              if (lower != 'null' && rawCatId.isNotEmpty) catId = rawCatId;
            }
            final hasValidCategory = catId != null && DatabaseService.getAllCategories().any((c) => c.id == catId);
            setState(() {
              _selectedPayeeId = selected.isEmpty ? null : selected;
              if (hasValidCategory) {
                _selectedCategoryId = catId;
              }
            });
          }
        },
      ),
    );
  }

  Widget _buildCategorySelector() {
  Category? selectedCategory = _selectedCategoryId != null
      ? (() {
          final cat = _categories.firstWhere(
            (c) => c.id == _selectedCategoryId,
            orElse: () => Category(name: 'Unknown', iconCodePoint: '0xe85d', colorValue: '0xFF607D8B', type: CategoryType.expense),
          );
          return cat.id == _selectedCategoryId ? cat : null;
        })()
      : null;
  String? categoryName = _transactionType == TransactionScreenType.transfer
      ? 'Transfer'
      : selectedCategory?.name;

  Widget? leadingWidget;
  if (selectedCategory != null) {
    final emoji = selectedCategory.displayEmoji;
    if (emoji != null) {
      leadingWidget = Text(emoji, style: TextStyle(fontSize: 24, color: selectedCategory.color));
    } else {
      leadingWidget = Icon(selectedCategory.icon, color: selectedCategory.color);
    }
  } else {
    leadingWidget = const Icon(Icons.label);
  }

  return Card(
    child: ListTile(
      leading: leadingWidget,
      title: const Text('Category'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(categoryName ?? 'Select'),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: () {
                setState(() {
                  _useSplits = !_useSplits;
                  if (!_useSplits) _splits = [];
                });
              },
              child: Text(
                _useSplits ? 'Disable splits' : 'Use splits',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () async {
          final allCategories = DatabaseService.getAllCategories();
          final filteredCats = _transactionType == TransactionScreenType.expense
              ? allCategories.where((c) => c.type == CategoryType.expense).toList()
              : _transactionType == TransactionScreenType.income
                  ? allCategories.where((c) => c.type == CategoryType.income).toList()
                  : allCategories;
          final selected = await showModalBottomSheet<String?>(
            context: context,
            isScrollControlled: true,
            builder: (_) => FractionallySizedBox(
              heightFactor: 0.85,
              child: Scaffold(
                appBar: AppBar(
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  title: const Text('Select Category'),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: 'Add',
                      onPressed: () async {
                        final nameController = TextEditingController();
                        final imageController = TextEditingController();
                        Color selectedColor = const Color(0xFF607D8B);
                        final result = await showDialog<Category?>(
                          context: context,
                          builder: (ctx) => StatefulBuilder(
                            builder: (ctx, setState) => AlertDialog(
                              title: const Text('Add Category'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(
                                    controller: nameController,
                                    textCapitalization: TextCapitalization.sentences,
                                    decoration: const InputDecoration(labelText: 'Name'),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: imageController,
                                    textCapitalization: TextCapitalization.sentences,
                                    decoration: const InputDecoration(
                                      labelText: 'Image (optional)',
                                      hintText: 'Image',
                                    ),
                                    onChanged: (v) {
                                      final chars = v.characters;
                                      final first = chars.isEmpty ? '' : chars.first;
                                      if (first != v) {
                                        imageController.text = first;
                                        imageController.selection = TextSelection.collapsed(offset: first.length);
                                      }
                                    },
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
                                        type: (_transactionType == TransactionScreenType.expense) ? CategoryType.expense : CategoryType.income,
                                        image: imageController.text.trim().isEmpty ? null : imageController.text.trim(),
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
                          Navigator.pop(context, newCatId); // Return new category id so it can be auto-selected
                        }
                      },
                    ),
                  ],
                ),
                body: _CategorySelectorSheet(categories: filteredCats, hideAddButton: true),
              ),
            ),
          );
          if (selected != null) {
            setState(() {
              _selectedCategoryId = selected;
            });
          }
        },
      ),
    );
  }

  Widget _buildAccountSelector() {
    final accountName = _selectedAccountId != null
        ? accountList.firstWhere((a) => a.id == _selectedAccountId, orElse: () => Account(name: 'Unknown', type: AccountType.bank, balance: 0)).name
        : null;
    return Card(
      elevation: 1,
      child: ListTile(
        leading: const Icon(Icons.account_balance_wallet),
        title: const Text('Account'),
        subtitle: Text(accountName ?? 'Select'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () async {
          final selected = await showModalBottomSheet<String?>(
            context: context,
            isScrollControlled: true,
            builder: (ctx) => FractionallySizedBox(
              heightFactor: 0.85,
              child: StatefulBuilder(builder: (ctx2, setState2) {
                List<Account> liveAccounts = DatabaseService.getAllAccounts();
                return Scaffold(
                  appBar: AppBar(
                    title: const Text('Select Account'),
                    backgroundColor: Theme.of(ctx2).colorScheme.primary,
                    foregroundColor: Colors.white,
                    actions: [
                      IconButton(
                        icon: Icon(Icons.add),
                        onPressed: () async {
                          final plan = DatabaseService.getSetting<String>('subscriptionPlan', 'Free') ?? 'Free';
                          final accounts = DatabaseService.getAllAccounts();
                          if (plan == 'Free' && accounts.length >= 3) {
                            await showDialog(
                              context: ctx2,
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
                          // Show add account dialog
                          final nameCtrl = TextEditingController();
                          final institutionCtrl = TextEditingController();
                          final accNumCtrl = TextEditingController();
                          AccountType selectedType = AccountType.cash;
                          final balCtrl = TextEditingController(text: '0.0');
                          final availCtrl = TextEditingController(text: '0.0');
                          String? customType;
                          final res = await showDialog<Account?>(
                            context: ctx2,
                            builder: (dctx) => StatefulBuilder(builder: (dctx, dset) {
                              return AlertDialog(
                                title: const Center(child: Text('Add Account')),
                                content: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(children: [
                                        const Text('Type:'),
                                        const SizedBox(width: 12),
                                        DropdownButton<String>(
                                          value: customType ?? selectedType.name,
                                          onChanged: (v) {
                                            if (v == null) return;
                                            final match = AccountType.values.firstWhere(
                                              (t) => t.name.toLowerCase() == v.toLowerCase(),
                                              orElse: () => AccountType.cash,
                                            );
                                            if (AccountType.values.map((t) => t.name.toLowerCase()).contains(v.toLowerCase())) {
                                              dset(() {
                                                selectedType = match;
                                                customType = null;
                                              });
                                            } else {
                                              dset(() => customType = v);
                                            }
                                          },
                                          items: ([...AccountType.values.map((t) => t.name), ...DatabaseService.getAllCustomAccountTypes()])
                                            .toSet()
                                            .map((type) => DropdownMenuItem(
                                              value: type,
                                              child: Text(type.isNotEmpty ? type[0].toUpperCase() + type.substring(1) : type),
                                            ))
                                            .toList(),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.add_circle_outline),
                                          tooltip: 'Add custom type',
                                          onPressed: () async {
                                            final textCtrl = TextEditingController();
                                            final res = await showDialog<String?>(
                                              context: dctx,
                                              builder: (tctx) => AlertDialog(
                                                title: const Text('Add account type'),
                                                content: TextField(controller: textCtrl, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Type name')),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(tctx), child: const Text('Cancel')),
                                                  TextButton(onPressed: () {
                                                    final v = textCtrl.text.trim();
                                                    if (v.isEmpty) return;
                                                    Navigator.pop(tctx, v);
                                                  }, child: const Text('Add')),
                                                ],
                                              ),
                                            );
                                            if (res != null) dset(() => customType = res);
                                          },
                                        ),
                                        if (customType != null) Padding(padding: const EdgeInsets.only(left:8.0), child: Text('($customType)', style: const TextStyle(fontStyle: FontStyle.italic))),
                                      ]),
                                      const SizedBox(height: 8),
                                      TextField(controller: nameCtrl, textCapitalization: TextCapitalization.words, autofillHints: const [AutofillHints.organizationName], decoration: const InputDecoration(labelText: 'Account')),
                                      const SizedBox(height: 8),
                                      TextField(controller: institutionCtrl, textCapitalization: TextCapitalization.words, autofillHints: const [AutofillHints.organizationName], decoration: const InputDecoration(labelText: 'Institution')),
                                      const SizedBox(height: 8),
                                      TextField(controller: accNumCtrl, autofillHints: const [AutofillHints.username], decoration: const InputDecoration(labelText: 'Account number')),
                                      const SizedBox(height: 8),
                                      const SizedBox(height: 8),
                                      TextField(controller: balCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Initial balance')),
                                      const SizedBox(height: 8),
                                      TextField(controller: availCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Available balance')),
                                    ],
                                  ),
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
                                  TextButton(onPressed: () {
                                    final name = nameCtrl.text.trim();
                                    if (name.isEmpty) return;
                                    final institution = institutionCtrl.text.trim();
                                    final accNum = accNumCtrl.text.trim().isEmpty ? null : accNumCtrl.text.trim();
                                    final bal = double.tryParse(balCtrl.text) ?? 0.0;
                                    final avail = double.tryParse(availCtrl.text);
                                    if (customType != null && customType!.isNotEmpty) {
                                      DatabaseService.addCustomAccountType(customType!);
                                    }
                                    final acc = Account(name: name, type: selectedType, balance: bal, accountNumber: accNum, availableBalance: avail, description: institution.isEmpty ? null : institution, customType: customType);
                                    Navigator.pop(dctx, acc);
                                  }, child: const Text('Add')),
                                ],
                              );
                            }),
                          );
                          if (res != null) {
                            await DatabaseService.addAccount(res);
                            final updated = DatabaseService.getAllAccounts();
                            setState2(() {});
                            setState(() {
                              _selectedAccountId = res.id;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  body: ListView.builder(
                    itemCount: liveAccounts.length,
                    itemBuilder: (context, idx) {
                      final a = liveAccounts[idx];
                      return ListTile(
                        title: Text(a.name),
                        selected: _selectedAccountId == a.id,
                        onTap: () => Navigator.pop(context, a.id),
                      );
                    },
                  ),
                );
              }),
            ),
          );
          if (selected != null) {
            setState(() => _selectedAccountId = selected);
          }
        },
      ),
    );
  }

  Widget _buildFromAccountSelector() {
    final accountName = _fromAccountId != null
        ? accountList.firstWhere((a) => a.id == _fromAccountId, orElse: () => Account(name: 'Unknown', type: AccountType.bank, balance: 0)).name
        : null;
    return Card(
      elevation: 1,
      child: ListTile(
        leading: const Icon(Icons.account_balance_wallet),
        title: const Text('From Account'),
        subtitle: Text(accountName ?? 'Select account'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () async {
          final selected = await showModalBottomSheet<String?>(
            context: context,
            isScrollControlled: true,
            builder: (ctx) => FractionallySizedBox(
              heightFactor: 0.85,
              child: StatefulBuilder(builder: (ctx2, setState2) {
                List<Account> liveAccounts = DatabaseService.getAllAccounts();
                return Scaffold(
                  appBar: AppBar(
                    title: const Text('Select Account'),
                    backgroundColor: Theme.of(ctx2).colorScheme.primary,
                    foregroundColor: Colors.white,
                    actions: [
                      IconButton(
                        icon: Icon(Icons.add),
                        onPressed: () async {
                          final plan = DatabaseService.getSetting<String>('subscriptionPlan', 'Free') ?? 'Free';
                          final accounts = DatabaseService.getAllAccounts();
                          if (plan == 'Free' && accounts.length >= 3) {
                            await showDialog(
                              context: ctx2,
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
                          // Show add account dialog
                          final nameCtrl = TextEditingController();
                          final institutionCtrl = TextEditingController();
                          final accNumCtrl = TextEditingController();
                          AccountType selectedType = AccountType.cash;
                          final balCtrl = TextEditingController(text: '0.0');
                          final availCtrl = TextEditingController(text: '0.0');
                          String? customType;
                          final res = await showDialog<Account?>(
                            context: ctx2,
                            builder: (dctx) => StatefulBuilder(builder: (dctx, dset) {
                              return AlertDialog(
                                title: const Center(child: Text('Add Account')),
                                content: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(children: [
                                        const Text('Type:'),
                                        const SizedBox(width: 12),
                                        DropdownButton<String>(
                                          value: customType ?? selectedType.name,
                                          onChanged: (v) {
                                            if (v == null) return;
                                            final match = AccountType.values.firstWhere(
                                              (t) => t.name.toLowerCase() == v.toLowerCase(),
                                              orElse: () => AccountType.cash,
                                            );
                                            if (AccountType.values.map((t) => t.name.toLowerCase()).contains(v.toLowerCase())) {
                                              dset(() {
                                                selectedType = match;
                                                customType = null;
                                              });
                                            } else {
                                              dset(() => customType = v);
                                            }
                                          },
                                          items: ([...AccountType.values.map((t) => t.name), ...DatabaseService.getAllCustomAccountTypes()])
                                            .toSet()
                                            .map((type) => DropdownMenuItem(
                                              value: type,
                                              child: Text(type.isNotEmpty ? type[0].toUpperCase() + type.substring(1) : type),
                                            ))
                                            .toList(),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.add_circle_outline),
                                          tooltip: 'Add custom type',
                                          onPressed: () async {
                                            final textCtrl = TextEditingController();
                                            final res = await showDialog<String?>(
                                              context: dctx,
                                              builder: (tctx) => AlertDialog(
                                                title: const Text('Add account type'),
                                                content: TextField(controller: textCtrl, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Type name')),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(tctx), child: const Text('Cancel')),
                                                  TextButton(onPressed: () {
                                                    final v = textCtrl.text.trim();
                                                    if (v.isEmpty) return;
                                                    Navigator.pop(tctx, v);
                                                  }, child: const Text('Add')),
                                                ],
                                              ),
                                            );
                                            if (res != null) dset(() => customType = res);
                                          },
                                        ),
                                        if (customType != null) Padding(padding: const EdgeInsets.only(left:8.0), child: Text('($customType)', style: const TextStyle(fontStyle: FontStyle.italic))),
                                      ]),
                                      const SizedBox(height: 8),
                                      TextField(controller: nameCtrl, textCapitalization: TextCapitalization.words, autofillHints: const [AutofillHints.organizationName], decoration: const InputDecoration(labelText: 'Account')),
                                      const SizedBox(height: 8),
                                      TextField(controller: institutionCtrl, textCapitalization: TextCapitalization.words, autofillHints: const [AutofillHints.organizationName], decoration: const InputDecoration(labelText: 'Institution')),
                                      const SizedBox(height: 8),
                                      TextField(controller: accNumCtrl, autofillHints: const [AutofillHints.username], decoration: const InputDecoration(labelText: 'Account number')),
                                      const SizedBox(height: 8),
                                      const SizedBox(height: 8),
                                      TextField(controller: balCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Initial balance')),
                                      const SizedBox(height: 8),
                                      TextField(controller: availCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Available balance')),
                                    ],
                                  ),
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
                                  TextButton(onPressed: () {
                                    final name = nameCtrl.text.trim();
                                    if (name.isEmpty) return;
                                    final institution = institutionCtrl.text.trim();
                                    final accNum = accNumCtrl.text.trim().isEmpty ? null : accNumCtrl.text.trim();
                                    final bal = double.tryParse(balCtrl.text) ?? 0.0;
                                    final avail = double.tryParse(availCtrl.text);
                                    if (customType != null && customType!.isNotEmpty) {
                                      DatabaseService.addCustomAccountType(customType!);
                                    }
                                    final acc = Account(name: name, type: selectedType, balance: bal, accountNumber: accNum, availableBalance: avail, description: institution.isEmpty ? null : institution, customType: customType);
                                    Navigator.pop(dctx, acc);
                                  }, child: const Text('Add')),
                                ],
                              );
                            }),
                          );
                          if (res != null) {
                            await DatabaseService.addAccount(res);
                            final updated = DatabaseService.getAllAccounts();
                            setState2(() {});
                            setState(() {
                              _fromAccountId = res.id;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  body: ListView.builder(
                    itemCount: liveAccounts.length,
                    itemBuilder: (context, idx) {
                      final a = liveAccounts[idx];
                      return ListTile(
                        title: Text(a.name),
                        selected: _fromAccountId == a.id,
                        onTap: () => Navigator.pop(context, a.id),
                      );
                    },
                  ),
                );
              }),
            ),
          );
          if (selected != null) {
            setState(() => _fromAccountId = selected);
          }
        },
      ),
    );
  }

  Widget _buildToAccountSelector() {
    final accountName = _toAccountId != null
        ? accountList.firstWhere((a) => a.id == _toAccountId, orElse: () => Account(name: 'Unknown', type: AccountType.bank, balance: 0)).name
        : null;

    return Card(
      elevation: 1,
      child: ListTile(
        leading: const Icon(Icons.account_balance_wallet),
        title: const Text('To Account'),
        subtitle: Text(accountName ?? 'Select account'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () async {
          final selected = await showModalBottomSheet<String?>(
            context: context,
            isScrollControlled: true,
            builder: (ctx) => FractionallySizedBox(
              heightFactor: 0.85,
              child: StatefulBuilder(builder: (ctx2, setState2) {
                List<Account> liveAccounts = DatabaseService.getAllAccounts();
                return Scaffold(
                  appBar: AppBar(
                    title: const Text('Select Account'),
                    backgroundColor: Theme.of(ctx2).colorScheme.primary,
                    foregroundColor: Colors.white,
                    actions: [
                      IconButton(
                        icon: Icon(Icons.add),
                        onPressed: () async {
                          final plan = DatabaseService.getSetting<String>('subscriptionPlan', 'Free') ?? 'Free';
                          final accounts = DatabaseService.getAllAccounts();
                          if (plan == 'Free' && accounts.length >= 3) {
                            await showDialog(
                              context: ctx2,
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
                          // Show add account dialog
                          final nameCtrl = TextEditingController();
                          final institutionCtrl = TextEditingController();
                          final accNumCtrl = TextEditingController();
                          AccountType selectedType = AccountType.cash;
                          final balCtrl = TextEditingController(text: '0.0');
                          final availCtrl = TextEditingController(text: '0.0');
                          String? customType;
                          final res = await showDialog<Account?>(
                            context: ctx2,
                            builder: (dctx) => StatefulBuilder(builder: (dctx, dset) {
                              return AlertDialog(
                                title: const Center(child: Text('Add Account')),
                                content: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(children: [
                                        const Text('Type:'),
                                        const SizedBox(width: 12),
                                        DropdownButton<String>(
                                          value: customType ?? selectedType.name,
                                          onChanged: (v) {
                                            if (v == null) return;
                                            final match = AccountType.values.firstWhere(
                                              (t) => t.name.toLowerCase() == v.toLowerCase(),
                                              orElse: () => AccountType.cash,
                                            );
                                            if (AccountType.values.map((t) => t.name.toLowerCase()).contains(v.toLowerCase())) {
                                              dset(() {
                                                selectedType = match;
                                                customType = null;
                                              });
                                            } else {
                                              dset(() => customType = v);
                                            }
                                          },
                                          items: ([...AccountType.values.map((t) => t.name), ...DatabaseService.getAllCustomAccountTypes()])
                                            .toSet()
                                            .map((type) => DropdownMenuItem(
                                              value: type,
                                              child: Text(type.isNotEmpty ? type[0].toUpperCase() + type.substring(1) : type),
                                            ))
                                            .toList(),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.add_circle_outline),
                                          tooltip: 'Add custom type',
                                          onPressed: () async {
                                            final textCtrl = TextEditingController();
                                            final res = await showDialog<String?>(
                                              context: dctx,
                                              builder: (tctx) => AlertDialog(
                                                title: const Text('Add account type'),
                                                content: TextField(controller: textCtrl, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Type name')),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(tctx), child: const Text('Cancel')),
                                                  TextButton(onPressed: () {
                                                    final v = textCtrl.text.trim();
                                                    if (v.isEmpty) return;
                                                    Navigator.pop(tctx, v);
                                                  }, child: const Text('Add')),
                                                ],
                                              ),
                                            );
                                            if (res != null) dset(() => customType = res);
                                          },
                                        ),
                                        if (customType != null) Padding(padding: const EdgeInsets.only(left:8.0), child: Text('($customType)', style: const TextStyle(fontStyle: FontStyle.italic))),
                                      ]),
                                      const SizedBox(height: 8),
                                      TextField(controller: nameCtrl, textCapitalization: TextCapitalization.words, autofillHints: const [AutofillHints.organizationName], decoration: const InputDecoration(labelText: 'Account')),
                                      const SizedBox(height: 8),
                                      TextField(controller: institutionCtrl, textCapitalization: TextCapitalization.words, autofillHints: const [AutofillHints.organizationName], decoration: const InputDecoration(labelText: 'Institution')),
                                      const SizedBox(height: 8),
                                      TextField(controller: accNumCtrl, autofillHints: const [AutofillHints.username], decoration: const InputDecoration(labelText: 'Account number')),
                                      const SizedBox(height: 8),
                                      const SizedBox(height: 8),
                                      TextField(controller: balCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Initial balance')),
                                      const SizedBox(height: 8),
                                      TextField(controller: availCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Available balance')),
                                    ],
                                  ),
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
                                  TextButton(onPressed: () {
                                    final name = nameCtrl.text.trim();
                                    if (name.isEmpty) return;
                                    final institution = institutionCtrl.text.trim();
                                    final accNum = accNumCtrl.text.trim().isEmpty ? null : accNumCtrl.text.trim();
                                    final bal = double.tryParse(balCtrl.text) ?? 0.0;
                                    final avail = double.tryParse(availCtrl.text);
                                    if (customType != null && customType!.isNotEmpty) {
                                      DatabaseService.addCustomAccountType(customType!);
                                    }
                                    final acc = Account(name: name, type: selectedType, balance: bal, accountNumber: accNum, availableBalance: avail, description: institution.isEmpty ? null : institution, customType: customType);
                                    Navigator.pop(dctx, acc);
                                  }, child: const Text('Add')),
                                ],
                              );
                            }),
                          );
                          if (res != null) {
                            await DatabaseService.addAccount(res);
                            final updated = DatabaseService.getAllAccounts();
                            setState2(() {});
                            setState(() {
                              _toAccountId = res.id;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  body: ListView.builder(
                    itemCount: liveAccounts.length,
                    itemBuilder: (context, idx) {
                      final a = liveAccounts[idx];
                      return ListTile(
                        title: Text(a.name),
                        selected: _toAccountId == a.id,
                        onTap: () => Navigator.pop(context, a.id),
                      );
                    },
                  ),
                );
              }),
            ),
          );
          if (selected != null) {
            setState(() => _toAccountId = selected);
          }
        },
      ),
    );
    // Removed unused variables after refactor
  }

  Widget _buildDateSelector() {
    return Card(
      elevation: 1,
      child: ListTile(
        leading: const Icon(Icons.calendar_today),
        title: const Text('Date'),
        subtitle: Text(DateFormat.yMMMd().format(_transactionDate)),
        trailing: const Icon(Icons.arrow_drop_down),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: _transactionDate,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (picked != null) {
            setState(() => _transactionDate = picked);
          }
        },
      ),
    );
  }

  Widget _buildNotesField() {
    return TextFormField(
      controller: _notesController,
      decoration: const InputDecoration(
        labelText: 'Notes',
        hintText: 'Optional notes',
        border: OutlineInputBorder(),
      ),
      maxLines: 2,
    );
  }

  Widget _buildClearedToggle() {
    return Card(
      child: SwitchListTile.adaptive(
        title: const Text('Cleared'),
        subtitle: const Text('Mark transaction as cleared'),
        value: _cleared,
        onChanged: (v) => setState(() => _cleared = v),
        secondary: const Icon(Icons.check_circle_outline),
      ),
    );
  }

  Widget _buildShowInReportsToggle() {
    final isTransfer = _transactionType == TransactionScreenType.transfer;
    return Card(
      child: SwitchListTile.adaptive(
        title: const Text('Show in reports'),
        subtitle: Text(
          isTransfer
              ? 'Transfers are always excluded from reports.'
              : 'Include this transaction in report totals and charts',
        ),
        value: isTransfer ? false : _showInReports,
        onChanged: isTransfer ? null : (v) => setState(() => _showInReports = v),
        secondary: const Icon(Icons.insights_outlined),
      ),
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: _isSaving ? null : _saveTransaction,
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: _isSaving
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 8),
                Text('Saving...'),
              ],
            )
          : const Text('Save Transaction'),
    );
  }

  Future<void> _applyDashboardHiddenIfNeeded(Iterable<String> transactionIds) async {
    if (!widget.hideFromCalendarDashboard) return;
    for (final id in transactionIds) {
      await DatabaseService.addHiddenTransactionId(id);
    }
  }

  Future<void> _saveTransaction() async {
    if (_isSaving) return;
    FocusScope.of(context).unfocus();
    // Subscription gating: limit free users to 50 transactions per account
      final isSubscriber = DatabaseService.subscriptionVersion.value != 'Free';
    String? accountId;
    if (_transactionType == TransactionScreenType.transfer) {
      accountId = _fromAccountId;
    } else {
      accountId = _selectedAccountId;
    }
    if (accountId != null && !isSubscriber && widget.existingTransaction == null) {
      final txCount = DatabaseService.getAllTransactions().where((tx) => tx.accountId == accountId).length;
      if (txCount >= 50) {
        await showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Transaction Limit Reached'),
            content: const Text('Free users can add up to 50 transactions per account. Subscribe for unlimited transactions.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('OK')),
            ],
          ),
        );
        return;
      }
    }
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(content: Text('Please enter a valid amount'), backgroundColor: Colors.blueGrey[400]),
      );
      return;
    }

    // Enforce category selection for expense/income transactions
    if ((_transactionType == TransactionScreenType.expense || _transactionType == TransactionScreenType.income) && _selectedCategoryId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please select a category'), backgroundColor: Colors.blueGrey[400]),
        );
      }
      return;
    }

    // If splits are defined, ensure they sum to the transaction amount
    if (_splits.isNotEmpty) {
      if (!validateSplitsEqualAmount(_splits, amount)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Split amounts must sum to the transaction amount'), backgroundColor: Colors.red[700]),
          );
        }
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      final notes = _notesController.text.isEmpty ? null : _notesController.text;
      final isEditing = widget.existingTransaction != null;
      bool transferEditPrompted = false;

  if (_transactionType == TransactionScreenType.expense || _transactionType == TransactionScreenType.income) {
        // Always use the selected payee/payer ID for saving, regardless of extra info in the title/description
        String desc = 'Transaction';
        String? payeeId;
        String? payerId;
        if (_selectedPayeeId != null) {
          // Find the payee/payer name for display, but keep the ID for saving
          final p = _payees.firstWhere((p) => p['id'] == _selectedPayeeId, orElse: () => <String, dynamic>{});
          if (p.containsKey('name')) desc = p['name'] as String;
        } else if (_selectedCategoryId != null) {
          final cat = DatabaseService.getCategoryById(_selectedCategoryId!);
          if (cat != null) desc = cat.name;
        }

        String? finalNote = notes;
        if (_selectedAccountId != null && notes != null) {
          final a = DatabaseService.getAccountById(_selectedAccountId!);
          if (a != null) {
            finalNote = 'account: ${a.name} — $notes';
          }
        }

        if (_transactionType == TransactionScreenType.expense) {
          payeeId = _selectedPayeeId;
          payerId = null;
        } else if (_transactionType == TransactionScreenType.income) {
          payeeId = null;
          payerId = _selectedPayeeId;
        }

        if (isEditing) {
      final orig = widget.existingTransaction!;
        // If this transaction is linked to a bill (billId set), it was created
        // by the pay-bill flow and its description contains the human-readable
        // "Payment for {bill name} (MM/dd/yyyy)" text. Keep that description
        // stable when editing amount/category/account so payment names are not
        // rewritten to generic values.
        final preserveBillPaymentDescription =
          orig.billId != null && orig.billId!.isNotEmpty;
        final newDescription =
          (widget.preserveDescriptionAndDate || preserveBillPaymentDescription)
            ? orig.description
            : desc;
      final newDate = widget.preserveDescriptionAndDate ? orig.date : _transactionDate;
          final updated = orig.copyWith(
            amount: amount,
            categoryId: _selectedCategoryId ?? '',
            type: _transactionType == TransactionScreenType.expense ? TransactionType.expense : TransactionType.income,
            description: newDescription,
            date: newDate,
            note: finalNote,
            cleared: _cleared,
            accountId: _selectedAccountId,
            payeeId: payeeId, // Always set from selected
            payerId: payerId, // Always set from selected
            // Explicitly preserve bill linkage for payments so edits keep the
            // transaction associated with the original bill occurrence.
            billId: orig.billId,
            occurrenceDate: orig.occurrenceDate,
            splitsJson: (_useSplits && _splits.isNotEmpty) ? jsonEncode(_splits) : null,
            showInReports: _showInReports,
          );
          await DatabaseService.updateTransaction(updated);
          await _applyDashboardHiddenIfNeeded([updated.id]);
          // If this transaction is linked to a bill, ensure listeners watching
          // bills (like PayBillScreen) are notified so payment history refreshes.
          if (orig.billId != null && orig.billId!.isNotEmpty) {
            try {
              DatabaseService.billsVersion.value++;
            } catch (_) {}
          }

          final oldEffect = (orig.type == TransactionType.income) ? orig.amount : -orig.amount;
          final newEffect = (updated.type == TransactionType.income) ? updated.amount : -updated.amount;
          final oldAccountId = orig.accountId;
          final newAccountId = updated.accountId;
          if (oldAccountId != null && oldAccountId == newAccountId) {
            final acc = DatabaseService.getAccountById(oldAccountId);
            if (acc != null) {
              final updatedAcc = acc.copyWith(balance: acc.balance + (newEffect - oldEffect));
              await DatabaseService.updateAccount(updatedAcc);
            }
          } else {
            if (oldAccountId != null) {
              final oldAcc = DatabaseService.getAccountById(oldAccountId);
              if (oldAcc != null) {
                final updatedOldAcc = oldAcc.copyWith(balance: oldAcc.balance - oldEffect);
                await DatabaseService.updateAccount(updatedOldAcc);
              }
            }
            if (newAccountId != null) {
              final newAcc = DatabaseService.getAccountById(newAccountId);
              if (newAcc != null) {
                final updatedNewAcc = newAcc.copyWith(balance: newAcc.balance + newEffect);
                await DatabaseService.updateAccount(updatedNewAcc);
              }
            }
          }
          DatabaseService.transactionsVersion.value++;
          DatabaseService.accountsVersion.value++;
        } else {
          final tx = Transaction(
      amount: amount,
      categoryId: _selectedCategoryId ?? '',
      type: _transactionType == TransactionScreenType.expense ? TransactionType.expense : TransactionType.income,
      description: desc,
      date: _transactionDate,
      note: _transactionType == TransactionScreenType.transfer
        ? ((finalNote == null || finalNote.isEmpty)
          ? '__transfer_manual__'
          : '__transfer_manual__ $finalNote')
        : finalNote,
      accountId: _selectedAccountId,
      cleared: _cleared,
      payeeId: payeeId, // Always set from selected
      payerId: payerId, // Always set from selected
      billId: widget.prefillTransaction?.billId ?? widget.existingTransaction?.billId,
  splitsJson: (_useSplits && _splits.isNotEmpty) ? jsonEncode(_splits) : null,
        showInReports: _showInReports,
      );
          await DatabaseService.addTransaction(tx);
          await _applyDashboardHiddenIfNeeded([tx.id]);

          if (_selectedAccountId != null) {
            final account = DatabaseService.getAccountById(_selectedAccountId!);
            if (account != null) {
              final newBalance = _transactionType == TransactionScreenType.income
                  ? account.balance + amount
                  : account.balance - amount;
              final updatedAccount = account.copyWith(balance: newBalance);
              await DatabaseService.updateAccount(updatedAccount);
            }
          }
        }
      } else if (_transactionType == TransactionScreenType.transfer) {
        if (_fromAccountId == null || _toAccountId == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Please select both accounts for transfer'), backgroundColor: Colors.blueGrey[400]),
            );
          }
          return;
        }

        final fromAcc = DatabaseService.getAccountById(_fromAccountId!);
        final toAcc = DatabaseService.getAccountById(_toAccountId!);
        final fromName = fromAcc?.name ?? 'From account';
        final toName = toAcc?.name ?? 'To account';
        final desc = 'Transfer from $fromName to $toName';
        final transferCategory = await DatabaseService.getOrCreateTransferCategory();
        String userNote = notes ?? '';
        String debitInternalNote = '__transfer_bill__';
        String creditInternalNote = '__transfer_bill__';
        if (userNote.isNotEmpty) {
          debitInternalNote += ' $userNote';
          creditInternalNote += ' $userNote';
        }
        // Always define debit and credit transactions for later use
        final debit = Transaction(
          amount: amount,
          categoryId: transferCategory.id,
          type: TransactionType.expense,
          description: desc,
          date: _transactionDate,
          note: debitInternalNote,
          accountId: _fromAccountId,
          cleared: _cleared,
          showInReports: false,
        );
        final credit = Transaction(
          amount: amount,
          categoryId: transferCategory.id,
          type: TransactionType.income,
          description: desc,
          date: _transactionDate,
          note: creditInternalNote,
          accountId: _toAccountId,
          cleared: _cleared,
          showInReports: false,
        );
        // If editing, prompt user if date or note changed
        if (isEditing) {
          final orig = widget.existingTransaction!;
          final dateChanged = orig.date != _transactionDate;
          final amountChanged = orig.amount != amount;
          String origNote = orig.note ?? '';
          // Remove internal transfer marker and any pair tokens when comparing notes
          String cleanedOrigNote = origNote.replaceAll('__transfer_bill__', '').replaceAll(RegExp(r'pair:[A-Za-z0-9\-]+'), '').trim();
          String cleanedNewNote = userNote.replaceAll(RegExp(r'pair:[A-Za-z0-9\-]+'), '').trim();
          final noteChanged = cleanedOrigNote != cleanedNewNote;
          bool updateBoth = false;
          if (dateChanged || noteChanged || amountChanged) {
            transferEditPrompted = true;
            String changeText = '';
            if (dateChanged && noteChanged && amountChanged) {
              changeText = 'date, notes, and amount';
            } else if (dateChanged && noteChanged) {
              changeText = 'date and notes';
            } else if (dateChanged && amountChanged) {
              changeText = 'date and amount';
            } else if (noteChanged && amountChanged) {
              changeText = 'notes and amount';
            } else if (dateChanged) {
              changeText = 'date';
            } else if (noteChanged) {
              changeText = 'notes';
            } else if (amountChanged) {
              changeText = 'amount';
            }
            updateBoth = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Edit Both Sides of Transfer?'),
                content: Text('You changed the $changeText for this transfer.\nDo you want to update both sides of the transfer or just this side?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Just this side'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Both sides'),
                  ),
                ],
              ),
            ) ?? false;
          }
          // Find the paired transaction (other side of the transfer)
          final allTxs = DatabaseService.getAllTransactions();
          Transaction? pair;
          // First try note-based linking
          try {
            pair = allTxs.firstWhere(
              (t) =>
                t.id != orig.id &&
                t.note != null &&
                (t.note!.contains(orig.id) || (orig.note != null && orig.note!.contains(t.id))),
            );
          } catch (_) {
            pair = null;
          }
          // If not found, try matching by account, amount, date, and category
          if (pair == null) {
            final candidates = allTxs.where(
              (t) =>
                t.id != orig.id &&
                t.amount == orig.amount &&
                t.date == orig.date &&
                t.categoryId == orig.categoryId &&
                t.accountId != orig.accountId,
            );
            pair = candidates.isNotEmpty ? candidates.first : null;
          }
          // Determine old and new account IDs for both sides
          final oldFromId = orig.type == TransactionType.expense ? orig.accountId : (pair != null ? pair.accountId : null);
          final oldToId = orig.type == TransactionType.income ? orig.accountId : (pair != null ? pair.accountId : null);
          final newFromId = _fromAccountId;
          final newToId = _toAccountId;
          // Update both transactions' accountId if changed
          Transaction updatedOrig = orig;
          Transaction? updatedPair = pair;
          if (orig.type == TransactionType.expense && newFromId != null && orig.accountId != newFromId) {
            updatedOrig = orig.copyWith(accountId: newFromId);
          } else if (orig.type == TransactionType.income && newToId != null && orig.accountId != newToId) {
            updatedOrig = orig.copyWith(accountId: newToId);
          }
          if (pair != null) {
            if (pair.type == TransactionType.expense && newFromId != null && pair.accountId != newFromId) {
              updatedPair = pair.copyWith(accountId: newFromId);
            } else if (pair.type == TransactionType.income && newToId != null && pair.accountId != newToId) {
              updatedPair = pair.copyWith(accountId: newToId);
            }
          }
          // Update other fields (amount, description, date, note)
            final preserveBillPaymentDescription =
              orig.billId != null && orig.billId!.isNotEmpty;
            final newDescription =
              (widget.preserveDescriptionAndDate || preserveBillPaymentDescription)
                ? orig.description
                : desc;
          final newDate = widget.preserveDescriptionAndDate ? orig.date : _transactionDate;
          String cleanedNotes = userNote;
          if (cleanedNotes.contains('__transfer_bill__')) {
            cleanedNotes = cleanedNotes.replaceAll('__transfer_bill__', '').trim();
          }
          // Only use transfer id for linking, do NOT add it to the note field
          // User-facing note should only be the user's note, no transfer id or internal marker
          updatedOrig = updatedOrig.copyWith(
            amount: amount,
            description: newDescription,
            date: newDate,
            note: cleanedNotes.isNotEmpty ? cleanedNotes : null,
            cleared: _cleared,
            showInReports: false,
          );
          if (updateBoth && updatedPair != null) {
            updatedPair = updatedPair.copyWith(
              amount: amount,
              description: newDescription,
              date: newDate,
              note: cleanedNotes.isNotEmpty ? cleanedNotes : null,
              cleared: _cleared,
              showInReports: false,
            );
          }
          // Save updated transactions
          await DatabaseService.updateTransaction(updatedOrig);
          if (updateBoth && updatedPair != null) {
            await DatabaseService.updateTransaction(updatedPair);
          }
          await _applyDashboardHiddenIfNeeded(
            <String>[updatedOrig.id, if (updateBoth && updatedPair != null) updatedPair.id],
          );
          // Adjust balances for all affected accounts
          // First, revert old balances
          if (oldFromId != null) {
            final oldFromAcc = DatabaseService.getAccountById(oldFromId);
            if (oldFromAcc != null) {
              final updatedOldFrom = oldFromAcc.copyWith(balance: oldFromAcc.balance + orig.amount);
              await DatabaseService.updateAccount(updatedOldFrom);
            }
          }
          if (oldToId != null) {
            final oldToAcc = DatabaseService.getAccountById(oldToId);
            if (oldToAcc != null) {
              final updatedOldTo = oldToAcc.copyWith(balance: oldToAcc.balance - orig.amount);
              await DatabaseService.updateAccount(updatedOldTo);
            }
          }
          // Then, apply new balances
          if (newFromId != null) {
            final newFromAcc = DatabaseService.getAccountById(newFromId);
            if (newFromAcc != null) {
              final updatedNewFrom = newFromAcc.copyWith(balance: newFromAcc.balance - amount);
              await DatabaseService.updateAccount(updatedNewFrom);
            }
          }
          if (newToId != null) {
            final newToAcc = DatabaseService.getAccountById(newToId);
            if (newToAcc != null) {
              final updatedNewTo = newToAcc.copyWith(balance: newToAcc.balance + amount);
              await DatabaseService.updateAccount(updatedNewTo);
            }
          }
          DatabaseService.transactionsVersion.value++;
          DatabaseService.accountsVersion.value++;
        } else {
          // Persist both transfer transactions
          await DatabaseService.addTransaction(debit);
          await DatabaseService.addTransaction(credit);

          // Immediately update notes to include a pair-link so edits can reliably
          // locate the other side of the transfer. We avoid changing the ids
          // (they're generated in the constructors) and only update the note.
          try {
            final linkedUserNote = userNote.isNotEmpty ? ' $userNote' : '';
            final updatedDebit = debit.copyWith(note: '__transfer_bill__ pair:${credit.id}$linkedUserNote', cleared: _cleared);
            final updatedCredit = credit.copyWith(note: '__transfer_bill__ pair:${debit.id}$linkedUserNote', cleared: _cleared);
            await DatabaseService.updateTransaction(updatedDebit);
            await DatabaseService.updateTransaction(updatedCredit);
          } catch (_) {}

          // Hide both transfer transactions from calendar/dashboard
          await DatabaseService.addHiddenTransactionId(debit.id);
          await DatabaseService.addHiddenTransactionId(credit.id);
          await _applyDashboardHiddenIfNeeded([debit.id, credit.id]);

          // Update account balances for transfer
          if (_fromAccountId != null) {
            final fromAccount = DatabaseService.getAccountById(_fromAccountId!);
            if (fromAccount != null) {
              final updatedFromAccount = fromAccount.copyWith(balance: fromAccount.balance - amount);
              await DatabaseService.updateAccount(updatedFromAccount);
            }
          }
          if (_toAccountId != null) {
            final toAccount = DatabaseService.getAccountById(_toAccountId!);
            if (toAccount != null) {
              final updatedToAccount = toAccount.copyWith(balance: toAccount.balance + amount);
              await DatabaseService.updateAccount(updatedToAccount);
            }
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transaction saved'), backgroundColor: Colors.blueGrey[400]),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving transaction: $e'), backgroundColor: Colors.blueGrey[400]),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  void initState() {
    _categoriesListener = () {
      if (!mounted) return;
      setState(() {});
    };
    DatabaseService.categoriesVersion.addListener(_categoriesListener!);
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
    });

    // Autofill account if provided from parent screen
    if (widget.initialAccountId != null && widget.initialAccountId!.isNotEmpty) {
      _selectedAccountId = widget.initialAccountId;
    }
    final source = widget.existingTransaction ?? widget.prefillTransaction;
    if (source == null) return;

    // Basic fields
    _amountController.text = source.amount.toStringAsFixed(2);
    // Only autofill notes that were user-entered. Strip internal markers
    // and system prefixes (transfer markers, hide-from-calendar marker,
    // and the automatic 'account: <name> — ' prefix) before deciding.
    String initialNote = '';
    if (source.note != null && source.note!.trim().isNotEmpty) {
      String cleanedNote = source.note!.trim();

      // Remove known internal markers
      const markers = ['__transfer_bill__', '__transfer_manual__'];
      for (final m in markers) {
        if (cleanedNote.contains(m)) cleanedNote = cleanedNote.replaceAll(m, '');
      }
      if (cleanedNote.contains(_hideFromCalendarMarker)) {
        cleanedNote = cleanedNote.replaceAll(_hideFromCalendarMarker, '');
      }

      cleanedNote = cleanedNote.trim();

      // Remove any internal pair tokens that link transfer sides: 'pair:<id>'
      cleanedNote = cleanedNote.replaceAll(RegExp(r'pair:[A-Za-z0-9\-]+'), '');

      // Remove automatic account prefix like: 'account: <Account Name> — user note'
      final lower = cleanedNote.toLowerCase();
      if (lower.startsWith('account:')) {
        // Find separator '—' (em dash) or '-' or ' - '
        int sep = cleanedNote.indexOf('—');
        if (sep == -1) sep = cleanedNote.indexOf('-');
        if (sep != -1 && sep + 1 < cleanedNote.length) {
          cleanedNote = cleanedNote.substring(sep + 1).trim();
        } else {
          // No user-provided note present after the account prefix
          cleanedNote = '';
        }
      }

      initialNote = cleanedNote.trim();
    }

    // Only set notes controller if there is actual user-entered text left
    _notesController.text = initialNote.isNotEmpty ? initialNote : '';
    // Initialize splits from source if present
    if (source.splitsJson != null && source.splitsJson!.trim().isNotEmpty) {
      try {
        _splits = parseSplitsJson(source.splitsJson);
      } catch (_) {
        _splits = [];
      }
    }
    // Enable split mode if incoming transaction already contains splits
    _useSplits = _splits.isNotEmpty;
    _transactionDate = source.date;
    // If the transaction has a category, use it. Otherwise, if this
    // transaction is linked to a bill, default to the bill's category so
    // payments created via the Pay Bill flow show the originating category
    // when edited.
    if (source.categoryId.isNotEmpty) {
      _selectedCategoryId = source.categoryId;
    } else if (source.billId != null && source.billId!.isNotEmpty) {
      try {
        final billId = source.billId!;
        final bills = DatabaseService.getAllBills();
        Bill? linkedBill;
        try {
          linkedBill = bills.firstWhere((b) => b.id == billId);
        } catch (_) {
          linkedBill = null;
        }
        if (linkedBill != null && linkedBill.categoryId != null && linkedBill.categoryId!.isNotEmpty) {
          _selectedCategoryId = linkedBill.categoryId;
        } else {
          _selectedCategoryId = null;
        }
      } catch (_) {
        _selectedCategoryId = null;
      }
    } else {
      _selectedCategoryId = null;
    }
    // Only override _selectedAccountId if not already set by initialAccountId
    if (_selectedAccountId == null) {
      _selectedAccountId = source.accountId;
    }

    // Autofill payee/payer directly from transaction if available
    if (source.payeeId != null && source.payeeId!.isNotEmpty) {
      _selectedPayeeId = source.payeeId;
    } else if (source.payerId != null && source.payerId!.isNotEmpty) {
      _selectedPayeeId = source.payerId;
    } else {
      // Derive description and lowercased form
      final desc = source.description.trim();
      final descLower = desc.toLowerCase();
      final noteLower = (source.note ?? '').toLowerCase();

      // Attempt to detect a transfer via explicit transfer markers or
      // canonical transfer description format.
      var detectedTransfer = false;
      final hasTransferMarker =
          noteLower.contains('__transfer_manual__') ||
          noteLower.contains('__transfer_bill__') ||
          RegExp(r'pair:[a-z0-9\-]+').hasMatch(noteLower);
      final hasCanonicalTransferDescription =
          RegExp(r'^transfer\s+from\s+.+\s+to\s+.+$', caseSensitive: false)
              .hasMatch(desc);

      if (hasTransferMarker || hasCanonicalTransferDescription) {
        final reg = RegExp(r'Transfer\s+from\s+(.+)\s+to\s+(.+)', caseSensitive: false);
        final m = reg.firstMatch(desc);
        if (m != null) {
          final fromName = m.group(1)!.trim();
          final toName = m.group(2)!.trim();
          final accounts = DatabaseService.getAllAccounts();
          String? fromId;
          String? toId;
          for (final a in accounts) {
            if (a.name.toLowerCase() == fromName.toLowerCase()) fromId = a.id;
            if (a.name.toLowerCase() == toName.toLowerCase()) toId = a.id;
          }
          if (fromId != null || toId != null) {
            detectedTransfer = true;
            if (source.type == TransactionType.expense) {
              _fromAccountId = source.accountId ?? fromId;
              _toAccountId = toId;
            } else {
              _toAccountId = source.accountId ?? toId;
              _fromAccountId = fromId;
            }
          }
        } else {
          final all = DatabaseService.getAllTransactions();
          Transaction? pair;
          try {
            pair = all.firstWhere((t) => t.id != source.id && t.description == desc && t.amount == source.amount);
          } catch (_) {
            pair = null;
          }
          if (pair != null) {
            detectedTransfer = true;
            if (source.type == TransactionType.expense) {
              _fromAccountId = source.accountId;
              _toAccountId = pair.accountId;
            } else {
              _toAccountId = source.accountId;
              _fromAccountId = pair.accountId;
            }
          }
        }
      }

      if (detectedTransfer) {
        _transactionType = TransactionScreenType.transfer;
        _cleared = source.cleared ?? false;
        _showInReports = false;
        return;
      }

      // Not a transfer — try to match payee/payer by description.
      // Use a more specific matching strategy: gather all payees whose
      // name appears in the description and prefer an exact match or the
      // longest matching name (most specific). This avoids matching a
      // generic "Amazon" when a more specific "Amazon - Pharmacy" exists.
      Map<String, dynamic>? matchedPayee;
      try {
        final payees = DatabaseService.getAllPayees();
        final matches = <Map<String, dynamic>>[];
        for (final p in payees) {
          final name = (p['name'] ?? '').toString().toLowerCase().trim();
          if (name.isEmpty) continue;
          // If the description equals the payee name exactly, prefer it immediately
          if (descLower == name) {
            matches.clear();
            matches.add(p);
            break;
          }
          if (descLower.contains(name)) {
            matches.add(p);
          }
        }

        if (matches.isNotEmpty) {
          // Prefer the most specific match: the longest payee name
          matches.sort((a, b) {
            final an = (a['name'] ?? '').toString().length;
            final bn = (b['name'] ?? '').toString().length;
            return bn.compareTo(an);
          });
          matchedPayee = matches.first;
        } else {
          matchedPayee = null;
        }
      } catch (_) {
        matchedPayee = null;
      }

      if (matchedPayee != null && matchedPayee.isNotEmpty) {
        _selectedPayeeId = matchedPayee['id'] as String?;
        try {
          String? rawCatId = matchedPayee['categoryId'] as String?;
          String? catId;
          if (rawCatId != null) {
            final lower = rawCatId.toLowerCase();
            if (lower != 'null' && rawCatId.isNotEmpty) catId = rawCatId;
          }
          // Only auto-select the payee/payer's default category when the
          // transaction is NOT a payment linked to a bill. For bill
          // payments we prefer the category that the payment was made for
          // (e.g. the bill's category) so do not overwrite that.
          if (catId != null && DatabaseService.getAllCategories().any((c) => c.id == catId)) {
            final isBillPayment = source.billId != null && source.billId!.isNotEmpty;
            if (!isBillPayment) {
              _selectedCategoryId = catId;
            }
          }
        } catch (_) {
          // ignore
        }
      }
    }

    // Finally, set transaction type from stored transaction (income/expense)
    _transactionType = source.type == TransactionType.income ? TransactionScreenType.income : TransactionScreenType.expense;
    // Initialize cleared state from source (default false)
    _cleared = source.cleared ?? false;
    _showInReports = source.showInReports;
  }
}

// Calculator sheet widget
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
    if (_expression.isNotEmpty) setState(() => _expression = _expression.substring(0, _expression.length - 1));
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
                Expanded(child: Text(_expression, style: const TextStyle(fontSize: 24))),
                IconButton(onPressed: _backspace, icon: const Icon(Icons.backspace))
              ],
            ),
          ),
          if (eval != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                children: [
                  const Text('Result:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Text(eval.toStringAsFixed(2), style: const TextStyle(fontSize: 20)),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.count(
              crossAxisCount: 4,
              childAspectRatio: 1.6,
              padding: const EdgeInsets.all(12),
              children: [
                '7','8','9','/',
                '4','5','6','*',
                '1','2','3','-',
                '.','0','=','+',
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
                    child: Text(label, style: const TextStyle(fontSize: 18)),
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

// Payee selector bottom sheet
class _PayeeSelectorSheet extends StatelessWidget {
  final List<Map<String, dynamic>> payees;
  final String type;

  const _PayeeSelectorSheet({required this.payees, required this.type});

  @override
  Widget build(BuildContext context) {
    return _PayeeSelectorSheetWithSearch(payees: payees, type: type);
  }

}

class _PayeeSelectorSheetWithSearch extends StatefulWidget {
  final List<Map<String, dynamic>> payees;
  final String type;
  const _PayeeSelectorSheetWithSearch({required this.payees, required this.type});

  @override
  State<_PayeeSelectorSheetWithSearch> createState() => _PayeeSelectorSheetWithSearchState();
}

class _PayeeSelectorSheetWithSearchState extends State<_PayeeSelectorSheetWithSearch> {
  String _query = '';
  String? _selectedCategoryId;
  List<Category> _categories = [];
  VoidCallback? _categoriesListener;

  @override
  void initState() {
    super.initState();
    // Show expense categories for payee, income categories for payer
    if (widget.type == 'payee') {
      _categories = DatabaseService.getAllCategories().where((cat) => cat.type == CategoryType.expense).toList();
    } else if (widget.type == 'payer') {
      _categories = DatabaseService.getAllCategories().where((cat) => cat.type == CategoryType.income).toList();
    } else {
      _categories = DatabaseService.getAllCategories();
    }
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

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.payees
        : widget.payees.where((p) => (p['name'] as String).toLowerCase().contains(_query.toLowerCase())).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ... AppBar now handles the title and add button ...
          const SizedBox(height: 8),
          TextField(
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search',
            ),
            onChanged: (q) => setState(() => _query = q),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              shrinkWrap: true,
              children: [
                ...filtered.map((payee) => ListTile(
                  title: Text(payee['name'] as String),
                  onTap: () => Navigator.pop(context, payee['id'] as String),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Category selector bottom sheet
class _CategorySelectorSheet extends StatefulWidget {
  final List<Category> categories;
  final bool hideAddButton;

  const _CategorySelectorSheet({required this.categories, this.hideAddButton = false});

  @override
  State<_CategorySelectorSheet> createState() => _CategorySelectorSheetState();
}

class _CategorySelectorSheetState extends State<_CategorySelectorSheet> {
  String _searchText = '';
  late List<Category> _allCategories;
  VoidCallback? _categoriesListener;

  @override
  void initState() {
    super.initState();
    _allCategories = widget.categories;
    _categoriesListener = () {
      setState(() {
        _allCategories = DatabaseService.getAllCategories();
      });
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

  @override
  Widget build(BuildContext context) {
  List<Category> filteredCategories = _searchText.isEmpty
    ? _allCategories
    : _allCategories.where((cat) => cat.name.toLowerCase().contains(_searchText.toLowerCase())).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.hideAddButton) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Select Category', style: Theme.of(context).textTheme.titleLarge),
                TextButton(
                  onPressed: () async {
                    final nameController = TextEditingController();
                    final result = await showDialog<Category?>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Add Category'),
                        content: TextField(
                          controller: nameController,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(labelText: 'Name'),
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
                                  colorValue: '0xFF607D8B',
                                  type: CategoryType.expense,
                                );
                                Navigator.pop(ctx, newCat);
                              }
                            },
                            child: const Text('Add'),
                          ),
                        ],
                      ),
                    );
                    if (result != null) {
                      await DatabaseService.addCategory(result);
                      Navigator.pop(context, null); // Close sheet so parent can refresh
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          // Search bar
          TextField(
            decoration: const InputDecoration(
              labelText: 'Search categories',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) {
              setState(() {
                _searchText = value;
              });
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: filteredCategories.isEmpty
                ? Center(child: Text('No categories found'))
                : ListView(
                    shrinkWrap: true,
                    children: filteredCategories.map((category) {
                      // Use const IconData if possible, otherwise fallback to default
                      final iconData = Category.iconMap[category.iconCodePoint] ?? const IconData(0xe88a, fontFamily: 'MaterialIcons');
                      final color = Color(int.parse(category.colorValue));
                      Widget? leadingWidget;
                      final emoji = category.displayEmoji;
                      if (emoji != null) {
                        leadingWidget = Text(emoji, style: TextStyle(fontSize: 24, color: color));
                      } else {
                        leadingWidget = Icon(iconData, color: color);
                      }
                      return ListTile(
                        leading: CircleAvatar(backgroundColor: color.withOpacity(0.2), child: leadingWidget),
                        title: Text(category.name),
                        onTap: () => Navigator.pop(context, category.id),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}
