import 'package:twoalogisticcabineuser/src/core/branding/company_branding_provider.dart';
import 'package:flutter/material.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import '../keyboard/keyboard_form_probe.dart';
import '../../helpers/keyboard_acceptance.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_customer_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_repository.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/presentation/sp_organizer_customer_detail_screen.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/presentation/sp_organizer_customers_screen.dart';

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

final _customerPage = SpOrganizerCustomerPage.fromJson({
  'items': [
    {
      'id': 7,
      'fullName': 'Анна Петрова',
      'phone': '+7 900 000-00-00',
      'telegram': '@anna',
      'city': 'Казань',
      'metrics': {
        'purchasesCount': 2,
        'itemsCount': 4,
        'turnoverRub': 565,
        'paidRub': 160,
        'balanceRub': 405,
        'debtRub': 405,
        'profitRub': 130,
        'lastPurchase': {
          'id': 17,
          'title': 'Закупка января',
          'status': 'collecting_payments',
          'kind': 'group',
        },
      },
    },
  ],
  'total': 1,
  'page': 1,
  'limit': 30,
  'totalPages': 1,
  'scope': 'active',
  'mode': 'read_only',
  'persisted': false,
});

final _customerDetail = SpOrganizerCustomerDetail.fromJson({
  'customer': {
    'id': 7,
    'fullName': 'Анна Петрова',
    'phone': '+7 900 000-00-00',
    'telegram': '@anna',
    'city': 'Казань',
    'comment': 'Позвонить перед отправкой',
  },
  'metrics': {
    'purchasesCount': 2,
    'itemsCount': 4,
    'turnoverRub': 565,
    'paidRub': 160,
    'balanceRub': 405,
    'debtRub': 405,
    'profitRub': 130,
  },
  'history': {
    'items': [
      {
        'id': 17,
        'title': 'Закупка января',
        'status': 'collecting_payments',
        'kind': 'group',
        'createdAt': '2026-01-10T00:00:00.000Z',
        'metrics': {
          'itemsCount': 1,
          'turnoverRub': 225,
          'paidRub': 100,
          'balanceRub': 125,
          'profitRub': 55,
        },
        'items': [
          {
            'id': 171,
            'title': 'Куртка',
            'status': 'purchased',
            'quantity': 1,
            'totalDueRub': 225,
          },
        ],
        'payments': [
          {
            'id': 1710,
            'type': 'goods_payment',
            'status': 'paid',
            'amountRub': 100,
          },
        ],
        'shipments': [
          {
            'id': 17100,
            'carrierName': 'СДЭК',
            'trackingNumber': 'TRACK-001',
            'status': 'sent',
          },
        ],
      },
    ],
    'total': 1,
    'page': 1,
    'limit': 20,
    'totalPages': 1,
  },
  'mode': 'read_only',
  'persisted': false,
  'financialScope': 'organizer_customer_ledger',
});

class _FakeRepository extends SpOrganizerRepository {
  _FakeRepository() : super(ApiClient());

  String? lastScope;
  String? lastSortBy;
  String? lastSortDirection;

  @override
  Future<SpOrganizerCapabilities> getCapabilities() async => _capabilities;

  @override
  Future<SpOrganizerCustomerPage> getCustomersDirectory({
    String? query,
    String scope = 'active',
    int page = 1,
    int limit = 30,
    String sortBy = 'fullName',
    String sortDirection = 'asc',
  }) async {
    lastScope = scope;
    lastSortBy = sortBy;
    lastSortDirection = sortDirection;
    return scope == 'archived'
        ? const SpOrganizerCustomerPage(scope: 'archived', mode: 'read_only')
        : _customerPage;
  }

  @override
  Future<SpOrganizerCustomerDetail> getCustomerDetail(
    int customerId, {
    int page = 1,
    int limit = 20,
  }) async {
    return _customerDetail;
  }
}

Future<_FakeRepository> _pump(
  WidgetTester tester, {
  required Widget child,
  required Size size,
  required Locale locale,
  TargetPlatform platform = TargetPlatform.android,
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
        theme: ThemeData(platform: platform),
        builder: (_, child) => AppKeyboardDismissRegion(child: child!),
        locale: locale,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ru'), Locale('zh')],
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return repository;
}

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform _pump toolbar every field320height', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await _pump(
        tester,
        child: const SpOrganizerCustomersScreen(),
        size: const Size(390, 640),
        locale: const Locale('ru'),
        platform: platform,
      );
      expect(await probeCurrentFormEditors(tester), 1);
    });
  }

  testWidgets('embedded customer tab omits the duplicate hero', (tester) async {
    await _pump(
      tester,
      child: const SpOrganizerCustomersScreen(embedded: true),
      size: const Size(390, 1000),
      locale: const Locale('ru'),
    );

    expect(find.text('Вся клиентская база'), findsNothing);
    expect(find.text('Анна Петрова'), findsOneWidget);
  });

  testWidgets('customer directory fits 320 px and switches server scope', (
    tester,
  ) async {
    final repository = await _pump(
      tester,
      child: const SpOrganizerCustomersScreen(),
      size: const Size(320, 1000),
      locale: const Locale('ru'),
    );

    expect(find.text('Вся клиентская база'), findsOneWidget);
    expect(find.text('Анна Петрова'), findsOneWidget);
    expect(find.text('Отдельный внутренний учёт'), findsOneWidget);
    expect(repository.lastScope, 'active');
    expect(repository.lastSortBy, 'fullName');
    expect(repository.lastSortDirection, 'asc');
    expect(find.byKey(const Key('sp-customer-sort-button')), findsNothing);
    expect(find.text('Имя: А–Я'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Архив'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(repository.lastScope, 'archived');
    expect(find.text('Архив пуст'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer directory uses Chinese labels at 390 px', (
    tester,
  ) async {
    await _pump(
      tester,
      child: const SpOrganizerCustomersScreen(),
      size: const Size(390, 1000),
      locale: const Locale('zh'),
    );

    expect(find.text('完整客户库'), findsOneWidget);
    expect(find.text('独立内部账本'), findsOneWidget);
    expect(find.text('客户'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer detail fits 320 px and shows separate ledger', (
    tester,
  ) async {
    await _pump(
      tester,
      child: const SpOrganizerCustomerDetailScreen(customerId: 7),
      size: const Size(320, 1300),
      locale: const Locale('ru'),
    );

    expect(find.text('Анна Петрова'), findsWidgets);
    expect(find.text('Баланс внутри СП'), findsOneWidget);
    expect(find.text('История закупок'), findsOneWidget);
    expect(find.text('Закупка января'), findsOneWidget);
    expect(find.textContaining('Куртка'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer detail uses Chinese labels at 390 px', (tester) async {
    await _pump(
      tester,
      child: const SpOrganizerCustomerDetailScreen(customerId: 7),
      size: const Size(390, 1300),
      locale: const Locale('zh'),
    );

    expect(find.text('拼团内部余额'), findsOneWidget);
    expect(find.text('采购历史'), findsOneWidget);
    expect(find.text('联系方式与配送'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer directory fits desktop width', (tester) async {
    await _pump(
      tester,
      child: const SpOrganizerCustomersScreen(),
      size: const Size(1024, 1200),
      locale: const Locale('ru'),
    );

    expect(find.text('Вся клиентская база'), findsOneWidget);
    expect(find.text('Анна Петрова'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer detail fits desktop width', (tester) async {
    await _pump(
      tester,
      child: const SpOrganizerCustomerDetailScreen(customerId: 7),
      size: const Size(1024, 1400),
      locale: const Locale('ru'),
    );

    expect(find.text('История закупок'), findsOneWidget);
    expect(find.text('Контакты и доставка'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
