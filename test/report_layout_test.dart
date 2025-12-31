// ignore_for_file: unused_local_variable

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cashsenseflutter/widgets/report_details_list.dart';

class TestSlice {
  final String label;
  final double value;
  final Color color;
  TestSlice(this.label, this.value, this.color);
}

void main() {
  testWidgets('ReportDetailsList does not overflow with long labels', (tester) async {
    final slices = List.generate(10, (i) {
      final label = 'Very long label that will exceed the available width for testing purposes - item $i - additional text to ensure overflow';
      return TestSlice(label, 12345.67 + i, Colors.blue);
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: ReportDetailsList(
            slices: slices,
            total: 12345.67 * slices.length,
          ),
        ),
      ),
    ));

    await tester.pumpAndSettle();

    // Assert the widget built and list items are visible
    expect(find.byType(ReportDetailsList), findsOneWidget);
    for (final s in slices) {
      expect(find.textContaining('item'), findsWidgets);
    }
  });

  testWidgets('Card header row with long title will ellipsize', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 240,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                      child: Text(
                        'This is a very long title that should ellipsize on small screens with a currency on the right',
                        style: const TextStyle(fontSize: 18),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                    Text('\$3,456.00', style: const TextStyle(fontSize: 18)),
                ],
              ),
            ),
          ),
        ),
      ),
    ));

    await tester.pumpAndSettle();

    expect(find.byType(Card), findsOneWidget);
    expect(find.textContaining('very long title'), findsOneWidget);
  });
}
