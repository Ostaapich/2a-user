import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/media/browser_video_session.dart';

const asset = '/uploads/photodesk-videos/PHOTODESK1/report-1/video-sha.mp4';
const privateAsset =
    '/private-media/photodesk-videos/PHOTODESK1/report-1/video-sha.mp4';
const firstGrant = '11111111-1111-4111-8111-111111111111';
const nextGrant = '22222222-2222-4222-8222-222222222222';

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Future<Map<String, dynamic>> Function()? grant;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.queryParameters['media-clear'] == '1') {
      return ResponseBody.fromString('', 204);
    }
    final data =
        await (grant?.call() ??
            Future.value({
              'url': privateAsset,
              'expiresIn': 900,
              'grantId': firstGrant,
            }));
    return ResponseBody.fromString(
      jsonEncode(data),
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
  test('only exact relative PhotoDesk MP4 paths can acquire sessions', () {
    expect(photoDeskVideoPath(asset), asset);
    for (final path in [
      'https://evil.test$asset',
      '//evil.test$asset',
      '$asset?token=secret',
      '$asset#fragment',
      '/uploads/elsewhere/a.mp4',
      '/uploads/photodesk-videos/../a.mp4',
      '/uploads/photodesk-videos/%2e%2e/a.mp4',
      '/uploads/photodesk-videos/a.jpg',
    ]) {
      expect(photoDeskVideoPath(path), isNull, reason: path);
    }
  });

  test(
    'same-origin bootstrap and guarded exact-path cleanup never put bearer in URLs',
    () async {
      final adapter = _Adapter(), dio = Dio();
      dio.httpClientAdapter = adapter;
      final session = await BrowserVideoSession.open(
        path: asset,
        getToken: () async => 'account-secret',
        origin: Uri.parse('https://cabinet.example/app#/tracks/1'),
        transport: dio,
      );
      expect(session.url.toString(), 'https://cabinet.example$privateAsset');
      expect(session.url.hasQuery, isFalse);
      expect(adapter.requests.single.uri.origin, 'https://cabinet.example');
      expect(adapter.requests.single.uri.path, '/private-media/session');
      expect(adapter.requests.single.queryParameters, {'path': asset});
      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer account-secret',
      );
      await session.dispose();
      await session.dispose();
      expect(adapter.requests.length, 2);
      final clear = adapter.requests.last;
      expect(clear.uri.path, privateAsset);
      expect(clear.queryParameters, {
        'media-clear': '1',
        'grantId': firstGrant,
      });
      expect(clear.headers['Authorization'], isNull);
      expect(
        adapter.requests.every(
          (r) => !r.uri.toString().contains('account-secret'),
        ),
        isTrue,
      );
    },
  );

  test(
    'foreign, absolute, query-bearing or malformed session responses are rejected',
    () async {
      for (final patch in [
        {'url': 'https://cabinet.example$privateAsset'},
        {'url': 'https://evil.test$privateAsset'},
        {'url': '$privateAsset?token=secret'},
        {'url': '/private-media/photodesk-videos/other.mp4'},
        {'grantId': 'not-a-grant'},
        {'expiresIn': 0},
        {'expiresIn': 901},
      ]) {
        final adapter = _Adapter()
          ..grant = () async => {
            'url': privateAsset,
            'expiresIn': 900,
            'grantId': firstGrant,
            ...patch,
          };
        final dio = Dio()..httpClientAdapter = adapter;
        await expectLater(
          BrowserVideoSession.open(
            path: asset,
            getToken: () async => 'secret',
            origin: Uri.parse('https://cabinet.example'),
            transport: dio,
          ),
          throwsStateError,
        );
      }
    },
  );

  test(
    'renew checks current session identity and disposal clears only its latest grant',
    () async {
      final adapter = _Adapter(), dio = Dio();
      dio.httpClientAdapter = adapter;
      var token = 'first-account';
      var invalid = 0;
      final session = await BrowserVideoSession.open(
        path: asset,
        getToken: () async => token,
        origin: Uri.parse('https://cabinet.example'),
        transport: dio,
        onInvalid: () => invalid++,
      );
      adapter.grant = () async => {
        'url': privateAsset,
        'expiresIn': 900,
        'grantId': nextGrant,
      };
      await session.renew();
      token = 'other-account';
      await session.renew();
      expect(invalid, 1);
      expect(
        adapter.requests
            .where((r) => r.uri.path == '/private-media/session')
            .length,
        2,
      );
      expect(adapter.requests.last.queryParameters['grantId'], nextGrant);
      await session.dispose();
    },
  );

  test(
    'a renewal finishing after disposal cleans its own newly issued grant',
    () async {
      final adapter = _Adapter(), dio = Dio();
      dio.httpClientAdapter = adapter;
      final session = await BrowserVideoSession.open(
        path: asset,
        getToken: () async => 'secret',
        origin: Uri.parse('https://cabinet.example'),
        transport: dio,
      );
      final pending = Completer<Map<String, dynamic>>(),
          entered = Completer<void>();
      adapter.grant = () {
        entered.complete();
        return pending.future;
      };
      final renewal = session.renew();
      await entered.future;
      await session.dispose();
      pending.complete({
        'url': privateAsset,
        'expiresIn': 900,
        'grantId': nextGrant,
      });
      await renewal;
      expect(
        adapter.requests
            .where((r) => r.queryParameters['media-clear'] == '1')
            .map((r) => r.queryParameters['grantId']),
        [firstGrant, nextGrant],
      );
    },
  );
  test(
    'identity changing while a renewal is in flight revokes both old and newly issued grants',
    () async {
      final adapter = _Adapter(), dio = Dio();
      dio.httpClientAdapter = adapter;
      var token = 'first-account';
      var invalid = 0;
      final session = await BrowserVideoSession.open(
        path: asset,
        getToken: () async => token,
        origin: Uri.parse('https://cabinet.example'),
        transport: dio,
        onInvalid: () => invalid++,
      );
      final pending = Completer<Map<String, dynamic>>(),
          entered = Completer<void>();
      adapter.grant = () {
        entered.complete();
        return pending.future;
      };
      final renewal = session.renew();
      await entered.future;
      token = 'other-account';
      pending.complete({
        'url': privateAsset,
        'expiresIn': 900,
        'grantId': nextGrant,
      });
      await renewal;
      expect(invalid, 1);
      expect(
        adapter.requests
            .where((r) => r.queryParameters['media-clear'] == '1')
            .map((r) => r.queryParameters['grantId']),
        [nextGrant, firstGrant],
      );
      await session.dispose();
    },
  );
  test(
    'same-owner bearer rotation during bootstrap and renew keeps video alive',
    () async {
      final adapter = _Adapter(), dio = Dio();
      dio.httpClientAdapter = adapter;
      var token = 'old-bearer';
      const identity = 'api-origin:session-epoch:original-anchor';
      var invalid = 0;
      final pending = Completer<Map<String, dynamic>>();
      final entered = Completer<void>();
      adapter.grant = () {
        entered.complete();
        return pending.future;
      };
      final opening = BrowserVideoSession.open(
        path: asset,
        getToken: () async => token,
        getSessionIdentity: () async => identity,
        origin: Uri.parse('https://cabinet.example'),
        transport: dio,
        onInvalid: () => invalid++,
      );
      await entered.future;
      token = 'renewed-bearer';
      pending.complete({
        'url': privateAsset,
        'expiresIn': 900,
        'grantId': firstGrant,
      });
      final session = await opening;
      adapter.grant = () async => {
        'url': privateAsset,
        'expiresIn': 900,
        'grantId': nextGrant,
      };
      await session.renew();
      expect(invalid, 0);
      final grants = adapter.requests
          .where((r) => r.uri.path == '/private-media/session')
          .toList();
      expect(grants.length, 2);
      // Existing server-valid bearer remains private to this playback session.
      expect(
        grants.every((r) => r.headers['Authorization'] == 'Bearer old-bearer'),
        isTrue,
      );
      await session.dispose();
      expect(adapter.requests.last.queryParameters['grantId'], nextGrant);
    },
  );

  for (final change in ['logout', 'client', 'agent', 'domain']) {
    test(
      'stable media identity still rejects $change during in-flight grant',
      () async {
        final adapter = _Adapter(), dio = Dio();
        dio.httpClientAdapter = adapter;
        var identity = 'original-session';
        var invalid = 0;
        final session = await BrowserVideoSession.open(
          path: asset,
          getToken: () async => 'unchanged-cached-bearer',
          getSessionIdentity: () async => identity,
          origin: Uri.parse('https://cabinet.example'),
          transport: dio,
          onInvalid: () => invalid++,
        );
        final pending = Completer<Map<String, dynamic>>(),
            entered = Completer<void>();
        adapter.grant = () {
          entered.complete();
          return pending.future;
        };
        final renewing = session.renew();
        await entered.future;
        identity = 'changed-$change';
        pending.complete({
          'url': privateAsset,
          'expiresIn': 900,
          'grantId': nextGrant,
        });
        await renewing;
        expect(invalid, 1);
        expect(
          adapter.requests
              .where((r) => r.queryParameters['media-clear'] == '1')
              .map((r) => r.queryParameters['grantId']),
          [nextGrant, firstGrant],
        );
        await session.dispose();
      },
    );
  }
}
