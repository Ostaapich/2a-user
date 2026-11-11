import 'package:flutter/material.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import '../keyboard/keyboard_form_probe.dart';
import '../../helpers/keyboard_acceptance.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/presentation/sp_organizer_product_detail_screen.dart';

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
  customersDirectory: true,
);

const _detail = SpOrganizerProductDetail(
  product: SpOrganizerProduct(
    id: 7,
    title: 'Куртка демисезонная',
    marketplaceCode: '1688-007',
    barcode: '460000000007',
    description: 'Карточка товара с полной историей закупок.',
    itemsCount: 6,
  ),
  summary: SpOrganizerProductUsageSummary(
    itemsCount: 6,
    purchasesCount: 3,
    customersCount: 4,
    totalQuantity: 8,
    totalWeightKg: 2.4,
    turnoverRub: 9600,
    costRub: 6800,
    profitRub: 2800,
    averageClientPriceRub: 1200,
    averageCostRub: 850,
  ),
  history: SpOrganizerProductHistoryPage(
    total: 1,
    page: 1,
    limit: 20,
    totalPages: 1,
    items: [
      SpOrganizerProductHistoryItem(
        id: 90,
        title: 'Куртка XL',
        quantity: 2,
        status: 'purchased',
        statusLabel: 'Выкуплен',
        clientPriceRub: 1200,
        costPriceRub: 850,
        purchase: SpOrganizerProductHistoryPurchase(
          id: 11,
          title: 'СП июль',
          kind: 'group',
          status: 'purchasing',
          statusLabel: 'Выкуп',
          currency: 'CNY',
        ),
        customer: SpOrganizerProductHistoryCustomer(
          id: 15,
          fullName: 'Иван Иванов',
          displayName: 'Иван Иванов',
          isOrganizerSelf: false,
        ),
      ),
    ],
  ),
  statusOptions: [
    SpOrganizerProductHistoryStatus(
      code: 'purchased',
      nameRu: 'Выкуплен',
      nameZh: '已购买',
      color: '#16A34A',
      sortOrder: 40,
    ),
  ],
);

Future<void> _pumpDetail(
  WidgetTester tester, {
  required Size size,
  required Locale locale,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        spOrganizerCapabilitiesProvider.overrideWith(
          (ref) async => _capabilities,
        ),
        spOrganizerProductDetailProvider.overrideWith((ref, query) async {
          expect(query.productId, 7);
          return _detail;
        }),
      ],
      child: MaterialApp(
        theme: ThemeData(platform: platform),
        builder: (_, child) => AppKeyboardDismissRegion(child: child!),
        locale: locale,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ru'), Locale('zh')],
        home: const Scaffold(
          body: SpOrganizerProductDetailScreen(productId: 7),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform _pumpDetail toolbar every field320height', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await _pumpDetail(
        tester,
        size: const Size(390, 640),
        locale: const Locale('ru'),
        platform: platform,
      );
      expect(await probeCurrentFormEditors(tester), 1);
    });
  }

  testWidgets('карточка товара помещается на ширине 320 px', (tester) async {
    await _pumpDetail(
      tester,
      size: const Size(320, 1800),
      locale: const Locale('ru'),
    );

    expect(find.text('Куртка демисезонная'), findsOneWidget);
    expect(find.text('Средняя цена'), findsOneWidget);
    expect(find.text('Полная история использования'), findsOneWidget);
    expect(find.text('СП июль'), findsOneWidget);
    expect(find.text('Иван Иванов'), findsOneWidget);
    expect(find.text('Выкуплен'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('карточка товара использует китайские подписи на 390 px', (
    tester,
  ) async {
    await _pumpDetail(
      tester,
      size: const Size(390, 1800),
      locale: const Locale('zh'),
    );

    expect(find.text('商品详情'), findsOneWidget);
    expect(find.text('平均售价'), findsOneWidget);
    expect(find.text('完整使用历史'), findsOneWidget);
    expect(find.text('采购使用历史'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
