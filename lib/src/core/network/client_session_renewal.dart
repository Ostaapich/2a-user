import 'dart:async';
import 'dart:convert';

Map<String, dynamic>? clientSessionClaims(String? token) {
  try {
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final value = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    return value is Map ? Map<String, dynamic>.from(value) : null;
  } catch (_) {
    return null;
  }
}

enum PersistedClientSession { unchanged, sameFamilyWinner, changed }

/// Only accepts a persisted winner belonging to this exact signed session family.
PersistedClientSession classifyPersistedClientSession(
  String previous,
  String? stored,
  DateTime now,
) {
  if (stored == previous) return PersistedClientSession.unchanged;
  final old = clientSessionClaims(previous),
      winner = clientSessionClaims(stored);
  if (!ClientSessionRenewal.isClient(old) ||
      !ClientSessionRenewal.isClient(winner)) {
    return PersistedClientSession.changed;
  }
  final start = old!['clientSessionStartedAt'] ?? old['iat'];
  final otherStart = winner!['clientSessionStartedAt'] ?? winner['iat'];
  final expires = winner['exp'];
  if (start is! int ||
      otherStart != start ||
      old['uid'] != winner['uid'] ||
      old['agentId'] != winner['agentId'] ||
      expires is! num ||
      !expires.isFinite ||
      expires <= now.millisecondsSinceEpoch ~/ 1000) {
    return PersistedClientSession.changed;
  }
  return PersistedClientSession.sameFamilyWinner;
}

class ClientRenewalException implements Exception {
  const ClientRenewalException(this.status, [this.code]);
  final int? status;
  final String? code;
}

/// Decoded JWT fields schedule renewal only. The server verifies authenticity.
class ClientSessionRenewal {
  ClientSessionRenewal({DateTime Function()? now}) : now = now ?? DateTime.now;
  final DateTime Function() now;
  final _pending = <(String, String, int), Future<String?>>{};
  final _retryAfter = <String, DateTime>{};

  static bool isClient(Map<String, dynamic>? c) =>
      c != null &&
      c['type'] == 'client' &&
      c['role'] == 'client' &&
      c['uid'] is int &&
      c['uid'] > 0 &&
      c['agentId'] is int &&
      c['agentId'] > 0 &&
      c['impersonatorUid'] == null &&
      c['impersonationReadOnly'] == null &&
      c['impersonatorSessionId'] == null;

  Future<String?> tokenForRequest({
    required String token,
    required String origin,
    required int generation,
    required bool Function() isCurrent,
    required Future<Map<String, dynamic>> Function(int clientId, int agentId)
    request,
    required Future<String?> Function(String token) persist,
    required void Function() invalidate,
  }) async {
    if (!isCurrent()) return null;
    final claims = clientSessionClaims(token);
    if (!isClient(claims)) return token;
    final issued = claims!['iat'], expires = claims['exp'];
    final seconds = now().millisecondsSinceEpoch ~/ 1000;
    if (issued is! num ||
        expires is! num ||
        !issued.isFinite ||
        !expires.isFinite ||
        expires <= seconds ||
        issued > seconds + 60) {
      return token;
    }
    if (seconds - issued < const Duration(days: 1).inSeconds &&
        expires - seconds > const Duration(days: 2).inSeconds) {
      return token;
    }
    if (_retryAfter[origin]?.isAfter(now()) == true) return token;
    final key = (token, origin, generation);
    final existing = _pending[key];
    if (existing != null) return existing;
    final future = _renew(
      token,
      origin,
      claims,
      isCurrent,
      request,
      persist,
      invalidate,
    );
    _pending[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_pending[key], future)) _pending.remove(key);
    }
  }

  Future<String?> _renew(
    String old,
    String origin,
    Map<String, dynamic> claims,
    bool Function() current,
    Future<Map<String, dynamic>> Function(int, int) request,
    Future<String?> Function(String) persist,
    void Function() invalidate,
  ) async {
    try {
      final response = await request(
        claims['uid'] as int,
        claims['agentId'] as int,
      );
      if (!current()) return null;
      final token = response['token'];
      final next = clientSessionClaims(token is String ? token : null);
      if (!isClient(next) ||
          next!['uid'] != claims['uid'] ||
          next['agentId'] != claims['agentId'] ||
          response['clientId'] != claims['uid'] ||
          response['agentId'] != claims['agentId'] ||
          next['exp'] is! num ||
          !(next['exp'] as num).isFinite ||
          next['exp'] <= now().millisecondsSinceEpoch ~/ 1000 ||
          next['iat'] is! num ||
          next['iat'] < claims['iat'] ||
          next['iat'] > now().millisecondsSinceEpoch ~/ 1000 + 60) {
        _retryAfter[origin] = now().add(const Duration(minutes: 1));
        return old;
      }
      final accepted = await persist(token as String);
      if (accepted == null) {
        _retryAfter[origin] = now().add(const Duration(minutes: 1));
        return current() ? old : null;
      }
      return current() ? accepted : null;
    } on ClientRenewalException catch (error) {
      if (!current()) return null;
      if (error.status == 401 ||
          (error.status == 409 && error.code == 'ACCOUNT_CHANGED')) {
        invalidate();
        return null;
      }
      _retryAfter[origin] = now().add(
        const [404, 405, 501].contains(error.status)
            ? const Duration(days: 1)
            : const Duration(minutes: 1),
      );
      return old;
    } catch (_) {
      _retryAfter[origin] = now().add(const Duration(minutes: 1));
      return current() ? old : null;
    }
  }
}
