import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/ui/sheet_handle.dart';

Future<void> loadKeyboardAcceptanceFonts() async {
  await (FontLoader('Gilroy')
        ..addFont(rootBundle.load('assets/fonts/gilroy/Gilroy-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/gilroy/Gilroy-Bold.ttf'))
        ..addFont(rootBundle.load('assets/fonts/gilroy/Gilroy-Black.ttf')))
      .load();
}

/// Measures the actual editing caret before any test-driven recovery scroll.
/// Hit testing also detects a caret covered by a pinned header or footer.
Rect expectFocusedCaretAboveIme(
  WidgetTester tester,
  Finder field, {
  double? keyboardTop,
}) {
  final visibleBottom =
      keyboardTop ??
      (tester.view.physicalSize.height - tester.view.viewInsets.bottom) /
          tester.view.devicePixelRatio;
  final state = tester.state<EditableTextState>(field);
  final render = state.renderEditable;
  final selection = state.widget.controller.selection;
  final position = selection.isValid
      ? selection.extent
      : TextPosition(offset: state.widget.controller.text.length);
  final local = render.getLocalRectForCaret(position);
  final caret = Rect.fromPoints(
    render.localToGlobal(local.topLeft),
    render.localToGlobal(local.bottomRight),
  );
  expect(state.widget.focusNode.hasFocus, isTrue);
  expect(
    caret.top,
    greaterThanOrEqualTo(0),
    reason: 'automatic caret must be on screen: $caret',
  );
  expect(
    caret.bottom,
    lessThanOrEqualTo(visibleBottom),
    reason: 'automatic caret must be above IME: $caret',
  );
  expect(
    tester
        .hitTestOnBinding(caret.center)
        .path
        .any((entry) => identical(entry.target, render)),
    isTrue,
    reason: 'automatic caret must not be clipped by pinned surfaces: $caret',
  );
  return caret;
}

/// Exercises every mounted editor on the current route, including numeric and
/// multiline fields below the initial viewport. No field values are changed.
Future<int> exerciseCurrentRouteEditors(WidgetTester tester) async {
  final controllers = find
      .byType(EditableText)
      .evaluate()
      .where(
        (element) =>
            ModalRoute.of(element)?.isCurrent == true &&
            !(element.widget as EditableText).readOnly,
      )
      .map((element) => (element.widget as EditableText).controller)
      .toSet()
      .toList();
  expect(controllers, isNotEmpty);
  for (final controller in controllers) {
    final field = find.byWidgetPredicate(
      (widget) =>
          widget is EditableText && identical(widget.controller, controller),
    );
    await tester.ensureVisible(field);
    await tester.pump();
    await tester.tap(field);
    await tester.pump();
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expectFocusedCaretAboveIme(tester, field);
    final handles = find.byType(SheetHandle).hitTestable();
    if (handles.evaluate().isNotEmpty) {
      await tester.tap(handles.last);
      await tester.pump();
    } else {
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isFalse);
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump(const Duration(milliseconds: 350));
  }
  return controllers.length;
}
