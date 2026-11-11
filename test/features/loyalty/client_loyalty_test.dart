import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_colors.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/auth_provider.dart';
import 'package:twoalogisticcabineuser/src/features/loyalty/data/client_loyalty_api.dart';
import 'package:twoalogisticcabineuser/src/features/loyalty/data/client_loyalty_provider.dart';
import 'package:twoalogisticcabineuser/src/features/loyalty/domain/client_loyalty.dart';
import 'package:twoalogisticcabineuser/src/features/loyalty/presentation/client_loyalty_section.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/data/tracks_provider.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/domain/photo_report_options.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/presentation/widgets/photo_report_selection_sheet.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/presentation/widgets/track_sheet_surface.dart';

Map<String, dynamic> _summary({int balance = 10, String tier = 'gold'}) => {
  'enabled': true,
  'version': 1,
  'balance': balance,
  'tier': tier,
  'metrics': {
    'windowDays': 90,
    'shippedKg': 320.5,
    'shipments': 6,
    'shippingDays': 4,
  },
  'thresholds': [
    {'tier': 'silver', 'kg': 100, 'shipments': 3},
    {'tier': 'gold', 'kg': 300, 'shipments': 6},
    {'tier': 'platinum', 'kg': 1000, 'shipments': 12},
  ],
  'rewards': {
    'photo': {'cost': 5, 'enabled': true},
    'video': {'cost': 10, 'enabled': true},
  },
  'gifts': <dynamic>[],
};

class _Api extends ApiClient {
  final once = <Map<String, dynamic>>[];
  final paidPaths = <String>[];
  Object? failure;
  int getStatus = 200;
  dynamic getData;
  dynamic acknowledgedBody = {'id': 81};

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    final request = RequestOptions(path: path);
    if (getStatus != 200) {
      throw DioException(
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: getStatus),
      );
    }
    return Response<T>(
      requestOptions: request,
      statusCode: 200,
      data: getData as T,
    );
  }

  @override
  Future<Response<T>> postOnce<T>(
    String path, {
    dynamic data,
    Options? options,
  }) async {
    once.add({'path': path, ...Map<String, dynamic>.from(data as Map)});
    if (failure != null) throw failure!;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 201,
      data: acknowledgedBody as T,
    );
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    paidPaths.add(path);
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 201,
      data: {'id': 82} as T,
    );
  }
}

class _Auth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    isLoggedIn: true,
    isLoading: false,
    clientId: 101,
    userDomain: 'company.test',
    clientData: {'agentId': 7},
  );
}

class _TimeoutAdapter implements HttpClientAdapter {
  int attempts = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancelFuture,
  ) async {
    attempts++;
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionTimeout,
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _redeem(
  ClientLoyaltyApi service, {
  required int client,
  String wish = 'Check stitching',
  String type = 'photo',
  bool current = true,
}) => service.redeem(
  agentId: 7,
  clientId: client,
  trackId: 21,
  rewardType: type,
  wish: wish,
  isCurrentIdentity: () => current,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'optional model rejects unknown versions, malformed balances and prices',
    () {
      expect(ClientLoyalty.tryParse({'enabled': false}), isNull);
      expect(ClientLoyalty.tryParse({..._summary(), 'version': 2}), isNull);
      expect(ClientLoyalty.tryParse({..._summary(), 'balance': -1}), isNull);
      expect(ClientLoyalty.tryParse({..._summary(), 'balance': 1.5}), isNull);
      expect(
        ClientLoyalty.tryParse({..._summary(), 'tier': 'unknown'}),
        isNull,
      );
      final malformed = _summary();
      (malformed['rewards'] as Map)['video'] = {'cost': 0, 'enabled': true};
      expect(ClientLoyalty.tryParse(malformed), isNull);
      final value = ClientLoyalty.tryParse(_summary(balance: 7))!;
      expect(value.canRedeem('photo'), isTrue);
      expect(value.canRedeem('video'), isFalse);
      expect(value.canRedeem('arbitrary'), isFalse);
      expect(value.canClaim('gold'), isTrue);
      expect(value.canClaim('platinum'), isFalse);
    },
  );

  test(
    'old backend and disabled capability do not create a new paid flow',
    () async {
      final api = _Api();
      final service = ClientLoyaltyApi(api);
      for (final status in [404, 501]) {
        api.getStatus = status;
        expect(await service.load(), isNull);
      }
      api.getStatus = 200;
      api.getData = {'enabled': false};
      expect(await service.load(), isNull);
      api.getData = {'data': _summary()};
      expect((await service.load())!.balance, 10);
      expect(api.once, isEmpty);
      expect(api.paidPaths, isEmpty);
    },
  );

  test('quality counters are optional and require nonnegative integers', () {
    final withoutQuality = ClientLoyalty.tryParse(_summary())!;
    expect(withoutQuality.pendingTracksMissingProductInfo, 0);
    expect(withoutQuality.assembliesMissingDelivery, 0);
    final raw = _summary();
    raw['quality'] = {
      'pendingTracksMissingProductInfo': 3,
      'assembliesMissingDelivery': 2,
    };
    expect(ClientLoyalty.tryParse(raw)!.pendingTracksMissingProductInfo, 3);
    expect(ClientLoyalty.tryParse(raw)!.assembliesMissingDelivery, 2);
    raw['quality'] = {'pendingTracksMissingProductInfo': -1};
    expect(ClientLoyalty.tryParse(raw), isNull);
    raw['quality'] = {'assembliesMissingDelivery': 1.5};
    expect(ClientLoyalty.tryParse(raw), isNull);
  });

  test(
    'definitive insufficient-balance rejection permits a new manual request',
    () async {
      final request = RequestOptions(path: '/client/loyalty/redemptions');
      final api = _Api()
        ..failure = DioException(
          requestOptions: request,
          response: Response(
            requestOptions: request,
            statusCode: 409,
            data: {'code': 'insufficient_loyalty_points'},
          ),
        );
      final service = ClientLoyaltyApi(api);
      await expectLater(
        _redeem(service, client: 301),
        throwsA(isA<DioException>()),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('client_loyalty_request_v1:7:301:21:photo'),
        isNull,
      );
      expect(api.once, hasLength(1));
      api.failure = null;
      await _redeem(service, client: 301, wish: 'New instructions');
      expect(api.once, hasLength(2));
      expect(api.once[1]['requestId'], isNot(api.once[0]['requestId']));
      expect(api.once[1]['wish'], 'New instructions');
      expect(api.paidPaths, isEmpty);
    },
  );

  test(
    'refunded rejection permits new manual instructions without a retry',
    () async {
      final request = RequestOptions(path: '/client/loyalty/redemptions');
      final api = _Api()
        ..failure = DioException(
          requestOptions: request,
          response: Response(
            requestOptions: request,
            statusCode: 409,
            data: {'code': 'reward_refunded'},
          ),
        );
      final service = ClientLoyaltyApi(api);
      await expectLater(
        _redeem(service, client: 302),
        throwsA(isA<DioException>()),
      );
      expect(api.once, hasLength(1));
      api.failure = null;
      await _redeem(service, client: 302, wish: 'New instructions');
      expect(api.once[1]['requestId'], isNot(api.once[0]['requestId']));
    },
  );

  for (final entry in [
    (503, 'insufficient_loyalty_points'),
    (409, 'request_id_conflict'),
    (401, null),
    (422, 'unknown_rejection'),
  ]) {
    test(
      'uncertain ${entry.$1}/${entry.$2} preserves pending request',
      () async {
        final client = 400 + entry.$1 + (entry.$2?.length ?? 0);
        final request = RequestOptions(path: '/client/loyalty/redemptions');
        final api = _Api()
          ..failure = DioException(
            requestOptions: request,
            response: Response(
              requestOptions: request,
              statusCode: entry.$1,
              data: entry.$2 == null ? {} : {'code': entry.$2},
            ),
          );
        final service = ClientLoyaltyApi(api);
        await expectLater(
          _redeem(service, client: client),
          throwsA(isA<DioException>()),
        );
        api.failure = null;
        await expectLater(
          _redeem(service, client: client, wish: 'New instructions'),
          throwsA(
            isA<LoyaltyRequestException>().having(
              (e) => e.code,
              'code',
              'loyalty_pending_request_changed',
            ),
          ),
        );
        expect(api.once, hasLength(1));
        expect(api.paidPaths, isEmpty);
      },
    );
  }

  test(
    'timeout preserves durable UUID, next explicit attempt reuses it',
    () async {
      final api = _Api()..failure = TimeoutException('Unconfirmed');
      await expectLater(
        _redeem(ClientLoyaltyApi(api), client: 201),
        throwsA(isA<TimeoutException>()),
      );
      expect(api.once, hasLength(1));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('client_loyalty_request_v1:7:201:21:photo'),
        contains(api.once.single['requestId'] as String),
      );
      api.failure = null;
      await _redeem(ClientLoyaltyApi(api), client: 201);
      expect(api.once, hasLength(2));
      expect(api.once[0], api.once[1]);
      expect(
        prefs.getString('client_loyalty_request_v1:7:201:21:photo'),
        isNull,
      );
      expect(api.paidPaths, isEmpty);
    },
  );

  test(
    'unknown 200 response does not clear pending request or retry',
    () async {
      final api = _Api()..acknowledgedBody = {};
      await expectLater(
        _redeem(ClientLoyaltyApi(api), client: 202),
        throwsA(isA<LoyaltyRequestException>()),
      );
      expect(api.once, hasLength(1));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('client_loyalty_request_v1:7:202:21:photo'),
        isNotNull,
      );
    },
  );

  test('changed wish cannot replace an unconfirmed redemption key', () async {
    final api = _Api()..failure = TimeoutException('Unconfirmed');
    final service = ClientLoyaltyApi(api);
    await expectLater(
      _redeem(service, client: 203),
      throwsA(isA<TimeoutException>()),
    );
    api.failure = null;
    await expectLater(
      _redeem(service, client: 203, wish: 'Changed'),
      throwsA(
        isA<LoyaltyRequestException>().having(
          (e) => e.code,
          'code',
          'loyalty_pending_request_changed',
        ),
      ),
    );
    expect(api.once, hasLength(1));
  });

  test('switching account while saving the key prevents dispatch', () async {
    final api = _Api();
    await expectLater(
      _redeem(ClientLoyaltyApi(api), client: 204, current: false),
      throwsA(
        isA<LoyaltyRequestException>().having(
          (e) => e.code,
          'code',
          'loyalty_identity_changed',
        ),
      ),
    );
    expect(api.once, isEmpty);
    await _redeem(ClientLoyaltyApi(api), client: 205);
    expect(api.once, hasLength(1));
  });

  test(
    'concurrent manual submissions use a single persisted request key',
    () async {
      final api = _Api()..failure = TimeoutException('Unconfirmed');
      final service = ClientLoyaltyApi(api);
      final futures = List.generate(
        2,
        (_) => _redeem(service, client: 206).catchError((_) {}),
      );
      await Future.wait(futures);
      expect(api.once, hasLength(2));
      expect(api.once[0]['requestId'], api.once[1]['requestId']);
    },
  );

  test('postOnce performs exactly one connection-timeout attempt', () async {
    final adapter = _TimeoutAdapter();
    final api = ApiClient(
      adapterFactory: () => adapter,
      runtimeHeaders: () async => {},
    );
    await expectLater(
      api.postOnce('/client/loyalty/redemptions', data: {'requestId': 'test'}),
      throwsA(isA<DioException>()),
    );
    expect(adapter.attempts, 1);
  });

  test(
    'bonus service failure never falls back to ordinary paid POST',
    () async {
      final api = _Api()..failure = TimeoutException('Unconfirmed');
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          authProvider.overrideWith(_Auth.new),
        ],
      );
      addTearDown(container.dispose);
      final service = container.read(tracksApiServiceProvider);
      expect(
        await service.createPhotoRequest(
          clientId: 101,
          clientCodeId: 8,
          trackId: 21,
          trackNumber: 'TEST',
          wish: 'Check stitching',
          reportType: 'custom',
          expectedPriceUsd: '0.00',
          loyaltyRewardType: 'video',
        ),
        isFalse,
      );
      expect(api.once, hasLength(1));
      expect(api.paidPaths, isEmpty);
      expect(service.lastPhotoRequestErrorCode, 'loyalty_request_failed');
    },
  );

  Future<void> openSheet(
    WidgetTester tester, {
    required int balance,
    Future<ClientLoyalty?> Function()? loader,
    String locale = 'ru',
    void Function(PhotoReportSelection?)? onResult,
  }) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          brandColorsProvider.overrideWithValue(BrandColors.defaultColors),
        ],
        child: MaterialApp(
          locale: Locale(locale),
          supportedLocales: const [Locale('ru'), Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  final selection =
                      await showModalBottomSheet<PhotoReportSelection>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => PhotoReportSelectionSheet(
                          trackNumber: 'TEST',
                          loadOptions: () async => PhotoReportOptions.fromJson({
                            'standard': {'enabled': true, 'priceUsd': '0.00'},
                            'custom': {'enabled': true, 'priceUsd': '5.00'},
                          }),
                          loadLoyalty:
                              loader ??
                              () async => ClientLoyalty.tryParse(
                                _summary(balance: balance),
                              ),
                        ),
                      );
                  onResult?.call(selection);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('bonus choice is explicit, insufficient video is disabled', (
    tester,
  ) async {
    PhotoReportSelection? result;
    await openSheet(tester, balance: 7, onResult: (value) => result = value);
    expect(find.text('Оплатить бонусами · баланс 7'), findsOneWidget);
    final video = find.widgetWithText(
      TrackSheetOptionTile,
      'Короткое видео товара',
    );
    expect(tester.widget<TrackSheetOptionTile>(video).onTap, isNull);
    final photo = find.text('Расширенный фотоотчёт');
    await tester.ensureVisible(photo);
    await tester.tap(photo);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Check stitching');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Запросить за 5 бонусов'));
    await tester.pumpAndSettle();
    expect(result?.loyaltyRewardType, 'photo');
    expect(result?.reportType, 'custom');
    expect(result?.expectedPriceUsd, '0.00');
  });

  testWidgets('optional loader failure leaves paid choices available', (
    tester,
  ) async {
    await openSheet(
      tester,
      balance: 0,
      loader: () async => throw StateError('old backend'),
    );
    expect(find.text('Стандартный фотоотчёт'), findsOneWidget);
    expect(find.text('Проверка по заданию'), findsOneWidget);
    expect(find.textContaining('Оплатить бонусами'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('available bonuses never change the default ordinary selection', (
    tester,
  ) async {
    PhotoReportSelection? result;
    await openSheet(tester, balance: 100, onResult: (value) => result = value);
    await tester.tap(find.text('Запросить фотоотчёт'));
    await tester.pumpAndSettle();
    expect(result?.loyaltyRewardType, isNull);
    expect(result?.reportType, 'standard');
  });

  testWidgets('ten points unlock video with required instructions', (
    tester,
  ) async {
    PhotoReportSelection? result;
    await openSheet(tester, balance: 10, onResult: (value) => result = value);
    final video = find.text('Короткое видео товара');
    await tester.ensureVisible(video);
    await tester.tap(video);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Запросить за 10 бонусов'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('Напишите пожелания к проверке'), findsOneWidget);
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(
      find.byType(TextField),
      'Show the mechanism working',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Запросить за 10 бонусов'));
    await tester.pumpAndSettle();
    expect(result?.loyaltyRewardType, 'video');
    expect(result?.expectedPriceUsd, '0.00');
    expect(result?.wish, 'Show the mechanism working');
  });

  testWidgets(
    'profile card uses Chinese labels and shows one-time gift state',
    (tester) async {
      final raw = _summary();
      raw['gifts'] = [
        {'id': 'gift-id', 'tier': 'silver', 'status': 'fulfilled'},
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            brandColorsProvider.overrideWithValue(BrandColors.defaultColors),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: const [Locale('ru'), Locale('zh')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(
              body: SingleChildScrollView(
                child: ClientLoyaltyCard(
                  value: ClientLoyalty.tryParse(raw)!,
                  onRefresh: () {},
                  onClaimGift: (_) async {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('积分与会员等级'), findsOneWidget);
      expect(find.text('积分：10'), findsOneWidget);
      expect(find.text('白银等级礼品：已发放'), findsOneWidget);
      expect(find.text('申请白银等级礼品'), findsNothing);
      expect(find.text('申请黄金等级礼品'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing capability hides only optional section', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [clientLoyaltyProvider.overrideWith((ref) async => null)],
        child: const MaterialApp(
          home: Column(
            children: [Text('Profile remains'), ClientLoyaltySection()],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Profile remains'), findsOneWidget);
    expect(find.byType(ClientLoyaltyCard), findsNothing);
  });

  for (final locale in ['ru', 'zh']) {
    testWidgets('quality reminders open the relevant tracks view ($locale)', (
      tester,
    ) async {
      final raw = _summary();
      raw['quality'] = {
        'pendingTracksMissingProductInfo': 3,
        'assembliesMissingDelivery': 2,
      };
      final router = GoRouter(
        initialLocation: '/profile',
        routes: [
          GoRoute(
            path: '/profile',
            builder: (context, _) => Scaffold(
              body: SingleChildScrollView(
                child: ClientLoyaltyCard(
                  value: ClientLoyalty.tryParse(raw)!,
                  onRefresh: () {},
                  onClaimGift: (_) async {},
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/tracks',
            builder: (context, state) => Scaffold(
              body: Text(
                'opened ${state.uri.queryParameters['view'] ?? 'singles'}',
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            brandColorsProvider.overrideWithValue(BrandColors.defaultColors),
          ],
          child: MaterialApp.router(
            locale: Locale(locale),
            supportedLocales: const [Locale('ru'), Locale('zh')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          locale == 'ru'
              ? 'У 3 треков не заполнена информация о товаре'
              : '3个运单尚未填写商品资料',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          locale == 'ru'
              ? 'У 2 сборок не заполнена доставка по России'
              : '2个集运包裹尚未填写俄罗斯境内配送资料',
        ),
        findsOneWidget,
      );
      final delivery = find.byKey(const Key('loyalty-complete-delivery'));
      await tester.ensureVisible(delivery);
      await tester.tap(delivery);
      await tester.pumpAndSettle();
      expect(find.text('opened groups'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      final product = find.byKey(const Key('loyalty-complete-product-info'));
      await tester.ensureVisible(product);
      await tester.tap(product);
      await tester.pumpAndSettle();
      expect(find.text('opened singles'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
