import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/core/services/workflow_event_queue.dart';

void main() {
  test(
    'real HTTP queue retries identical UUIDs, persists only enums, and isolates account switch',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var identity = const WorkflowTransportIdentity(
        token: 'account-A',
        clientId: 1,
        agentId: 10,
      );
      final received = <Map<String, dynamic>>[];
      final auth = <String?>[];
      var fail = true;
      server.listen((request) async {
        auth.add(request.headers.value('authorization'));
        final body =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        received.add(body);
        request.response.statusCode = fail ? 503 : 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            fail
                ? {'error': 'try again'}
                : {
                    'acceptedIds': (body['events'] as List)
                        .map((e) => e['id'])
                        .toList(),
                  },
          ),
        );
        await request.response.close();
      });
      var queue = WorkflowEventQueue(
        preferences: prefs,
        readIdentity: () async => identity,
        endpoint: 'http://127.0.0.1:${server.port}/client/workflow-events',
        automaticFlush: false,
      );
      addTearDown(queue.dispose);
      await queue.enqueue({'action': 'trackAdd', 'stage': 'started'});
      await queue.flush();
      expect(queue.pendingCount, 1);
      queue.dispose();
      queue = WorkflowEventQueue(
        preferences: prefs,
        readIdentity: () async => identity,
        endpoint: 'http://127.0.0.1:${server.port}/client/workflow-events',
        automaticFlush: false,
      );
      addTearDown(queue.dispose);
      fail = false;
      await queue.flush();
      expect(queue.pendingCount, 0);
      expect(received[0]['events'], received[1]['events']);
      expect(auth, ['Bearer account-A', 'Bearer account-A']);
      fail = true;
      await queue.enqueue({'action': 'assemblyCreate', 'stage': 'started'});
      await queue.flush();
      identity = const WorkflowTransportIdentity(
        token: 'account-B',
        clientId: 2,
        agentId: 20,
      );
      queue.sessionChanged();
      fail = false;
      await queue.enqueue({'action': 'paymentReceipt', 'stage': 'succeeded'});
      await queue.flush();
      expect(received.last['expectedClientId'], 2);
      expect(
        (received.last['events'] as List).single['action'],
        'paymentReceipt',
      );
      final stored = prefs.getString(WorkflowEventQueue.storageKey) ?? '';
      expect(stored, isNot(contains('account-A')));
      expect(stored, isNot(contains('account-B')));
    },
  );
  test(
    'queue is bounded; anonymous and corrupted stored fields are never reassigned',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      WorkflowTransportIdentity? identity;
      final queue = WorkflowEventQueue(
        preferences: prefs,
        readIdentity: () async => identity,
        endpoint: 'http://127.0.0.1:1/workflow',
        automaticFlush: false,
      );
      addTearDown(queue.dispose);
      await queue.enqueue({'action': 'login', 'stage': 'viewed'});
      expect(queue.pendingCount, 0);
      identity = const WorkflowTransportIdentity(
        token: 'new-session',
        clientId: 2,
        agentId: 20,
      );
      queue.sessionChanged();
      for (var i = 0; i < 200; i++) {
        await queue.enqueue({'action': 'trackAdd', 'stage': 'viewed'});
      }
      expect(queue.pendingCount, WorkflowEventQueue.maxPending);
      final stored =
          jsonDecode(prefs.getString(WorkflowEventQueue.storageKey)!) as Map;
      expect((stored['events'] as List).length, 180);
      await queue.enqueue({
        'action': 'trackAdd',
        'stage': 'viewed',
        'email': 'secret@example.test',
      });
      expect(
        prefs.getString(WorkflowEventQueue.storageKey),
        isNot(contains('secret@example.test')),
      );
      identity = null;
      queue.sessionChanged();
      await queue.flush();
      expect(queue.pendingCount, 0);
      expect(prefs.getString(WorkflowEventQueue.storageKey), isNull);
    },
  );
  test(
    'in-flight old-session acknowledgement cannot remove or resend new-owner events',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var identity = const WorkflowTransportIdentity(
        token: 'old',
        clientId: 1,
        agentId: 10,
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final arrived = Completer<void>(), release = Completer<void>();
      final bodies = <Map<String, dynamic>>[];
      final tokens = <String?>[];
      server.listen((request) async {
        try {
          final body =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;
          bodies.add(body);
          tokens.add(request.headers.value('authorization'));
          if (bodies.length == 1) {
            arrived.complete();
            await release.future;
          }
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'acceptedIds': (body['events'] as List)
                  .map((e) => e['id'])
                  .toList(),
            }),
          );
          await request.response.close();
        } catch (_) {
          /* Expected cancelled old HTTP connection. */
        }
      });
      final queue = WorkflowEventQueue(
        preferences: prefs,
        readIdentity: () async => identity,
        endpoint: 'http://127.0.0.1:${server.port}/workflow',
        automaticFlush: false,
      );
      addTearDown(queue.dispose);
      await queue.enqueue({'action': 'trackAdd', 'stage': 'started'});
      final oldFlush = queue.flush();
      await arrived.future.timeout(const Duration(seconds: 2));
      identity = const WorkflowTransportIdentity(
        token: 'new',
        clientId: 2,
        agentId: 20,
      );
      queue.sessionChanged();
      await queue.enqueue({'action': 'paymentReceipt', 'stage': 'succeeded'});
      await oldFlush;
      release.complete();
      expect(queue.pendingCount, 1);
      await queue.flush();
      expect(queue.pendingCount, 0);
      expect(tokens, ['Bearer old', 'Bearer new']);
      expect(
        (bodies.last['events'] as List).single['action'],
        'paymentReceipt',
      );
      expect(bodies.last['expectedClientId'], 2);
    },
  );
  test(
    'anonymous delivery has no bearer/account envelope or localStorage and batches at10',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        WorkflowEventQueue.storageKey,
        'existing-auth-owned-record',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final bodies = <Map<String, dynamic>>[];
      server.listen((request) async {
        expect(request.headers.value('authorization'), isNull);
        final body =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        bodies.add(body);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'acceptedIds': (body['events'] as List)
                .map((e) => e['id'])
                .toList(),
          }),
        );
        await request.response.close();
      });
      final queue = WorkflowEventQueue(
        preferences: prefs,
        persistEvents: false,
        readIdentity: () async => const WorkflowTransportIdentity.anonymous(
          sessionId: '81ab7c2f-1951-433a-a443-f685762e854b',
        ),
        endpoint: 'http://127.0.0.1:${server.port}/public/workflow-events',
        automaticFlush: false,
      );
      addTearDown(queue.dispose);
      for (var i = 0; i < 12; i++) {
        await queue.enqueue({'action': 'login', 'stage': 'viewed'});
      }
      await queue.flush();
      expect(queue.pendingCount, 2);
      await queue.flush();
      expect(queue.pendingCount, 0);
      expect((bodies.first['events'] as List).length, 10);
      expect(bodies.first.keys.toSet(), {'sessionId', 'events'});
      expect(
        prefs.getString(WorkflowEventQueue.storageKey),
        'existing-auth-owned-record',
      );
    },
  );
}
