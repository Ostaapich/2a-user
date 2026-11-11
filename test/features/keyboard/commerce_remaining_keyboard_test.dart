import 'package:twoalogisticcabineuser/src/features/tracks/presentation/widgets/track_sheet_surface.dart';
import 'package:dio/dio.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import '../../helpers/keyboard_acceptance.dart';
import '../../helpers/keyboard_draft_acceptance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/data/tracks_provider.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/domain/track_item.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/presentation/tracks_screen.dart';

class _NoNetworkApi extends ApiClient {
  @override
  Future<String?> getToken() async => null;
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async => throw StateError('Unexpected fixture read: $path');
  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async => throw StateError('Unexpected fixture mutation: $path');
}

class _ReadOnlyTrackService extends TracksApiService {
  _ReadOnlyTrackService(super.ref);
  @override
  Future<TrackReturnInfo?> getTrackReturn(int trackId) async => null;
}

Future<void> _pumpTrack(
  WidgetTester tester,
  TargetPlatform platform, {
  TrackAssembly? assembly,
  bool orphan = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewInsets);
  final now = DateTime(2026, 11, 10);
  final track = TrackItem(
    id: 42,
    code: 'GAP-TRACK',
    status: orphan ? 'В ожидании' : 'На складе',
    statusCode: orphan ? 'pending' : 'in_warehouse',
    date: now,
    createdAt: now,
    updatedAt: now,
    groupId: assembly?.id.toString(),
    assembly: assembly,
  );
  final tracks = [
    track,
    if (orphan)
      TrackItem(
        id: 44,
        code: 'GAP-OTHER',
        status: 'В ожидании',
        statusCode: 'pending',
        date: now,
        createdAt: now,
        updatedAt: now,
      ),
  ];
  final embedded = TracksScreen.embedded(
    tracks: tracks,
    asAssembly: assembly != null,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(_NoNetworkApi()),
        activeClientCodeProvider.overrideWithValue('2A-TEST'),
        trackStatusesProvider.overrideWith((ref) async => const []),
        assemblyStatusesProvider.overrideWith((ref) async => const []),
        tracksApiServiceProvider.overrideWith(_ReadOnlyTrackService.new),
      ],
      child: MaterialApp(
        theme: ThemeData(fontFamily: 'Gilroy', platform: platform),
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => AppKeyboardDismissRegion(child: child!),
        home: Scaffold(
          body: orphan ? SingleChildScrollView(child: embedded) : embedded,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openAction(WidgetTester tester, String label) async {
  final action = find.byKey(ValueKey('client-track-action-$label'));
  expect(action, findsOneWidget);
  await tester.ensureVisible(action);
  await tester.pump();
  await tester.tap(action);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    await loadKeyboardAcceptanceFonts();
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final entry in ['Заметка', 'Возврат', 'О товаре']) {
      testWidgets(
        'actual ${entry == 'О товаре' ? 'orphan unique' : 'separate'} $entry retains every typed draft ${platform.name}',
        (tester) async {
          await _pumpTrack(tester, platform, orphan: entry == 'О товаре');
          if (entry == 'О товаре') {
            final action = find
                .descendant(
                  of: find.byWidgetPredicate(
                    (widget) =>
                        widget.runtimeType.toString() == '_ActionChipButton',
                  ),
                  matching: find.text(entry),
                )
                .first;
            await tester.ensureVisible(action);
            await tester.tap(action);
            await tester.pumpAndSettle();
          } else {
            await _openAction(tester, entry);
          }
          final editors = tester
              .widgetList<EditableText>(find.byType(EditableText))
              .toList();
          expect(editors.length, entry == 'О товаре' ? 2 : 1);
          for (var index = 0; index < editors.length; index++) {
            final text = entry == 'О товаре'
                ? (index == 0 ? 'Кроссовки для клиента' : '7')
                : entry == 'Возврат'
                ? 'RETURN-777'
                : 'Размер и цвет\nСохранённая заметка';
            await typeDraftThroughIme(tester, editors[index].controller, text);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
    testWidgets('actual delivery footer symmetric gaps ${platform.name}', (
      tester,
    ) async {
      tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetPadding);
      const assembly = TrackAssembly(
        id: 43,
        number: 'ASM-FOOTER',
        status: 'ready_for_pickup',
        deliveryMethod: 'transport_company',
        recipientName: 'Клиент',
        recipientPhone: '+79991234567',
        recipientCity: 'Москва',
        transportCompanyName: 'СДЭК',
        trackCount: 1,
      );
      await _pumpTrack(tester, platform, assembly: assembly);
      await _openAction(tester, 'Доставка');
      final save = find.text('Сохранить');
      final footer = find
          .ancestor(
            of: save,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Row &&
                  widget.children.length == 3 &&
                  widget.children.first is Expanded &&
                  widget.children.last is Expanded,
            ),
          )
          .first;
      final footerPadding = find
          .ancestor(of: footer, matching: find.byType(Padding))
          .first;
      void checkGaps() {
        final rowRect = tester.getRect(footer),
            padded = tester.getRect(footerPadding);
        expect(rowRect.top - padded.top, 12);
        expect(padded.bottom - rowRect.bottom, 12);
        final painted = find
            .ancestor(of: footerPadding, matching: find.byType(ColoredBox))
            .first;
        expect(tester.widget<ColoredBox>(painted).color, Colors.white);
        expect(
          tester.getRect(painted),
          padded,
          reason: 'footer gaps must belong to one continuous white surface',
        );
        expect(save.hitTestable(), findsOneWidget);
        expect(find.text('Отмена').hitTestable(), findsOneWidget);
        for (final label in ['Сохранить', 'Отмена']) {
          final ink = find
              .ancestor(of: find.text(label), matching: find.byType(InkWell))
              .first;
          expect(tester.widget<InkWell>(ink).onTap, isNotNull);
        }
      }

      checkGaps();
      final city = tester
          .widgetList<EditableText>(find.byType(EditableText))
          .last;
      final editor = find.byWidgetPredicate(
        (widget) =>
            widget is EditableText &&
            identical(widget.controller, city.controller),
      );
      await tester.ensureVisible(editor);
      await tester.tap(editor);
      await tester.enterText(editor, 'Город для проверки');
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expectFocusedCaretAboveIme(tester, editor);
      checkGaps();
      expect(tester.getRect(footerPadding).bottom, lessThanOrEqualTo(524));
      final surface = find
          .byWidgetPredicate((widget) => widget is TrackSheetSurface)
          .last;
      final scroll = find
          .descendant(of: surface, matching: find.byType(Scrollable))
          .first;
      final before = tester.state<ScrollableState>(scroll).position.pixels;
      final pinned = tester.getRect(footerPadding);
      await tester.drag(scroll, const Offset(0, 120));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        tester.state<ScrollableState>(scroll).position.pixels,
        lessThan(before),
      );
      expect(tester.getRect(footerPadding), pinned);
      checkGaps();
      expect(city.controller.text, 'Город для проверки');
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      checkGaps();
      expect(city.controller.text, 'Город для проверки');
      expect(tester.getRect(footerPadding).bottom, lessThanOrEqualTo(810));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    testWidgets(
      'actual separate delivery retains every typed draft ${platform.name}',
      (tester) async {
        const assembly = TrackAssembly(
          id: 43,
          number: 'ASM-GAPS',
          status: 'ready_for_pickup',
          deliveryMethod: 'transport_company',
          recipientName: 'Клиент',
          recipientPhone: '+79991234567',
          recipientCity: 'Москва',
          transportCompanyName: 'СДЭК',
          trackCount: 1,
        );
        await _pumpTrack(tester, platform, assembly: assembly);
        await _openAction(tester, 'Доставка');
        final editors = tester
            .widgetList<EditableText>(find.byType(EditableText))
            .toList();
        expect(editors.length, 4);
        const drafts = [
          'Новая ТК',
          'Новый получатель',
          '9997654321',
          'Новый город',
        ];
        for (var index = 0; index < editors.length; index++) {
          await typeDraftThroughIme(
            tester,
            editors[index].controller,
            drafts[index],
            numericFormatting: index == 2,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
    testWidgets('actual inline note retains typed draft ${platform.name}', (
      tester,
    ) async {
      await _pumpTrack(tester, platform);
      await tester.tap(
        find.byKey(const ValueKey('client-track-card-GAP-TRACK')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('client-track-detail-tab-0')));
      await tester.pumpAndSettle();
      final note = find.text('Добавить комментарий');
      expect(
        note,
        findsOneWidget,
        reason: find
            .byType(Text)
            .evaluate()
            .map((e) => (e.widget as Text).data)
            .toList()
            .toString(),
      );
      await tester.ensureVisible(note);
      await tester.tap(note);
      await tester.pumpAndSettle();
      final editors = tester
          .widgetList<EditableText>(find.byType(EditableText))
          .toList();
      expect(editors.length, 1);
      await typeDraftThroughIme(
        tester,
        editors.single.controller,
        'Заметка внутри карточки\nПроверить размеры',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    testWidgets(
      'actual detail return request keeps typed code ${platform.name}',
      (tester) async {
        await _pumpTrack(tester, platform);
        await tester.tap(
          find.byKey(const ValueKey('client-track-card-GAP-TRACK')),
        );
        await tester.pumpAndSettle();
        final tab = find.byKey(const ValueKey('client-track-detail-tab-4'));
        await tester.ensureVisible(tab);
        await tester.tap(tab);
        await tester.pumpAndSettle();
        final request = find.text('Запросить возврат');
        await tester.ensureVisible(request);
        await tester.tap(request);
        await tester.pumpAndSettle();
        final editors = tester
            .widgetList<EditableText>(find.byType(EditableText))
            .toList();
        expect(editors.length, 1);
        await typeDraftThroughIme(
          tester,
          editors.single.controller,
          'INLINE-RETURN-777',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
    testWidgets(
      'actual orphan unique question entry has fixed task and no editable input ${platform.name}',
      (tester) async {
        await _pumpTrack(tester, platform, orphan: true);
        final action = find
            .descendant(
              of: find.byWidgetPredicate(
                (widget) =>
                    widget.runtimeType.toString() == '_ActionChipButton',
              ),
              matching: find.text('Вопрос'),
            )
            .first;
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(find.text('Вопрос складу'), findsOneWidget);
        expect(
          find.text(
            'Не знаю что это за трек номер, могли бы проверить и код клиента и трек номер',
          ),
          findsOneWidget,
        );
        expect(find.byType(EditableText), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
