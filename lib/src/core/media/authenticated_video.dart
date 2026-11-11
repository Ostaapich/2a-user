import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import 'authenticated_media.dart';
import 'browser_video_session.dart';
import '../network/api_config.dart';
import 'media_file_metadata.dart';
import 'private_video_source_stub.dart'
    if (dart.library.io) 'private_video_source_io.dart'
    if (dart.library.js_interop) 'private_video_source_web.dart';

class _StreamingVideoController extends VideoPlayerController {
  _StreamingVideoController(
    super.url, {
    super.httpHeaders,
    this.session,
    this.progressivePlayback = false,
  }) : super.networkUrl() {
    if (_usesProgressiveIOS) addListener(_resumeBufferedPlayback);
  }
  final BrowserVideoSession? session;
  final bool progressivePlayback;
  static const _playbackChannel = MethodChannel(
    'com.twoalogistic.user/video_playback',
  );
  bool _wantsToPlay = false;
  bool _resuming = false;
  bool _disposed = false;
  bool _nativePlaybackAvailable = true;
  bool get _usesProgressiveIOS =>
      progressivePlayback &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _playAvailable() async {
    if (_disposed ||
        !_wantsToPlay ||
        !value.isInitialized ||
        _resuming ||
        !_nativePlaybackAvailable) {
      return;
    }
    _resuming = true;
    try {
      await _playbackChannel.invokeMethod<void>('playAvailable', {
        // The plugin exposes this handle for native integration; never persist it.
        // ignore: invalid_use_of_visible_for_testing_member
        'playerId': playerId,
        'rate': value.playbackSpeed,
      });
    } on MissingPluginException {
      // Dart can be hot-reloaded while the installed native runner is older.
      // Buffer tuning is optional: the initialized video must keep playing.
      _nativePlaybackAvailable = false;
      debugPrint(
        '[VideoPlayback] Native buffer tuning unavailable; using standard playback',
      );
    } on PlatformException catch (error) {
      _nativePlaybackAvailable = false;
      debugPrint(
        '[VideoPlayback] Native buffer tuning failed (${error.code}); using standard playback',
      );
    } finally {
      _resuming = false;
    }
  }

  void _resumeBufferedPlayback() {
    if (!_usesProgressiveIOS ||
        !_wantsToPlay ||
        _disposed ||
        _resuming ||
        !value.isBuffering ||
        value.hasError ||
        value.isCompleted) {
      return;
    }
    // AVPlayer may reset its actual rate after a stall. Resume only when the
    // current position (including a seek target) has playable data ahead.
    final position = value.position;
    final hasBuffer = value.buffered.any(
      (range) =>
          range.start <= position &&
          range.end > position &&
          (range.end >= value.duration ||
              range.end - position >= const Duration(seconds: 1)),
    );
    if (hasBuffer) {
      unawaited(
        _playAvailable().catchError((Object error) {
          debugPrint('[VideoPlayback] resume failed: $error');
        }),
      );
    }
  }

  @override
  Future<void> play() async {
    _wantsToPlay = true;
    await super.play();
    if (_usesProgressiveIOS) await _playAvailable();
  }

  @override
  Future<void> pause() async {
    _wantsToPlay = false;
    await super.pause();
  }

  @override
  Future<void> seekTo(Duration position) async {
    await super.seekTo(position);
    if (_usesProgressiveIOS && _wantsToPlay) await _playAvailable();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _wantsToPlay = false;
    if (_usesProgressiveIOS) removeListener(_resumeBufferedPlayback);
    try {
      await super.dispose();
    } finally {
      await session?.dispose();
    }
  }
}

/// Signed scan recordings stream through their capability URL without bearer
/// headers. Other protected videos consume disposable local media.
Future<VideoPlayerController> createAuthenticatedVideoController(
  BuildContext context,
  String url, {
  bool progressivePlayback = false,
}) async {
  final path = authenticatedMediaPath(url);
  if (path != null) {
    final uri = Uri.parse(path);
    if (uri.path == '/assembly-scan-media/playback' &&
        (uri.queryParameters['token']?.isNotEmpty ?? false)) {
      // Preserve Range playback for large recordings. The signed token is the
      // credential; never give a platform player the account bearer token.
      return VideoPlayerController.networkUrl(
        Uri.parse('${ApiConfig.baseUrl}$path'),
      );
    }
  }
  if (path == null) {
    return VideoPlayerController.networkUrl(Uri.parse(url));
  }
  if (photoDeskVideoPath(path) != null) {
    final api = mediaApiClient(context);
    if (kIsWeb) {
      late _StreamingVideoController controller;
      final session = await BrowserVideoSession.open(
        path: path,
        getToken: api.getToken,
        getSessionIdentity: () async =>
            '${api.activeBaseUrl}:${await api.getMediaCacheIdentity()}',
        onInvalid: () {
          controller.pause().ignore();
        },
      );
      controller = _StreamingVideoController(session.url, session: session);
      return controller;
    }
    final token = await api.getToken();
    if (token == null || token.isEmpty) {
      throw StateError('Media authentication required');
    }
    return _StreamingVideoController(
      Uri.parse('${ApiConfig.baseUrl}$path'),
      progressivePlayback: progressivePlayback,
      httpHeaders: {'Authorization': 'Bearer $token'},
    );
  }
  final bytes = await loadMediaBytes(mediaApiClient(context), url);
  final mime = mediaMimeType(url, isVideo: true);
  return createPrivateVideoSource(bytes, mime);
}
