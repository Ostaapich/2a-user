import 'package:twoalogisticcabineuser/src/features/training/presentation/training_target.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/app_background.dart';
import '../../core/ui/app_layout.dart';
import '../../core/utils/locale_text.dart';
import '../../core/ui/pixso_top_menu_surface.dart';
import '../../features/clients/presentation/client_switcher_button.dart';
import '../../features/notifications/application/notifications_controller.dart';
import '../../features/notifications/domain/notification_item.dart';
import '../../features/notifications/presentation/notifications_bell_button.dart';
import '../../features/shell/presentation/desktop_side_nav.dart';

class AppScaffold extends ConsumerWidget {
  final String title;
  final Widget child;
  final bool showBack;

  const AppScaffold({
    super.key,
    required this.title,
    required this.child,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusTop = MediaQuery.paddingOf(context).top;
    final theme = Theme.of(context);
    final overlayStyle = theme.brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    final useSideNavigation = AppLayout.useSideNavigation(context);
    final sideNavExpanded = ref.watch(desktopSideNavExpandedProvider);
    final sideNavWidth = AppLayout.sideNavWidthFor(sideNavExpanded);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
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
                // The outer padding already owns the status-bar inset.
                // Page content must not count it again in header spacing.
                child: Builder(
                  builder: (bodyContext) => MediaQuery.removePadding(
                    // Preserve the keyboard inset already consumed by Scaffold.
                    context: bodyContext,
                    removeTop: true,
                    child: AppLayout.constrainContent(bodyContext, child),
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
                  child: const DesktopSideNav(),
                ),
              if (!useSideNavigation)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AppFloatingTopBar(title: title, showBack: showBack),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppFloatingTopBar extends StatelessWidget {
  final String title;
  final bool showBack;

  const AppFloatingTopBar({
    super.key,
    required this.title,
    required this.showBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overlayStyle = theme.brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    final top = MediaQuery.paddingOf(context).top;
    final useSideNavigation = AppLayout.useSideNavigation(context);
    final topBar = Padding(
      padding: EdgeInsets.fromLTRB(
        AppLayout.horizontalMargin(context),
        top + AppLayout.topBarTopMarginFor(context),
        AppLayout.horizontalMargin(context),
        AppLayout.topBarBottomGapFor(context),
      ),
      child: _buildTopBarSurface(
        context: context,
        content: const _TopBarContent(),
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: useSideNavigation
          ? topBar
          : Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: AppLayout.navigationContentMaxWidth(context),
                ),
                child: topBar,
              ),
            ),
    );
  }
}

Widget _buildTopBarSurface({
  required BuildContext context,
  required Widget content,
}) {
  // Transparent container - glass effect only on individual buttons
  return SizedBox(
    width: double.infinity,
    height: AppLayout.topBarHeightFor(context),
    child: content,
  );
}

class _TopBarContent extends StatelessWidget {
  const _TopBarContent();

  @override
  Widget build(BuildContext context) {
    final useSideNavigation = AppLayout.useSideNavigation(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (useSideNavigation)
          const Spacer()
        else
          const Flexible(
            fit: FlexFit.loose,
            child: Align(
              alignment: Alignment.centerLeft,
              child: TrainingTarget(
                id: 'nav.code',
                child: SizedBox(height: 44, child: ClientSwitcherButton()),
              ),
            ),
          ),
        const _ActionsPill(),
      ],
    );
  }
}

class _ActionsPill extends ConsumerWidget {
  const _ActionsPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsControllerProvider);
    final hasUnreadSupportChat =
        notifications.value?.any(
          (item) => !item.isRead && item.type == NotificationType.chatMessage,
        ) ??
        false;

    final scale = AppLayout.compactScale(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: PixsoTopMenuSurface(
        padding: EdgeInsets.zero,
        child: Material(
          type: MaterialType.transparency,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const TrainingTarget(
                id: 'nav.notifications',
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: NotificationsBellButton(),
                ),
              ),
              SizedBox(width: 6 * scale),
              _TopBarActionButton(
                tooltip: tr(context, ru: 'Чат поддержки', zh: '客服聊天'),
                icon: CupertinoIcons.chat_bubble_2,
                hasBadge: hasUnreadSupportChat,
                onTap: () => context.go('/support'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBarActionButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool hasBadge;
  final VoidCallback onTap;

  const _TopBarActionButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.hasBadge = false,
  });

  static const _contentColor = Color(0xFF2F2F2F);

  @override
  Widget build(BuildContext context) {
    final scale = AppLayout.compactScale(context);
    final radius = 12 * scale;

    return SizedBox(
      width: 44,
      height: 44,
      child: Tooltip(
        message: tooltip,
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(radius),
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: onTap,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                PixsoTopMenuActionSurface(
                  child: Icon(icon, size: 18.5 * scale, color: _contentColor),
                ),
                if (hasBadge)
                  Positioned(
                    right: (44 - 30 * scale) / 2 + 2 * scale,
                    top: (44 - 30 * scale) / 2 + 2 * scale,
                    child: Container(
                      width: 8 * scale,
                      height: 8 * scale,
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: Colors.white,
                          width: 1.5 * scale,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
