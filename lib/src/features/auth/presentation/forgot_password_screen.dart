import '../../../core/services/analytics_service.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_toast.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phone_form_field/phone_form_field.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../core/services/agent_domain_resolver.dart';
import '../../../core/ui/app_background.dart';
import '../../../core/ui/phone_input_field.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/utils/locale_text.dart';
import '../data/auth_provider.dart';
import '../data/partner_link_provider.dart';
import '../data/auth_input_safety.dart';
import 'auth_visuals.dart';
import 'auth_verification_help.dart';

/// Этапы восстановления пароля
enum ResetStep {
  enterPhone, // Ввод номера телефона
  waitingCall, // Ожидание звонка
  enterPassword, // Ввод нового пароля
  success, // Успешно
}

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen>
    with WidgetsBindingObserver {
  late final PhoneController _phoneCtrl;
  final _domainCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  String? _phoneError;
  String? _domainError;

  ResetStep _currentStep = ResetStep.enterPhone;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  // Данные для звонка
  String? _checkId;
  String? _callPhone;
  String? _callPhonePretty;
  DateTime? _expiresAt;
  String? _resetToken;
  bool _checkingCall = false;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  int _secondsLeft = 300; // 5 минут

  @override
  void initState() {
    super.initState();
    AnalyticsService.trackFunnel(
      WorkflowAction.passwordRecovery,
      WorkflowStage.viewed,
    );
    WidgetsBinding.instance.addObserver(this);
    AppToast.hide();
    _phoneCtrl = PhoneController(
      initialValue: const PhoneNumber(isoCode: IsoCode.RU, nsn: ''),
    );
    final detectedDomain = ref.read(partnerLinkProvider).hasPendingToken
        ? partnerLinkAgentDomain
        : AgentDomainResolver.currentAgentDomain;
    if (detectedDomain != null) {
      _domainCtrl.text = detectedDomain;
    } else {
      unawaited(_restoreLastCompany());
    }
  }

  Future<void> _restoreLastCompany() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || _domainCtrl.text.isNotEmpty) return;
    _domainCtrl.text = prefs.getString('last_company_domain') ?? '';
  }

  void _cancelTimers() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _phoneCtrl.dispose();
    _domainCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _cancelTimers();
    super.dispose();
  }

  String? _validatePhone() {
    if (_phoneCtrl.value.nsn.trim().isEmpty) {
      return 'Введите номер телефона';
    }
    return PhoneInputField.internationalValue(_phoneCtrl.value) == null
        ? 'Введите корректный номер телефона'
        : null;
  }

  /// Валидация домена компании
  String? _validateDomain() {
    final domain = _effectiveDomain;

    if (domain.isEmpty) {
      return 'Введите домен компании';
    }

    return null;
  }

  String get _effectiveDomain => ref.read(partnerLinkProvider).hasPendingToken
      ? partnerLinkAgentDomain
      : _domainCtrl.text.trim();

  String _getPhoneForApi() {
    return PhoneInputField.internationalValue(_phoneCtrl.value)!;
  }

  /// Шаг 1: Запросить восстановление
  Future<void> _requestReset() async {
    final phoneError = _validatePhone();
    final domainError = _validateDomain();

    if (phoneError != null || domainError != null) {
      setState(() {
        _phoneError = phoneError;
        _domainError = domainError;
      });
      return;
    }

    setState(() {
      _phoneError = null;
      _domainError = null;
      _isLoading = true;
    });

    final phone = _getPhoneForApi();
    final domain = _effectiveDomain;

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.post(
        '/password-reset/request',
        data: {'phone': phone, 'domain': domain},
      );

      if (!mounted) return;

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        setState(() {
          _checkId = data['checkId'];
          _callPhone = data['callPhone'];
          _callPhonePretty = data['callPhonePretty'];
          _expiresAt =
              DateTime.tryParse(data['expiresAt'] ?? '') ??
              DateTime.now().add(const Duration(minutes: 5));
          _currentStep = ResetStep.waitingCall;
          _secondsLeft = verificationSecondsLeft(
            _expiresAt ?? DateTime.now().add(const Duration(minutes: 5)),
          );
          _isLoading = false;
        });

        // Запускаем polling для проверки звонка
        _startPolling();
        _startCountdown();
      } else {
        final error = _extractResponseError(response.data) ?? 'Ошибка запроса';
        _showError(error);
        setState(() => _isLoading = false);
      }
    } on DioException catch (e) {
      if (!mounted) return;
      _showError(
        _passwordResetErrorMessage(e, fallback: 'Не удалось отправить запрос'),
      );
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      _showError('Не удалось отправить запрос');
      setState(() => _isLoading = false);
    }
  }

  /// Polling для проверки статуса звонка
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkCallStatus();
    });
  }

  /// Обратный отсчёт
  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshDeadline(),
    );
  }

  void _refreshDeadline() {
    if (!mounted || _currentStep != ResetStep.waitingCall) return;
    final seconds = verificationSecondsLeft(_expiresAt ?? DateTime.now());
    if (seconds == 0) {
      _cancelTimers();
      _showError(
        tr(
          context,
          ru: 'Время истекло. Запросите новый звонок.',
          zh: '验证已过期，请重新请求通话。',
        ),
      );
      setState(() => _currentStep = ResetStep.enterPhone);
    } else {
      setState(() => _secondsLeft = seconds);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _refreshDeadline();
    if (_currentStep == ResetStep.waitingCall) unawaited(_checkCallStatus());
  }

  /// Проверить статус звонка
  Future<void> _checkCallStatus() async {
    final checkId = _checkId;
    if (checkId == null || _checkingCall) return;
    _checkingCall = true;
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.post(
        '/password-reset/verify',
        data: {'checkId': checkId},
      );

      if (!mounted || _checkId != checkId) return;

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;

        if (data['confirmed'] == true) {
          _cancelTimers();
          _resetToken = data['resetToken'];
          HapticFeedback.heavyImpact();
          setState(() => _currentStep = ResetStep.enterPassword);
        } else if (data['expired'] == true) {
          _cancelTimers();
          _showError('Время истекло. Попробуйте снова.');
          setState(() => _currentStep = ResetStep.enterPhone);
        }
      }
    } catch (e) {
      // Temporary polling errors do not discard the recovery form.
    } finally {
      _checkingCall = false;
    }
  }

  /// Шаг 3: Установить новый пароль
  Future<void> _setNewPassword() async {
    final password = _passwordCtrl.text;
    final confirm = _confirmPasswordCtrl.text;

    if (password.length < 6) {
      _showError('Пароль должен быть не менее 6 символов');
      return;
    }

    if (password != confirm) {
      _showError('Пароли не совпадают');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await AnalyticsService.traceOperation(
        WorkflowAction.passwordRecovery,
        () => apiClient.post(
          '/password-reset/complete',
          data: {'resetToken': _resetToken, 'newPassword': password},
        ),
        outcome: (response) =>
            response.statusCode == 200 && response.data is Map
            ? WorkflowStage.succeeded
            : WorkflowStage.failed,
      );

      if (!mounted) return;

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final token = data['token'] as String?;
        final userData = data['user'] as Map<String, dynamic>?;

        HapticFeedback.heavyImpact();

        // Если есть токен - авторизуем пользователя
        if (token != null && userData != null) {
          final success = await ref
              .read(authProvider.notifier)
              .loginWithData(token: token, userData: userData);

          if (!mounted) return;

          if (success) {
            // Перенаправляем в приложение
            // The auth router restores the original destination.
            return;
          }
        }

        // Если авторизация не удалась - показываем экран успеха
        setState(() {
          _currentStep = ResetStep.success;
          _isLoading = false;
        });
      } else {
        final error = _extractResponseError(response.data) ?? 'Ошибка';
        _showError(error);
        setState(() => _isLoading = false);
      }
    } on DioException catch (e) {
      if (!mounted) return;
      _showError(
        _passwordResetErrorMessage(e, fallback: 'Не удалось установить пароль'),
      );
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      _showError('Не удалось установить пароль');
      setState(() => _isLoading = false);
    }
  }

  /// Позвонить на номер
  Future<void> _makeCall() async {
    if (_callPhone == null) return;

    final uri = Uri.parse('tel:$_callPhone');
    if (await canLaunchUrl(uri)) {
      if (!mounted) return;
      await launchUrl(uri);
    }
  }

  String? _extractResponseError(Object? data) {
    if (data is Map) {
      final error = data['error'] ?? data['message'];
      if (error is String && error.trim().isNotEmpty) {
        return error.trim();
      }
    }
    return null;
  }

  String _passwordResetErrorMessage(
    DioException error, {
    required String fallback,
  }) {
    final serverError = _extractResponseError(error.response?.data);
    if (serverError != null) return serverError;

    if (error.response?.statusCode == 404) {
      return 'Номер телефона не зарегистрирован у этого партнёра';
    }

    final userMessage = ErrorUtils.getErrorInfo(error).message;
    return userMessage.isNotEmpty ? userMessage : fallback;
  }

  void _showError(String message) {
    AppToast.showFromSnackBar(
      context,
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    final partnerLinkActive = ref.watch(
      partnerLinkProvider.select((value) => value.hasPendingToken),
    );
    if (partnerLinkActive && _domainCtrl.text != partnerLinkAgentDomain) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _domainCtrl.text == partnerLinkAgentDomain) return;
        _domainCtrl.text = partnerLinkAgentDomain;
      });
    }
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final topPadding = MediaQuery.paddingOf(context).top;

    return AutofillGroup(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            const AppBackground(),
            GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  24,
                  topPadding + 28,
                  24,
                  bottomPadding + 24,
                ),
                child: AuthResponsiveContent(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: GestureDetector(
                          onTap: () {
                            if (_currentStep == ResetStep.enterPhone ||
                                _currentStep == ResetStep.success) {
                              context.pop();
                            } else {
                              _cancelTimers();
                              setState(
                                () => _currentStep = ResetStep.enterPhone,
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.82),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.78),
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x0A000000),
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.arrow_back_ios_rounded,
                                  size: 16,
                                  color: Color(0xFF666666),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Назад',
                                  style: TextStyle(
                                    color: Color(0xFF666666),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      AuthHeroHeader(
                        icon: _getHeroIcon(),
                        title: _getTitle(),
                        subtitle: _getSubtitle(),
                        trustItems: _getTrustItems(),
                      ),
                      const SizedBox(height: 28),

                      AuthFormCard(
                        child: Column(
                          children: [
                            _buildContent(partnerLinkActive: partnerLinkActive),
                            if (_currentStep != ResetStep.success)
                              AuthVerificationHelp(company: _effectiveDomain),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getHeroIcon() {
    switch (_currentStep) {
      case ResetStep.enterPhone:
        return Icons.lock_reset_rounded;
      case ResetStep.waitingCall:
        return Icons.phone_callback_rounded;
      case ResetStep.enterPassword:
        return Icons.key_rounded;
      case ResetStep.success:
        return Icons.check_circle_rounded;
    }
  }

  List<AuthTrustItem> _getTrustItems() {
    switch (_currentStep) {
      case ResetStep.enterPhone:
        return const [
          AuthTrustItem(icon: Icons.call_rounded, label: 'Без SMS'),
          AuthTrustItem(icon: Icons.timer_rounded, label: '5 минут'),
          AuthTrustItem(icon: Icons.verified_rounded, label: 'Безопасно'),
        ];
      case ResetStep.waitingCall:
        return const [
          AuthTrustItem(
            icon: Icons.phone_callback_rounded,
            label: 'Звонок бесплатный',
          ),
          AuthTrustItem(
            icon: Icons.sync_rounded,
            label: 'Проверка автоматически',
          ),
        ];
      case ResetStep.enterPassword:
        return const [
          AuthTrustItem(icon: Icons.key_rounded, label: 'Новый пароль'),
          AuthTrustItem(icon: Icons.lock_rounded, label: 'Защищённый вход'),
        ];
      case ResetStep.success:
        return const [
          AuthTrustItem(icon: Icons.check_circle_rounded, label: 'Готово'),
          AuthTrustItem(icon: Icons.login_rounded, label: 'Можно войти'),
        ];
    }
  }

  String _getTitle() {
    switch (_currentStep) {
      case ResetStep.enterPhone:
        return tr(context, ru: 'Восстановление доступа', zh: '恢复账户访问');
      case ResetStep.waitingCall:
        return 'Подтвердите номер';
      case ResetStep.enterPassword:
        return 'Новый пароль';
      case ResetStep.success:
        return 'Вход выполнен!';
    }
  }

  String _getSubtitle() {
    switch (_currentStep) {
      case ResetStep.enterPhone:
        return 'Введите номер телефона, привязанный к вашему аккаунту';
      case ResetStep.waitingCall:
        return 'Позвоните на указанный номер для подтверждения';
      case ResetStep.enterPassword:
        return 'Установите новый пароль для входа';
      case ResetStep.success:
        return 'Вы успешно авторизовались';
    }
  }

  Widget _buildContent({required bool partnerLinkActive}) {
    switch (_currentStep) {
      case ResetStep.enterPhone:
        return _buildPhoneStep(partnerLinkActive: partnerLinkActive);
      case ResetStep.waitingCall:
        return _buildCallStep();
      case ResetStep.enterPassword:
        return _buildPasswordStep();
      case ResetStep.success:
        return _buildSuccessStep();
    }
  }

  Widget _buildPhoneStep({required bool partnerLinkActive}) {
    final hasPhoneError = _phoneError != null;
    final hasDomainError = _domainError != null;
    final accent = AuthVisuals.primary(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (partnerLinkActive)
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.18)),
            ),
            child: const Row(
              children: [
                Icon(Icons.business_rounded, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Восстановление аккаунта партнёра',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          )
        else ...[
          const Text(
            'Домен компании',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF333333),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: hasDomainError
                    ? Colors.red.shade400
                    : const Color(0xFFE0E0E0),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _domainCtrl,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_domainError != null) {
                  setState(() => _domainError = null);
                }
              },
              decoration: InputDecoration(
                hintText: 'example-company',
                hintStyle: const TextStyle(
                  color: Color(0xFFAAAAAA),
                  fontSize: 14,
                ),
                prefixIcon: Icon(
                  Icons.business_rounded,
                  color: hasDomainError ? Colors.red.shade400 : accent,
                  size: 20,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ],
        if (hasDomainError) ...[
          const SizedBox(height: 8),
          Text(
            _domainError!,
            style: TextStyle(fontSize: 12, color: Colors.red.shade600),
          ),
        ],
        const SizedBox(height: 16),

        // Поле номера телефона
        const Text(
          'Номер телефона',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF333333),
          ),
        ),
        const SizedBox(height: 8),
        PhoneInputField(
          controller: _phoneCtrl,
          hintText: 'Номер телефона',
          textInputAction: TextInputAction.done,
          onChanged: (_) {
            if (_phoneError != null) {
              setState(() => _phoneError = null);
            }
          },
        ),
        if (hasPhoneError) ...[
          const SizedBox(height: 8),
          Text(
            _phoneError!,
            style: TextStyle(fontSize: 12, color: Colors.red.shade600),
          ),
        ],
        const SizedBox(height: 20),
        // Информация о процессе
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.help_outline, color: Color(0xFF666666), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Как это работает?',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF333333),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildStep('1', 'Введите номер телефона'),
              const SizedBox(height: 8),
              _buildStep('2', 'Позвоните на указанный номер (бесплатно)'),
              const SizedBox(height: 8),
              _buildStep('3', 'Установите новый пароль'),
              const SizedBox(height: 8),
              _buildStep('4', 'Войдите в приложение'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      color: Colors.amber,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'После подтверждения номера вы зададите новый пароль для входа',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF666666),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _isLoading ? null : _requestReset,
          style: AuthVisuals.primaryButtonStyle(context),
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Продолжить',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
        ),
      ],
    );
  }

  Widget _buildCallStep() {
    final minutes = _secondsLeft ~/ 60;
    final seconds = _secondsLeft % 60;
    final accent = AuthVisuals.primary(context);

    return Column(
      children: [
        // Номер для звонка
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              const Text(
                'Позвоните на номер:',
                style: TextStyle(fontSize: 14, color: Color(0xFF666666)),
              ),
              const SizedBox(height: 8),
              Text(
                _callPhonePretty ?? _callPhone ?? '',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: accent,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _makeCall,
                  style: AuthVisuals.outlinedButtonStyle(context),
                  icon: const Icon(Icons.phone),
                  label: const Text('Позвонить'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Обратный отсчёт
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.timer_outlined,
                size: 20,
                color: Color(0xFF666666),
              ),
              const SizedBox(width: 8),
              Text(
                'Осталось: ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF333333),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Анимация ожидания
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text(
              'Ожидаем ваш звонок...',
              style: TextStyle(fontSize: 14, color: Color(0xFF666666)),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Важное предупреждение
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.red.shade600,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Звоните с номера ${_formatPhoneDisplay()}\nИначе звонок не будет засчитан',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Инструкция
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.amber, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Звонок бесплатный. После соединения можете сразу положить трубку.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF666666)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Форматирование номера для отображения
  String _formatPhoneDisplay() {
    return _phoneCtrl.value.international;
  }

  Widget _buildPasswordStep() {
    final accent = AuthVisuals.primary(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Новый пароль
        const Text(
          'Новый пароль',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF333333),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE0E0E0)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: _passwordCtrl,
            autofillHints: const [AutofillHints.newPassword],
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              hintText: 'Минимум 6 символов',
              hintStyle: const TextStyle(
                color: Color(0xFFAAAAAA),
                fontSize: 14,
              ),
              prefixIcon: Icon(Icons.lock_rounded, color: accent, size: 20),
              suffixIcon: IconButton(
                tooltip: tr(
                  context,
                  ru: _obscurePassword ? 'Показать пароль' : 'Скрыть пароль',
                  zh: _obscurePassword ? '显示密码' : '隐藏密码',
                ),
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: const Color(0xFF999999),
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Подтверждение пароля
        const Text(
          'Подтвердите пароль',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF333333),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE0E0E0)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: _confirmPasswordCtrl,
            autofillHints: const [AutofillHints.newPassword],
            obscureText: _obscureConfirm,
            decoration: InputDecoration(
              hintText: 'Повторите пароль',
              hintStyle: const TextStyle(
                color: Color(0xFFAAAAAA),
                fontSize: 14,
              ),
              prefixIcon: Icon(Icons.lock_rounded, color: accent, size: 20),
              suffixIcon: IconButton(
                tooltip: tr(
                  context,
                  ru: _obscureConfirm ? 'Показать пароль' : 'Скрыть пароль',
                  zh: _obscureConfirm ? '显示密码' : '隐藏密码',
                ),
                icon: Icon(
                  _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                  color: const Color(0xFF999999),
                ),
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        FilledButton(
          onPressed: _isLoading ? null : _setNewPassword,
          style: AuthVisuals.primaryButtonStyle(context),
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Установить пароль',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
        ),
      ],
    );
  }

  Widget _buildSuccessStep() {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_rounded,
            size: 32,
            color: Colors.green.shade600,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Готово!',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Теперь вы можете войти в приложение\nс установленным паролем',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Color(0xFF666666), height: 1.4),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Вы можете изменить пароль на постоянный в разделе «Профиль» → «Настройки»',
                  style: TextStyle(fontSize: 12, color: Color(0xFF666666)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => context.go('/login'),
          style: AuthVisuals.primaryButtonStyle(context),
          child: const Text(
            'Войти',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildStep(String number, String text) {
    final accent = AuthVisuals.primary(context);

    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: Color(0xFF555555)),
          ),
        ),
      ],
    );
  }
}
