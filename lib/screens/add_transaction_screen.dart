// ignore_for_file: prefer_collection_literals, curly_braces_in_flow_control_structures, deprecated_member_use, unused_element, unused_local_variable, unnecessary_null_comparison, unused_field, use_build_context_synchronously, prefer_conditional_assignment, unrelated_type_equality_checks, prefer_null_aware_operators, prefer_interpolation_to_compose_strings, dead_code, unnecessary_null_in_if_null_operators

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/transaction.dart';
import '../models/category.dart';
import '../models/bill.dart';
import '../models/account.dart';
import '../services/database_service.dart';
import '../services/bill_reminder_service.dart';
import '../services/lookups_state.dart';
import '../services/lookups_sync_helper.dart';
import '../widgets/app_color_picker.dart';
import '../widgets/account_type_icon.dart';
import '../widgets/splits_editor.dart';
import '../utils/split_utils.dart';
import 'dart:convert';

// Marker used to indicate a transaction should not appear on the calendar/dashboard
const String _hideFromCalendarMarker = '__hide_from_calendar__';

Category? _findCategoryById(Iterable<Category> categories, String? id) {
  if (id == null || id.isEmpty) return null;
  for (final category in categories) {
    if (category.id == id) return category;
  }
  return null;
}

enum TransactionScreenType { expense, income, transfer }

class AddTransactionScreen extends StatefulWidget {
  final Transaction? existingTransaction;
  final Transaction? prefillTransaction;
  final bool isDuplicate;
  final bool isRefund;
  final bool preserveDescriptionAndDate;
  final String? initialAccountId;
  final bool hideFromCalendarDashboard;
  const AddTransactionScreen({
    super.key,
    this.existingTransaction,
    this.prefillTransaction,
    this.isDuplicate = false,
    this.isRefund = false,
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
  bool _didUserEditNotes = false;
  bool _didUserSelectPayee = false;
  TransactionScreenType? _initialTransactionType;

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

  Account? _accountForId(String? accountId) {
    if (accountId == null) return null;
    for (final account in accountList) {
      if (account.id == accountId) return account;
    }
    return null;
  }

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
  String?
  _originalCategoryId; // Track the category from the transaction being edited/duplicated

  String _sanitizeInternalNoteTokens(String text) {
    var cleaned = text;
    cleaned = cleaned.replaceAll(
      RegExp(r'__transfer_(manual|bill)__', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'__hide_from_calendar__', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'pair:[A-Za-z0-9\-]+', caseSensitive: false),
      '',
    );
    return cleaned.trim();
  }

  String? _applyHideFromCalendarMarker(String? note, bool shouldHide) {
    final trimmed = note?.trim();
    if (!shouldHide) return trimmed;
    if (trimmed == null || trimmed.isEmpty) return _hideFromCalendarMarker;
    if (trimmed.contains(_hideFromCalendarMarker)) return trimmed;
    return '$trimmed $_hideFromCalendarMarker';
  }

  bool _isAccountScopedEntry() {
    final initial = widget.initialAccountId?.trim();
    return initial != null && initial.isNotEmpty;
  }

  bool _shouldHideFromDashboard({Transaction? existing}) {
    return widget.hideFromCalendarDashboard ||
        _isAccountScopedEntry() ||
        (existing?.hideFromCalendarDashboard ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final bottomClearance = MediaQuery.paddingOf(context).bottom + 96;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(
          widget.isRefund
              ? 'Create Refund'
              : widget.existingTransaction != null
              ? 'Edit Transaction'
              : 'Add Transaction',
        ),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(16, 16, 16, bottomClearance),
            children: [
              _buildTypeToggle(),
              const SizedBox(height: 16),
              _buildAmountField(),
              const SizedBox(height: 16),
              if (_transactionType == TransactionScreenType.transfer) ...[
                _buildFromAccountSelector(),
                const SizedBox(height: 10),
                _buildToAccountSelector(),
              ] else ...[
                _buildPayeeSelector(),
                const SizedBox(height: 10),
                _buildCategorySelector(),
                const SizedBox(height: 10),
                if (_useSplits)
                  SplitsEditor(
                    initialSplits: _splits,
                    transactionAmount:
                        double.tryParse(_amountController.text) ?? null,
                    onChanged: (s) => _splits = s,
                    categoryTypeFilter:
                        _transactionType == TransactionScreenType.income
                        ? CategoryType.income
                        : CategoryType.expense,
                  ),
                const SizedBox(height: 10),
                _buildAccountSelector(),
              ],
              const SizedBox(height: 10),
              if (_transactionType != TransactionScreenType.transfer) ...[
                _buildClearedToggle(),
                const SizedBox(height: 10),
              ],
              _buildShowInReportsToggle(),
              const SizedBox(height: 10),
              _buildDateSelector(),
              const SizedBox(height: 12),
              _buildNotesField(),
              const SizedBox(height: 24),
              _buildSaveButton(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (_categoriesListener != null)
      DatabaseService.categoriesVersion.removeListener(_categoriesListener!);
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Widget _buildTypeToggle() {
    final colorScheme = Theme.of(context).colorScheme;

    Widget option(TransactionScreenType type, String label) {
      final selected = _transactionType == type;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            final index = TransactionScreenType.values.indexOf(type);
            setState(() {
              if (_transactionType != TransactionScreenType.values[index]) {
                _didUserSelectPayee = true;
              }
              _transactionType = TransactionScreenType.values[index];
              _selectedPayeeId = null;
              _selectedCategoryId = null;
              if (_transactionType == TransactionScreenType.transfer) {
                _showInReports = false;
                _selectedAccountId = null;
                _fromAccountId = null;
                _toAccountId = null;
              }
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          option(TransactionScreenType.expense, 'Expense'),
          option(TransactionScreenType.income, 'Income'),
          option(TransactionScreenType.transfer, 'Transfer'),
        ],
      ),
    );
  }

  Widget _buildAmountField() {
    final colorScheme = Theme.of(context).colorScheme;
    return TextFormField(
      controller: _amountController,
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
      decoration: InputDecoration(
        labelText: 'Amount',
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 16, right: 8),
          child: Align(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              '\$',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: _transactionType == TransactionScreenType.income
                    ? AppTheme.incomeGreen
                    : (_transactionType == TransactionScreenType.expense
                          ? AppTheme.expenseRed
                          : colorScheme.primary),
              ),
            ),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        hintText: '0.00',
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        suffixIcon: IconButton(
          icon: const Icon(Icons.calculate_outlined),
          tooltip: 'Calculator',
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return 'Please enter an amount';
        final v = double.tryParse(value);
        if (v == null || v <= 0) return 'Please enter a valid amount';
        return null;
      },
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildPayeeSelector() {
    List<Map<String, dynamic>> payees = DatabaseService.getAllPayees();
    final payeeName = _selectedPayeeId != null
        ? payees.firstWhere(
            (p) => p['id'].toString() == _selectedPayeeId,
            orElse: () => {'name': 'Unknown'},
          )['name']
        : null;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.22),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 3),
        leading: const Icon(Icons.person_outline_rounded),
        title: Text(
          _transactionType == TransactionScreenType.expense ? 'Payee' : 'Payer',
        ),
        subtitle: Text(
          payeeName ??
              (_transactionType == TransactionScreenType.expense
                  ? 'Select payee'
                  : 'Select payer'),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () async {
          FocusScope.of(context).unfocus();
          payees = DatabaseService.getAllPayees();
          final type = _transactionType;
          final visible = type == TransactionScreenType.expense
              ? payees.where((p) => (p['type'] as String?) == 'payee').toList()
              : payees.where((p) => (p['type'] as String?) == 'payer').toList();

          final selected = await Navigator.of(context).push<String>(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => _TransactionPayeeSelectorPage(
                payees: visible,
                initialSelectedId: _selectedPayeeId,
                transactionType: type,
              ),
            ),
          );

          if (!mounted) return;
          payees = DatabaseService.getAllPayees();

          if (selected != null) {
            final payee = payees.firstWhere(
              (p) => p['id'].toString() == selected,
              orElse: () => <String, dynamic>{},
            );
            String? rawCatId;
            if (payee.isNotEmpty && payee.containsKey('categoryId')) {
              rawCatId = payee['categoryId'] as String?;
            }
            String? catId;
            if (rawCatId != null) {
              final lower = rawCatId.toLowerCase();
              if (lower != 'null' && rawCatId.isNotEmpty) catId = rawCatId;
            }
            final hasValidCategory = catId != null &&
                DatabaseService.getAllCategories().any((c) => c.id == catId);

            setState(() {
              _didUserSelectPayee = true;
              _selectedPayeeId = selected.isEmpty ? null : selected;
              if (_originalCategoryId == null && hasValidCategory) {
                _selectedCategoryId = catId;
              }
            });
          }
        },
      ),
    );
  }

  Widget _buildCategorySelector() {
    final selectedCategory = _findCategoryById(
      _categories,
      _selectedCategoryId,
    );
    final categoryName = _transactionType == TransactionScreenType.transfer
        ? 'Transfer'
        : selectedCategory?.name;

    final Widget leadingWidget = selectedCategory != null
        ? SizedBox(
            width: 24,
            height: 24,
            child: Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: selectedCategory.color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          )
        : const Icon(Icons.category_outlined);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.22),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 3),
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
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () async {
          FocusScope.of(context).unfocus();
          final allCategories = DatabaseService.getAllCategories();
          final filtered = _transactionType == TransactionScreenType.expense
              ? allCategories.where((c) => c.type == CategoryType.expense).toList()
              : allCategories.where((c) => c.type == CategoryType.income).toList();

          final selected = await Navigator.of(context).push<String>(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => _TransactionCategorySelectorPage(
                categories: filtered,
                initialSelectedId: _selectedCategoryId,
                transactionType: _transactionType,
              ),
            ),
          );

          if (selected != null && mounted) {
            setState(() => _selectedCategoryId = selected);
          }
        },
      ),
    );
  }

  Widget _buildAccountSelector() {
    final selectedAccount = _accountForId(_selectedAccountId);
    final accountName = selectedAccount?.name;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 3),
        leading: selectedAccount == null
            ? const Icon(Icons.account_balance_wallet_outlined)
            : AccountTypeIcon(
                type: selectedAccount.type,
                displayName: selectedAccount.typeDisplayName,
              ),
        title: const Text('Account'),
        subtitle: Text(accountName ?? 'Select'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () async {
          final selected = await showModalBottomSheet<String?>(
            context: context,
            isScrollControlled: true,
            builder: (ctx) => FractionallySizedBox(
              heightFactor: 0.85,
              child: StatefulBuilder(
                builder: (ctx2, setState2) {
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
                            final plan =
                                DatabaseService.getSetting<String>(
                                  'subscriptionPlan',
                                  'Free',
                                ) ??
                                'Free';
                            final accounts = DatabaseService.getAllAccounts();
                            if (plan == 'Free' && accounts.length >= 3) {
                              await showDialog(
                                context: ctx2,
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
                            // Show add account dialog
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
                            final res = await Navigator.of(ctx2).push<Account>(
                              MaterialPageRoute(
                                fullscreenDialog: true,
                                builder: (_) => const _TransactionAddAccountPage(),
                              ),
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
                          leading: AccountTypeIcon(
                            type: a.type,
                            displayName: a.typeDisplayName,
                          ),
                          title: Text(a.name),
                          selected: _selectedAccountId == a.id,
                          onTap: () => Navigator.pop(context, a.id),
                        );
                      },
                    ),
                  );
                },
              ),
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
    final selectedAccount = _accountForId(_fromAccountId);
    final accountName = selectedAccount?.name;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 3),
        leading: selectedAccount == null
            ? const Icon(Icons.account_balance_wallet_outlined)
            : AccountTypeIcon(
                type: selectedAccount.type,
                displayName: selectedAccount.typeDisplayName,
              ),
        title: const Text('From Account'),
        subtitle: Text(accountName ?? 'Select account'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () async {
          final selected = await showModalBottomSheet<String?>(
            context: context,
            isScrollControlled: true,
            builder: (ctx) => FractionallySizedBox(
              heightFactor: 0.85,
              child: StatefulBuilder(
                builder: (ctx2, setState2) {
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
                            final plan =
                                DatabaseService.getSetting<String>(
                                  'subscriptionPlan',
                                  'Free',
                                ) ??
                                'Free';
                            final accounts = DatabaseService.getAllAccounts();
                            if (plan == 'Free' && accounts.length >= 3) {
                              await showDialog(
                                context: ctx2,
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
                            // Show add account dialog
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
                            final res = await Navigator.of(ctx2).push<Account>(
                              MaterialPageRoute(
                                fullscreenDialog: true,
                                builder: (_) => const _TransactionAddAccountPage(),
                              ),
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
                          leading: AccountTypeIcon(
                            type: a.type,
                            displayName: a.typeDisplayName,
                          ),
                          title: Text(a.name),
                          selected: _fromAccountId == a.id,
                          onTap: () => Navigator.pop(context, a.id),
                        );
                      },
                    ),
                  );
                },
              ),
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
    final selectedAccount = _accountForId(_toAccountId);
    final accountName = selectedAccount?.name;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 3),
        leading: selectedAccount == null
            ? const Icon(Icons.account_balance_wallet_outlined)
            : AccountTypeIcon(
                type: selectedAccount.type,
                displayName: selectedAccount.typeDisplayName,
              ),
        title: const Text('To Account'),
        subtitle: Text(accountName ?? 'Select account'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () async {
          final selected = await showModalBottomSheet<String?>(
            context: context,
            isScrollControlled: true,
            builder: (ctx) => FractionallySizedBox(
              heightFactor: 0.85,
              child: StatefulBuilder(
                builder: (ctx2, setState2) {
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
                            final plan =
                                DatabaseService.getSetting<String>(
                                  'subscriptionPlan',
                                  'Free',
                                ) ??
                                'Free';
                            final accounts = DatabaseService.getAllAccounts();
                            if (plan == 'Free' && accounts.length >= 3) {
                              await showDialog(
                                context: ctx2,
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
                            // Show add account dialog
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
                            final res = await Navigator.of(ctx2).push<Account>(
                              MaterialPageRoute(
                                fullscreenDialog: true,
                                builder: (_) => const _TransactionAddAccountPage(),
                              ),
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
                          leading: AccountTypeIcon(
                            type: a.type,
                            displayName: a.typeDisplayName,
                          ),
                          title: Text(a.name),
                          selected: _toAccountId == a.id,
                          onTap: () => Navigator.pop(context, a.id),
                        );
                      },
                    ),
                  );
                },
              ),
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
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 3),
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
    final colorScheme = Theme.of(context).colorScheme;
    return TextFormField(
      controller: _notesController,
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      onChanged: (_) {
        if (!_didUserEditNotes) {
          setState(() => _didUserEditNotes = true);
        }
      },
      decoration: InputDecoration(
        labelText: 'Notes',
        hintText: 'Optional notes',
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      minLines: 2,
      maxLines: 3,
    );
  }

  Widget _buildClearedToggle() {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      child: SwitchListTile.adaptive(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
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
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      child: SwitchListTile.adaptive(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
        title: const Text('Show in reports'),
        subtitle: Text(
          isTransfer
              ? 'Transfers are always excluded from reports.'
              : 'Include this transaction in report totals and charts',
        ),
        value: isTransfer ? false : _showInReports,
        onChanged: isTransfer
            ? null
            : (v) => setState(() => _showInReports = v),
        secondary: const Icon(Icons.insights_outlined),
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveTransaction,
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isSaving
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
            : Text(
                widget.isRefund ? 'Create Refund' : 'Save Transaction',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
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
    if (accountId != null &&
        !isSubscriber &&
        widget.existingTransaction == null) {
      final txCount = DatabaseService.getAllTransactions()
          .where((tx) => tx.accountId == accountId)
          .length;
      if (txCount >= 50) {
        await showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Transaction Limit Reached'),
            content: const Text(
              'Free users can add up to 50 transactions per account. Subscribe for unlimited transactions.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
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
        SnackBar(
          content: Text('Please enter a valid amount'),
          backgroundColor: Colors.blueGrey[400],
        ),
      );
      return;
    }

    // A primary category is only needed when splits do not fully categorize
    // the transaction.
    if ((_transactionType == TransactionScreenType.expense ||
            _transactionType == TransactionScreenType.income) &&
        (_selectedCategoryId == null || _selectedCategoryId!.trim().isEmpty) &&
        !_useSplits) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please select a category'),
            backgroundColor: Colors.blueGrey[400],
          ),
        );
      }
      return;
    }

    // If splits are defined, ensure they sum to the transaction amount
    if (_useSplits) {
      if (_splits.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Add at least one category split'),
              backgroundColor: Colors.red[700],
            ),
          );
        }
        return;
      }
      if (!validateSplitCategories(_splits)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Select a category and enter an amount for every split',
              ),
              backgroundColor: Colors.red[700],
            ),
          );
        }
        return;
      }
      if (!validateSplitsEqualAmount(_splits, amount)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Split amounts must sum to the transaction amount'),
              backgroundColor: Colors.red[700],
            ),
          );
        }
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      final sanitizedInputNote = _sanitizeInternalNoteTokens(
        _notesController.text,
      );
      final notes = sanitizedInputNote.isEmpty ? null : sanitizedInputNote;
      final isEditing = widget.existingTransaction != null;
      bool transferEditPrompted = false;

      if (_transactionType == TransactionScreenType.expense ||
          _transactionType == TransactionScreenType.income) {
        // Always use the selected payee/payer ID for saving, regardless of extra info in the title/description
        String desc = 'Transaction';
        String? payeeId;
        String? payerId;
        if (_selectedPayeeId != null) {
          // Find the payee/payer name for display, but keep the ID for saving
          final p = _payees.firstWhere(
            (p) => p['id'] == _selectedPayeeId,
            orElse: () => <String, dynamic>{},
          );
          if (p.containsKey('name')) desc = p['name'] as String;
        } else if (_selectedCategoryId != null) {
          final cat = DatabaseService.getCategoryById(_selectedCategoryId!);
          if (cat != null) desc = cat.name;
        }

        // The account is stored separately in accountId. Keep note limited to
        // what the user entered; embedding the account name here causes edited
        // notes to render as account metadata on transaction cards.
        String? finalNote = notes;

        if (_transactionType == TransactionScreenType.expense) {
          payeeId = _selectedPayeeId;
          payerId = null;
        } else if (_transactionType == TransactionScreenType.income) {
          payeeId = null;
          payerId = _selectedPayeeId;
        }

        final lookupsState = context.read<LookupsState>();
        final selectedCategory = _selectedCategoryId == null
            ? null
            : lookupsState.categoriesById[_selectedCategoryId!];
        final selectedPayee = payeeId == null
            ? null
            : lookupsState.payeesById[payeeId];
        final selectedPayer = payerId == null
            ? null
            : lookupsState.payersById[payerId];

        final selectedCategoryName =
            selectedCategory?.name ??
            (_selectedCategoryId == null
                ? null
                : DatabaseService.getCategoryById(_selectedCategoryId!)?.name);
        final selectedPayeeName =
            selectedPayee?.name ??
            ((payeeId != null && desc.isNotEmpty) ? desc : null);
        final selectedPayerName =
            selectedPayer?.name ??
            ((payerId != null && desc.isNotEmpty) ? desc : null);

        if (isEditing) {
          final orig = widget.existingTransaction!;
          final sameTransactionKind =
              _initialTransactionType == null ||
              _initialTransactionType == _transactionType;
          final preserveOriginalPayee =
              sameTransactionKind && !_didUserSelectPayee;
          final effectivePayeeId = preserveOriginalPayee
              ? orig.payeeId
              : payeeId;
          final effectivePayeeName = preserveOriginalPayee
              ? orig.payeeName
              : selectedPayeeName;
          final effectivePayerId = preserveOriginalPayee
              ? orig.payerId
              : payerId;
          final effectivePayerName = preserveOriginalPayee
              ? orig.payerName
              : selectedPayerName;
          final shouldHideFromCalendar = _shouldHideFromDashboard(
            existing: orig,
          );
          if (!_didUserEditNotes) {
            finalNote = orig.note;
          }
          finalNote = _applyHideFromCalendarMarker(
            finalNote,
            shouldHideFromCalendar,
          );
          // If this transaction is linked to a bill (billId set), it was created
          // by the pay-bill flow and its description contains the human-readable
          // "Payment for {bill name} (MM/dd/yyyy)" text. Keep that description
          // stable when editing amount/category/account so payment names are not
          // rewritten to generic values.
          final preserveBillPaymentDescription =
              orig.billId != null && orig.billId!.isNotEmpty;
          final newDescription =
              (widget.preserveDescriptionAndDate ||
                  preserveBillPaymentDescription)
              ? orig.description
              : desc;
          final newDate = widget.preserveDescriptionAndDate
              ? orig.date
              : _transactionDate;
          final updated = orig.copyWith(
            amount: amount,
            categoryId: _selectedCategoryId ?? '',
            type: _transactionType == TransactionScreenType.expense
                ? TransactionType.expense
                : TransactionType.income,
            description: newDescription,
            date: newDate,
            updatedAt: DateTime.now(),
            note: finalNote,
            cleared: _cleared,
            accountId: _selectedAccountId,
            payeeId: effectivePayeeId,
            payeeName: effectivePayeeName,
            payerId: effectivePayerId,
            payerName: effectivePayerName,
            categoryName: selectedCategoryName,
            // Explicitly preserve bill linkage for payments so edits keep the
            // transaction associated with the original bill occurrence.
            billId: orig.billId,
            occurrenceDate: orig.occurrenceDate,
            splitsJson: (_useSplits && _splits.isNotEmpty)
                ? jsonEncode(_splits)
                : null,
            showInReports: _showInReports,
            hideFromCalendarDashboard: shouldHideFromCalendar,
          );
          await DatabaseService.updateTransaction(updated);
          // If this transaction is linked to a bill, ensure listeners watching
          // bills (like PayBillScreen) are notified so payment history refreshes.
          if (orig.billId != null && orig.billId!.isNotEmpty) {
            try {
              DatabaseService.billsVersion.value++;
            } catch (_) {}
            BillReminderService().refreshAllReminders().catchError((e) {
              debugPrint('Bill reminder refresh failed after payment edit: $e');
            });
          }

          final oldEffect = (orig.type == TransactionType.income)
              ? orig.amount
              : -orig.amount;
          final newEffect = (updated.type == TransactionType.income)
              ? updated.amount
              : -updated.amount;
          final oldAccountId = orig.accountId;
          final newAccountId = updated.accountId;
          if (oldAccountId != null && oldAccountId == newAccountId) {
            final acc = DatabaseService.getAccountById(oldAccountId);
            if (acc != null) {
              final updatedAcc = acc.copyWith(
                balance: acc.balance + (newEffect - oldEffect),
              );
              await DatabaseService.updateAccount(updatedAcc);
            }
          } else {
            if (oldAccountId != null) {
              final oldAcc = DatabaseService.getAccountById(oldAccountId);
              if (oldAcc != null) {
                final updatedOldAcc = oldAcc.copyWith(
                  balance: oldAcc.balance - oldEffect,
                );
                await DatabaseService.updateAccount(updatedOldAcc);
              }
            }
            if (newAccountId != null) {
              final newAcc = DatabaseService.getAccountById(newAccountId);
              if (newAcc != null) {
                final updatedNewAcc = newAcc.copyWith(
                  balance: newAcc.balance + newEffect,
                );
                await DatabaseService.updateAccount(updatedNewAcc);
              }
            }
          }
          DatabaseService.transactionsVersion.value++;
          DatabaseService.accountsVersion.value++;
        } else {
          final shouldHideFromCalendar = _shouldHideFromDashboard();
          finalNote = _applyHideFromCalendarMarker(
            finalNote,
            shouldHideFromCalendar,
          );
          final tx = Transaction(
            amount: amount,
            categoryId: _selectedCategoryId ?? '',
            type: _transactionType == TransactionScreenType.expense
                ? TransactionType.expense
                : TransactionType.income,
            description: desc,
            date: _transactionDate,
            updatedAt: DateTime.now(),
            note: _transactionType == TransactionScreenType.transfer
                ? ((finalNote == null || finalNote.isEmpty)
                      ? '__transfer_manual__'
                      : '__transfer_manual__ $finalNote')
                : finalNote,
            accountId: _selectedAccountId,
            cleared: _cleared,
            payeeId: payeeId, // Always set from selected
            payeeName: selectedPayeeName,
            payerId: payerId, // Always set from selected
            payerName: selectedPayerName,
            categoryName: selectedCategoryName,
            billId:
                widget.prefillTransaction?.billId ??
                widget.existingTransaction?.billId,
            occurrenceDate:
                widget.prefillTransaction?.occurrenceDate ??
                widget.existingTransaction?.occurrenceDate,
            paymentFor:
                widget.prefillTransaction?.paymentFor ??
                widget.existingTransaction?.paymentFor,
            splitsJson: (_useSplits && _splits.isNotEmpty)
                ? jsonEncode(_splits)
                : null,
            showInReports: _showInReports,
            hideFromCalendarDashboard: shouldHideFromCalendar,
          );
          await DatabaseService.addTransaction(tx);
          if (tx.billId != null && tx.billId!.isNotEmpty) {
            BillReminderService().refreshAllReminders().catchError((e) {
              debugPrint(
                'Bill reminder refresh failed after payment create: $e',
              );
            });
          }

          if (_selectedAccountId != null) {
            final account = DatabaseService.getAccountById(_selectedAccountId!);
            if (account != null) {
              final newBalance =
                  _transactionType == TransactionScreenType.income
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
              SnackBar(
                content: Text('Please select both accounts for transfer'),
                backgroundColor: Colors.blueGrey[400],
              ),
            );
          }
          return;
        }

        final fromAcc = DatabaseService.getAccountById(_fromAccountId!);
        final toAcc = DatabaseService.getAccountById(_toAccountId!);
        final fromName = fromAcc?.name ?? 'From account';
        final toName = toAcc?.name ?? 'To account';
        final desc = 'Transfer from $fromName to $toName';
        final transferCategory =
            await DatabaseService.getOrCreateTransferCategory();
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
          updatedAt: DateTime.now(),
          note: debitInternalNote,
          accountId: _fromAccountId,
          cleared: _cleared,
          showInReports: false,
          categoryName: transferCategory.name,
          hideFromCalendarDashboard: true,
        );
        final credit = Transaction(
          amount: amount,
          categoryId: transferCategory.id,
          type: TransactionType.income,
          description: desc,
          date: _transactionDate,
          updatedAt: DateTime.now(),
          note: creditInternalNote,
          accountId: _toAccountId,
          cleared: _cleared,
          showInReports: false,
          categoryName: transferCategory.name,
          hideFromCalendarDashboard: true,
        );
        // If editing, prompt user if date or note changed
        if (isEditing) {
          final orig = widget.existingTransaction!;
          String? extractPairId(String? note) {
            if (note == null || note.isEmpty) return null;
            final m = RegExp(
              r'pair:([A-Za-z0-9\-]+)',
              caseSensitive: false,
            ).firstMatch(note);
            final id = m?.group(1);
            if (id == null || id.isEmpty) return null;
            return id;
          }

          String buildTransferNote({
            required String? linkedId,
            required String userText,
          }) {
            var result = '__transfer_bill__';
            if (linkedId != null && linkedId.isNotEmpty) {
              result += ' pair:$linkedId';
            }
            if (userText.isNotEmpty) {
              result += ' $userText';
            }
            return result;
          }

          bool sameCalendarDay(DateTime a, DateTime b) {
            return a.year == b.year && a.month == b.month && a.day == b.day;
          }

          final dateChanged = orig.date != _transactionDate;
          final amountChanged = orig.amount != amount;
          final clearedChanged = (orig.cleared ?? false) != _cleared;
          String origNote = orig.note ?? '';
          // Remove internal transfer marker and any pair tokens when comparing notes
          String cleanedOrigNote = origNote
              .replaceAll('__transfer_bill__', '')
              .replaceAll(RegExp(r'pair:[A-Za-z0-9\-]+'), '')
              .trim();
          String cleanedNewNote = userNote
              .replaceAll(RegExp(r'pair:[A-Za-z0-9\-]+'), '')
              .trim();
          final noteChanged = cleanedOrigNote != cleanedNewNote;

          // Find the paired transaction (other side of the transfer)
          final allTxs = DatabaseService.getAllTransactions();
          Transaction? pair;

          final explicitPairId = extractPairId(orig.note);
          if (explicitPairId != null) {
            try {
              pair = allTxs.firstWhere((t) => t.id == explicitPairId);
            } catch (_) {
              pair = null;
            }
          }

          if (pair == null) {
            try {
              pair = allTxs.firstWhere(
                (t) =>
                    t.id != orig.id &&
                    t.note != null &&
                    (t.note!.contains(orig.id) ||
                        (orig.note != null && orig.note!.contains(t.id))),
              );
            } catch (_) {
              pair = null;
            }
          }

          if (pair == null) {
            final candidates = allTxs.where(
              (t) =>
                  t.id != orig.id &&
                  t.amount == orig.amount &&
                  sameCalendarDay(t.date, orig.date) &&
                  t.categoryId == orig.categoryId &&
                  t.accountId != orig.accountId,
            );
            pair = candidates.isNotEmpty ? candidates.first : null;
          }

          final currentFromId = orig.type == TransactionType.expense
              ? orig.accountId
              : pair?.accountId;
          final currentToId = orig.type == TransactionType.income
              ? orig.accountId
              : pair?.accountId;
          final accountChanged =
              currentFromId != _fromAccountId || currentToId != _toAccountId;

          bool updateBoth = false;
          if (dateChanged ||
              noteChanged ||
              amountChanged ||
              clearedChanged ||
              accountChanged) {
            transferEditPrompted = true;
            String changeText = '';
            final changedParts = <String>[];
            if (dateChanged) changedParts.add('date');
            if (noteChanged) changedParts.add('notes');
            if (amountChanged) changedParts.add('amount');
            if (clearedChanged) changedParts.add('cleared status');
            if (accountChanged) changedParts.add('accounts');
            if (changedParts.length == 1) {
              changeText = changedParts.first;
            } else if (changedParts.length == 2) {
              changeText = '${changedParts[0]} and ${changedParts[1]}';
            } else {
              changeText =
                  '${changedParts.sublist(0, changedParts.length - 1).join(', ')}, and ${changedParts.last}';
            }
            updateBoth =
                await showDialog<bool>(
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
                      actionsPadding: const EdgeInsets.fromLTRB(
                        24,
                        20,
                        24,
                        18,
                      ),
                      title: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer.withValues(
                                alpha: 0.65,
                              ),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(
                              Icons.swap_horiz_rounded,
                              color: colorScheme.primary,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Text(
                              'Update Transfer',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                      content: Text(
                        'You changed the $changeText for this transfer. Do you want to update both sides or just this side?',
                        style: Theme.of(dialogContext).textTheme.bodyMedium
                            ?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                      ),
                      actions: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: 50,
                              child: FilledButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(true),
                                style: FilledButton.styleFrom(
                                  backgroundColor: colorScheme.primary,
                                  foregroundColor: colorScheme.onPrimary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Both Sides',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 50,
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(false),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: colorScheme.primary,
                                  side: BorderSide(
                                    color: colorScheme.outlineVariant,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Just This Side',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ) ??
                false;
          }

          if (updateBoth && pair == null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Could not find the linked transfer side. Please edit both entries manually once to relink.',
                  ),
                  backgroundColor: Colors.blueGrey[400],
                ),
              );
            }
            return;
          }

          // Determine old and new account IDs for both sides
          final oldFromId = orig.type == TransactionType.expense
              ? orig.accountId
              : (pair != null ? pair.accountId : null);
          final oldToId = orig.type == TransactionType.income
              ? orig.accountId
              : (pair != null ? pair.accountId : null);
          final newFromId = _fromAccountId;
          final newToId = _toAccountId;
          // Update both transactions' accountId if changed
          Transaction updatedOrig = orig;
          Transaction? updatedPair = pair;
          if (orig.type == TransactionType.expense &&
              newFromId != null &&
              orig.accountId != newFromId) {
            updatedOrig = orig.copyWith(accountId: newFromId);
          } else if (orig.type == TransactionType.income &&
              newToId != null &&
              orig.accountId != newToId) {
            updatedOrig = orig.copyWith(accountId: newToId);
          }
          if (pair != null) {
            if (pair.type == TransactionType.expense &&
                newFromId != null &&
                pair.accountId != newFromId) {
              updatedPair = pair.copyWith(accountId: newFromId);
            } else if (pair.type == TransactionType.income &&
                newToId != null &&
                pair.accountId != newToId) {
              updatedPair = pair.copyWith(accountId: newToId);
            }
          }
          // Update other fields (amount, description, date, note)
          final preserveBillPaymentDescription =
              orig.billId != null && orig.billId!.isNotEmpty;
          final newDescription =
              (widget.preserveDescriptionAndDate ||
                  preserveBillPaymentDescription)
              ? orig.description
              : desc;
          final newDate = widget.preserveDescriptionAndDate
              ? orig.date
              : _transactionDate;
          String cleanedNotes = userNote;
          if (cleanedNotes.contains('__transfer_bill__')) {
            cleanedNotes = cleanedNotes
                .replaceAll('__transfer_bill__', '')
                .trim();
          }

          final linkedIdForOrig = pair?.id;
          updatedOrig = updatedOrig.copyWith(
            amount: amount,
            description: newDescription,
            date: newDate,
            updatedAt: DateTime.now(),
            note: buildTransferNote(
              linkedId: linkedIdForOrig,
              userText: cleanedNotes,
            ),
            cleared: _cleared,
            showInReports: false,
            hideFromCalendarDashboard: true,
          );
          if (updateBoth && updatedPair != null) {
            updatedPair = updatedPair.copyWith(
              amount: amount,
              description: newDescription,
              date: newDate,
              updatedAt: DateTime.now(),
              note: buildTransferNote(
                linkedId: updatedOrig.id,
                userText: cleanedNotes,
              ),
              cleared: _cleared,
              showInReports: false,
              hideFromCalendarDashboard: true,
            );
          }
          // Save updated transactions
          await DatabaseService.updateTransaction(updatedOrig);
          if (updateBoth && updatedPair != null) {
            await DatabaseService.updateTransaction(updatedPair);
          }

          final accountDeltaById = <String, double>{};
          void applyDeltaForUpdate(Transaction before, Transaction after) {
            final beforeEffect = before.type == TransactionType.income
                ? before.amount
                : -before.amount;
            final afterEffect = after.type == TransactionType.income
                ? after.amount
                : -after.amount;

            if (before.accountId != null) {
              accountDeltaById[before.accountId!] =
                  (accountDeltaById[before.accountId!] ?? 0.0) - beforeEffect;
            }
            if (after.accountId != null) {
              accountDeltaById[after.accountId!] =
                  (accountDeltaById[after.accountId!] ?? 0.0) + afterEffect;
            }
          }

          applyDeltaForUpdate(orig, updatedOrig);
          if (updateBoth && pair != null && updatedPair != null) {
            applyDeltaForUpdate(pair, updatedPair);
          }

          for (final entry in accountDeltaById.entries) {
            if (entry.value == 0.0) continue;
            final acc = DatabaseService.getAccountById(entry.key);
            if (acc == null) continue;
            await DatabaseService.updateAccount(
              acc.copyWith(balance: acc.balance + entry.value),
            );
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
            final updatedDebit = debit.copyWith(
              note: '__transfer_bill__ pair:${credit.id}$linkedUserNote',
              cleared: _cleared,
              hideFromCalendarDashboard: true,
            );
            final updatedCredit = credit.copyWith(
              note: '__transfer_bill__ pair:${debit.id}$linkedUserNote',
              cleared: _cleared,
              hideFromCalendarDashboard: true,
            );
            await DatabaseService.updateTransaction(updatedDebit);
            await DatabaseService.updateTransaction(updatedCredit);
          } catch (_) {}

          // Update account balances for transfer
          if (_fromAccountId != null) {
            final fromAccount = DatabaseService.getAccountById(_fromAccountId!);
            if (fromAccount != null) {
              final updatedFromAccount = fromAccount.copyWith(
                balance: fromAccount.balance - amount,
              );
              await DatabaseService.updateAccount(updatedFromAccount);
            }
          }
          if (_toAccountId != null) {
            final toAccount = DatabaseService.getAccountById(_toAccountId!);
            if (toAccount != null) {
              final updatedToAccount = toAccount.copyWith(
                balance: toAccount.balance + amount,
              );
              await DatabaseService.updateAccount(updatedToAccount);
            }
          }
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving transaction: $e'),
            backgroundColor: Colors.blueGrey[400],
          ),
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
    if (widget.initialAccountId != null &&
        widget.initialAccountId!.isNotEmpty) {
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
      String cleanedNote = _sanitizeInternalNoteTokens(source.note!.trim());

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
    _transactionDate = widget.isRefund ? DateTime.now() : source.date;
    // If the transaction has a category, use it. Otherwise, if this
    // transaction is linked to a bill, default to the bill's category so
    // payments created via the Pay Bill flow show the originating category
    // when edited.
    if (source.categoryId.isNotEmpty) {
      _selectedCategoryId = source.categoryId;
      _originalCategoryId = source.categoryId;
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
        if (linkedBill != null &&
            linkedBill.categoryId != null &&
            linkedBill.categoryId!.isNotEmpty) {
          _selectedCategoryId = linkedBill.categoryId;
          _originalCategoryId = linkedBill.categoryId;
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
      final hasCanonicalTransferDescription = RegExp(
        r'^transfer\s+from\s+.+\s+to\s+.+$',
        caseSensitive: false,
      ).hasMatch(desc);

      if (hasTransferMarker || hasCanonicalTransferDescription) {
        final reg = RegExp(
          r'Transfer\s+from\s+(.+)\s+to\s+(.+)',
          caseSensitive: false,
        );
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
            pair = all.firstWhere(
              (t) =>
                  t.id != source.id &&
                  t.description == desc &&
                  t.amount == source.amount,
            );
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
        _initialTransactionType = _transactionType;
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
          if (catId != null &&
              DatabaseService.getAllCategories().any((c) => c.id == catId)) {
            final isBillPayment =
                source.billId != null && source.billId!.isNotEmpty;
            // Don't override the transaction's category if it's already set (i.e., when editing/duplicating)
            final hasTransactionCategory = source.categoryId.isNotEmpty;
            if (!isBillPayment && !hasTransactionCategory) {
              _selectedCategoryId = catId;
            }
          }
        } catch (_) {
          // ignore
        }
      }
    }

    // Finally, set transaction type from stored transaction (income/expense)
    _transactionType = widget.isRefund
        ? (source.type == TransactionType.income
              ? TransactionScreenType.expense
              : TransactionScreenType.income)
        : (source.type == TransactionType.income
              ? TransactionScreenType.income
              : TransactionScreenType.expense);
    _initialTransactionType = _transactionType;
    // Initialize cleared state from source (default false)
    _cleared = widget.isRefund ? false : source.cleared ?? false;
    _showInReports = source.showInReports;
  }
}

class _TransactionAddAccountPage extends StatefulWidget {
  const _TransactionAddAccountPage();

  @override
  State<_TransactionAddAccountPage> createState() =>
      _TransactionAddAccountPageState();
}

class _TransactionAddAccountPageState
    extends State<_TransactionAddAccountPage> {
  final _nameController = TextEditingController();
  final _institutionController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _cardNumberController = TextEditingController();
  final _balanceController = TextEditingController(text: '0.0');
  final _availableController = TextEditingController(text: '0.0');

  AccountType _selectedType = AccountType.cash;
  String? _customType;

  @override
  void dispose() {
    _nameController.dispose();
    _institutionController.dispose();
    _accountNumberController.dispose();
    _cardNumberController.dispose();
    _balanceController.dispose();
    _availableController.dispose();
    super.dispose();
  }

  String _displayType(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  InputDecoration _fieldDecoration(BuildContext context, String label) {
    final colors = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.35),
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
        borderSide: BorderSide(color: colors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  Future<void> _pickType() async {
    final builtIn = AccountType.values.map((t) => t.name).toList();
    final custom = DatabaseService.getAllCustomAccountTypes();
    final types = [...builtIn, ...custom].toSet().toList();
    final current = _customType ?? _selectedType.name;

    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Account Type',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add custom type',
                    icon: const Icon(Icons.add_rounded),
                    onPressed: () async {
                      final controller = TextEditingController();
                      final value = await showDialog<String>(
                        context: sheetContext,
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
                                if (text.isNotEmpty) {
                                  Navigator.pop(dialogContext, text);
                                }
                              },
                              child: const Text('Add'),
                            ),
                          ],
                        ),
                      );
                      controller.dispose();
                      if (value != null && value.isNotEmpty) {
                        if (sheetContext.mounted) Navigator.pop(sheetContext, value);
                      }
                    },
                  ),
                ],
              ),
            ),
            ...types.map(
              (type) {
                final builtInType = AccountType.values.where(
                  (candidate) =>
                      candidate.name.toLowerCase() == type.toLowerCase(),
                );
                final displayType = _displayType(type);
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  leading: builtInType.isNotEmpty
                      ? AccountTypeIcon(
                          type: builtInType.first,
                          displayName: displayType,
                        )
                      : const Icon(Icons.account_balance_wallet_outlined),
                  title: Text(displayType),
                  trailing: type.toLowerCase() == current.toLowerCase()
                      ? Icon(
                          Icons.check_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.pop(sheetContext, type),
                );
              },
            ),
          ],
        ),
      ),
    );

    if (picked == null || !mounted) return;
    final match = AccountType.values.where(
      (type) => type.name.toLowerCase() == picked.toLowerCase(),
    );
    setState(() {
      if (match.isNotEmpty) {
        _selectedType = match.first;
        _customType = null;
      } else {
        _customType = picked;
      }
    });
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an account name')),
      );
      return;
    }

    if (_customType != null && _customType!.isNotEmpty) {
      DatabaseService.addCustomAccountType(_customType!);
    }

    Navigator.pop(
      context,
      Account(
        name: name,
        type: _selectedType,
        institution: _institutionController.text.trim().isEmpty
            ? null
            : _institutionController.text.trim(),
        accountNumber: _accountNumberController.text.trim().isEmpty
            ? null
            : _accountNumberController.text.trim(),
        cardNumber: _cardNumberController.text.trim().isEmpty
            ? null
            : _cardNumberController.text.trim(),
        balance: double.tryParse(_balanceController.text) ?? 0.0,
        availableBalance: double.tryParse(_availableController.text),
        customType: _customType,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final outline = colors.outlineVariant.withValues(alpha: 0.35);

    Widget sectionLabel(String text) => Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Add Account'),
        centerTitle: true,
        backgroundColor: colors.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            sectionLabel('ACCOUNT DETAILS'),
            Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: outline),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: _fieldDecoration(context, 'Account name'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _institutionController,
                      textCapitalization: TextCapitalization.words,
                      decoration: _fieldDecoration(context, 'Institution'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _accountNumberController,
                      decoration: _fieldDecoration(context, 'Account number'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _cardNumberController,
                      decoration: _fieldDecoration(context, 'Card number'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            sectionLabel('ACCOUNT SETTINGS'),
            Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: outline),
              ),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 4,
                    ),
                    leading: const Icon(Icons.account_balance_wallet_outlined),
                    title: const Text('Type'),
                    subtitle: Text(
                      _displayType(_customType ?? _selectedType.name),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _pickType,
                  ),
                  Divider(height: 1, indent: 18, endIndent: 18, color: outline),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: TextField(
                      controller: _balanceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: _fieldDecoration(context, 'Initial balance'),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: TextField(
                      controller: _availableController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          _fieldDecoration(context, 'Available balance'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Save Account',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

// Payee selector bottom sheet
class _TransactionCategorySelectorPage extends StatefulWidget {
  final List<Category> categories;
  final String? initialSelectedId;
  final TransactionScreenType transactionType;

  const _TransactionCategorySelectorPage({
    required this.categories,
    this.initialSelectedId,
    required this.transactionType,
  });

  @override
  State<_TransactionCategorySelectorPage> createState() =>
      _TransactionCategorySelectorPageState();
}

class _TransactionCategorySelectorPageState
    extends State<_TransactionCategorySelectorPage> {
  late List<Category> _all;
  late List<Category> _filtered;
  String _query = '';
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialSelectedId;
    _reload(initial: true);
  }

  void _reload({bool initial = false}) {
    final expectedType = widget.transactionType == TransactionScreenType.income
        ? CategoryType.income
        : CategoryType.expense;
    final updated = DatabaseService.getAllCategories()
        .where((c) => c.type == expectedType)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (initial) {
      _all = updated;
      _filtered = List<Category>.from(updated);
    } else if (mounted) {
      setState(() {
        _all = updated;
        _filtered = _all
            .where((c) => c.name.toLowerCase().contains(_query))
            .toList();
      });
    }
  }

  void _onSearch(String value) {
    final query = value.trim().toLowerCase();
    setState(() {
      _query = query;
      _filtered = _all
          .where((c) => c.name.toLowerCase().contains(query))
          .toList();
    });
  }

  Future<void> _addCategory() async {
    FocusScope.of(context).unfocus();
    final result = await Navigator.of(context).push<Category>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _TransactionAddCategoryPage(
          transactionType: widget.transactionType,
        ),
      ),
    );
    if (result == null) return;
    try {
      final newId = await DatabaseService.addCategory(result);
      try {
        await LookupsSyncHelper.syncCategory(result.copyWith(id: newId));
      } catch (_) {}
      if (!mounted) return;
      _selectedId = newId;
      _reload();
      if (!mounted) return;
      Navigator.pop(context, newId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save category: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hint = widget.transactionType == TransactionScreenType.income
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: TextField(
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                onChanged: _onSearch,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: hint,
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
                    borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Text(
                        _query.isEmpty ? 'No categories yet' : 'No categories found',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.separated(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final category = _filtered[index];
                        final selected = _selectedId == category.id;
                        return Material(
                          color: selected
                              ? colorScheme.primaryContainer.withValues(alpha: 0.45)
                              : colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => Navigator.pop(context, category.id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: selected
                                      ? colorScheme.primary.withValues(alpha: 0.55)
                                      : colorScheme.outlineVariant.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: category.color.withValues(alpha: 0.14),
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
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  if (selected)
                                    Icon(Icons.check_circle_rounded, color: colorScheme.primary)
                                  else
                                    Icon(Icons.chevron_right_rounded, color: colorScheme.onSurfaceVariant),
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

class _TransactionAddCategoryPage extends StatefulWidget {
  final TransactionScreenType transactionType;
  const _TransactionAddCategoryPage({required this.transactionType});

  @override
  State<_TransactionAddCategoryPage> createState() => _TransactionAddCategoryPageState();
}

class _TransactionAddCategoryPageState extends State<_TransactionAddCategoryPage> {
  final _nameController = TextEditingController();
  Color _selectedColor = const Color(0xFF607D8B);

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _cancel() {
    FocusScope.of(context).unfocus();
    Navigator.pop(context);
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a category name')),
      );
      return;
    }
    final type = widget.transactionType == TransactionScreenType.income
        ? CategoryType.income
        : CategoryType.expense;
    Navigator.pop(
      context,
      Category(
        name: name,
        iconCodePoint: '0xe85d',
        colorValue: _selectedColor.value.toString(),
        type: type,
      ),
    );
  }

  Future<void> _pickColor() async {
    FocusScope.of(context).unfocus();
    final picked = await showAppColorPicker(
      context: context,
      initialColor: _selectedColor,
      title: 'Pick Category Color',
    );
    if (picked != null && mounted) setState(() => _selectedColor = picked);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isIncome = widget.transactionType == TransactionScreenType.income;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Cancel',
          onPressed: _cancel,
          icon: const Icon(Icons.close_rounded),
        ),
        title: const Text('Add Category'),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Text(
              isIncome
                  ? 'Create a category for your income.'
                  : 'Create a category for your expenses.',
              style: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            Text('NAME', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              autofocus: true,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                hintText: 'Category name',
                prefixIcon: const Icon(Icons.category_outlined),
                filled: true,
                fillColor: colorScheme.surfaceContainerLow,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.45)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text('COLOR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Material(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _pickColor,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.45)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _selectedColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black12),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Category Color', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 3),
                            Text('Tap to choose a color', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      Icon(Icons.color_lens_outlined, color: colorScheme.primary),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Add Category'),
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

class _TransactionPayeeSelectorPage extends StatefulWidget {
  final List<Map<String, dynamic>> payees;
  final String? initialSelectedId;
  final TransactionScreenType transactionType;

  const _TransactionPayeeSelectorPage({
    required this.payees,
    this.initialSelectedId,
    required this.transactionType,
  });

  @override
  State<_TransactionPayeeSelectorPage> createState() => _TransactionPayeeSelectorPageState();
}

class _TransactionPayeeSelectorPageState extends State<_TransactionPayeeSelectorPage> {
  late List<Map<String, dynamic>> _all;
  late List<Map<String, dynamic>> _filtered;
  String _query = '';
  String? _selectedId;

  bool get _isIncome => widget.transactionType == TransactionScreenType.income;
  String get _type => _isIncome ? 'payer' : 'payee';

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialSelectedId;
    _all = List<Map<String, dynamic>>.from(widget.payees)
      ..sort((a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo((b['name'] ?? '').toString().toLowerCase()));
    _filtered = List<Map<String, dynamic>>.from(_all);
  }

  void _onSearch(String value) {
    final q = value.trim().toLowerCase();
    setState(() {
      _query = q;
      _filtered = _all.where((p) => (p['name'] ?? '').toString().toLowerCase().contains(q)).toList();
    });
  }

  Future<void> _addPayee() async {
    FocusScope.of(context).unfocus();
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _TransactionAddPayeePage(transactionType: widget.transactionType),
      ),
    );
    if (result == null) return;
    final newPayee = <String, dynamic>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'name': result['name'],
      'type': _type,
      'categoryId': result['categoryId'],
    };
    try {
      await DatabaseService.addPayee(newPayee);
      try {
        await LookupsSyncHelper.syncPayeeOrPayer(newPayee);
      } catch (_) {}
      await DatabaseService.updatePayeeReferences(newPayee);
      if (!mounted) return;
      Navigator.pop(context, newPayee['id'] as String);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isIncome ? 'Unable to save payer: $e' : 'Unable to save payee: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(_isIncome ? 'Select Payer' : 'Select Payee'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: _isIncome ? 'Add payer' : 'Add payee',
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
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                onChanged: _onSearch,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: _isIncome ? 'Search payers' : 'Search payees',
                  filled: true,
                  fillColor: colorScheme.surfaceContainerLow,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.45)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Text(
                        _query.isEmpty
                            ? (_isIncome ? 'No payers yet' : 'No payees yet')
                            : (_isIncome ? 'No payers found' : 'No payees found'),
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.separated(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = _filtered[index];
                        final id = item['id']?.toString() ?? '';
                        final selected = _selectedId == id;
                        final category = DatabaseService.getCategoryById((item['categoryId'] ?? '').toString());
                        return Material(
                          color: selected
                              ? colorScheme.primaryContainer.withValues(alpha: 0.45)
                              : colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => Navigator.pop(context, id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: selected
                                      ? colorScheme.primary.withValues(alpha: 0.55)
                                      : colorScheme.outlineVariant.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary.withValues(alpha: 0.10),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.person_outline_rounded, color: colorScheme.primary),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text((item['name'] ?? '').toString(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                        if (category != null) ...[
                                          const SizedBox(height: 3),
                                          Text(category.name, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (selected)
                                    Icon(Icons.check_circle_rounded, color: colorScheme.primary)
                                  else
                                    Icon(Icons.chevron_right_rounded, color: colorScheme.onSurfaceVariant),
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

class _TransactionAddPayeePage extends StatefulWidget {
  final TransactionScreenType transactionType;
  const _TransactionAddPayeePage({required this.transactionType});

  @override
  State<_TransactionAddPayeePage> createState() => _TransactionAddPayeePageState();
}

class _TransactionAddPayeePageState extends State<_TransactionAddPayeePage> {
  final _nameController = TextEditingController();
  String? _categoryId;
  bool get _isIncome => widget.transactionType == TransactionScreenType.income;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _selectCategory() async {
    FocusScope.of(context).unfocus();
    final type = _isIncome ? CategoryType.income : CategoryType.expense;
    final categories = DatabaseService.getAllCategories().where((c) => c.type == type).toList();
    final selected = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _TransactionCategorySelectorPage(
          categories: categories,
          initialSelectedId: _categoryId,
          transactionType: widget.transactionType,
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _categoryId = selected);
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isIncome ? 'Please enter a payer name' : 'Please enter a payee name')),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    Navigator.pop(context, <String, dynamic>{'name': name, 'categoryId': _categoryId});
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedCategory = _findCategoryById(DatabaseService.getAllCategories(), _categoryId);
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Cancel',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(_isIncome ? 'Add Payer' : 'Add Payee'),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Text(
              _isIncome
                  ? 'Create a payer and optionally choose a default category.'
                  : 'Create a payee and optionally choose a default category.',
              style: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            Text('NAME', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              autofocus: true,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: _isIncome ? 'Payer name' : 'Payee name',
                prefixIcon: const Icon(Icons.person_outline_rounded),
                filled: true,
                fillColor: colorScheme.surfaceContainerLow,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.45)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text('DEFAULT CATEGORY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Material(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _selectCategory,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.45)),
                  ),
                  child: Row(
                    children: [
                      if (selectedCategory != null)
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(color: selectedCategory.color, shape: BoxShape.circle),
                        )
                      else
                        Icon(Icons.category_outlined, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Category', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 3),
                            Text(selectedCategory?.name ?? 'Select category', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: colorScheme.onSurfaceVariant),
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
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(_isIncome ? 'Add Payer' : 'Add Payee'),
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
