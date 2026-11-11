import 'dart:io';
import '../../helpers/keyboard_acceptance.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/data/tracks_provider.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/domain/track_item.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/presentation/tracks_screen.dart';

class _FailingProductService extends TracksApiService {
  _FailingProductService(super.ref);

  @override
  Future<TrackReturnInfo?> getTrackReturn(int trackId) async => null;

  @override
  Future<bool> updateProductInfo({
    required int trackId,
    required String productName,
    required int quantity,
    File? imageFile,
    String? imageUrl,
  }) async => false;
}

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'failed server save keeps product editor and entered name ${platform.name}',
      (tester) async {
        await initializeDateFormatting('ru');
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetViewInsets);
        final now = DateTime(2026, 11, 9);
        final track = TrackItem(
          id: 42,
          code: 'AUDIT-PRODUCT',
          status: 'На складе',
          statusCode: 'in_warehouse',
          date: now,
          createdAt: now,
          updatedAt: now,
          productInfo: const ProductInfo(name: 'Старое название', quantity: 1),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              activeClientCodeProvider.overrideWithValue('2A-TEST'),
              trackStatusesProvider.overrideWith((ref) async => const []),
              assemblyStatusesProvider.overrideWith((ref) async => const []),
              tracksApiServiceProvider.overrideWith(_FailingProductService.new),
            ],
            child: MaterialApp(
              theme: ThemeData(fontFamily: 'Gilroy', platform: platform),
              builder: (context, child) =>
                  AppKeyboardDismissRegion(child: child!),
              home: Scaffold(body: TracksScreen.embedded(tracks: [track])),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('client-track-card-AUDIT-PRODUCT')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('client-track-detail-tab-0')),
        );
        await tester.pumpAndSettle();
        final comment = find.text('Добавить комментарий');
        await tester.ensureVisible(comment);
        await tester.tap(comment);
        await tester.pumpAndSettle();
        expect(await exerciseCurrentRouteEditors(tester), 1);
        await tester.ensureVisible(find.text('Отмена'));
        await tester.tap(find.text('Отмена'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Изменить информацию'),
          300,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('Изменить информацию'));
        await tester.pumpAndSettle();
        expect(await exerciseCurrentRouteEditors(tester), 2);
        final field = find.byType(TextField).first;
        await tester.enterText(field, 'Новое название');
        await tester.ensureVisible(find.text('Сохранить'));
        await tester.tap(find.text('Сохранить'));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsWidgets);
        expect(find.text('Новое название'), findsOneWidget);
        expect(find.text('Изменить информацию'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 4));
      },
    );
  }
}
