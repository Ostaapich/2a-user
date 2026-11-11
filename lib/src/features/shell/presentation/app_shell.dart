import '../../../core/ui/scroll_to_top_button.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_target.dart';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:twoalogisticcabineuser/src/core/ui/blurred_modal_bottom_sheet.dart';

import '../../../app/widgets/app_scaffold.dart';
import '../../../core/logging/client_log_service.dart';
import '../../../core/ui/app_background.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/ui/app_layout.dart';
import '../../../core/utils/locale_text.dart';
import '../application/shell_branch_provider.dart';
import '../../more/presentation/more_sheet.dart';
import 'desktop_side_nav.dart';

/// Notifier to hide/show bottom navigation bar (e.g. when a modal is open)
class BottomNavVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void hide() => state = false;
  void show() => state = true;
}

final bottomNavVisibleProvider =
    NotifierProvider<BottomNavVisibleNotifier, bool>(
      BottomNavVisibleNotifier.new,
    );

const _bottomNavigationHeight = 68.0;

double _compactShellScale(BuildContext context) {
  return AppLayout.compactScale(context);
}

class AppShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  static const _titles = <String>[
    'Дашборд',
    'Фото',
    'Треки',
    'Счета',
    'Поддержка',
    'Ещё',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = navigationShell.currentIndex;
    _syncActiveShellBranch(context, ref, currentIndex);
    final title = _titles[currentIndex.clamp(0, _titles.length - 1)];
    final statusTop = MediaQuery.paddingOf(context).top;
    final theme = Theme.of(context);
    final overlayStyle = theme.brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    final bottomNavVisible = ref.watch(bottomNavVisibleProvider);
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final useSideNavigation = AppLayout.useSideNavigation(context);
    final sideNavExpanded = ref.watch(desktopSideNavExpandedProvider);
    final sideNavWidth = AppLayout.sideNavWidthFor(sideNavExpanded);
    final compactScale = AppLayout.compactScale(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final navigationBottomMargin = AppLayout.bottomBarBottomMarginFor(context);
    final scrollButtonObstruction =
        safeBottom +
        (!useSideNavigation && !keyboardVisible && bottomNavVisible
            ? _bottomNavigationHeight * compactScale + navigationBottomMargin
            : 0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        extendBody: true,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          onHorizontalDragEnd: (details) {
            if (useSideNavigation) return;

            // Проверяем, что shell - активный маршрут (нет внутренних страниц поверх)
            // Используем rootNavigator чтобы проверить есть ли страницы поверх shell
            final rootNavigator = Navigator.of(context, rootNavigator: true);
            if (rootNavigator.canPop()) {
              return; // Есть внутренняя страница - не обрабатываем свайп
            }

            // Дополнительная проверка для shell navigator
            if (Navigator.of(context).canPop()) return;

            final v = details.primaryVelocity ?? 0;
            // Swipe right: previous tab
            if (v > 250) {
              if (currentIndex > 0) {
                HapticFeedback.lightImpact();
                ClientLogService.instance.action(
                  'Навигация свайпом по вкладкам',
                  data: {
                    'fromTab': title,
                    'toTab': _titles[currentIndex - 1],
                    'direction': 'previous',
                  },
                );
                navigationShell.goBranch(
                  currentIndex - 1,
                  initialLocation: false,
                );
              }
            }
            // Swipe left: next tab
            else if (v < -250) {
              // Не позволяем свайпать на последнюю вкладку "Ещё" (она открывается только по тапу)
              if (currentIndex < _titles.length - 2) {
                HapticFeedback.lightImpact();
                ClientLogService.instance.action(
                  'Навигация свайпом по вкладкам',
                  data: {
                    'fromTab': title,
                    'toTab': _titles[currentIndex + 1],
                    'direction': 'next',
                  },
                );
                navigationShell.goBranch(
                  currentIndex + 1,
                  initialLocation: false,
                );
              }
            }
          },
          child: Stack(
            children: [
              const Positioned.fill(child: AppBackground()),
              AnimatedPadding(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.only(
                  left: useSideNavigation ? sideNavWidth : 0,
                  top: statusTop,
                ),
                // Keep raw safe-area data for the floating bar siblings,
                // but remove the status inset already consumed by the body.
                child: Builder(
                  builder: (bodyContext) => MediaQuery.removePadding(
                    // Preserve the keyboard inset already consumed by Scaffold.
                    context: bodyContext,
                    removeTop: true,
                    child: ScrollToTopViewport(
                      bottomObstruction: scrollButtonObstruction,
                      safeAreaBottom: safeBottom,
                      child: AppLayout.constrainNavigationContent(
                        bodyContext,
                        navigationShell,
                      ),
                    ),
                  ),
                ),
              ),
              if (useSideNavigation)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  top: 0,
                  left: 0,
                  bottom: 0,
                  width: sideNavWidth,
                  child: DesktopSideNav(
                    currentShellIndex: currentIndex,
                    onShellTap: (index) {
                      navigationShell.goBranch(
                        index,
                        initialLocation: index == currentIndex,
                      );
                    },
                  ),
                ),
              if (!useSideNavigation)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AppFloatingTopBar(title: title, showBack: false),
                ),
              if (!useSideNavigation && !keyboardVisible)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    offset: bottomNavVisible
                        ? Offset.zero
                        : const Offset(0, 1.5),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          14 * compactScale,
                          0,
                          14 * compactScale,
                          navigationBottomMargin,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: _PixsoBottomNav(
                              currentIndex: currentIndex,
                              onTap: (index) {
                                navigationShell.goBranch(
                                  index,
                                  initialLocation: index == currentIndex,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _syncActiveShellBranch(
    BuildContext context,
    WidgetRef ref,
    int currentIndex,
  ) {
    if (ref.read(activeShellBranchIndexProvider) == currentIndex) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      if (ref.read(activeShellBranchIndexProvider) == currentIndex) return;
      ref.read(activeShellBranchIndexProvider.notifier).setIndex(currentIndex);
    });
  }
}

class _PixsoBottomNav extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _PixsoBottomNav({required this.currentIndex, required this.onTap});

  @override
  State<_PixsoBottomNav> createState() => _PixsoBottomNavState();
}

class _PixsoBottomNavState extends State<_PixsoBottomNav> {
  double _dragStart = 0;

  static const _items = [
    (
      icon: CupertinoIcons.house,
      selectedIcon: CupertinoIcons.house_fill,
      label: 'Главная',
    ),
    (
      icon: CupertinoIcons.photo_on_rectangle,
      selectedIcon: CupertinoIcons.photo_fill_on_rectangle_fill,
      label: 'Фото',
    ),
    (
      icon: CupertinoIcons.cube,
      selectedIcon: CupertinoIcons.cube_fill,
      label: 'Треки',
    ),
    (
      icon: CupertinoIcons.creditcard,
      selectedIcon: CupertinoIcons.creditcard_fill,
      label: 'Счета',
    ),
    (
      icon: CupertinoIcons.chat_bubble_text,
      selectedIcon: CupertinoIcons.chat_bubble_text_fill,
      label: 'Чат',
    ),
    (
      icon: CupertinoIcons.ellipsis,
      selectedIcon: CupertinoIcons.ellipsis,
      label: 'Ещё',
    ),
  ];

  void _handleSwipe(double delta) {
    final nextIndex = widget.currentIndex;

    // Swipe right - go to previous item
    if (delta > 20) {
      if (nextIndex > 0) {
        HapticFeedback.lightImpact();
        ClientLogService.instance.action(
          'Навигация свайпом по нижнему меню',
          data: {
            'fromTab': _items[nextIndex].label,
            'toTab': _items[nextIndex - 1].label,
            'direction': 'previous',
          },
        );
        widget.onTap(nextIndex - 1);
      }
    }
    // Swipe left - go to next item
    else if (delta < -20) {
      // Не позволяем свайпать на последнюю вкладку "Ещё" (она открывается только по тапу)
      if (nextIndex < _items.length - 2) {
        HapticFeedback.lightImpact();
        ClientLogService.instance.action(
          'Навигация свайпом по нижнему меню',
          data: {
            'fromTab': _items[nextIndex].label,
            'toTab': _items[nextIndex + 1].label,
            'direction': 'next',
          },
        );
        widget.onTap(nextIndex + 1);
      }
    }
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    _dragStart = details.globalPosition.dx;
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final delta = _dragStart - details.globalPosition.dx;
    _handleSwipe(delta);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragStart: _onHorizontalDragStart,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: _BottomNavSurface(
          child: LayoutBuilder(
            builder: (context, _) {
              final scale = _compactShellScale(context);
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 8 * scale,
                  vertical: 9 * scale,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final contentWidth = constraints.maxWidth;
                    final selectedIndex = widget.currentIndex.clamp(
                      0,
                      _items.length - 1,
                    );
                    final gap = 6.0 * scale;
                    final buttonSize =
                        ((contentWidth - gap * (_items.length - 1)) /
                                _items.length)
                            .clamp(42.0 * scale, 50.0 * scale);

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (var index = 0; index < _items.length; index++)
                          Builder(
                            builder: (context) {
                              final item = _items[index];
                              final isSelected = index == selectedIndex;

                              final button = _BottomNavButton(
                                icon: isSelected
                                    ? item.selectedIcon
                                    : item.icon,
                                label: tr(
                                  context,
                                  ru: item.label == 'Чат'
                                      ? 'Чат поддержки'
                                      : item.label,
                                  zh: [
                                    '首页',
                                    '照片',
                                    '包裹',
                                    '账单',
                                    '客服聊天',
                                    '更多',
                                  ][index],
                                ),
                                visibleLabel: tr(
                                  context,
                                  ru: item.label == 'Чат'
                                      ? 'Помощь'
                                      : item.label,
                                  zh: [
                                    '首页',
                                    '照片',
                                    '包裹',
                                    '账单',
                                    '客服',
                                    '更多',
                                  ][index],
                                ),
                                isSelected: isSelected,
                                size: buttonSize,
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  ClientLogService.instance.action(
                                    'Нажата нижняя навигация',
                                    data: {
                                      'tab': item.label,
                                      'index': index,
                                      'selected': isSelected,
                                    },
                                  );
                                  if (index == _items.length - 1) {
                                    ClientLogService.instance.action(
                                      'Открыто меню Ещё',
                                      data: {'source': 'bottom_navigation'},
                                    );
                                    showBlurredModalBottomSheet<void>(
                                      context: context,
                                      backgroundColor: Colors.transparent,
                                      barrierColor: Colors.black.withValues(
                                        alpha: 0.22,
                                      ),
                                      useSafeArea: true,
                                      isScrollControlled: true,
                                      builder: (_) => const MoreSheet(),
                                    );
                                  } else {
                                    widget.onTap(index);
                                  }
                                },
                              );
                              final targetId = index == 0
                                  ? 'nav.home'
                                  : index == _items.length - 1
                                  ? 'nav.more'
                                  : null;
                              return targetId == null
                                  ? button
                                  : TrainingTarget(
                                      id: targetId,
                                      onActivate: targetId == 'nav.more'
                                          ? button.onTap
                                          : null,
                                      child: button,
                                    );
                            },
                          ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BottomNavSurface extends StatelessWidget {
  final Widget child;

  const _BottomNavSurface({required this.child});

  @override
  Widget build(BuildContext context) {
    final scale = _compactShellScale(context);
    final radius = 24 * scale;
    return Container(
      height: _bottomNavigationHeight * scale,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 28,
            spreadRadius: -10,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.97),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: Colors.white.withValues(alpha: 0.80)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.99),
                  const Color(0xFFF8FAFC).withValues(alpha: 0.96),
                ],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _BottomNavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String visibleLabel;
  final bool isSelected;
  final double size;
  final VoidCallback onTap;

  const _BottomNavButton({
    required this.icon,
    required this.label,
    required this.visibleLabel,
    required this.isSelected,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(17),
          child: InkWell(
            borderRadius: BorderRadius.circular(17),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: size,
              height: size < 44 ? 44 : size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: isSelected ? context.brandGradient : null,
                color: isSelected ? null : Colors.white.withValues(alpha: 0.34),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.22)
                      : Colors.black.withValues(alpha: 0.035),
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: context.brandPrimary.withValues(alpha: 0.18),
                          blurRadius: 12,
                          spreadRadius: -5,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: animation, child: child),
                    ),
                    child: Icon(
                      icon,
                      key: ValueKey('${icon.codePoint}-$isSelected'),
                      size: 21,
                      color: isSelected ? Colors.white : context.brandPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  ExcludeSemantics(
                    child: Text(
                      visibleLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        height: 1.05,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : context.brandPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
