import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/core/persistence/shared_preferences_provider.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/auth_provider.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/clients/domain/client_codes_state.dart';
import 'package:twoalogisticcabineuser/src/features/home/presentation/home_screen.dart';
import 'package:twoalogisticcabineuser/src/features/news/data/news_provider.dart';
import 'package:twoalogisticcabineuser/src/features/profile/data/profile_provider.dart';
import 'package:twoalogisticcabineuser/src/features/rules/data/client_terms_provider.dart';

class _Auth extends AuthNotifier {
  @override
  AuthState build() =>
      const AuthState(isLoading: false, isLoggedIn: true, clientId: 17);
  void switchClient(int id) =>
      state = AuthState(isLoading: false, isLoggedIn: true, clientId: id);
}

class _Codes extends ClientCodesController {
  @override
  Future<ClientCodesState> build() async =>
      const ClientCodesState(codes: [], activeCode: null);
}

class _Server extends ApiClient {
  String revision = List.filled(64, 'a').join();
  String content = 'Exact original published text';
  bool accepted = false;
  int gets = 0, posts = 0;
  bool failNextAccept = false;
  Completer<void>? acceptBarrier;
  int currentClientId = 17;
  final bodies = <Map<String, dynamic>>[];
  Map<String, dynamic> bundle() => {
    'clientId': currentClientId,
    'agentId': 9,
    'available': true,
    'revision': revision,
    'accepted': accepted,
    'acceptedAt': accepted ? '2026-11-10T01:00:00.000Z' : null,
    'rules': [
      {
        'id': 1,
        'agentId': 9,
        'title': 'Published document',
        'content': content,
        'sortOrder': 1,
        'updatedAt': '2026-11-10T00:00:00.000Z',
      },
    ],
  };
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    if (path != '/client/terms') throw StateError('Unexpected $path');
    gets++;
    return Response<T>(
      data: bundle() as T,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    if (path != '/client/terms/accept') throw StateError('Unexpected $path');
    posts++;
    final body = Map<String, dynamic>.from(data as Map);
    bodies.add(body);
    final request = RequestOptions(path: path);
    if (failNextAccept) {
      failNextAccept = false;
      throw DioException(
        requestOptions: request,
        type: DioExceptionType.connectionError,
      );
    }
    if (acceptBarrier != null) {
      await acceptBarrier!.future;
    }
    final code = body['expectedClientId'] != currentClientId
        ? 'ACCOUNT_CHANGED'
        : body['revision'] != revision
        ? 'TERMS_VERSION_CHANGED'
        : null;
    if (code != null) {
      throw DioException(
        requestOptions: request,
        response: Response(
          requestOptions: request,
          statusCode: 409,
          data: {'code': code},
        ),
        type: DioExceptionType.badResponse,
      );
    }
    accepted = true;
    return Response<T>(
      data:
          {
                'clientId': 17,
                'agentId': 9,
                'revision': revision,
                'accepted': true,
                'acceptedAt': '2026-11-10T01:00:00.000Z',
              }
              as T,
      statusCode: 200,
      requestOptions: request,
    );
  }
}

Future<ProviderContainer> _pump(WidgetTester tester, _Server server) async {
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authProvider.overrideWith(_Auth.new),
      clientAgentIdProvider.overrideWithValue(9),
      activeClientCodeProvider.overrideWithValue(null),
      clientCodesControllerProvider.overrideWith(_Codes.new),
      clientProfileProvider.overrideWith((_) async => null),
      apiClientProvider.overrideWithValue(server),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: HomeScreen())),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final target = find.text(text);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'terms_accepted': true}));
  testWidgets(
    'reads exact server bundle, conflicts refresh explicitly, offline never accepts, next device sees server audit',
    (tester) async {
      final server = _Server();
      var container = await _pump(tester, server);
      expect(
        find.text('Соглашаюсь'),
        findsOneWidget,
      ); // Legacy local true is ignored.
      await _tapText(tester, 'Ознакомиться с правилами');
      await tester.pumpAndSettle();
      server.revision = List.filled(64, 'b').join();
      server.content = 'New published source text';
      expect(find.text('Exact original published text'), findsOneWidget);
      expect(find.text('New published source text'), findsNothing);
      expect(server.gets, 1);
      await tester.tap(find.byTooltip('Закрыть правила'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Соглашаюсь'));
      await _tapText(tester, 'Соглашаюсь');
      await tester.pumpAndSettle();
      expect(server.accepted, false);
      expect(find.text('Обновить правила'), findsOneWidget);
      await _tapText(tester, 'Обновить правила');
      await tester.pumpAndSettle();
      expect(server.gets, 2);
      expect(find.text('Соглашаюсь'), findsOneWidget);
      await _tapText(tester, 'Ознакомиться с правилами');
      expect(find.text('New published source text'), findsOneWidget);
      expect(find.text('Exact original published text'), findsNothing);
      await tester.tap(find.byTooltip('Закрыть правила'));
      await tester.pumpAndSettle();

      server.failNextAccept = true;
      await _tapText(tester, 'Соглашаюсь');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('на сервере. Проверьте соединение'),
        findsOneWidget,
      );
      expect(server.accepted, false);
      await _tapText(tester, 'Соглашаюсь');
      await tester.pumpAndSettle();
      expect(server.accepted, true);
      expect(find.text('Соглашаюсь'), findsNothing);
      expect(server.bodies.last, {
        'revision': server.revision,
        'expectedClientId': 17,
        'expectedAgentId': 9,
      });
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      SharedPreferences.setMockInitialValues(
        {},
      ); // A different device has no local audit.
      container = await _pump(tester, server);
      expect(find.text('Соглашаюсь'), findsNothing);
      expect(find.text('Повторить проверку правил'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );
  testWidgets(
    'account switch while acceptance is in flight cannot accept for the new owner',
    (tester) async {
      final server = _Server()..acceptBarrier = Completer<void>();
      final container = await _pump(tester, server);
      await _tapText(tester, 'Соглашаюсь');
      await tester.pump();
      server.currentClientId = 18;
      (container.read(authProvider.notifier) as _Auth).switchClient(18);
      server.acceptBarrier!.complete();
      await tester.pumpAndSettle();
      expect(server.posts, 1);
      expect(server.bodies.single['expectedClientId'], 17);
      expect(server.accepted, false);
      expect(find.text('Соглашаюсь'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );

  test(
    'old modal with new same-agent account token is rejected by optimistic owner guard',
    () async {
      final server = _Server();
      final service = ClientTermsService(server);
      final old = await service.fetch(clientId: 17, agentId: 9);
      server.currentClientId = 18;
      await expectLater(
        service.accept(old),
        throwsA(isA<TermsAccountChanged>()),
      );
      expect(server.accepted, false);
      await expectLater(
        service.fetch(clientId: 17, agentId: 9),
        throwsA(isA<TermsAccountChanged>()),
      );
    },
  );
}
