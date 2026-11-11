import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dio/dio.dart';

@JS('AbortController')
extension type _AbortController._(JSObject _) implements JSObject {
  external factory _AbortController();
  external JSObject get signal;
  external void abort();
}

extension type _FetchHeaders._(JSObject _) implements JSObject {
  external void forEach(JSFunction callback);
}

extension type _FetchResponse._(JSObject _) implements JSObject {
  external int get status;
  external String get statusText;
  external _FetchHeaders get headers;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

@JS('fetch')
external JSPromise<_FetchResponse> _fetch(String url, JSObject options);

HttpClientAdapter wrapMediaHttpAdapter(HttpClientAdapter adapter) =>
    StrictMediaBrowserAdapter(adapter);

/// Dio's XHR adapter follows redirects even when followRedirects is false.
/// Protected media and the exact bounded workflow POST use Fetch's mandatory
/// redirect:error policy. Other API requests keep their existing adapter.
class StrictMediaBrowserAdapter implements HttpClientAdapter {
  StrictMediaBrowserAdapter(this.delegate);
  final HttpClientAdapter delegate;
  final _active = <_AbortController>{};
  bool _closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final workflow = options.extra['workflow_no_redirect'] == true;
    if (options.extra['private_media_no_redirect'] != true && !workflow) {
      return delegate.fetch(options, requestStream, cancelFuture);
    }
    final allowedWorkflow =
        workflow &&
        options.method == 'POST' &&
        const {
          '/api/client/workflow-events',
          '/client/workflow-events',
          '/api/public/workflow-events',
          '/public/workflow-events',
        }.contains(options.uri.path) &&
        !options.uri.hasQuery &&
        !options.uri.hasFragment;
    if (_closed ||
        (workflow
            ? !allowedWorkflow
            : options.method != 'GET' || requestStream != null)) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
        message: 'Media request unavailable',
      );
    }
    final controller = _AbortController();
    _active.add(controller);
    var complete = false;
    Timer? timer;
    final timeout = options.receiveTimeout ?? options.connectTimeout;
    if (timeout != null && timeout > Duration.zero) {
      timer = Timer(timeout, () => controller.abort());
    }
    unawaited(
      cancelFuture?.then((_) {
        if (!complete) controller.abort();
      }),
    );
    try {
      final headers = <String, String>{
        for (final entry in options.headers.entries)
          entry.key: entry.value.toString(),
      };
      String? body;
      if (workflow) {
        final bytes = <int>[];
        if (requestStream != null) {
          await for (final chunk in requestStream) {
            if (bytes.length + chunk.length > 16384) {
              throw const FormatException('Workflow request too large');
            }
            bytes.addAll(chunk);
          }
        }
        body = utf8.decode(bytes);
      }
      final init =
          <String, Object>{
                'method': workflow ? 'POST' : 'GET',
                if (body != null) 'body': body,
                'headers': headers,
                'redirect': 'error',
                'credentials': 'omit',
                'mode': 'cors',
                'cache': 'no-store',
                'signal': controller.signal,
              }.jsify()
              as JSObject;
      final response = await _fetch(options.uri.toString(), init).toDart;
      final responseHeaders = <String, List<String>>{};
      response.headers.forEach(
        ((JSString value, JSString name) {
          responseHeaders[name.toDart.toLowerCase()] = [value.toDart];
        }).toJS,
      );
      final buffer = await response.arrayBuffer().toDart;
      return ResponseBody.fromBytes(
        buffer.toDart.asUint8List(),
        response.status,
        headers: responseHeaders,
        statusMessage: response.statusText,
      );
    } catch (_) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'Media request blocked or unavailable',
      );
    } finally {
      complete = true;
      timer?.cancel();
      _active.remove(controller);
    }
  }

  @override
  void close({bool force = false}) {
    _closed = true;
    for (final controller in _active) {
      controller.abort();
    }
    delegate.close(force: force);
  }
}
