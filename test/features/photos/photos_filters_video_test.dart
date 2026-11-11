import '../../helpers/keyboard_acceptance.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_input_decoration.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/photos/data/photos_provider.dart';
import 'package:twoalogisticcabineuser/src/features/photos/presentation/photos_screen.dart';

class _Api extends ApiClient {
  final queries = <Map<String, dynamic>>[];
  @override
  Future<String?> getToken() async => null;
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    queries.add(Map.of(queryParameters ?? {}));
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data:
          {
                'total': 1,
                'data': [
                  {
                    'id': 'video:12',
                    'url': '/report.mp4',
                    'mimeType': 'video/mp4',
                    'trackNumber': 'TRACK-VIDEO',
                    'createdAt': '2026-11-09T10:00:00Z',
                  },
                ],
              }
              as T,
    );
  }
}

Future<void> _tick(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    await loadKeyboardAcceptanceFonts();
    await initializeDateFormatting('ru');
  });
  for (final width in [320.0, 390.0]) {
    testWidgets('photos filters and video-only report at $width', (t) async {
      SharedPreferences.setMockInitialValues({});
      t.view.physicalSize = Size(width, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final api = _Api();
      await t.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            apiClientProvider.overrideWithValue(api),
            activeClientCodeProvider.overrideWithValue('TEST'),
            photosRealtimeBridgeProvider.overrideWith((ref) {}),
          ],
          child: MaterialApp(
            theme: ThemeData(fontFamily: 'Gilroy'),
            locale: const Locale('ru'),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('ru')],
            home: const Scaffold(body: PhotosScreen()),
          ),
        ),
      );
      await _tick(t);
      final frame = find.byType(AppOutlinedInputFrame);
      expect(frame, findsOneWidget);
      expect(t.widget<AppOutlinedInputFrame>(frame).height, 48);
      final calendar = find.byTooltip('Выбрать дату');
      expect(t.getSize(calendar), const Size(48, 48));
      expect(t.getCenter(frame).dy, t.getCenter(calendar).dy);
      expect(api.queries, isNotEmpty);
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Открыть видеоотчёт',
        ),
        findsOneWidget,
      );
      expect(api.queries.last['includeVideos'], true);
      await t.enterText(find.byType(TextField), 'TRACK');
      await t.pump(const Duration(milliseconds: 400));
      await _tick(t);
      expect(api.queries.last['search'], 'TRACK');
      await t.tap(find.byTooltip('Очистить поиск'));
      await _tick(t);
      expect(api.queries.last['search'], isNull);
      await t.tap(calendar);
      await _tick(t);
      expect(find.byType(CalendarDatePicker), findsOneWidget);
      await t.tap(find.text('1').last);
      await t.tap(find.text('Применить'));
      await _tick(t);
      expect(api.queries.last['date'], isNotNull);
      expect(find.byType(InputChip), findsOneWidget);
      await t.tap(find.byTooltip('Сбросить дату'));
      await _tick(t);
      expect(api.queries.last['date'], isNull);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await _tick(t);
    });
  }
}
