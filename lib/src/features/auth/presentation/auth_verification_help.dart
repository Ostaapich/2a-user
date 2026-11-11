import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/utils/locale_text.dart';

/// Assistance remains separate from verification: opening company contacts
/// never confirms a phone number or bypasses the existing call provider.
class AuthVerificationHelp extends StatelessWidget {
  const AuthVerificationHelp({super.key, required this.company});
  final String company;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: const Icon(Icons.help_outline_rounded),
    label: Text(
      tr(context, ru: 'Не получается подтвердить номер?', zh: '无法验证电话号码？'),
    ),
    onPressed: () async {
      final raw = company.trim().replaceFirst(RegExp(r'^https?://'), '');
      final parsed = Uri.tryParse('https://$raw');
      final uri =
          parsed != null && parsed.host.contains('.') && parsed.userInfo.isEmpty
          ? Uri.https(parsed.host, '/')
          : Uri.parse('https://2a-logistic.ru/contacts/');
      final open = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr(context, ru: 'Помощь с подтверждением', zh: '验证帮助')),
          content: Text(
            tr(
              context,
              ru: 'Если звонок не проходит, обратитесь в компанию через её сайт. Введённые данные останутся на экране. Подтверждение номера пока не завершено.',
              zh: '如果无法拨打验证电话，请通过公司网站联系工作人员。已填写的内容会保留，电话号码尚未验证。',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(tr(context, ru: 'Вернуться к форме', zh: '返回表单')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(tr(context, ru: 'Открыть контакты', zh: '打开联系方式')),
            ),
          ],
        ),
      );
      if (!context.mounted || open != true) return;
      try {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!context.mounted) return;
        if (!launched) {
          AppToast.show(
            context,
            tr(context, ru: 'Не удалось открыть сайт компании', zh: '无法打开公司网站'),
            isError: true,
          );
        }
      } catch (_) {
        if (context.mounted) {
          AppToast.show(
            context,
            tr(context, ru: 'Не удалось открыть сайт компании', zh: '无法打开公司网站'),
            isError: true,
          );
        }
      }
    },
  );
}
