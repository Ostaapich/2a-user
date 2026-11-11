import 'package:intl/intl.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_target.dart';
import 'package:flutter/material.dart';

import '../../../core/ui/app_colors.dart';
import '../../../core/utils/locale_text.dart';

/// Брендовый градиентный хедер карточки/модалки самовыкупа.
class SelfBuyoutGradientHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? subtitleTrainingTargetId;

  const SelfBuyoutGradientHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.subtitleTrainingTargetId,
  });

  @override
  Widget build(BuildContext context) {
    final subtitleText = Text(
      subtitle,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Color(0xE6FFFFFF),
        fontFamily: 'Gilroy',
        fontSize: 12.8,
        height: 1.15,
        fontWeight: FontWeight.w600,
      ),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: context.brandGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: context.brandPrimary.withValues(alpha: 0.18),
            blurRadius: 22,
            spreadRadius: -12,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Icon(icon, color: Colors.white, size: 25),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Gilroy',
                    fontSize: 21,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.25,
                  ),
                ),
                const SizedBox(height: 5),
                subtitleTrainingTargetId == null
                    ? subtitleText
                    : TrainingTarget(
                        id: subtitleTrainingTargetId!,
                        child: subtitleText,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SelfBuyoutPrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isLoading;

  const SelfBuyoutPrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !isLoading;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 50,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: enabled ? context.brandGradient : null,
            color: enabled ? null : const Color(0xFFE9ECEF),
            borderRadius: BorderRadius.circular(18),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: context.brandPrimary.withValues(alpha: 0.18),
                      blurRadius: 18,
                      spreadRadius: -10,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Gilroy',
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class SelfBuyoutSecondaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const SelfBuyoutSecondaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 140),
          opacity: enabled ? 1 : 0.52,
          child: Container(
            height: 50,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: context.brandPrimary.withValues(alpha: 0.34),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: context.brandPrimary, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.brandPrimary,
                      fontFamily: 'Gilroy',
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Цвет статуса заявки самовыкупа.
Color selfBuyoutStatusColor(String status) {
  switch (status) {
    case 'new':
      return const Color(0xFF3B82F6);
    case 'awaiting_payment':
      return const Color(0xFFF59E0B);
    case 'payment_review':
      return const Color(0xFF8B5CF6);
    case 'in_progress':
      return const Color(0xFF06B6D4);
    case 'completed':
      return const Color(0xFF10B981);
    case 'cancelled':
      return const Color(0xFFEF4444);
    default:
      return AppColors.textSecondary;
  }
}

String selfBuyoutStatusLabel(BuildContext context, String status) {
  switch (status) {
    case 'new':
      return tr(context, ru: 'Новая', zh: '新建');
    case 'awaiting_payment':
      return tr(context, ru: 'Ожидает оплаты', zh: '待付款');
    case 'payment_review':
      return tr(context, ru: 'На проверке', zh: '待审核');
    case 'in_progress':
      return tr(context, ru: 'В работе', zh: '处理中');
    case 'completed':
      return tr(context, ru: 'Выполнена', zh: '已完成');
    case 'cancelled':
      return tr(context, ru: 'Отменена', zh: '已取消');
    default:
      return status;
  }
}

String formatSelfBuyoutMoney(BuildContext context, num amount) =>
    NumberFormat.decimalPatternDigits(
      locale: Localizations.localeOf(context).languageCode == 'zh'
          ? 'zh_CN'
          : 'ru_RU',
      decimalDigits: 2,
    ).format(amount);
