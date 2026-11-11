import '../../../core/services/analytics_service.dart';
import '../../home/data/home_counts_provider.dart';
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/cache/stale_data_cache.dart';
import '../../../core/logging/client_log_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/chat_presence_service.dart';
import '../../../core/services/platform_helper.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/services/runtime/app_runtime_info.dart';
import '../../../core/services/showcase_service.dart';
import '../../../core/utils/error_utils.dart';
import '../../assemblies/data/assemblies_provider.dart';
import '../../clients/application/client_codes_controller.dart';
import '../../invoices/data/invoices_provider.dart';
import '../../news/data/news_provider.dart';
import '../../notifications/application/notifications_controller.dart';
import '../../payment_chat/data/payment_chat_provider.dart';
import '../../photos/data/photos_provider.dart';
import '../../profile/data/profile_provider.dart';
import '../../rules/data/rules_provider.dart';
import '../../sp_finance/data/sp_provider.dart';
import '../../sp_finance/data/sp_v2_provider.dart';
import '../../support/data/chat_provider.dart';
import '../../tracks/data/assemblies_provider.dart' as tracks_assemblies;
import '../../tracks/data/tracks_provider.dart';

const _kIsLoggedInKey = 'is_logged_in';
const _kUserEmailKey = 'user_email';
const _kUserDomainKey = 'user_domain';
const _kTokenKey = 'auth_token';
const _kClientIdKey = 'client_id';
const _kClientNameKey = 'client_name';
const _kClientDataKey = 'client_data';

@visibleForTesting
Duration pushRegistrationRetryDelay(int attempt) {
  const delays = [15, 30, 60, 120, 300];
  final index = attempt.clamp(0, delays.length - 1);
  return Duration(seconds: delays[index]);
}

final logoutDeviceCleanupTimeoutProvider = Provider<Duration>(
  (_) => const Duration(seconds: 3),
);

class LoginVerificationChallenge {
  final String login;
  final String domain;
  final String message;
  final String? maskedPhone;
  final DateTime? lockedUntil;
  final int? remainingSeconds;
  final int? attemptsLimit;

  const LoginVerificationChallenge({
    required this.login,
    required this.domain,
    required this.message,
    this.maskedPhone,
    this.lockedUntil,
    this.remainingSeconds,
    this.attemptsLimit,
  });
}

class LoginVerificationRequestInfo {
  final String checkId;
  final String callPhone;
  final String callPhonePretty;
  final String? maskedPhone;
  final DateTime? expiresAt;

  const LoginVerificationRequestInfo({
    required this.checkId,
    required this.callPhone,
    required this.callPhonePretty,
    this.maskedPhone,
    this.expiresAt,
  });
}

class LoginVerificationStatus {
  final bool confirmed;
  final bool expired;
  final bool loggedIn;

  const LoginVerificationStatus({
    required this.confirmed,
    required this.expired,
    required this.loggedIn,
  });
}

class AuthState {
  final bool isLoggedIn;
  final String? userEmail;
  final String? userDomain;
  final bool isLoading;
  final String? error;
  final int? clientId;
  final String? clientName;
  final Map<String, dynamic>? clientData;
  final LoginVerificationChallenge? loginVerificationChallenge;

  const AuthState({
    this.isLoggedIn = false,
    this.userEmail,
    this.userDomain,
    this.isLoading = true,
    this.error,
    this.clientId,
    this.clientName,
    this.clientData,
    this.loginVerificationChallenge,
  });

  AuthState copyWith({
    bool? isLoggedIn,
    String? userEmail,
    String? userDomain,
    bool? isLoading,
    String? error,
    bool clearError = false,
    int? clientId,
    String? clientName,
    Map<String, dynamic>? clientData,
    LoginVerificationChallenge? loginVerificationChallenge,
    bool clearLoginVerificationChallenge = false,
  }) {
    return AuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      userEmail: userEmail ?? this.userEmail,
      userDomain: userDomain ?? this.userDomain,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      clientId: clientId ?? this.clientId,
      clientName: clientName ?? this.clientName,
      clientData: clientData ?? this.clientData,
      loginVerificationChallenge: clearLoginVerificationChallenge
          ? null
          : (loginVerificationChallenge ?? this.loginVerificationChallenge),
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  late ApiClient _apiClient;
  // Флаг: начальная загрузка завершена или login/logout уже взяли управление.
  // Предотвращает race condition когда _loadAuthState() завершается ПОСЛЕ того,
  // как пользователь уже нажал "Войти" и login() изменил state.
  bool _initialLoadDone = false;
  Timer? _pushRegistrationRetryTimer;
  int _pushRegistrationRetryAttempt = 0;
  bool _pushRegistrationInFlight = false;
  String? _pendingRefreshedPushToken;
  int _pushSessionGeneration = 0;
  bool _pushReceiptFlushInFlight = false;
  Timer? _pushReceiptRetryTimer;

  @override
  AuthState build() {
    _apiClient = ref.read(apiClientProvider);
    _initialLoadDone = false;

    // Подписываемся на обновление FCM токена — перерегистрируем на бэкенде.
    // Без этого при обновлении токена Firebase старый становится невалидным и пуши пропадают.
    PushNotificationService.onTokenRefreshed = (newToken) {
      if (state.isLoggedIn) {
        unawaited(_registerForPush(state.userDomain ?? '', token: newToken));
      }
    };
    PushNotificationService.onReceiptQueued = () =>
        unawaited(_flushPushReceipts());
    ref.onDispose(() {
      _pushSessionGeneration++;
      _pushRegistrationRetryTimer?.cancel();
      _pushReceiptRetryTimer?.cancel();
      PushNotificationService.onTokenRefreshed = null;
      PushNotificationService.onReceiptQueued = null;
    });

    _loadAuthState();
    return const AuthState();
  }

  Future<void> _loadAuthState() async {
    debugPrint('🔄 Loading auth state...');

    // Гарантируем что auth state загрузится за 10 секунд максимум
    // Если что-то зависает (SecureStorage, SharedPrefs) — не блокируем UI навсегда
    Timer? timeoutTimer;
    try {
      final timeout = Completer<void>();
      timeoutTimer = Timer(const Duration(seconds: 10), () {
        if (!timeout.isCompleted) {
          timeout.completeError(
            TimeoutException('Auth state loading timed out after 10s'),
          );
        }
      });
      ref.onDispose(() => timeoutTimer?.cancel());
      await Future.any([_doLoadAuthState(), timeout.future]);
    } catch (e) {
      debugPrint('❌ _loadAuthState timeout/error: $e');
      if (ref.mounted && !_initialLoadDone) {
        _initialLoadDone = true;
        state = const AuthState(isLoggedIn: false, isLoading: false);
        PushNotificationService.clearActiveClient();
        AnalyticsService.clearBrowserSession();
      }
    } finally {
      timeoutTimer?.cancel();
    }
  }

  Future<void> _doLoadAuthState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!ref.mounted) return;
      final isLoggedIn = prefs.getBool(_kIsLoggedInKey) ?? false;
      final userEmail = prefs.getString(_kUserEmailKey);
      final userDomain = prefs.getString(_kUserDomainKey);
      final clientId = prefs.getInt(_kClientIdKey);
      final clientName = prefs.getString(_kClientNameKey);

      debugPrint('🔍 isLoggedIn from SharedPreferences: $isLoggedIn');
      debugPrint('🔍 cached user identity: ${userEmail != null}');

      // Проверяем есть ли токен в ApiClient (он сам знает откуда читать: localStorage на web, SecureStorage на мобильных)
      if (isLoggedIn) {
        final hasToken = await _apiClient.hasTokenAsync();
        if (!ref.mounted) return;
        debugPrint('🔍 hasToken from ApiClient: $hasToken');

        if (!hasToken) {
          // Токен не найден — возможны два случая:
          // 1. Транзиентная ошибка iOS Keychain (до первой разблокировки после перезагрузки,
          //    после обновления приложения/iOS) — токен физически есть, просто не читается.
          // 2. Токен реально удалён.
          //
          // В обоих случаях НЕ вызываем logout() — это необратимо очищает SharedPreferences
          // и убивает авторизацию навсегда. Вместо этого просто показываем экран входа.
          // При следующем запуске попробуем снова — если Keychain восстановился, войдём
          // автоматически; если нет — пользователь введёт пароль и получит новый токен.
          debugPrint(
            '🔐 Token not found — showing login screen (not forcing logout)',
          );
          if (ref.mounted && !_initialLoadDone) {
            _initialLoadDone = true;
            state = const AuthState(isLoggedIn: false, isLoading: false);
            PushNotificationService.clearActiveClient();
            AnalyticsService.clearBrowserSession();
          }
          return;
        }
      }

      // Восстанавливаем данные клиента
      Map<String, dynamic>? clientData;
      final clientDataJson = prefs.getString(_kClientDataKey);
      if (clientDataJson != null) {
        try {
          clientData = jsonDecode(clientDataJson) as Map<String, dynamic>;
        } catch (e) {
          debugPrint('Error parsing client data: $e');
        }
      }

      // Проверяем, что login() не успел взять управление пока мы читали хранилище.
      // Если _initialLoadDone уже true — login() или logout() уже обновили state, не перезаписываем.
      if (_initialLoadDone) {
        debugPrint(
          '⚠️ _loadAuthState: skipping state update — login/logout already took over',
        );
        return;
      }
      _initialLoadDone = true;

      state = AuthState(
        isLoggedIn: isLoggedIn,
        userEmail: userEmail,
        userDomain: userDomain,
        isLoading: false,
        clientId: clientId,
        clientName: clientName,
        clientData: clientData,
      );
      if (isLoggedIn) {
        PushNotificationService.setActiveClient(clientId);
        _setLogUserContextFromData(clientId: clientId, clientData: clientData);
      } else {
        PushNotificationService.clearActiveClient();
        AnalyticsService.clearBrowserSession();
        ClientLogService.instance.clearUserContext();
      }

      debugPrint(
        '✅ Auth state loaded: isLoggedIn=$isLoggedIn, email=$userEmail',
      );

      // Обновляем clientData из /auth/me в фоне, чтобы коды клиента содержали актуальные id.
      // Это важно для корректной передачи clientCodeId при создании сборок.
      if (isLoggedIn) {
        _refreshClientDataInBackground();
        if (userDomain != null && userDomain.isNotEmpty) {
          unawaited(_registerForPush(userDomain));
        }
      }
    } catch (e, stackTrace) {
      // Если что-то пошло не так при загрузке состояния — не зависаем на сплэше,
      // просто показываем экран входа.
      debugPrint('❌ Error loading auth state: $e\n$stackTrace');
      if (ref.mounted && !_initialLoadDone) {
        _initialLoadDone = true;
        state = const AuthState(isLoggedIn: false, isLoading: false);
        PushNotificationService.clearActiveClient();
        AnalyticsService.clearBrowserSession();
      }
    }
  }

  /// Обновляет clientData из /auth/me в фоне.
  /// Критично для того, чтобы codes содержали актуальный id (нужен для clientCodeId в сборках).
  Future<void> _refreshClientDataInBackground() async {
    try {
      final response = await _apiClient.get('/auth/me');
      if (response.statusCode == 200 && response.data != null) {
        final userData = response.data as Map<String, dynamic>;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kClientDataKey, jsonEncode(userData));
        unawaited(cacheClientProfileData(userData));
        state = state.copyWith(clientData: userData);
        _setLogUserContextFromData(
          clientId: state.clientId,
          clientData: userData,
        );
        debugPrint('✅ clientData refreshed from /auth/me');
      }
    } catch (e) {
      debugPrint('⚠️ Could not refresh clientData from /auth/me: $e');
    }
  }

  Future<bool> login({
    required String email,
    required String domain,
    required String password,
    Future<void> Function(Map<String, dynamic> userData)? beforeComplete,
  }) async {
    return AnalyticsService.traceOperation(
      WorkflowAction.login,
      () async {
        _initialLoadDone =
            true; // Предотвращаем перезапись state от _loadAuthState()
        state = state.copyWith(
          isLoading: true,
          clearError: true,
          clearLoginVerificationChallenge: true,
        );

        try {
          final response = await _apiClient.post(
            '/login',
            data: {
              'email': email,
              'password': password,
              'type': 'client', // Важно! Для клиентов type = 'client'
              // PU-C1: передаём domain, чтобы backend нашёл агента и не
              // подхватил клиента с тем же email из другого тенанта.
              'domain': domain,
            },
          );

          if (response.statusCode == 200 && response.data != null) {
            final data = response.data as Map<String, dynamic>;
            final token = data['token'] as String?;
            final userData = data['user'] as Map<String, dynamic>?;

            if (token == null || userData == null) {
              state = state.copyWith(
                isLoading: false,
                error: 'Некорректный ответ сервера',
              );
              return false;
            }

            // Сохраняем токен в ApiClient (он сам выберет где хранить: localStorage на web, SecureStorage на мобильных)
            await _apiClient.setToken(token);

            // Извлекаем данные клиента
            final clientId =
                userData['id'] as int? ?? userData['clientId'] as int?;
            await _prepareClientIdentity(clientId);
            final clientName =
                userData['fullName'] as String? ??
                userData['name'] as String? ??
                email;
            final agentData = userData['agent'] as Map<String, dynamic>?;
            final clientDomain = agentData?['domain'] as String? ?? domain;

            // Сохраняем в SharedPreferences (без токена - он в secure storage)
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool(_kIsLoggedInKey, true);
            await prefs.setString(_kUserEmailKey, email);
            await prefs.setString(_kUserDomainKey, clientDomain);
            if (clientId != null) {
              await prefs.setInt(_kClientIdKey, clientId);
            }
            await prefs.setString(_kClientNameKey, clientName);
            await prefs.setString(_kClientDataKey, jsonEncode(userData));
            unawaited(cacheClientProfileData(userData));

            if (beforeComplete != null) {
              try {
                await beforeComplete(userData);
              } catch (e) {
                debugPrint('⚠️ Password login beforeComplete hook failed: $e');
              }
            }

            // Сбрасываем только обучение, не принятие правил.
            final showcaseService = ref.read(showcaseServiceProvider);
            await showcaseService.resetTutorials();

            // Обновляем состояние ПЕРЕД invalidate чтобы избежать циклических зависимостей
            state = AuthState(
              isLoggedIn: true,
              userEmail: email,
              userDomain: clientDomain,
              isLoading: false,
              clientId: clientId,
              clientName: clientName,
              clientData: userData,
            );
            PushNotificationService.setActiveClient(clientId);
            _setLogUserContextFromData(
              clientId: clientId,
              clientData: userData,
            );

            // Invalidate все провайдеры данных чтобы новый пользователь не видел данные предыдущего
            Future.microtask(() {
              _invalidateAllProviders();
              for (final page in ShowcasePage.values) {
                ref.invalidate(showcaseProvider(page));
              }
              for (final block in ShowcaseBlock.values) {
                ref.invalidate(showcaseBlockProvider(block));
              }
            });

            // Регистрируем устройство для push-уведомлений
            unawaited(_registerForPush(clientDomain));

            return true;
          } else {
            state = state.copyWith(
              isLoading: false,
              error: 'Неверный email или пароль',
            );
            return false;
          }
        } on DioException catch (e) {
          String errorMessage;

          final responseData = e.response?.data;
          final responseMap = responseData is Map<String, dynamic>
              ? responseData
              : responseData is Map
              ? Map<String, dynamic>.from(responseData)
              : null;
          final responseCode = responseMap?['code'] as String?;

          // Специфичные ошибки авторизации
          if (e.response?.statusCode == 423 &&
              responseCode == 'LOGIN_VERIFICATION_REQUIRED') {
            errorMessage =
                responseMap?['error'] as String? ??
                'Слишком много неверных попыток. Подтвердите вход звонком.';
            state = state.copyWith(
              isLoading: false,
              error: errorMessage,
              loginVerificationChallenge: LoginVerificationChallenge(
                login: email,
                domain: domain,
                message: errorMessage,
                maskedPhone: responseMap?['maskedPhone'] as String?,
                lockedUntil: DateTime.tryParse(
                  responseMap?['lockedUntil'] as String? ?? '',
                ),
                remainingSeconds: responseMap?['remainingSeconds'] is int
                    ? responseMap!['remainingSeconds'] as int
                    : null,
                attemptsLimit: responseMap?['attemptsLimit'] is int
                    ? responseMap!['attemptsLimit'] as int
                    : null,
              ),
            );
            return false;
          } else if (e.response?.statusCode == 401 ||
              e.response?.statusCode == 403) {
            errorMessage = 'Неверный email или пароль';
          } else if (e.response?.statusCode == 404) {
            errorMessage = 'Пользователь не найден. Проверьте данные для входа';
          } else {
            // Используем ErrorUtils для остальных ошибок
            final errorInfo = ErrorUtils.getErrorInfo(e);
            errorMessage = errorInfo.message;
          }

          debugPrint('Login error: $e');
          debugPrint('Error message shown to user: $errorMessage');

          state = state.copyWith(
            isLoading: false,
            error: errorMessage,
            clearLoginVerificationChallenge: true,
          );
          return false;
        } catch (e, stackTrace) {
          debugPrint('Login error: $e');

          await ClientLogService.instance.captureNonFatal(
            'Неожиданная ошибка входа',
            error: e,
            stackTrace: stackTrace,
            data: {'domain': domain},
          );

          state = state.copyWith(
            isLoading: false,
            error: 'Произошла ошибка: $e',
          );
          return false;
        }
      },
      outcome: (result) =>
          result ? WorkflowStage.succeeded : WorkflowStage.failed,
    );
  }

  Future<LoginVerificationRequestInfo> requestLoginVerification({
    required String login,
    required String domain,
  }) async {
    final response = await _apiClient.post(
      '/login/verification/request',
      data: {'login': login, 'domain': domain},
    );
    final data = response.data as Map<String, dynamic>;
    final checkId = data['checkId'] as String?;
    final callPhone = data['callPhone'] as String?;
    if (checkId == null || callPhone == null) {
      throw StateError('Некорректный ответ проверки входа');
    }
    return LoginVerificationRequestInfo(
      checkId: checkId,
      callPhone: callPhone,
      callPhonePretty: data['callPhonePretty'] as String? ?? callPhone,
      maskedPhone: data['maskedPhone'] as String?,
      expiresAt: DateTime.tryParse(data['expiresAt'] as String? ?? ''),
    );
  }

  Future<LoginVerificationStatus> verifyLoginVerification({
    required String checkId,
  }) async {
    final response = await _apiClient.post(
      '/login/verification/verify',
      data: {'checkId': checkId},
    );
    final data = response.data as Map<String, dynamic>;
    final confirmed = data['confirmed'] == true;
    final expired = data['expired'] == true;
    var loggedIn = false;

    if (confirmed) {
      final token = data['token'] as String?;
      final userData = data['user'] as Map<String, dynamic>?;
      if (token != null && userData != null) {
        loggedIn = await loginWithData(token: token, userData: userData);
      }
    }

    return LoginVerificationStatus(
      confirmed: confirmed,
      expired: expired,
      loggedIn: loggedIn,
    );
  }

  /// Авторизация по данным от password-reset (после подтверждения по звонку)
  Future<bool> loginWithData({
    required String token,
    required Map<String, dynamic> userData,
  }) async {
    _initialLoadDone =
        true; // Предотвращаем перезапись state от _loadAuthState()
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Сохраняем токен в ApiClient (он сам выберет где хранить: localStorage на web, SecureStorage на мобильных)
      await _apiClient.setToken(token);

      // Извлекаем данные клиента
      final clientId = userData['id'] as int? ?? userData['clientId'] as int?;
      await _prepareClientIdentity(clientId);
      final email = userData['email'] as String? ?? '';
      final clientName =
          userData['fullName'] as String? ??
          userData['name'] as String? ??
          email;
      final agentData = userData['agent'] as Map<String, dynamic>?;
      final clientDomain = agentData?['domain'] as String? ?? '';

      // Сохраняем в SharedPreferences (без токена - он в secure storage)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kIsLoggedInKey, true);
      await prefs.setString(_kUserEmailKey, email);
      await prefs.setString(_kUserDomainKey, clientDomain);
      if (clientId != null) {
        await prefs.setInt(_kClientIdKey, clientId);
      }
      await prefs.setString(_kClientNameKey, clientName);
      await prefs.setString(_kClientDataKey, jsonEncode(userData));
      unawaited(cacheClientProfileData(userData));

      // Сбрасываем только обучение, не принятие правил.
      final showcaseService = ref.read(showcaseServiceProvider);
      await showcaseService.resetTutorials();

      // Обновляем state ПЕРЕД invalidate — чтобы при перестройке провайдеры
      // видели уже нового пользователя (новый clientId/clientCode)
      state = AuthState(
        isLoggedIn: true,
        userEmail: email,
        userDomain: clientDomain,
        isLoading: false,
        clientId: clientId,
        clientName: clientName,
        clientData: userData,
      );
      PushNotificationService.setActiveClient(clientId);
      _setLogUserContextFromData(clientId: clientId, clientData: userData);

      // Invalidate все провайдеры данных чтобы новый пользователь не видел данные предыдущего
      Future.microtask(() {
        _invalidateAllProviders();
        for (final page in ShowcasePage.values) {
          ref.invalidate(showcaseProvider(page));
        }
        for (final block in ShowcaseBlock.values) {
          ref.invalidate(showcaseBlockProvider(block));
        }
      });

      // Регистрируем устройство для push-уведомлений
      if (clientDomain.isNotEmpty) {
        unawaited(_registerForPush(clientDomain));
      }

      return true;
    } catch (e) {
      debugPrint('LoginWithData error: $e');
      state = state.copyWith(isLoading: false, error: 'Ошибка авторизации: $e');
      return false;
    }
  }

  /// Повторно проверяет FCM и актуализирует устройство на backend. Вызывается
  /// после входа, восстановления сессии, token refresh и возврата приложения.
  Future<void> refreshPushRegistration() async {
    final domain = state.userDomain;
    if (!state.isLoggedIn || domain == null || domain.isEmpty) return;
    await _registerForPush(domain);
    await _flushPushReceipts();
  }

  Future<void> _prepareClientIdentity(int? nextClientId) async {
    _pushSessionGeneration++;
    _pushRegistrationInFlight = false;
    _pendingRefreshedPushToken = null;
    _pushRegistrationRetryTimer?.cancel();
    _pushRegistrationRetryTimer = null;
    if (state.clientId != nextClientId) {
      await StaleDataCache.clearAll();
      await clearCachedClientProfile();
    }
  }

  Future<void> _flushPushReceipts({int retryAttempt = 0}) async {
    if (_pushReceiptFlushInFlight || !state.isLoggedIn || _isLoggingOut) return;
    _pushReceiptFlushInFlight = true;
    final generation = _pushSessionGeneration;
    final clientId = state.clientId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // background isolate may have queued receipts
      final deviceId = prefs.getString('device_id');
      if (deviceId == null || clientId == null) return;
      final keys = prefs
          .getKeys()
          .where((key) => key.startsWith('push_receipt_'))
          .toList();
      var sent = 0;
      for (final key in keys) {
        if (generation != _pushSessionGeneration ||
            _isLoggingOut ||
            !state.isLoggedIn) {
          return;
        }
        final raw = prefs.getString(key);
        if (raw == null) continue;
        try {
          final item = jsonDecode(raw) as Map<String, dynamic>;
          final queuedAt = DateTime.tryParse(
            item['queuedAt']?.toString() ?? '',
          );
          if (queuedAt == null ||
              DateTime.now().difference(queuedAt).inDays >= 7) {
            await prefs.remove(key);
            continue;
          }
          if (item['recipientId'] != clientId || sent >= 50) continue;
          await _apiClient
              .post(
                '/client/push-receipts',
                data: {
                  'deviceId': deviceId,
                  'notificationId': item['notificationId'],
                  'event': item['event'],
                },
              )
              .timeout(const Duration(seconds: 5));
          await prefs.remove(key);
          sent++;
        } catch (error) {
          if (error is DioException &&
              error.response?.statusCode == 404 &&
              retryAttempt < 2 &&
              _pushReceiptRetryTimer?.isActive != true) {
            _pushReceiptRetryTimer = Timer(
              Duration(seconds: 2 << retryAttempt),
              () {
                _pushReceiptRetryTimer = null;
                if (generation == _pushSessionGeneration) {
                  unawaited(_flushPushReceipts(retryAttempt: retryAttempt + 1));
                }
              },
            );
          }
          // Older servers may not have this optional endpoint. Keep the
          // receipt until next resume rather than blocking auth or retrying hot.
          return;
        }
      }
    } catch (_) {
      // Diagnostics must never change login or notification handling.
    } finally {
      _pushReceiptFlushInFlight = false;
    }
  }

  /// Регистрация устройства для push-уведомлений с автоматическим retry.
  Future<void> _registerForPush(String domain, {String? token}) async {
    if (!state.isLoggedIn || _isLoggingOut) return;
    if (_pushRegistrationInFlight) {
      if (token != null && token.isNotEmpty) {
        _pendingRefreshedPushToken = token;
      }
      return;
    }

    _pushRegistrationInFlight = true;
    final generation = _pushSessionGeneration;
    final clientId = state.clientId;
    bool sessionIsCurrent() =>
        generation == _pushSessionGeneration &&
        !_isLoggingOut &&
        state.isLoggedIn &&
        state.clientId == clientId;
    PushNotificationService.recordDeviceRegistrationAttempt();
    try {
      await PushNotificationService.initializeFirebase().timeout(
        const Duration(seconds: 40),
      );
      if (!sessionIsCurrent()) return;
      final fcmToken = token ?? await PushNotificationService.getFCMToken();
      if (!sessionIsCurrent()) return;
      if (fcmToken == null || fcmToken.isEmpty) {
        throw StateError('FCM token is not available');
      }

      final runtime = await AppRuntimeInfo.instance.snapshot().timeout(
        const Duration(seconds: 5),
      );
      final deviceId = await _getDeviceId().timeout(const Duration(seconds: 2));
      Map<String, dynamic>? pushDiagnostics;
      try {
        pushDiagnostics = await PushNotificationService.diagnosticSnapshot()
            .timeout(const Duration(seconds: 4));
      } catch (_) {}
      if (!sessionIsCurrent()) return;
      final response = await _apiClient
          .post(
            '/devices',
            data: {
              'platform': getPlatformNameImpl(),
              'token': fcmToken,
              'deviceId': deviceId,
              'deviceName': runtime.device,
              'deviceModel': runtime.device,
              'osVersion': runtime.osVersion,
              'appVersion': runtime.appVersion,
              'locale': PlatformDispatcher.instance.locale.languageCode,
              if (pushDiagnostics != null) 'pushDiagnostics': pushDiagnostics,
            },
          )
          .timeout(const Duration(seconds: 20));
      if (!sessionIsCurrent()) return;
      final device = response.data;
      if (device is Map<String, dynamic>) {
        await PushNotificationService.applyDevicePreferences(
          notificationsEnabled: device['notificationsEnabled'] as bool?,
          soundEnabled: device['soundEnabled'] as bool?,
          badgeEnabled: device['badgeEnabled'] as bool?,
        ).timeout(const Duration(seconds: 3));
      }
      if (!sessionIsCurrent()) return;

      _pushRegistrationRetryTimer?.cancel();
      _pushRegistrationRetryTimer = null;
      _pushRegistrationRetryAttempt = 0;
      await PushNotificationService.recordDeviceRegistrationSuccess().timeout(
        const Duration(seconds: 3),
      );
      ClientLogService.instance.add(
        type: 'push_device_registered',
        level: 'info',
        message: 'Устройство зарегистрировано для push-уведомлений',
        data: {
          'platform': getPlatformNameImpl(),
          'appVersion': runtime.appVersion,
        },
      );
      debugPrint('🔔 Device registered successfully');
      unawaited(_flushPushReceipts());

      // Клиентские push отправляются точечно по DeviceToken. Общие topic'и
      // оставляем только как legacy cleanup, чтобы после смены аккаунта
      // телефон не получал широкие рассылки старых подписок.
      await PushNotificationService.unsubscribeFromTopic('clients');
      await PushNotificationService.unsubscribeFromTopic('domain_$domain');
    } catch (e) {
      if (!sessionIsCurrent()) return;
      final errorMessage = ErrorUtils.getErrorInfo(e).message;
      await PushNotificationService.recordDeviceRegistrationFailure(
        errorMessage,
      ).timeout(const Duration(seconds: 3)).catchError((_) {});
      ClientLogService.instance.add(
        type: 'push_device_registration_failed',
        level: 'warning',
        message: 'Не удалось зарегистрировать устройство для push',
        data: {
          'attempt': _pushRegistrationRetryAttempt + 1,
          'error': errorMessage,
        },
      );
      debugPrint('🔔 Error registering for push: $e');
      _schedulePushRegistrationRetry();
    } finally {
      if (generation == _pushSessionGeneration) {
        _pushRegistrationInFlight = false;
        final pendingToken = _pendingRefreshedPushToken;
        _pendingRefreshedPushToken = null;
        if (pendingToken != null && sessionIsCurrent()) {
          unawaited(
            _registerForPush(state.userDomain ?? domain, token: pendingToken),
          );
        }
      }
    }
  }

  void _schedulePushRegistrationRetry() {
    if (!state.isLoggedIn || _pushRegistrationRetryTimer?.isActive == true) {
      return;
    }
    final delay = pushRegistrationRetryDelay(_pushRegistrationRetryAttempt);
    _pushRegistrationRetryAttempt++;
    _pushRegistrationRetryTimer = Timer(delay, () {
      _pushRegistrationRetryTimer = null;
      unawaited(refreshPushRegistration());
    });
  }

  /// Получить уникальный ID устройства
  Future<String?> _getDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? deviceId = prefs.getString('device_id');
      if (deviceId == null) {
        // Генерируем уникальный ID
        deviceId =
            'device_${DateTime.now().millisecondsSinceEpoch}_${UniqueKey().hashCode}';
        await prefs.setString('device_id', deviceId);
      }
      return deviceId;
    } catch (e) {
      return null;
    }
  }

  bool _isLoggingOut = false;

  Future<void> logout() async {
    // Another browser tab owns shared storage now. Forget this tab's identity
    // without deleting that tab's token, preferences or push installation.
    if (_apiClient.takeExternalSessionChange()) {
      _pushSessionGeneration++;
      _pushReceiptRetryTimer?.cancel();
      _pushRegistrationRetryTimer?.cancel();
      _initialLoadDone = true;
      ref.read(chatPresenceServiceProvider).stopForLogout();
      PushNotificationService.clearActiveClient();
      AnalyticsService.clearBrowserSession();
      ClientLogService.instance.clearUserContext();
      state = const AuthState(isLoggedIn: false, isLoading: false);
      _invalidateAllProviders();
      return;
    }
    if (_isLoggingOut) {
      debugPrint('🚪 Logout already in progress, skipping');
      return;
    }
    _isLoggingOut = true;
    _apiClient.prepareForLogout();
    _pushSessionGeneration++;
    _pushReceiptRetryTimer?.cancel();
    try {
      debugPrint('🚪 Starting logout process...');
      _pushRegistrationRetryTimer?.cancel();
      _pushRegistrationRetryTimer = null;
      _pushRegistrationRetryAttempt = 0;
      _pendingRefreshedPushToken = null;
      PushNotificationService.clearActiveClient();
      AnalyticsService.clearBrowserSession();
      // Revoke the installation address even when the authenticated DELETE
      // cannot reach our backend. Run in parallel so logout remains bounded.
      final revokePushToken = PushNotificationService.revokeTokenForLogout();
      ref.read(chatPresenceServiceProvider).stopForLogout();

      // Отписываемся от push-уведомлений
      try {
        await _unregisterFromPush();
        debugPrint('✅ Push device cleanup completed or safely deferred');
      } catch (e) {
        debugPrint('⚠️ Error unregistering from push: $e');
        // Продолжаем logout даже если отписка от push не удалась
      }
      await revokePushToken;

      // Очищаем токен в ApiClient (он сам очистит и localStorage на web, и SecureStorage на мобильных)
      try {
        await _apiClient.clearToken();
        debugPrint('✅ Token cleared from ApiClient');
      } catch (e) {
        debugPrint('⚠️ Error clearing token: $e');
      }

      // Очищаем SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_kIsLoggedInKey);
        await prefs.remove(_kUserEmailKey);
        final lastCompany =
            state.userDomain ?? prefs.getString(_kUserDomainKey);
        if (lastCompany != null && lastCompany.trim().isNotEmpty) {
          await prefs.setString('last_company_domain', lastCompany);
        }
        await prefs.remove(_kUserDomainKey);
        await prefs.remove(_kTokenKey); // legacy cleanup
        await prefs.remove(_kClientIdKey);
        await prefs.remove(_kClientNameKey);
        await prefs.remove(_kClientDataKey);
        await StaleDataCache.clearAll();
        await clearCachedClientProfile();
        debugPrint('✅ SharedPreferences cleared');

        // Verify it was actually removed
        final stillLoggedIn = prefs.getBool(_kIsLoggedInKey);
        debugPrint(
          '🔍 After logout, isLoggedIn key = $stillLoggedIn (should be null)',
        );
      } catch (e) {
        debugPrint('⚠️ Error clearing SharedPreferences: $e');
      }

      // Clear notification badge (not supported on Desktop)
      if (!kIsWeb && !isDesktopImpl()) {
        try {
          // Очищаем все уведомления и badge
          final flutterLocalNotificationsPlugin =
              FlutterLocalNotificationsPlugin();
          await flutterLocalNotificationsPlugin.cancelAll();
          debugPrint('✅ Notifications cleared');
        } catch (e) {
          debugPrint('⚠️ Error clearing notifications: $e');
        }
      }

      // Очищаем SharedPreferences ключи clientCodesController вручную,
      // чтобы PIN-коды одного пользователя не утекли к следующему
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('active_client_code');
        await prefs.remove('client_codes_list');
      } catch (e) {
        debugPrint('⚠️ Error clearing client codes from prefs: $e');
      }

      // Сначала обновляем state — при перестройке провайдеры увидят isLoggedIn: false
      state = const AuthState(isLoggedIn: false, isLoading: false);
      PushNotificationService.clearActiveClient();
      AnalyticsService.clearBrowserSession();
      ClientLogService.instance.clearUserContext();

      // Затем инвалидируем все провайдеры
      _invalidateAllProviders();

      debugPrint('✅ Logout completed successfully');
    } catch (e, stackTrace) {
      debugPrint('❌ Critical error during logout: $e');
      debugPrint('Stack trace: $stackTrace');

      // Всё равно устанавливаем состояние "разлогинен" даже если была ошибка
      state = const AuthState(isLoggedIn: false, isLoading: false);
      PushNotificationService.clearActiveClient();
      AnalyticsService.clearBrowserSession();
      ClientLogService.instance.clearUserContext();

      // Invalidate providers even on error
      _invalidateAllProviders();
    } finally {
      _isLoggingOut = false;
    }
  }

  void _setLogUserContextFromData({
    required int? clientId,
    required Map<String, dynamic>? clientData,
  }) {
    final agent = clientData?['agent'];
    final agentId = clientData?['agentId'] is int
        ? clientData!['agentId'] as int
        : agent is Map<String, dynamic>
        ? agent['id'] as int?
        : null;
    final codes = clientData?['codes'];
    String? clientCode;
    if (codes is List && codes.isNotEmpty) {
      final first = codes.first;
      if (first is Map<String, dynamic>) {
        clientCode = first['code'] as String?;
      }
    }

    final resolvedClientId = clientId ?? clientData?['id'] as int?;
    if (resolvedClientId != null &&
        resolvedClientId > 0 &&
        agentId != null &&
        agentId > 0) {
      AnalyticsService.setBrowserSession(
        _apiClient,
        clientId: resolvedClientId,
        agentId: agentId,
      );
    } else {
      AnalyticsService.clearBrowserSession();
    }
    ClientLogService.instance.setUserContext(
      userId: resolvedClientId,
      clientCode: clientCode,
      agentId: agentId,
    );
  }

  /// Инвалидация всех провайдеров данных при logout
  void _invalidateAllProviders() {
    debugPrint('🗑️ Invalidating all data providers...');

    // Каждый invalidate в отдельном try-catch: если один провайдер недоступен,
    // остальные всё равно будут инвалидированы (иначе при смене аккаунта могут
    // остаться старые данные).
    void inv(dynamic provider) {
      try {
        ref.invalidate(provider);
      } catch (_) {}
    }

    // Profile & Stats
    inv(clientProfileProvider);
    inv(clientStatsProvider);

    // Client codes
    inv(clientCodesControllerProvider);

    // Tracks (all family instances)
    inv(paginatedTracksProvider);
    inv(tracksListProvider);
    inv(tracksDigestProvider);
    inv(tracksSimpleListProvider);
    inv(tracksCountProvider);
    inv(homeTracksCountProvider);
    inv(tracksWithoutAssemblyCountProvider);
    inv(trackStatusesProvider);

    // Assemblies (tracks module)
    inv(tracks_assemblies.assembliesListProvider);
    inv(tracks_assemblies.assembliesDigestProvider);
    inv(tracks_assemblies.assembliesCountProvider);
    inv(tracks_assemblies.tariffsProvider);

    // Assemblies (assemblies module)
    inv(assembliesCountProvider);
    inv(homeAssembliesCountProvider);

    // Invoices
    inv(invoicesListProvider);
    inv(invoiceDirectoryProvider);
    inv(invoiceDirectoryPageProvider);
    inv(invoicesDigestProvider);
    inv(invoicesCountProvider);
    inv(invoiceStatusesProvider);

    // Photos
    inv(photosTotalCountProvider);
    inv(photosRecentProvider);
    inv(photosDaysProvider);
    inv(photosByDateProvider);
    inv(paginatedPhotosProvider);
    inv(paginatedPhotosByDateProvider);
    inv(filteredPhotosProvider);
    inv(photosSearchProvider);

    // Notifications
    inv(notificationsControllerProvider);
    inv(notificationsHistoryInfoProvider);
    inv(unreadCountProvider);

    // SP Finance
    inv(spAssembliesControllerProvider);
    inv(spV2PurchasesControllerProvider);
    inv(spV2CustomersProvider);

    // Tenant-scoped content and chats
    inv(chatControllerProvider);
    inv(paymentChatControllerProvider);
    inv(newsListProvider);
    inv(newsItemProvider);
    inv(rulesListProvider);
    inv(ruleItemProvider);

    debugPrint('✅ All providers invalidated');
  }

  /// Отписка от push-уведомлений
  Future<void> _unregisterFromPush() async {
    final domain = state.userDomain;

    try {
      // Device ID хранится локально и не зависит от Firebase/APNS.
      // Поэтому logout не должен ждать getToken(), который на некоторых
      // устройствах может зависнуть на минуты.
      if (_apiClient.hasToken) {
        final deviceId = await _getDeviceId().timeout(
          const Duration(seconds: 1),
          onTimeout: () => null,
        );
        if (deviceId != null) {
          try {
            await _apiClient
                .delete('/devices', data: {'deviceId': deviceId})
                .timeout(ref.read(logoutDeviceCleanupTimeoutProvider));
            debugPrint('🔔 Device deactivated successfully');
          } on TimeoutException {
            debugPrint('🔔 Device deactivation timed out; continuing logout');
          } catch (e) {
            debugPrint('🔔 Error deactivating device: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('🔔 Error deactivating device during logout: $e');
    }

    // Топики больше не участвуют в адресации клиентских push. Их
    // legacy-cleanup не должен блокировать очистку локальной сессии.
    unawaited(_unsubscribeFromLegacyPushTopics(domain));
  }

  Future<void> _unsubscribeFromLegacyPushTopics(String? domain) async {
    await PushNotificationService.unsubscribeFromTopic('clients');
    if (domain != null) {
      await PushNotificationService.unsubscribeFromTopic('domain_$domain');
    }
    debugPrint('🔔 Legacy push topics unsubscribed');
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

// Helper provider to check if user is logged in (non-loading)
final isLoggedInProvider = Provider<bool>((ref) {
  final auth = ref.watch(authProvider);
  return auth.isLoggedIn;
});

// Helper provider to check if auth is still loading
final isAuthLoadingProvider = Provider<bool>((ref) {
  final auth = ref.watch(authProvider);
  return auth.isLoading;
});
