import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/keyboard_acceptance.dart';

Finder _routeScroll() => find.byElementPredicate(
  (element) =>
      element.widget is Scrollable &&
      ModalRoute.of(element)?.isCurrent == true &&
      (element.widget as Scrollable).axisDirection == AxisDirection.down,
);

/// Enumerates lazy fields with the keyboard closed, then measures automatic
/// caret movement for each field. No recovery scroll occurs after IME opens.
Future<int> probeCurrentFormEditors(
  WidgetTester tester, {
  int minimumFields = 1,
  double keyboardInset = 320,
}) async {
  tester.view.viewInsets = FakeViewPadding.zero;
  await tester.pump(const Duration(milliseconds: 400));
  final offsets = <TextEditingController, double>{};
  ScrollableState? outer() => _routeScroll().evaluate().isEmpty
      ? null
      : tester.state<ScrollableState>(_routeScroll().first);
  final initial = outer();
  if (initial != null && initial.position.hasContentDimensions) {
    initial.position.jumpTo(0);
  }
  await tester.pump(const Duration(milliseconds: 400));
  for (var step = 0; step < 100; step++) {
    final scroll = outer();
    final offset = scroll?.position.pixels ?? 0;
    for (final element in find.byType(EditableText).evaluate()) {
      final editor = element.widget as EditableText;
      if (ModalRoute.of(element)?.isCurrent == true && !editor.readOnly) {
        offsets.putIfAbsent(editor.controller, () => offset);
      }
    }
    if (scroll == null ||
        scroll.position.pixels >= scroll.position.maxScrollExtent - 1) {
      break;
    }
    scroll.position.jumpTo(
      (offset + 90).clamp(0, scroll.position.maxScrollExtent),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }
  expect(offsets.length, greaterThanOrEqualTo(minimumFields));
  for (final entry in offsets.entries) {
    final scroll = outer();
    if (scroll != null) {
      scroll.position.jumpTo(
        entry.value.clamp(0, scroll.position.maxScrollExtent),
      );
    }
    await tester.pump(const Duration(milliseconds: 400));
    final target = find.byWidgetPredicate(
      (widget) =>
          widget is EditableText && identical(widget.controller, entry.key),
    );
    expect(target, findsOneWidget);
    await tester.ensureVisible(target);
    await tester.pump(const Duration(milliseconds: 400));
    final editor = tester.widget<EditableText>(target);
    await tester.tap(target);
    await tester.pump();
    expect(editor.focusNode.hasFocus, isTrue);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final imeTop =
        tester.view.physicalSize.height / tester.view.devicePixelRatio -
        tester.view.viewInsets.bottom / tester.view.devicePixelRatio;
    expectFocusedCaretAboveIme(tester, target, keyboardTop: imeTop);
    expect(tester.takeException(), isNull);
    editor.focusNode.unfocus();
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump(const Duration(milliseconds: 400));
  }
  return offsets.length;
}
