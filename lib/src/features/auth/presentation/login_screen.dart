import '../../../core/services/analytics_service.dart';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/agent_domain_resolver.dart';
import '../../../core/ui/app_background.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/ui/blurred_modal_bottom_sheet.dart';
import '../../../core/utils/locale_text.dart';
import '../../tariffs/data/tariffs_provider.dart';
import '../data/auth_provider.dart';
import '../data/passkey_auth_service.dart';
import '../data/partner_link_provider.dart';
import 'auth_visuals.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  final _domainCtrl = TextEditingController();
  final _loginCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  late final AnimationController _introController;
  late final AnimationController _ambientController;
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _showPasswordLogin = kIsWeb;
  bool _passkeyAvailable = false;
  bool _passkeyAvailabilityChecked = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.trackFunnel(WorkflowAction.login, WorkflowStage.viewed);
    AppToast.hide();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 920),
    );
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat(reverse: true);

    final detectedDomain = AgentDomainResolver.currentAgentDomain;
    if (detectedDomain != null) {
      _domainCtrl.text = detectedDomain;
    } else {
      unawaited(_restoreLastCompany());
    }
    _introController.forward();
    Future<void>.delayed(const Duration(seconds: 8), () {
      if (mounted) {
        _ambientController.stop();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (kIsWeb) return;
      _loadPasskeyAvailability();
    });
  }

  Future<void> _restoreLastCompany() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || _domainCtrl.text.isNotEmpty) return;
    _domainCtrl.text = prefs.getString('last_company_domain') ?? '';
  }

  @override
  void dispose() {
    _introController.dispose();
    _ambientController.dispose();
    _domainCtrl.dispose();
    _loginCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPasskeyAvailability() async {
    if (kIsWeb) {
      if (!mounted) return;
      setState(() {
        _passkeyAvailable = false;
        _passkeyAvailabilityChecked = true;
      });
      return;
    }

    // На старых Android проверка passkeys может поднимать Google Play Services
    // и заметно блокировать первые кадры. Даём экрану входа сначала отрисоваться.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    final available = await ref.read(passkeyAuthServiceProvider).isAvailable();
    if (!mounted) return;
    setState(() {
      _passkeyAvailable = available;
      _passkeyAvailabilityChecked = true;
    });
  }

  Future<void> _loginWithPassword() async {
    final partnerLinkActive = ref.read(partnerLinkProvider).hasPendingToken;
    final effectiveDomain = partnerLinkActive
        ? partnerLinkAgentDomain
        : _domainCtrl.text.trim();
    if (effectiveDomain.isEmpty ||
        _loginCtrl.text.isEmpty ||
        _passwordCtrl.text.isEmpty) {
      _showError('Заполните все поля');
      return;
    }

    // Закрываем клавиатуру перед началом
    FocusScope.of(context).unfocus();

    setState(() => _isLoading = true);

    try {
      final success = await ref
          .read(authProvider.notifier)
          .login(
            email: _loginCtrl.text.trim(),
            domain: effectiveDomain,
            password: _passwordCtrl.text,
            beforeComplete: (userData) async {
              if (!mounted) return;
              await _maybeOfferPasskeyEnrollment(userData);
            },
          );

      if (!mounted) return;

      if (!success) {
        // Небольшая задержка чтобы пользователь увидел что была попытка
        await Future.delayed(const Duration(milliseconds: 300));

        if (!mounted) return;

        setState(() => _isLoading = false);

        // Показываем ошибку из authProvider или запускаем подтверждение звонком.
        final authState = ref.read(authProvider);
        final challenge = authState.loginVerificationChallenge;
        final errorMessage = authState.error ?? 'Ошибка авторизации';
        debugPrint('❌ Login failed: $errorMessage');

        // Ждём завершения анимации loader'а перед показом UI ошибки.
        await Future.delayed(const Duration(milliseconds: 100));

        if (!mounted) return;
        if (challenge != null) {
          await _showLoginVerificationSheet(challenge);
        } else {
          _showError(errorMessage);
        }
      } else {
        debugPrint('✅ Login successful');
        setState(() => _isLoading = false);
      }
      // Router will automatically redirect to / on successful login
    } catch (e) {
      if (!mounted) return;

      // Небольшая задержка чтобы пользователь увидел что была попытка
      await Future.delayed(const Duration(milliseconds: 300));

      if (!mounted) return;

      setState(() => _isLoading = false);
      debugPrint('❌ Login exception: $e');

      // Ждём завершения анимации loader'а
      await Future.delayed(const Duration(milliseconds: 100));

      if (mounted) {
        _showError('Произошла ошибка при входе. Попробуйте ещё раз');
      }
    }
  }

  Future<void> _loginWithPasskey() async {
    if (_passkeyAvailabilityChecked && !_passkeyAvailable) {
      _showError('Это устройство не поддерживает быстрый вход');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    final passkeyService = ref.read(passkeyAuthServiceProvider);

    try {
      final result = await passkeyService.authenticate();

      if (!mounted) return;

      final success = await ref
          .read(authProvider.notifier)
          .loginWithData(token: result.token, userData: result.userData);

      if (!mounted) return;

      if (!success) {
        final authState = ref.read(authProvider);
        _showError(authState.error ?? 'Ошибка авторизации');
      }
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);
      debugPrint('❌ Passkey login failed: $e');
      _showError(passkeyService.humanMessage(e));
    }
  }

  Future<void> _maybeOfferPasskeyEnrollment(
    Map<String, dynamic> userData,
  ) async {
    if (kIsWeb) return;

    var passkeyAvailable = _passkeyAvailable;
    if (!_passkeyAvailabilityChecked) {
      passkeyAvailable = await ref
          .read(passkeyAuthServiceProvider)
          .isAvailable();
      if (!mounted) return;
      setState(() {
        _passkeyAvailable = passkeyAvailable;
        _passkeyAvailabilityChecked = true;
      });
    }
    if (!passkeyAvailable) return;

    final clientId = userData['id'] as int? ?? userData['clientId'] as int?;
    final agentId = userData['agentId'] as int?;
    if (clientId == null) return;

    final prefs = await SharedPreferences.getInstance();
    final prefSuffix = '${agentId ?? 'agent'}_$clientId';
    final dismissedKey = 'passkey_prompt_dismissed_v1_$prefSuffix';
    try {
      final serverStatus = await ref
          .read(passkeyAuthServiceProvider)
          .getCurrentUserPasskeyStatus();
      if (!mounted || serverStatus.enabled) return;
    } catch (error) {
      debugPrint('Passkey status check after login failed: $error');
      return;
    }
    if (prefs.getBool(dismissedKey) == true) return;

    if (!mounted) return;

    final shouldEnable = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Включить быстрый вход?'),
          content: const Text(
            'После подключения вы сможете входить без телефона, домена '
            'партнёра и пароля. Если у вас несколько аккаунтов, устройство '
            'предложит выбрать нужного партнёра.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Позже'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Включить'),
            ),
          ],
        );
      },
    );

    if (shouldEnable != true) {
      await prefs.setBool(dismissedKey, true);
      return;
    }

    try {
      await ref.read(passkeyAuthServiceProvider).registerCurrentUserPasskey();
      await prefs.remove(dismissedKey);
      if (!mounted) return;
      AppToast.showFromSnackBar(
        context,
        const SnackBar(content: Text('Быстрый вход подключён')),
      );
    } catch (e, stackTrace) {
      debugPrint(
        '⚠️ Passkey registration failed (${e.runtimeType}): $e\n$stackTrace',
      );
      if (!mounted) return;
      AppToast.showFromSnackBar(
        context,
        SnackBar(
          content: Text(
            ref.read(passkeyAuthServiceProvider).humanRegistrationMessage(e),
          ),
        ),
      );
    }
  }

  Future<void> _showLoginVerificationSheet(
    LoginVerificationChallenge challenge,
  ) async {
    await showBlurredModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LoginVerificationSheet(challenge: challenge),
    );
  }

  void _showError(String message) {
    AppToast.showFromSnackBar(
      context,
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Ошибка входа',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        duration: const Duration(seconds: 5),
        elevation: 8,
      ),
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
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final animationsEnabled =
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);

    return AutofillGroup(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
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
                  bottomPadding + keyboardInset + 24,
                ),
                child: AuthResponsiveContent(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PremiumEntrance(
                        animation: _introController,
                        animationsEnabled: animationsEnabled,
                        child: const AuthHeroHeader(
                          icon: Icons.local_shipping_rounded,
                          title: 'Вход в личный кабинет',
                          subtitle:
                              'Следите за грузами, сборками, счетами и фотоотчётами в одном защищённом кабинете.',
                          trustItems: [
                            AuthTrustItem(
                              icon: Icons.photo_camera_rounded,
                              label: 'Фотоотчёты',
                            ),
                            AuthTrustItem(
                              icon: Icons.location_on_rounded,
                              label: 'Отслеживание',
                            ),
                            AuthTrustItem(
                              icon: Icons.account_balance_wallet_rounded,
                              label: 'Alipay / WeChat Pay',
                            ),
                            AuthTrustItem(
                              icon: Icons.shopping_bag_rounded,
                              label: 'Выкуп',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      _PremiumEntrance(
                        animation: _introController,
                        delay: 0.14,
                        animationsEnabled: animationsEnabled,
                        child: _AmbientAuthCard(
                          animation: _ambientController,
                          animationsEnabled: animationsEnabled,
                          child: AuthFormCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 280),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: _verticalRevealTransition,
                                  child: _showPasswordLogin
                                      ? _buildTextField(
                                          key: const ValueKey(
                                            'password-login-identifier',
                                          ),
                                          controller: _loginCtrl,
                                          label: 'Email или телефон',
                                          hint: 'user@example.com',
                                          prefixIcon: Icons.person_rounded,
                                          keyboardType:
                                              TextInputType.emailAddress,
                                        )
                                      : const SizedBox.shrink(
                                          key: ValueKey(
                                            'passkey-login-identifier-hidden',
                                          ),
                                        ),
                                ),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 280),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: _verticalRevealTransition,
                                  child:
                                      !_showPasswordLogin &&
                                          _passkeyAvailabilityChecked &&
                                          _passkeyAvailable
                                      ? _buildPasskeyActions()
                                      : const SizedBox.shrink(
                                          key: ValueKey('passkey-hidden'),
                                        ),
                                ),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 360),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: _verticalRevealTransition,
                                  child: _showPasswordLogin
                                      ? _buildPasswordFields(
                                          partnerLinkActive: partnerLinkActive,
                                        )
                                      : const SizedBox(
                                          key: ValueKey(
                                            'password-fields-hidden',
                                          ),
                                          height: 12,
                                        ),
                                ),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 260),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: _buttonSwapTransition,
                                  child: _showPasswordLogin
                                      ? _buildPasswordSubmitButton()
                                      : _buildPasswordRevealButton(),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: _isLoading
                                      ? null
                                      : () => context.push('/register'),
                                  style: AuthVisuals.outlinedButtonStyle(
                                    context,
                                  ),
                                  icon: const Icon(
                                    Icons.person_add_alt_1_rounded,
                                  ),
                                  label: const Text(
                                    'Зарегистрироваться',
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),
                      _PremiumEntrance(
                        animation: _introController,
                        delay: 0.28,
                        animationsEnabled: animationsEnabled,
                        child: const _PublicTariffsPreview(),
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

  Widget _buildPasskeyActions() {
    return Column(
      key: const ValueKey('passkey-actions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _isLoading ? null : _loginWithPasskey,
          style: AuthVisuals.primaryButtonStyle(context),
          icon: _isLoading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.fingerprint_rounded),
          label: const Text(
            'Войти по Face ID / отпечатку',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Телефон и домен вводить не нужно. Если доступно несколько '
          'профилей, выберите нужного партнёра в системном окне.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondary.withValues(alpha: 0.82),
            fontSize: 12,
            height: 1.25,
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordFields({required bool partnerLinkActive}) {
    return Column(
      key: const ValueKey('password-fields'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        if (partnerLinkActive)
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AuthVisuals.primary(context).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: AuthVisuals.primary(context).withValues(alpha: 0.18),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.business_rounded, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Вход в аккаунт партнёра',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          )
        else
          _buildTextField(
            controller: _domainCtrl,
            label: 'Домен партнёра',
            hint: 'example-company.ru',
            prefixIcon: Icons.business_rounded,
            keyboardType: TextInputType.url,
          ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _passwordCtrl,
          label: 'Пароль',
          hint: '••••••••',
          prefixIcon: Icons.lock_rounded,
          obscureText: _obscurePassword,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _loginWithPassword(),
          suffixIcon: IconButton(
            tooltip: tr(
              context,
              ru: _obscurePassword ? 'Показать пароль' : 'Скрыть пароль',
              zh: _obscurePassword ? '显示密码' : '隐藏密码',
            ),
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              color: const Color(0xFF999999),
              size: 20,
            ),
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => context.push('/forgot-password'),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Забыли пароль?',
              style: TextStyle(
                color: AuthVisuals.primary(context),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildPasswordSubmitButton() {
    return SizedBox(
      key: const ValueKey('password-submit'),
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _isLoading ? null : _loginWithPassword,
        style: AuthVisuals.primaryButtonStyle(context),
        icon: _isLoading
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.lock_outline_rounded),
        label: const Text(
          'Войти с помощью пароля',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildPasswordRevealButton() {
    return SizedBox(
      key: const ValueKey('password-reveal'),
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _isLoading
            ? null
            : () => setState(() => _showPasswordLogin = true),
        style: AuthVisuals.outlinedButtonStyle(context),
        icon: const Icon(Icons.lock_outline_rounded),
        label: const Text(
          'Войти с помощью пароля',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
    );
  }

  Widget _verticalRevealTransition(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return FadeTransition(
      opacity: curved,
      child: SizeTransition(
        sizeFactor: curved,
        axisAlignment: -1,
        child: child,
      ),
    );
  }

  Widget _buttonSwapTransition(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
        child: child,
      ),
    );
  }

  Widget _buildTextField({
    Key? key,
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData prefixIcon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    List<TextInputFormatter>? inputFormatters,
    TextInputAction? textInputAction,
    void Function(String)? onSubmitted,
  }) {
    final accent = AuthVisuals.primary(context);

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF333333),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.78),
            border: Border.all(color: accent.withValues(alpha: 0.16)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: controller,
            autofillHints: controller == _passwordCtrl
                ? const [AutofillHints.password]
                : controller == _loginCtrl
                ? const [AutofillHints.username]
                : null,
            keyboardType: keyboardType,
            obscureText: obscureText,
            inputFormatters: inputFormatters,
            textInputAction: textInputAction,
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                color: Color(0xFFAAAAAA),
                fontSize: 14,
              ),
              prefixIcon: Icon(
                prefixIcon,
                color: accent.withValues(alpha: 0.72),
                size: 20,
              ),
              suffixIcon: suffixIcon,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LoginVerificationSheet extends ConsumerStatefulWidget {
  final LoginVerificationChallenge challenge;

  const _LoginVerificationSheet({required this.challenge});

  @override
  ConsumerState<_LoginVerificationSheet> createState() =>
      _LoginVerificationSheetState();
}

class _LoginVerificationSheetState
    extends ConsumerState<_LoginVerificationSheet> {
  LoginVerificationRequestInfo? _requestInfo;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  int _secondsLeft = 0;
  bool _requesting = false;
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }

  void _cancelTimers() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  Future<void> _requestCall() async {
    if (_requesting) return;
    _cancelTimers();
    setState(() {
      _requesting = true;
      _error = null;
      _requestInfo = null;
      _secondsLeft = 0;
    });

    try {
      final info = await ref
          .read(authProvider.notifier)
          .requestLoginVerification(
            login: widget.challenge.login,
            domain: widget.challenge.domain,
          );
      if (!mounted) return;
      final expiresAt = info.expiresAt;
      setState(() {
        _requestInfo = info;
        _secondsLeft = expiresAt == null
            ? 300
            : expiresAt
                  .difference(DateTime.now())
                  .inSeconds
                  .clamp(1, 300)
                  .toInt();
        _requesting = false;
      });
      _startPolling();
      _startCountdown();
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _requesting = false;
        _error = _extractDioMessage(e, 'Не удалось начать проверку звонком');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _requesting = false;
        _error = 'Не удалось начать проверку звонком';
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _verifyCall();
    });
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
      } else {
        _cancelTimers();
        setState(() {
          _error = 'Время проверки истекло. Запросите новый звонок.';
          _requestInfo = null;
        });
      }
    });
  }

  Future<void> _verifyCall({bool showPendingMessage = false}) async {
    final info = _requestInfo;
    if (info == null || _checking) return;

    _checking = true;
    try {
      final result = await ref
          .read(authProvider.notifier)
          .verifyLoginVerification(checkId: info.checkId);
      if (!mounted) return;
      if (result.loggedIn) {
        _cancelTimers();
        HapticFeedback.heavyImpact();
        Navigator.of(context).pop(true);
        return;
      }
      if (result.expired) {
        _cancelTimers();
        setState(() {
          _requestInfo = null;
          _error = 'Время проверки истекло. Запросите новый звонок.';
        });
      } else if (showPendingMessage) {
        setState(() => _error = 'Звонок пока не подтверждён');
      }
    } on DioException catch (e) {
      if (showPendingMessage && mounted) {
        setState(() {
          _error = _extractDioMessage(e, 'Не удалось проверить звонок');
        });
      }
    } catch (_) {
      if (showPendingMessage && mounted) {
        setState(() => _error = 'Не удалось проверить звонок');
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> _makeCall() async {
    final callPhone = _requestInfo?.callPhone;
    if (callPhone == null || callPhone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: callPhone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  String _formatCountdown() {
    final minutes = _secondsLeft ~/ 60;
    final seconds = _secondsLeft % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _extractDioMessage(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map) {
      final value = data['error'] ?? data['message'];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final accent = AuthVisuals.primary(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final info = _requestInfo;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.security_rounded,
                      color: accent,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Подтвердите вход',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Это защита от подбора пароля',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _InfoBox(
                icon: Icons.lock_clock_rounded,
                color: Colors.orange.shade700,
                background: Colors.orange.shade50,
                border: Colors.orange.shade100,
                text: widget.challenge.maskedPhone == null
                    ? widget.challenge.message
                    : '${widget.challenge.message}\nЗвонок должен быть выполнен с номера ${widget.challenge.maskedPhone}.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _InfoBox(
                  icon: Icons.error_outline_rounded,
                  color: Colors.red.shade700,
                  background: Colors.red.shade50,
                  border: Colors.red.shade100,
                  text: _error!,
                ),
              ],
              const SizedBox(height: 18),
              if (info == null) ...[
                FilledButton.icon(
                  onPressed: _requesting ? null : _requestCall,
                  style: AuthVisuals.primaryButtonStyle(context),
                  icon: _requesting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.phone_callback_rounded, size: 18),
                  label: const Text('Получить номер для звонка'),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: accent.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Позвоните на номер:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        info.callPhonePretty,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.timer_outlined,
                            size: 18,
                            color: Color(0xFF6B7280),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Осталось: ${_formatCountdown()}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF374151),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _makeCall,
                  style: AuthVisuals.primaryButtonStyle(context),
                  icon: const Icon(Icons.call_rounded, size: 18),
                  label: const Text('Позвонить'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _checking
                      ? null
                      : () => _verifyCall(showPendingMessage: true),
                  style: AuthVisuals.outlinedButtonStyle(context),
                  icon: _checking
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accent,
                          ),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Проверить'),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: _requesting ? null : _requestCall,
                  child: const Text('Запросить звонок заново'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Звонок бесплатный. После соединения можете сразу положить трубку. Мы проверим звонок автоматически.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final Color border;
  final String text;

  const _InfoBox({
    required this.icon,
    required this.color,
    required this.background,
    required this.border,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumEntrance extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  final double delay;
  final bool animationsEnabled;

  const _PremiumEntrance({
    required this.animation,
    required this.child,
    this.delay = 0,
    this.animationsEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!animationsEnabled) return child;

    final start = delay.clamp(0.0, 0.72).toDouble();
    final end = (start + 0.68).clamp(0.08, 1.0).toDouble();
    final eased = animation.drive(
      CurveTween(curve: Interval(start, end, curve: Curves.easeOutCubic)),
    );

    return FadeTransition(
      opacity: eased,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.055),
          end: Offset.zero,
        ).animate(eased),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(eased),
          child: child,
        ),
      ),
    );
  }
}

class _AmbientAuthCard extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  final bool animationsEnabled;

  const _AmbientAuthCard({
    required this.animation,
    required this.child,
    this.animationsEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!animationsEnabled) return child;

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final accent = AuthVisuals.primary(context);
        final secondary = AuthVisuals.secondary(context);
        final pulse = Curves.easeInOut.transform(animation.value);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -14,
              top: -12,
              right: -14,
              bottom: -16,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.01),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.12 + pulse * 0.07),
                        blurRadius: 28 + pulse * 18,
                        spreadRadius: 1 + pulse * 2,
                        offset: Offset(0, 12 + pulse * 5),
                      ),
                      BoxShadow(
                        color: secondary.withValues(
                          alpha: 0.08 + (1 - pulse) * 0.04,
                        ),
                        blurRadius: 34,
                        spreadRadius: 1,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            child!,
          ],
        );
      },
    );
  }
}

class _PublicTariffsPreview extends ConsumerWidget {
  const _PublicTariffsPreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tariffsAsync = ref.watch(publicDefaultTariffsProvider);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: tariffsAsync.when(
        loading: () => const SizedBox(
          height: 88,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (_, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PublicTariffsHeader(accent: AuthVisuals.primary(context)),
            const SizedBox(height: 12),
            Text(
              'Не удалось загрузить тарифы доставки.',
              style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.9),
                fontWeight: FontWeight.w500,
                height: 1.25,
              ),
            ),
          ],
        ),
        data: (tariffs) {
          if (tariffs.isEmpty) return const SizedBox.shrink();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PublicTariffsHeader(accent: AuthVisuals.primary(context)),
              const SizedBox(height: 14),
              for (var i = 0; i < tariffs.length; i++) ...[
                _PublicTariffRow(tariff: tariffs[i]),
                if (i != tariffs.length - 1)
                  Divider(
                    height: 18,
                    color: const Color(0xFF2F2F2F).withValues(alpha: 0.08),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PublicTariffsHeader extends StatelessWidget {
  final Color accent;

  const _PublicTariffsHeader({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.price_change_rounded, color: accent, size: 20),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Тарифы доставки',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2F2F2F),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PublicTariffRow extends StatelessWidget {
  final UserDeliveryTariff tariff;

  const _PublicTariffRow({required this.tariff});

  @override
  Widget build(BuildContext context) {
    final accent = AuthVisuals.primary(context);
    final String priceText;
    if (tariff.isDensityBased) {
      final kg = tariff.minimumDensityPricePerKg;
      final m3 = tariff.minimumDensityPricePerM3;
      final prices = [
        if (kg != null)
          tr(context, ru: 'от \$${_fmt(kg)}/кг', zh: '\$${_fmt(kg)}/kg起'),
        if (m3 != null)
          tr(context, ru: 'от \$${_fmt(m3)}/м³', zh: '\$${_fmt(m3)}/m³起'),
      ];
      priceText = prices.isEmpty
          ? tr(context, ru: 'Цена не указана', zh: '价格未设置')
          : prices.join('\n');
    } else {
      final price = _priceFrom(tariff);
      priceText = price > 0 ? 'от \$${_fmt(price)}/кг' : 'цена от —';
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            tariff.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              height: 1.15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2F2F2F),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            priceText,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: accent,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  static double _priceFrom(UserDeliveryTariff tariff) {
    final tierPrices = tariff.weightTiers
        .map((tier) => tier.pricePerKg)
        .where((price) => price > 0)
        .toList();
    if (tierPrices.isEmpty) return tariff.baseCost;
    tierPrices.sort();
    return tierPrices.first;
  }

  static String _fmt(double value) {
    final rounded = value.toStringAsFixed(2);
    return rounded.endsWith('00')
        ? value.toStringAsFixed(0)
        : rounded.replaceFirst(RegExp(r'0$'), '');
  }
}
