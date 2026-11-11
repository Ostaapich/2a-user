import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/ui/sheet_handle.dart';
import 'keyboard_acceptance.dart';

/// Types through the actual editor, checks automatic caret handling, and
/// dismisses only the keyboard. It never submits the enclosing business form.
Future<void> typeDraftThroughIme(
  WidgetTester tester,
  TextEditingController controller,
  String text, {
  bool numericFormatting = false,
}) async {
  final editor = find.byWidgetPredicate(
    (widget) =>
        widget is EditableText && identical(widget.controller, controller),
  );
  if (editor.hitTestable().evaluate().isEmpty) {
    await tester.ensureVisible(editor);
    await tester.pump();
  }
  await tester.tap(editor);
  await tester.enterText(editor, text);
  await tester.pump();
  final focus = tester.widget<EditableText>(editor).focusNode;
  expect(focus.hasFocus, isTrue);
  final retainedText = controller.text;
  if (numericFormatting) {
    expect(
      retainedText.replaceAll(RegExp(r'\D'), ''),
      text.replaceAll(RegExp(r'\D'), ''),
    );
  } else {
    expect(retainedText, text);
  }
  tester.view.viewInsets = const FakeViewPadding(bottom: 320);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  expectFocusedCaretAboveIme(tester, editor);
  expect(tester.widget<EditableText>(editor).focusNode, same(focus));
  expect(controller.text, retainedText);
  final handles = find.byType(SheetHandle).hitTestable();
  expect(handles, findsWidgets);
  await tester.tap(handles.last);
  await tester.pump();
  expect(focus.hasFocus, isFalse);
  tester.view.viewInsets = FakeViewPadding.zero;
  await tester.pump(const Duration(milliseconds: 350));
  expect(controller.text, retainedText);
  expect(tester.widget<EditableText>(editor).focusNode, same(focus));
}
