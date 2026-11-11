import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'workflow_event_contract.dart';
import '../network/media_http_adapter.dart';

class WorkflowTransportIdentity {
  const WorkflowTransportIdentity({
    required this.token,
    required this.clientId,
    required this.agentId,
  }) : sessionId = null,
       companyDomain = null;
  const WorkflowTransportIdentity.anonymous({
    required this.sessionId,
    this.companyDomain,
  }) : token = '',
       clientId = 0,
       agentId = 0;
  final String? sessionId, companyDomain;
  bool get isAnonymous => sessionId != null;
  final String token;
  final int clientId, agentId;
  String get storageOwner => sha256
      .convert(
        utf8.encode(
          isAnonymous
              ? 'anonymous:$sessionId:$companyDomain'
              : '$clientId:$agentId:$token',
        ),
      )
      .toString();
}

/// Optional, bounded telemetry; queued payload never contains credentials or business data.
/// Each HTTP request freezes its bearer and expected owner instead of using an interceptor
/// that could replace the bearer after a concurrent account switch.
class WorkflowEventQueue {
  WorkflowEventQueue({
    required this.preferences,
    required this.readIdentity,
    required this.endpoint,
    this.automaticFlush = true,
    this.persistEvents = true,
    Dio? transport,
  }) : _dio =
           transport ??
           Dio(BaseOptions(connectTimeout: const Duration(seconds: 5))) {
    _dio.httpClientAdapter = wrapMediaHttpAdapter(_dio.httpClientAdapter);
  }
  static const storageKey = 'workflow_events_v1';
  static const maxPending = 180;
  final SharedPreferences preferences;
  final Future<WorkflowTransportIdentity?> Function() readIdentity;
  final String endpoint;
  final bool automaticFlush, persistEvents;
  final Dio _dio;
  final List<Map<String, dynamic>> _pending = [];
  Future<void> _serial = Future.value();
  bool _loaded = false, _flushing = false, _disposed = false;
  String? _owner;
  int _generation = 0, _retry = 0;
  Timer? _timer;
  CancelToken? _requestCancel;
  int get pendingCount => _pending.length;

  Future<void> _local(Future<void> Function() action) {
    final task = _serial.then((_) async {
      if (!_disposed) await action();
    });
    _serial = task.catchError((Object _) {});
    return task;
  }

  bool _valid(Map fields) =>
      fields.keys.every((key) => {'action', 'stage', 'reason'}.contains(key)) &&
      WorkflowAction.values.any((v) => v.name == fields['action']) &&
      WorkflowStage.values.any((v) => v.name == fields['stage']) &&
      (!fields.containsKey('reason') ||
          WorkflowFailure.values.any((v) => v.name == fields['reason']));

  Future<void> _sync(WorkflowTransportIdentity? identity) async {
    if (!_loaded) {
      _loaded = true;
      try {
        final stored = !persistEvents
            ? null
            : jsonDecode(preferences.getString(storageKey) ?? 'null');
        if (stored is Map &&
            stored['owner'] is String &&
            stored['events'] is List) {
          _owner = stored['owner'] as String;
          for (final raw in (stored['events'] as List).take(maxPending)) {
            if (raw is! Map) continue;
            final row = Map<String, dynamic>.from(raw);
            final date = DateTime.tryParse(row['occurredAt']?.toString() ?? '');
            final fields = Map<String, dynamic>.from(row)
              ..remove('id')
              ..remove('occurredAt');
            if (_valid(fields) &&
                row['id'] is String &&
                RegExp(
                  r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
                ).hasMatch(row['id'] as String) &&
                date != null &&
                DateTime.now().toUtc().difference(date).inHours < 24) {
              _pending.add(row);
            }
          }
        }
      } catch (_) {
        /* Corrupt optional telemetry is discarded. */
      }
    }
    final owner = identity?.storageOwner;
    if (owner != _owner) {
      _pending.clear();
      _owner = owner;
      _retry = 0;
    }
    _pending.removeWhere((row) {
      final date = DateTime.tryParse(row['occurredAt']?.toString() ?? '');
      final age = date == null ? null : DateTime.now().toUtc().difference(date);
      return age == null || age.inHours >= 24 || age.inMinutes < -5;
    });
    await _persist();
  }

  Future<void> _persist() async {
    if (!persistEvents) return;
    if (_owner == null || _pending.isEmpty) {
      await preferences.remove(storageKey);
    } else {
      await preferences.setString(
        storageKey,
        jsonEncode({'owner': _owner, 'events': _pending}),
      );
    }
  }

  void sessionChanged() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _requestCancel?.cancel('session_changed');
    unawaited(
      _local(() async {
        await _sync(await readIdentity());
      }).catchError((Object _) {}),
    );
    if (automaticFlush) _schedule(Duration.zero);
  }

  Future<void> enqueue(Map<String, Object> fields) async {
    if (!_valid(fields) || _disposed) return;
    final generation = _generation;
    await _local(() async {
      final identity = await readIdentity();
      if (_disposed || generation != _generation) return;
      await _sync(identity);
      if (identity == null) {
        return; // Never reassign pre-auth events to a later account.
      }
      if (_disposed || generation != _generation) return;
      _pending.add({
        'id': const Uuid().v4(),
        'occurredAt': DateTime.now().toUtc().toIso8601String(),
        ...fields,
      });
      if (_pending.length > maxPending) {
        _pending.removeRange(0, _pending.length - maxPending);
      }
      await _persist();
    });
    if (automaticFlush) _schedule(const Duration(milliseconds: 300));
  }

  void _schedule(Duration delay) {
    if (_disposed || _timer?.isActive == true) return;
    _timer = Timer(delay, () {
      _timer = null;
      unawaited(flush());
    });
  }

  Future<void> flush() async {
    if (_disposed) return;
    if (_flushing) {
      if (automaticFlush && _pending.isNotEmpty) {
        _schedule(const Duration(seconds: 1));
      }
      return;
    }
    _flushing = true;
    final generation = _generation;
    WorkflowTransportIdentity? identity;
    List<Map<String, dynamic>> batch = [];
    try {
      await _local(() async {
        identity = await readIdentity();
        if (_disposed || generation != _generation) return;
        await _sync(identity);
        batch = _pending
            .take(identity?.isAnonymous == true ? 10 : 20)
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
      });
      if (identity == null ||
          batch.isEmpty ||
          _disposed ||
          generation != _generation) {
        return;
      }
      final current = await readIdentity();
      if (current?.storageOwner != identity!.storageOwner ||
          _disposed ||
          generation != _generation) {
        return;
      }
      final cancel = CancelToken();
      _requestCancel = cancel;
      final deadline = Timer(
        const Duration(seconds: 8),
        () => cancel.cancel('telemetry_timeout'),
      );
      final Response<dynamic> response;
      try {
        response = await _dio.post<dynamic>(
          endpoint,
          cancelToken: cancel,
          data: identity!.isAnonymous
              ? {
                  'sessionId': identity!.sessionId,
                  if (identity!.companyDomain != null)
                    'companyDomain': identity!.companyDomain,
                  'events': batch,
                }
              : {
                  'expectedClientId': identity!.clientId,
                  'expectedAgentId': identity!.agentId,
                  'events': batch,
                },
          options: Options(
            extra: {'workflow_no_redirect': true},
            headers: {
              if (!identity!.isAnonymous)
                'Authorization': 'Bearer ${identity!.token}',
            },
            followRedirects: false,
            maxRedirects: 0,
            sendTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          ),
        );
      } finally {
        deadline.cancel();
        if (identical(_requestCancel, cancel)) _requestCancel = null;
      }
      final accepted = response.data is Map
          ? response.data['acceptedIds']
          : null;
      final expected = batch.map((e) => e['id']).toSet();
      if (response.statusCode != 200 ||
          accepted is! List ||
          accepted.length != expected.length ||
          !accepted.toSet().containsAll(expected)) {
        throw const FormatException('Incomplete workflow acknowledgement');
      }
      await _local(() async {
        final owner = await readIdentity();
        if (_disposed ||
            generation != _generation ||
            owner?.storageOwner != identity!.storageOwner) {
          return;
        }
        _pending.removeWhere((row) => expected.contains(row['id']));
        _retry = 0;
        await _persist();
      });
    } catch (_) {
      _retry = (_retry + 1).clamp(0, 6);
    } finally {
      _flushing = false;
      if (automaticFlush &&
          !_disposed &&
          _pending.isNotEmpty &&
          generation == _generation) {
        _schedule(
          Duration(
            seconds: _retry == 0 ? 1 : (5 * (1 << (_retry - 1))).clamp(5, 120),
          ),
        );
      }
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _dio.close(force: true);
  }
}
