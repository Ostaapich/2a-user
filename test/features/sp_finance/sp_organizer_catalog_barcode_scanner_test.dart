import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_repository.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_v2_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_v2_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/presentation/sp_organizer_catalog_item_sheet.dart';

const _barcode = '460000000011';

const _purchase = SpV2Purchase(
  id: 17,
  title: 'Закупка июля',
  status: 'open',
  statusLabel: 'Принимает товары',
  isAcceptingItems: true,
);

const _participants = SpOrganizerParticipantList(
  source: 'participants',
  participants: [
    SpOrganizerParticipant(
      id: 71,
      spPurchaseId: 17,
      spCustomerId: 31,
      displayOrder: 0,
      legacyDerived: false,
      customer: SpOrganizerParticipantCustomer(
        id: 31,
        fullName: 'Участник теста',
        displayName: 'Участник теста',
        isOrganizerSelf: false,
      ),
    ),
  ],
);

class _FakeRepository extends SpOrganizerRepository {
  _FakeRepository() : super(ApiClient());

  final queries = <String?>[];

  @override
  Future<SpOrganizerProductPage> getProducts({
    String? query,
    int page = 1,
    int limit = 40,
    bool includeArchived = false,
    String sortBy = 'title',
    String sortDirection = 'asc',
  }) async {
    queries.add(query);
    return const SpOrganizerProductPage(
      items: [
        SpOrganizerProduct(
          id: 11,
          title: 'Куртка демисезонная',
          barcode: _barcode,
        ),
      ],
      total: 1,
      page: 1,
      limit: 40,
      totalPages: 1,
    );
  }
}

class _DeferredRepository extends SpOrganizerRepository {
  _DeferredRepository() : super(ApiClient());

  final requests = <String, Completer<SpOrganizerProductPage>>{};

  @override
  Future<SpOrganizerProductPage> getProducts({
    String? query,
    int page = 1,
    int limit = 40,
    bool includeArchived = false,
    String sortBy = 'title',
    String sortDirection = 'asc',
  }) {
    final normalized = query ?? '';
    if (normalized.isEmpty) {
      return Future.value(
        const SpOrganizerProductPage(
          items: [],
          total: 0,
          page: 1,
          limit: 40,
          totalPages: 0,
        ),
      );
    }
    return (requests[normalized] ??= Completer<SpOrganizerProductPage>())
        .future;
  }
}

SpOrganizerProductPage _page(String title, int id) => SpOrganizerProductPage(
  items: [SpOrganizerProduct(id: id, title: title)],
  total: 1,
  page: 1,
  limit: 40,
  totalPages: 1,
);

void main() {
  testWidgets('camera result becomes a server catalog query and exact match', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 900));
    final repository = _FakeRepository();
    var scannerCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          spOrganizerRepositoryProvider.overrideWithValue(repository),
          spV2PurchaseDetailProvider(17).overrideWith((ref) async => _purchase),
          spOrganizerParticipantsProvider(
            17,
          ).overrideWith((ref) async => _participants),
        ],
        child: MaterialApp(
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
                  onPressed: () => showSpOrganizerCatalogItemSheet(
                    context: context,
                    purchaseId: 17,
                    barcodeScanner: (context) async {
                      scannerCalls++;
                      return '  $_barcode  ';
                    },
                  ),
                  child: const Text('Открыть'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(
      find.byKey(const Key('sp-catalog-barcode-scan-button')),
      findsOneWidget,
    );
    expect(find.byTooltip('Сканировать штрихкод'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sp-catalog-barcode-scan-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(scannerCalls, 1);
    expect(repository.queries.last, _barcode);
    final searchField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('sp-catalog-search-field')),
        matching: find.byType(TextField),
      ),
    );
    expect(searchField.controller?.text, _barcode);
    final beforeClear = repository.queries.length;
    await tester.tap(find.byTooltip('Очистить поиск'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(searchField.controller?.text, '');
    expect(repository.queries.last, '');
    expect(repository.queries.length, beforeClear + 1);
    expect(scannerCalls, 1);
    expect(
      find.byKey(const Key('sp-catalog-barcode-scan-button')),
      findsOneWidget,
    );
    expect(find.text('Параметры позиции'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('older catalog response cannot overwrite a newer query', (
    tester,
  ) async {
    final repository = _DeferredRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          spOrganizerRepositoryProvider.overrideWithValue(repository),
          spV2PurchaseDetailProvider(17).overrideWith((ref) async => _purchase),
          spOrganizerParticipantsProvider(
            17,
          ).overrideWith((ref) async => _participants),
        ],
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ru'), Locale('zh')],
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showSpOrganizerCatalogItemSheet(
                  context: context,
                  purchaseId: 17,
                  barcodeScanner: (_) async => null,
                ),
                child: const Text('Открыть'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();

    final search = find.byKey(const Key('sp-catalog-search-field'));
    await tester.enterText(search, 'old');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(search, 'new');
    await tester.pump(const Duration(milliseconds: 400));

    repository.requests['new']!.complete(_page('Новый результат', 2));
    await tester.pump();
    expect(find.text('Новый результат'), findsOneWidget);

    repository.requests['old']!.complete(_page('Устаревший результат', 1));
    await tester.pump();
    expect(find.text('Новый результат'), findsOneWidget);
    expect(find.text('Устаревший результат'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
