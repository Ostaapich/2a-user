import 'dart:js_interop';
// This standalone dart compile js fixture deliberately has no Flutter bootstrap
// or package resolver; it exercises the same conditional web bridge directly.
// ignore: avoid_relative_lib_imports
import '../../lib/src/core/media/browser_media_export.dart';

@JS('dartExport')
external set _export(JSFunction function);
@JS('testIdentity')
external JSString get _identity;
@JS('dartReceived')
external set _received(JSNumber count);

void main() {
  _export = ((JSString url, JSString base, JSString name, JSString id) {
    return beginBrowserMediaExport(
          BrowserMediaExportRequest(
            operationId: id.toDart,
            url: url.toDart,
            apiBase: base.toDart,
            name: name.toDart,
            token: 'fixture-a',
            identity: 'account-A',
            getIdentity: () async => _identity.toDart,
            onProgress: (received, _) => _received = received.toJS,
          ),
        )
        .then<JSAny?>((result) => {'kind': result.kind.name}.jsify())
        .catchError(
          (Object error) => {
            'error': error is BrowserMediaExportException
                ? error.code
                : 'unknown',
          }.jsify(),
        )
        .toJS;
  }).toJS;
}
