import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../../helpers/keyboard_acceptance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/app/theme/app_theme.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_colors.dart';
import 'package:twoalogisticcabineuser/src/features/photos/presentation/photo_date_sheet.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/presentation/widgets/track_sheet_surface.dart';

void main() {
  setUpAll(() async {
    await loadKeyboardAcceptanceFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final size in [const Size(320, 568), const Size(390, 844)]) {
    for (final apply in [true, false]) {
      testWidgets('branded date sheet ${size.width} apply=$apply', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        t.view.padding = const FakeViewPadding(top: 59, bottom: 34);
        t.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
        addTearDown(t.view.reset);
        DateTime? result;
        await t.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightWithColors(
              BrandColors.fromHex('#F2783C', '#F79345'),
            ),
            builder: (_, child) => RepaintBoundary(
              key: const ValueKey('date-sheet-render'),
              child: ProviderScope(child: child!),
            ),
            locale: const Locale('ru'),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('ru')],
            home: Builder(
              builder: (context) => Scaffold(
                backgroundColor: AppColors.brandBg,
                body: TextButton(
                  onPressed: () async {
                    result = await showPhotoDateSheet(
                      context: context,
                      firstDate: DateTime(2015),
                      lastDate: DateTime(2026, 11, 30),
                      initialDate: DateTime(2026, 11, 10),
                    );
                  },
                  child: const Text('Открыть'),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('Открыть'));
        await t.pumpAndSettle();
        expect(find.byType(DatePickerDialog), findsNothing);
        if (size.width == 390 && apply) {
          await t.runAsync(() async {
            final boundary = t.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('date-sheet-render')),
            );
            final picture = await boundary.toImage(pixelRatio: 1);
            final bytes = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              '../outputs/2026-11-10-ui-followup/photo-date-sheet-390.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            picture.dispose();
          });
        }

        final surface = t.widget<TrackSheetSurface>(
          find.byType(TrackSheetSurface),
        );
        expect(surface.title, 'Выбор даты');
        expect(surface.icon, Icons.calendar_month_rounded);
        final theme = t.widget<DatePickerTheme>(find.byType(DatePickerTheme));
        expect(theme.data.backgroundColor, Colors.white);
        expect(theme.data.surfaceTintColor, Colors.transparent);
        final context = t.element(find.byType(CalendarDatePicker));
        expect(
          theme.data.dayBackgroundColor!.resolve({WidgetState.selected}),
          context.brandPrimary,
        );
        final calendar = find.byType(CalendarDatePicker);
        await t.ensureVisible(calendar);
        await t.pumpAndSettle();
        final day = find.text('15').last;
        await t.ensureVisible(day);
        await t.pumpAndSettle();
        await t.tap(day);
        await t.pumpAndSettle();
        final action = find.text(apply ? 'Применить' : 'Отмена');
        expect(t.getRect(action).bottom, lessThanOrEqualTo(size.height - 34));
        await t.tap(action);
        await t.pumpAndSettle();
        expect(result, apply ? DateTime(2026, 11, 15) : isNull);
        expect(find.byType(PhotoDateSheet), findsNothing);
        expect(t.takeException(), isNull);
      });
    }
  }
}
