import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:cashsenseflutter/utils/split_utils.dart';

void main() {
  group('categoryAllocations', () {
    test('allocates a split transaction to each split category', () {
      final allocations = categoryAllocations(
        primaryCategoryId: '',
        total: 100,
        splitsJson: jsonEncode([
          {'categoryId': 'groceries', 'amount': 60},
          {'categoryId': 'household', 'amount': 40},
        ]),
      );

      expect(allocations, {'groceries': 60, 'household': 40});
    });

    test('combines repeated split categories', () {
      final allocations = categoryAllocations(
        primaryCategoryId: 'primary',
        total: 25,
        splitsJson: jsonEncode([
          {'categoryId': 'food', 'amount': 10},
          {'categoryId': 'food', 'amount': 15},
        ]),
      );

      expect(allocations, {'food': 25});
    });

    test('falls back to primary category for malformed split data', () {
      final allocations = categoryAllocations(
        primaryCategoryId: 'primary',
        total: 100,
        splitsJson: jsonEncode([
          {'categoryId': 'groceries', 'amount': 50},
        ]),
      );

      expect(allocations, {'primary': 100});
    });
  });

  test('split categories require a category and positive amount', () {
    expect(
      validateSplitCategories([
        {'categoryId': 'groceries', 'amount': 10},
      ]),
      isTrue,
    );
    expect(
      validateSplitCategories([
        {'categoryId': '', 'amount': 10},
      ]),
      isFalse,
    );
  });

  group('remainingSplitAmount', () {
    test('calculates the remainder without counting the balancing split', () {
      final splits = [
        {'categoryId': 'groceries', 'amount': 60.25},
        {'categoryId': 'household', 'amount': 0},
      ];

      expect(remainingSplitAmount(100, splits, excludingIndex: 1), 39.75);
    });

    test('returns zero when the entered splits exceed the total', () {
      final splits = [
        {'categoryId': 'groceries', 'amount': 120},
        {'categoryId': 'household', 'amount': 0},
      ];

      expect(remainingSplitAmount(100, splits, excludingIndex: 1), 0);
    });
  });
}
