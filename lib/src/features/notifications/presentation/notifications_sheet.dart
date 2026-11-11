import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../training/presentation/training_target.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/ui/sheet_handle.dart';
import '../../../core/utils/locale_text.dart';
import '../application/notifications_controller.dart';
import '../domain/notification_item.dart';

/// Интервал polling (30 секунд)
const _kPollingInterval = Duration(seconds: 30);

class NotificationsSheet extends ConsumerStatefulWidget {
  final String clientCode;
  final ValueChanged<String> onNavigate;
  final ScrollController? controller;

  const NotificationsSheet({
    super.key,
    required this.clientCode,
    required this.onNavigate,
    this.controller,
  });

  @override
  ConsumerState<NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends ConsumerState<NotificationsSheet> {
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    // Первый запрос сразу при открытии (отложено чтобы не модифицировать провайдер во время build)
    debugPrint('🔔 Initial notifications load...');
    Future(() {
      if (!mounted) return;
      ref.read(notificationsControllerProvider.notifier).refresh();
    });

    // Затем каждые 30 секунд
    _pollingTimer = Timer.periodic(_kPollingInterval, (_) {
      if (!mounted) return;
      debugPrint('🔔 Polling notifications...');
      ref.read(notificationsControllerProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(notificationsControllerProvider);
    final unreadCount = ref.watch(unreadCountProvider);
    final history = ref.watch(notificationsHistoryInfoProvider);
    final hasUnread = unreadCount > 0;

    return SafeArea(
      top: false,
      bottom: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          children: [
            Center(
              child: SizedBox(
                width: 42,
                child: TrainingTarget(
                  id: 'notification.sheet.dismiss',
                  onActivate: () => Navigator.of(context).pop(),
                  child: SheetHandle(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: _NotificationsHeader(
                unreadCount: unreadCount,
                totalCount: history.total,
                onMarkAllRead: hasUnread
                    ? () => ref
                          .read(notificationsControllerProvider.notifier)
                          .markAllRead()
                    : null,
              ),
            ),
            Expanded(
              child: itemsAsync.when(
                loading: () =>
                    _NotificationsLoadingState(color: context.brandPrimary),
                error: (e, _) => _NotificationsErrorState(
                  message: 'Ошибка загрузки: $e',
                  onRetry: () => ref
                      .read(notificationsControllerProvider.notifier)
                      .refresh(),
                ),
                data: (items) => _buildItemsList(context, items),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsList(BuildContext context, List<NotificationItem> items) {
    final history = ref.watch(notificationsHistoryInfoProvider);
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async {
          debugPrint('🔔 Pull-to-refresh triggered');
          await ref.read(notificationsControllerProvider.notifier).refresh();
        },
        color: context.brandPrimary,
        child: SingleChildScrollView(
          controller: widget.controller,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.45,
            child: const _NotificationsEmptyState(),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        debugPrint('🔔 Pull-to-refresh triggered');
        await ref.read(notificationsControllerProvider.notifier).refresh();
      },
      color: context.brandPrimary,
      child: ListView.separated(
        controller: widget.controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount:
            items.length + (history.hasMore || history.error != null ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (i == items.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: history.loadingMore
                  ? const Center(child: CircularProgressIndicator())
                  : TextButton.icon(
                      onPressed: () => ref
                          .read(notificationsControllerProvider.notifier)
                          .loadMore(),
                      icon: Icon(
                        history.error == null
                            ? Icons.expand_more
                            : Icons.refresh,
                      ),
                      label: Text(
                        tr(
                          context,
                          ru: history.error == null
                              ? 'Загрузить ещё'
                              : 'Не удалось загрузить историю. Повторить',
                          zh: history.error == null ? '加载更多' : '无法加载历史记录，重试',
                        ),
                      ),
                    ),
            );
          }
          final item = items[i];
          return _NotificationTile(
            item: item,
            onTap: () async {
              await ref
                  .read(notificationsControllerProvider.notifier)
                  .markRead(item.id);
              if (!mounted) return;
              final route = item.route;
              if (route == null) return;
              widget.onNavigate(route);
            },
          );
        },
      ),
    );
  }
}

class _NotificationsHeader extends StatelessWidget {
  final int unreadCount;
  final int totalCount;
  final VoidCallback? onMarkAllRead;

  const _NotificationsHeader({
    required this.unreadCount,
    required this.totalCount,
    required this.onMarkAllRead,
  });

  @override
  Widget build(BuildContext context) {
    final hasUnread = unreadCount > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: context.brandGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: context.brandPrimary.withValues(alpha: 0.18),
            blurRadius: 22,
            spreadRadius: -12,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 400;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (!compact)
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                  child: const Icon(
                    Icons.notifications_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              if (!compact) const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Уведомления',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'Gilroy',
                          fontSize: 23,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.25,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      hasUnread
                          ? '$unreadCount новых из $totalCount'
                          : totalCount > 0
                          ? 'Все уведомления прочитаны'
                          : 'Новых событий пока нет',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xE6FFFFFF),
                        fontFamily: 'Gilroy',
                        fontSize: 12.8,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (onMarkAllRead != null)
                _HeaderActionButton(onTap: onMarkAllRead!, compact: compact)
              else
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: const Icon(
                    Icons.check_circle_outline_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool compact;

  const _HeaderActionButton({required this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tr(context, ru: 'Прочитать всё', zh: '全部标为已读'),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 12,
              vertical: 10,
            ),
            constraints: const BoxConstraints(minHeight: 44),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.done_all_rounded,
                  color: Colors.white,
                  size: compact ? 18 : 21,
                ),
                SizedBox(width: compact ? 6 : 8),
                Text(
                  tr(context, ru: 'Прочитать всё', zh: '全部标为已读'),
                  style: TextStyle(
                    fontSize: compact ? 12 : 14,
                    color: Colors.white,
                    fontFamily: 'Gilroy',
                    fontWeight: FontWeight.w700,
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

class _NotificationsLoadingState extends StatelessWidget {
  final Color color;

  const _NotificationsLoadingState({required this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

class _NotificationsErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _NotificationsErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44, color: Colors.red),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'Gilroy',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(onPressed: onRetry, child: const Text('Повторить')),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationsEmptyState extends StatelessWidget {
  const _NotificationsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: context.brandPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.notifications_none_rounded,
              color: context.brandPrimary,
              size: 34,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Пока нет уведомлений',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Gilroy',
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Потяните вниз, чтобы обновить список',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Gilroy',
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

String _cleanNotificationTitle(String title) {
  return title
      .replaceFirst(
        RegExp(r'^[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\s]+', unicode: true),
        '',
      )
      .trimLeft();
}

class _NotificationTile extends StatelessWidget {
  final NotificationItem item;
  final VoidCallback onTap;

  const _NotificationTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM, HH:mm', 'ru');
    final time = df.format(item.createdAt);
    final title = _cleanNotificationTitle(item.title);
    final accent = context.brandPrimary;
    final unread = !item.isRead;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: unread ? accent.withValues(alpha: 0.065) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: unread
                  ? accent.withValues(alpha: 0.20)
                  : Colors.black.withValues(alpha: 0.035),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.045),
                blurRadius: 24,
                spreadRadius: -16,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Icon(item.type.icon, color: accent, size: 22),
                  ),
                  if (unread)
                    Positioned(
                      right: -1,
                      top: -1,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: context.brandPrimary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title.isEmpty ? item.type.displayName : title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontFamily: 'Gilroy',
                              fontWeight: unread
                                  ? FontWeight.w900
                                  : FontWeight.w800,
                              fontSize: 15.5,
                              height: 1.12,
                              letterSpacing: -0.05,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          time,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontFamily: 'Gilroy',
                            fontSize: 11.8,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    _NotificationTypePill(type: item.type),
                    const SizedBox(height: 8),
                    Text(
                      item.message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontFamily: 'Gilroy',
                        fontSize: 14,
                        height: 1.28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (item.oldStatus != null && item.newStatus != null) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _StatusBadge(status: item.oldStatus!, isOld: true),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          _StatusBadge(status: item.newStatus!, isOld: false),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary.withValues(alpha: 0.62),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationTypePill extends StatelessWidget {
  final NotificationType type;

  const _NotificationTypePill({required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: context.brandPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.brandPrimary.withValues(alpha: 0.10)),
      ),
      child: Text(
        type.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'Gilroy',
          fontSize: 11.2,
          height: 1,
          fontWeight: FontWeight.w800,
          color: context.brandPrimary,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final bool isOld;

  const _StatusBadge({required this.status, required this.isOld});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isOld
            ? Colors.grey.shade200
            : const Color(0xFF4CAF50).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isOld ? Colors.grey.shade600 : const Color(0xFF2E7D32),
        ),
      ),
    );
  }
}
