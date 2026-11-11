import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/utils/locale_text.dart';
import '../../auth/data/auth_provider.dart';

/// Read only platform metadata; auth and translation sessions stay uninitialized.
final screenTranslationIOSVersionProvider = FutureProvider<String?>((
  ref,
) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return null;
  try {
    return (await DeviceInfoPlugin().iosInfo).systemVersion;
  } catch (_) {
    return null;
  }
});

/// Version availability is checked before mounting the auth/session owner.
class ScreenTranslationSection extends ConsumerWidget {
  const ScreenTranslationSection({
    super.key,
    this.enabled = featureEnabled,
    this.actionBuilder,
  });

  static const featureEnabled = bool.fromEnvironment(
    'SCREEN_TRANSLATION_ENABLED',
    defaultValue: false,
  );

  static bool available({bool enabled = featureEnabled}) =>
      enabled && !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  final bool enabled;

  /// Reuses the session owner in a menu without removing it during native launch.
  /// Disabled/platform-unsupported builds receive no action and initialize no auth.
  final Widget Function(
    BuildContext context,
    VoidCallback? onPressed,
    bool supported,
  )?
  actionBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!available(enabled: enabled)) {
      return actionBuilder?.call(context, null, false) ??
          const SizedBox.shrink();
    }
    final version = ref
        .watch(screenTranslationIOSVersionProvider)
        .asData
        ?.value;
    final major = int.tryParse(version?.split('.').first ?? '');
    if (major == null || major < 27) {
      return actionBuilder?.call(context, null, false) ??
          const SizedBox.shrink();
    }
    return _ScreenTranslationCard(actionBuilder: actionBuilder);
  }
}

class _ScreenTranslationCard extends ConsumerStatefulWidget {
  const _ScreenTranslationCard({this.actionBuilder});

  final Widget Function(
    BuildContext context,
    VoidCallback? onPressed,
    bool supported,
  )?
  actionBuilder;

  @override
  ConsumerState<_ScreenTranslationCard> createState() =>
      _ScreenTranslationCardState();
}

class _ScreenTranslationCardState
    extends ConsumerState<_ScreenTranslationCard> {
  static const _channel = MethodChannel(
    'com.twoalogistic.user/screen_translation',
  );
  bool _busy = false;
  bool _opened = false;
  int _scopeRevision = 0;

  bool _sameScope(AuthState a, AuthState b) =>
      a.isLoggedIn == b.isLoggedIn &&
      a.clientId == b.clientId &&
      a.userDomain == b.userDomain;

  void _stop() {
    if (!_opened) return;
    _opened = false;
    unawaited(_channel.invokeMethod<void>('stop').catchError((Object _) {}));
  }

  void _message({bool login = false, bool unsupported = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          unsupported
              ? tr(
                  context,
                  ru: 'Для перевода экрана требуется iOS 27 или новее.',
                  zh: '屏幕翻译需要iOS 27或更新版本。',
                )
              : login
              ? tr(context, ru: 'Войдите в аккаунт заново.', zh: '请重新登录账户。')
              : tr(
                  context,
                  ru: 'Перевод экрана сейчас недоступен. Попробуйте позже.',
                  zh: '屏幕翻译暂时不可用，请稍后重试。',
                ),
        ),
      ),
    );
  }

  Future<void> _present() async {
    if (_busy) return;
    final scope = ref.read(authProvider);
    if (!scope.isLoggedIn || scope.clientId == null) {
      _message(login: true);
      return;
    }
    final revision = _scopeRevision;
    final api = ref.read(apiClientProvider);
    final base = api.activeBaseUrl;
    final uri = Uri.tryParse(base);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      _message();
      return;
    }
    final endpoint = uri.replace(
      path: '${uri.path.replaceFirst(RegExp(r'/+$'), '')}/screen-translate/v1',
    );
    final colors = Theme.of(context).colorScheme;
    final appearance = {
      'primary': colors.primary.toARGB32(),
      'secondary': colors.secondary.toARGB32(),
      'gradientStart': context.brandGradient.colors.first.toARGB32(),
      'language': Localizations.localeOf(context).languageCode,
    };
    setState(() => _busy = true);
    try {
      final token = await api.getToken();
      if (!mounted ||
          revision != _scopeRevision ||
          !_sameScope(scope, ref.read(authProvider)) ||
          api.activeBaseUrl != base) {
        return;
      }
      if (token == null || token.trim().isEmpty) {
        _message(login: true);
        return;
      }
      // Mark ownership before invoking: logout/dispose must also stop an
      // in-flight native presentation. Credentials remain local to this call.
      _opened = true;
      final result = await _channel.invokeMethod<Object?>('present', {
        'endpoint': endpoint.toString(),
        'accessToken': token,
        'appearance': appearance,
      });
      if (!mounted || revision != _scopeRevision) return;
      if (result == false) {
        _stop();
        _message();
      }
    } on PlatformException catch (error) {
      _stop();
      if (mounted && revision == _scopeRevision) {
        _message(unsupported: error.code == 'UNSUPPORTED_IOS');
      }
    } catch (_) {
      _stop();
      if (mounted && revision == _scopeRevision) _message();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (previous != null && !_sameScope(previous, next)) {
        _scopeRevision++;
        _stop();
      }
    });
    final actionBuilder = widget.actionBuilder;
    if (actionBuilder != null) {
      return actionBuilder(context, _busy ? null : _present, true);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Card(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(context, ru: 'Перевод экрана', zh: '屏幕翻译'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr(
                  context,
                  ru: 'Текст распознаётся на iPhone. Для перевода распознанный текст отправляется через 2A в Яндекс. Разрешение на захват экрана вы дадите отдельно перед запуском.',
                  zh: '文字在 iPhone 上识别。识别后的文字通过 2A 发送至 Yandex 翻译。开始前需另行授权屏幕捕获。',
                ),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _present,
                icon: const Icon(Icons.translate_rounded),
                label: Text(tr(context, ru: 'Перевод экрана', zh: '屏幕翻译')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
