import 'dart:async';

import 'package:dio/dio.dart';

/// Only the dedicated PhotoDesk MP4 namespace can use a browser session.
String? photoDeskVideoPath(String path) {
  final uri = Uri.tryParse(path);
  if (uri == null ||
      uri.hasAuthority ||
      uri.hasScheme ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  if (!RegExp(
    r'^/uploads/photodesk-videos/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_.-]+\.mp4$',
  ).hasMatch(path)) {
    return null;
  }
  if (uri.pathSegments.any((part) => part == '.' || part == '..')) return null;
  return path;
}

/// A same-origin, HttpOnly, asset-bound cookie lets the browser seek with Range.
/// The account token is used only to bootstrap/renew; never in the video URL.
class BrowserVideoSession {
  BrowserVideoSession._(
    this._dio,
    this._ownsDio,
    this._origin,
    this._path,
    this._token,
    this._identity,
    this._getSessionIdentity,
    this._refreshEvery,
    this._onInvalid,
  );

  final Dio _dio;
  final bool _ownsDio;
  final Uri _origin;
  final String _path, _token, _identity;
  final Future<String?> Function() _getSessionIdentity;
  final Duration _refreshEvery;
  final void Function()? _onInvalid;
  Timer? _timer;
  bool _disposed = false, _renewing = false;
  String? _grantId;
  late Uri url;

  static Future<BrowserVideoSession> open({
    required String path,
    required Future<String?> Function() getToken,
    // A renewed bearer is still the same owner. Legacy callers without this
    // callback retain strict raw-token comparison.
    Future<String?> Function()? getSessionIdentity,
    Uri? origin,
    Dio? transport,
    Duration refreshEvery = const Duration(minutes: 10),
    void Function()? onInvalid,
  }) async {
    if (photoDeskVideoPath(path) == null) {
      throw StateError('Invalid video path');
    }
    final base = origin ?? Uri.base;
    if (!const ['https', 'http'].contains(base.scheme) || base.host.isEmpty) {
      throw StateError('Invalid browser origin');
    }
    final readIdentity = getSessionIdentity ?? getToken;
    final identity = await readIdentity();
    final token = await getToken();
    if (token == null ||
        token.isEmpty ||
        identity == null ||
        identity.isEmpty) {
      throw StateError('Media authentication required');
    }
    if (await readIdentity() != identity) {
      throw StateError('Media session changed');
    }
    final session = BrowserVideoSession._(
      transport ?? Dio(),
      transport == null,
      Uri.parse(base.origin),
      path,
      token,
      identity,
      readIdentity,
      refreshEvery,
      onInvalid,
    );
    try {
      await session._grant();
      return session;
    } catch (_) {
      await session.dispose();
      rethrow;
    }
  }

  Future<void> _grant() async {
    if (_disposed) return;
    final response = await _dio.get<dynamic>(
      _origin.resolve('/private-media/session').toString(),
      queryParameters: {'path': _path},
      options: Options(
        responseType: ResponseType.json,
        followRedirects: false,
        receiveTimeout: const Duration(seconds: 15),
        headers: {'Authorization': 'Bearer $_token'},
      ),
    );
    final data = response.data;
    final expected = _path.replaceFirst('/uploads/', '/private-media/');
    if (response.statusCode != 200 ||
        data is! Map ||
        data['url'] != expected ||
        data['expiresIn'] is! int ||
        data['expiresIn'] < 1 ||
        data['expiresIn'] > 900 ||
        data['grantId'] is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
        ).hasMatch(data['grantId'])) {
      throw StateError('Invalid media session response');
    }
    final nextUrl = _origin.resolve(expected),
        nextGrant = data['grantId'] as String;
    if (_disposed || await _getSessionIdentity() != _identity) {
      await _clear(nextUrl, nextGrant);
      if (!_disposed) throw StateError('Media session changed');
      return;
    }
    url = nextUrl;
    _grantId = nextGrant;
    _timer?.cancel();
    final seconds = ((data['expiresIn'] as int) * 2 / 3).floor();
    final lifetime = Duration(seconds: seconds < 1 ? 1 : seconds);
    _timer = Timer(_refreshEvery < lifetime ? _refreshEvery : lifetime, renew);
  }

  Future<void> renew() async {
    if (_disposed || _renewing) return;
    _renewing = true;
    try {
      if (await _getSessionIdentity() != _identity) {
        throw StateError('Media session changed');
      }
      await _grant();
    } catch (_) {
      _onInvalid?.call();
      await dispose();
    } finally {
      _renewing = false;
      if (_disposed && _ownsDio) _dio.close();
    }
  }

  Future<void> _clear(Uri asset, String grant) async {
    try {
      await _dio.get<dynamic>(
        asset.toString(),
        queryParameters: {'media-clear': '1', 'grantId': grant},
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: false,
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
    } catch (_) {
      // Expiry and live server authorization remain the fail-closed boundary.
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    final grant = _grantId;
    if (grant != null) await _clear(url, grant);
    // An in-flight renewal owns its final guarded clear before closing Dio.
    if (_ownsDio && !_renewing) _dio.close();
  }
}
