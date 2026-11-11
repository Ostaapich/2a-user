import '../../helpers/keyboard_acceptance.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/data/tracks_provider.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/domain/track_item.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/presentation/tracks_screen.dart';

class _MockApiClient extends Mock implements ApiClient {}

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'completed return keeps its code editor available ${platform.name}',
      (tester) async {
        await initializeDateFormatting('ru');
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetViewInsets);
        final api = _MockApiClient();
        when(
          () => api.get(
            '/client/tracks/42/return',
            options: any(named: 'options'),
          ),
        ).thenAnswer(
          (_) async => Response<Map<String, dynamic>>(
            requestOptions: RequestOptions(path: '/client/tracks/42/return'),
            statusCode: 200,
            data: {
              'id': 7,
              'returnCode': 'OLD-RETURN-CODE',
              'status': 'completed',
              'createdAt': '2026-09-01T08:00:00.000Z',
            },
          ),
        );
        final now = DateTime(2026, 9, 1);
        final track = TrackItem(
          id: 42,
          code: 'COMPLETED-RETURN-42',
          status: 'Возвращён',
          statusCode: 'returned',
          date: now,
          createdAt: now,
          updatedAt: now,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(api),
              activeClientCodeProvider.overrideWithValue('2A-TEST'),
              trackStatusesProvider.overrideWith((ref) async => const []),
              assemblyStatusesProvider.overrideWith((ref) async => const []),
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
          find.byKey(const ValueKey('client-track-card-COMPLETED-RETURN-42')),
        );
        await tester.pumpAndSettle();
        final returnTab = find.byKey(
          const ValueKey('client-track-detail-tab-4'),
        );
        await tester.ensureVisible(returnTab);
        await tester.pumpAndSettle();
        await tester.tap(returnTab);
        await tester.pumpAndSettle();

        expect(find.text('OLD-RETURN-CODE'), findsOneWidget);
        final editButton = find.text('Изменить код возврата');
        expect(editButton, findsOneWidget);
        await tester.ensureVisible(editButton);
        await tester.tap(editButton);
        await tester.pumpAndSettle();

        expect(find.text('Новый код возврата'), findsOneWidget);
        expect(find.text('Сохранить код'), findsOneWidget);
        final editor = tester.widget<TextFormField>(find.byType(TextFormField));
        expect(editor.initialValue, 'OLD-RETURN-CODE');
        expect(await exerciseCurrentRouteEditors(tester), 1);
        await tester.enterText(
          find.byType(TextFormField),
          'REPLACEMENT-RETURN-CODE',
        );
        expect(find.text('REPLACEMENT-RETURN-CODE'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
