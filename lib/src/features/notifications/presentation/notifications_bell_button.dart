import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_layout.dart';
import 'package:twoalogisticcabineuser/src/core/ui/blurred_modal_bottom_sheet.dart';

import '../../../core/ui/app_colors.dart';
import '../../../core/utils/locale_text.dart';
import '../../../core/ui/pixso_top_menu_surface.dart';
import '../../../core/services/push_notification_service.dart';
import '../../clients/application/client_codes_controller.dart';
import '../application/notifications_controller.dart';
import 'notifications_sheet.dart';

class NotificationsBellButton extends ConsumerWidget {
  const NotificationsBellButton({super.key});

  static const _contentColor = Color(0xFF2F2F2F);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = AppLayout.compactScale(context);
    final radius = 12 * scale;
    final clientCode = ref.watch(activeClientCodeProvider);
    if (clientCode == null) {
      return Tooltip(
        message: tr(context, ru: 'Уведомления', zh: '通知'),
        child: PixsoTopMenuActionSurface(
          child: Icon(
            CupertinoIcons.bell,
            size: 18.5 * scale,
            color: _contentColor,
          ),
        ),
      );
    }

    // PU-M13 follow-up: badge берёт count из глобального
    // unreadNotificationsCountProvider, в который контроллер пишет backend
    // unreadCount по ВСЕМ уведомлениям (а не только по первой странице).
    // Контроллер всё ещё watch'им — иначе он autoDispose, и без него никто
    // не пишет в unreadNotificationsCountProvider.
    ref.watch(notificationsControllerProvider);
    final unreadCount = ref.watch(unreadNotificationsCountProvider);

    return Tooltip(
      message: tr(context, ru: 'Уведомления', zh: '通知'),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: () {
            final navigator = Navigator.of(context);
            final router = GoRouter.of(context);
            final useSideSheet = AppLayout.useSideNavigation(context);
            var isSheetOpen = true;

            void handleNavigate(String route) {
              if (!isSheetOpen || !navigator.mounted) return;
              isSheetOpen = false;
              if (navigator.canPop()) {
                navigator.pop();
              }
              router.push(route);
            }

            showBlurredModalBottomSheet<void>(
              context: context,
              backgroundColor: Colors.transparent,
              barrierColor: Colors.black.withValues(alpha: 0.22),
              useSafeArea: true,
              isScrollControlled: true,
              builder: (_) {
                if (useSideSheet) {
                  return NotificationsSheet(
                    clientCode: clientCode,
                    onNavigate: handleNavigate,
                  );
                }

                return DraggableScrollableSheet(
                  initialChildSize: 0.65,
                  minChildSize: 0.4,
                  maxChildSize: 0.95,
                  expand: false,
                  builder: (_, controller) => NotificationsSheet(
                    clientCode: clientCode,
                    onNavigate: handleNavigate,
                    controller: controller,
                  ),
                );
              },
            ).whenComplete(() => isSheetOpen = false);
          },
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              PixsoTopMenuActionSurface(
                highlighted: unreadCount > 0,
                child: Icon(
                  CupertinoIcons.bell,
                  size: 18.5 * scale,
                  color: unreadCount > 0 ? context.brandPrimary : _contentColor,
                ),
              ),
              if (unreadCount > 0)
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
    );
  }
}
