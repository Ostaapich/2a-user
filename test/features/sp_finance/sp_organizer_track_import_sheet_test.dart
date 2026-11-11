import 'package:twoalogisticcabineuser/src/features/tracks/data/tracks_provider.dart';
import 'package:flutter/material.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import '../keyboard/keyboard_form_probe.dart';
import '../../helpers/keyboard_acceptance.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_cached_media_image.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_repository.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_track_import_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_v2_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_v2_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/presentation/sp_organizer_track_import_sheet.dart';

const _customer = SpV2Customer(id: 31, fullName: 'Участник трека');

const _candidate = SpOrganizerTrackImportCandidate(
  id: 701,
  trackNumber: 'YT-SP-701-CN',
  status: 'in_warehouse',
  clientCode: 'E12',
  title: 'Куртка из трека',
  quantity: 2,
  photoUrls: ['https://example.test/track-701.jpg'],
);

const _linkedCandidate = SpOrganizerTrackImportCandidate(
  id: 702,
  trackNumber: 'YT-SP-702-CN',
  status: 'received',
  clientCode: 'E12',
  title: 'Уже добавленный товар',
  quantity: 1,
  linkedItemIds: [991],
  linkedCustomerIds: [31],
);

class _FakeRepository extends SpOrganizerRepository {
  _FakeRepository() : super(ApiClient());

  int? importedPurchaseId;
  int? importedTrackId;
  int? importedCustomerId;
  int importCalls = 0;

  @override
  Future<SpOrganizerTrackImportCandidatePage> getTrackImportCandidates({
    required int purchaseId,
    String? query,
    int page = 1,
    int limit = 20,
  }) async {
    return const SpOrganizerTrackImportCandidatePage(
      candidates: [_candidate, _linkedCandidate],
      page: 1,
      limit: 20,
      total: 2,
      totalPages: 1,
    );
  }

  @override
  Future<bool> importTrackItem({
    required int purchaseId,
    required int trackId,
    required int customerId,
  }) async {
    importCalls += 1;
    importedPurchaseId = purchaseId;
    importedTrackId = trackId;
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
        trackStatusesProvider.overrideWith(
          (ref) async => const [
            TrackStatus(
              id: 1,
              type: 'track',
              code: 'in_warehouse',
              nameRu: 'На складе',
              nameZh: '已入库',
              sortOrder: 1,
              isActive: true,
            ),
          ],
        ),
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
                onPressed: () => showSpOrganizerTrackImportSheet(
                  context: context,
                  purchaseId: 17,
                ),
                child: const Text('Открыть треки'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Открыть треки'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 500));
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

  test('track import page parses safe snapshot fields', () {
    final page = SpOrganizerTrackImportCandidatePage.fromJson({
      'candidates': [
        {
          'id': '701',
          'trackNumber': ' YT-SP-701-CN ',
          'status': 'in_warehouse',
          'clientCode': ' E12 ',
          'title': ' Куртка из трека ',
          'quantity': '2',
          'photoUrls': [' track.jpg ', '', 7],
          'linkedItemIds': ['991', 992],
          'linkedCustomerIds': [31, '32'],
        },
      ],
      'pagination': {'page': '2', 'limit': 20, 'total': '41', 'totalPages': 3},
    });

    expect(page.page, 2);
    expect(page.hasMore, isTrue);
    expect(page.total, 41);
    expect(page.candidates.single.trackNumber, 'YT-SP-701-CN');
    expect(page.candidates.single.title, 'Куртка из трека');
    expect(page.candidates.single.photoUrls, ['track.jpg']);
    expect(page.candidates.single.linkedItemIds, [991, 992]);
    expect(page.candidates.single.isLinkedToCustomer(32), isTrue);
  });

  testWidgets('imports a track snapshot at 320 px', (tester) async {
    final repository = await _pumpSheet(tester, size: const Size(320, 800));

    expect(find.text('Добавить из трека'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final trackList = find.byKey(const ValueKey('track-import-list'));
    await tester.drag(trackList, const Offset(0, -130));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('track-import-customer-selector')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Участник трека').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.drag(trackList, const Offset(0, -320));
    await tester.pump();
    expect(find.text('Куртка из трека'), findsOneWidget);
    expect(find.text('YT-SP-701-CN'), findsOneWidget);
    await Scrollable.ensureVisible(
      tester.element(find.text('Куртка из трека')),
      alignment: 0.5,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Куртка из трека'));
    await tester.pump();
    await tester.drag(trackList, const Offset(0, -220));
    await tester.pump();

    expect(find.text('Уже у участника'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('track-import-submit')));
    await tester.tap(
      find.byKey(const ValueKey('track-import-submit')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(repository.importedPurchaseId, 17);
    expect(repository.importedTrackId, 701);
    expect(repository.importedCustomerId, 31);
    expect(repository.importCalls, 1);
    expect(find.text('Добавить из трека'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('track card shows photo title and number at 390 px', (
    tester,
  ) async {
    await _pumpSheet(tester, size: const Size(390, 800));
    await tester.drag(
      find.byKey(const ValueKey('track-import-list')),
      const Offset(0, -300),
    );
    await tester.pump();

    expect(find.text('Куртка из трека'), findsOneWidget);
    expect(find.text('YT-SP-701-CN'), findsOneWidget);
    expect(find.text('2 шт.'), findsOneWidget);
    expect(find.byType(AppCachedMediaImage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
