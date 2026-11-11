import 'dart:js_interop';
import 'browser_media_export_types.dart';

@JS('twoaBrowserMediaExports.begin')
external JSPromise<JSAny?> _begin(JSObject options);
@JS('twoaBrowserMediaExports.sharePrepared')
external JSPromise<JSAny?> _share(JSString id);
@JS('twoaBrowserMediaExports.cancelAll')
external void _cancelAll();
@JS('twoaBrowserMediaExports.cancel')
external void _cancel(JSString id);
@JS('twoaBrowserMediaExports.clearPrepared')
external void _clearPrepared(JSString id);

BrowserMediaExportResult _result(JSAny? value) {
  final data = value.dartify();
  if (data is! Map) throw StateError('Invalid browser export response');
  final kind = switch (data['kind']) {
    'downloaded' => BrowserMediaExportKind.downloaded,
    'shareReady' => BrowserMediaExportKind.shareReady,
    'shared' => BrowserMediaExportKind.shared,
    'cancelled' => BrowserMediaExportKind.cancelled,
    _ => throw StateError('Invalid browser export response'),
  };
  final id = data['preparedId'];
  if (kind == BrowserMediaExportKind.shareReady &&
      (id is! String || !RegExp(r'^[a-f0-9-]{36}$').hasMatch(id))) {
    throw StateError('Invalid browser share response');
  }
  return BrowserMediaExportResult(kind, preparedId: id is String ? id : null);
}

Future<BrowserMediaExportResult> beginBrowserMediaExport(
  BrowserMediaExportRequest request,
) async {
  final identity =
      (() => request.getIdentity().then((value) => value.toJS).toJS).toJS;
  final progress = ((JSNumber received, JSNumber total) {
    request.onProgress?.call(received.toDartInt, total.toDartInt);
  }).toJS;
  final options =
      <String, Object?>{
            'operationId': request.operationId,
            'url': request.url,
            'name': request.name,
            'apiBase': request.apiBase,
            'identity': request.identity,
            'getIdentity': identity,
            'progress': progress,
            'token': request.token,
            'mode': request.share ? 'share' : 'download',
          }.jsify()
          as JSObject;
  try {
    return _result(await _begin(options).toDart);
  } catch (error) {
    throw _failure(error);
  }
}

Future<BrowserMediaExportResult> sharePreparedBrowserMedia(String id) async {
  try {
    return _result(await _share(id.toJS).toDart);
  } catch (error) {
    throw _failure(error);
  }
}

void clearPreparedBrowserMedia(String id) {
  try {
    _clearPrepared(id.toJS);
  } catch (_) {
    /* Optional bridge before web bootstrap. */
  }
}

void cancelActiveBrowserMediaExports() {
  try {
    _cancelAll();
  } catch (_) {
    /* Native tests and early bootstrap have no bridge. */
  }
}

BrowserMediaExportException _failure(Object error) {
  final text = error.toString();
  for (final code in [
    'session_changed',
    'cancelled',
    'streaming_unavailable',
    'media_denied',
    'network_timeout',
    'share_expired',
    'busy',
  ]) {
    if (text.contains(code)) return BrowserMediaExportException(code);
  }
  return const BrowserMediaExportException('stream_failed');
}

void cancelBrowserMediaExport(String id) {
  try {
    _cancel(id.toJS);
  } catch (_) {
    /* No bridge before bootstrap. */
  }
}
