import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';

class _DeferredFrameBinding extends AutomatedTestWidgetsFlutterBinding {
  bool deferUnauthorized = false;
  @override
  SchedulerPhase get schedulerPhase => deferUnauthorized
      ? SchedulerPhase.persistentCallbacks
      : super.schedulerPhase;
}

class _UnauthorizedAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '{}',
    401,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
  @override
  void close({bool force = false}) {}
}

void main() {
  final binding = _DeferredFrameBinding();
  late ApiClient api;
  late int calls;
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    SharedPreferences.setMockInitialValues({});
    api = ApiClient(
      adapterFactory: () => _UnauthorizedAdapter(),
      runtimeHeaders: () async => {},
    );
    await api.setToken('session-a');
    calls = 0;
    api.setOnUnauthorizedCallback(() => calls++);
  });
  tearDown(() async {
    binding.deferUnauthorized = false;
    await api.clearToken();
    debugDefaultTargetPlatformOverride = null;
  });
  Future<void> rejected() =>
      expectLater(api.get('/private'), throwsA(isA<DioException>()));
  testWidgets(
    'latest current generation replaces queued stale unauthorized event',
    (tester) async {
      binding.deferUnauthorized = true;
      await tester.runAsync(() async {
        await rejected();
        await api.setToken('session-b');
        await rejected();
      });
      expect(calls, 0);
      binding.deferUnauthorized = false;
      binding.scheduleFrame();
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
      expect(calls, 1);
    },
  );
  testWidgets(
    'new login cancels queued previous generation without a current unauthorized event',
    (tester) async {
      binding.deferUnauthorized = true;
      await tester.runAsync(() async {
        await rejected();
        await api.setToken('session-b');
      });
      binding.deferUnauthorized = false;
      binding.scheduleFrame();
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
      expect(calls, 0);
    },
  );
  testWidgets('same-generation unauthorized storm invokes one callback', (
    tester,
  ) async {
    binding.deferUnauthorized = true;
    await tester.runAsync(() async {
      await Future.wait([rejected(), rejected(), rejected()]);
    });
    expect(calls, 0);
    binding.deferUnauthorized = false;
    binding.scheduleFrame();
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
    expect(calls, 1);
  });
}
