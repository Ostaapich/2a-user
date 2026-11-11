import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/app_colors.dart';
import '../../../core/utils/locale_text.dart';
import '../data/client_loyalty_provider.dart';
import '../domain/client_loyalty.dart';

String loyaltyTierLabel(BuildContext context, String tier) => switch (tier) {
  'silver' => tr(context, ru: 'Серебро', zh: '白银'),
  'gold' => tr(context, ru: 'Золото', zh: '黄金'),
  'platinum' => tr(context, ru: 'Платина', zh: '铂金'),
  _ => tr(context, ru: 'Базовый', zh: '基础'),
};

bool isLoyaltyErrorCode(String? code) =>
    code?.startsWith('loyalty_') == true ||
    const {
      'insufficient_loyalty_points',
      'reward_disabled',
      'invalid_track',
      'invalid_reward',
      'invalid_wish',
      'invalid_request_id',
      'PHOTO_REPORT_NOT_ALLOWED_FOR_STATUS',
      'duplicate_photo_request',
      'reward_refunded',
      'request_id_conflict',
    }.contains(code);

String loyaltyErrorText(BuildContext context, String? code) => switch (code) {
  'loyalty_insufficient_balance' || 'insufficient_loyalty_points' => tr(
    context,
    ru: 'Недостаточно бонусов. Баланс мог измениться — откройте выбор заново.',
    zh: '积分不足，余额可能已变更，请重新打开选择。',
  ),
  'loyalty_pending_request_changed' => tr(
    context,
    ru: 'Предыдущий запрос ещё не подтверждён. Повторите его с исходными пожеланиями.',
    zh: '上一项申请尚未确认，请使用原来的要求重试。',
  ),
  'loyalty_identity_changed' => tr(
    context,
    ru: 'Аккаунт изменился. Откройте запрос заново.',
    zh: '账户已变更，请重新打开申请。',
  ),
  'loyalty_disabled' || 'reward_disabled' => tr(
    context,
    ru: 'Программа бонусов сейчас недоступна. Бонусы не будут заменены платной услугой.',
    zh: '积分计划目前不可用，不会自动改为收费服务。',
  ),
  'reward_refunded' => tr(
    context,
    ru: 'Предыдущий запрос отменён, бонусы возвращены. Можно оформить новый запрос вручную.',
    zh: '上一项申请已取消，积分已退回。您可以手动提交新申请。',
  ),
  'request_id_conflict' => tr(
    context,
    ru: 'Параметры ранее отправленного запроса отличаются. Обновите список и обратитесь к менеджеру, если запрос не отображается.',
    zh: '先前提交的申请参数不一致，请刷新列表；如未显示申请，请联系经理。',
  ),
  'invalid_track' || 'PHOTO_REPORT_NOT_ALLOWED_FOR_STATUS' => tr(
    context,
    ru: 'Для запроса нужен ваш трек в ожидании. Обновите список и выберите доступный трек.',
    zh: '请选择属于您且待入库的运单，请刷新列表后重试。',
  ),
  'duplicate_photo_request' => tr(
    context,
    ru: 'Для этого трека уже есть активный запрос. Обновите список.',
    zh: '该运单已有处理中的申请，请刷新列表。',
  ),
  'invalid_wish' => tr(
    context,
    ru: 'Заполните пожелания к фотоотчёту или видео и повторите запрос.',
    zh: '请填写照片报告或视频的具体要求后重试。',
  ),
  _ => tr(
    context,
    ru: 'Не удалось подтвердить бонусный запрос. Повторите с теми же пожеланиями: повторное списание защищено.',
    zh: '无法确认积分申请。请使用相同要求重试，重复提交不会重复扣分。',
  ),
};

/// Kept outside the profile's loading/error state: a legacy server or an
/// unavailable optional capability cannot block the existing profile.
class ClientLoyaltySection extends ConsumerWidget {
  const ClientLoyaltySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(clientLoyaltyProvider);
    return summary.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (value) => value == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: ClientLoyaltyCard(
                value: value,
                onRefresh: () => ref.invalidate(clientLoyaltyProvider),
                onClaimGift: (tier) async {
                  await ref.read(clientLoyaltyApiProvider).claimGift(tier);
                  ref.invalidate(clientLoyaltyProvider);
                },
              ),
            ),
    );
  }
}

class ClientLoyaltyCard extends StatefulWidget {
  final ClientLoyalty value;
  final VoidCallback onRefresh;
  final Future<void> Function(String tier) onClaimGift;

  const ClientLoyaltyCard({
    super.key,
    required this.value,
    required this.onRefresh,
    required this.onClaimGift,
  });

  @override
  State<ClientLoyaltyCard> createState() => _ClientLoyaltyCardState();
}

class _ClientLoyaltyCardState extends State<ClientLoyaltyCard> {
  String? _claiming;
  String? _message;

  Future<void> _claim(String tier) async {
    if (_claiming != null) return;
    setState(() {
      _claiming = tier;
      _message = null;
    });
    try {
      await widget.onClaimGift(tier);
      if (!mounted) return;
      setState(
        () => _message = tr(
          context,
          ru: 'Заявка на подарок принята. Менеджер согласует получение.',
          zh: '礼品申请已受理，经理将与您确认领取方式。',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _message = tr(
          context,
          ru: 'Не удалось подтвердить заявку. Обновите данные и повторите: подарок за уровень выдаётся один раз.',
          zh: '无法确认申请。请刷新后重试，每个等级的礼品只能领取一次。',
        ),
      );
    } finally {
      if (mounted) setState(() => _claiming = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.workspace_premium_outlined,
                color: context.brandPrimary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr(context, ru: 'Бонусы и уровень', zh: '积分与会员等级'),
                  style: const TextStyle(
                    fontFamily: 'Gilroy',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: widget.onRefresh,
                tooltip: tr(context, ru: 'Обновить', zh: '刷新'),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          Text(
            loyaltyTierLabel(context, value.tier),
            style: TextStyle(
              color: context.brandPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              context,
              ru: 'Бонусов: ${value.balance}',
              zh: '积分：${value.balance}',
            ),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              context,
              ru: 'Расширенный фотоотчёт — 5 бонусов. Короткое видео — 10.',
              zh: '详细照片报告需5积分，商品短视频需10积分。',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              context,
              ru: '1 бонус за трек, добавленный заранее с описанием товара и фактически принятый на склад. Услугу выбирайте в карточке трека в ожидании.',
              zh: '提前添加运单并填写商品资料，货物实际入库后获得1积分。可在待入库运单卡片中兑换服务。',
            ),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              height: 1.3,
            ),
          ),
          if (value.pendingTracksMissingProductInfo > 0 ||
              value.assembliesMissingDelivery > 0) ...[
            const SizedBox(height: 12),
            Text(
              tr(context, ru: 'Что нужно заполнить', zh: '待完善资料'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (value.pendingTracksMissingProductInfo > 0)
              OutlinedButton.icon(
                key: const Key('loyalty-complete-product-info'),
                onPressed: () => context.push('/tracks'),
                icon: const Icon(Icons.inventory_2_outlined),
                label: Text(
                  tr(
                    context,
                    ru: 'У ${value.pendingTracksMissingProductInfo} треков не заполнена информация о товаре',
                    zh: '${value.pendingTracksMissingProductInfo}个运单尚未填写商品资料',
                  ),
                ),
              ),
            if (value.assembliesMissingDelivery > 0)
              OutlinedButton.icon(
                key: const Key('loyalty-complete-delivery'),
                onPressed: () => context.push('/tracks?view=groups'),
                icon: const Icon(Icons.local_shipping_outlined),
                label: Text(
                  tr(
                    context,
                    ru: 'У ${value.assembliesMissingDelivery} сборок не заполнена доставка по России',
                    zh: '${value.assembliesMissingDelivery}个集运包裹尚未填写俄罗斯境内配送资料',
                  ),
                ),
              ),
            Text(
              tr(
                context,
                ru: 'Это текущие задачи. За старые пропуски штрафов нет. Дополнительные бонусы за доставку по России пока не начисляются.',
                zh: '以上为当前待办事项，历史遗漏不会受罚。目前填写俄罗斯境内配送资料不额外增加积分。',
              ),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
              ),
            ),
          ],
          const Divider(height: 24),
          Text(
            tr(
              context,
              ru: 'За ${value.windowDays} дней: ${value.shippedKg.toStringAsFixed(1)} кг · ${value.shipments} сборок',
              zh: '近${value.windowDays}天：${value.shippedKg.toStringAsFixed(1)}公斤 · ${value.shipments}个集运包裹',
            ),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          for (final threshold in value.thresholds)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                tr(
                  context,
                  ru: '${loyaltyTierLabel(context, threshold.tier)}: ${threshold.kg.toStringAsFixed(0)} кг или ${threshold.shipments} отправок',
                  zh: '${loyaltyTierLabel(context, threshold.tier)}：${threshold.kg.toStringAsFixed(0)}公斤或${threshold.shipments}次发货',
                ),
              ),
            ),
          Text(
            tr(
              context,
              ru: 'Для уровня нужны отправки минимум в две разные даты. Дни считаются по времени Китая.',
              zh: '会员等级要求至少在两个不同日期发货，日期按中国时间计算。',
            ),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
            ),
          ),
          for (final threshold in value.thresholds)
            if (value.canClaim(threshold.tier))
              OutlinedButton.icon(
                onPressed: _claiming != null
                    ? null
                    : () => _claim(threshold.tier),
                icon: const Icon(Icons.card_giftcard_rounded),
                label: Text(
                  tr(
                    context,
                    ru: 'Запросить подарок: ${loyaltyTierLabel(context, threshold.tier)}',
                    zh: '申请${loyaltyTierLabel(context, threshold.tier)}等级礼品',
                  ),
                ),
              ),
          for (final gift in value.gifts)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                tr(
                  context,
                  ru: 'Подарок «${loyaltyTierLabel(context, gift.tier)}»: ${gift.status == 'fulfilled' ? 'выдан' : 'заявка принята'}',
                  zh: '${loyaltyTierLabel(context, gift.tier)}等级礼品：${gift.status == 'fulfilled' ? '已发放' : '已受理申请'}',
                ),
              ),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_message!),
            ),
        ],
      ),
    );
  }
}
