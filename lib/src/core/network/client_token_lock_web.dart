import 'dart:js_interop';

@JS('navigator.locks')
external _BrowserLocks? get _browserLocks;
extension type _BrowserLocks._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> request(String name, JSFunction callback);
}

/// Same lock surrounds login/logout writes and renewal CAS in every current tab.
Future<bool> withClientTokenLock(
  Future<void> Function() action, {
  bool requireLock = false,
}) async {
  var started = false;
  Object? failure;
  StackTrace? trace;
  try {
    await _browserLocks!
        .request(
          '2a-user-auth-token',
          ((JSAny? _) {
            started = true;
            return () async {
              try {
                await action();
              } catch (error, stack) {
                failure = error;
                trace = stack;
              }
              return null as JSAny?;
            }().toJS;
          }).toJS,
        )
        .toDart;
  } catch (_) {
    if (started) rethrow;
    if (requireLock) {
      return false;
    } // Fail closed for renewal on browsers without Web Locks.
    await action();
    return true;
  }
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
  return true;
}
