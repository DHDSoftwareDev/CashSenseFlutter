import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../models/category.dart';
import '../utils/split_utils.dart';

typedef SplitsChanged = void Function(List<Map<String, dynamic>> splits);

class SplitsEditor extends StatefulWidget {
  final List<Map<String, dynamic>>? initialSplits;
  final SplitsChanged? onChanged;
  final double? transactionAmount;
  final CategoryType? categoryTypeFilter;

  const SplitsEditor({
    super.key,
    this.initialSplits,
    this.onChanged,
    this.transactionAmount,
    this.categoryTypeFilter,
  });

  @override
  State<SplitsEditor> createState() => _SplitsEditorState();
}

class _SplitsEditorState extends State<SplitsEditor> {
  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: '\$');
  late List<Map<String, dynamic>> _splits;
  final List<TextEditingController> _amountControllers = [];
  final List<FocusNode> _amountFocusNodes = [];
  final List<bool> _amountWasEdited = [];

  @override
  void initState() {
    super.initState();
    _splits = widget.initialSplits != null
        ? widget.initialSplits!
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : <Map<String, dynamic>>[];
    for (final split in _splits) {
      final amount = _amountFrom(split);
      _amountControllers.add(
        TextEditingController(text: amount == 0 ? '' : _displayAmount(amount)),
      );
      _amountFocusNodes.add(FocusNode());
      // Existing non-zero values should not be overwritten when this editor
      // first appears. Newly added/zero rows remain available for balancing.
      _amountWasEdited.add(amount != 0);
    }
  }

  @override
  void didUpdateWidget(covariant SplitsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.transactionAmount != oldWidget.transactionAmount) {
      _rebalance();
    }
  }

  @override
  void dispose() {
    for (final controller in _amountControllers) {
      controller.dispose();
    }
    for (final focusNode in _amountFocusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  double _amountFrom(Map<String, dynamic> split) {
    final amount = split['amount'];
    if (amount is num) return amount.toDouble();
    return double.tryParse(amount?.toString() ?? '') ?? 0.0;
  }

  String _displayAmount(double amount) => amount.toStringAsFixed(2);

  void _setAmount(int index, double amount) {
    _splits[index]['amount'] = amount;
    final text = amount == 0 ? '' : _displayAmount(amount);
    if (_amountControllers[index].text != text) {
      _amountControllers[index].text = text;
    }
  }

  int? _balancingIndex({int? except}) {
    for (var i = _splits.length - 1; i >= 0; i--) {
      if (i != except && !_amountWasEdited[i]) return i;
    }
    return null;
  }

  void _rebalance({int? except, int? preferredIndex}) {
    final total = widget.transactionAmount;
    if (total == null || _splits.length < 2) return;
    final index = preferredIndex ?? _balancingIndex(except: except);
    if (index == null || index == except) return;
    // Keep a single automatic balancing row. With three or more categories,
    // intermediate untouched rows stay blank while the final untouched row
    // shows the full remainder.
    for (var i = 0; i < _splits.length; i++) {
      if (i != index && i != except && !_amountWasEdited[i]) {
        _setAmount(i, 0);
      }
    }
    _setAmount(
      index,
      remainingSplitAmount(total, _splits, excludingIndex: index),
    );
  }

  void _notify() {
    if (widget.onChanged != null) widget.onChanged!(_splits);
  }

  void _addSplit() {
    setState(() {
      _splits.add({'categoryId': '', 'amount': 0.0});
      _amountControllers.add(TextEditingController());
      _amountFocusNodes.add(FocusNode());
      _amountWasEdited.add(false);
      if (_splits.length > 1) {
        _rebalance(preferredIndex: _splits.length - 1);
      }
    });
    _notify();
  }

  void _removeSplit(int idx) {
    setState(() {
      _splits.removeAt(idx);
      _amountControllers.removeAt(idx).dispose();
      _amountFocusNodes.removeAt(idx).dispose();
      _amountWasEdited.removeAt(idx);
      _rebalance();
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    var categories = DatabaseService.getAllCategories();
    if (widget.categoryTypeFilter != null) {
      categories = categories
          .where((c) => c.type == widget.categoryTypeFilter)
          .toList();
    }
    final total = widget.transactionAmount ?? 0.0;
    final sum = _splits.fold<double>(0.0, (s, e) {
      final a = e['amount'];
      if (a is num) return s + a.toDouble();
      if (a is String) return s + (double.tryParse(a) ?? 0.0);
      return s;
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Splits',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton.icon(
                  onPressed: _addSplit,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_splits.isEmpty)
              Text(
                'No splits defined',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              Column(
                children: List.generate(_splits.length, (i) {
                  final split = _splits[i];
                  final selCatId = split['categoryId']?.toString() ?? '';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Row(
                      children: [
                        // Category dropdown should expand to take available space
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: selCatId.isEmpty ? null : selCatId,
                            hint: const Text('Category'),
                            items: categories.map<DropdownMenuItem<String>>((
                              Category c,
                            ) {
                              return DropdownMenuItem(
                                value: c.id,
                                child: Text(c.name),
                              );
                            }).toList(),
                            onChanged: (v) {
                              split['categoryId'] = v ?? '';
                              _notify();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Constrain the amount input so it can shrink on small screens
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 70,
                            maxWidth: 120,
                          ),
                          child: SizedBox(
                            width: 110,
                            child: TextFormField(
                              controller: _amountControllers[i],
                              focusNode: _amountFocusNodes[i],
                              textAlign: TextAlign.right,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                prefixText: '\$ ',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 8,
                                ),
                              ),
                              onTap: () {
                                final controller = _amountControllers[i];
                                if (_amountFrom(split) == 0) {
                                  controller.clear();
                                } else {
                                  controller.selection = TextSelection(
                                    baseOffset: 0,
                                    extentOffset: controller.text.length,
                                  );
                                }
                              },
                              onChanged: (v) {
                                split['amount'] = double.tryParse(v) ?? 0.0;
                                _amountWasEdited[i] = v.trim().isNotEmpty;
                                _rebalance(except: i);
                                setState(() {});
                                _notify();
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Keep delete button compact so it doesn't force row expansion
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          icon: const Icon(
                            Icons.delete_forever,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                          onPressed: () => _removeSplit(i),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total: ${_currencyFormat.format(sum)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (widget.transactionAmount != null)
                  Text(
                    'Target: ${_currencyFormat.format(total)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
            if (widget.transactionAmount != null &&
                (sum - total).abs() > 0.01) ...[
              const SizedBox(height: 6),
              Text(
                'Split totals do not match transaction amount',
                style: TextStyle(color: Colors.red[700], fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
