import 'package:flutter/material.dart';

import '../../../core/ui/app_layout.dart';
import '../../../core/ui/blurred_modal_bottom_sheet.dart';
import '../../../core/ui/sheet_handle.dart';

Future<T?> showGarageModalSheet<T>({
  required BuildContext context,
  required Widget child,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  final media = MediaQuery.sizeOf(context);
  final useSideSheet = AppLayout.useSideNavigation(context);
  return showBlurredModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.22),
    constraints: BoxConstraints(
      maxHeight: useSideSheet ? media.height : media.height * 0.9,
    ),
    builder: (sheetContext) => ColoredBox(
      color: Colors.white,
      child: Column(
        children: [
          if (!useSideSheet) const SheetHandle(),
          Expanded(child: GarageModalScope(child: child)),
        ],
      ),
    ),
  );
}

class GarageModalScope extends InheritedWidget {
  const GarageModalScope({super.key, required super.child});

  static bool active(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<GarageModalScope>() !=
        null;
  }

  @override
  bool updateShouldNotify(GarageModalScope oldWidget) => false;
}
