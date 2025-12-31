import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/account.dart';

class AddAccountScreen extends StatefulWidget {
  final Account? account;

  const AddAccountScreen({super.key, this.account});

  @override
  State<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends State<AddAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _accountNumberController = TextEditingController();
  
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
    _descriptionController.dispose();
    _accountNumberController.dispose();
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
      _descriptionController.text = acc.description ?? '';
      _accountNumberController.text = acc.accountNumber ?? '';
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

  Future<void> _save() async {
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
        balance: balance,
        description: _descriptionController.text.trim(),
        accountNumber: _accountNumberController.text.trim(),
        availableBalance: double.tryParse(_availableBalanceController.text) ?? balance,
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
        balance: balance,
        description: _descriptionController.text.trim(),
        accountNumber: _accountNumberController.text.trim(),
        availableBalance: double.tryParse(_availableBalanceController.text) ?? balance,
        customType: customType,
      );
      await DatabaseService.addAccount(account);
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
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

              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Account name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Institution'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountNumberController,
                decoration: const InputDecoration(
                  labelText: 'Account/card number (optional)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.text,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                // When creating a new account don't preselect a built-in type so
                // the field shows the 'Type' placeholder instead of defaulting
                // to 'Bank'. When editing an existing account, preserve the
                // saved type selection.
                initialValue: widget.account != null
                    ? (_customTypeInput != null
                        ? (_customTypeInput!.isEmpty ? null : _customTypeInput)
                        : _type.name)
                    : null,
                hint: const Text('Select Account Type'),
                items: [
                  ...AccountType.values.map((t) {
                    String label;
                    switch (t) {
                      case AccountType.cash:
                        label = 'Cash';
                        break;
                      case AccountType.bank:
                        label = 'Checking';
                        break;
                      case AccountType.card:
                        label = 'Card';
                        break;
                      case AccountType.investment:
                        label = 'Savings';
                        break;
                    }
                    return DropdownMenuItem(value: t.name, child: Text(label));
                  }),
                  // Add a sentinel menu item to allow adding a new custom type
                  const DropdownMenuItem(value: '__add_custom__', child: Text('Add custom type...')),
                  // Add custom account types from the list (shown after built-in types and the add action)
                  ...DatabaseService.getAllCustomAccountTypes().map((customTypeName) {
                    return DropdownMenuItem(value: customTypeName, child: Text(customTypeName));
                  }),
                ],
                onChanged: (v) {
                  if (v == '__add_custom__') {
                    // user chose Add custom type...
                    setState(() {
                      _customTypeInput = '';
                      _customTypeController.clear();
                    });
                    return;
                  } else if (v == null) {
                    // no-op: user cleared selection
                    return;
                  } else {
                    // Check if it's a built-in type or custom type
                    final builtInType = AccountType.values.where((t) => t.name == v).firstOrNull;
                    if (builtInType != null) {
                      setState(() {
                        _type = builtInType;
                        _customTypeInput = null;
                      });
                    } else {
                      // It's an existing custom type
                      setState(() {
                        _customTypeInput = v;
                        _customTypeController.text = v;
                      });
                    }
                  }
                },
                decoration: const InputDecoration(labelText: 'Type'),
              ),
              if (_customTypeInput != null) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _customTypeController,
                  decoration: const InputDecoration(labelText: 'Custom type'),
                  textCapitalization: TextCapitalization.words,
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _balanceController,
                decoration: const InputDecoration(labelText: 'Initial balance'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                focusNode: _balanceFocusNode,
                validator: (v) => (v != null && double.tryParse(v) == null) ? 'Invalid number' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _availableBalanceController,
                decoration: const InputDecoration(labelText: 'Available balance'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                focusNode: _availableBalanceFocusNode,
                validator: (v) => (v != null && double.tryParse(v) == null) ? 'Invalid number' : null,
              ),
              const SizedBox(height: 12),
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
