import 'package:flutter/material.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import '../keyboard/keyboard_form_probe.dart';
import '../../helpers/keyboard_acceptance.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/core/branding/company_branding_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_previous_purchase_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_repository.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_v2_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_v2_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/presentation/sp_organizer_previous_purchase_import_sheet.dart';

const _customer = SpV2Customer(id: 31, fullName: 'Участник E11');

const _candidate = SpOrganizerPreviousPurchaseCandidate(
  id: 601,
  sourcePurchaseId: 41,
  sourcePurchaseTitle: 'Закупка весна',
  sourcePurchaseCurrency: 'CNY',
  sourceCustomerId: 18,
  sourceCustomerName: 'Прошлый участник',
  title: 'Повторяемая куртка',
  quantity: 2,
  sourceStatus: 'delivered',
  purchasePriceYuan: 88.5,
);

const _importedCandidate = SpOrganizerPreviousPurchaseCandidate(
  id: 602,
  sourcePurchaseId: 42,
  sourcePurchaseTitle: 'Закупка зима',
  sourcePurchaseCurrency: 'RUB',
  sourceCustomerId: 19,
  sourceCustomerName: 'Другой участник',
  title: 'Уже скопированный товар',
  quantity: 1,
  sourceStatus: 'delivered',
  costPriceRub: 1500,
  imported: true,
  importedItemId: 990,
  importedCustomerId: 31,
);

class _FakeRepository extends SpOrganizerRepository {
  _FakeRepository() : super(ApiClient());

  int? importedPurchaseId;
  int? importedSourceId;
  int? importedCustomerId;

  @override
  Future<SpOrganizerPreviousPurchaseCandidatePage>
  getPreviousPurchaseImportCandidates({
    required int purchaseId,
    String? query,
    int page = 1,
    int limit = 20,
  }) async {
    return const SpOrganizerPreviousPurchaseCandidatePage(
      candidates: [_candidate, _importedCandidate],
      page: 1,
      limit: 20,
      total: 2,
      totalPages: 1,
    );
  }

  @override
  Future<bool> importPreviousPurchaseItem({
    required int purchaseId,
    required int sourceSpItemId,
    required int customerId,
  }) async {
    importedPurchaseId = purchaseId;
    importedSourceId = sourceSpItemId;
    importedCustomerId = customerId;
    return true;
  }
}

Future<_FakeRepository> _pumpSheet(
  WidgetTester tester, {
  required Size size,
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
        spV2CustomersProvider.overrideWith((ref) async => const [_customer]),
      ],
      child: MaterialApp(
        theme: ThemeData(platform: platform),
        builder: (_, child) => AppKeyboardDismissRegion(child: child!),
        locale: const Locale('ru'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ru'), Locale('zh')],
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showSpOrganizerPreviousPurchaseImportSheet(
                  context: context,
                  purchaseId: 17,
                ),
                child: const Text('Открыть прошлые товары'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Открыть прошлые товары'));
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform import search automatic caret320height', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await _pumpSheet(tester, size: const Size(390, 640), platform: platform);
      expect(await probeCurrentFormEditors(tester), 1);
    });
  }

  test(
    'previous purchase page parses mixed numeric fields and retry state',
    () {
      final page = SpOrganizerPreviousPurchaseCandidatePage.fromJson({
        'candidates': [
          {
            'id': '601',
            'sourcePurchaseId': 41,
            'sourcePurchaseTitle': ' Закупка весна ',
            'sourcePurchaseCurrency': 'CNY',
            'sourceCustomerId': '18',
            'sourceCustomerName': ' Прошлый участник ',
            'title': ' Повторяемая куртка ',
            'quantity': '2',
            'sourceStatus': 'delivered',
            'purchasePriceYuan': '88.5',
            'declaredWeightKg': 1.2,
            'photoUrls': [' item.jpg ', '', 7],
            'imported': true,
            'importedItemId': '990',
            'importedCustomerId': 31,
          },
        ],
        'pagination': {
          'page': '2',
          'limit': 20,
          'total': '41',
          'totalPages': 3,
        },
      });

      expect(page.page, 2);
      expect(page.hasMore, isTrue);
      expect(page.total, 41);
      expect(page.candidates.single.title, 'Повторяемая куртка');
      expect(page.candidates.single.sourceCustomerName, 'Прошлый участник');
      expect(page.candidates.single.purchasePriceYuan, 88.5);
      expect(page.candidates.single.declaredWeightKg, 1.2);
      expect(page.candidates.single.photoUrls, ['item.jpg']);
      expect(page.candidates.single.importedItemId, 990);
    },
  );

  testWidgets('imports a previous purchase item at 320 px', (tester) async {
    final repository = await _pumpSheet(tester, size: const Size(320, 800));

    expect(find.text('Товар из прошлой закупки'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey('previous-purchase-customer-selector')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Участник E11').last);
    await tester.pumpAndSettle();
    expect(find.byType(ListView), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pump();
    expect(find.text('Повторяемая куртка'), findsOneWidget);
    await tester.tap(find.text('Повторяемая куртка'));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -180));
    await tester.pump();

    expect(find.text('Уже добавлен'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey('previous-purchase-import-submit')),
    );
    await tester.pumpAndSettle();

    expect(repository.importedPurchaseId, 17);
    expect(repository.importedSourceId, 601);
    expect(repository.importedCustomerId, 31);
    expect(find.text('Товар из прошлой закупки'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('previous purchase cards fit 390 px', (tester) async {
    await _pumpSheet(tester, size: const Size(390, 800));
    await tester.scrollUntilVisible(
      find.text('Повторяемая куртка'),
      180,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .last,
    );
    await tester.pumpAndSettle();

    expect(find.text('Повторяемая куртка'), findsOneWidget);
    expect(find.text('Закупка весна'), findsOneWidget);
    expect(find.text('Прошлый участник'), findsOneWidget);
    expect(find.text('88.5 ¥/шт.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
