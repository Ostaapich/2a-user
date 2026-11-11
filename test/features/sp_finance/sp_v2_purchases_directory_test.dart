import 'package:twoalogisticcabineuser/src/core/branding/company_branding_provider.dart';
import 'package:flutter/material.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import '../keyboard/keyboard_form_probe.dart';
import '../../helpers/keyboard_acceptance.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_v2_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_v2_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/presentation/sp_v2_purchases_screen.dart';

const _capabilities = SpOrganizerCapabilities(
  contractVersion: 1,
  organizerV2: true,
  purchaseKinds: true,
  participants: true,
  products: false,
  calculationProfiles: false,
  fulfillmentOverview: false,
  selfBuyoutLinks: false,
  selfBuyout: SpOrganizerActionCapability.unavailable,
  garageImport: false,
  trackLinks: false,
  assemblyLinks: false,
  invoiceLinks: false,
  analytics: false,
);

final _purchases = [
  SpV2Purchase(
    id: 1,
    kind: 'group',
    title: 'Летняя закупка',
    status: 'purchasing',
    statusLabel: 'Сервер: выкуп',
    isAcceptingItems: false,
    stats: SpV2PurchaseStats(
      customersCount: 4,
      itemsCount: 8,
      linkedTracksCount: 3,
      totalDueRub: 12500,
      totalProfitRub: 2100,
    ),
    directory: SpV2PurchaseDirectoryCard(
      available: true,
      createdAt: DateTime.utc(2026, 7, 1),
      updatedAt: DateTime.utc(2026, 7, 5),
      stageAt: DateTime.utc(2026, 7, 5),
      weightKg: 4.25,
      weightSource: 'actual',
      costRub: 10400,
      outstandingRub: 6300,
      profitRub: 2100,
      integrations: const SpV2PurchaseDirectoryIntegrations(
        selfBuyoutRequestsCount: 1,
        garageOrderItemsCount: 1,
        tracksCount: 3,
        photosCount: 4,
        photoRequestsCount: 1,
        assembliesCount: 2,
        invoicesCount: 1,
        connectedServicesCount: 7,
      ),
    ),
  ),
  SpV2Purchase(
    id: 2,
    kind: 'personal',
    title: 'Персональная закупка',
    status: 'open',
    statusLabel: 'Сервер: открыта',
    isAcceptingItems: true,
    stats: SpV2PurchaseStats(
      customersCount: 1,
      itemsCount: 2,
      totalDueRub: 3500,
      totalProfitRub: 500,
    ),
    directory: SpV2PurchaseDirectoryCard(
      available: true,
      createdAt: DateTime.utc(2026, 7, 7),
      updatedAt: DateTime.utc(2026, 7, 7),
      stageAt: DateTime.utc(2026, 7, 7),
      costRub: 3000,
      outstandingRub: 3500,
      profitRub: 500,
    ),
  ),
];

class _TestPurchasesController extends SpV2PurchasesController {
  int loadMoreCalls = 0;

  @override
  SpV2PurchasesState build() {
    return SpV2PurchasesState(
      purchases: _purchases,
      directoryQuery: const SpV2PurchaseDirectoryQuery(),
      pagination: const SpV2PurchaseDirectoryPagination(
        page: 1,
        limit: 2,
        total: 4,
        totalPages: 2,
        hasNextPage: true,
      ),
      summary: const SpV2PurchaseDirectorySummary(
        purchasesCount: 4,
        activePurchasesCount: 3,
        itemsCount: 17,
        totalDueRub: 28000,
        totalProfitRub: 4200,
      ),
      statusOptions: const [
        SpV2PurchaseDirectoryStatus(code: 'open', label: 'Сервер: открыта'),
        SpV2PurchaseDirectoryStatus(code: 'purchasing', label: 'Сервер: выкуп'),
      ],
    );
  }

  @override
  Future<void> load({bool silent = false, String? query}) async {}

  @override
  Future<void> search(String query) async {
    state = state.copyWith(
      directoryQuery: state.directoryQuery.copyWith(query: query),
    );
  }

  @override
  Future<void> updateDirectoryQuery(SpV2PurchaseDirectoryQuery query) async {
    state = state.copyWith(directoryQuery: query.copyWith(page: 1));
  }

  @override
  Future<void> clearDirectoryFilters() async {
    state = state.copyWith(
      directoryQuery: SpV2PurchaseDirectoryQuery(query: state.query),
    );
  }

  @override
  Future<void> loadMore() async {
    loadMoreCalls += 1;
  }
}

Future<_TestPurchasesController> _pumpDirectory(
  WidgetTester tester, {
  required Size size,
  bool embedded = false,
  NavigatorObserver? observer,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(size);
  late _TestPurchasesController controller;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        companyNameProvider.overrideWithValue('Partner Cargo'),
        spV2PurchasesControllerProvider.overrideWith(() {
          controller = _TestPurchasesController();
          return controller;
        }),
        spOrganizerCapabilitiesProvider.overrideWith(
          (ref) async => _capabilities,
        ),
      ],
      child: MaterialApp(
        builder: (_, child) => AppKeyboardDismissRegion(child: child!),
        navigatorObservers: [if (observer != null) observer],
        locale: const Locale('ru'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ru')],
        theme: ThemeData(
          platform: platform,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6D5BD0)),
        ),
        home: Scaffold(body: SpV2PurchasesScreen(embedded: embedded)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return controller;
}

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      '$platform _pumpDirectory actual create editor every field320height',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        await _pumpDirectory(
          tester,
          size: const Size(390, 640),
          platform: platform,
        );
        expect(await probeCurrentFormEditors(tester), 1);
        await tester.ensureVisible(find.byIcon(Icons.add_rounded));
        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(await probeCurrentFormEditors(tester, minimumFields: 3), 3);
      },
    );
  }

  testWidgets('embedded purchase tab omits the duplicate hero', (tester) async {
    await _pumpDirectory(tester, size: const Size(390, 900), embedded: true);

    expect(find.text('Закупки организатора'), findsNothing);
    expect(find.byKey(const Key('sp-purchase-filter-button')), findsOneWidget);
  });

  testWidgets(
    'directory fits 320 px and applies a status supplied by backend',
    (tester) async {
      final controller = await _pumpDirectory(
        tester,
        size: const Size(320, 900),
      );

      expect(find.textContaining('по дате создания'), findsNothing);
      expect(find.text('Себестоимость'), findsWidgets);
      expect(find.text('Сервисы Partner Cargo'), findsOneWidget);
      expect(find.byTooltip('Самовыкуп: 1'), findsOneWidget);
      expect(find.byTooltip('Фото и запросы фото: 5'), findsOneWidget);
      expect(
        find.byKey(const Key('sp-purchase-filter-button')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('sp-purchase-filter-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(const Key('sp-purchase-filter-sheet')), findsOneWidget);
      expect(find.text('Сервер: выкуп'), findsWidgets);
      await tester.ensureVisible(
        find.byKey(const Key('sp-purchase-status-purchasing')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('sp-purchase-status-purchasing')));
      await tester.ensureVisible(
        find.byKey(const Key('sp-purchase-filter-apply')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('sp-purchase-filter-apply')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(controller.state.directoryQuery.status, 'purchasing');
      expect(controller.state.directoryQuery.activeFilterCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('directory fits 390 px and exposes explicit pagination', (
    tester,
  ) async {
    final controller = await _pumpDirectory(
      tester,
      size: const Size(390, 1000),
    );

    final loadMore = find.byKey(const Key('sp-purchase-load-more'));
    await tester.ensureVisible(loadMore);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Показать ещё · 2 из 4'), findsOneWidget);
    final callsBeforeTap = controller.loadMoreCalls;
    await tester.tap(loadMore);
    await tester.pump();

    expect(controller.loadMoreCalls, greaterThan(callsBeforeTap));
    expect(tester.takeException(), isNull);
  });

  testWidgets('purchase preview keeps the organizer summary compact', (
    tester,
  ) async {
    await _pumpDirectory(tester, size: const Size(390, 1000), embedded: true);

    final card = find.byKey(const ValueKey('sp-purchase-card-1'));
    expect(card, findsOneWidget);
    expect(tester.getSize(card).height, lessThanOrEqualTo(310));
    expect(find.text('Себестоимость'), findsWidgets);
    expect(find.text('Сервисы Partner Cargo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'create purchase sheet ignores same-frame double tap and reopens',
    (tester) async {
      final observer = _CountingNavigatorObserver();
      await _pumpDirectory(
        tester,
        size: const Size(390, 1000),
        observer: observer,
      );
      final addButton = find.byIcon(Icons.add_rounded).first;
      final pushesBefore = observer.pushes;

      await tester.tap(addButton);
      await tester.tap(addButton, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Новая СП'), findsOneWidget);
      expect(observer.pushes, pushesBefore + 1);

      Navigator.of(tester.element(find.text('Новая СП'))).pop();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(addButton);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Новая СП'), findsOneWidget);
      expect(observer.pushes, pushesBefore + 2);
    },
  );

  testWidgets('purchase period opens the shared SP date modal', (tester) async {
    await _pumpDirectory(tester, size: const Size(390, 1000));

    await tester.tap(find.byKey(const Key('sp-purchase-filter-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.byKey(const Key('sp-purchase-period')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('sp-purchase-period')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byKey(const ValueKey('sp-finance-date-range-sheet')),
      findsOneWidget,
    );
    expect(find.text('Период создания закупки'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide directory uses a two-column card grid', (tester) async {
    await _pumpDirectory(tester, size: const Size(900, 1000));

    final first = tester.getTopLeft(find.text('Летняя закупка'));
    final second = tester.getTopLeft(find.text('Персональная закупка'));
    expect((first.dy - second.dy).abs(), lessThan(8));
    expect(second.dx, greaterThan(first.dx + 250));
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
