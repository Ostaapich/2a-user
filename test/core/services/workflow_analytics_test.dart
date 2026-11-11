import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/add_tracks/data/add_tracks_repository.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:twoalogisticcabineuser/src/core/services/analytics_service.dart';

class _TrackApi extends ApiClient {
  int added = 0;
  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async => Response<T>(
    requestOptions: RequestOptions(path: path),
    statusCode: 201,
    data: {'added': added, 'skipped': []} as T,
  );
}

void main() {
  final events = <Map<String, Object>>[];
  setUp(() {
    events.clear();
    AnalyticsService.funnelReporterOverride = (name, fields) async {
      expect(name, 'workflow_step');
      events.add(fields);
    };
  });
  tearDown(() => AnalyticsService.funnelReporterOverride = null);
  test(
    'real track repository hook distinguishes no-change from confirmed creation',
    () async {
      final api = _TrackApi();
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final repository = container.read(addTracksRepositoryProvider);
      await repository.addTracks(
        clientCode: 'PRIVATE-CLIENT',
        trackCodes: ['PRIVATE-TRACK'],
      );
      api.added = 1;
      await repository.addTracks(
        clientCode: 'PRIVATE-CLIENT',
        trackCodes: ['PRIVATE-TRACK'],
      );
      await Future<void>.delayed(Duration.zero);
      expect(events.map((e) => e['stage']), [
        'started',
        'noChange',
        'started',
        'succeeded',
      ]);
      expect(events.map((e) => e['action']).toSet(), {'trackAdd'});
      expect(events.toString(), isNot(contains('PRIVATE')));
    },
  );
  test(
    'privacy-safe funnel only emits bounded action stage and reason, not business payload',
    () async {
      final value = await AnalyticsService.traceOperation(
        WorkflowAction.registration,
        () async => true,
        outcome: (value) =>
            value ? WorkflowStage.succeeded : WorkflowStage.failed,
      );
      expect(value, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(events.map((e) => e['stage']), ['started', 'succeeded']);
      for (final e in events) {
        expect(
          e.keys.toSet().difference({'action', 'stage', 'reason'}),
          isEmpty,
        );
      }
    },
  );
  test(
    'false outcome is failure; thrown request stays thrown and has a safe reason',
    () async {
      await AnalyticsService.traceOperation(
        WorkflowAction.login,
        () async => false,
        outcome: (value) =>
            value ? WorkflowStage.succeeded : WorkflowStage.failed,
      );
      await expectLater(
        AnalyticsService.traceOperation(
          WorkflowAction.paymentReceipt,
          () async => throw DioException(
            requestOptions: RequestOptions(path: '/private-account-number'),
            type: DioExceptionType.connectionError,
          ),
        ),
        throwsA(isA<DioException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events.map((e) => e['stage']), [
        'started',
        'failed',
        'started',
        'failed',
      ]);
      expect(events.last['reason'], 'network');
      expect(events.toString(), isNot(contains('private-account-number')));
    },
  );
  test(
    'analytics delay or failure never blocks or fails successful business action',
    () async {
      final never = Completer<void>();
      AnalyticsService.funnelReporterOverride = (_, _) => never.future;
      expect(
        await AnalyticsService.traceOperation(
          WorkflowAction.trackAdd,
          () async => 12,
        ).timeout(const Duration(seconds: 1)),
        12,
      );
      AnalyticsService.funnelReporterOverride = (_, _) async =>
          throw StateError('telemetry unavailable');
      expect(
        await AnalyticsService.traceOperation(
          WorkflowAction.assemblyCreate,
          () async => 13,
        ),
        13,
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        await AnalyticsService.traceOperation(
          WorkflowAction.login,
          () async => true,
          outcome: (_) => throw StateError('classifier bug'),
        ),
        isTrue,
      );
      never.complete();
    },
  );
}
