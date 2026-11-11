import 'dart:ui' show PointerDeviceKind;
import '../../helpers/keyboard_acceptance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:twoalogisticcabineuser/src/core/ui/blurred_modal_bottom_sheet.dart';

const _parentKey = ValueKey('parent-editor');
const _modalKey = ValueKey('modal-editor');
const _handleKey = ValueKey('modal-handle');
const _blankKey = ValueKey('modal-blank');
const _nextKey = ValueKey('next-route-editor');

class _Fixture extends StatelessWidget {
  const _Fixture({
    required this.parentFocus,
    required this.modalFocus,
    this.blockPop = false,
    this.openNext = false,
  });
  final bool blockPop, openNext;
  final FocusNode parentFocus, modalFocus;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        TextField(key: _parentKey, focusNode: parentFocus),
        TextFieldTapRegion(
          child: TextButton(
            onPressed: () async {
              await showBlurredModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (sheetContext) => PopScope(
                  canPop: !blockPop,
                  child: SizedBox(
                    height: 300,
                    child: Column(
                      children: [
                        const SizedBox(
                          key: _handleKey,
                          height: 32,
                          width: double.infinity,
                          child: Center(child: Text('handle')),
                        ),
                        TextField(key: _modalKey, focusNode: modalFocus),
                        TextFieldTapRegion(
                          child: TextButton(
                            onPressed: () {},
                            child: const Text('editor-owned control'),
                          ),
                        ),
                        if (blockPop)
                          TextFieldTapRegion(
                            child: TextButton(
                              onPressed: () =>
                                  Navigator.of(sheetContext).maybePop(),
                              child: const Text('Guarded close'),
                            ),
                          ),
                        const SizedBox(
                          key: _blankKey,
                          height: 64,
                          width: double.infinity,
                          child: ColoredBox(color: Colors.white),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: const Text('Cancel sheet'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
              if (openNext && context.mounted) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: TextField(key: _nextKey, autofocus: true),
                    ),
                  ),
                );
              }
            },
            child: const Text('Open sheet'),
          ),
        ),
      ],
    ),
  );
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

Future<({FocusNode parent, FocusNode modal})> _open(
  WidgetTester tester,
  TargetPlatform platform, {
  bool blockPop = false,
  bool openNext = false,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  final parent = FocusNode(), modal = FocusNode();
  addTearDown(() {
    debugDefaultTargetPlatformOverride = null;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewInsets();
    parent.dispose();
    modal.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Gilroy', platform: platform),
      builder: (_, child) => AppKeyboardDismissRegion(child: child!),
      home: _Fixture(
        parentFocus: parent,
        modalFocus: modal,
        blockPop: blockPop,
        openNext: openNext,
      ),
    ),
  );
  await tester.tap(find.byKey(_parentKey), kind: PointerDeviceKind.touch);
  await _frames(tester);
  expect(parent.hasFocus, true);
  expect(tester.testTextInput.isVisible, true);
  await tester.tap(find.text('Open sheet'), kind: PointerDeviceKind.touch);
  await _frames(tester);
  await tester.tap(find.byKey(_modalKey), kind: PointerDeviceKind.touch);
  await tester.enterText(find.byKey(_modalKey), 'fixture selection');
  await _frames(tester);
  tester.view.viewInsets = const FakeViewPadding(bottom: 320);
  await _frames(tester);
  expect(modal.hasFocus, true);
  expect(tester.testTextInput.isVisible, true);
  return (parent: parent, modal: modal);
}

Future<void> _dispose(WidgetTester tester) async {
  debugDefaultTargetPlatformOverride = null;
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'blocked editor-owned close preserves IME and draft ${platform.name}',
      (tester) async {
        final focus = await _open(tester, platform, blockPop: true);
        final hideCount = tester.testTextInput.log
            .where((call) => call.method == 'TextInput.hide')
            .length;
        await tester.tap(
          find.text('Guarded close'),
          kind: PointerDeviceKind.touch,
        );
        await _frames(tester);
        expect(find.byKey(_modalKey), findsOneWidget);
        expect(focus.modal.hasFocus, true);
        expect(tester.testTextInput.isVisible, true);
        expect(
          tester.testTextInput.log
              .where((call) => call.method == 'TextInput.hide')
              .length,
          hideCount,
          reason: 'blocked maybePop must not issue a native hide',
        );
        final editable = find.descendant(
          of: find.byKey(_modalKey),
          matching: find.byType(EditableText),
        );
        expect(
          tester.widget<EditableText>(editable).controller.text,
          'fixture selection',
        );
        await _dispose(tester);
      },
    );
    testWidgets(
      'new route editor has no trailing hide after modal pop ${platform.name}',
      (tester) async {
        await _open(tester, platform, openNext: true);
        await tester.tap(
          find.text('Cancel sheet'),
          kind: PointerDeviceKind.touch,
        );
        await _frames(tester);
        expect(find.byKey(_nextKey), findsOneWidget);
        final editor = find.descendant(
          of: find.byKey(_nextKey),
          matching: find.byType(EditableText),
        );
        expect(tester.widget<EditableText>(editor).focusNode.hasFocus, true);
        expect(tester.testTextInput.isVisible, true);
        final hideCount = tester.testTextInput.log
            .where((call) => call.method == 'TextInput.hide')
            .length;
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(tester.widget<EditableText>(editor).focusNode.hasFocus, true);
        expect(tester.testTextInput.isVisible, true);
        expect(
          tester.testTextInput.log
              .where((call) => call.method == 'TextInput.hide')
              .length,
          hideCount,
          reason: 'old modal completion must not hide the new route keyboard',
        );
        final calls = tester.testTextInput.log
            .map((call) => call.method)
            .toList();
        expect(
          calls.lastIndexOf('TextInput.show'),
          greaterThan(calls.lastIndexOf('TextInput.hide')),
        );
        await _dispose(tester);
      },
    );
    for (final close in ['swipe', 'cancel', 'barrier']) {
      testWidgets(
        'pop $close must not restore underlying editor IME ${platform.name}',
        (tester) async {
          final focus = await _open(tester, platform);
          if (close == 'swipe') {
            await tester.drag(find.byKey(_handleKey), const Offset(0, 220));
          } else if (close == 'cancel') {
            await tester.tap(
              find.text('Cancel sheet'),
              kind: PointerDeviceKind.touch,
            );
          } else {
            await tester.tapAt(
              const Offset(20, 100),
              kind: PointerDeviceKind.touch,
            );
          }
          await _frames(tester);
          expect(find.byKey(_modalKey), findsNothing);
          expect(
            focus.parent.hasFocus,
            false,
            reason: 'parent editor must not regain focus after dismissal',
          );
          expect(focus.modal.hasFocus, false);
          expect(
            tester.testTextInput.isVisible,
            false,
            reason:
                'dismissed sheet must close IME without reopening parent editor',
          );
          await _dispose(tester);
        },
      );
    }
    testWidgets(
      'sheet blank unfocuses but editor-owned control retains focus ${platform.name}',
      (tester) async {
        final focus = await _open(tester, platform);
        await tester.tap(
          find.text('editor-owned control'),
          kind: PointerDeviceKind.touch,
        );
        await _frames(tester);
        expect(focus.modal.hasFocus, true);
        await tester.tap(find.byKey(_blankKey), kind: PointerDeviceKind.touch);
        await _frames(tester);
        expect(focus.modal.hasFocus, false);
        expect(tester.testTextInput.isVisible, false);
        expect(find.byKey(_modalKey), findsOneWidget);
        await _dispose(tester);
      },
    );
    testWidgets(
      'selection toolbar does not consume sheet blank dismissal ${platform.name}',
      (tester) async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.hasStrings') return {'value': true};
            if (call.method == 'Clipboard.getData') {
              return {'text': 'fixture paste'};
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final focus = await _open(tester, platform);
        final editor = find.descendant(
          of: find.byKey(_modalKey),
          matching: find.byType(EditableText),
        );
        final state = tester.state<EditableTextState>(editor);
        state.widget.controller.selection = const TextSelection(
          baseOffset: 0,
          extentOffset: 7,
        );
        await _frames(tester);
        expect(state.showToolbar(), true);
        await _frames(tester);
        expect(find.text('Paste'), findsWidgets);
        await tester.tap(find.byKey(_blankKey), kind: PointerDeviceKind.touch);
        await _frames(tester);
        expect(focus.modal.hasFocus, false);
        expect(tester.testTextInput.isVisible, false);
        expect(find.text('Paste'), findsNothing);
        await _dispose(tester);
      },
    );
  }
}
