import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/foundation.dart';
import '../../helpers/keyboard_acceptance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/ui/blurred_modal_bottom_sheet.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/clients/domain/client_codes_state.dart';
import 'package:twoalogisticcabineuser/src/features/clients/presentation/client_switcher_sheet.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/data/tracks_provider.dart';
import 'package:twoalogisticcabineuser/src/features/assemblies/data/assemblies_provider.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/data/invoices_provider.dart';

class _Codes extends ClientCodesController {
  _Codes(this.initial);
  final ClientCodesState initial;
  final selected = <String>[];
  String? get active => state.asData?.value.activeCode;
  @override
  Future<ClientCodesState> build() async => initial;
  @override
  Future<void> selectClient(String code) async {
    selected.add(code);
    state = AsyncData(state.requireValue.copyWith(activeCode: code));
  }
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

Future<_Codes> _openKineticSelector(
  WidgetTester tester,
  TargetPlatform platform,
) async {
  final codes = _Codes(
    ClientCodesState(
      codes: List.generate(
        13,
        (index) => 'A-${(index + 1).toString().padLeft(3, '0')}',
      ),
      activeCode: 'A-001',
    ),
  );
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clientCodesControllerProvider.overrideWith(() => codes),
        tracksCountProvider.overrideWith((ref, code) async => 0),
        assembliesCountProvider.overrideWith((ref, code) async => 0),
        invoicesCountProvider.overrideWith((ref, code) async => 0),
      ],
      child: MaterialApp(
        theme: ThemeData(fontFamily: 'Gilroy', platform: platform),
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showBlurredModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const ClientSwitcherSheet(),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await _frames(tester);
  await _frames(tester);
  return codes;
}

Offset _bottomVisibleCodeRow(WidgetTester tester) {
  final list = find.byType(SingleChildScrollView);
  expect(list, findsOneWidget);
  final scrollable = find.descendant(
    of: list,
    matching: find.byType(Scrollable),
  );
  final position = tester.state<ScrollableState>(scrollable).position;
  expect(position.pixels, position.minScrollExtent);
  expect(position.maxScrollExtent, greaterThan(0));
  final viewport = tester.getRect(list);
  final targetY = viewport.bottom - 45;
  final cards = find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == '_ClientCodeOptionCard',
  );
  final visibleRows = cards
      .evaluate()
      .map((element) => tester.getRect(find.byWidget(element.widget)))
      .where(
        (rect) => rect.overlaps(viewport) && rect.top < viewport.bottom - 10,
      )
      .toList();
  final row = visibleRows.lastWhere(
    (rect) => rect.top <= targetY,
    orElse: () => visibleRows.first,
  );
  final start = Offset(
    viewport.center.dx,
    targetY.clamp(row.top + 10, row.bottom - 10),
  );
  expect(row.contains(start), isTrue);
  expect(viewport.contains(start), isTrue);
  expect(viewport.bottom - start.dy, lessThanOrEqualTo(80));
  return start;
}

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final held in [false, true]) {
      testWidgets(
        'actual 13-code selector ${held ? 'held short pull springs back' : 'short bottom flick closes'} $platform',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          try {
            final codes = await _openKineticSelector(tester, platform);
            final before = tester.getRect(find.byType(ClientSwitcherSheet));
            final start = _bottomVisibleCodeRow(tester);
            final gesture = await tester.createGesture(
              kind: PointerDeviceKind.touch,
            );
            await gesture.down(start, timeStamp: Duration.zero);
            await gesture.moveBy(
              Offset(0, held ? 20 : 35),
              timeStamp: const Duration(milliseconds: 20),
            );
            await tester.pump(const Duration(milliseconds: 20));
            final pulled = tester.getRect(find.byType(ClientSwitcherSheet));
            expect(pulled.top, greaterThan(before.top));
            if (held) {
              await tester.pump(const Duration(milliseconds: 200));
              await gesture.up(timeStamp: const Duration(milliseconds: 220));
              await tester.pump();
              expect(find.byType(ClientSwitcherSheet), findsOneWidget);
              expect(
                tester.getRect(find.byType(ClientSwitcherSheet)).top,
                greaterThan(before.top),
              );
              await tester.pump(const Duration(milliseconds: 40));
              final settling = tester.getRect(find.byType(ClientSwitcherSheet));
              expect(settling.top, greaterThan(before.top));
              expect(settling.top, lessThan(pulled.top));
              await _frames(tester);
              await _frames(tester);
              expect(
                tester.getRect(find.byType(ClientSwitcherSheet)).top,
                closeTo(before.top, 0.5),
              );
            } else {
              await gesture.up(timeStamp: const Duration(milliseconds: 21));
              await _frames(tester);
              expect(find.byType(ClientSwitcherSheet), findsNothing);
            }
            expect(
              codes.selected,
              isEmpty,
              reason: 'a drag must not select a code',
            );
            expect(codes.active, 'A-001');
            expect(tester.takeException(), isNull);
          } finally {
            debugDefaultTargetPlatformOverride = null;
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump(const Duration(seconds: 10));
          }
        },
      );
    }
  }

  for (final language in ['ru', 'zh']) {
    for (final empty in [false, true]) {
      testWidgets(
        'switcher only selects assigned codes $language empty=$empty',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final codes = _Codes(
            ClientCodesState(
              codes: empty ? [] : ['A-001', 'A-002'],
              activeCode: empty ? null : 'A-001',
            ),
          );
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                clientCodesControllerProvider.overrideWith(() => codes),
                tracksCountProvider.overrideWith((ref, code) async => 0),
                assembliesCountProvider.overrideWith((ref, code) async => 0),
                invoicesCountProvider.overrideWith((ref, code) async => 0),
              ],
              child: MaterialApp(
                theme: ThemeData(fontFamily: 'Gilroy'),
                locale: Locale(language),
                supportedLocales: const [Locale('ru'), Locale('zh')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => showBlurredModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => const ClientSwitcherSheet(),
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await _frames(tester);
          await _frames(tester);
          expect(find.text('Привязать код по PIN'), findsNothing);
          expect(find.text('使用 PIN 关联客户代码'), findsNothing);
          expect(find.text('Доступные коды'), findsNothing);
          expect(find.byType(TextField), findsNothing);
          if (empty) {
            expect(find.text('Коды клиента пока не найдены'), findsOneWidget);
            expect(codes.selected, isEmpty);
          } else {
            expect(find.text('A-001'), findsWidgets);
            expect(find.text('A-002'), findsOneWidget);
            await tester.tap(find.text('A-002'));
            await _frames(tester);
            expect(codes.selected, ['A-002']);
            expect(codes.active, 'A-002');
            expect(find.byType(ClientSwitcherSheet), findsNothing);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 10));
        },
      );
    }
  }
}
