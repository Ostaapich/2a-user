import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/ui/blurred_modal_bottom_sheet.dart';

void main() {
  for (final width in [390.0, 1200.0]) {
    for (final safe in [true, false]) {
      testWidgets(
        'route consumes only its owned safe inset width=$width safe=$safe',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          tester.view.viewPadding = const FakeViewPadding(bottom: 34);
          tester.view.padding = const FakeViewPadding(bottom: 34);
          addTearDown(tester.view.reset);
          MediaQueryData? childMedia;
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showBlurredModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: safe,
                      builder: (context) {
                        childMedia = MediaQuery.of(context);
                        return const SizedBox(height: 240, child: Text('form'));
                      },
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          final expected = width < 840 && safe ? 0.0 : 34.0;
          expect(
            childMedia!.padding.bottom,
            expected,
            reason: 'inner form must not repeat route-owned system padding',
          );
          expect(childMedia!.viewPadding.bottom, expected);
          tester.view.viewInsets = const FakeViewPadding(bottom: 320);
          tester.view.padding = const FakeViewPadding();
          await tester.pumpAndSettle();
          expect(childMedia!.viewInsets.bottom, 0);
          expect(childMedia!.padding.bottom, 0);
          expect(childMedia!.viewPadding.bottom, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
