import 'package:twoalogisticcabineuser/src/core/branding/company_branding_provider.dart';
import 'package:flutter/material.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import '../keyboard/keyboard_form_probe.dart';
import '../../helpers/keyboard_acceptance.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_fulfillment_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_repository.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/presentation/sp_organizer_fulfillment_link_sheet.dart';

const _status = SpOrganizerFulfillmentStatus(
  code: 'in_warehouse',
  nameRu: 'На складе',
  nameZh: '已入库',
  color: '#2563EB',
  sortOrder: 20,
);

const _overview = SpOrganizerFulfillmentOverview(
  contractVersion: 1,
  mode: 'read_only',
  persisted: false,
  purchaseId: 17,
  items: [SpOrganizerFulfillmentItem(id: 5, title: 'Куртка')],
  summary: SpOrganizerFulfillmentSummary(itemsCount: 1),
);

const _capabilities = SpOrganizerCapabilities(
  contractVersion: 1,
  organizerV2: true,
  purchaseKinds: true,
  participants: true,
  products: true,
  calculationProfiles: true,
  fulfillmentOverview: true,
  selfBuyoutLinks: false,
  selfBuyout: SpOrganizerActionCapability.unavailable,
  garageImport: false,
  trackLinks: true,
  assemblyLinks: false,
  invoiceLinks: false,
  analytics: false,
);

class _FakeRepository extends SpOrganizerRepository {
  _FakeRepository() : super(ApiClient());

  int? linkedPurchaseId;
  int? linkedItemId;
  int? linkedTargetId;
  SpOrganizerFulfillmentLinkKind? linkedKind;

  @override
  Future<SpOrganizerFulfillmentCandidatePage> getFulfillmentCandidates({
    required int purchaseId,
    required SpOrganizerFulfillmentLinkKind kind,
    int? itemId,
    String? query,
    int page = 1,
    int limit = 20,
  }) async {
    return const SpOrganizerFulfillmentCandidatePage(
      kind: SpOrganizerFulfillmentLinkKind.track,
      candidates: [
        SpOrganizerFulfillmentCandidate(
          id: 41,
          title: 'TRACK-041',
          subtitle: '2A-00041',
          status: _status,
        ),
      ],
      total: 1,
      page: 1,
      limit: 20,
      totalPages: 1,
    );
  }

  @override
  Future<void> linkFulfillmentCandidate({
    required int purchaseId,
    required SpOrganizerFulfillmentLinkKind kind,
    required int targetId,
    int? itemId,
  }) async {
    linkedPurchaseId = purchaseId;
    linkedItemId = itemId;
    linkedTargetId = targetId;
    linkedKind = kind;
  }
}

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform fulfillment search actual modal320height', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 640);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            companyNameProvider.overrideWithValue('Partner Cargo'),
            spOrganizerRepositoryProvider.overrideWithValue(_FakeRepository()),
          ],
          child: MaterialApp(
            theme: ThemeData(platform: platform),
            builder: (_, child) => AppKeyboardDismissRegion(child: child!),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showSpOrganizerFulfillmentLinkSheet(
                    context: context,
                    purchaseId: 17,
                    overview: _overview,
                    capabilities: _capabilities,
                  ),
                  child: const Text('Связать'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Связать'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(await probeCurrentFormEditors(tester), 1);
    });
  }

  testWidgets('selector links an existing track at 320 px', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(320, 800));
    final repository = _FakeRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          companyNameProvider.overrideWithValue('Partner Cargo'),
          spOrganizerRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          locale: const Locale('ru'),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showSpOrganizerFulfillmentLinkSheet(
                    context: context,
                    purchaseId: 17,
                    overview: _overview,
                    capabilities: _capabilities,
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
    await tester.pumpAndSettle();

    expect(find.text('Связать с операцией Partner Cargo'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('TRACK-041'),
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
    expect(find.text('TRACK-041'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('TRACK-041'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TRACK-041'));
    await tester.pump();
    await tester.tap(find.text('Добавить связь'));
    await tester.pumpAndSettle();

    expect(repository.linkedPurchaseId, 17);
    expect(repository.linkedItemId, 5);
    expect(repository.linkedTargetId, 41);
    expect(repository.linkedKind, SpOrganizerFulfillmentLinkKind.track);
    expect(find.text('Связать с операцией Partner Cargo'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
