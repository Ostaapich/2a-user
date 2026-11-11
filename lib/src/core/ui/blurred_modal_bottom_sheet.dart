import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_layout.dart';
import 'app_keyboard_dismiss.dart';

const _mobileSheetBorderRadius = BorderRadius.vertical(
  top: Radius.circular(30),
);

/// Project-wide modal bottom sheet with a dimmed + softly blurred backdrop.
///
/// It intentionally mirrors the common subset of [showModalBottomSheet]
/// arguments used in this app, so existing sheets can switch to it without
/// rewriting their inner content. The sheet content still owns its internal
/// layout and fixed handle. The route owns keyboard avoidance once and removes
/// the consumed bottom inset from its builder. Bottom system navigation insets are
/// protected by default so actions stay reachable on Android devices with
/// gesture or three-button navigation.
Future<T?> showBlurredModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  Color? barrierColor,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
  bool useSafeArea = true,
  bool isDismissible = true,
  bool enableDrag = true,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  RouteSettings? routeSettings,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final capturedThemes = InheritedTheme.capture(
    from: context,
    to: navigator.context,
  );
  ProviderContainer? callerContainer;
  try {
    callerContainer = ProviderScope.containerOf(context, listen: false);
  } on StateError {
    // Standalone UI callers may have no Riverpod scope.
  }
  final capturedContainer = callerContainer;

  // Do not let a modal pop restore an old editor/keyboard on the parent page.
  AppKeyboardDismissRegion.dismiss();
  return navigator.push<T>(
    _BlurredModalBottomSheetRoute<T>(
      // Root-navigator sheets must retain the caller's account/data scope.
      // Its existing owner remains responsible for the container's lifetime.
      builder: capturedContainer == null
          ? builder
          : (_) => UncontrolledProviderScope(
              container: capturedContainer,
              child: Builder(builder: builder),
            ),
      capturedThemes: capturedThemes,
      backgroundColor: backgroundColor,
      modalBarrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.24),
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      shape: shape,
      clipBehavior: clipBehavior,
      constraints: constraints,
      settings: routeSettings,
      modalBarrierLabel: MaterialLocalizations.of(
        context,
      ).modalBarrierDismissLabel,
    ),
  );
}

class _BlurredModalBottomSheetRoute<T> extends PopupRoute<T> {
  final WidgetBuilder builder;
  final CapturedThemes capturedThemes;
  final Color? backgroundColor;
  final Color modalBarrierColor;
  final bool isScrollControlled;
  final bool useSafeArea;
  final bool isDismissible;
  final bool enableDrag;
  final ShapeBorder? shape;
  final Clip? clipBehavior;
  final BoxConstraints? constraints;
  final String modalBarrierLabel;

  _BlurredModalBottomSheetRoute({
    required this.builder,
    required this.capturedThemes,
    required this.modalBarrierColor,
    required this.isScrollControlled,
    required this.useSafeArea,
    required this.isDismissible,
    required this.enableDrag,
    required this.modalBarrierLabel,
    this.backgroundColor,
    this.shape,
    this.clipBehavior,
    this.constraints,
    super.settings,
  });

  @override
  bool get barrierDismissible => isDismissible;

  @override
  Color? get barrierColor => modalBarrierColor;

  @override
  String? get barrierLabel => modalBarrierLabel;

  @override
  bool didPop(T? result) {
    final scope = subtreeContext == null
        ? null
        : FocusScope.of(subtreeContext!);
    final popped = super.didPop(result);
    if (popped) {
      AppKeyboardDismissRegion.dismiss(scope: scope);
    }
    return popped;
  }

  @override
  Duration get transitionDuration => const Duration(milliseconds: 260);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 210);

  @override
  bool get maintainState => true;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return capturedThemes.wrap(
      _BlurredModalBottomSheetPage<T>(
        animation: animation,
        builder: builder,
        backgroundColor: backgroundColor,
        isScrollControlled: isScrollControlled,
        useSafeArea: useSafeArea,
        enableDrag: enableDrag,
        shape: shape,
        clipBehavior: clipBehavior,
        constraints: constraints,
      ),
    );
  }
}

class _BlurredModalBottomSheetPage<T> extends StatefulWidget {
  final Animation<double> animation;
  final WidgetBuilder builder;
  final Color? backgroundColor;
  final bool isScrollControlled;
  final bool useSafeArea;
  final bool enableDrag;
  final ShapeBorder? shape;
  final Clip? clipBehavior;
  final BoxConstraints? constraints;

  const _BlurredModalBottomSheetPage({
    required this.animation,
    required this.builder,
    required this.backgroundColor,
    required this.isScrollControlled,
    required this.useSafeArea,
    required this.enableDrag,
    required this.shape,
    required this.clipBehavior,
    required this.constraints,
  });

  @override
  State<_BlurredModalBottomSheetPage<T>> createState() =>
      _BlurredModalBottomSheetPageState<T>();
}

class _BlurredModalBottomSheetPageState<T>
    extends State<_BlurredModalBottomSheetPage<T>>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0;
  double _closeDistance = 96;
  late final AnimationController _settleController;
  Offset? _pointerDownPosition;
  Offset? _lastSamplePosition;
  Offset? _previousSamplePosition;
  Duration? _lastSampleTime;
  Duration? _previousSampleTime;
  int _sampleCount = 0;
  int _handoffGeneration = 0;
  bool _handoffStartPending = false;

  @override
  void initState() {
    super.initState();
    _settleController = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        setState(
          () => _dragOffset = _settleController.value.clamp(0.0, 1000.0),
        );
      });
  }

  void _settleBack({double velocity = 0, SpringDescription? spring}) {
    if (!mounted || _dragOffset == 0) return;
    _settleController.stop();
    _settleController.value = _dragOffset;
    unawaited(
      _settleController.animateWith(
        ScrollSpringSimulation(
          spring ??
              const SpringDescription(mass: 0.5, stiffness: 100, damping: 15),
          _dragOffset,
          0,
          velocity,
          tolerance: const Tolerance(distance: 0.1, velocity: 1),
        ),
      ),
    );
  }

  void _setCloseDistance(Offset pointer, {double initialDistance = 0}) {
    final media = MediaQuery.of(context);
    final usableBottom =
        media.size.height -
        media.viewInsets.bottom.clamp(0.0, media.size.height) -
        media.padding.bottom;
    final availableTravel = (usableBottom - pointer.dy + initialDistance).clamp(
      0.0,
      media.size.height,
    );
    _closeDistance = (availableTravel * 0.35).clamp(24.0, 96.0);
  }

  void _recordPointerSample(PointerEvent event) {
    _previousSamplePosition = _lastSamplePosition;
    _previousSampleTime = _lastSampleTime;
    _lastSamplePosition = event.position;
    _lastSampleTime = event.timeStamp;
    _sampleCount++;
    _pointerVelocity?.addPosition(event.timeStamp, event.position);
  }

  double _releaseVelocity(PointerUpEvent event) {
    final lastTime = _lastSampleTime;
    // The platform tracker uses the same 40ms stopped-motion rule. Explicit
    // event timestamps also distinguish a held release in deterministic tests.
    if (lastTime == null ||
        event.timeStamp - lastTime > const Duration(milliseconds: 40)) {
      return 0;
    }
    var velocity = _pointerVelocity?.getVelocity().pixelsPerSecond.dy ?? 0;
    if (_sampleCount == 2 && _previousSampleTime != null) {
      final elapsed = (lastTime - _previousSampleTime!).inMicroseconds;
      final distance = _lastSamplePosition!.dy - _previousSamplePosition!.dy;
      // A one-move native flick has only DOWN+MOVE, insufficient for the
      // quadratic tracker. Use its actual displacement/time, never an UP
      // sample that would fabricate an abrupt stop.
      if (elapsed > 0 && elapsed <= 40000 && distance.abs() > kTouchSlop) {
        velocity = distance * Duration.microsecondsPerSecond / elapsed;
      }
    }
    return velocity.clamp(-8000.0, 8000.0);
  }

  final Set<int> _touchPointers = {};
  bool _directDragCancelled = false;
  int? _activePointer;
  VelocityTracker? _pointerVelocity;
  ScrollableState? _handoffScrollable;
  ScrollPosition? _handoffPosition;
  Offset? _handoffPointerPosition;

  bool get _hasLiveHandoff =>
      mounted &&
      ModalRoute.of(context)?.isCurrent == true &&
      _handoffScrollable?.mounted == true &&
      identical(_handoffScrollable!.position, _handoffPosition);

  void _resetPointerTracking({bool restoreSheet = false}) {
    final wasHandedOff = _handoffPosition != null;
    _handoffGeneration++;
    _handoffStartPending = false;
    _activePointer = null;
    _pointerVelocity = null;
    _pointerDownPosition = null;
    _lastSamplePosition = null;
    _previousSamplePosition = null;
    _lastSampleTime = null;
    _previousSampleTime = null;
    _sampleCount = 0;
    _handoffScrollable = null;
    _handoffPosition = null;
    _handoffPointerPosition = null;
    if (restoreSheet && wasHandedOff && mounted && _dragOffset != 0) {
      _settleBack();
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    // A fresh sequence also includes mouse/stylus or a resized side sheet.
    // Clear before their early return, while retaining the block through UP.
    if (_touchPointers.isEmpty) {
      _directDragCancelled = false;
      _settleController.stop();
    }
    if (event.kind != PointerDeviceKind.touch ||
        !widget.enableDrag ||
        AppLayout.useSideNavigation(context)) {
      return;
    }
    // Keep cancellation through the final UP: the recognizer dispatches its
    // end after raw pointer listeners. Only a fresh sequence may drag again.
    _touchPointers.add(event.pointer);
    if (_touchPointers.length != 1) {
      _directDragCancelled = true;
      // A second finger never turns a scroll/selection gesture into dismissal.
      _resetPointerTracking(restoreSheet: true);
      _onDragCancel();
      return;
    }
    _activePointer = event.pointer;
    _pointerDownPosition = event.position;
    _setCloseDistance(event.position);
    _pointerVelocity = ScrollConfiguration.of(
      context,
    ).velocityTrackerBuilder(context)(event);
    _recordPointerSample(event);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    _recordPointerSample(event);
    if (_handoffPosition == null) return;
    if (!_hasLiveHandoff) {
      _resetPointerTracking(restoreSheet: true);
      return;
    }
    if (_handoffStartPending) {
      _handoffStartPending = false;
      _handoffPosition!.jumpTo(_handoffPosition!.minScrollExtent);
    }
    final previous = _handoffPointerPosition!;
    _handoffPointerPosition = event.position;
    final delta = event.position.dy - previous.dy;
    if (delta == 0) return;
    final position = _handoffPosition!;
    var nextOffset = _dragOffset + delta;
    if (_dragOffset == 0 && position.pixels > position.minScrollExtent) {
      // Reversing a handed-off gesture can resume list scrolling without
      // forcing the user to lift their finger first.
      final nextPixels = position.pixels - delta;
      position.jumpTo(
        nextPixels.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
      nextOffset = (position.minScrollExtent - nextPixels).clamp(0.0, 1000.0);
    } else if (nextOffset < 0) {
      position.jumpTo(
        (position.pixels - nextOffset).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
      nextOffset = 0;
    }
    setState(() => _dragOffset = nextOffset.clamp(0.0, 1000.0));
  }

  void _onPointerUp(PointerUpEvent event) {
    _touchPointers.remove(event.pointer);
    if (event.pointer != _activePointer) return;
    final handedOff = _hasLiveHandoff;
    final position = _handoffPosition;
    if (handedOff && _handoffStartPending) {
      _handoffStartPending = false;
      position!.jumpTo(position.minScrollExtent);
    }
    final velocity = _releaseVelocity(event);
    _resetPointerTracking(restoreSheet: !handedOff);
    if (handedOff && _dragOffset > 0) {
      _onDragEnd(
        DragEndDetails(
          primaryVelocity: velocity,
          velocity: Velocity(pixelsPerSecond: Offset(0, velocity)),
        ),
      );
    } else if (handedOff && position is ScrollPositionWithSingleContext) {
      position.goBallistic(-velocity);
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _directDragCancelled = true;
    _touchPointers.remove(event.pointer);
    if (event.pointer == _activePointer) {
      _resetPointerTracking(restoreSheet: true);
    }
    // A recognized DragGestureRecognizer may report an OS cancel as a zero
    // velocity end. Clear direct/header offset before that can request a pop.
    _onDragCancel();
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (!widget.enableDrag ||
        ModalRoute.of(context)?.isCurrent != true ||
        _activePointer == null ||
        _touchPointers.length != 1 ||
        _handoffPosition != null ||
        notification.depth != 0 ||
        notification.metrics.axisDirection != AxisDirection.down ||
        AppLayout.useSideNavigation(context)) {
      return false;
    }
    final origin = notification.context;
    if (origin == null || !origin.mounted) return false;
    var excluded = false;
    origin.visitAncestorElements((element) {
      if (element.widget is EditableText ||
          element.widget is DraggableScrollableSheet) {
        excluded = true;
        return false;
      }
      return element.widget is! _BlurredModalBottomSheetPage;
    });
    if (excluded) return false;
    Offset? dragPosition;
    double distance = 0;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null &&
        notification.metrics.pixels <= notification.metrics.minScrollExtent &&
        _pointerDownPosition != null) {
      final start = notification.dragDetails!.globalPosition;
      final delta = start - _pointerDownPosition!;
      if (delta.dy > 0 && delta.dy.abs() > delta.dx.abs()) {
        dragPosition = start;
        distance = delta.dy;
      }
    }
    if (notification is OverscrollNotification && notification.overscroll < 0) {
      if (notification.dragDetails?.delta.dy != null &&
          notification.dragDetails!.delta.dy > 0) {
        dragPosition = notification.dragDetails!.globalPosition;
      }
      distance = -notification.overscroll;
    } else if (notification is ScrollUpdateNotification &&
        notification.metrics.pixels < notification.metrics.minScrollExtent) {
      if (notification.dragDetails?.delta.dy != null &&
          notification.dragDetails!.delta.dy > 0) {
        dragPosition = notification.dragDetails!.globalPosition;
      }
      distance =
          notification.metrics.minScrollExtent - notification.metrics.pixels;
    }
    // Ignore wheel, programmatic scrolling, and ballistic/bounce notifications.
    if (dragPosition == null || distance <= 0) return false;
    final scrollable = Scrollable.maybeOf(origin);
    if (scrollable == null || !scrollable.mounted) return false;
    final position = scrollable.position;
    // Claim before jumpTo: it cancels the child's drag activity and may dispatch
    // synchronous notifications. Reset iOS overscroll before the next paint so
    // only the complete modal consumes the remaining pointer movement.
    _handoffScrollable = scrollable;
    _handoffPosition = position;
    _handoffPointerPosition = dragPosition;
    _setCloseDistance(dragPosition, initialDistance: distance);
    if (notification is ScrollStartNotification) {
      // Scrollable assigns its Drag controller AFTER dispatching ScrollStart.
      // Cancel after that assignment; synchronous cancellation would leave a
      // disposed controller assigned back to Scrollable. Invalidate queued work
      // on release/cancel, so it can never stop resumed ballistic scrolling.
      _handoffStartPending = true;
      final generation = _handoffGeneration;
      scheduleMicrotask(() {
        if (!mounted ||
            generation != _handoffGeneration ||
            !_handoffStartPending ||
            !_hasLiveHandoff ||
            _activePointer == null) {
          return;
        }
        _handoffStartPending = false;
        position.jumpTo(position.minScrollExtent);
      });
    } else {
      position.jumpTo(position.minScrollExtent);
    }
    if (mounted) setState(() => _dragOffset = distance.clamp(0.0, 1000.0));
    return false;
  }

  @override
  void dispose() {
    _touchPointers.clear();
    _resetPointerTracking();
    _settleController.dispose();
    super.dispose();
  }

  void _onDragCancel() {
    // Losing the arena to a child Scrollable is also a direct-drag cancel.
    // Keep raw pointer tracking so that child can hand off at its leading edge.
    if (_directDragCancelled) {
      _settleController.stop();
      if (mounted && _dragOffset != 0) setState(() => _dragOffset = 0);
      return;
    }
    _settleBack();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!widget.enableDrag || _directDragCancelled) return;
    _settleController.stop();
    if (AppLayout.useSideNavigation(context)) {
      final dx = details.primaryDelta ?? 0;
      if (dx <= 0 && _dragOffset <= 0) return;
      setState(() => _dragOffset = (_dragOffset + dx).clamp(0.0, 1000.0));
      return;
    }

    final dy = details.primaryDelta ?? 0;
    if (dy <= 0 && _dragOffset <= 0) return;
    setState(() => _dragOffset = (_dragOffset + dy).clamp(0.0, 1000.0));
  }

  void _requestDismissAfterDrag() {
    final route = ModalRoute.of(context);
    // A route pushed during this gesture owns the navigator now. Never let
    // a stale pointer-up dismiss that dialog/page on behalf of this sheet.
    if (route?.isCurrent != true) {
      _settleBack();
      return;
    }
    unawaited(
      Navigator.of(context).maybePop().then((_) {
        // A successful pop continues from the dragged position. A guard may
        // handle maybePop without removing the sheet; restore only that sheet.
        if (mounted && route?.isActive == true && _dragOffset != 0) {
          _settleBack();
        }
      }),
    );
  }

  void _onDragEnd(DragEndDetails details) {
    if (!widget.enableDrag || _directDragCancelled) return;
    final velocity = details.primaryVelocity ?? 0;
    if (AppLayout.useSideNavigation(context)) {
      final shouldClose = velocity > 650 || _dragOffset > 96;
      if (shouldClose) {
        _requestDismissAfterDrag();
        return;
      }
      _settleBack(velocity: velocity);
      return;
    }

    final shouldClose = velocity > 650 || _dragOffset >= _closeDistance;
    if (shouldClose) {
      _requestDismissAfterDrag();
      return;
    }
    _settleBack(velocity: velocity);
  }

  @override
  Widget build(BuildContext context) {
    final mediaSize = MediaQuery.sizeOf(context);
    final useSideSheet = AppLayout.useSideNavigation(context);
    final modalMaxWidth = useSideSheet
        ? mediaSize.width * 0.6
        : AppLayout.modalMaxWidth(context);
    final maxWidth = modalMaxWidth.clamp(0.0, mediaSize.width).toDouble();
    // Tall mobile sheets keep breathing room below the status bar. The bottom
    // SafeArea is added outside routeConstraints, so reserve its space here.
    final safeInsets = MediaQuery.viewPaddingOf(context);
    final media = MediaQuery.of(context);
    // Native keyboard dismissal may briefly overshoot zero (spring metrics).
    // Negative padding is invalid and must never reach the sheet surface.
    final keyboardInset = media.viewInsets.bottom
        .clamp(0.0, mediaSize.height)
        .toDouble();
    final bottomInset = widget.useSafeArea && keyboardInset == 0
        ? safeInsets.bottom
        : 0.0;
    final availableHeight = mediaSize.height - keyboardInset;
    // Short phones/landscape need the usable space for input. Keep the status
    // bar and a reachable handle, without reserving a large decorative gap.
    final topSpace = keyboardInset > 0 && availableHeight < 480
        ? safeInsets.top + 8
        : (mediaSize.height * 0.08).clamp(safeInsets.top, mediaSize.height) +
              24;
    final mobileMaxHeight = (availableHeight - topSpace - bottomInset).clamp(
      0.0,
      mediaSize.height,
    );
    final maxHeight = useSideSheet
        ? (mediaSize.height - keyboardInset).clamp(0.0, mediaSize.height)
        : widget.isScrollControlled
        ? mobileMaxHeight
        : (mediaSize.height * 9 / 16).clamp(0.0, mobileMaxHeight);
    final routeConstraints = widget.constraints == null
        ? BoxConstraints(maxHeight: maxHeight)
        : widget.constraints!.enforce(BoxConstraints(maxHeight: maxHeight));

    final consumesBottomSafeArea = !useSideSheet && widget.useSafeArea;
    final contentMedia = media.copyWith(
      viewInsets: media.viewInsets.copyWith(bottom: 0),
      padding: media.padding.copyWith(
        bottom: keyboardInset > 0 || consumesBottomSafeArea
            ? 0
            : media.padding.bottom,
      ),
      viewPadding: media.viewPadding.copyWith(
        bottom: keyboardInset > 0 || consumesBottomSafeArea
            ? 0
            : media.viewPadding.bottom,
      ),
    );
    Widget sheet = MediaQuery(
      data: contentMedia,
      child: Builder(builder: widget.builder),
    );

    if (widget.backgroundColor != Colors.transparent || widget.shape != null) {
      sheet = Material(
        color: widget.backgroundColor ?? Colors.white,
        shape: widget.shape,
        clipBehavior: widget.clipBehavior ?? Clip.none,
        child: sheet,
      );
    } else {
      sheet = Material(type: MaterialType.transparency, child: sheet);
    }

    sheet = ConstrainedBox(
      constraints: routeConstraints,
      child: SizedBox(
        width: maxWidth,
        height: useSideSheet ? maxHeight : null,
        child: sheet,
      ),
    );

    if (useSideSheet) {
      sheet = ClipRRect(
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(30)),
        child: ColoredBox(color: Colors.white, child: sheet),
      );
    } else {
      // Paint the inset together with the modal surface. Wrapping only with
      // SafeArea leaves a transparent strip above Android system navigation
      // when callers use a transparent route background.
      if (widget.useSafeArea) {
        sheet = ColoredBox(
          color: Colors.white,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: sheet,
          ),
        );
      }

      // Clip the complete surface so every mobile sheet has the same rounded
      // top corners, including legacy sheets whose inner content is
      // rectangular.
      sheet = ClipRRect(borderRadius: _mobileSheetBorderRadius, child: sheet);
    }

    sheet = GestureDetector(
      behavior: HitTestBehavior.translucent,
      // Background taps are a fallback for platform selection-menu/input
      // connections. Child editors and buttons keep their own tap recognizers.
      onTap: () =>
          AppKeyboardDismissRegion.dismiss(scope: FocusScope.of(context)),
      onVerticalDragUpdate: widget.enableDrag && !useSideSheet
          ? _onDragUpdate
          : null,
      onVerticalDragEnd: widget.enableDrag && !useSideSheet ? _onDragEnd : null,
      onVerticalDragCancel: widget.enableDrag && !useSideSheet
          ? _onDragCancel
          : null,
      onHorizontalDragUpdate: widget.enableDrag && useSideSheet
          ? _onDragUpdate
          : null,
      onHorizontalDragEnd: widget.enableDrag && useSideSheet
          ? _onDragEnd
          : null,
      onHorizontalDragCancel: widget.enableDrag && useSideSheet
          ? _onDragCancel
          : null,
      child: sheet,
    );

    sheet = Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: sheet,
      ),
    );

    return AnimatedBuilder(
      animation: widget.animation,
      builder: (context, child) {
        final eased = Curves.easeOutCubic.transform(widget.animation.value);
        final blurSigma = 4.0 * eased;

        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            // Keep the modal's painted surface behind the occluded IME area.
            // iOS rounded/floating keyboards expose its corners. This layer
            // never extends above keyboardTop and creates no content spacer.
            if (keyboardInset > 0)
              Positioned(
                bottom: 0,
                right: useSideSheet ? 0 : (mediaSize.width - maxWidth) / 2,
                width: maxWidth,
                height: keyboardInset,
                child: IgnorePointer(
                  child: ColoredBox(
                    color:
                        widget.backgroundColor == null ||
                            widget.backgroundColor == Colors.transparent
                        ? Colors.white
                        : widget.backgroundColor!,
                  ),
                ),
              ),
            if (useSideSheet)
              Align(
                alignment: Alignment.centerRight,
                child: FractionalTranslation(
                  translation: Offset(1 - eased, 0),
                  child: Transform.translate(
                    offset: Offset(_dragOffset, 0),
                    child: child,
                  ),
                ),
              )
            else
              Align(
                alignment: Alignment.bottomCenter,
                child: FractionalTranslation(
                  translation: Offset(0, 1 - eased),
                  child: Transform.translate(
                    offset: Offset(0, _dragOffset),
                    child: child,
                  ),
                ),
              ),
          ],
        );
      },
      child: Padding(
        // Outside the painted surface: no opaque filler above the IME and no
        // duplicated inset in legacy inner forms. Follow native IME metrics.
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: sheet,
      ),
    );
  }
}
