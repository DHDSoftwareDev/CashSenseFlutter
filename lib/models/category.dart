import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'category.g.dart';

@HiveType(typeId: 13)
enum CategoryType {
  @HiveField(0)
  expense,
  @HiveField(1)
  income,
}

@HiveType(typeId: 12)
class Category extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String iconCodePoint;

  @HiveField(3)
  String colorValue;

  @HiveField(4)
  bool isDefault;

  @HiveField(5)
  double? budgetLimit;

  @HiveField(6)
  String? image;

  @HiveField(7)
  CategoryType type;

  Category({
    String? id,
    required this.name,
    required this.iconCodePoint,
    required this.colorValue,
    this.isDefault = false,
    this.budgetLimit,
    this.image,
    this.type = CategoryType.expense,
  }) : id = id ?? const Uuid().v4();

  // Use a static const map for icons to ensure const IconData
  static const Map<String, IconData> iconMap = {
    // Add all used iconCodePoints here, e.g.:
    '0xe88a': IconData(0xe88a, fontFamily: 'MaterialIcons'), // example
    // Add more as needed
  };

  IconData get icon => Category.iconMap[iconCodePoint] ?? const IconData(0xe88a, fontFamily: 'MaterialIcons');

  Color get color {
    final raw = colorValue.trim();
    if (raw.isEmpty) return const Color(0xFF607D8B);

    try {
      if (raw.startsWith('0x') || raw.startsWith('0X')) {
        return Color(int.parse(raw.substring(2), radix: 16));
      }

      if (raw.startsWith('#')) {
        final hex = raw.substring(1);
        if (hex.length == 6) {
          return Color(int.parse('FF$hex', radix: 16));
        }
        if (hex.length == 8) {
          return Color(int.parse(hex, radix: 16));
        }
      }

      return Color(int.parse(raw));
    } catch (_) {
      return const Color(0xFF607D8B);
    }
  }

  /// Returns a single grapheme emoji for UI display, otherwise null.
  /// This accepts composed emojis (skin tone, ZWJ sequences, flags).
  String? get displayEmoji {
    final raw = image?.trim();
    if (raw == null || raw.isEmpty) return null;
    try {
      return raw.characters.length == 1 ? raw : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'iconCodePoint': iconCodePoint,
      'colorValue': colorValue,
      'isDefault': isDefault,
      'budgetLimit': budgetLimit,
  'image': image,
  'isIncome': type == CategoryType.income,
  'type': type.toString().split('.').last,
    };
  }

  factory Category.fromJson(Map<String, dynamic> json) {
    CategoryType type = CategoryType.expense;
    try {
      if (json.containsKey('type') && json['type'] is String) {
        final s = (json['type'] as String).toLowerCase();
        if (s.contains('income')) type = CategoryType.income;
      } else if (json.containsKey('isIncome')) {
        final raw = json['isIncome'];
        final normalized = raw?.toString().trim().toLowerCase();
        final isIncome = raw == true || raw == 1 || normalized == 'true' || normalized == '1';
        if (isIncome) type = CategoryType.income;
      }
    } catch (_) {}

    return Category(
      id: json['id'],
      name: json['name'],
      iconCodePoint: json['iconCodePoint'],
      colorValue: (json['colorValue'] ?? '0xFF607D8B').toString(),
      isDefault: json['isDefault'] ?? false,
      budgetLimit: json['budgetLimit']?.toDouble(),
      image: json['image'],
      type: type,
    );
  }

  Category copyWith({
    String? id,
    String? name,
    String? iconCodePoint,
    String? colorValue,
    bool? isDefault,
    double? budgetLimit,
  String? image,
  CategoryType? type,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      iconCodePoint: iconCodePoint ?? this.iconCodePoint,
      colorValue: colorValue ?? this.colorValue,
      isDefault: isDefault ?? this.isDefault,
      budgetLimit: budgetLimit ?? this.budgetLimit,
  image: image ?? this.image,
  type: type ?? this.type,
    );
  }
}

// Predefined categories
class DefaultCategories {
  static List<Category> expenseCategories = [
    Category(
      name: 'Food & Dining',
      iconCodePoint: '0xe537', // Icons.restaurant
      colorValue: '0xFFFF5722',
      isDefault: true,
    ),
    Category(
      name: 'Transportation',
      iconCodePoint: '0xe1c1', // Icons.directions_car
      colorValue: '0xFF2196F3',
      isDefault: true,
    ),
    Category(
      name: 'Shopping',
      iconCodePoint: '0xe59c', // Icons.shopping_bag
      colorValue: '0xFF9C27B0',
      isDefault: true,
    ),
    Category(
      name: 'Entertainment',
      iconCodePoint: '0xe02c', // Icons.movie
      colorValue: '0xFFE91E63',
      isDefault: true,
    ),
    Category(
      name: 'Bills & Utilities',
      iconCodePoint: '0xe0e4', // Icons.receipt
      colorValue: '0xFFFF9800',
      isDefault: true,
    ),
    Category(
      name: 'Healthcare',
      iconCodePoint: '0xe1d8', // Icons.local_hospital
      colorValue: '0xFFF44336',
      isDefault: true,
    ),
    Category(
      name: 'Education',
      iconCodePoint: '0xe80c', // Icons.school
      colorValue: '0xFF4CAF50',
      isDefault: true,
    ),
    Category(
      name: 'Travel',
      iconCodePoint: '0xe1d1', // Icons.flight
      colorValue: '0xFF00BCD4',
      isDefault: true,
    ),
  ];

  static List<Category> incomeCategories = [
    Category(
      name: 'Salary',
      iconCodePoint: '0xe8f7', // Icons.work
      colorValue: '0xFF4CAF50',
      isDefault: true,
      type: CategoryType.income,
    ),
    Category(
      name: 'Freelance',
      iconCodePoint: '0xe89c', // Icons.laptop
      colorValue: '0xFF2196F3',
      isDefault: true,
      type: CategoryType.income,
    ),
    Category(
      name: 'Investment',
      iconCodePoint: '0xe1db', // Icons.trending_up
      colorValue: '0xFF9C27B0',
      isDefault: true,
      type: CategoryType.income,
    ),
    Category(
      name: 'Gift',
      iconCodePoint: '0xe8cc', // Icons.card_giftcard
      colorValue: '0xFFE91E63',
      isDefault: true,
      type: CategoryType.income,
    ),
    Category(
      name: 'Other Income',
      iconCodePoint: '0xe85d', // Icons.add_circle
      colorValue: '0xFF607D8B',
      isDefault: true,
      type: CategoryType.income,
    ),
  ];
}
