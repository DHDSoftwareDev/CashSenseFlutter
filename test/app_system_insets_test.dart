import 'package:cashsenseflutter/widgets/app_system_insets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final bottom in [24.0, 48.0]) {
    testWidgets(
      'Protects controls with bottom inset $bottom without doubling it',
      (tester) async {
        const target = Key('controls');
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(800, 600),
                padding: EdgeInsets.fromLTRB(30, 24, 20, bottom),
                viewPadding: EdgeInsets.fromLTRB(30, 24, 20, bottom),
              ),
              child: const AppSystemInsets(
                child: SafeArea(child: SizedBox.expand(key: target)),
              ),
            ),
          ),
        );
        expect(tester.getTopLeft(find.byKey(target)), const Offset(30, 24));
        expect(
          tester.getBottomRight(find.byKey(target)),
          Offset(780, 600 - bottom),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Keyboard inset is still handled once by Scaffold', (
    tester,
  ) async {
    const target = Key('body');
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(800, 600),
            viewPadding: EdgeInsets.only(bottom: 48),
            viewInsets: EdgeInsets.only(bottom: 300),
          ),
          child: AppSystemInsets(
            child: Scaffold(body: SizedBox.expand(key: target)),
          ),
        ),
      ),
    );
    expect(tester.getBottomRight(find.byKey(target)).dy, 300);
    expect(tester.takeException(), isNull);
  });
}
