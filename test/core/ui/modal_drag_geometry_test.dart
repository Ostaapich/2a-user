import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/ui/blurred_modal_bottom_sheet.dart';

void main() {
  for (final side in [false, true]) {
    testWidgets(
      'accepted drag continues dismissal without jumping back side=$side',
      (tester) async {
        tester.view.physicalSize = Size(side ? 1200 : 390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const key = ValueKey('drag-header');
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showBlurredModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const SizedBox(
                      height: 240,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          key: key,
                          width: 100,
                          height: 40,
                          child: Text('Header'),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(key)),
        );
        await gesture.moveBy(side ? const Offset(20, 0) : const Offset(0, 20));
        await tester.pump();
        await gesture.moveBy(
          side ? const Offset(140, 0) : const Offset(0, 140),
        );
        await tester.pump();
        final during = tester.getTopLeft(find.byKey(key));
        await gesture.up();
        await tester.pump();
        final after = tester.getTopLeft(find.byKey(key));
        expect(
          side ? after.dx : after.dy,
          greaterThanOrEqualTo((side ? during.dx : during.dy) - 1),
          reason:
              'accepted close must continue in drag direction, not snap back',
        );
        await tester.pumpAndSettle();
        expect(find.byKey(key), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
