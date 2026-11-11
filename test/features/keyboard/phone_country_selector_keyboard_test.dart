import '../../helpers/keyboard_acceptance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_form_field/phone_form_field.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:twoalogisticcabineuser/src/core/ui/phone_input_field.dart';

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'country search caret, outside dismiss, selection and list end ${platform.name}',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        final phone = PhoneController(
          initialValue: const PhoneNumber(
            isoCode: IsoCode.RU,
            nsn: '9991234567',
          ),
        );
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetViewInsets();
          phone.dispose();
        });
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: ThemeData(fontFamily: 'Gilroy'),
              builder: (_, child) => AppKeyboardDismissRegion(child: child!),
              home: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: PhoneInputField(controller: phone),
                  ),
                ),
              ),
            ),
          ),
        );
        await _frames(tester);
        await tester.tap(find.byType(CountryButton));
        await _frames(tester);
        expect(find.byType(DraggableScrollableSheet), findsOneWidget);
        final search = find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.hintText == 'Поиск страны',
        );
        expect(search, findsOneWidget);
        await tester.tap(search);
        // Two characters keep the package's country-autofill shortcut inactive;
        // actual row selection is tested separately below.
        await tester.enterText(search, 'Ch');
        await _frames(tester);
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await _frames(tester);
        final editor = find.descendant(
          of: search,
          matching: find.byType(EditableText),
        );
        expectFocusedCaretAboveIme(tester, editor, keyboardTop: 360);
        final sheet = tester.getRect(find.byType(DraggableScrollableSheet));
        await tester.tapAt(Offset(sheet.center.dx, sheet.top + 8));
        await _frames(tester);
        expect(tester.widget<EditableText>(editor).focusNode.hasFocus, isFalse);
        expect(tester.widget<EditableText>(editor).controller.text, 'Ch');
        tester.view.resetViewInsets();
        await _frames(tester);
        final china = find.byKey(const ValueKey('CN')).first;
        await tester.ensureVisible(china);
        await _frames(tester);
        await tester.tap(china);
        await _frames(tester);
        expect(phone.value.isoCode, IsoCode.CN);
        expect(phone.value.nsn, '9991234567');
        expect(find.byType(DraggableScrollableSheet), findsNothing);

        await tester.tap(find.byType(CountryButton));
        await _frames(tester);
        final lastCountry = find.byKey(const ValueKey('ZW'));
        final scrollable = find
            .descendant(
              of: find.byType(DraggableScrollableSheet),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              ),
            )
            .first;
        await tester.scrollUntilVisible(
          lastCountry,
          500,
          scrollable: scrollable,
          maxScrolls: 100,
        );
        await _frames(tester);
        expect(lastCountry.hitTestable(), findsOneWidget);
        expect(tester.getRect(lastCountry).bottom, lessThanOrEqualTo(640));
        await tester.tap(lastCountry);
        await _frames(tester);
        expect(phone.value.isoCode, IsoCode.ZW);
        expect(phone.value.nsn, '9991234567');
        expect(find.byType(DraggableScrollableSheet), findsNothing);
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
