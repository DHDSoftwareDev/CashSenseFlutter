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
                      return ListTile(
                        leading: SizedBox(
                          width: 24,
                          height: 24,
                          child: Center(
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: c.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
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
