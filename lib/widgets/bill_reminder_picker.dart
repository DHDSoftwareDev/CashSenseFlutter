import 'package:flutter/material.dart';

import '../models/reminder_offset.dart';

class BillReminderPicker extends StatefulWidget {
  final List<ReminderOffset> initialValue;
  final ValueChanged<List<ReminderOffset>> onChanged;

  const BillReminderPicker({
    super.key,
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<BillReminderPicker> createState() => _BillReminderPickerState();
}

class _BillReminderPickerState extends State<BillReminderPicker> {
  late List<ReminderOffset> _reminders;

  @override
  void initState() {
    super.initState();
    _reminders = _sortedUnique(widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant BillReminderPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _reminders = _sortedUnique(widget.initialValue);
    }
  }

  List<ReminderOffset> _sortedUnique(List<ReminderOffset> items) {
    final map = <String, ReminderOffset>{};
    for (final item in items) {
      map[item.dedupeKey] = item;
    }
    final list = map.values.toList();
    list.sort((a, b) {
      if (a.daysBefore != b.daysBefore) {
        return b.daysBefore.compareTo(a.daysBefore);
      }
      if (a.hour != b.hour) {
        return a.hour.compareTo(b.hour);
      }
      return a.minute.compareTo(b.minute);
    });
    return list;
  }

  void _emit() {
    final cleaned = _sortedUnique(_reminders);
    setState(() => _reminders = cleaned);
    widget.onChanged(cleaned);
  }

  Future<void> _addReminder() async {
    final result = await showModalBottomSheet<ReminderOffset>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ReminderEditorSheet(),
    );

    if (result != null) {
      _reminders.add(result);
      _emit();
    }
  }

  Future<void> _editReminder(int index) async {
    final result = await showModalBottomSheet<ReminderOffset>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReminderEditorSheet(initialValue: _reminders[index]),
    );

    if (result != null) {
      _reminders[index] = result;
      _emit();
    }
  }

  void _removeReminder(int index) {
    _reminders.removeAt(index);
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Reminders',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(
              onPressed: _addReminder,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_reminders.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('No reminders set'),
          )
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: List.generate(_reminders.length, (index) {
                final reminder = _reminders[index];

                return Dismissible(
                  key: ValueKey(reminder.dedupeKey),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => _removeReminder(index),
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade400,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  child: ListTile(
                    title: Text(reminder.daysLabel),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _editReminder(index),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}

class _ReminderEditorSheet extends StatefulWidget {
  final ReminderOffset? initialValue;

  const _ReminderEditorSheet({this.initialValue});

  @override
  State<_ReminderEditorSheet> createState() => _ReminderEditorSheetState();
}

class _ReminderEditorSheetState extends State<_ReminderEditorSheet> {
  late int _daysBefore;

  static const List<int> _dayOptions = [0, 1, 2, 3, 5, 7, 14, 30];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue;
    _daysBefore = initial?.daysBefore ?? 1;
    // Time is fixed to 9:00 AM
  }


  void _save() {
    Navigator.pop(
      context,
      ReminderOffset(
        daysBefore: _daysBefore,
        hour: 9,
        minute: 0,
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Text(
              widget.initialValue == null ? 'Add Reminder' : 'Edit Reminder',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _daysBefore,
              decoration: const InputDecoration(
                labelText: 'When',
                border: OutlineInputBorder(),
              ),
              items: _dayOptions.map((days) {
                final label = days == 0
                    ? 'Due date'
                    : days == 1
                        ? '1 day before'
                        : '$days days before';
                return DropdownMenuItem<int>(
                  value: days,
                  child: Text(label),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _daysBefore = value);
                }
              },
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                child: const Text('Save Reminder'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
