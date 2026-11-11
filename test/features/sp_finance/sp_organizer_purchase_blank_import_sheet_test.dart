import 'package:flutter/material.dart';
import '../../helpers/keyboard_acceptance.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_purchase_blank_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_repository.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_v2_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_v2_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/presentation/sp_organizer_purchase_blank_import_sheet.dart';

const _customer = SpV2Customer(id: 31, fullName: 'Участник теста');

const _candidate = SpOrganizerPurchaseBlankCandidate(
  id: 501,
  blankId: 77,
  blankStatus: 'completed',
  orderNumber: 3,
  title: 'Синяя куртка',
  characteristics: 'Размер M',
  quantity: 2,
  unitPriceYuan: 88.5,
  trackNumber: 'PB-TRACK-501',
);

const _importedCandidate = SpOrganizerPurchaseBlankCandidate(
  id: 502,
  blankId: 78,
  blankStatus: 'completed',
  orderNumber: 1,
  title: 'Уже добавленный товар',
  quantity: 1,
  unitPriceYuan: 20,
  imported: true,
  importedItemId: 900,
  importedCustomerId: 31,
);

class _FakeRepository extends SpOrganizerRepository {
  _FakeRepository() : super(ApiClient());

  int? importedPurchaseId;
  int? importedSourceId;
  int? importedCustomerId;

  @override
  Future<SpOrganizerPurchaseBlankCandidatePage>
  getPurchaseBlankImportCandidates({
    required int purchaseId,
    String? query,
    int page = 1,
    int limit = 20,
  }) async {
    return const SpOrganizerPurchaseBlankCandidatePage(
      candidates: [_candidate, _importedCandidate],
      page: 1,
      limit: 20,
      total: 2,
      totalPages: 1,
    );
  }

  @override
  Future<bool> importPurchaseBlankItem({
    required int purchaseId,
    required int purchaseBlankItemId,
    required int customerId,
  }) async {
    importedPurchaseId = purchaseId;
    importedSourceId = purchaseBlankItemId;
    importedCustomerId = customerId;
    return true;
  }
}

Future<void> _pumpSheet(
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
        builder: (context, child) => AppKeyboardDismissRegion(child: child!),
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
                onPressed: () => showSpOrganizerPurchaseBlankImportSheet(
                  context: context,
                  purchaseId: 17,
                ),
                child: const Text('Открыть импорт'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Открыть импорт'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      '$platform import search stays above keyboard without double inset',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        await _pumpSheet(
          tester,
          size: const Size(390, 700),
          platform: platform,
        );
        final search = find.byType(TextField).first;
        await tester.ensureVisible(search);
        await tester.tap(search);
        await tester.pump();
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(MediaQuery.viewInsetsOf(tester.element(search)).bottom, 0);
        expectFocusedCaretAboveIme(
          tester,
          find.byType(EditableText).first,
          keyboardTop:
              tester.view.physicalSize.height / tester.view.devicePixelRatio -
              tester.view.viewInsets.bottom / tester.view.devicePixelRatio,
        );
        await tester.ensureVisible(search);
        await tester.pumpAndSettle();
        expect(tester.getBottomLeft(search).dy, lessThanOrEqualTo(400));
        await tester.tap(
          find.text('Импорт из бланка выкупа').first,
          warnIfMissed: false,
        );
        await tester.pump();
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText).first)
              .focusNode
              .hasFocus,
          isFalse,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }

  test('candidate page parses pagination, money and retry state', () {
    final page = SpOrganizerPurchaseBlankCandidatePage.fromJson({
      'candidates': [
        {
          'id': '501',
          'blankId': 77,
          'blankStatus': 'completed',
          'orderNumber': '3',
          'title': ' Синяя куртка ',
          'quantity': '2',
          'unitPriceYuan': '88.5',
          'photoUrls': [' a.jpg ', '', 7],
          'imported': true,
          'importedItemId': '900',
          'importedCustomerId': 31,
        },
      ],
      'pagination': {'page': '2', 'limit': 20, 'total': '41', 'totalPages': 3},
    });

    expect(page.page, 2);
    expect(page.hasMore, isTrue);
    expect(page.total, 41);
    expect(page.candidates.single.title, 'Синяя куртка');
    expect(page.candidates.single.unitPriceYuan, 88.5);
    expect(page.candidates.single.photoUrls, ['a.jpg']);
    expect(page.candidates.single.imported, isTrue);
    expect(page.candidates.single.importedItemId, 900);
  });

  testWidgets('imports selected Purchase Blank item at 320 px', (tester) async {
    await _pumpSheet(tester, size: const Size(320, 800));
    final container = ProviderScope.containerOf(
      tester.element(find.text('Импорт из бланка выкупа')),
    );
    final repository =
        container.read(spOrganizerRepositoryProvider) as _FakeRepository;

    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey('purchase-blank-customer-selector')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Участник теста').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Синяя куртка'),
      180,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .last,
    );
    expect(find.text('Синяя куртка'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Синяя куртка'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Уже импортирован'),
      160,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .last,
    );
    expect(find.text('Уже импортирован'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(
      find.byKey(const ValueKey('purchase-blank-import-submit')),
    );
    await tester.pumpAndSettle();

    expect(repository.importedPurchaseId, 17);
    expect(repository.importedSourceId, 501);
    expect(repository.importedCustomerId, 31);
    expect(find.text('Импорт из бланка выкупа'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sheet keeps compact layout at 390 px', (tester) async {
    await _pumpSheet(tester, size: const Size(390, 800));

    // The shared mobile top gap leaves a shorter viewport; lazy rows remain
    // reachable by scrolling instead of all being built above the fold.
    await tester.scrollUntilVisible(
      find.text('Синяя куртка'),
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
    expect(find.text('Синяя куртка'), findsOneWidget);
    expect(find.text('PB-TRACK-501'), findsOneWidget);
    expect(find.text('Бланк №77 · #3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
