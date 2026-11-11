import '../utils/payment_qr_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

import '../../../core/ui/app_colors.dart';
import '../../../core/ui/blurred_modal_bottom_sheet.dart';
import '../../tracks/presentation/widgets/track_sheet_surface.dart';
import '../../../core/utils/locale_text.dart';

Future<void> showPaymentQrTimingWarning(
  BuildContext context, {
  String? paymentAttemptKey,
}) async {
  final preferences = paymentAttemptKey == null
      ? null
      : await SharedPreferences.getInstance();
  final key = 'payment.qr.rules.v1.$paymentAttemptKey';
  if (preferences?.getBool(key) == true || !context.mounted) return;
  final acknowledged = await showBlurredModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (dialogContext) => const _PaymentQrTimingWarningDialog(),
  );
  if (preferences != null && acknowledged == true) {
    await preferences.setBool(key, true);
  }
}

class _PaymentQrTimingWarningDialog extends StatelessWidget {
  const _PaymentQrTimingWarningDialog();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: TrackSheetSurface(
        showHandle: false,
        icon: Icons.receipt_long_rounded,
        title: tr(context, ru: 'Условия оплаты', zh: '付款说明'),
        subtitle: tr(context, ru: 'Оплата по QR и зачисление', zh: '二维码付款与入账'),
        footer: TrackSheetPrimaryButton(
          label: tr(context, ru: 'Я понял', zh: '我明白了'),
          icon: Icons.check_rounded,
          onTap: () => Navigator.of(context).pop(true),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE3E7EE)),
          ),
          child: Text(
            paymentQrTimingRules(context),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Gilroy',
              fontSize: 14,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

String paymentQrTimingRules(BuildContext context) => tr(
  context,
  ru: 'Если вы оплатите по этому QR после уведомления о том, что менеджеры по оплатам отдыхают, платёж будет зачислен на следующий день — по курсу юаня, актуальному на следующий день. Из-за изменения курса может потребоваться доплата.\n\nЧтобы избежать недоразумений, сразу после получения QR-кода произведите оплату и приложите чек. После успешной загрузки чека платёж будет автоматически отправлен на проверку.',
  zh: '如果您在收到“支付经理已休息”的通知后才使用此二维码付款，款项将在次日按照次日有效的人民币汇率入账。因此，汇率变动可能导致需要补款。\n\n为避免误解，请在获取二维码后立即完成付款并上传付款凭证。凭证上传成功后，付款将自动提交审核。',
);

class PaymentQrTimingNotice extends StatelessWidget {
  const PaymentQrTimingNotice({super.key});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: context.brandPrimary.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: context.brandPrimary.withValues(alpha: .14)),
    ),
    child: Material(
      color: Colors.transparent,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: context.brandPrimary,
        collapsedIconColor: context.brandPrimary,
        leading: Icon(Icons.info_outline_rounded, color: context.brandPrimary),
        title: Text(
          tr(context, ru: 'Условия оплаты и зачисления', zh: '付款及入账说明'),
          style: const TextStyle(
            fontFamily: 'Gilroy',
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        children: [
          Text(
            paymentQrTimingRules(context),
            style: const TextStyle(
              fontFamily: 'Gilroy',
              fontSize: 13.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Prominent recipient restriction, kept directly above monetary QR codes.
class PaymentRecipientWarning extends StatelessWidget {
  const PaymentRecipientWarning({super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1F2),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFFECACA)),
    ),
    child: Text(
      tr(context, ru: paymentPayerWarning, zh: '请勿使用个体工商户或公司账户付款'),
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: 'Gilroy',
        color: Color(0xFFB91C1C),
        fontSize: 16,
        fontWeight: FontWeight.w900,
        height: 1.25,
      ),
    ),
  );
}
