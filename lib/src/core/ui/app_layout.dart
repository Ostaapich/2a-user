import 'package:flutter/widgets.dart';

import 'app_keyboard_dismiss.dart';

class AppLayout {
  const AppLayout._();

  static const mobileBreakpoint = 600.0;
  static const tabletBreakpoint = 840.0;
  static const desktopBreakpoint = 1024.0;
  static const wideDesktopBreakpoint = 1440.0;

  static const topBarHeight = 44.0;
  static const topBarTopMargin = 10.0;
  static const topBarBottomGap = 12.0;

  static const bottomBarHeight = 60.0;
  static const bottomBarBottomMargin = 10.0;
  static const bottomBarExtraScrollPadding = 32.0;

  static const sideNavCollapsedWidth = 104.0;
  static const sideNavExpandedWidth = 248.0;
  static const sideNavHorizontalMargin = 16.0;

  static double sideNavWidthFor(bool expanded) {
    return expanded ? sideNavExpandedWidth : sideNavCollapsedWidth;
  }

  static bool isCompactPhone(BuildContext context) {
    return MediaQuery.sizeOf(context).width <= 390;
  }

  /// Общий коэффициент компактности для маленьких телефонов.
  ///
  /// Не применяется на планшетах/desktop: там адаптив строится сетками и
  /// сайдбаром. На старых Android с шириной 360dp это помогает страницам,
  /// модалкам и меню не выглядеть слишком крупно.
  static double compactScale(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width <= 360) return 0.88;
    if (width <= 390) return 0.92;
    return 1.0;
  }

  /// Отдельный коэффициент для текста. Он мягче, чем геометрия, чтобы
  /// интерфейс оставался читаемым, но длинные номера/лейблы помещались.
  static double compactTextScale(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width <= 360) return 0.92;
    if (width <= 390) return 0.95;
    return 1.0;
  }

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= mobileBreakpoint && width < desktopBreakpoint;
  }

  static bool isDesktop(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= desktopBreakpoint;
  }

  static bool useSideNavigation(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final height = media.size.height;

    // iPad portrait remains touch/mobile-first, while iPad landscape, macOS
    // and desktop web get a real side navigation and free vertical space.
    return width >= desktopBreakpoint ||
        (width >= tabletBreakpoint && width > height);
  }

  static double horizontalMargin(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= wideDesktopBreakpoint) return 32;
    if (width >= desktopBreakpoint) return 28;
    if (width >= mobileBreakpoint) return 24;
    return 16;
  }

  static double contentMaxWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= wideDesktopBreakpoint) return 1180;
    if (width >= desktopBreakpoint) return 1040;
    if (width >= mobileBreakpoint) return 760;
    return double.infinity;
  }

  static double modalMaxWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= desktopBreakpoint) return 720;
    if (width >= mobileBreakpoint) return 680;
    return double.infinity;
  }

  static double navigationContentMaxWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= wideDesktopBreakpoint) return 1240;
    if (width >= desktopBreakpoint) return 1100;
    if (width >= mobileBreakpoint) return 780;
    return double.infinity;
  }

  static EdgeInsets pageHorizontalPadding(BuildContext context) {
    final horizontal = horizontalMargin(context);
    return EdgeInsets.symmetric(horizontal: horizontal);
  }

  static Widget constrainContent(BuildContext context, Widget child) {
    if (useSideNavigation(context)) return child;

    final maxWidth = contentMaxWidth(context);
    if (!maxWidth.isFinite) return child;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }

  static Widget constrainNavigationContent(BuildContext context, Widget child) {
    if (useSideNavigation(context)) return child;

    final maxWidth = navigationContentMaxWidth(context);
    if (!maxWidth.isFinite) return child;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }

  static double topBarHeightFor(BuildContext context) {
    return (topBarHeight * compactScale(context)).clamp(44.0, double.infinity);
  }

  static double topBarTopMarginFor(BuildContext context) {
    return topBarTopMargin * compactScale(context);
  }

  static double topBarBottomGapFor(BuildContext context) {
    return topBarBottomGap * compactScale(context);
  }

  static double bottomBarHeightFor(BuildContext context) {
    return bottomBarHeight * compactScale(context);
  }

  static double bottomBarBottomMarginFor(BuildContext context) {
    return bottomBarBottomMargin * compactScale(context);
  }

  static double topBarTotalHeight(BuildContext context) {
    return MediaQuery.paddingOf(context).top +
        topBarTopMarginFor(context) +
        topBarHeightFor(context) +
        topBarBottomGapFor(context);
  }

  static double bottomBarObstruction(BuildContext context) {
    if (useSideNavigation(context) ||
        AppKeyboardDismissRegion.isKeyboardVisibleOf(context)) {
      return 0;
    }

    return MediaQuery.viewPaddingOf(context).bottom +
        bottomBarHeightFor(context) +
        bottomBarBottomMarginFor(context);
  }

  static double bottomScrollPadding(BuildContext context) {
    return bottomBarObstruction(context) + bottomBarExtraScrollPadding;
  }
}
