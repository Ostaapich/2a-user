import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// A touch outside an editor dismisses the mobile keyboard as well as desktop
/// focus. TextFieldTapRegion keeps editor-owned controls inside the same group.
/// The visibility flag survives Scaffold consuming the physical keyboard inset.
class AppKeyboardDismissRegion extends StatelessWidget {
  const AppKeyboardDismissRegion({super.key, required this.child});

  final Widget child;

  /// End both framework focus and the platform input connection synchronously
  /// with the user's dismissal. Do not defer this until a route future completes.
  static void dismiss({FocusScopeNode? scope}) {
    if (scope != null) {
      scope.unfocus();
    } else {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
  }

  static bool isKeyboardVisibleOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_KeyboardVisibility>()
          ?.visible ??
      (MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0) > 0;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final bottom = (media?.viewInsets.bottom ?? 0)
        .clamp(0.0, media?.size.height ?? double.infinity)
        .toDouble();
    Widget content = Actions(
      actions: <Type, Action<Intent>>{
        EditableTextTapOutsideIntent:
            CallbackAction<EditableTextTapOutsideIntent>(
              onInvoke: (intent) {
                intent.focusNode.unfocus();
                dismiss();
                return null;
              },
            ),
      },
      child: child,
    );
    // iOS IME spring transitions can report a tiny negative bottom inset.
    // Normalize at the app boundary for manual-inset screens as well.
    if (media != null) {
      content = MediaQuery(
        data: media.copyWith(
          viewInsets: media.viewInsets.copyWith(bottom: bottom),
        ),
        child: content,
      );
    }
    // Transparent scaffolds resize above the IME. The Flutter viewport itself
    // still needs an opaque backing where rounded system keyboards reveal it.
    return ColoredBox(
      color: AppColors.brandBg,
      child: _KeyboardVisibility(visible: bottom > 0, child: content),
    );
  }
}

class _KeyboardVisibility extends InheritedWidget {
  const _KeyboardVisibility({required this.visible, required super.child});
  final bool visible;

  @override
  bool updateShouldNotify(_KeyboardVisibility oldWidget) =>
      visible != oldWidget.visible;
}
