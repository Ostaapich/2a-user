import '../../helpers/keyboard_acceptance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:twoalogisticcabineuser/src/core/ui/blurred_modal_bottom_sheet.dart';
import 'package:twoalogisticcabineuser/src/core/ui/sheet_handle.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/domain/photo_report_options.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/presentation/widgets/photo_report_selection_sheet.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/presentation/widgets/track_sheet_surface.dart';

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final width in [320.0, 390.0]) {
      testWidgets(
        'actual custom photo sheet focus/IME/dismiss ${platform.name} $width',
        (t) async {
          t.view.devicePixelRatio = 1;
          t.view.physicalSize = Size(width, 844);
          addTearDown(t.view.resetDevicePixelRatio);
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetViewInsets);
          await t.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: ThemeData(fontFamily: 'Gilroy', platform: platform),
                locale: const Locale('ru'),
                supportedLocales: const [Locale('ru')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                builder: (context, child) =>
                    AppKeyboardDismissRegion(child: child!),
                home: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => showBlurredModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => PhotoReportSelectionSheet(
                          trackNumber: 'TEST-001',
                          initialType: 'custom',
                          initialWish: 'Проверить размер',
                          loadOptions: () async => PhotoReportOptions.fromJson({
                            'standard': {'enabled': true, 'priceUsd': '0.00'},
                            'custom': {'enabled': true, 'priceUsd': '5.00'},
                          }),
                        ),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.tap(find.text('open'));
          await t.pumpAndSettle();
          final field = find.byType(TextField);
          await t.ensureVisible(field);
          await t.tap(field);
          await t.pump();
          final editable = find.descendant(
            of: field,
            matching: find.byType(EditableText),
          );
          expect(t.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
          t.view.viewInsets = const FakeViewPadding(bottom: 320);
          await t.pumpAndSettle();
          expectFocusedCaretAboveIme(t, editable);
          final footer = t.getRect(find.byType(TrackSheetPrimaryButton));
          expect(footer.bottom, lessThanOrEqualTo(524));
          expect(footer.top, greaterThan(0));
          expect(
            MediaQuery.viewInsetsOf(t.element(field)).bottom,
            0,
            reason: 'shared route consumes IME exactly once',
          );
          final handle = find.byType(SheetHandle);
          expect(handle.hitTestable(), findsOneWidget);
          final handleY = t.getRect(handle).top;
          expect(handleY, greaterThanOrEqualTo(50));
          await t.tap(handle);
          await t.pump();
          expect(t.widget<EditableText>(editable).focusNode.hasFocus, isFalse);
          await t.drag(handle, const Offset(0, 170));
          await t.pumpAndSettle();
          expect(find.byType(PhotoReportSelectionSheet), findsNothing);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
