// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

/// A reusable color picker dialog for the app.
Future<Color?> showAppColorPicker({
  required BuildContext context,
  required Color initialColor,
  String title = 'Pick a Color',
}) async {
  Color selectedColor = initialColor;
  return showDialog<Color>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: ColorPicker(
          pickerColor: selectedColor,
          onColorChanged: (color) => selectedColor = color,
          enableAlpha: false,
          showLabel: true,
          pickerAreaHeightPercent: 0.7,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(selectedColor),
          child: const Text('Select'),
        ),
      ],
    ),
  );
}
