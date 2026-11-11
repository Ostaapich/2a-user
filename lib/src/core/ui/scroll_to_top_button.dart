import 'package:flutter/material.dart';

import 'app_keyboard_dismiss.dart';

/// The page owner supplies its painted bottom navigation extent, including the
/// system safe area. Root pages without a bottom bar use their own safe area.
class ScrollToTopViewport extends InheritedWidget {
  const ScrollToTopViewport({
    super.key,
    required this.bottomObstruction,
    required this.safeAreaBottom,
    required super.child,
  });

  final double bottomObstruction;
  final double safeAreaBottom;

  static double bottomInsetOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ScrollToTopViewport>();
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    if (scope == null) return safeBottom;
    // A descendant SafeArea can already have consumed the same system inset.
    final consumed = (scope.safeAreaBottom - safeBottom).clamp(
      0.0,
      scope.safeAreaBottom,
    );
    return (scope.bottomObstruction - consumed).clamp(0.0, double.infinity);
  }

  @override
  bool updateShouldNotify(ScrollToTopViewport oldWidget) =>
      bottomObstruction != oldWidget.bottomObstruction ||
      safeAreaBottom != oldWidget.safeAreaBottom;
}

/// Кнопка «Наверх» — появляется при прокрутке вниз.
/// Использовать внутри Stack:
/// ```dart
/// Stack(children: [
///   ListView(..., controller: _scrollController),
///   ScrollToTopButton(controller: _scrollController),
/// ])
/// ```
class ScrollToTopButton extends StatefulWidget {
  final ScrollController controller;
  final double showAfterOffset;
  final double? bottomOffset;

  const ScrollToTopButton({
    super.key,
    required this.controller,
    this.showAfterOffset = 300,
    this.bottomOffset,
  });

  @override
  State<ScrollToTopButton> createState() => _ScrollToTopButtonState();
}

class _ScrollToTopButtonState extends State<ScrollToTopButton> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(ScrollToTopButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final positions = widget.controller.positions;
    final show =
        positions.length == 1 &&
        positions.first.pixels > widget.showAfterOffset;
    if (show != _visible) {
      setState(() => _visible = show);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        _visible && !AppKeyboardDismissRegion.isKeyboardVisibleOf(context);
    return Positioned(
      left: 16,
      bottom:
          widget.bottomOffset ??
          ScrollToTopViewport.bottomInsetOf(context) + 24,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !visible,
          child: GestureDetector(
            onTap: () {
              widget.controller.animateTo(
                0,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
              );
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.keyboard_arrow_up_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
