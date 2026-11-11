import 'package:twoalogisticcabineuser/src/core/ui/app_input_decoration.dart';
import 'package:twoalogisticcabineuser/src/core/ui/phone_input_field.dart';
import 'package:phone_form_field/phone_form_field.dart';
import 'package:dio/dio.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import '../../helpers/keyboard_acceptance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/data/tracks_provider.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/domain/track_item.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/presentation/tracks_screen.dart';

class _NoNetworkApi extends ApiClient {
  @override
  Future<String?> getToken() async => null;
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async => throw StateError('Unexpected fixture read: $path');
  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async => throw StateError('Unexpected fixture mutation: $path');
}

class _ReadOnlyTrackService extends TracksApiService {
  _ReadOnlyTrackService(super.ref);
  @override
  Future<TrackReturnInfo?> getTrackReturn(int trackId) async => null;
}

Future<void> _pumpTrack(
  WidgetTester tester,
  TargetPlatform platform, {
  TrackAssembly? assembly,
  bool orphan = false,
  double width = 390,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, width == 320 ? 640 : 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewInsets);
  final now = DateTime(2026, 11, 10);
  final track = TrackItem(
    id: 42,
    code: 'GAP-TRACK',
    status: orphan ? 'В ожидании' : 'На складе',
    statusCode: orphan ? 'pending' : 'in_warehouse',
    date: now,
    createdAt: now,
    updatedAt: now,
    groupId: assembly?.id.toString(),
    assembly: assembly,
  );
  final tracks = [
    track,
    if (orphan)
      TrackItem(
        id: 44,
        code: 'GAP-OTHER',
        status: 'В ожидании',
        statusCode: 'pending',
        date: now,
        createdAt: now,
        updatedAt: now,
      ),
  ];
  final embedded = TracksScreen.embedded(
    tracks: tracks,
    asAssembly: assembly != null,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(_NoNetworkApi()),
        activeClientCodeProvider.overrideWithValue('2A-TEST'),
        trackStatusesProvider.overrideWith((ref) async => const []),
        assemblyStatusesProvider.overrideWith((ref) async => const []),
        tracksApiServiceProvider.overrideWith(_ReadOnlyTrackService.new),
      ],
      child: MaterialApp(
        theme: ThemeData(fontFamily: 'Gilroy', platform: platform),
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => AppKeyboardDismissRegion(child: child!),
        home: Scaffold(
          body: orphan ? SingleChildScrollView(child: embedded) : embedded,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openAction(WidgetTester tester, String label) async {
  final action = find.byKey(ValueKey('client-track-action-$label'));
  expect(action, findsOneWidget);
  await tester.ensureVisible(action);
  await tester.pump();
  await tester.tap(action);
  await tester.pumpAndSettle();
}

Finder _field(String hint) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.hintText == hint,
);
Finder _frame(Finder field) => find
    .ancestor(of: field, matching: find.byType(AppGradientInputFrame))
    .first;
void _sameFrame(WidgetTester tester) {
  final phone = _frame(_field('Телефон получателя'));
  final name = _frame(_field('ФИО получателя'));
  final city = _frame(_field('Город'));
  expect(tester.getSize(phone).height, tester.getSize(name).height);
  expect(tester.getSize(phone).height, tester.getSize(city).height);
  BoxDecoration decoration(Finder frame) =>
      tester
              .widget<DecoratedBox>(
                find
                    .descendant(of: frame, matching: find.byType(DecoratedBox))
                    .first,
              )
              .decoration
          as BoxDecoration;
  expect(decoration(phone).gradient, decoration(name).gradient);
  expect(decoration(phone).borderRadius, decoration(name).borderRadius);
  expect(
    tester.widget<AppGradientInputFrame>(phone).borderWidth,
    tester.widget<AppGradientInputFrame>(name).borderWidth,
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    await loadKeyboardAcceptanceFonts();
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final width in [320.0, 390.0]) {
      for (final inline in [false, true]) {
        testWidgets(
          'actual delivery phone matches adjacent frames ${platform.name} width=$width inline=$inline',
          (tester) async {
            const assembly = TrackAssembly(
              id: 43,
              number: 'ASM-PHONE',
              status: 'ready_for_pickup',
              deliveryMethod: 'transport_company',
              recipientName: 'Клиент',
              recipientPhone: '+79991234567',
              recipientCity: 'Москва',
              transportCompanyName: 'СДЭК',
              trackCount: 1,
            );
            await _pumpTrack(
              tester,
              platform,
              assembly: assembly,
              width: width,
            );
            if (inline) {
              await tester.tap(find.text('ASM-PHONE').first);
              await tester.pumpAndSettle();
              final tab = find.text('Доставка').last;
              await tester.ensureVisible(tab);
              await tester.tap(tab);
              await tester.pumpAndSettle();
            } else {
              await _openAction(tester, 'Доставка');
            }
            _sameFrame(tester);
            final phone = _field('Телефон получателя');
            await tester.ensureVisible(phone);
            await tester.tap(phone);
            await tester.enterText(phone, '9997654321');
            await tester.pump();
            tester.view.viewInsets = FakeViewPadding(
              bottom: width == 320 ? 280 : 320,
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
            expectFocusedCaretAboveIme(
              tester,
              find.descendant(of: phone, matching: find.byType(EditableText)),
            );
            _sameFrame(tester);
            tester.view.resetViewInsets();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
            await tester.ensureVisible(find.byType(CountryButton));
            await tester.tap(find.byType(CountryButton));
            await tester.pumpAndSettle();
            final china = find.byKey(const ValueKey('CN')).first;
            await tester.ensureVisible(china);
            await tester.tap(china);
            await tester.pumpAndSettle();
            final controller = tester
                .widget<PhoneInputField>(find.byType(PhoneInputField))
                .controller!;
            expect(controller.value.isoCode, IsoCode.CN);
            expect(controller.value.nsn, '9997654321');
            _sameFrame(tester);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          },
        );
      }
    }
  }
}
