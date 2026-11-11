import 'package:flutter/material.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import '../keyboard/keyboard_form_probe.dart';
import '../../helpers/keyboard_acceptance.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_garage_import_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_repository.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_v2_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_v2_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/presentation/sp_organizer_garage_import_sheet.dart';

const _customer = SpV2Customer(id: 31, fullName: 'Участник E12');

const _candidate = SpOrganizerGarageImportCandidate(
  id: 701,
  orderId: 81,
  orderNumber: 'GO-E12-001',
  orderStatus: 'purchased',
  title: 'Тормозные колодки',
  manufacturer: 'Safe Brand',
  partNumber: 'PAD-E12',
  optionType: 'original',
  quantity: 2,
  unitPriceCny: 55,
  unitPriceRub: 715,
  purchaseStatus: 'purchased',
);

const _importedCandidate = SpOrganizerGarageImportCandidate(
  id: 702,
  orderId: 82,
  orderNumber: 'GO-E12-002',
  orderStatus: 'purchased',
  title: 'Уже добавленный фильтр',
  manufacturer: 'Filter Brand',
  partNumber: 'FLT-E12',
  optionType: 'analog',
  quantity: 1,
  unitPriceCny: 20,
  unitPriceRub: 260,
  purchaseStatus: 'purchased',
  imported: true,
  importedItemId: 991,
  importedCustomerId: 31,
);

class _FakeRepository extends SpOrganizerRepository {
  _FakeRepository() : super(ApiClient());

  int? importedPurchaseId;
  int? importedSourceId;
  int? importedCustomerId;

  @override
  Future<SpOrganizerGarageImportCandidatePage> getGarageImportCandidates({
    required int purchaseId,
    String? query,
    int page = 1,
    int limit = 20,
  }) async {
    return const SpOrganizerGarageImportCandidatePage(
      candidates: [_candidate, _importedCandidate],
      page: 1,
      limit: 20,
      total: 2,
      totalPages: 1,
    );
  }

  @override
  Future<bool> importGarageItem({
    required int purchaseId,
    required int garageOrderItemId,
    required int customerId,
  }) async {
    importedPurchaseId = purchaseId;
    importedSourceId = garageOrderItemId;
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
                onPressed: () => showSpOrganizerGarageImportSheet(
                  context: context,
                  purchaseId: 17,
                ),
                child: const Text('Открыть Garage'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Открыть Garage'));
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

  test('Garage page parses safe mixed fields and retry state', () {
    final page = SpOrganizerGarageImportCandidatePage.fromJson({
      'candidates': [
        {
          'id': '701',
          'orderId': 81,
          'orderNumber': ' GO-E12-001 ',
          'orderStatus': 'purchased',
          'title': ' Тормозные колодки ',
          'manufacturer': ' Safe Brand ',
          'partNumber': ' PAD-E12 ',
          'optionType': ' original ',
          'quantity': '2',
          'unitPriceCny': '55.5',
          'unitPriceRub': 721.5,
          'purchaseStatus': 'purchased',
          'photoUrls': [' item.jpg ', '', 7],
          'imported': true,
          'importedItemId': '991',
          'importedCustomerId': 31,
        },
      ],
      'pagination': {'page': '2', 'limit': 20, 'total': '41', 'totalPages': 3},
    });

    expect(page.page, 2);
    expect(page.hasMore, isTrue);
    expect(page.total, 41);
    expect(page.candidates.single.title, 'Тормозные колодки');
    expect(page.candidates.single.partLabel, 'Safe Brand · PAD-E12 · original');
    expect(page.candidates.single.unitPriceCny, 55.5);
    expect(page.candidates.single.unitPriceRub, 721.5);
    expect(page.candidates.single.photoUrls, ['item.jpg']);
    expect(page.candidates.single.importedItemId, 991);
  });

  testWidgets('imports a Garage item at 320 px', (tester) async {
    final repository = await _pumpSheet(tester, size: const Size(320, 800));

    expect(find.text('Добавить из Garage'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey('garage-import-customer-selector')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Участник E12').last);
    await tester.pumpAndSettle();
    expect(find.byType(ListView), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pump();
    await tester.tap(find.text('Тормозные колодки'));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -180));
    await tester.pump();

    expect(find.text('Уже добавлен'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('garage-import-submit')));
    await tester.pumpAndSettle();

    expect(repository.importedPurchaseId, 17);
    expect(repository.importedSourceId, 701);
    expect(repository.importedCustomerId, 31);
    expect(find.text('Добавить из Garage'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Garage cards fit 390 px', (tester) async {
    await _pumpSheet(tester, size: const Size(390, 800));

    expect(find.text('Тормозные колодки'), findsOneWidget);
    expect(find.text('GO-E12-001'), findsOneWidget);
    expect(find.text('Safe Brand · PAD-E12 · original'), findsOneWidget);
    expect(find.text('55 ¥/шт.'), findsOneWidget);
    expect(find.text('715 ₽/шт.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
