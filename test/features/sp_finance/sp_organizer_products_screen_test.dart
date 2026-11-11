import 'package:flutter/material.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import '../keyboard/keyboard_form_probe.dart';
import '../../helpers/keyboard_acceptance.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/presentation/sp_organizer_products_screen.dart';

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

const _products = [
  SpOrganizerProduct(
    id: 11,
    title: 'Куртка демисезонная',
    marketplaceCode: 'SKU-011',
    barcode: '460000000011',
    description: 'Карточка организатора без локальной копии расчётов.',
    itemsCount: 4,
  ),
  SpOrganizerProduct(
    id: 12,
    title: 'Брюки утеплённые',
    marketplaceCode: 'SKU-012',
    itemsCount: 2,
  ),
];

class _ProductsController extends SpOrganizerProductsController {
  @override
  SpOrganizerProductsState build() {
    return const SpOrganizerProductsState(
      products: _products,
      total: 2,
      page: 1,
      totalPages: 1,
    );
  }

  @override
  Future<void> load({
    bool silent = false,
    String? query,
    bool? includeArchived,
    String? sortBy,
    String? sortDirection,
  }) async {}
}

Future<void> _pumpProducts(
  WidgetTester tester, {
  required Size size,
  required Locale locale,
  bool embedded = false,
  NavigatorObserver? observer,
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
        spOrganizerProductsControllerProvider.overrideWith(
          _ProductsController.new,
        ),
      ],
      child: MaterialApp(
        builder: (_, child) => AppKeyboardDismissRegion(child: child!),
        navigatorObservers: [if (observer != null) observer],
        theme: ThemeData(platform: platform),
        locale: locale,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ru'), Locale('zh')],
        home: Scaffold(body: SpOrganizerProductsScreen(embedded: embedded)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      '$platform _pumpProducts actual create editor every field320height',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        await _pumpProducts(
          tester,
          size: const Size(390, 640),
          platform: platform,
          locale: const Locale('ru'),
        );
        expect(await probeCurrentFormEditors(tester), 1);
        await tester.ensureVisible(find.byTooltip('Добавить товар'));
        await tester.tap(find.byTooltip('Добавить товар'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(await probeCurrentFormEditors(tester, minimumFields: 5), 5);
      },
    );
  }

  testWidgets('embedded product tab omits the duplicate hero', (tester) async {
    await _pumpProducts(
      tester,
      size: const Size(390, 1000),
      locale: const Locale('ru'),
      embedded: true,
    );

    expect(find.text('Товары организатора'), findsNothing);
    expect(find.text('Куртка демисезонная'), findsOneWidget);
  });

  testWidgets('product catalog fits 320 px and labels icon-only add action', (
    tester,
  ) async {
    await _pumpProducts(
      tester,
      size: const Size(320, 1200),
      locale: const Locale('ru'),
    );

    expect(find.text('Товары организатора'), findsOneWidget);
    expect(find.text('Куртка демисезонная'), findsOneWidget);
    expect(find.text('Брюки утеплённые'), findsOneWidget);
    expect(find.byTooltip('Добавить товар'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Добавить товар' &&
            widget.properties.button == true,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('product catalog uses Chinese copy at 390 px', (tester) async {
    await _pumpProducts(
      tester,
      size: const Size(390, 1200),
      locale: const Locale('zh'),
    );

    expect(find.text('团长商品'), findsOneWidget);
    expect(find.text('显示归档'), findsOneWidget);
    expect(find.byTooltip('添加商品'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('product catalog omits manual sorting controls', (tester) async {
    await _pumpProducts(
      tester,
      size: const Size(320, 1200),
      locale: const Locale('ru'),
    );

    expect(find.byKey(const Key('sp-product-sort-button')), findsNothing);
    expect(find.text('По названию: А–Я'), findsNothing);
    expect(find.text('По названию: Я–А'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new product sheet exposes photo and QR upload blocks', (
    tester,
  ) async {
    await _pumpProducts(
      tester,
      size: const Size(320, 1000),
      locale: const Locale('ru'),
    );

    await tester.tap(find.byTooltip('Добавить товар'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.text('Новый товар'), findsOneWidget);
    expect(find.byKey(const Key('sp-product-main-photo')), findsOneWidget);
    expect(find.byKey(const Key('sp-product-qr-photo')), findsOneWidget);
    expect(
      find.byKey(const Key('sp-product-barcode-scan-button')),
      findsOneWidget,
    );
    expect(find.byTooltip('Сканировать штрихкод'), findsOneWidget);
    expect(find.text('Фото товара'), findsOneWidget);
    expect(find.text('QR-код'), findsOneWidget);
    expect(find.textContaining('до 20 МБ'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('product sheet ignores same-frame double tap and reopens', (
    tester,
  ) async {
    final observer = _CountingNavigatorObserver();
    await _pumpProducts(
      tester,
      size: const Size(390, 1000),
      locale: const Locale('ru'),
      observer: observer,
    );
    final addButton = find.byTooltip('Добавить товар');
    final pushesBefore = observer.pushes;

    await tester.tap(addButton);
    await tester.tap(addButton, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Новый товар'), findsOneWidget);
    expect(observer.pushes, pushesBefore + 1);

    Navigator.of(tester.element(find.text('Новый товар'))).pop();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(addButton);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Новый товар'), findsOneWidget);
    expect(observer.pushes, pushesBefore + 2);
  });

  testWidgets('Chinese product sheet keeps the QR-specific icon', (
    tester,
  ) async {
    await _pumpProducts(
      tester,
      size: const Size(390, 1000),
      locale: const Locale('zh'),
    );

    await tester.tap(find.byTooltip('添加商品'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    final qrCard = find.byKey(const Key('sp-product-qr-photo'));
    expect(qrCard, findsOneWidget);
    expect(
      find.descendant(
        of: qrCard,
        matching: find.byIcon(Icons.qr_code_2_rounded),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('product catalog uses a two-column grid on desktop', (
    tester,
  ) async {
    await _pumpProducts(
      tester,
      size: const Size(1024, 1200),
      locale: const Locale('ru'),
    );

    final first = tester.getTopLeft(find.text('Куртка демисезонная'));
    final second = tester.getTopLeft(find.text('Брюки утеплённые'));
    expect((first.dy - second.dy).abs(), lessThan(8));
    expect(second.dx, greaterThan(first.dx + 300));
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
