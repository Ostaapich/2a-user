import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_layout.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'touch dismisses numeric keyboard and retains text on $platform',
      (tester) async {
        final first = TextEditingController(text: '12.50');
        final focus = FocusNode();
        addTearDown(first.dispose);
        addTearDown(focus.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            builder: (_, child) => AppKeyboardDismissRegion(child: child!),
            home: Scaffold(
              body: Column(
                children: [
                  TextField(
                    key: const ValueKey('first'),
                    focusNode: focus,
                    controller: first,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const TextField(key: ValueKey('second')),
                  TextFieldTapRegion(
                    child: TextButton(
                      onPressed: () {
                        first.text = '15.50';
                      },
                      child: const Text('editor control'),
                    ),
                  ),
                  const Expanded(
                    child: ColoredBox(
                      key: ValueKey('outside'),
                      color: Colors.white,
                      child: SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.tap(
          find.byKey(const ValueKey('first')),
          kind: PointerDeviceKind.touch,
        );
        await tester.pump();
        expect(focus.hasFocus, isTrue);
        await tester.tap(
          find.text('editor control'),
          kind: PointerDeviceKind.touch,
        );
        await tester.pump();
        expect(
          focus.hasFocus,
          isTrue,
          reason: 'editor-owned controls must retain focus',
        );
        await tester.tap(
          find.byKey(const ValueKey('second')),
          kind: PointerDeviceKind.touch,
        );
        await tester.pump();
        expect(tester.testTextInput.isVisible, isTrue);
        await tester.tap(
          find.byKey(const ValueKey('outside')),
          kind: PointerDeviceKind.touch,
        );
        await tester.pump();
        expect(tester.testTextInput.isVisible, isFalse);
        expect(first.text, '15.50');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Scaffold consumes IME without phantom bottom navigation gap on $platform',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.reset);
        double? height, inset, obstruction;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            builder: (_, child) => AppKeyboardDismissRegion(child: child!),
            home: Scaffold(
              resizeToAvoidBottomInset: true,
              body: Builder(
                builder: (context) {
                  inset = MediaQuery.viewInsetsOf(context).bottom;
                  obstruction = AppLayout.bottomBarObstruction(context);
                  return LayoutBuilder(
                    builder: (_, constraints) {
                      height = constraints.maxHeight;
                      return const TextField();
                    },
                  );
                },
              ),
            ),
          ),
        );
        expect(obstruction, greaterThan(0));
        tester.view.viewInsets = const FakeViewPadding(bottom: 320);
        await tester.pumpAndSettle();
        expect(height, 524);
        expect(inset, 0);
        expect(obstruction, 0);
        tester.view.viewInsets = const FakeViewPadding();
        await tester.pumpAndSettle();
        expect(height, 844);
        expect(obstruction, greaterThan(0));
      },
    );
  }
}
