import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final trainingModalOwnershipProvider = Provider(
  (_) => TrainingModalOwnership(),
);

/// Captures only popup routes pushed synchronously by an explicit tour action.
/// User-opened windows and routes opened later by unrelated async work stay out.
class TrainingModalOwnership extends NavigatorObserver {
  bool _capturing = false;
  final List<Route<dynamic>> _owned = [];
  Future<bool>? _closing;

  bool get hasOwnedActive => _owned.any((route) => route.isActive);

  void runOwned(VoidCallback action) {
    final wasCapturing = _capturing;
    _capturing = true;
    try {
      action();
    } finally {
      _capturing = wasCapturing;
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_capturing && route is PopupRoute) _owned.add(route);
  }

  Future<bool> closeOwned() =>
      _closing ??= _close().whenComplete(() => _closing = null);

  Future<bool> _close() async {
    _owned.removeWhere((route) => !route.isActive);
    while (_owned.isNotEmpty) {
      final route = _owned.last;
      // Never close through another window or bypass a protected form.
      if (!route.isCurrent ||
          route is! PopupRoute ||
          !route.barrierDismissible) {
        return false;
      }
      final nav = route.navigator;
      if (nav == null) {
        _owned.removeLast();
        continue;
      }
      await nav.maybePop();
      if (route.isActive) return false;
      _owned.remove(route);
    }
    return true;
  }
}
