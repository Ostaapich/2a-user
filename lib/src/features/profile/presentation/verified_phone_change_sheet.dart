import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phone_form_field/phone_form_field.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/network/api_client.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/ui/phone_input_field.dart';
import '../../../core/utils/locale_text.dart';
import '../../auth/data/auth_input_safety.dart';

class VerifiedPhoneChangeSheet extends ConsumerStatefulWidget {
  const VerifiedPhoneChangeSheet({super.key});
  @override
  ConsumerState<VerifiedPhoneChangeSheet> createState() =>
      _VerifiedPhoneChangeSheetState();
}

class _VerifiedPhoneChangeSheetState
    extends ConsumerState<VerifiedPhoneChangeSheet>
    with WidgetsBindingObserver {
  final _phone = PhoneController(
    initialValue: const PhoneNumber(isoCode: IsoCode.RU, nsn: ''),
  );
  String? _pendingToken, _callPhone, _verifiedNumber, _error;
  DateTime? _expiresAt;
  bool _busy = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _phone.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingToken != null) {
      unawaited(_check());
    }
  }

  Future<void> _request() async {
    final number = PhoneInputField.internationalValue(_phone.value);
    if (number == null) {
      setState(
        () => _error = tr(
          context,
          ru: 'Введите корректный номер телефона',
          zh: '请输入有效的电话号码',
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await ref
          .read(apiClientProvider)
          .post(
            '/register/phone-verification/request',
            data: {'phone': number},
          );
      if (!mounted) return;
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['verificationToken'] is! String ||
          data['callPhone'] is! String) {
        throw StateError('Incomplete verification response');
      }
      setState(() {
        _pendingToken = data['verificationToken'] as String;
        _callPhone = data['callPhone'] as String;
        _verifiedNumber = number;
        _expiresAt =
            DateTime.tryParse(data['expiresAt']?.toString() ?? '') ??
            DateTime.now().add(const Duration(minutes: 5));
      });
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = tr(
          context,
          ru: 'Не удалось начать проверку. Попробуйте ещё раз.',
          zh: '无法开始验证，请重试。',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    if (_busy || _pendingToken == null) return;
    if (verificationSecondsLeft(_expiresAt ?? DateTime.now()) == 0) {
      _poll?.cancel();
      setState(() {
        _pendingToken = null;
        _error = tr(
          context,
          ru: 'Время истекло. Запросите новый звонок.',
          zh: '验证已过期，请重新请求通话。',
        );
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final response = await ref
          .read(apiClientProvider)
          .post(
            '/register/phone-verification/verify',
            data: {'verificationToken': _pendingToken},
          );
      if (!mounted) return;
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['confirmed'] == true &&
          data['phoneVerificationToken'] is String) {
        _poll?.cancel();
        await ref
            .read(apiClientProvider)
            .patch(
              '/client/profile',
              data: {
                'phone': _verifiedNumber,
                'phoneVerificationToken': data['phoneVerificationToken'],
              },
            );
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else if (data['expired'] == true) {
        _poll?.cancel();
        setState(() {
          _pendingToken = null;
          _error = tr(
            context,
            ru: 'Проверка истекла. Повторите звонок.',
            zh: '验证已过期，请重新通话。',
          );
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = tr(
          context,
          ru: 'Номер не изменён. Не удалось подтвердить или сохранить его. Повторите проверку; прежний номер сохранён.',
          zh: '号码未更改。无法验证或保存，请重试。原号码仍保留。',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(context, ru: 'Подтвердите новый телефон', zh: '验证新电话号码'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(
            tr(
              context,
              ru: 'Прежний номер останется для восстановления доступа, пока новый не подтверждён и не сохранён.',
              zh: '新号码验证并保存前，原号码仍用于恢复账户。',
            ),
          ),
          const SizedBox(height: 16),
          if (_pendingToken == null) PhoneInputField(controller: _phone),
          if (_pendingToken != null) ...[
            Text(
              tr(
                context,
                ru: 'Позвоните с нового номера на $_callPhone, затем вернитесь в приложение.',
                zh: '请使用新号码拨打 $_callPhone，然后返回应用。',
              ),
            ),
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      final uri = Uri(scheme: 'tel', path: _callPhone);
                      try {
                        final opened = await launchUrl(uri);
                        if (!mounted) return;
                        if (!opened) {
                          setState(
                            () => _error = tr(
                              context,
                              ru: 'Позвоните на номер вручную: $_callPhone',
                              zh: '请手动拨打：$_callPhone',
                            ),
                          );
                        }
                      } catch (_) {
                        if (mounted) {
                          setState(
                            () => _error = tr(
                              context,
                              ru: 'Не удалось открыть телефон. Наберите $_callPhone вручную.',
                              zh: '无法打开电话，请手动拨打 $_callPhone。',
                            ),
                          );
                        }
                      }
                    },
              icon: const Icon(Icons.call),
              label: Text(_callPhone ?? ''),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy
                ? null
                : (_pendingToken == null ? _request : _check),
            style: FilledButton.styleFrom(
              backgroundColor: context.brandPrimary,
            ),
            child: Text(
              tr(
                context,
                ru: _busy
                    ? 'Проверяем…'
                    : _pendingToken == null
                    ? 'Подтвердить звонком'
                    : 'Проверить и сохранить номер',
                zh: _busy
                    ? '验证中…'
                    : _pendingToken == null
                    ? '通话验证'
                    : '验证并保存号码',
              ),
            ),
          ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: Text(tr(context, ru: 'Отмена', zh: '取消')),
          ),
        ],
      ),
    ),
  );
}
