import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/network/client_session_renewal.dart';

String jwt(
  int issued,
  int expires, {
  int uid = 17,
  int agent = 4,
  Map<String, dynamic> extra = const {},
}) =>
    'e30.${base64Url.encode(utf8.encode(jsonEncode({'uid': uid, 'agentId': agent, 'type': 'client', 'role': 'client', 'iat': issued, 'exp': expires, ...extra}))).replaceAll('=', '')}.sig';
void main() {
  const day = 86400;
  const now = 2000000000;
  late ClientSessionRenewal coordinator;
  late String old, renewed;
  late int calls, saves, invalidations;
  var current = true;
  late Future<Map<String, dynamic>> Function(int, int) request;
  late Future<String?> Function(String) persist;
  Future<String?> run({
    String? token,
    String origin = 'tenant-a',
    int generation = 1,
  }) => coordinator.tokenForRequest(
    token: token ?? old,
    origin: origin,
    generation: generation,
    isCurrent: () => current,
    request: request,
    persist: persist,
    invalidate: () => invalidations++,
  );
  setUp(() {
    coordinator = ClientSessionRenewal(
      now: () => DateTime.fromMillisecondsSinceEpoch(now * 1000),
    );
    old = jwt(now - 2 * day, now + 28 * day);
    renewed = jwt(now, now + 30 * day);
    calls = saves = invalidations = 0;
    current = true;
    request = (client, agent) async {
      calls++;
      expect((client, agent), (17, 4));
      return {'token': renewed, 'clientId': 17, 'agentId': 4};
    };
    persist = (value) async {
      saves++;
      return value;
    };
  });
  test(
    'daily active use renews and saves once across concurrent requests',
    () async {
      final gate = Completer<Map<String, dynamic>>();
      request = (_, _) {
        calls++;
        return gate.future;
      };
      final a = run(), b = run();
      gate.complete({'token': renewed, 'clientId': 17, 'agentId': 4});
      expect(await a, renewed);
      expect(await b, renewed);
      expect(calls, 1);
      expect(saves, 1);
    },
  );
  test(
    'young token, expired token, malformed token and employee/impersonation skip renewal',
    () async {
      for (final token in [
        jwt(now, now + 30 * day),
        jwt(now - 40 * day, now - 1),
        'invalid',
        jwt(now - day * 2, now + day, extra: {'type': 'employee'}),
        jwt(now - day * 2, now + day, extra: {'impersonatorUid': 18}),
      ]) {
        expect(await run(token: token), token);
      }
      expect(calls, 0);
      expect(saves, 0);
      expect(invalidations, 0);
    },
  );
  test('short remaining expiry renews before daily interval', () async {
    expect(await run(token: jwt(now - 60, now + day)), renewed);
    expect(calls, 1);
  });
  test(
    'unsupported server keeps valid credential and cooldown prevents request storm',
    () async {
      request = (_, _) async {
        calls++;
        throw const ClientRenewalException(404);
      };
      expect(await run(), old);
      expect(await run(), old);
      expect(calls, 1);
      expect(invalidations, 0);
    },
  );
  test(
    'network/server errors and storage failure retain current valid token',
    () async {
      request = (_, _) async {
        calls++;
        throw const ClientRenewalException(503);
      };
      expect(await run(), old);
      expect(await run(), old);
      expect(calls, 1);
      coordinator = ClientSessionRenewal(
        now: () => DateTime.fromMillisecondsSinceEpoch(now * 1000),
      );
      request = (_, _) async => {
        'token': renewed,
        'clientId': 17,
        'agentId': 4,
      };
      persist = (_) async => null;
      expect(await run(), old);
      expect(invalidations, 0);
    },
  );
  test(
    'revoked or owner-conflicting credentials trigger current-session logout',
    () async {
      for (final failure in [
        const ClientRenewalException(401),
        const ClientRenewalException(409, 'ACCOUNT_CHANGED'),
      ]) {
        coordinator = ClientSessionRenewal(
          now: () => DateTime.fromMillisecondsSinceEpoch(now * 1000),
        );
        request = (_, _) async => throw failure;
        expect(await run(), isNull);
      }
      expect(invalidations, 2);
      expect(saves, 0);
    },
  );
  test(
    'logout/account switch while renewal is in flight cannot persist or invalidate new identity',
    () async {
      final gate = Completer<Map<String, dynamic>>();
      request = (_, _) => gate.future;
      final pending = run();
      current = false;
      gate.complete({'token': renewed, 'clientId': 17, 'agentId': 4});
      expect(await pending, isNull);
      expect(saves, 0);
      expect(invalidations, 0);
    },
  );
  test('late old-session 401 cannot logout new identity', () async {
    final gate = Completer<Map<String, dynamic>>();
    request = (_, _) => gate.future;
    final pending = run();
    current = false;
    gate.completeError(const ClientRenewalException(401));
    expect(await pending, isNull);
    expect(invalidations, 0);
  });
  test('foreign/malformed response is never persisted', () async {
    request = (_, _) async => {
      'token': jwt(now, now + day, agent: 5),
      'clientId': 17,
      'agentId': 5,
    };
    expect(await run(), old);
    expect(saves, 0);
  });
  test(
    'absolute session cap may shorten expiry while keeping live renewed token',
    () async {
      renewed = jwt(
        now,
        now + 5 * day,
        extra: {'clientSessionStartedAt': now - 360 * day},
      );
      expect(await run(), renewed);
      expect(saves, 1);
    },
  );
  test(
    'generic proxy403 keeps valid session and backs off instead of forced logout',
    () async {
      request = (_, _) async {
        calls++;
        throw const ClientRenewalException(403);
      };
      expect(await run(), old);
      expect(await run(), old);
      expect(calls, 1);
      expect(invalidations, 0);
      expect(saves, 0);
    },
  );
  test(
    'two active contexts adopt same-family persisted winner instead of retaining old bearer',
    () async {
      final origin = now - 2 * day;
      final winner = jwt(
        now - 10,
        now + 30 * day - 10,
        extra: {'clientSessionStartedAt': origin},
      );
      String? shared = old;
      final tabA = ClientSessionRenewal(
        now: () => DateTime.fromMillisecondsSinceEpoch(now * 1000),
      );
      final tabB = ClientSessionRenewal(
        now: () => DateTime.fromMillisecondsSinceEpoch(now * 1000),
      );
      Future<String?> activity(ClientSessionRenewal tab) => tab.tokenForRequest(
        token: old,
        origin: 'tenant',
        generation: 1,
        isCurrent: () => true,
        request: (_, _) async => {
          'token': winner,
          'clientId': 17,
          'agentId': 4,
        },
        persist: (candidate) async {
          final decision = classifyPersistedClientSession(
            old,
            shared,
            DateTime.fromMillisecondsSinceEpoch(now * 1000),
          );
          if (decision == PersistedClientSession.sameFamilyWinner) {
            return shared;
          }
          if (decision == PersistedClientSession.changed) return null;
          shared = candidate;
          return candidate;
        },
        invalidate: () => fail('Active same-family tab must not logout'),
      );
      expect(await activity(tabA), winner);
      expect(await activity(tabB), winner);
      expect(shared, winner);
    },
  );
  test(
    'shared logout/different owner or different login family never resurrects old token',
    () {
      final date = DateTime.fromMillisecondsSinceEpoch(now * 1000);
      for (final shared in <String?>[
        null,
        jwt(now, now + day, uid: 18),
        jwt(now, now + day),
        jwt(now, now - 1, extra: {'clientSessionStartedAt': now - 2 * day}),
      ]) {
        expect(
          classifyPersistedClientSession(old, shared, date),
          PersistedClientSession.changed,
        );
      }
      expect(
        classifyPersistedClientSession(old, old, date),
        PersistedClientSession.unchanged,
      );
      final sameOwnerOtherAgent = jwt(
        now,
        now + day,
        extra: {'agentId': 5, 'clientSessionStartedAt': now - 2 * day},
      );
      expect(
        classifyPersistedClientSession(old, sameOwnerOtherAgent, date),
        PersistedClientSession.changed,
      );
    },
  );
}
