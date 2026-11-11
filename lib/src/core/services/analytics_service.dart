import 'package:uuid/uuid.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:appmetrica_plugin/appmetrica_plugin.dart';
import 'package:flutter/foundation.dart';
import '../config/appmetrica_config.dart';

import 'workflow_event_contract.dart';
import 'workflow_event_queue.dart';
import '../network/api_client.dart';
import '../network/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
export 'workflow_event_contract.dart';

/// Сервис для работы с Yandex AppMetrica аналитикой
class AnalyticsService {
  AnalyticsService._();

  static bool _initialized = false;
  static WorkflowEventQueue? _browserQueue;
  static Future<WorkflowEventQueue>? _browserQueueLoading;
  static ApiClient? _browserApi;
  static int? _browserClientId, _browserAgentId;
  static int _browserGeneration = 0;
  static final String _anonymousSessionId = const Uuid().v4();
  static String? _anonymousCompany;
  static int _anonymousGeneration = 0;
  static WorkflowEventQueue? _anonymousQueue;
  static Future<WorkflowEventQueue>? _anonymousQueueLoading;

  static void setAnonymousCompanyDomain(String? domain) {
    if (!kIsWeb) return;
    final candidate = domain?.trim().toLowerCase();
    final valid =
        candidate != null &&
            candidate.length <= 253 &&
            RegExp(
              r'^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$',
            ).hasMatch(candidate)
        ? candidate
        : null;
    if (valid == _anonymousCompany) return;
    _anonymousGeneration++;
    _anonymousCompany = valid;
    _anonymousQueue?.sessionChanged();
  }

  static Future<WorkflowEventQueue> _ensureAnonymousQueue() {
    final existing = _anonymousQueue;
    if (existing != null) return Future.value(existing);
    return _anonymousQueueLoading ??= (() async {
      final preferences = await SharedPreferences.getInstance();
      final queue = WorkflowEventQueue(
        preferences: preferences,
        persistEvents: false,
        readIdentity: () async => WorkflowTransportIdentity.anonymous(
          sessionId: _anonymousSessionId,
          companyDomain: _anonymousCompany,
        ),
        endpoint:
            '${ApiConfig.baseUrl.replaceFirst(RegExp(r'/$'), '')}/public/workflow-events',
      );
      _anonymousQueue = queue;
      return queue;
    })().whenComplete(() => _anonymousQueueLoading = null);
  }

  static void setBrowserSession(
    ApiClient api, {
    required int clientId,
    required int agentId,
  }) {
    if (!kIsWeb || !AppMetricaSettings.enabled) return;
    if (clientId <= 0 || agentId <= 0) {
      clearBrowserSession();
      return;
    }
    if (identical(_browserApi, api) &&
        _browserClientId == clientId &&
        _browserAgentId == agentId) {
      return;
    }
    _browserGeneration++;
    _browserApi = api;
    _browserClientId = clientId;
    _browserAgentId = agentId;
    _browserQueue?.sessionChanged();
    unawaited(
      _ensureBrowserQueue()
          .then((queue) => queue.flush())
          .catchError((Object _) {}),
    );
  }

  static void clearBrowserSession() {
    if (!kIsWeb) return;
    _browserGeneration++;
    _browserApi = null;
    _browserClientId = null;
    _browserAgentId = null;
    _browserQueue?.sessionChanged();
  }

  static Future<WorkflowTransportIdentity?> _browserIdentity() async {
    final api = _browserApi,
        clientId = _browserClientId,
        agentId = _browserAgentId,
        generation = _browserGeneration;
    if (api == null || clientId == null || agentId == null) return null;
    final token = await api.getToken();
    if (generation != _browserGeneration || token == null || token.isEmpty) {
      return null;
    }
    return WorkflowTransportIdentity(
      token: token,
      clientId: clientId,
      agentId: agentId,
    );
  }

  static Future<WorkflowEventQueue> _ensureBrowserQueue() {
    final existing = _browserQueue;
    if (existing != null) return Future.value(existing);
    return _browserQueueLoading ??= (() async {
      final preferences = await SharedPreferences.getInstance();
      final queue = WorkflowEventQueue(
        preferences: preferences,
        readIdentity: _browserIdentity,
        endpoint:
            '${ApiConfig.baseUrl.replaceFirst(RegExp(r'/$'), '')}/client/workflow-events',
      );
      _browserQueue = queue;
      return queue;
    })().whenComplete(() => _browserQueueLoading = null);
  }

  @visibleForTesting
  static Future<void> Function(String, Map<String, Object>)?
  funnelReporterOverride;

  static void trackFunnel(
    WorkflowAction action,
    WorkflowStage stage, {
    WorkflowFailure? reason,
  }) => _emitFunnel(
    action,
    stage,
    reason: reason,
    browserGeneration: _browserGeneration,
    anonymousGeneration: _anonymousGeneration,
    anonymous:
        kIsWeb &&
        _browserApi == null &&
        const {WorkflowAction.login}.contains(action),
  );

  static void _emitFunnel(
    WorkflowAction action,
    WorkflowStage stage, {
    WorkflowFailure? reason,
    required int browserGeneration,
    int? anonymousGeneration,
    bool anonymous = false,
  }) {
    final fields = <String, Object>{
      'action': action.name,
      'stage': stage.name,
      if (reason != null) 'reason': reason.name,
    };
    unawaited(() async {
      try {
        final reporter = funnelReporterOverride;
        if (reporter != null) {
          await reporter('workflow_step', fields);
        } else if (kIsWeb) {
          // User requested registration and recovery to stay as they work.
          // Their existing native hooks remain; no new web delivery for these flows.
          if (action == WorkflowAction.registration ||
              action == WorkflowAction.passwordRecovery) {
            return;
          }
          if (!AppMetricaSettings.enabled) return;
          if (anonymous) {
            if (anonymousGeneration != _anonymousGeneration) return;
            final queue = await _ensureAnonymousQueue();
            if (anonymousGeneration != _anonymousGeneration) return;
            await queue.enqueue(fields);
          } else {
            if (_browserApi == null ||
                browserGeneration != _browserGeneration) {
              return;
            }
            final queue = await _ensureBrowserQueue();
            if (browserGeneration != _browserGeneration) return;
            await queue.enqueue(fields);
          }
        } else {
          await logEvent('workflow_step', fields);
        }
      } catch (_) {
        /* Optional telemetry never changes a business outcome. */
      }
    }());
  }

  static WorkflowFailure _workflowFailure(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == null) return WorkflowFailure.network;
      if (status == 401 || status == 403) return WorkflowFailure.unauthorized;
      if (status == 400 || status == 422) return WorkflowFailure.invalidInput;
      if (status == 409) return WorkflowFailure.conflict;
      if (status >= 500) return WorkflowFailure.server;
    }
    return WorkflowFailure.unknown;
  }

  static Future<T> traceOperation<T>(
    WorkflowAction action,
    Future<T> Function() operation, {
    WorkflowStage Function(T value)? outcome,
  }) async {
    final browserGeneration = _browserGeneration;
    final anonymousGeneration = _anonymousGeneration;
    final anonymous =
        kIsWeb &&
        _browserApi == null &&
        const {WorkflowAction.login}.contains(action);
    _emitFunnel(
      action,
      WorkflowStage.started,
      browserGeneration: browserGeneration,
      anonymousGeneration: anonymousGeneration,
      anonymous: anonymous,
    );
    try {
      final result = await operation();
      WorkflowStage stage;
      try {
        stage = outcome?.call(result) ?? WorkflowStage.succeeded;
      } catch (_) {
        // A broken telemetry classifier must not change a successful request.
        return result;
      }
      _emitFunnel(
        action,
        stage,
        browserGeneration: browserGeneration,
        anonymousGeneration: anonymousGeneration,
        anonymous: anonymous,
        reason: stage == WorkflowStage.failed
            ? WorkflowFailure.unsuccessfulResult
            : null,
      );
      return result;
    } catch (error) {
      _emitFunnel(
        action,
        WorkflowStage.failed,
        reason: _workflowFailure(error),
        browserGeneration: browserGeneration,
        anonymousGeneration: anonymousGeneration,
        anonymous: anonymous,
      );
      rethrow;
    }
  }

  /// Инициализация AppMetrica SDK
  static Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb) return; // AppMetrica не поддерживает Web

    if (!AppMetricaSettings.enabled) {
      if (kDebugMode) {
        debugPrint('📊 AppMetrica: Аналитика отключена');
      }
      return;
    }

    try {
      // Конфигурация AppMetrica
      await AppMetrica.activate(
        AppMetricaConfig(
          AppMetricaSettings.apiKey,
          logs: AppMetricaSettings.logsEnabled,
          locationTracking: AppMetricaSettings.locationTracking,
          crashReporting: AppMetricaSettings.crashReporting,
          sessionTimeout: 10, // 10 секунд неактивности = новая сессия
          dataSendingEnabled: true,
        ),
      );

      _initialized = true;

      if (kDebugMode) {
        debugPrint('📊 AppMetrica: Инициализация успешна');
        debugPrint('📊 AppMetrica: App ID - ${AppMetricaSettings.appId}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('📊 AppMetrica: Ошибка инициализации - $e');
      }
    }
  }

  /// Отправить событие
  static Future<void> logEvent(
    String eventName, [
    Map<String, dynamic>? parameters,
  ]) async {
    if (!_initialized || !AppMetricaSettings.enabled) return;

    try {
      if (parameters != null && parameters.isNotEmpty) {
        await AppMetrica.reportEventWithMap(
          eventName,
          parameters.cast<String, Object>(),
        );
      } else {
        await AppMetrica.reportEvent(eventName);
      }

      if (kDebugMode) {
        debugPrint(
          '📊 AppMetrica: Событие "$eventName"${parameters != null ? ' с параметрами: $parameters' : ''}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('📊 AppMetrica: Ошибка отправки события "$eventName" - $e');
      }
    }
  }

  /// Установить ID пользователя
  static Future<void> setUserId(String userId) async {
    if (!_initialized || !AppMetricaSettings.enabled) return;

    try {
      await AppMetrica.setUserProfileID(userId);

      if (kDebugMode) {
        debugPrint('📊 AppMetrica: User ID установлен - $userId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('📊 AppMetrica: Ошибка установки User ID - $e');
      }
    }
  }

  /// Установить атрибут пользователя
  static Future<void> setUserAttribute(String key, String value) async {
    if (!_initialized || !AppMetricaSettings.enabled) return;

    try {
      final attribute = AppMetricaStringAttribute.withValueReset(key);
      final userProfile = AppMetricaUserProfile([attribute]);
      await AppMetrica.reportUserProfile(userProfile);

      if (kDebugMode) {
        debugPrint('📊 AppMetrica: Атрибут пользователя "$key" = "$value"');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('📊 AppMetrica: Ошибка установки атрибута "$key" - $e');
      }
    }
  }

  /// Отправить информацию об ошибке
  static Future<void> reportError(
    String message, {
    dynamic error,
    StackTrace? stackTrace,
  }) async {
    if (!_initialized || !AppMetricaSettings.enabled) return;

    try {
      // Отправляем как событие, так как API reportError может отличаться в разных версиях
      await logEvent('app_error', {
        'error_message': message,
        'error_type': error?.runtimeType.toString() ?? 'Unknown',
        'has_stacktrace': stackTrace != null,
      });

      if (kDebugMode) {
        debugPrint('📊 AppMetrica: Ошибка зарегистрирована - $message');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('📊 AppMetrica: Ошибка отправки error report - $e');
      }
    }
  }

  /// Начать новую сессию
  static Future<void> resumeSession() async {
    if (!_initialized || !AppMetricaSettings.enabled) return;

    try {
      await AppMetrica.resumeSession();

      if (kDebugMode) {
        debugPrint('📊 AppMetrica: Сессия возобновлена');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('📊 AppMetrica: Ошибка возобновления сессии - $e');
      }
    }
  }

  /// Приостановить сессию
  static Future<void> pauseSession() async {
    if (!_initialized || !AppMetricaSettings.enabled) return;

    try {
      await AppMetrica.pauseSession();

      if (kDebugMode) {
        debugPrint('📊 AppMetrica: Сессия приостановлена');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('📊 AppMetrica: Ошибка приостановки сессии - $e');
      }
    }
  }

  // === Готовые методы для типовых событий ===

  /// Событие: Пользователь вошел в систему
  static Future<void> logLogin(String method) async {
    await logEvent('login', {'method': method});
  }

  /// Событие: Пользователь вышел из системы
  static Future<void> logLogout() async {
    await logEvent('logout');
  }

  /// Событие: Просмотр экрана
  static Future<void> logScreenView(String screenName) async {
    await logEvent('screen_view', {'screen_name': screenName});
  }

  /// Событие: Клик по элементу
  static Future<void> logButtonClick(
    String buttonName, {
    String? screen,
  }) async {
    await logEvent('button_click', {
      'button_name': buttonName,
      if (screen != null) 'screen': screen,
    });
  }

  /// Событие: Поиск треков
  static Future<void> logTrackSearch(String query, int resultsCount) async {
    await logEvent('track_search', {
      'query': query,
      'results_count': resultsCount,
    });
  }

  /// Событие: Создание сборки
  static Future<void> logAssemblyCreated(int trackCount) async {
    await logEvent('assembly_created', {'track_count': trackCount});
  }

  /// Событие: Запрос фотоотчета
  static Future<void> logPhotoReportRequest() async {
    await logEvent('photo_report_request');
  }

  /// Событие: Задан вопрос
  static Future<void> logQuestionAsked() async {
    await logEvent('question_asked');
  }

  /// Событие: Открытие чата
  static Future<void> logChatOpened(String chatType) async {
    await logEvent('chat_opened', {'chat_type': chatType});
  }

  /// Событие: Отправка сообщения
  static Future<void> logMessageSent(String chatType) async {
    await logEvent('message_sent', {'chat_type': chatType});
  }

  /// Событие: Просмотр новости
  static Future<void> logNewsViewed(String newsId, String newsTitle) async {
    await logEvent('news_viewed', {'news_id': newsId, 'news_title': newsTitle});
  }

  /// Событие: Выбор способа доставки
  static Future<void> logDeliveryMethodSelected(String method) async {
    await logEvent('delivery_method_selected', {'method': method});
  }

  /// Событие: Выбор тарифа
  static Future<void> logTariffSelected(String tariffName) async {
    await logEvent('tariff_selected', {'tariff_name': tariffName});
  }
}
