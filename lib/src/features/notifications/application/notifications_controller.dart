import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/push_notification_service.dart';
import '../../clients/application/client_codes_controller.dart';
import '../data/notifications_repository.dart';
import '../domain/notification_item.dart';

/// Состояние уведомлений (для совместимости)
class NotificationsState {
  final List<NotificationItem> items;
  final bool isLoading;
  final String? error;

  const NotificationsState({
    this.items = const [],
    this.isLoading = false,
    this.error,
  });

  NotificationsState copyWith({
    List<NotificationItem>? items,
    bool? isLoading,
    String? error,
  }) {
    return NotificationsState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Провайдер для уведомлений с поддержкой clientCode
final notificationsControllerProvider =
    AsyncNotifierProvider.autoDispose<
      NotificationsController,
      List<NotificationItem>
    >(NotificationsController.new);

/// Инициализатор push уведомлений для обновления списка
void initializePushNotificationsHandler(
  WidgetRef ref, {
  void Function(String route)? onNavigate,
}) {
  PushNotificationService.onFCMMessageReceived = (RemoteMessage message) {
    try {
      _handleFCMMessage(ref, message);
    } catch (e, stackTrace) {
      debugPrint('🔔 FCM foreground handler error: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  };
  PushNotificationService.onFCMMessageOpened = (RemoteMessage message) {
    return _handleFCMMessageOpened(ref, message, onNavigate);
  };

  final pushService = ref.read(pushNotificationServiceProvider);
  unawaited(
    pushService.initialize(
      onTap: (payload) =>
          _handleLocalNotificationTapped(ref, payload, onNavigate),
    ),
  );
}

void _handleFCMMessage(WidgetRef ref, RemoteMessage message) {
  debugPrint('🔔 FCM received in notifications handler: ${message.data}');

  // Получаем активный clientCode
  final clientCode = ref.read(activeClientCodeProvider);
  if (clientCode == null) {
    debugPrint('🔔 No active clientCode, skipping notification update');
    return;
  }

  // Пробуем создать NotificationItem из FCM данных
  try {
    final item = NotificationItem.fromPushData(
      message.data,
      title: message.notification?.title,
      body: message.notification?.body,
    );

    // Добавляем в контроллер
    ref.read(notificationsControllerProvider.notifier).addNotification(item);
    debugPrint('🔔 Notification added to list: ${item.title}');
  } catch (e) {
    debugPrint('🔔 Error parsing FCM message: $e');
    // Если не удалось распарсить - просто обновляем список
    ref.read(notificationsControllerProvider.notifier).refresh();
  }
}

Future<void> _handleFCMMessageOpened(
  WidgetRef ref,
  RemoteMessage message,
  void Function(String route)? onNavigate,
) async {
  debugPrint('🔔 FCM opened in notifications handler: ${message.data}');
  await _handleNotificationTapTarget(
    ref,
    NotificationTapTarget(
      route: NotificationItem.routeFromPushData(message.data),
      notificationId: NotificationItem.notificationIdFromData(message.data),
    ),
    onNavigate,
  );
}

Future<void> _handleLocalNotificationTapped(
  WidgetRef ref,
  String? payload,
  void Function(String route)? onNavigate,
) async {
  await _handleNotificationTapTarget(
    ref,
    NotificationItem.tapTargetFromPayload(payload),
    onNavigate,
  );
}

Future<void> _handleNotificationTapTarget(
  WidgetRef ref,
  NotificationTapTarget target,
  void Function(String route)? onNavigate,
) async {
  final notificationId = target.notificationId;
  if (notificationId != null && notificationId.isNotEmpty) {
    unawaited(
      ref
          .read(notificationsControllerProvider.notifier)
          .markRead(notificationId)
          .catchError((Object error, StackTrace stackTrace) {
            debugPrint('🔔 Failed to mark notification as read: $error');
            debugPrintStack(stackTrace: stackTrace);
          }),
    );
  }

  final route = target.route;
  if (route != null && route.isNotEmpty) {
    try {
      onNavigate?.call(route);
    } catch (e, stackTrace) {
      debugPrint('🔔 Notification navigation failed: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}

/// Контроллер уведомлений
class NotificationsController extends AsyncNotifier<List<NotificationItem>> {
  String? _clientCode;
  Timer? _refreshDebounce;
  bool _isRefreshing = false;
  bool _disposeRegistered = false;
  int _serverUnread = 0;
  int _page = 1;
  int _total = 0;
  bool _hasMore = false;
  bool _loadingMore = false;
  int _generation = 0;
  Future<void> _mutations = Future<void>.value();

  void _publishHistory({String? error}) {
    if (!ref.mounted) return;
    ref
        .read(notificationsHistoryInfoProvider.notifier)
        .set(
          NotificationsHistoryInfo(
            total: _total,
            hasMore: _hasMore,
            loadingMore: _loadingMore,
            error: error,
          ),
        );
  }

  Future<void> _serialize(Future<void> Function() action) {
    final generation = _generation;
    final operation = _mutations.then((_) async {
      if (ref.mounted && generation == _generation) await action();
    });
    _mutations = operation.catchError((Object _) {});
    return operation;
  }

  @override
  Future<List<NotificationItem>> build() async {
    final generation = ++_generation;
    if (!_disposeRegistered) {
      ref.onDispose(() => _refreshDebounce?.cancel());
      _disposeRegistered = true;
    }

    // В Riverpod 3.x family notifier получает arg через специальный механизм
    // Мы используем workaround через активный clientCode
    _clientCode = ref.watch(activeClientCodeProvider);
    if (_clientCode == null) {
      _serverUnread = 0;
      _page = 1;
      _total = 0;
      _hasMore = false;
      return [];
    }

    final repo = ref.watch(notificationsRepositoryProvider);
    // PU-M13: используем page-based fetch, чтобы получить unreadCount из
    // backend (работает корректно при >100 уведомлений) и иметь возможность
    // в будущем подключить loadMore.
    final page = await repo.fetchPage(
      clientCode: _clientCode!,
      page: 1,
      limit: 50,
    );
    if (!ref.mounted || generation != _generation) return page.items;
    _page = page.page;
    _total = page.total;
    _hasMore = page.hasMore;
    _publishHistory();
    _updateBadge(page.items, backendUnread: page.unreadCount);
    return page.items;
  }

  void _updateBadge(List<NotificationItem> items, {int? backendUnread}) {
    if (!ref.mounted) return;

    // PU-M13: предпочитаем unreadCount из backend, fallback на локальный
    // подсчёт, если функция вызвана не из fetch (например, после markRead).
    final unreadCount = (backendUnread ?? _serverUnread).clamp(0, 1 << 31);
    _serverUnread = unreadCount;
    ref.read(unreadNotificationsCountProvider.notifier).set(unreadCount);

    // Обновляем badge на иконке приложения
    try {
      final pushService = ref.read(pushNotificationServiceProvider);
      pushService.updateBadgeCount(unreadCount);
    } catch (e) {
      debugPrint('🔔 Badge update skipped: $e');
    }
  }

  Future<void> markRead(String id) => _serialize(() => _markRead(id));

  Future<void> _markRead(String id) async {
    final generation = _generation;
    final current = state.value;
    final intId = int.tryParse(id);
    if (intId == null) return;

    if (current == null) {
      final repo = ref.read(notificationsRepositoryProvider);
      await repo.markAsRead([intId]);
      refreshDebounced();
      return;
    }

    final idx = current.indexWhere((e) => e.id == id);
    if (idx == -1) {
      final repo = ref.read(notificationsRepositoryProvider);
      await repo.markAsRead([intId]);
      refreshDebounced();
      return;
    }
    if (current[idx].isRead) return;

    // Обновляем UI сразу
    final next = List<NotificationItem>.from(current);
    final previousUnread = _serverUnread;
    next[idx] = next[idx].copyWith(isRead: true);
    state = AsyncData(next);
    _updateBadge(next, backendUnread: previousUnread - 1);

    // Отправляем на сервер
    try {
      final repo = ref.read(notificationsRepositoryProvider);
      await repo.markAsRead([intId]);
    } catch (e) {
      // Если ошибка - откатываем
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(current);
      _updateBadge(current, backendUnread: previousUnread);
    }
  }

  Future<void> markTypesRead(Set<NotificationType> types) =>
      _serialize(() => _markTypesRead(types));

  Future<void> _markTypesRead(Set<NotificationType> types) async {
    final generation = _generation;
    if (types.isEmpty) return;
    final aliases = types
        .expand((type) => type.backendTypeAliases)
        .toSet()
        .toList(growable: false);

    final current = state.value;
    final previousUnread = _serverUnread;
    if (current != null) {
      final next = <NotificationItem>[
        for (final n in current)
          types.contains(n.type) && !n.isRead ? n.copyWith(isRead: true) : n,
      ];
      state = AsyncData(next);
      final changed = current
          .where((n) => types.contains(n.type) && !n.isRead)
          .length;
      _updateBadge(next, backendUnread: previousUnread - changed);
    }

    try {
      final repo = ref.read(notificationsRepositoryProvider);
      await repo.markTypesAsRead(aliases);
      refreshDebounced();
    } catch (e) {
      if (ref.mounted && generation == _generation && current != null) {
        state = AsyncData(current);
        _updateBadge(current, backendUnread: previousUnread);
      }
    }
  }

  Future<void> markAllRead() => _serialize(_markAllRead);

  Future<void> _markAllRead() async {
    final generation = _generation;
    final current = state.value;
    if (current == null) return;
    if (_serverUnread == 0 && current.every((n) => n.isRead)) return;
    final previousUnread = _serverUnread;

    // Обновляем UI сразу
    final next = <NotificationItem>[
      for (final n in current) n.isRead ? n : n.copyWith(isRead: true),
    ];
    state = AsyncData(next);
    _updateBadge(next, backendUnread: 0);

    // Отправляем на сервер
    try {
      final repo = ref.read(notificationsRepositoryProvider);
      await repo.markAllAsRead();
    } catch (e) {
      // Если ошибка - откатываем
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(current);
      _updateBadge(current, backendUnread: previousUnread);
    }
  }

  Future<void> refresh() => _serialize(_refresh);

  Future<void> _refresh() async {
    final generation = _generation;
    if (!ref.mounted || generation != _generation) return;
    if (_clientCode == null) return;
    if (_isRefreshing) return;

    _isRefreshing = true;
    final previous = state.value;
    try {
      final repo = ref.read(notificationsRepositoryProvider);
      final page = await repo.fetchPage(
        clientCode: _clientCode!,
        page: 1,
        limit: 50,
      );
      final merged = [...page.items];
      var lastPage = page;
      for (var index = 2; index <= _page && lastPage.hasMore; index++) {
        lastPage = await repo.fetchPage(
          clientCode: _clientCode!,
          page: index,
          limit: 50,
        );
        merged.addAll(lastPage.items);
      }
      if (!ref.mounted || generation != _generation) return;
      _page = lastPage.page;
      _total = page.total;
      _hasMore = lastPage.hasMore;
      _publishHistory();
      _updateBadge(page.items, backendUnread: page.unreadCount);
      state = AsyncData(
        {for (final n in merged) n.id: n}.values.toList(growable: false),
      );
    } catch (error, stackTrace) {
      if (!ref.mounted || generation != _generation) return;
      if (previous == null) {
        state = AsyncError(error, stackTrace);
      } else {
        debugPrint('🔔 Silent notifications refresh skipped: $error');
      }
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> loadMore() => _serialize(_loadMore);

  Future<void> _loadMore() async {
    if (!ref.mounted || _clientCode == null || !_hasMore || _loadingMore) {
      return;
    }
    final generation = _generation;
    _loadingMore = true;
    _publishHistory();
    try {
      final page = await ref
          .read(notificationsRepositoryProvider)
          .fetchPage(clientCode: _clientCode!, page: _page + 1, limit: 50);
      if (!ref.mounted || generation != _generation) return;
      final byId = {
        for (final n in state.value ?? <NotificationItem>[]) n.id: n,
      };
      for (final n in page.items) {
        byId.putIfAbsent(n.id, () => n);
      }
      _page = page.page;
      _total = page.total;
      _hasMore = page.hasMore;
      state = AsyncData(byId.values.toList(growable: false));
    } catch (error) {
      if (ref.mounted && generation == _generation) {
        _publishHistory(error: error.toString());
      }
    } finally {
      _loadingMore = false;
      if (ref.mounted && generation == _generation) {
        final error = ref.read(notificationsHistoryInfoProvider).error;
        _publishHistory(error: error);
      }
    }
  }

  void refreshDebounced() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 700), () {
      if (!ref.mounted) return;
      unawaited(refresh());
    });
  }

  /// Добавить новое уведомление (например, при получении push)
  void addNotification(NotificationItem item) {
    final current = state.value ?? [];
    final next = <NotificationItem>[
      item,
      ...current.where((n) => n.id != item.id),
    ];
    state = AsyncData(next);
    final isNew = !current.any((n) => n.id == item.id);
    if (isNew) _total++;
    _updateBadge(
      next,
      backendUnread: _serverUnread + (isNew && !item.isRead ? 1 : 0),
    );
    _publishHistory();
  }
}

/// Провайдер для подсчёта непрочитанных уведомлений
final unreadCountProvider = Provider<int>((ref) {
  ref.watch(notificationsControllerProvider);
  return ref.watch(unreadNotificationsCountProvider);
});

class NotificationsHistoryInfo {
  final int total;
  final bool hasMore;
  final bool loadingMore;
  final String? error;
  const NotificationsHistoryInfo({
    this.total = 0,
    this.hasMore = false,
    this.loadingMore = false,
    this.error,
  });
}

class NotificationsHistoryInfoNotifier
    extends Notifier<NotificationsHistoryInfo> {
  @override
  NotificationsHistoryInfo build() => const NotificationsHistoryInfo();
  void set(NotificationsHistoryInfo value) => state = value;
}

final notificationsHistoryInfoProvider =
    NotifierProvider<
      NotificationsHistoryInfoNotifier,
      NotificationsHistoryInfo
    >(NotificationsHistoryInfoNotifier.new);
