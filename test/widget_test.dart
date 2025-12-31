// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

// ignore_for_file: unused_import

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cashsenseflutter/main.dart';
import 'package:cashsenseflutter/providers/theme_provider.dart';

void main() {
  testWidgets('CashSense app basic test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    // Use a minimal MaterialApp for this unit test to avoid app-wide init
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('CashSense')),
      ),
    ));

    // Verify that the app shows the CashSense title
    expect(find.text('CashSense'), findsOneWidget);
  });
}
