import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/ui/blurred_modal_bottom_sheet.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('modal consumes keyboard exactly once on $platform', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
      tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
      addTearDown(tester.view.reset);
      double? childInset;
      const surface = ValueKey('surface');
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showBlurredModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) {
                    childInset = MediaQuery.viewInsetsOf(context).bottom;
                    return const SizedBox(
                      key: surface,
                      height: 2000,
                      child: Column(
                        children: [
                          Text('Form'),
                          Expanded(
                            child: SingleChildScrollView(child: TextField()),
                          ),
                        ],
                      ),
                    );
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
      await tester.tap(find.byType(TextField));
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      tester.view.padding = const FakeViewPadding(top: 44);
      await tester.pumpAndSettle();
      expect(
        childInset,
        0,
        reason:
            'route consumes keyboard; nested legacy pads must not double it',
      );
      expect(
        tester.getBottomRight(find.byKey(surface)).dy,
        closeTo(844 - 320, 1),
      );
      expect(
        tester.getTopLeft(find.byKey(surface)).dy,
        greaterThanOrEqualTo(44 + 24),
      );
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: -0.000001);
      tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
      await tester.pumpAndSettle();
      expect(
        tester.getBottomRight(find.byKey(surface)).dy,
        closeTo(844 - 34, 1),
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'short phone reserves safe header space and clamps caller minimum height',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);
      const key = ValueKey('compact-surface');
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showBlurredModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  constraints: const BoxConstraints(minHeight: 700),
                  builder: (_) => const SizedBox(
                    key: key,
                    height: 900,
                    child: Column(
                      children: [
                        Text('Header'),
                        Expanded(
                          child: SingleChildScrollView(child: TextField()),
                        ),
                      ],
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
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      tester.view.padding = const FakeViewPadding(top: 24);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(key)).dy, closeTo(32, 1));
      expect(tester.getBottomRight(find.byKey(key)).dy, closeTo(320, 1));
      expect(tester.takeException(), isNull);
    },
  );
}
