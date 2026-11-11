import 'package:twoalogisticcabineuser/src/core/branding/company_branding_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_analytics_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_repository.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/presentation/sp_organizer_analytics_screen.dart';

const _capabilities = SpOrganizerCapabilities(
  contractVersion: 1,
  organizerV2: true,
  purchaseKinds: true,
  participants: true,
  products: true,
  calculationProfiles: true,
  fulfillmentOverview: true,
  selfBuyoutLinks: true,
  selfBuyout: SpOrganizerActionCapability.unavailable,
  garageImport: true,
  trackLinks: true,
  assemblyLinks: true,
  invoiceLinks: true,
  analytics: true,
);

const _analytics = SpOrganizerAnalytics(
  contractVersion: 1,
  mode: 'read_only',
  persisted: false,
  filter: SpOrganizerAnalyticsFilter(),
  summary: SpOrganizerAnalyticsSummary(
    purchasesCount: 2,
    activePurchasesCount: 1,
    completedPurchasesCount: 1,
    customersCount: 3,
    itemsCount: 4,
    purchasedItemsCount: 3,
    catalogProductsCount: 5,
    turnoverRub: 565,
    paidRub: 160,
    receivableRub: 405,
    costRub: 435,
    profitRub: 130,
    expensesRub: 15,
    totalWeightKg: 3.5,
    averagePurchaseRub: 282.5,
    averageItemRub: 141.25,
    averageDeliveryDays: 5,
  ),
  comparison: SpOrganizerAnalyticsComparison(
    available: true,
    previous: SpOrganizerAnalyticsComparisonSummary(
      purchasesCount: 1,
      customersCount: 2,
      itemsCount: 2,
      turnoverRub: 100,
      profitRub: 20,
      averagePurchaseRub: 100,
      averageDeliveryDays: 7,
    ),
    changes: SpOrganizerAnalyticsComparisonChanges(
      purchasesCount: 100,
      customersCount: 50,
      itemsCount: 100,
      turnoverRub: 465,
      profitRub: 550,
      averagePurchaseRub: 182.5,
      averageDeliveryDays: -28.57,
    ),
  ),
  integrations: SpOrganizerAnalyticsIntegrations(
    buyoutLinkedItemsCount: 2,
    buyoutLinkedItemsShare: 50,
    trackLinkedItemsCount: 2,
    trackLinkedItemsShare: 50,
    fulfillmentPurchasesCount: 2,
    fulfillmentPurchasesShare: 100,
    invoiceLinkedPurchasesCount: 1,
    invoiceLinkedPurchasesShare: 50,
  ),
  series: [
    SpOrganizerAnalyticsSeriesPoint(
      month: '2026-01',
      purchasesCount: 1,
      itemsCount: 2,
      turnoverRub: 225,
      paidRub: 100,
      profitRub: 55,
    ),
  ],
  topPurchases: [
    SpOrganizerAnalyticsTopPurchase(
      id: 17,
      title: 'Закупка января',
      kind: 'group',
      status: 'active',
      itemsCount: 2,
      customersCount: 2,
      turnoverRub: 225,
      paidRub: 100,
      profitRub: 55,
      has2aFulfillment: true,
    ),
  ],
  topCustomers: [
    SpOrganizerAnalyticsTopCustomer(
      id: 15,
      fullName: 'Иван Иванов',
      displayName: 'Иван Иванов',
      purchasesCount: 2,
      itemsCount: 3,
      turnoverRub: 400,
      paidRub: 300,
      profitRub: 80,
    ),
  ],
  topProducts: [
    SpOrganizerAnalyticsTopProduct(
      id: 7,
      title: 'Куртка',
      marketplaceCode: '1688',
      purchasesCount: 2,
      customersCount: 3,
      quantity: 4,
      turnoverRub: 500,
      costRub: 350,
      profitRub: 150,
    ),
  ],
  topMarketplaces: [
    SpOrganizerAnalyticsTopMarketplace(
      code: '1688',
      productsCount: 1,
      purchasesCount: 2,
      quantity: 4,
      turnoverRub: 500,
      profitRub: 150,
    ),
  ],
  formulas: {
    'turnoverRub': 'legacy_stats.totalDueRub',
    'profitRub': 'legacy_stats.totalProfitRub',
  },
);

class _FakeRepository extends SpOrganizerRepository {
  _FakeRepository() : super(ApiClient());

  SpOrganizerAnalyticsFilter? lastFilter;

  @override
  Future<SpOrganizerCapabilities> getCapabilities() async => _capabilities;

  @override
  Future<SpOrganizerAnalytics> getAnalytics(
    SpOrganizerAnalyticsFilter filter,
  ) async {
    lastFilter = filter;
    return _analytics;
  }
}

Future<_FakeRepository> _pumpScreen(
  WidgetTester tester, {
  required Size size,
  required Locale locale,
  bool embedded = false,
}) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(size);
  final repository = _FakeRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        companyNameProvider.overrideWithValue('Partner Cargo'),
        spOrganizerRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ru'), Locale('zh')],
        home: Scaffold(body: SpOrganizerAnalyticsScreen(embedded: embedded)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return repository;
}

void main() {
  testWidgets('retry reloads capabilities after a failed initial check', (
    tester,
  ) async {
    final repository = _RetryRepository();
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          companyNameProvider.overrideWithValue('Partner Cargo'),
          spOrganizerRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SpOrganizerAnalyticsScreen(embedded: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Аналитика временно недоступна'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(repository.checks, 2);
    expect(repository.lastFilter, isNotNull);
    expect(find.text('Аналитика временно недоступна'), findsNothing);
  });

  testWidgets('embedded analytics tab omits the duplicate hero', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      size: const Size(390, 1000),
      locale: const Locale('ru'),
      embedded: true,
    );

    expect(find.text('Рабочая картина закупок'), findsNothing);
    expect(find.text('Использование Partner Cargo'), findsOneWidget);
  });

  testWidgets('read-only analytics fits 320 px and changes server period', (
    tester,
  ) async {
    final repository = await _pumpScreen(
      tester,
      size: const Size(320, 1000),
      locale: const Locale('ru'),
    );

    expect(find.text('Рабочая картина закупок'), findsOneWidget);
    expect(find.text('Использование Partner Cargo'), findsOneWidget);
    expect(find.text('Выкуп через Partner Cargo'), findsOneWidget);
    expect(find.text('Крупнейшие закупки'), findsOneWidget);
    expect(find.text('Сравнение с прошлым периодом'), findsOneWidget);
    expect(find.text('Средняя доставка'), findsWidgets);
    expect(find.text('Лучшие клиенты'), findsOneWidget);
    expect(find.text('Лучшие товары'), findsOneWidget);
    expect(find.text('Площадки'), findsOneWidget);
    expect(find.text('Тип аналитики'), findsOneWidget);
    expect(find.text('Все закупки'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sp-analytics-period-90d')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('sp-analytics-audience-selector')),
      findsOneWidget,
    );
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(repository.lastFilter?.period, '90d');
    expect(repository.lastFilter?.audience, 'all');
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('30 дней'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repository.lastFilter?.period, '30d');
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Свой период'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byKey(const ValueKey('sp-finance-date-range-sheet')),
      findsOneWidget,
    );
    expect(find.text('Период аналитики'), findsOneWidget);
    await tester.tap(find.byTooltip('Закрыть').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(
      find.byKey(const ValueKey('sp-analytics-audience-selector')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Выберите тип аналитики'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('sp-analytics-audience-client')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repository.lastFilter?.audience, 'client');
    expect(repository.lastFilter?.kind, 'all');
    expect(find.text('Подтип'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sp-analytics-subtype-selector')),
      findsOneWidget,
    );
    expect(find.text('Мои товары — как личные'), findsOneWidget);

    await tester.tap(find.text('Мои товары — как личные'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repository.lastFilter?.selfItemsAsPersonal, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('read-only analytics uses Chinese labels at 390 px', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      size: const Size(390, 1000),
      locale: const Locale('zh'),
    );

    expect(find.text('采购经营概览'), findsOneWidget);
    expect(find.text('Partner Cargo使用情况'), findsOneWidget);
    expect(find.text('通过Partner Cargo采购'), findsOneWidget);
    expect(find.text('最大采购'), findsOneWidget);
    expect(find.text('与上一周期对比'), findsOneWidget);
    expect(find.text('重点客户'), findsOneWidget);
    expect(find.text('热门商品'), findsOneWidget);
    expect(find.text('采购平台'), findsOneWidget);
    expect(find.textContaining('仅查看'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('read-only analytics fits desktop width', (tester) async {
    await _pumpScreen(
      tester,
      size: const Size(1024, 1200),
      locale: const Locale('ru'),
    );

    expect(find.text('Рабочая картина закупок'), findsOneWidget);
    expect(find.text('Крупнейшие закупки'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _RetryRepository extends _FakeRepository {
  int checks = 0;
  @override
  Future<SpOrganizerCapabilities> getCapabilities() async {
    if (++checks == 1) throw StateError('network unavailable');
    return _capabilities;
  }
}
