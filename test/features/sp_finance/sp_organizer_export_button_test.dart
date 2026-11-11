import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/core/branding/company_branding_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_garage_import_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_previous_purchase_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_purchase_blank_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_repository.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_track_import_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_v2_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_v2_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/presentation/sp_v2_purchase_detail_screen.dart';

const _purchase = SpV2Purchase(
  id: 17,
  title: 'Закупка июля',
  status: 'open',
  statusLabel: 'Принимает товары',
  isAcceptingItems: true,
);

const _capabilities = SpOrganizerCapabilities(
  contractVersion: 1,
  organizerV2: true,
  purchaseKinds: false,
  participants: false,
  products: false,
  purchaseBlankImport: true,
  previousPurchaseImport: true,
  calculationProfiles: false,
  fulfillmentOverview: false,
  selfBuyoutLinks: false,
  selfBuyout: SpOrganizerActionCapability.unavailable,
  garageImport: true,
  trackLinks: true,
  trackImport: true,
  assemblyLinks: false,
  invoiceLinks: false,
  analytics: false,
  purchaseExport: true,
);

class _EmptyImportRepository extends SpOrganizerRepository {
  _EmptyImportRepository() : super(ApiClient());

  @override
  Future<SpOrganizerTrackImportCandidatePage> getTrackImportCandidates({
    required int purchaseId,
    String? query,
    int page = 1,
    int limit = 20,
  }) async => const SpOrganizerTrackImportCandidatePage(
    candidates: [],
    page: 1,
    limit: 20,
    total: 0,
    totalPages: 0,
  );

  @override
  Future<SpOrganizerPurchaseBlankCandidatePage>
  getPurchaseBlankImportCandidates({
    required int purchaseId,
    String? query,
    int page = 1,
    int limit = 20,
  }) async => const SpOrganizerPurchaseBlankCandidatePage(
    candidates: [],
    page: 1,
    limit: 20,
    total: 0,
    totalPages: 0,
  );

  @override
  Future<SpOrganizerPreviousPurchaseCandidatePage>
  getPreviousPurchaseImportCandidates({
    required int purchaseId,
    String? query,
    int page = 1,
    int limit = 20,
  }) async => const SpOrganizerPreviousPurchaseCandidatePage(
    candidates: [],
    page: 1,
    limit: 20,
    total: 0,
    totalPages: 0,
  );

  @override
  Future<SpOrganizerGarageImportCandidatePage> getGarageImportCandidates({
    required int purchaseId,
    String? query,
    int page = 1,
    int limit = 20,
  }) async => const SpOrganizerGarageImportCandidatePage(
    candidates: [],
    page: 1,
    limit: 20,
    total: 0,
    totalPages: 0,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required Locale locale,
  SpOrganizerCapabilities capabilities = _capabilities,
  NavigatorObserver? observer,
}) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        companyNameProvider.overrideWithValue('Partner Cargo'),
        spV2PurchaseDetailProvider(17).overrideWith((ref) async => _purchase),
        spOrganizerCapabilitiesProvider.overrideWith(
          (ref) async => capabilities,
        ),
        spOrganizerRepositoryProvider.overrideWithValue(
          _EmptyImportRepository(),
        ),
        spOrganizerParticipantsProvider(
          17,
        ).overrideWith((ref) async => throw StateError('participants test')),
        spOrganizerCalculationPreviewProvider(
          17,
        ).overrideWith((ref) async => throw StateError('calculation test')),
        spOrganizerFulfillmentOverviewProvider(
          17,
        ).overrideWith((ref) async => throw StateError('fulfillment test')),
        spV2CustomersProvider.overrideWith(
          (ref) async => const [
            SpV2Customer(id: 31, fullName: 'Участник теста'),
          ],
        ),
      ],
      child: MaterialApp(
        navigatorObservers: [if (observer != null) observer],
        locale: locale,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ru'), Locale('zh')],
        home: const Scaffold(body: SpV2PurchaseDetailScreen(purchaseId: 17)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void _expectSharedHeaderActionStyle(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  expect(tester.getSize(finder), const Size(46, 44));
  final material = tester.widget<Material>(
    find.ancestor(of: finder, matching: find.byType(Material)).first,
  );
  expect(material.color, Colors.white);
  expect(material.borderRadius, BorderRadius.circular(16));
}

void main() {
  testWidgets('Chinese SP add form localizes inputs, imports and validation', (
    tester,
  ) async {
    await _pump(
      tester,
      size: const Size(390, 1000),
      locale: const Locale('zh'),
    );
    await tester.tap(find.text('Добавить товар').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('添加商品'), findsWidgets);
    expect(find.text('参与者姓名 *'), findsOneWidget);
    expect(find.text('新建'), findsOneWidget);
    expect(find.text('导入商品'), findsOneWidget);
    final save = find.widgetWithText(FilledButton, '添加商品');
    await tester.tap(save);
    await tester.pump();
    expect(find.text('请填写客户和商品'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('export action fits purchase header at 320 px', (tester) async {
    await _pump(
      tester,
      size: const Size(320, 1000),
      locale: const Locale('ru'),
    );

    expect(find.byTooltip('Экспортировать закупку'), findsOneWidget);
    expect(find.text('Закупка июля'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('purchase header actions share the help button style', (
    tester,
  ) async {
    await _pump(
      tester,
      size: const Size(390, 1000),
      locale: const Locale('ru'),
    );

    final actionFinders = [
      find.byKey(const ValueKey('sp-purchase-edit')),
      find.descendant(
        of: find.byTooltip('Экспортировать закупку'),
        matching: find.byType(InkWell),
      ),
      find.ancestor(
        of: find.byIcon(Icons.question_mark_rounded),
        matching: find.byType(InkWell),
      ),
    ];

    for (final finder in actionFinders) {
      _expectSharedHeaderActionStyle(tester, finder);
    }
  });

  testWidgets('detail keeps participants and settings inside their own tabs', (
    tester,
  ) async {
    const enabledCapabilities = SpOrganizerCapabilities(
      contractVersion: 1,
      organizerV2: true,
      purchaseKinds: true,
      participants: true,
      products: true,
      calculationProfiles: true,
      fulfillmentOverview: true,
      selfBuyoutLinks: false,
      selfBuyout: SpOrganizerActionCapability.unavailable,
      garageImport: false,
      trackLinks: false,
      assemblyLinks: false,
      invoiceLinks: false,
      analytics: false,
    );
    await _pump(
      tester,
      size: const Size(320, 1200),
      locale: const Locale('ru'),
      capabilities: enabledCapabilities,
    );

    expect(find.text('Участники закупки'), findsNothing);
    expect(find.text('Параметры расчёта'), findsNothing);
    expect(find.text('Логистика Partner Cargo'), findsNothing);
    expect(find.text('Добавить товар'), findsOneWidget);
    expect(find.text('Закрыть приём'), findsNothing);
    await tester.tap(find.text('Управление СП'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Закрыть приём'), findsOneWidget);
    await tester.tap(find.text('Управление СП'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Участники'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Участники закупки'), findsOneWidget);
    expect(find.text('Добавить товар'), findsNothing);
    expect(find.byTooltip('Добавить товар из каталога'), findsNothing);
    _expectSharedHeaderActionStyle(
      tester,
      find.descendant(
        of: find.byTooltip('Добавить участника'),
        matching: find.byType(InkWell),
      ),
    );

    await Scrollable.ensureVisible(tester.element(find.text('Настройки')));
    await tester.tap(find.text('Настройки'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Параметры расчёта'), findsOneWidget);
    expect(find.text('Логистика Partner Cargo'), findsOneWidget);
    for (final tooltip in [
      'Настроить профиль',
      'Обновить расчёт',
      'Обновить логистику',
    ]) {
      _expectSharedHeaderActionStyle(
        tester,
        find.descendant(
          of: find.byTooltip(tooltip),
          matching: find.byType(InkWell),
        ),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('export action has Chinese semantics at 390 px', (tester) async {
    await _pump(
      tester,
      size: const Size(390, 1000),
      locale: const Locale('zh'),
    );

    expect(find.byTooltip('导出采购'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('add item sheet groups all enabled import sources', (
    tester,
  ) async {
    await _pump(
      tester,
      size: const Size(390, 1000),
      locale: const Locale('ru'),
    );

    await tester.tap(find.text('Добавить товар').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byKey(const ValueKey('add-item-modal')), findsOneWidget);
    expect(find.byKey(const ValueKey('track-import-entry')), findsNothing);
    await tester.tap(find.text('Импорт товара'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('track-import-entry')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('purchase-blank-import-entry')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('previous-purchase-import-entry')),
      findsOneWidget,
    );
    expect(find.text('Добавить из трека'), findsOneWidget);
    expect(find.text('Из бланка выкупа'), findsOneWidget);
    expect(find.text('Из прошлой закупки'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('garage-import-entry')),
      160,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('add-item-form-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('garage-import-entry')), findsOneWidget);
    expect(find.text('Из Garage'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all import sheets ignore same-frame double tap and reopen', (
    tester,
  ) async {
    final observer = _CountingNavigatorObserver();
    await _pump(
      tester,
      size: const Size(390, 1000),
      locale: const Locale('ru'),
      observer: observer,
    );
    await tester.tap(find.text('Добавить товар').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Импорт товара'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final cases = <(Key, String)>[
      (const ValueKey('track-import-entry'), 'Добавить из трека'),
      (
        const ValueKey('purchase-blank-import-entry'),
        'Импорт из бланка выкупа',
      ),
      (
        const ValueKey('previous-purchase-import-entry'),
        'Товар из прошлой закупки',
      ),
      (const ValueKey('garage-import-entry'), 'Добавить из Garage'),
    ];

    for (final (entryKey, title) in cases) {
      final entry = find.byKey(entryKey);
      await tester.ensureVisible(entry);
      await tester.pump(const Duration(milliseconds: 250));
      final pushesBefore = observer.pushes;

      await tester.tap(entry);
      await tester.tap(entry, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(title), findsWidgets, reason: title);
      expect(observer.pushes, pushesBefore + 1, reason: title);

      Navigator.of(tester.element(find.text(title).last)).pop();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.ensureVisible(entry);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(entry);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(title), findsWidgets, reason: '$title reopen');
      expect(observer.pushes, pushesBefore + 2, reason: '$title reopen');
      Navigator.of(tester.element(find.text(title).last)).pop();
      await tester.pump(const Duration(milliseconds: 500));
    }
  });

  testWidgets('manual add item form is sectioned and compact at 320 px', (
    tester,
  ) async {
    const manualCapabilities = SpOrganizerCapabilities(
      contractVersion: 1,
      organizerV2: true,
      purchaseKinds: false,
      participants: false,
      products: false,
      purchaseBlankImport: false,
      previousPurchaseImport: false,
      calculationProfiles: false,
      fulfillmentOverview: false,
      selfBuyoutLinks: false,
      selfBuyout: SpOrganizerActionCapability.unavailable,
      garageImport: false,
      trackLinks: false,
      assemblyLinks: false,
      invoiceLinks: false,
      analytics: false,
      purchaseExport: false,
    );
    await _pump(
      tester,
      size: const Size(320, 1200),
      locale: const Locale('ru'),
      capabilities: manualCapabilities,
    );

    await tester.tap(find.text('Добавить товар').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(
      find.byKey(const ValueKey('add-item-customer-section')),
      findsOneWidget,
    );
    expect(find.text('Контакты участника'), findsOneWidget);

    final formList = find.byKey(const ValueKey('add-item-form-list'));
    await tester.drag(formList, const Offset(0, -150));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('add-item-existing-customer-mode')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.byKey(const ValueKey('add-item-customer-picker-modal')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('add-item-customer-search')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('add-item-customer-search')),
      'Участник',
    );
    await tester.pump();
    expect(find.text('Участник теста'), findsOneWidget);
    await tester.tap(find.byTooltip('Очистить поиск'));
    await tester.pump();
    final participantSearch = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('add-item-customer-search')),
        matching: find.byType(TextField),
      ),
    );
    expect(participantSearch.controller?.text, '');
    await tester.tap(find.byKey(const ValueKey('add-item-customer-result-31')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.byKey(const ValueKey('add-item-selected-customer')),
      findsOneWidget,
    );
    expect(find.text('Участник теста'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add-item-new-customer-mode')));
    await tester.pump();
    final contactsSection = find.byKey(
      const ValueKey('add-item-customer-contacts'),
    );
    expect(
      tester
          .widget<AnimatedCrossFade>(
            find.descendant(
              of: contactsSection,
              matching: find.byType(AnimatedCrossFade),
            ),
          )
          .crossFadeState,
      CrossFadeState.showFirst,
    );
    await tester.drag(formList, const Offset(0, -280));
    await tester.pump();
    await tester.tap(find.text('Контакты участника'));
    await tester.pump(const Duration(milliseconds: 220));
    expect(
      tester
          .widget<AnimatedCrossFade>(
            find.descendant(
              of: contactsSection,
              matching: find.byType(AnimatedCrossFade),
            ),
          )
          .crossFadeState,
      CrossFadeState.showSecond,
    );

    await tester.drag(formList, const Offset(0, -520));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('add-item-product-section')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('add-item-product-section')),
        matching: find.byKey(const ValueKey('add-item-details-section')),
      ),
      findsOneWidget,
    );
    await tester.drag(formList, const Offset(0, -520));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('add-item-prices-section')),
      findsOneWidget,
    );
    await tester.drag(formList, const Offset(0, -520));
    await tester.pump();
    expect(find.text('Можно заполнить позже'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _CountingNavigatorObserver extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes += 1;
    super.didPush(route, previousRoute);
  }
}
