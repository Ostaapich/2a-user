import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:twoalogisticcabineuser/src/features/calculator/domain/calculator_cargo_places.dart';
import 'package:twoalogisticcabineuser/src/features/calculator/presentation/calculator_cargo_places_editor.dart';
import '../../helpers/keyboard_acceptance.dart';

Finder field(int id, String part) =>
    find.byKey(ValueKey('cargo-place-$id-$part'));
Future<void> host(
  WidgetTester tester,
  List<CargoPlacesTotals?> events, {
  double width = 390,
  TargetPlatform platform = TargetPlatform.android,
  Locale locale = const Locale('ru'),
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ru'), Locale('zh')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(platform: platform),
      builder: (context, child) => AppKeyboardDismissRegion(
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: CalculatorCargoPlacesEditor(onChanged: events.add),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> edit(
  WidgetTester tester,
  int id,
  String part,
  String value,
) async {
  await tester.ensureVisible(field(id, part));
  await tester.pump();
  await tester.enterText(field(id, part), value);
  await tester.pump();
}

Future<void> tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.pump();
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  testWidgets(
    'no build callback, all fields required, comma decimals and invalid paste never partially aggregate',
    (tester) async {
      final events = <CargoPlacesTotals?>[];
      await host(tester, events);
      expect(events, isEmpty);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('cargo-place-remove-0')),
            )
            .onPressed,
        isNull,
      );
      for (final part in ['length', 'width', 'height']) {
        await edit(tester, 0, part, '10');
        expect(events.last, isNull);
      }
      await edit(tester, 0, 'weight', '2,5');
      expect(events.last!.weightKg, 2.5);
      expect(events.last!.volumeM3, .001);
      for (final value in ['-2', '0', '1,2,3', '1e309', '']) {
        await edit(tester, 0, 'weight', value);
        expect(events.last, isNull, reason: value);
      }
      await edit(tester, 0, 'weight', '2.5');
      expect(events.last!.weightKg, 2.5);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'add invalid row then remove preserves valid row and new IDs never reuse removed controllers',
    (tester) async {
      final events = <CargoPlacesTotals?>[];
      await host(tester, events);
      for (final entry in {
        'length': '100',
        'width': '40',
        'height': '30',
        'weight': '6',
      }.entries) {
        await edit(tester, 0, entry.key, entry.value);
      }
      final original = tester.widget<TextField>(field(0, 'length')).controller;
      await tap(tester, 'cargo-place-add');
      expect(events.last, isNull);
      expect(field(1, 'length'), findsOneWidget);
      await edit(tester, 1, 'length', '20');
      await tap(tester, 'cargo-place-remove-1');
      expect(field(1, 'length'), findsNothing);
      expect(events.last!.placesCount, 1);
      expect(events.last!.weightKg, 6);
      expect(
        tester.widget<TextField>(field(0, 'length')).controller,
        same(original),
      );
      expect(original!.text, '100');
      await tap(tester, 'cargo-place-add');
      expect(field(2, 'length'), findsOneWidget);
      expect(field(1, 'length'), findsNothing);
      for (final entry in {
        'length': '20',
        'width': '20',
        'height': '10',
        'weight': '4',
      }.entries) {
        await edit(tester, 2, entry.key, entry.value);
      }
      expect(events.last!.placesCount, 2);
      expect(events.last!.weightKg, 10);
      expect(events.last!.volumeM3, closeTo(.124, 1e-12));
      await tap(tester, 'cargo-place-remove-0');
      expect(events.last!.weightKg, 4);
      expect(events.last!.placesCount, 1);
      expect(
        tester.widget<TextField>(field(2, 'length')).controller!.text,
        '20',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'removing focused row then disposing parent before cleanup frame is safe',
    (tester) async {
      final events = <CargoPlacesTotals?>[];
      await host(tester, events);
      await tap(tester, 'cargo-place-add');
      await edit(tester, 1, 'weight', '4');
      final remove = find.byKey(const ValueKey('cargo-place-remove-1'));
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final width in [320.0, 390.0]) {
      for (final locale in [const Locale('ru'), const Locale('zh')]) {
        testWidgets(
          'two-column cargo fields fit $width $platform $locale largefont with automatic IME caret',
          (tester) async {
            final events = <CargoPlacesTotals?>[];
            await host(
              tester,
              events,
              width: width,
              platform: platform,
              locale: locale,
              scale: 1.6,
            );
            for (final part in ['length', 'width', 'height', 'weight']) {
              await edit(tester, 0, part, '11,5');
            }
            await tap(tester, 'cargo-place-add');
            for (final part in ['length', 'width', 'height', 'weight']) {
              await tester.ensureVisible(field(1, part));
              await tester.pump();
              await tester.tap(field(1, part));
              await tester.pump();
              tester.view.viewInsets = const FakeViewPadding(bottom: 320);
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 350));
              final editable = find.descendant(
                of: field(1, part),
                matching: find.byType(EditableText),
              );
              expectFocusedCaretAboveIme(tester, editable);
              await tester.enterText(field(1, part), '11,5');
              await tester.pump();
              expectFocusedCaretAboveIme(tester, editable);
              await tester.tapAt(Offset(width - 4, 50));
              await tester.pump();
              expect(
                tester.widget<EditableText>(editable).focusNode.hasFocus,
                isFalse,
              );
              tester.view.viewInsets = const FakeViewPadding();
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 350));
              expect(
                tester.widget<TextField>(field(1, part)).controller!.text,
                '11,5',
              );
              expect(tester.takeException(), isNull);
            }
            expect(events.last!.weightKg, 23);
            expect(events.last!.placesCount, 2);
            await tap(tester, 'cargo-place-add');
            expect(events.last, isNull);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
