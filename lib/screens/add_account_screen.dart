import '../services/account_operations.dart';
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/account.dart';
import '../widgets/account_type_icon.dart';

class AddAccountScreen extends StatefulWidget {
  final Account? account;

  const AddAccountScreen({super.key, this.account});

  @override
  State<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends State<AddAccountScreen> {
  final int _accountGeneration = AccountOperations.generation;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _institutionController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _cardNumberController = TextEditingController();
  
  AccountType _type = AccountType.bank;
  String? _customTypeInput;
  final _customTypeController = TextEditingController();
  final _balanceController = TextEditingController(text: '0.00');
  final _availableBalanceController = TextEditingController(text: '0.00');
  final _balanceFocusNode = FocusNode();
  final _availableBalanceFocusNode = FocusNode();
  bool _balanceTouched = false;
  bool _availableBalanceTouched = false;

  @override
  void dispose() {
    _nameController.dispose();
    _institutionController.dispose();
    _accountNumberController.dispose();
    _cardNumberController.dispose();
    _balanceFocusNode.dispose();
    _availableBalanceFocusNode.dispose();
    _balanceController.dispose();
    _availableBalanceController.dispose();
    _customTypeController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final acc = widget.account;
    if (acc != null) {
      _nameController.text = acc.name;
      _type = acc.type;
      // Show the stored initial balance (the value the user entered when
      // they created/edited the account) so it doesn't change when current
      // account balance is updated by transactions.
      final storedInitial = DatabaseService.getInitialBalance(acc.id);
      _balanceController.text = storedInitial.toStringAsFixed(2);
      _institutionController.text = acc.institution ?? acc.description ?? '';
      _accountNumberController.text = acc.accountNumber ?? '';
      _cardNumberController.text = acc.cardNumber ?? '';
      _availableBalanceController.text = (acc.availableBalance ?? acc.balance).toStringAsFixed(2);
      _customTypeInput = acc.customType;
      _customTypeController.text = acc.customType ?? '';
    }
    // Set up focus listeners to clear placeholder on first focus
    _balanceFocusNode.addListener(() {
      if (_balanceFocusNode.hasFocus && !_balanceTouched) {
        _balanceTouched = true;
        if (_balanceController.text.trim() == '0.00') {
          _balanceController.clear();
        }
      }
      if (!_balanceFocusNode.hasFocus && _balanceController.text.trim().isEmpty) {
        _balanceController.text = '0.00';
      }
    });

    _availableBalanceFocusNode.addListener(() {
      if (_availableBalanceFocusNode.hasFocus && !_availableBalanceTouched) {
        _availableBalanceTouched = true;
        if (_availableBalanceController.text.trim() == '0.00') {
          _availableBalanceController.clear();
        }
      }
      if (!_availableBalanceFocusNode.hasFocus && _availableBalanceController.text.trim().isEmpty) {
        _availableBalanceController.text = '0.00';
      }
    });

  }

  Future<void> _save() {
    return AccountOperations.bind(_accountGeneration, () async {
    if (!_formKey.currentState!.validate()) return;
    final name = _nameController.text.trim();
    final type = _type;
    final balance = double.tryParse(_balanceController.text) ?? 0.0;
    final customType = _customTypeController.text.trim().isEmpty ? null : _customTypeController.text.trim();

    // Add custom type to the list if it's new
    if (customType != null && customType.isNotEmpty) {
      await DatabaseService.addCustomAccountType(customType);
    }

    if (widget.account != null) {
      final updated = widget.account!.copyWith(
        name: name,
        type: type,
        balance: double.tryParse(_balanceController.text) ?? 0,
        description: _institutionController.text,
        institution: _institutionController.text,
        accountNumber: _accountNumberController.text,
        cardNumber: _cardNumberController.text,
        availableBalance: double.tryParse(_availableBalanceController.text) ?? 0,
        customType: customType,
      );
      await DatabaseService.updateAccount(updated);
      // If the initial balance changed in the edit UI, update the stored initial balance
      final storedInitial = DatabaseService.getInitialBalance(widget.account!.id);
      if (storedInitial != balance) {
        await DatabaseService.setInitialBalance(widget.account!.id, balance);
      }
    } else {
      final account = Account(
        name: name,
        type: type,
        description: _institutionController.text,
        institution: _institutionController.text,
        accountNumber: _accountNumberController.text,
        cardNumber: _cardNumberController.text,
        balance: double.tryParse(_balanceController.text) ?? 0,
        availableBalance: double.tryParse(_availableBalanceController.text) ?? 0,
        customType: customType,
      );
      await DatabaseService.addAccount(account);
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
      });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.account != null ? 'Edit Account' : 'Add Account'),
      ),
      // Allow the form to scroll when the keyboard is up so the Save button
      // can be reached on smaller screens.
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Form fields

           Align(
  alignment: Alignment.centerLeft,
  child: Text(
    'ACCOUNT DETAILS',
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.7,
    ),
  ),
),

const SizedBox(height: 8),

Card(
  margin: EdgeInsets.zero,
  elevation: 0,
  color: Theme.of(context).colorScheme.surface,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(18),
    side: BorderSide(
      color: Theme.of(context)
          .colorScheme
          .outlineVariant
          .withValues(alpha: 0.35),
    ),
  ),
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        TextFormField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Account name',
            filled: true,
            fillColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.35),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 1.5,
              ),
            ),
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty)
                  ? 'Enter a name'
                  : null,
        ),

        const SizedBox(height: 12),

        TextFormField(
          controller: _institutionController,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Institution',
            filled: true,
            fillColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.35),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 1.5,
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        TextFormField(
          controller: _accountNumberController,
          keyboardType: TextInputType.text,
          decoration: InputDecoration(
            labelText: 'Account number',
            hintText: 'Optional',
            filled: true,
            fillColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.35),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 1.5,
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        TextFormField(
          controller: _cardNumberController,
          keyboardType: TextInputType.text,
          decoration: InputDecoration(
            labelText: 'Card number',
            hintText: 'Optional',
            filled: true,
            fillColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.35),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    ),
  ),
),

const SizedBox(height: 20),
Align(
  alignment: Alignment.centerLeft,
  child: Text(
    'ACCOUNT SETTINGS',
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.7,
    ),
  ),
),

const SizedBox(height: 8),

Card(
  margin: EdgeInsets.zero,
  elevation: 0,
  color: Theme.of(context).colorScheme.surface,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(18),
    side: BorderSide(
      color: Theme.of(context)
          .colorScheme
          .outlineVariant
          .withValues(alpha: 0.35),
    ),
  ),
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
       InkWell(
  borderRadius: BorderRadius.circular(12),
  onTap: () async {
    FocusScope.of(context).unfocus();

    final customTypes =
        DatabaseService.getAllCustomAccountTypes();

    final selectedValue = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor:
          Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (sheetContext) {
        final colorScheme =
            Theme.of(sheetContext).colorScheme;

        String? currentValue;

        if (_customTypeInput != null &&
            _customTypeInput!.isNotEmpty) {
          currentValue = _customTypeInput;
        } else if (widget.account != null ||
            _customTypeInput == null) {
          currentValue = _type.name;
        }

        Widget option({
          required String value,
          required String label,
          AccountType? accountType,
          IconData? icon,
        }) {
          final isSelected = currentValue == value;
          final iconColor = isSelected
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant;

          return ListTile(
            leading: accountType != null
                ? AccountTypeIcon(
                    type: accountType,
                    displayName: label,
                    color: iconColor,
                  )
                : Icon(icon, color: iconColor),
            title: Text(
              label,
              style: TextStyle(
                fontWeight: isSelected
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
            trailing: isSelected
                ? Icon(
                    Icons.check_rounded,
                    color: colorScheme.primary,
                  )
                : null,
            onTap: () {
              Navigator.pop(sheetContext, value);
            },
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              12,
              0,
              12,
              12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    12,
                    4,
                    12,
                    12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Select Account Type',
                          style: Theme.of(sheetContext)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),

                option(
                  value: AccountType.cash.name,
                  label: 'Cash',
                  accountType: AccountType.cash,
                ),
                option(
                  value: AccountType.bank.name,
                  label: 'Checking',
                  accountType: AccountType.bank,
                ),
                option(
                  value: AccountType.card.name,
                  label: 'Card',
                  accountType: AccountType.card,
                ),
                option(
                  value: AccountType.investment.name,
                  label: 'Savings',
                  accountType: AccountType.investment,
                ),

                if (customTypes.isNotEmpty) ...[
                  const Divider(height: 16),

                  ...customTypes.map(
                    (customTypeName) => option(
                      value: customTypeName,
                      label: customTypeName,
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                  ),
                ],

                const Divider(height: 16),

                ListTile(
                  leading: Icon(
                    Icons.add_rounded,
                    color: colorScheme.primary,
                  ),
                  title: Text(
                    'Add custom type',
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(
                      sheetContext,
                      '__add_custom__',
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selectedValue == null || !mounted) return;

    if (selectedValue == '__add_custom__') {
      setState(() {
        _customTypeInput = '';
        _customTypeController.clear();
      });
      return;
    }

    final builtInType = AccountType.values
        .where((t) => t.name == selectedValue)
        .firstOrNull;

    if (builtInType != null) {
      setState(() {
        _type = builtInType;
        _customTypeInput = null;
        _customTypeController.clear();
      });
    } else {
      setState(() {
        _customTypeInput = selectedValue;
        _customTypeController.text = selectedValue;
      });
    }
  },

  child: InputDecorator(
    decoration: InputDecoration(
      labelText: 'Type',
      filled: true,
      fillColor: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.35),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            _customTypeInput != null &&
                    _customTypeInput!.isNotEmpty
                ? _customTypeInput!
                : widget.account != null ||
                        _customTypeInput == null &&
                            _type != AccountType.bank
                    ? switch (_type) {
                        AccountType.cash => 'Cash',
                        AccountType.bank => 'Checking',
                        AccountType.card => 'Card',
                        AccountType.investment => 'Savings',
                      }
                    : 'Select Account Type',
            style: TextStyle(
              fontSize: 16,
              color: widget.account == null &&
                      _type == AccountType.bank &&
                      _customTypeInput == null
                  ? Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                  : Theme.of(context)
                      .colorScheme
                      .onSurface,
            ),
          ),
        ),
        Icon(
          Icons.keyboard_arrow_down_rounded,
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant,
        ),
      ],
    ),
  ),
),
              if (_customTypeInput != null) ...[
                const SizedBox(height: 12),
                TextFormField(
  controller: _customTypeController,
  textCapitalization: TextCapitalization.words,
  onTapOutside: (_) {
    FocusScope.of(context).unfocus();
  },
  decoration: InputDecoration(
    labelText: 'Custom type',
    filled: true,
    fillColor: Theme.of(context)
        .colorScheme
        .surfaceContainerHighest
        .withValues(alpha: 0.35),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.primary,
        width: 1.5,
      ),
    ),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 16,
    ),
  ),
),
              ],
              const SizedBox(height: 12),
           TextFormField(
  controller: _balanceController,
  keyboardType: const TextInputType.numberWithOptions(
    decimal: true,
    signed: true,
  ),
  focusNode: _balanceFocusNode,
  decoration: InputDecoration(
    labelText: 'Initial balance',
    prefixText: '\$ ',
    filled: true,
    fillColor: Theme.of(context)
        .colorScheme
        .surfaceContainerHighest
        .withValues(alpha: 0.35),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.primary,
        width: 1.5,
      ),
    ),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 16,
    ),
  ),
  validator: (v) => (v != null && double.tryParse(v) == null)
      ? 'Invalid number'
      : null,
),
              const SizedBox(height: 12),
            TextFormField(
  controller: _availableBalanceController,
  keyboardType: const TextInputType.numberWithOptions(
    decimal: true,
    signed: true,
  ),
  focusNode: _availableBalanceFocusNode,
  decoration: InputDecoration(
    labelText: 'Available balance',
    prefixText: '\$ ',
    filled: true,
    fillColor: Theme.of(context)
        .colorScheme
        .surfaceContainerHighest
        .withValues(alpha: 0.35),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.primary,
        width: 1.5,
      ),
    ),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 16,
    ),
  ),
  validator: (v) => (v != null && double.tryParse(v) == null)
      ? 'Invalid number'
      : null,
),
                    ],
    ),
  ),
),

const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _save,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
