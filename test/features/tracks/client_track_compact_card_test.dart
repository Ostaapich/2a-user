import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/presentation/widgets/client_track_compact_card.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('Gilroy')
          ..addFont(rootBundle.load('assets/fonts/gilroy/Gilroy-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/gilroy/Gilroy-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader('CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
  });
  testWidgets('card keeps selection independent from opening details', (
    tester,
  ) async {
    var selectionCount = 0;
    final openedTabs = <int>[];

    await tester.pumpWidget(
      _testApp(
        child: ClientTrackCompactCard(
          trackNumber: 'YT123456789',
          status: 'На складе',
          statusColor: const Color(0xFF168A5B),
          productName: 'Кроссовки',
          selectable: true,
          selected: false,
          onToggleSelection: () => selectionCount++,
          onCopyTrack: () {},
          onOpenDetails: openedTabs.add,
          indicators: const [
            ClientTrackIndicator(
              icon: Icons.photo_library_outlined,
              title: 'Фото',
              value: 'Готово',
              label: 'Фотоотчёт готов',
              color: Color(0xFF168A5B),
              tabIndex: 1,
            ),
          ],
          actions: const [],
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('client-track-selection')));
    await tester.pump();
    expect(selectionCount, 1);
    expect(openedTabs, isEmpty);

    await tester.tap(
      find.byKey(const ValueKey('client-track-card-YT123456789')),
    );
    await tester.pump();
    expect(openedTabs, [0]);
  });

  testWidgets('status indicators open their matching detail tab', (
    tester,
  ) async {
    final openedTabs = <int>[];
    await tester.pumpWidget(
      _testApp(
        child: ClientTrackCompactCard(
          trackNumber: 'YT123',
          status: 'В ожидании',
          statusColor: const Color(0xFFD97706),
          productName: '',
          selectable: false,
          selected: false,
          onToggleSelection: null,
          onCopyTrack: () {},
          onOpenDetails: openedTabs.add,
          indicators: const [
            ClientTrackIndicator(
              icon: Icons.inventory_2_outlined,
              title: 'Товар',
              value: 'Не заполнено',
              label: 'Товар не заполнен',
              color: Color(0xFFD97706),
              tabIndex: 0,
            ),
            ClientTrackIndicator(
              icon: Icons.help_outline_rounded,
              title: 'Вопросы',
              value: 'Ждёт ответа',
              label: '2 · ждёт ответа',
              color: Color(0xFFD97706),
              tabIndex: 2,
            ),
          ],
          actions: const [],
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('client-track-indicator-2')));
    await tester.pump();
    expect(openedTabs, [2]);
    expect(find.text('Информация о товаре не заполнена'), findsNothing);
  });

  testWidgets('compact card stays overflow-free on a narrow viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testApp(
        textScale: 1.3,
        child: ClientTrackCompactCard(
          trackNumber: '79132563149057',
          status: 'Передан транспортной компании',
          statusColor: const Color(0xFF2D6CDF),
          productName: 'Очень длинное название товара для проверки карточки',
          selectable: true,
          selected: true,
          onToggleSelection: () {},
          onCopyTrack: () {},
          onOpenDetails: (_) {},
          indicators: const [
            ClientTrackIndicator(
              icon: Icons.photo_library_outlined,
              title: 'Фото',
              value: 'Готово',
              label: 'Фотоотчёт готов',
              color: Color(0xFF168A5B),
              tabIndex: 1,
            ),
          ],
          actions: [
            ClientTrackQuickAction(
              icon: Icons.help_outline_rounded,
              label: 'Вопрос',
              onTap: () {},
            ),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('79132563149057'), findsOneWidget);
  });

  testWidgets('state and action cells stay uniform and tappable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testApp(
        textScale: 1.3,
        child: ClientTrackCompactCard(
          trackNumber: 'YT123456789',
          status: 'На складе',
          statusColor: const Color(0xFF168A5B),
          productName: 'Кроссовки',
          selectable: true,
          selected: false,
          onToggleSelection: () {},
          onCopyTrack: () {},
          onOpenDetails: (_) {},
          indicators: const [
            ClientTrackIndicator(
              icon: Icons.inventory_2_rounded,
              title: 'Товар',
              value: 'Заполнено',
              label: 'Товар заполнен',
              color: Color(0xFF168A5B),
              tabIndex: 0,
            ),
            ClientTrackIndicator(
              icon: Icons.photo_library_rounded,
              title: 'Фото',
              value: 'Готово',
              label: 'Фотоотчёт готов',
              color: Color(0xFF168A5B),
              tabIndex: 1,
            ),
            ClientTrackIndicator(
              icon: Icons.help_outline_rounded,
              title: 'Вопросы',
              value: 'Ждёт ответа',
              label: 'Вопрос ждёт ответа',
              color: Color(0xFFD97706),
              tabIndex: 2,
            ),
            ClientTrackIndicator(
              icon: Icons.assignment_return_rounded,
              title: 'Возврат',
              value: 'Оформлен',
              label: 'Возврат оформлен',
              color: Color(0xFFD97706),
              tabIndex: 3,
            ),
          ],
          actions: [
            ClientTrackQuickAction(
              icon: Icons.help_outline_rounded,
              label: 'Вопрос',
              onTap: () {},
            ),
            ClientTrackQuickAction(
              icon: Icons.swap_horiz_rounded,
              label: 'Перенести',
              onTap: () {},
            ),
            ClientTrackQuickAction(
              icon: Icons.edit_note_rounded,
              label: 'Заметка',
              onTap: () {},
            ),
            ClientTrackQuickAction(
              icon: Icons.photo_camera_outlined,
              label: 'Фотоотчёт',
              onTap: () {},
            ),
            ClientTrackQuickAction(
              icon: Icons.assignment_return_outlined,
              label: 'Возврат',
              onTap: () {},
            ),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('client-track-indicator-0')))
          .height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('client-track-action-Вопрос')))
          .height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('client-track-action-panel')))
          .height,
      greaterThanOrEqualTo(64),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('client-track-action-panel')))
          .width,
      lessThanOrEqualTo(
        tester
            .getSize(
              find.byKey(const ValueKey('client-track-card-YT123456789')),
            )
            .width,
      ),
    );
    expect(find.text('Заполнено'), findsNothing);
    expect(find.text('Готово'), findsNothing);
    expect(find.text('Ждёт ответа'), findsNothing);
    expect(find.text('Оформлен'), findsNothing);
  });

  testWidgets(
    'all six actions remain visible and tappable at320px with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final labels = [
        'Вопросы',
        'Перенести',
        'Заметка',
        'Фотоотчёт',
        'Возврат',
        'Удалить',
      ];
      final taps = <String>[];
      await tester.pumpWidget(
        _testApp(
          textScale: 1.6,
          child: ClientTrackCompactCard(
            trackNumber: 'TEST',
            status: 'На складе',
            statusColor: Colors.green,
            productName: 'Товар',
            selectable: false,
            selected: false,
            onToggleSelection: null,
            onCopyTrack: () {},
            onOpenDetails: (_) {},
            indicators: const [],
            actions: [
              for (final label in labels)
                ClientTrackQuickAction(
                  icon: Icons.help_outline,
                  label: label,
                  onTap: () => taps.add(label),
                ),
            ],
          ),
        ),
      );
      final panel = tester.getRect(
        find.byKey(const ValueKey('client-track-action-panel')),
      );
      for (final label in labels) {
        final action = find.byKey(ValueKey('client-track-action-$label'));
        final rect = tester.getRect(action);
        expect(rect.left, greaterThanOrEqualTo(panel.left));
        expect(rect.right, lessThanOrEqualTo(panel.right));
        expect(rect.top, greaterThanOrEqualTo(panel.top));
        expect(rect.bottom, lessThanOrEqualTo(panel.bottom));
        expect(rect.width, greaterThanOrEqualTo(44));
        expect(rect.height, greaterThanOrEqualTo(44));
        await tester.tap(action);
      }
      expect(taps, labels);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact card visual baseline matches the client app style', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testApp(
        seedColor: const Color(0xFFFF5A1F),
        backgroundColor: const Color(0xFFF4F5FC),
        child: RepaintBoundary(
          key: const ValueKey('client-track-style-golden'),
          child: ColoredBox(
            color: const Color(0xFFF4F5FC),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ClientTrackCompactCard(
                trackNumber: '79132563149057',
                status: 'На складе',
                statusColor: const Color(0xFF168A5B),
                productName: 'Кроссовки Nike Air Max',
                selectable: true,
                selected: false,
                onToggleSelection: () {},
                onCopyTrack: () {},
                onOpenDetails: (_) {},
                indicators: const [
                  ClientTrackIndicator(
                    icon: Icons.inventory_2_rounded,
                    title: 'Товар',
                    value: 'Заполнено',
                    label: 'Товар заполнен',
                    color: Color(0xFF168A5B),
                    tabIndex: 0,
                  ),
                  ClientTrackIndicator(
                    icon: Icons.photo_library_outlined,
                    title: 'Фото',
                    value: 'Нет',
                    label: 'Фотоотчёта нет',
                    color: Color(0xFF7C8494),
                    tabIndex: 1,
                  ),
                  ClientTrackIndicator(
                    icon: Icons.help_outline_rounded,
                    title: 'Вопросы',
                    value: 'Ждёт ответа',
                    label: 'Вопрос ждёт ответа',
                    color: Color(0xFFD97706),
                    tabIndex: 2,
                  ),
                ],
                actions: [
                  ClientTrackQuickAction(
                    icon: Icons.forum_outlined,
                    label: 'Вопросы',
                    onTap: () {},
                  ),
                  ClientTrackQuickAction(
                    icon: Icons.swap_horiz_rounded,
                    label: 'Перенести',
                    onTap: () {},
                  ),
                  ClientTrackQuickAction(
                    icon: Icons.edit_note_rounded,
                    label: 'Заметка',
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byKey(const ValueKey('client-track-style-golden')),
      matchesGoldenFile('goldens/client_track_compact_card_style.png'),
    );
  });

  testWidgets('detail tabs expose all five sections and selection semantics', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      _testApp(
        child: StatefulBuilder(
          builder: (context, setState) => ClientTrackDetailTabs(
            selectedIndex: selected,
            onSelected: (value) => setState(() => selected = value),
          ),
        ),
      ),
    );

    for (final label in ClientTrackDetailTabs.labels) {
      expect(find.text(label), findsOneWidget);
    }

    expect(ClientTrackDetailTabs.labels[1], 'Доставка до склада');

    await tester.tap(find.byKey(const ValueKey('client-track-detail-tab-4')));
    await tester.pumpAndSettle();
    expect(selected, 4);
    expect(
      tester.getSemantics(find.text('Возвраты')),
      matchesSemantics(
        label: 'Возвраты',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
      ),
    );
  });

  testWidgets('warehouse delivery tab can be hidden without shifting indices', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      _testApp(
        child: StatefulBuilder(
          builder: (context, setState) => ClientTrackDetailTabs(
            selectedIndex: selected,
            visibleIndices: const [0, 2, 3, 4],
            onSelected: (value) => setState(() => selected = value),
          ),
        ),
      ),
    );

    expect(find.text('Доставка до склада'), findsNothing);
    expect(find.text('Фотоотчёт'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('client-track-detail-tab-2')));
    await tester.pumpAndSettle();
    expect(selected, 2);
  });
}

Widget _testApp({
  required Widget child,
  double textScale = 1,
  Color seedColor = const Color(0xFF3267D6),
  Color backgroundColor = Colors.white,
}) {
  return MaterialApp(
    theme: ThemeData(
      fontFamily: 'Gilroy',
      colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
    ),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: Center(child: child),
      ),
    ),
  );
}
