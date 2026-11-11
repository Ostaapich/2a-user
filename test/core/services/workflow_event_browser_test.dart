@TestOn('browser')
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/core/network/media_http_adapter.dart';
import 'package:twoalogisticcabineuser/src/core/services/workflow_event_queue.dart';

const origin = String.fromEnvironment('WORKFLOW_TEST_ORIGIN');
void main() {
  test(
    'real browser queue retries stable events and strict Fetch rejects302/307 without credential forwarding',
    () async {
      if (origin.isEmpty) fail('Use test/fixtures/workflow_event_server.py');
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var identity = const WorkflowTransportIdentity(
        token: 'fixture-retry',
        clientId: 1,
        agentId: 10,
      );
      final queue = WorkflowEventQueue(
        preferences: prefs,
        readIdentity: () async => identity,
        endpoint: '$origin/api/client/workflow-events',
        automaticFlush: false,
      );
      addTearDown(queue.dispose);
      await queue.enqueue({'action': 'trackAdd', 'stage': 'started'});
      await queue.flush();
      expect(queue.pendingCount, 1);
      await queue.flush();
      expect(queue.pendingCount, 0);
      identity = const WorkflowTransportIdentity(
        token: 'fixture-other',
        clientId: 2,
        agentId: 20,
      );
      queue.sessionChanged();
      await queue.enqueue({'action': 'paymentReceipt', 'stage': 'succeeded'});
      await queue.flush();
      expect(queue.pendingCount, 0);
      final dio = Dio();
      dio.httpClientAdapter = wrapMediaHttpAdapter(dio.httpClientAdapter);
      addTearDown(dio.close);
      for (final code in [302, 307]) {
        await expectLater(
          dio.post<dynamic>(
            '$origin/api/client/workflow-events',
            data: {'events': []},
            options: Options(
              extra: {'workflow_no_redirect': true},
              headers: {'Authorization': 'Bearer fixture-$code'},
            ),
          ),
          throwsA(isA<DioException>()),
        );
      }
      await expectLater(
        dio.post<dynamic>(
          '$origin/api/not-workflow',
          data: {},
          options: Options(extra: {'workflow_no_redirect': true}),
        ),
        throwsA(isA<DioException>()),
      );
      await expectLater(
        dio.post<dynamic>(
          '$origin/api/client/workflow-events',
          data: {'tooLarge': 'x' * 20000},
          options: Options(extra: {'workflow_no_redirect': true}),
        ),
        throwsA(isA<DioException>()),
      );
      final stats = (await Dio().get<dynamic>('$origin/stats')).data as Map;
      expect(stats['sinkHits'], 0);
      expect(stats['thirdPartyHits'], 0);
      expect(stats['unexpectedPathHits'], 0);
      final bodies = stats['bodies'] as List;
      expect(bodies[0]['events'], bodies[1]['events']);
      expect(bodies[2]['expectedClientId'], 2);
    },
  );
}
