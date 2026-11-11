import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/app/router.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/auth_provider.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/partner_link_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const token = 'abcdefghijklmnopqrstuvwxyz_ABCDEFGHIJKLMNOPQRSTUVWXYZ-1234';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('ordinary protected link retains query through authentication', (
    tester,
  ) async {
    final fixture = await _pumpRouter(
      tester,
      initialAuthState: const AuthState(isLoggedIn: false, isLoading: false),
      initialLocation: '/purchase-blanks/invalid?source=notification',
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(fixture.router.routeInformationProvider.value.uri.path, '/login');
    fixture.authNotifier.authenticate();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      fixture.router.routeInformationProvider.value.uri.toString(),
      '/purchase-blanks/invalid?source=notification',
    );
    expect(find.text('Некорректный ID бланка выкупа'), findsOneWidget);
    await _finishWidgetTest(tester);
  });

  testWidgets('ссылка сохраняется на входе и завершается после авторизации', (
    tester,
  ) async {
    final fixture = await _pumpRouter(
      tester,
      initialAuthState: const AuthState(isLoggedIn: false, isLoading: false),
    );

    fixture.router.go('/partner-connect/$token');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fixture.router.routeInformationProvider.value.uri.path, '/login');
    expect(fixture.container.read(partnerLinkProvider).token, token);
    expect(fixture.container.read(partnerLinkProvider).hasPendingToken, isTrue);

    final passwordLoginButton = find.text('Войти с помощью пароля');
    await tester.ensureVisible(passwordLoginButton);
    await tester.pump();
    await tester.tap(passwordLoginButton);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Вход в аккаунт партнёра'), findsOneWidget);
    expect(find.text('Домен партнёра'), findsNothing);

    fixture.authNotifier.authenticate();
    await _pumpUntil(
      tester,
      () =>
          fixture.container.read(partnerLinkProvider).phase ==
          PartnerLinkPhase.completed,
      diagnostic: fixture.describe,
    );
    await tester.pump();

    expect(fixture.api.requestedPaths, [
      '/partner-link/sessions/$token',
      '/partner-link/sessions/$token/complete',
    ]);
    expect(find.text('Аккаунт привязан'), findsOneWidget);
    await _finishWidgetTest(tester);
  });

  testWidgets('авторизованный пользователь привязывается сразу', (
    tester,
  ) async {
    final fixture = await _pumpRouter(
      tester,
      initialAuthState: const AuthState(
        isLoggedIn: true,
        isLoading: false,
        clientId: 101,
      ),
      initialLocation: '/partner-connect/$token',
    );

    await _pumpUntil(
      tester,
      () =>
          fixture.container.read(partnerLinkProvider).phase ==
          PartnerLinkPhase.completed,
      diagnostic: fixture.describe,
    );
    await tester.pump();

    expect(fixture.api.requestedPaths, [
      '/partner-link/sessions/$token',
      '/partner-link/sessions/$token/complete',
    ]);
    expect(find.text('Аккаунт привязан'), findsOneWidget);
    await _finishWidgetTest(tester);
  });

  testWidgets(
    'после регистрации pending token возвращает пользователя к завершению привязки',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'pending_partner_link_token_v1': token,
      });
      final fixture = await _pumpRouter(
        tester,
        initialAuthState: const AuthState(isLoggedIn: false, isLoading: false),
        initialLocation: '/register',
        sessionStatus: 'completed',
      );

      await _pumpUntil(
        tester,
        () => fixture.container.read(partnerLinkProvider).hasPendingToken,
        diagnostic: fixture.describe,
      );
      await tester.pump();
      fixture.authNotifier.authenticate();
      await _pumpUntil(
        tester,
        () =>
            fixture.container.read(partnerLinkProvider).phase ==
            PartnerLinkPhase.completed,
        diagnostic: fixture.describe,
      );
      await tester.pump();

      expect(fixture.api.requestedPaths, [
        '/partner-link/sessions/$token',
        '/partner-link/sessions/$token/complete',
      ]);
      expect(find.text('Аккаунт привязан'), findsOneWidget);
      await _finishWidgetTest(tester);
    },
  );
}

Future<_RouterFixture> _pumpRouter(
  WidgetTester tester, {
  required AuthState initialAuthState,
  String? initialLocation,
  String sessionStatus = 'pending',
}) async {
  final api = _PartnerLinkApiClient(sessionStatus: sessionStatus);
  late _TestAuthNotifier authNotifier;
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      authProvider.overrideWith(() {
        authNotifier = _TestAuthNotifier(initialAuthState);
        return authNotifier;
      }),
    ],
  );
  final router = container.read(routerProvider);
  if (initialLocation != null) router.go(initialLocation);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();

  addTearDown(() {
    router.dispose();
    container.dispose();
  });
  return _RouterFixture(
    api: api,
    authNotifier: authNotifier,
    container: container,
    router: router,
  );
}

Future<void> _finishWidgetTest(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 9));
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  String Function()? diagnostic,
}) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (predicate()) return;
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(
    predicate(),
    isTrue,
    reason: 'Условие не выполнилось за 1 секунду. ${diagnostic?.call() ?? ''}',
  );
}

class _RouterFixture {
  const _RouterFixture({
    required this.api,
    required this.authNotifier,
    required this.container,
    required this.router,
  });

  final _PartnerLinkApiClient api;
  final _TestAuthNotifier authNotifier;
  final ProviderContainer container;
  final GoRouter router;

  String describe() {
    final link = container.read(partnerLinkProvider);
    final auth = container.read(authProvider);
    return 'route=${router.routeInformationProvider.value.uri.path}, '
        'auth=${auth.isLoggedIn}/${auth.isLoading}, '
        'link=${link.phase}/${link.token}, api=${api.requestedPaths}';
  }
}

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier(this.initialState);

  final AuthState initialState;

  @override
  AuthState build() => initialState;

  void authenticate() {
    state = const AuthState(
      isLoggedIn: true,
      isLoading: false,
      clientId: 101,
      userEmail: 'client@example.test',
      userDomain: partnerLinkAgentDomain,
    );
  }
}

class _PartnerLinkApiClient extends ApiClient {
  _PartnerLinkApiClient({required this.sessionStatus});

  final String sessionStatus;
  final requestedPaths = <String>[];

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    if (path.startsWith('/partner-link/')) requestedPaths.add(path);
    if (path == '/public/tariffs') {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'tariffs': <dynamic>[]} as T,
      );
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data:
          {
                'data': {
                  'status': sessionStatus,
                  'partnerName': 'Exchange Partner',
                  'registrationAgent': partnerLinkAgentDomain,
                  'clientCodePrefix': 'PL',
                },
              }
              as T,
    );
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    requestedPaths.add(path);
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data:
          {
                'data': {
                  'status': 'linked',
                  'clientId': 101,
                  'clientCode': '2A-1001',
                  'clientCodes': ['2A-1001'],
                  'accessMode': 'linked_2a',
                  'agent': partnerLinkAgentDomain,
                  'idempotent': sessionStatus == 'completed',
                },
              }
              as T,
    );
  }
}
