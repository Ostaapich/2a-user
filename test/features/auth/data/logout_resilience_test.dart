import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/core/services/chat_presence_service.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/auth_provider.dart';
import 'package:twoalogisticcabineuser/src/features/news/data/news_provider.dart';
import 'package:twoalogisticcabineuser/src/features/rules/data/rules_provider.dart';
import 'package:twoalogisticcabineuser/src/core/services/push_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => PushNotificationService.setMessagingForTesting(null));

  test(
    'disposing during initial auth restore does not update unmounted state',
    () async {
      SharedPreferences.setMockInitialValues({
        'is_logged_in': true,
        'client_id': 101,
      });
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(_HangingDeviceCleanupApiClient()),
        ],
      );
      container.read(authProvider);
      container.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 30));
    },
  );

  test(
    'token completing after logout cannot register the old session',
    () async {
      SharedPreferences.setMockInitialValues({
        'is_logged_in': true,
        'user_email': 'client@test.local',
        'user_domain': 'test.local',
        'client_id': 101,
        'device_id': 'device-race',
      });
      PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1',
        buildNumber: '1',
        buildSignature: '',
      );
      final messaging = _MockMessaging();
      final tokenRequested = Completer<void>();
      final pendingToken = Completer<String?>();
      when(() => messaging.getToken()).thenAnswer((_) {
        if (!tokenRequested.isCompleted) tokenRequested.complete();
        return pendingToken.future;
      });
      when(() => messaging.deleteToken()).thenAnswer((_) async {});
      PushNotificationService.setMessagingForTesting(messaging);
      final api = _HangingDeviceCleanupApiClient();
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          chatPresenceServiceProvider.overrideWithValue(
            _RecordingChatPresenceService(api),
          ),
          logoutDeviceCleanupTimeoutProvider.overrideWithValue(
            const Duration(milliseconds: 10),
          ),
        ],
      );
      addTearDown(container.dispose);
      await _waitForAuthLoaded(container);
      await tokenRequested.future.timeout(const Duration(seconds: 1));
      await container.read(authProvider.notifier).logout();
      pendingToken.complete('late-fcm-token');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(api.deviceRegistrations, 0);
      verify(() => messaging.deleteToken()).called(1);
      expect(container.read(authProvider).isLoggedIn, false);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'last_company_domain',
        ),
        'test.local',
      );
    },
  );

  test(
    'logout finishes when remote device deactivation never responds',
    () async {
      SharedPreferences.setMockInitialValues({
        'is_logged_in': true,
        'user_email': 'client@example.test',
        'user_domain': '',
        'client_id': 101,
        'client_name': 'Тестовый клиент',
        'client_data': jsonEncode({
          'id': 101,
          'fullName': 'Тестовый клиент',
          'codes': <Map<String, dynamic>>[],
        }),
        'device_id': 'device-test-101',
      });

      final apiClient = _HangingDeviceCleanupApiClient();
      final presenceService = _RecordingChatPresenceService(apiClient);
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
          chatPresenceServiceProvider.overrideWithValue(presenceService),
          logoutDeviceCleanupTimeoutProvider.overrideWithValue(
            const Duration(milliseconds: 20),
          ),
        ],
      );
      addTearDown(container.dispose);

      final restored = await _waitForAuthLoaded(container);
      expect(restored.isLoggedIn, isTrue);

      final stopwatch = Stopwatch()..start();
      await container
          .read(authProvider.notifier)
          .logout()
          .timeout(const Duration(seconds: 1));
      stopwatch.stop();

      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
      expect(presenceService.wasStoppedForLogout, isTrue);
      expect(apiClient.clearTokenCalled, isTrue);
      expect(apiClient.deletedPath, '/devices');
      expect(apiClient.deletedData, {'deviceId': 'device-test-101'});
      expect(container.read(authProvider).isLoggedIn, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('is_logged_in'), isNull);
    },
  );
  test(
    'external browser session change forgets this tab without deleting shared winning identity',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'other-tab-token',
        'is_logged_in': true,
        'client_profile_cache_v1': 'other-tab-cache',
        'active_client_code': 'B202',
        'client_id': 202,
        'user_email': 'other@example.test',
      });
      final api = _ExternalSessionApi();
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      await _waitForAuthLoaded(container);
      await container.read(authProvider.notifier).logout();
      expect(container.read(authProvider).isLoggedIn, false);
      expect(api.clearTokenCalled, false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), 'other-tab-token');
      expect(prefs.getBool('is_logged_in'), true);
      expect(prefs.getString('client_profile_cache_v1'), 'other-tab-cache');
      expect(prefs.getString('active_client_code'), 'B202');
      expect(prefs.getInt('client_id'), 202);
      expect(prefs.getString('user_email'), 'other@example.test');
    },
  );
  test(
    'logout invalidates every numeric news/rule detail across tenant identities',
    () async {
      SharedPreferences.setMockInitialValues({});
      final api = _TenantDetailApi();
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      await _waitForAuthLoaded(container);
      expect(
        (await container.read(newsItemProvider('51').future))?.title,
        'Tenant A',
      );
      expect(
        (await container.read(ruleItemProvider('52').future))?.title,
        'Tenant A',
      );
      api.foreign = true;
      await container.read(authProvider.notifier).logout();
      expect(await container.read(newsItemProvider('51').future), isNull);
      expect(await container.read(ruleItemProvider('52').future), isNull);
      expect(api.detailReads, 4);
    },
  );
}

Future<AuthState> _waitForAuthLoaded(ProviderContainer container) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < const Duration(seconds: 1)) {
    final auth = container.read(authProvider);
    if (!auth.isLoading) return auth;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return container.read(authProvider);
}

class _HangingDeviceCleanupApiClient extends ApiClient {
  int deviceRegistrations = 0;
  bool clearTokenCalled = false;
  String? deletedPath;
  dynamic deletedData;

  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    if (path == '/devices') deviceRegistrations++;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 201,
    );
  }

  @override
  bool get hasToken => true;

  @override
  Future<bool> hasTokenAsync() async => true;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => Completer<Response<T>>().future;

  @override
  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    deletedPath = path;
    deletedData = data;
    return Completer<Response<T>>().future;
  }

  @override
  Future<void> clearToken() async {
    clearTokenCalled = true;
  }
}

class _MockMessaging extends Mock implements FirebaseMessaging {}

class _RecordingChatPresenceService extends ChatPresenceService {
  _RecordingChatPresenceService(super.apiClient);

  bool wasStoppedForLogout = false;

  @override
  void stopForLogout() {
    wasStoppedForLogout = true;
    super.stopForLogout();
  }
}

class _TenantDetailApi extends _HangingDeviceCleanupApiClient {
  bool foreign = false;
  int detailReads = 0;
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    if (path == '/news/51' || path == '/service-rules/52') {
      detailReads++;
      if (foreign) {
        throw DioException(
          requestOptions: RequestOptions(path: path),
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: path),
            statusCode: 404,
          ),
        );
      }
      final item = {
        'id': 51,
        'title': 'Tenant A',
        'content': 'Private tenant content',
      };
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: (path.startsWith('/news') ? {'data': item} : item) as T,
      );
    }
    throw StateError('Unscripted request $path');
  }
}

class _ExternalSessionApi extends _HangingDeviceCleanupApiClient {
  @override
  bool takeExternalSessionChange() => true;
}
