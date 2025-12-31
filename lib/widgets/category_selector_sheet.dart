// ignore_for_file: use_super_parameters, deprecated_member_use

import 'package:flutter/material.dart';
import '../models/category.dart';
import '../services/database_service.dart';

class CategorySelectorSheet extends StatefulWidget {
  final List<Category> categories;
  final bool hideAddButton;

  const CategorySelectorSheet({required this.categories, this.hideAddButton = false, Key? key}) : super(key: key);

  @override
  State<CategorySelectorSheet> createState() => _CategorySelectorSheetState();
}

class _CategorySelectorSheetState extends State<CategorySelectorSheet> {
  String _searchText = '';
  late List<Category> _allCategories;
  VoidCallback? _categoriesListener;

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
          TextField(
            decoration: const InputDecoration(
              labelText: 'Search',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _searchText = v.trim()),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filteredCategories.isEmpty
                ? const Center(child: Text('No categories found.'))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: filteredCategories.length,
                    itemBuilder: (context, index) {
                      final c = filteredCategories[index];
                      Widget leading;
                      if (c.image != null && c.image!.isNotEmpty) {
                        final chars = c.image!.runes.toList();
                        final emojiRegex = RegExp(r'^[\u{1F1E6}-\u{1F1FF}\u{1F300}-\u{1F5FF}\u{1F600}-\u{1F64F}\u{1F680}-\u{1F6FF}\u{1F700}-\u{1F77F}\u{1F780}-\u{1F7FF}\u{1F800}-\u{1F8FF}\u{1F900}-\u{1F9FF}\u{1FA00}-\u{1FAFF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{2300}-\u{23FF}]$', unicode: true);
                        if (chars.length == 1 && emojiRegex.hasMatch(c.image!)) {
                          leading = Text(c.image!, style: TextStyle(fontSize: 20, color: c.color));
                        } else {
                          leading = Icon(c.icon, color: c.color);
                        }
                      } else {
                        leading = Icon(c.icon, color: c.color);
                      }

                      return ListTile(
                        leading: CircleAvatar(backgroundColor: c.color.withOpacity(0.2), child: leading),
                        title: Text(c.name),
                        onTap: () => Navigator.pop(context, c.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // Initialize with provided categories or full list if none provided
    _allCategories = widget.categories.isNotEmpty ? widget.categories : DatabaseService.getAllCategories();
    _categoriesListener = () {
      setState(() {
        _allCategories = DatabaseService.getAllCategories();
      });
    };
    DatabaseService.categoriesVersion.addListener(_categoriesListener!);
  }

  @override
  void dispose() {
    if (_categoriesListener != null) DatabaseService.categoriesVersion.removeListener(_categoriesListener!);
    super.dispose();
  }
}
