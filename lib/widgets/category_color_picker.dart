import 'package:flutter/material.dart';

class CategoryColorPicker extends StatelessWidget {
  final Color selectedColor;
  final List<Color> palette;
  final ValueChanged<Color> onColorSelected;

  const CategoryColorPicker({
    super.key,
    required this.selectedColor,
    required this.palette,
    required this.onColorSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final color in palette)
          GestureDetector(
            onTap: () => onColorSelected(color),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: color == selectedColor ? Colors.black : Colors.transparent,
                  width: 2,
                ),
              ),
              child: color == selectedColor
                  ? const Icon(Icons.check, color: Colors.white)
                  : null,
            ),
          ),
      ],
    );
  }
}
