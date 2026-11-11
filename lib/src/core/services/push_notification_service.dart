import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../firebase_options.dart';
import '../../features/notifications/domain/notification_item.dart';
import '../ui/app_colors.dart';
import '../branding/company_branding_provider.dart';
import 'platform_helper.dart';

/// Проверка платформы (безопасно для Web)
bool get _isMobilePlatform => isMobilePlatformImpl();

/// Проверка iOS (безопасно для Web)
bool get _isIOS => isIOSImpl();

/// Проверка Android (безопасно для Web)
bool get _isAndroid => isAndroidImpl();

/// Проверка Desktop (безопасно для Web)
bool get _isDesktop => isDesktopImpl();

String localNotificationChannelId(
  String baseId, {
  required bool soundEnabled,
}) => '${baseId}_${soundEnabled ? 'sound' : 'silent'}';

Future<bool> checkWebPushSupport(FirebaseMessaging messaging) =>
    messaging.isSupported().timeout(const Duration(seconds: 3));

/// Background message handler (must be top-level)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await PushNotificationService._recordPushReceived(message);
  if (kDebugMode) {
    debugPrint('🔔 Background FCM message: ${message.messageId}');
  }
}

/// Провайдер для сервиса push-уведомлений
final pushNotificationServiceProvider = Provider<PushNotificationService>((
  ref,
) {
  return PushNotificationService();
});

/// Bound from the app root, after auth is available. Keep the service provider
/// independent of companyNameProvider: auth itself initializes push services.
final pushNotificationBrandingProvider = Provider<void>((ref) {
  final companyName = ref.watch(companyNameProvider);
  final service = ref.read(pushNotificationServiceProvider);
  unawaited(service.updateCompanyName(companyName));
});

List<AndroidNotificationChannel> companyNotificationChannels(
  String companyName,
) => [
  AndroidNotificationChannel(
    'fcm_channel',
    'Основные уведомления',
    description: 'Важные уведомления $companyName',
    importance: Importance.high,
    playSound: true,
  ),
  AndroidNotificationChannel(
    'fcm_channel_silent',
    'Основные уведомления без звука',
    description: 'Уведомления $companyName без звука',
    importance: Importance.high,
    playSound: false,
  ),
];

/// Простой Notifier для bool состояния
class IsChatScreenOpenNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

/// Провайдер для отслеживания открытого экрана чата
final isChatScreenOpenProvider =
    NotifierProvider<IsChatScreenOpenNotifier, bool>(
      IsChatScreenOpenNotifier.new,
    );

/// Простой Notifier для int состояния
class UnreadNotificationsCountNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void set(int value) => state = value;
}

/// Провайдер для счётчика непрочитанных уведомлений
final unreadNotificationsCountProvider =
    NotifierProvider<UnreadNotificationsCountNotifier, int>(
      UnreadNotificationsCountNotifier.new,
    );

/// Сервис для управления push-уведомлениями и badge на иконке приложения
class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  String _companyName = fallbackCompanyName;

  Future<void> updateCompanyName(String companyName) async {
    final name = companyName.trim().isEmpty
        ? fallbackCompanyName
        : companyName.trim();
    if (_companyName == name) return;
    _companyName = name;
    if (_isInitialized && !kIsWeb && _isAndroid) {
      try {
        await _updateNotificationChannels();
      } catch (error) {
        debugPrint('🔔 Notification channel branding update failed: $error');
      }
    }
  }

  Future<void> _updateNotificationChannels() async {
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    for (final channel in companyNotificationChannels(_companyName)) {
      await android?.createNotificationChannel(channel);
    }
  }

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static FirebaseMessaging? _messaging;
  static bool _isInitialized = false;
  static bool _firebaseReady = false; // Firebase SDK полностью инициализирован
  static bool _fcmTokenObtained = false; // FCM токен получен
  static bool _messagingSupported = true; // FCM доступен в текущем браузере/ОС
  static Future<void>? _firebaseInitializationFuture;
  static bool _initializationRetryRunning = false;
  static bool _tokenRetryRunning = false;
  static bool _pushSessionActive = true;
  static bool? _tokenWebOverride;
  static bool? _tokenIOSOverride;
  static final List<RemoteMessage> _pendingOpenedMessages = [];
  static const _notificationsEnabledKey = 'push_notifications_enabled';
  static const _soundEnabledKey = 'push_sound_enabled';
  static const _badgeEnabledKey = 'push_badge_enabled';
  static const _lastPushReceivedAtKey = 'push_last_received_at';
  static const _lastRegistrationAtKey = 'push_last_registration_at';
  static const _lastRegistrationErrorKey = 'push_last_registration_error';
  static bool _preferencesLoaded = false;
  static bool _notificationsEnabled = true;
  static bool _soundEnabled = true;
  static bool _badgeEnabled = true;
  static String? _authorizationStatus;
  static DateTime? _lastTokenObtainedAt;
  static DateTime? _lastRegistrationAttemptAt;
  static int _registrationAttemptCount = 0;

  static ({bool notificationsEnabled, bool soundEnabled, bool badgeEnabled})
  get devicePreferences => (
    notificationsEnabled: _notificationsEnabled,
    soundEnabled: _soundEnabled,
    badgeEnabled: _badgeEnabled,
  );

  // Callback для обработки нажатия на уведомление
  void Function(String? route)? onNotificationTap;
  final List<String?> _pendingLocalNotificationTapPayloads = [];

  // Callback для обработки FCM сообщений
  static Function(RemoteMessage)? onFCMMessageReceived;

  // Callback для обработки открытия push-уведомления
  static FutureOr<void> Function(RemoteMessage)? _onFCMMessageOpened;

  static FutureOr<void> Function(RemoteMessage)? get onFCMMessageOpened =>
      _onFCMMessageOpened;

  static set onFCMMessageOpened(
    FutureOr<void> Function(RemoteMessage)? handler,
  ) {
    _onFCMMessageOpened = handler;
    if (handler == null || _pendingOpenedMessages.isEmpty) return;

    final pending = List<RemoteMessage>.from(_pendingOpenedMessages);
    _pendingOpenedMessages.clear();
    for (final message in pending) {
      _dispatchOpenedMessage(message);
    }
  }

  // Callback для обработки обновления FCM токена
  static Function(String)? onTokenRefreshed;
  static void Function()? onReceiptQueued;

  static int? _activeClientId;

  static void setActiveClient(int? clientId) {
    _activeClientId = clientId;
    _pushSessionActive = clientId != null;
  }

  static void clearActiveClient() {
    _activeClientId = null;
    _pushSessionActive = false;
  }

  /// Call directly from a button handler: Web permission needs user activation.
  static Future<bool> requestPermissionFromUserGesture() async {
    final messaging = _messaging;
    if (messaging == null) return false;
    final settings = await messaging
        .requestPermission(alert: true, badge: true, sound: true)
        .timeout(const Duration(seconds: 30));
    _authorizationStatus = settings.authorizationStatus.name;
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  static Future<void> revokeTokenForLogout() async {
    final messaging = _messaging;
    _fcmTokenObtained = false;
    if (messaging == null) return;
    try {
      await messaging.deleteToken().timeout(const Duration(seconds: 3));
    } catch (error) {
      debugPrint('🔔 Token revocation unavailable: $error');
    }
  }

  static void recordDeviceRegistrationAttempt() {
    _lastRegistrationAttemptAt = DateTime.now().toUtc();
    _registrationAttemptCount++;
  }

  static Future<void> recordDeviceRegistrationSuccess() async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastRegistrationAtKey, now);
      await prefs.remove(_lastRegistrationErrorKey);
    } catch (_) {}
  }

  static Future<void> recordDeviceRegistrationFailure(String message) async {
    try {
      final normalized = message.trim();
      final safeMessage = normalized.length > 300
          ? normalized.substring(0, 300)
          : normalized;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastRegistrationErrorKey, safeMessage);
    } catch (_) {}
  }

  /// Безопасная диагностика push без FCM token и других секретов.
  static Future<Map<String, dynamic>> diagnosticSnapshot() async {
    await _loadDevicePreferences();
    String? authorizationStatus = _authorizationStatus;
    bool? systemNotificationsEnabled;
    bool? defaultChannelPresent;
    bool? silentChannelPresent;

    try {
      final messaging = _messaging;
      if (messaging != null) {
        authorizationStatus = (await messaging.getNotificationSettings())
            .authorizationStatus
            .name;
      }
    } catch (_) {}

    if (_isAndroid) {
      try {
        final service = PushNotificationService();
        await service.initialize();
        final android = service._notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        systemNotificationsEnabled = await android?.areNotificationsEnabled();
        final channels = await android?.getNotificationChannels();
        defaultChannelPresent = channels?.any(
          (channel) => channel.id == 'fcm_channel',
        );
        silentChannelPresent = channels?.any(
          (channel) => channel.id == 'fcm_channel_silent',
        );
      } catch (_) {}
    }

    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    return {
      'firebaseReady': _firebaseReady,
      'messagingSupported': _messagingSupported,
      'messagingAddressAvailable': _fcmTokenObtained,
      'notificationPermissionStatus': authorizationStatus ?? 'unknown',
      'systemNotificationsEnabled': systemNotificationsEnabled,
      'notificationsEnabledInApp': _notificationsEnabled,
      'soundEnabledInApp': _soundEnabled,
      'defaultChannelPresent': defaultChannelPresent,
      'silentChannelPresent': silentChannelPresent,
      'registrationAttemptCount': _registrationAttemptCount,
      'lastMessagingAddressAt': _lastTokenObtainedAt?.toIso8601String(),
      'lastRegistrationAttemptAt': _lastRegistrationAttemptAt
          ?.toIso8601String(),
      'lastRegistrationAt': prefs?.getString(_lastRegistrationAtKey),
      'lastRegistrationError': prefs?.getString(_lastRegistrationErrorKey),
      'lastPushReceivedAt': prefs?.getString(_lastPushReceivedAtKey),
    };
  }

  static Future<void> _recordPushReceived(
    RemoteMessage message, {
    bool opened = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      await prefs.setString(
        _lastPushReceivedAtKey,
        DateTime.now().toUtc().toIso8601String(),
      );
      final notificationId = int.tryParse(
        message.data['notificationId']?.toString() ?? '',
      );
      final recipientId = int.tryParse(
        message.data['recipientId']?.toString() ??
            message.data['clientId']?.toString() ??
            '',
      );
      if (notificationId != null && recipientId != null) {
        final event = opened ? 'opened' : 'received';
        await prefs.setString(
          'push_receipt_${recipientId}_${notificationId}_$event',
          jsonEncode({
            'notificationId': notificationId,
            'recipientId': recipientId,
            'event': event,
            'queuedAt': DateTime.now().toUtc().toIso8601String(),
          }),
        );
        final receipts = prefs
            .getKeys()
            .where((key) => key.startsWith('push_receipt_'))
            .toList();
        if (receipts.length > 200) {
          String queuedAt(String key) {
            try {
              return (jsonDecode(prefs.getString(key) ?? '{}')
                          as Map)['queuedAt']
                      ?.toString() ??
                  '';
            } catch (_) {
              return '';
            }
          }

          receipts.sort((a, b) => queuedAt(a).compareTo(queuedAt(b)));
          for (final key in receipts.take(receipts.length - 200)) {
            await prefs.remove(key);
          }
        }
        onReceiptQueued?.call();
      }
    } catch (_) {}
  }

  static Future<void> applyDevicePreferences({
    bool? notificationsEnabled,
    bool? soundEnabled,
    bool? badgeEnabled,
  }) async {
    if (notificationsEnabled == null &&
        soundEnabled == null &&
        badgeEnabled == null) {
      return;
    }

    _notificationsEnabled = notificationsEnabled ?? _notificationsEnabled;
    _soundEnabled = soundEnabled ?? _soundEnabled;
    _badgeEnabled = badgeEnabled ?? _badgeEnabled;
    _preferencesLoaded = true;

    final prefs = await SharedPreferences.getInstance();
    if (notificationsEnabled != null) {
      await prefs.setBool(_notificationsEnabledKey, notificationsEnabled);
    }
    if (soundEnabled != null) {
      await prefs.setBool(_soundEnabledKey, soundEnabled);
    }
    if (badgeEnabled != null) {
      await prefs.setBool(_badgeEnabledKey, badgeEnabled);
    }
  }

  static Future<void> _loadDevicePreferences() async {
    if (_preferencesLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _notificationsEnabled = prefs.getBool(_notificationsEnabledKey) ?? true;
    _soundEnabled = prefs.getBool(_soundEnabledKey) ?? true;
    _badgeEnabled = prefs.getBool(_badgeEnabledKey) ?? true;
    _preferencesLoaded = true;
  }

  /// Статическая инициализация Firebase после восстановления/создания сессии.
  /// Выполняется с таймаутом и не должна блокировать auth-flow.
  static Future<void> initializeFirebase() async {
    if (_firebaseReady) return;
    final inProgress = _firebaseInitializationFuture;
    if (inProgress != null) return inProgress;

    final future = _initializeFirebase();
    _firebaseInitializationFuture = future;
    try {
      await future;
    } finally {
      _firebaseInitializationFuture = null;
    }
  }

  static Future<void> _initializeFirebase() async {
    try {
      debugPrint('🔔 Starting Firebase initialization...');

      if (Firebase.apps.isEmpty) {
        // Таймаут 10с — если Google-серверы недоступны (DPI/ТСПУ),
        // не зависаем бесконечно
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            debugPrint(
              '🔔 Firebase.initializeApp() timed out (10s) — Google servers may be blocked by ISP',
            );
            return Firebase.app();
          },
        );
        debugPrint('🔔 Firebase app initialized');
      } else {
        debugPrint('🔔 Firebase app already initialized');
      }

      // Firebase Messaging поддерживается на Web, Android, iOS
      if (kIsWeb || _isMobilePlatform) {
        final messaging = FirebaseMessaging.instance;

        if (kIsWeb) {
          final isSupported = await checkWebPushSupport(messaging);
          if (!isSupported) {
            _messagingSupported = false;
            _messaging = null;
            _firebaseReady = true;
            debugPrint(
              '🔔 Firebase Messaging is not supported in this browser',
            );
            return;
          }
        }

        _messagingSupported = true;
        _messaging = messaging;
        debugPrint('🔔 Firebase Messaging instance created');

        // Каналы должны существовать до первого background push. Особенно это
        // важно на OEM-прошивках, которые не всегда корректно создают fallback.
        if (_isAndroid) {
          await PushNotificationService().initialize().timeout(
            const Duration(seconds: 5),
          );
        }

        // Запрос разрешений
        try {
          final settings =
              await (kIsWeb
                      ? _messaging!.getNotificationSettings()
                      : _messaging!.requestPermission(
                          alert: true,
                          badge: true,
                          sound: true,
                        ))
                  .timeout(const Duration(seconds: 5));
          _authorizationStatus = settings.authorizationStatus.name;
          debugPrint('🔔 FCM Permission: ${settings.authorizationStatus}');
        } catch (e) {
          _authorizationStatus = 'request_failed';
          debugPrint('🔔 FCM Permission request failed/timed out: $e');
        }

        // Получить токен сразу после инициализации
        try {
          final token = await getFCMToken().timeout(
            const Duration(seconds: 10),
          );
          if (token != null) {
            _fcmTokenObtained = true;
            debugPrint('🔔 Initial FCM token obtained successfully');
          } else {
            debugPrint('🔔 Warning: Initial FCM token is null');
          }
        } catch (e) {
          debugPrint(
            '🔔 Error getting initial FCM token (may retry later): $e',
          );
        }

        // Resolve the only fallible async operation before attaching listeners,
        // so a retry cannot attach the same listeners a second time.
        final initialMessage = await _messaging!.getInitialMessage().timeout(
          const Duration(seconds: 5),
        );

        // Background handler
        FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler,
        );

        // Token refresh — Firebase периодически обновляет FCM токен.
        // Без этого listener старый токен становится невалидным и пуши перестают приходить.
        _messaging!.onTokenRefresh.listen(
          (newToken) {
            debugPrint(
              '🔔 FCM token refreshed: ${newToken.substring(0, 20)}...',
            );
            _fcmTokenObtained = true;
            onTokenRefreshed?.call(newToken);
          },
          onError: (Object error) {
            if (_isUnsupportedMessagingError(error)) {
              _messagingSupported = false;
            }
            debugPrint('🔔 FCM token refresh error: $error');
          },
        );

        // Foreground handler
        FirebaseMessaging.onMessage.listen((message) {
          unawaited(_recordPushReceived(message));
          debugPrint('🔔 Foreground FCM: ${message.notification?.title}');
          if (!_isMessageForActiveClient(message)) {
            debugPrint('🔔 Foreground FCM skipped: recipient mismatch');
            return;
          }
          onFCMMessageReceived?.call(message);
          _showFCMNotification(message);
        });

        // Message opened app
        FirebaseMessaging.onMessageOpenedApp.listen((message) {
          unawaited(_recordPushReceived(message, opened: true));
          debugPrint('🔔 FCM opened app: ${message.notification?.title}');
          if (!_isMessageForActiveClient(message)) {
            debugPrint('🔔 FCM opened app skipped: recipient mismatch');
            return;
          }
          _dispatchOpenedMessage(message);
        });

        if (initialMessage != null) {
          unawaited(_recordPushReceived(initialMessage, opened: true));
          Future.microtask(() {
            debugPrint(
              '🔔 FCM initial message: ${initialMessage.notification?.title}',
            );
            if (!_isMessageForActiveClient(initialMessage)) {
              debugPrint('🔔 FCM initial message skipped: recipient mismatch');
              return;
            }
            _dispatchOpenedMessage(initialMessage);
          });
        }
      } else {
        debugPrint(
          '🔔 FCM not supported on this platform (Windows/Linux/macOS Desktop)',
        );
      }

      _firebaseReady = true;
      debugPrint('🔔 Firebase initialized');

      // Если токен не получен — запускаем фоновый retry
      if (_messagingSupported && !_fcmTokenObtained) {
        unawaited(_retryGetFCMToken());
      }
    } catch (e) {
      if (_isUnsupportedMessagingError(e)) {
        _messagingSupported = false;
        _messaging = null;
        _firebaseReady = true;
        debugPrint('🔔 Firebase Messaging unsupported (non-fatal): $e');
        return;
      }
      debugPrint('🔔 Firebase init error (non-fatal): $e');
      // Запускаем retry всей инициализации
      unawaited(_retryInitializeFirebase());
    }
  }

  static bool _isUnsupportedMessagingError(Object error) {
    final text = error.toString();
    return text.contains('messaging/unsupported-browser') ||
        text.contains('unsupported-browser') ||
        text.contains('INDEXED_DB_UNSUPPORTED');
  }

  /// Повторные попытки инициализации Firebase (30с → 60с → ... → макс 600с)
  @visibleForTesting
  static Future<void> runInitializationRetryForTesting(
    Future<void> Function() retry,
  ) => _retryInitializeFirebase(retry: retry);

  static Future<void> _retryInitializeFirebase({
    Future<void> Function()? retry,
  }) async {
    if (_initializationRetryRunning) return;
    _initializationRetryRunning = true;
    try {
      var delaySec = 30;
      while (!_firebaseReady && _pushSessionActive) {
        debugPrint('🔔 Retrying Firebase init in ${delaySec}s...');
        await Future.delayed(Duration(seconds: delaySec));
        if (_firebaseReady || !_pushSessionActive) return;
        try {
          await (retry ?? initializeFirebase)();
        } catch (_) {}
        delaySec = (delaySec * 2).clamp(30, 600); // макс 10 минут
      }
    } finally {
      _initializationRetryRunning = false;
    }
  }

  /// Повторные попытки получения FCM токена (30с → 60с → макс 300с, бесконечно)
  static Future<void> _retryGetFCMToken() async {
    if (_tokenRetryRunning) return;
    _tokenRetryRunning = true;
    try {
      var delaySec = 30;
      while (!_fcmTokenObtained && _pushSessionActive && _messagingSupported) {
        debugPrint('🔔 Retrying FCM token in ${delaySec}s...');
        await Future.delayed(Duration(seconds: delaySec));
        if (_fcmTokenObtained || !_pushSessionActive || !_messagingSupported) {
          return;
        }
        try {
          final token = await getFCMToken().timeout(
            const Duration(seconds: 10),
          );
          if (token != null) {
            _fcmTokenObtained = true;
            _lastTokenObtainedAt = DateTime.now().toUtc();
            debugPrint('🔔 FCM token obtained on retry');
            onTokenRefreshed?.call(token);
            return;
          }
        } catch (e) {
          // На симуляторе APNS никогда не будет доступен — прекращаем retry
          if (e.toString().contains('apns-token-not-set')) {
            debugPrint(
              '🔔 APNS not available (simulator?) — stopping FCM retry',
            );
            return;
          }
        }
        delaySec = (delaySec * 2).clamp(
          30,
          300,
        ); // макс 5 минут между попытками
      }
    } finally {
      _tokenRetryRunning = false;
    }
  }

  /// Показать локальное уведомление из FCM
  static Future<void> _showFCMNotification(RemoteMessage message) async {
    if (kIsWeb) return;

    final notification = message.notification;
    if (notification == null) return;

    final service = PushNotificationService();
    if (!_isInitialized) {
      await service.initialize();
    }
    if (!_notificationsEnabled) return;

    final item = NotificationItem.fromPushData(
      message.data,
      title: notification.title,
      body: notification.body,
    );
    final channelConfig = service._getChannelConfig(item.type);
    final androidDetails = AndroidNotificationDetails(
      localNotificationChannelId(channelConfig.id, soundEnabled: _soundEnabled),
      channelConfig.name,
      channelDescription: channelConfig.description,
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notification',
      playSound: _soundEnabled,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: _badgeEnabled,
      presentSound: _soundEnabled,
      sound: _soundEnabled ? 'default' : null,
    );

    await service._notifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: NotificationItem.tapPayloadFromPushData(message.data),
    );
  }

  static bool _isMessageForActiveClient(RemoteMessage message) {
    final activeClientId = _activeClientId;
    final data = message.data;
    final recipientType = data['recipientType'] ?? data['recipient_type'];
    final rawRecipientId =
        data['recipientId'] ?? data['recipient_id'] ?? data['clientId'];
    final recipientId = int.tryParse(rawRecipientId?.toString() ?? '');

    if (activeClientId == null) {
      // В разлогиненном состоянии targeted push показывать нельзя. Старые
      // broadcast payload без recipientId тоже не должны всплывать на login.
      return false;
    }

    if (recipientType != null && recipientType.toString() != 'client') {
      return false;
    }

    if (recipientId != null && recipientId != activeClientId) {
      return false;
    }

    return true;
  }

  static void _dispatchOpenedMessage(RemoteMessage message) {
    final handler = onFCMMessageOpened;
    if (handler == null) {
      _pendingOpenedMessages.add(message);
      if (_pendingOpenedMessages.length > 5) {
        _pendingOpenedMessages.removeAt(0);
      }
      debugPrint('🔔 FCM open queued until handler is ready');
      return;
    }

    unawaited(
      Future<void>.sync(() => handler(message)).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        debugPrint('🔔 FCM open handler error: $error');
        debugPrintStack(stackTrace: stackTrace);
      }),
    );
  }

  /// VAPID Key для Web Push (Firebase Console → Project Settings → Cloud Messaging)
  static const String _vapidKey =
      'BN84z0kGwWRFRalLMJ-HlMPVYBp5Tu7QnsGiACoT-ODg7VkwtFV_kdDhFHapsr5BguDgeBs0E6Pe2aY2_0fMshQ';

  /// Inject only the token SDK dependency; tests must clear it in teardown.
  @visibleForTesting
  static void setMessagingForTesting(
    FirebaseMessaging? messaging, {
    bool? isWeb,
    bool? isIOS,
  }) {
    _messaging = messaging;
    _firebaseReady = messaging != null;
    _messagingSupported = true;
    _fcmTokenObtained = false;
    _lastTokenObtainedAt = null;
    _tokenWebOverride = isWeb;
    _tokenIOSOverride = isIOS;
    if (messaging == null) _pushSessionActive = false;
  }

  /// Получить FCM токен, не удерживая регистрацию устройства бесконечно.
  static Future<String?> getFCMToken() async {
    try {
      if (!_messagingSupported) {
        debugPrint('🔔 FCM Token skipped: messaging unsupported');
        return null;
      }

      final messaging = _messaging;
      if (messaging == null) {
        debugPrint('🔔 FCM Token skipped: messaging not initialized');
        return null;
      }

      // Для Web нужен VAPID ключ
      final isWeb = _tokenWebOverride ?? kIsWeb;
      final isIOS = _tokenIOSOverride ?? _isIOS;
      if (isWeb) {
        final settings = await messaging.getNotificationSettings().timeout(
          const Duration(seconds: 3),
        );
        _authorizationStatus = settings.authorizationStatus.name;
        if (settings.authorizationStatus != AuthorizationStatus.authorized) {
          return null;
        }
      } else if (isIOS) {
        final apnsToken = await messaging.getAPNSToken().timeout(
          const Duration(seconds: 3),
        );
        if (apnsToken == null) return null;
      }
      final tokenRequest = isWeb
          ? messaging.getToken(vapidKey: _vapidKey)
          : messaging.getToken();
      final token = await tokenRequest.timeout(const Duration(seconds: 10));

      if (token != null) {
        _fcmTokenObtained = true;
        _lastTokenObtainedAt = DateTime.now().toUtc();
        debugPrint('🔔 FCM token получен');
      } else {
        debugPrint('🔔 FCM Token не получен (null)');
      }

      return token;
    } catch (e) {
      if (_isUnsupportedMessagingError(e)) {
        _messagingSupported = false;
        _messaging = null;
      }
      debugPrint('🔔 Error getting FCM token: $e');
      return null;
    }
  }

  /// Подписаться на топик
  static Future<void> subscribeToTopic(String topic) async {
    // Topic subscription не поддерживается на Web
    if (kIsWeb) {
      debugPrint('🔔 Topic subscription not supported on Web');
      return;
    }
    try {
      await _messaging?.subscribeToTopic(topic);
      debugPrint('🔔 Subscribed to: $topic');
    } catch (e) {
      debugPrint('🔔 Subscribe error: $e');
    }
  }

  /// Отписаться от топика
  static Future<void> unsubscribeFromTopic(String topic) async {
    // Topic unsubscription не поддерживается на Web
    if (kIsWeb) {
      debugPrint('🔔 Topic unsubscription not supported on Web');
      return;
    }
    try {
      final messaging = _messaging;
      if (messaging == null) return;
      await messaging
          .unsubscribeFromTopic(topic)
          .timeout(const Duration(seconds: 3));
      debugPrint('🔔 Unsubscribed from: $topic');
    } on TimeoutException {
      debugPrint('🔔 Unsubscribe timed out for: $topic');
    } catch (e) {
      debugPrint('🔔 Unsubscribe error: $e');
    }
  }

  /// Инициализация локальных уведомлений
  Future<void> initialize({void Function(String? route)? onTap}) async {
    if (kIsWeb) {
      _setNotificationTapHandler(onTap);
      _isInitialized = true;
      return;
    }

    await _loadDevicePreferences();

    if (_isInitialized) {
      _setNotificationTapHandler(onTap);
      return;
    }

    _setNotificationTapHandler(onTap);

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    try {
      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      if (_isAndroid) {
        await _updateNotificationChannels();
      }

      final launchDetails = await _notifications
          .getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        _dispatchLocalNotificationTap(
          launchDetails?.notificationResponse?.payload,
        );
      }
    } catch (e) {
      debugPrint('🔔 Local notifications init skipped: $e');
      return;
    }

    // Request permissions on iOS
    if (_isIOS) {
      await _notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    _isInitialized = true;
  }

  void _onNotificationTapped(NotificationResponse response) {
    final clientId = _activeClientId;
    final target = NotificationItem.tapTargetFromPayload(response.payload);
    if (clientId != null && target.notificationId != null) {
      unawaited(
        _recordPushReceived(
          RemoteMessage(
            data: {
              'notificationId': target.notificationId,
              'recipientId': '$clientId',
            },
          ),
          opened: true,
        ),
      );
    }
    _dispatchLocalNotificationTap(response.payload);
  }

  void _setNotificationTapHandler(void Function(String? route)? onTap) {
    if (onTap != null) {
      onNotificationTap = onTap;
    }
    _drainPendingLocalNotificationTaps();
  }

  void _dispatchLocalNotificationTap(String? payload) {
    final handler = onNotificationTap;
    if (handler == null) {
      _pendingLocalNotificationTapPayloads.add(payload);
      if (_pendingLocalNotificationTapPayloads.length > 5) {
        _pendingLocalNotificationTapPayloads.removeAt(0);
      }
      debugPrint('🔔 Local notification tap queued until handler is ready');
      return;
    }
    handler(payload);
  }

  void _drainPendingLocalNotificationTaps() {
    final handler = onNotificationTap;
    if (handler == null || _pendingLocalNotificationTapPayloads.isEmpty) {
      return;
    }

    final pending = List<String?>.from(_pendingLocalNotificationTapPayloads);
    _pendingLocalNotificationTapPayloads.clear();
    for (final payload in pending) {
      handler(payload);
    }
  }

  /// Получить настройки канала для типа уведомления
  _ChannelConfig _getChannelConfig(NotificationType type) {
    switch (type) {
      case NotificationType.trackStatus:
        return _ChannelConfig(
          id: 'track_status_channel',
          name: 'Статусы треков',
          description: 'Уведомления об изменении статусов трек-номеров',
        );
      case NotificationType.assemblyStatus:
        return _ChannelConfig(
          id: 'assembly_status_channel',
          name: 'Статусы сборок',
          description: 'Уведомления об изменении статусов сборок',
        );
      case NotificationType.photoReportStatus:
        return _ChannelConfig(
          id: 'photo_report_channel',
          name: 'Фотоотчёты',
          description: 'Уведомления о готовности фотоотчётов',
        );
      case NotificationType.questionStatus:
        return _ChannelConfig(
          id: 'question_channel',
          name: 'Ответы на вопросы',
          description: 'Уведомления о получении ответов на вопросы',
        );
      case NotificationType.chatMessage:
        return _ChannelConfig(
          id: 'chat_channel',
          name: 'Чат поддержки',
          description: 'Уведомления о новых сообщениях в чате поддержки',
        );
      case NotificationType.paymentChatMessage:
        return _ChannelConfig(
          id: 'payment_chat_channel',
          name: 'Чат по оплате',
          description: 'Уведомления о новых сообщениях в чате по оплате',
        );
      case NotificationType.news:
        return _ChannelConfig(
          id: 'news_channel',
          name: 'Новости',
          description: 'Уведомления о новых новостях',
        );
      case NotificationType.serviceRules:
        return _ChannelConfig(
          id: 'service_rules_channel',
          name: 'Правила оказания услуг',
          description: 'Уведомления о новых правилах оказания услуг',
        );
      case NotificationType.invoice:
        return _ChannelConfig(
          id: 'invoice_channel',
          name: 'Счета',
          description: 'Уведомления о новых счетах на оплату',
        );
      case NotificationType.paymentStatus:
        return _ChannelConfig(
          id: 'payment_status_channel',
          name: 'Оплата',
          description: 'Уведомления о состоянии и подтверждении оплаты',
        );
      case NotificationType.selfBuyout:
        return _ChannelConfig(
          id: 'self_buyout_channel',
          name: 'Самовыкуп',
          description: 'Уведомления по заявкам самовыкупа',
        );
      case NotificationType.garage:
        return _ChannelConfig(
          id: 'garage_channel',
          name: 'Гараж',
          description: 'Уведомления по заявкам и заказам автозапчастей',
        );
      case NotificationType.broadcast:
        return _ChannelConfig(
          id: 'broadcast_channel',
          name: 'Объявления',
          description: 'Информационные сообщения компании',
        );
    }
  }

  /// Показать push-уведомление на основе NotificationItem
  Future<void> showNotification(NotificationItem item) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_notificationsEnabled) return;

    final channelConfig = _getChannelConfig(item.type);

    final androidDetails = AndroidNotificationDetails(
      localNotificationChannelId(channelConfig.id, soundEnabled: _soundEnabled),
      channelConfig.name,
      channelDescription: channelConfig.description,
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: 'ic_notification',
      color: BrandColors.defaultColors.primary,
      enableVibration: true,
      playSound: _soundEnabled,
      category: _getCategoryForType(item.type),
      styleInformation: BigTextStyleInformation(
        item.message,
        contentTitle: item.title,
        summaryText: item.type.displayName,
      ),
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: _badgeEnabled,
      presentSound: _soundEnabled,
      sound: _soundEnabled ? 'default' : null,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      item.id.hashCode,
      item.title,
      item.message,
      details,
      payload: item.route,
    );
  }

  AndroidNotificationCategory _getCategoryForType(NotificationType type) {
    switch (type) {
      case NotificationType.chatMessage:
      case NotificationType.garage:
        return AndroidNotificationCategory.message;
      case NotificationType.trackStatus:
      case NotificationType.assemblyStatus:
      case NotificationType.paymentStatus:
      case NotificationType.selfBuyout:
        return AndroidNotificationCategory.status;
      case NotificationType.news:
      case NotificationType.broadcast:
        return AndroidNotificationCategory.recommendation;
      default:
        return AndroidNotificationCategory.event;
    }
  }

  /// Показать уведомление о новом сообщении в чате
  Future<void> showChatMessageNotification({
    required String senderName,
    required String message,
    int? notificationId,
  }) async {
    final item = NotificationItem.chatMessage(
      id:
          notificationId?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      senderName: senderName,
      messagePreview: message,
      createdAt: DateTime.now(),
    );
    await showNotification(item);
  }

  /// Показать уведомление о новом сообщении в чате по оплате
  Future<void> showPaymentChatMessageNotification({
    required String senderName,
    required String message,
    int? notificationId,
  }) async {
    final item = NotificationItem.paymentChatMessage(
      id:
          notificationId?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      senderName: senderName,
      messagePreview: message,
      createdAt: DateTime.now(),
    );
    await showNotification(item);
  }

  /// Показать уведомление об изменении статуса трека
  Future<void> showTrackStatusNotification({
    required String trackNumber,
    required String oldStatus,
    required String newStatus,
  }) async {
    final item = NotificationItem.trackStatusChange(
      id: 'track_${DateTime.now().millisecondsSinceEpoch}',
      trackNumber: trackNumber,
      oldStatus: oldStatus,
      newStatus: newStatus,
      createdAt: DateTime.now(),
    );
    await showNotification(item);
  }

  /// Показать уведомление об изменении статуса сборки
  Future<void> showAssemblyStatusNotification({
    required String assemblyId,
    required String oldStatus,
    required String newStatus,
  }) async {
    final item = NotificationItem.assemblyStatusChange(
      id: 'asm_${DateTime.now().millisecondsSinceEpoch}',
      assemblyId: assemblyId,
      oldStatus: oldStatus,
      newStatus: newStatus,
      createdAt: DateTime.now(),
    );
    await showNotification(item);
  }

  /// Показать уведомление о фотоотчёте
  Future<void> showPhotoReportNotification({
    required String trackNumber,
    required String status,
  }) async {
    final item = NotificationItem.photoReportStatusChange(
      id: 'photo_${DateTime.now().millisecondsSinceEpoch}',
      trackNumber: trackNumber,
      status: status,
      createdAt: DateTime.now(),
    );
    await showNotification(item);
  }

  /// Показать уведомление об ответе на вопрос
  Future<void> showQuestionAnsweredNotification({
    required String trackNumber,
    required String answer,
  }) async {
    final item = NotificationItem.questionAnswered(
      id: 'question_${DateTime.now().millisecondsSinceEpoch}',
      trackNumber: trackNumber,
      answer: answer,
      createdAt: DateTime.now(),
    );
    await showNotification(item);
  }

  /// Показать уведомление о новой новости
  Future<void> showNewsNotification({
    required String newsId,
    required String title,
    required String preview,
  }) async {
    final item = NotificationItem.news(
      id: 'news_${DateTime.now().millisecondsSinceEpoch}',
      newsTitle: title,
      newsPreview: preview,
      newsId: newsId,
      createdAt: DateTime.now(),
    );
    await showNotification(item);
  }

  /// Показать уведомление о новом счёте
  Future<void> showInvoiceNotification({
    required String invoiceNumber,
    required String amount,
  }) async {
    final item = NotificationItem.invoice(
      id: 'invoice_${DateTime.now().millisecondsSinceEpoch}',
      invoiceNumber: invoiceNumber,
      amount: amount,
      createdAt: DateTime.now(),
    );
    await showNotification(item);
  }

  /// Обновить badge на иконке приложения
  Future<void> updateBadgeCount(int count) async {
    // Badge не поддерживается на Desktop
    if (_isDesktop) {
      return;
    }

    // Updating the iOS application badge must not remove delivered notifications.
    // Android launchers derive badges from their notification channels.
    if (kIsWeb || !_isIOS) return;
    try {
      await const MethodChannel(
        'com.twoalogistic.user/notification_badge',
      ).invokeMethod<void>('setCount', {
        'count': _badgeEnabled ? count.clamp(0, 1 << 31) : 0,
      });
    } catch (e) {
      debugPrint('Error updating badge: $e');
    }
  }

  /// Очистить badge
  Future<void> clearBadge() async {
    await updateBadgeCount(0);
  }

  /// Отменить все уведомления
  Future<void> cancelAllNotifications() async {
    if (!_isInitialized) return;
    // На Web flutter_local_notifications не работает
    if (kIsWeb) return;
    try {
      await _notifications.cancelAll();
      await clearBadge();
    } catch (e) {
      debugPrint('⚠️ Error canceling notifications: $e');
    }
  }

  /// Отменить конкретное уведомление
  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }
}

class _ChannelConfig {
  final String id;
  final String name;
  final String description;

  const _ChannelConfig({
    required this.id,
    required this.name,
    required this.description,
  });
}
