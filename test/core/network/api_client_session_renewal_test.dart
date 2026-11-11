import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';

String token(int age, {int uid = 17}) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return 'e30.${base64Url.encode(utf8.encode(jsonEncode({'type': 'client', 'role': 'client', 'uid': uid, 'agentId': 4, 'iat': now - age, 'exp': now + 30 * 86400 - age}))).replaceAll('=', '')}.signature';
}

class _Script {
  final paths = <String>[];
  final auth = <String?>[];
  final started = Completer<void>();
  Completer<void>? gate;
  int status = 200;
  late String renewed;
  int renewCalls = 0;
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.script);
  final _Script script;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancelFuture,
  ) async {
    script.paths.add(options.path);
    script.auth.add(options.headers['Authorization'] as String?);
    if (options.path == '/auth/client/renew') {
      expect(options.followRedirects, false);
      expect(options.maxRedirects, 0);
      script.renewCalls++;
      if (!script.started.isCompleted) script.started.complete();
      if (script.gate != null) await script.gate!.future;
      return ResponseBody.fromString(
        jsonEncode({'token': script.renewed, 'clientId': 17, 'agentId': 4}),
        script.status,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ApiClient api;
  late _Script script;
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    SharedPreferences.setMockInitialValues({});
    script = _Script()..renewed = token(0);
    api = ApiClient(
      adapterFactory: () => _Adapter(script),
      runtimeHeaders: () async => {},
    );
    await api.clearToken();
    await api.setToken(token(2 * 86400));
  });
  tearDown(() async {
    await api.clearToken();
    debugDefaultTargetPlatformOverride = null;
  });
  test(
    'Android delayed secure write is serialized before logout delete',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      final started = Completer<void>(), release = Completer<void>();
      String? secure;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'write') {
              if (!started.isCompleted) {
                started.complete();
                await release.future;
              }
              secure = (call.arguments as Map)['value'] as String?;
            } else if (call.method == 'delete') {
              secure = null;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await api.setToken(token(0));
      await started.future;
      final clear = api.clearToken();
      release.complete();
      await clear;
      expect(secure, isNull);
      expect(
        (await SharedPreferences.getInstance()).getString('auth_token'),
        isNull,
      );
    },
  );
  test(
    'native write completing after timeout and logout is reconciled to logged-out state',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      final started = Completer<void>(), release = Completer<void>();
      String? secure;
      var deletes = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'write') {
              if (!started.isCompleted) {
                started.complete();
                await release.future;
              }
              secure = (call.arguments as Map)['value'] as String?;
            } else if (call.method == 'delete') {
              deletes++;
              secure = null;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await api.setToken(token(0));
      await started.future;
      await Future<void>.delayed(const Duration(milliseconds: 5100));
      await api.clearToken();
      expect(secure, isNull);
      expect(deletes, 1);
      release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(secure, isNull);
      expect(deletes, 2);
      expect(await api.getToken(), isNull);
    },
  );
  test(
    'renewal durably replaces bearer while retaining media/export identity',
    () async {
      final before = await api.getMediaCacheIdentity();
      await Future.wait([api.get('/one'), api.get('/two')]);
      expect(script.renewCalls, 1);
      expect(await api.getToken(), script.renewed);
      expect(
        (await SharedPreferences.getInstance()).getString('auth_token'),
        script.renewed,
      );
      expect(await api.getMediaCacheIdentity(), before);
      expect(script.auth.last, 'Bearer ${script.renewed}');
      await api.setToken(token(0, uid: 18));
      expect(await api.getMediaCacheIdentity(), isNot(before));
    },
  );
  test(
    'logout during renewal cannot restore persisted credential or issue old request',
    () async {
      script.gate = Completer<void>();
      final request = api.get('/private');
      final rejected = expectLater(request, throwsA(isA<DioException>()));
      await script.started.future;
      api.prepareForLogout();
      await api.clearToken();
      script.gate!.complete();
      await rejected;
      expect(await api.getToken(), isNull);
      expect(
        (await SharedPreferences.getInstance()).getString('auth_token'),
        isNull,
      );
      expect(script.paths, isNot(contains('/private')));
    },
  );
  test(
    'account switch during renewal preserves new identity and rejects old pending work',
    () async {
      script.gate = Completer<void>();
      final rejected = expectLater(
        api.get('/private'),
        throwsA(isA<DioException>()),
      );
      await script.started.future;
      final other = token(0, uid: 18);
      await api.setToken(other);
      script.gate!.complete();
      await rejected;
      expect(await api.getToken(), other);
      expect(
        (await SharedPreferences.getInstance()).getString('auth_token'),
        other,
      );
    },
  );
  test(
    'public authentication POSTs remain independent of stale blocked-owner renewal',
    () async {
      script.status = 401; // Any accidental renewal must fail this test.
      var unauthorized = 0;
      api.setOnUnauthorizedCallback(() => unauthorized++);
      final previous = await api.getToken();
      for (final path in const [
        '/login',
        '/login/verification/request',
        '/login/verification/verify',
        '/register',
        '/register/phone-verification/request',
        '/register/phone-verification/verify',
        '/password-reset/request',
        '/password-reset/verify',
        '/password-reset/complete',
        '/client/passkeys/authenticate/options',
        '/client/passkeys/authenticate/verify',
      ]) {
        final response = await api.post(path, data: {'fixture': 'unchanged'});
        expect(response.statusCode, 200);
        expect(script.auth.last, 'Bearer $previous');
        expect(script.paths.last, path);
      }
      expect(script.renewCalls, 0);
      expect(unauthorized, 0);
      expect(await api.getToken(), previous);
    },
  );
  test(
    'protected auth/me and passkey registration still renew normal client session',
    () async {
      await api.get('/auth/me');
      expect(script.renewCalls, 1);
      await api.setToken(token(2 * 86400));
      await api.post('/client/passkeys/register/options', data: {});
      expect(script.renewCalls, 2);
      expect(script.auth.last, 'Bearer ${script.renewed}');
    },
  );
  test(
    'renewal redirect never follows bearer and retains valid current session',
    () async {
      script.status = 302;
      final previous = await api.getToken();
      var unauthorized = 0;
      api.setOnUnauthorizedCallback(() => unauthorized++);
      await api.get('/private');
      expect(script.renewCalls, 1);
      expect(await api.getToken(), previous);
      expect(script.paths, contains('/private'));
      expect(script.auth.last, 'Bearer $previous');
      expect(unauthorized, 0);
    },
  );
}
