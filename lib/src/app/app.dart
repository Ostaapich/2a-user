import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/cache/stale_data_cache.dart';
import '../core/logging/client_log_service.dart';
import '../core/network/api_client.dart';
import '../core/network/api_config.dart';
import '../core/services/app_language_service.dart';
import '../core/services/push_notification_service.dart';
import '../core/services/app_performance_monitor.dart';
import '../core/services/update_gate_provider.dart';
import '../core/services/chat_presence_service.dart';
import '../core/services/delta_sync_provider.dart';
import '../core/services/websocket_provider.dart';
import '../core/ui/app_colors.dart';
import '../core/ui/app_layout.dart';
import '../core/ui/app_keyboard_dismiss.dart';
import '../core/ui/app_toast.dart';
import '../core/ui/app_update_gate.dart';
import '../core/ui/demo_mode_banner.dart';
import '../features/auth/application/sentry_context_provider.dart';
import '../features/auth/data/auth_provider.dart';
import '../features/notifications/application/notifications_controller.dart';
import '../features/profile/data/problem_report_repository.dart';
import '../features/training/presentation/training_tour_host.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> with WidgetsBindingObserver {
  DateTime? _pausedAt;
  String? _pendingNotificationRoute;
  bool _problemReportFlushScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppPerformanceMonitor.instance.start();
    _setupAppUpdateRequiredHandler();
    // Инициализируем обработчик push уведомлений
    WidgetsBinding.instance.addPostFrameCallback((_) {
      initializePushNotificationsHandler(
        ref,
        onNavigate: _handleNotificationNavigation,
      );
      _setupUnauthorizedHandler();
      unawaited(
        ref.read(appUpdateGateProvider.notifier).check(reason: 'startup'),
      );
    });
  }

  void _setupAppUpdateRequiredHandler() {
    ref.read(apiClientProvider).setOnAppUpdateRequiredCallback((payload) {
      ref.read(appUpdateGateProvider.notifier).requireFromServer(payload);
    });
  }

  void _handleNotificationNavigation(String route) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navigateOrQueueNotification(route);
    });
  }

  void _navigateOrQueueNotification(String route) {
    final authState = ref.read(authProvider);
    if (authState.isLoading) {
      _pendingNotificationRoute = route;
      debugPrint('🔔 Push navigation queued until auth is ready: $route');
      return;
    }

    if (!authState.isLoggedIn) {
      debugPrint('🔔 Push navigation skipped: user is not logged in');
      _pendingNotificationRoute = null;
      return;
    }

    _goToNotificationRoute(route);
  }

  void _goToNotificationRoute(String route) {
    try {
      debugPrint('🔔 Push navigation: $route');
      ref.read(routerProvider).go(route);
    } catch (e, stackTrace) {
      debugPrint('🔔 Push navigation failed: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _flushPendingNotificationRoute() {
    final route = _pendingNotificationRoute;
    if (route == null) return;
    _pendingNotificationRoute = null;
    _navigateOrQueueNotification(route);
  }

  /// Настройка обработчика 401 ошибки
  void _setupUnauthorizedHandler() {
    final apiClient = ref.read(apiClientProvider);
    apiClient.setOnUnauthorizedCallback(() {
      ClientLogService.instance.add(
        type: 'auth_logout_by_401',
        level: 'warning',
        message: 'Запускаем выход из-за 401',
      );
      ref.read(authProvider.notifier).logout();
    });
  }

  @override
  void dispose() {
    AppPerformanceMonitor.instance.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    ClientLogService.instance.add(
      type: 'app_lifecycle',
      level: 'info',
      message: 'Состояние приложения: ${state.name}',
      data: {'state': state.name},
    );

    // На Flutter Web `resumed` может приходить от смены вкладки/фокуса окна.
    // Не применяем mobile/iOS reconnect-логику, иначе web получает лишние
    // force reconnect + full refetch без реального ухода приложения в background.
    if (kIsWeb) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ref.read(chatPresenceServiceProvider).onAppPaused();
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      // iOS-фикс: в background TCP-сокеты (HTTP keepalive и WebSocket)
      // часто становятся мертвы, но dart:io этого не знает и пишет в
      // зомби-соединение до receive timeout → у пользователя висит
      // spinner и UI не обновляется. Принудительно пересоздаём сокет
      // только если пауза была больше 5 секунд (короткие паузы —
      // клавиатура, notification center — сокет пережить может).
      final pausedAt = _pausedAt;
      _pausedAt = null;
      if (pausedAt == null) return;
      final pausedFor = DateTime.now().difference(pausedAt);
      if (pausedFor.inSeconds < 5) return;
      debugPrint(
        '[App] Resumed after ${pausedFor.inSeconds}s — force WS reconnect',
      );
      ClientLogService.instance.add(
        type: 'app_resumed_refresh',
        level: 'warning',
        message: 'Приложение вернулось из background, пересоздаём соединения',
        data: {'pausedForSeconds': pausedFor.inSeconds},
      );
      ref
          .read(apiClientProvider)
          .resetConnections(reason: 'app_resumed', force: false);
      ref.read(webSocketServiceProvider).forceReconnect(reason: 'app_resumed');
      unawaited(
        ref.read(appUpdateGateProvider.notifier).check(reason: 'resume'),
      );
      unawaited(ref.read(authProvider.notifier).refreshPushRegistration());
      Future.microtask(() {
        if (!mounted) return;
        if (!ref.read(authProvider).isLoggedIn) return;
        _scheduleProblemReportQueueFlush(reason: 'app_resumed');
        invalidateClientCoreProviders(ref);
      });
    }
  }

  void _scheduleProblemReportQueueFlush({required String reason}) {
    if (_problemReportFlushScheduled) return;
    _problemReportFlushScheduled = true;
    Future<void>.delayed(const Duration(seconds: 2), () async {
      try {
        if (!mounted) return;
        final auth = ref.read(authProvider);
        final clientId = auth.clientId;
        if (!auth.isLoggedIn || clientId == null) return;
        final sent = await ref
            .read(problemReportRepositoryProvider)
            .flushQueuedReports(clientId: clientId);
        if (!mounted) return;
        if (sent > 0) {
          ClientLogService.instance.add(
            type: 'problem_report_queue_flushed',
            level: 'info',
            message: 'Отправлена локальная очередь отчётов о проблеме',
            data: {'sent': sent, 'reason': reason},
          );
        }
      } finally {
        _problemReportFlushScheduled = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.isLoading) return;
      if (!next.isLoggedIn) {
        _pendingNotificationRoute = null;
        return;
      }
      _scheduleProblemReportQueueFlush(reason: 'auth_logged_in');
      if (_pendingNotificationRoute == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _flushPendingNotificationRoute();
      });
    });

    ref.listen<StaleDataNotice?>(staleDataNoticeProvider, (previous, next) {
      if (next == null) return;
      if (previous?.createdAt == next.createdAt) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppToast.show(
          context,
          next.message,
          icon: Icons.sync_problem_rounded,
          backgroundColor: const Color(0xFFF59E0B),
          duration: const Duration(seconds: 6),
        );
      });
    });

    // WebSocket + delta sync: watch ensures re-trigger on auth state change
    ref.watch(webSocketAutoConnectProvider);
    ref.watch(deltaSyncProvider);
    ref.watch(sentryContextProvider);
    ref.watch(pushNotificationBrandingProvider);

    final router = ref.watch(routerProvider);
    final brandColors = ref.watch(brandColorsProvider);
    final language = ref.watch(appLanguageProvider);

    // 2a-user всегда работает напрямую с основным backend.
    // HK-прокси используется только в 2a-admin для сотрудников из Китая.
    ApiConfig.setChineseMode(false);

    return MaterialApp.router(
      title: 'Карго',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ru'), Locale('zh')],
      locale: language.locale,
      theme: AppTheme.lightWithColors(brandColors),
      routerConfig: router,
      builder: (context, child) {
        final content = _CompactTextScale(
          child: child ?? const SizedBox.shrink(),
        );
        return AppKeyboardDismissRegion(
          child: AppUpdateGate(
            child: TrainingTourHost(
              router: router,
              child: Stack(children: [content, const DemoModeBanner()]),
            ),
          ),
        );
      },
    );
  }
}

class _CompactTextScale extends StatelessWidget {
  final Widget child;

  const _CompactTextScale({required this.child});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compactScale = AppLayout.compactTextScale(context);
    if (compactScale == 1.0) return child;

    final baseScale = media.textScaler.scale(14) / 14;
    // Preserve the user's accessibility scaler, including nonlinear scaling.
    if (baseScale > 1.0) return child;
    final effectiveScale = (baseScale * compactScale).clamp(0.82, 1.0);

    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.linear(effectiveScale)),
      child: child,
    );
  }
}
