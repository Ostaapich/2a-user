import 'package:twoalogisticcabineuser/src/features/training/presentation/training_target.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/app_colors.dart';
import '../../../core/ui/app_layout.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/ui/blurred_modal_bottom_sheet.dart';
import '../../../core/utils/locale_text.dart';
import '../../payments/data/payment_operator_status.dart';
import '../../payments/presentation/payment_operator_sleeping_notice.dart';
import '../../purchase_blanks/presentation/purchase_blank_ui.dart';
import '../data/self_buyout_models.dart';
import '../data/self_buyout_service.dart';
import 'self_buyout_alipay_qr_instruction_sheet.dart';
import 'self_buyout_create_sheet.dart';
import 'self_buyout_detail_sheet.dart';
import 'self_buyout_qr_sheet.dart';
import 'self_buyout_ui.dart';
import 'self_buyout_verification_sheet.dart';

class SelfBuyoutScreen extends ConsumerStatefulWidget {
  const SelfBuyoutScreen({super.key});

  @override
  ConsumerState<SelfBuyoutScreen> createState() => _SelfBuyoutScreenState();
}

class _SelfBuyoutScreenState extends ConsumerState<SelfBuyoutScreen> {
  Timer? _verificationStatusTimer;
  String _requestView = 'all';

  @override
  void initState() {
    super.initState();
    _verificationStatusTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      final current = ref.read(selfBuyoutAvailabilityProvider).asData?.value;
      if (current?.verification.isPending == true ||
          current?.verification.isRejected == true) {
        ref.invalidate(selfBuyoutAvailabilityProvider);
      }
    });
  }

  @override
  void dispose() {
    _verificationStatusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_requestView != 'action') {
      _requestView = 'all';
    }
    final requestsAsync = ref.watch(selfBuyoutRequestsProvider);
    final availabilityAsync = ref.watch(selfBuyoutAvailabilityProvider);
    final availability = availabilityAsync.asData?.value;
    final operatorStatus = paymentOperatorStatusOrWorking(
      ref.watch(paymentOperatorStatusProvider),
    );
    final topPad = AppLayout.topBarTotalHeight(context);
    final bottomPad = AppLayout.bottomScrollPadding(context);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(selfBuyoutRequestsProvider);
        ref.invalidate(selfBuyoutAvailabilityProvider);
        ref.invalidate(paymentOperatorStatusProvider);
        await Future.wait([
          ref.read(selfBuyoutRequestsProvider.future),
          ref.read(selfBuyoutAvailabilityProvider.future),
          ref.read(paymentOperatorStatusProvider.future),
        ]);
      },
      color: context.brandPrimary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, topPad * 0.7 + 16, 16, bottomPad + 16),
        children: [
          const PurchaseBlankPageHeader(title: 'Самовыкуп'),
          const SizedBox(height: 12),
          _hero(context, ref, availability, operatorStatus.sleeping),
          if (availabilityAsync.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                children: [
                  Text(
                    tr(
                      context,
                      ru: 'Не удалось проверить доступность самовыкупа. Это не означает запрет услуги.',
                      zh: '无法确认自助代购是否可用，这不代表服务被禁止。',
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(selfBuyoutAvailabilityProvider),
                    child: Text(
                      tr(context, ru: 'Повторить проверку', zh: '重新检查'),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          requestsAsync.when(
            data: (rows) => _list(context, ref, rows),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => _errorBox(context, ref),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _hero(
    BuildContext context,
    WidgetRef ref,
    SelfBuyoutAvailability? availability,
    bool operatorsSleeping,
  ) {
    final canCreate = availability?.available ?? false;
    final verification = availability?.verification;
    final reason = availability?.reason;
    final showVerification =
        verification != null &&
        verification.required &&
        !verification.isApproved &&
        (reason == 'verification_required' ||
            reason == 'verification_pending' ||
            reason == 'verification_rejected');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: context.brandGradient,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: context.brandPrimary.withValues(alpha: 0.20),
            blurRadius: 26,
            spreadRadius: -14,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(context, ru: 'Помощь в самовыкупе', zh: '自助代购协助'),
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'Gilroy',
              fontSize: 22,
              height: 1.1,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              context,
              ru: 'Мы помогаем вам самостоятельно выкупить товары с нужных площадок, предоставляя нужное количество юаней.',
              zh: '我们为您提供所需数量的人民币，帮助您自行在平台购买商品。',
            ),
            style: const TextStyle(
              color: Color(0xE6FFFFFF),
              fontFamily: 'Gilroy',
              fontSize: 13.5,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          if (showVerification)
            _verificationPanel(context, ref, verification)
          else if (operatorsSleeping)
            const TrainingTarget(
              id: 'selfbuyout.operators.unavailable',
              child: PaymentOperatorSleepingNotice(
                onGradient: true,
                compact: true,
              ),
            )
          else
            _heroButton(context, ref, canCreate, availability),
          if (!showVerification &&
              !operatorsSleeping &&
              !canCreate &&
              _availabilityMessage(context, availability) != null) ...[
            const SizedBox(height: 10),
            Text(
              _availabilityMessage(context, availability)!,
              style: const TextStyle(
                color: Color(0xE6FFFFFF),
                fontFamily: 'Gilroy',
                fontSize: 12.5,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _verificationPanel(
    BuildContext context,
    WidgetRef ref,
    SelfBuyoutVerification verification,
  ) {
    final rejected = verification.isRejected;
    final pending = verification.isPending;
    final title = pending
        ? tr(context, ru: 'Данные отправлены на проверку', zh: '资料已提交审核')
        : rejected
        ? tr(context, ru: 'Проверка не пройдена', zh: '验证未通过')
        : tr(context, ru: 'Нужна проверка', zh: '需要验证');
    final description = pending
        ? tr(
            context,
            ru: 'Ожидаем решения платёжного партнёра. Статус обновится автоматически.',
            zh: '正在等待支付合作方审核，状态会自动更新。',
          )
        : rejected
        ? (verification.rejectionReason?.trim().isNotEmpty == true
              ? verification.rejectionReason!
              : tr(
                  context,
                  ru: 'Партнёр не подтвердил доступ к самовыкупу.',
                  zh: '合作方未批准自助代购权限。',
                ))
        : tr(
            context,
            ru: 'Перед первой заявкой подтвердите ФИО, телефон и Telegram.',
            zh: '首次申请前，请验证姓名、电话和 Telegram。',
          );
    final accent = rejected
        ? const Color(0xFFFFD1D1)
        : pending
        ? const Color(0xFFFFE0AD)
        : Colors.white;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                pending
                    ? Icons.schedule_rounded
                    : rejected
                    ? Icons.gpp_bad_rounded
                    : Icons.verified_user_outlined,
                color: accent,
                size: 21,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: accent,
                        fontFamily: 'Gilroy',
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Color(0xE6FFFFFF),
                        fontFamily: 'Gilroy',
                        fontSize: 12.5,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!pending && verification.canSubmit) ...[
            const SizedBox(height: 12),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _openVerification(context, ref, verification),
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        rejected
                            ? Icons.refresh_rounded
                            : Icons.verified_rounded,
                        color: context.brandPrimary,
                        size: 19,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        rejected
                            ? tr(context, ru: 'Отправить повторно', zh: '重新提交')
                            : tr(context, ru: 'Пройти проверку', zh: '开始验证'),
                        style: TextStyle(
                          color: context.brandPrimary,
                          fontFamily: 'Gilroy',
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? _availabilityMessage(
    BuildContext context,
    SelfBuyoutAvailability? availability,
  ) {
    final reason = availability?.reason;
    if (reason == 'rate_stale' ||
        reason == 'no_rate' ||
        reason == 'rate_invalid') {
      return tr(
        context,
        ru: 'Создать заявку на самовыкуп можно будет после обновления курсов валют. Ожидайте обновления курсов.',
        zh: '汇率更新后即可创建自助代购申请，请等待汇率更新。',
      );
    }
    if (reason == 'client_disabled') {
      return availability?.disabledReason ??
          tr(
            context,
            ru: 'Самовыкуп для вашего аккаунта временно недоступен.',
            zh: '您的账户暂时无法使用自助代购。',
          );
    }
    if (reason == 'feature_disabled') {
      return tr(context, ru: 'Самовыкуп временно недоступен.', zh: '自助代购暂不可用。');
    }
    return null;
  }

  Future<void> _openVerification(
    BuildContext context,
    WidgetRef ref,
    SelfBuyoutVerification verification,
  ) async {
    final submitted = await showBlurredModalBottomSheet<SelfBuyoutVerification>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (_) => SelfBuyoutVerificationSheet(verification: verification),
    );
    if (submitted == null || !context.mounted) return;
    ref.invalidate(selfBuyoutAvailabilityProvider);
    AppToast.show(
      context,
      tr(context, ru: 'Данные отправлены на проверку', zh: '资料已提交审核'),
    );
  }

  Widget _heroButton(
    BuildContext context,
    WidgetRef ref,
    bool canCreate,
    SelfBuyoutAvailability? availability,
  ) {
    final VoidCallback? openCreate = canCreate
        ? () => _openCreate(context, ref, availability!)
        : null;
    return TrainingTarget(
      id: canCreate ? 'selfbuyout.create' : 'selfbuyout.create.unavailable',
      onActivate: openCreate,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: openCreate,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, color: context.brandPrimary, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    canCreate
                        ? tr(context, ru: 'Создать заявку', zh: '创建申请')
                        : tr(context, ru: 'Временно недоступно', zh: '暂不可用'),
                    style: TextStyle(
                      color: context.brandPrimary,
                      fontFamily: 'Gilroy',
                      fontSize: 15,
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

  Widget _list(
    BuildContext context,
    WidgetRef ref,
    List<SelfBuyoutRequest> rows,
  ) {
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
        decoration: PurchaseBlankUi.cardDecoration(),
        child: Column(
          children: [
            const Icon(
              Icons.inbox_rounded,
              size: 40,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 10),
            Text(
              tr(context, ru: 'Заявок пока нет', zh: '暂无申请'),
              style: PurchaseBlankUi.bodyStyle,
            ),
          ],
        ),
      );
    }
    final sorted = [...rows]
      ..sort((a, b) {
        bool needsAction(SelfBuyoutRequest r) =>
            r.status == 'new' || r.status == 'awaiting_payment';
        final priority = (needsAction(b) ? 1 : 0) - (needsAction(a) ? 1 : 0);
        return priority != 0
            ? priority
            : (b.createdAt ?? DateTime(1970)).compareTo(
                a.createdAt ?? DateTime(1970),
              );
      });
    final visible = sorted
        .where(
          (r) => switch (_requestView) {
            'action' => r.status == 'new' || r.status == 'awaiting_payment',
            _ => true,
          },
        )
        .toList(growable: false);
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final entry in [
                ('action', tr(context, ru: 'Требуют действия', zh: '待处理')),
                ('all', tr(context, ru: 'Все', zh: '全部')),
              ])
                ChoiceChip(
                  label: Text(entry.$2),
                  selected: _requestView == entry.$1,
                  backgroundColor: Colors.white,
                  selectedColor: context.brandPrimary,
                  surfaceTintColor: Colors.transparent,
                  checkmarkColor: Colors.white,
                  showCheckmark: true,
                  elevation: 0,
                  pressElevation: 0,
                  shape: const StadiumBorder(),
                  side: BorderSide(
                    color: _requestView == entry.$1
                        ? context.brandPrimary
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 9,
                  ),
                  labelPadding: EdgeInsets.zero,
                  labelStyle: TextStyle(
                    color: _requestView == entry.$1
                        ? Colors.white
                        : AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 13,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                  onSelected: (_) => setState(() => _requestView = entry.$1),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              tr(context, ru: 'В этом разделе заявок нет', zh: '此分类暂无申请'),
            ),
          ),
        for (final r in visible) ...[
          _RequestCard(
            request: r,
            trainingTarget: identical(r, visible.first),
            onTap: () => _onCardTap(context, ref, r),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _errorBox(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: PurchaseBlankUi.cardDecoration(),
      child: Column(
        children: [
          Text(
            tr(context, ru: 'Не удалось загрузить заявки', zh: '无法加载申请'),
            style: PurchaseBlankUi.bodyStyle,
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => ref.invalidate(selfBuyoutRequestsProvider),
            child: Text(tr(context, ru: 'Повторить', zh: '重试')),
          ),
        ],
      ),
    );
  }

  Future<void> _openCreate(
    BuildContext context,
    WidgetRef ref,
    SelfBuyoutAvailability availability,
  ) async {
    if (!await _ensurePaymentOperatorsWorking(context, ref)) return;
    if (!context.mounted) return;

    var alipayTopUpExperienced = availability.alipayTopUpExperienced;
    if (availability.showFirstExchangeOnboarding) {
      final answer = await showBlurredModalBottomSheet<bool>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.22),
        builder: (_) => SelfBuyoutAlipayQrInstructionSheet(
          initialAlipayTopUpExperienced: alipayTopUpExperienced,
        ),
      );
      if (answer == null || !context.mounted) return;
      alipayTopUpExperienced = answer;
    }
    if (availability.firstExchangeActive && alipayTopUpExperienced == null) {
      AppToast.show(
        context,
        tr(
          context,
          ru: 'Ответьте на вопрос об опыте пополнения Alipay',
          zh: '请回答支付宝充值经验问题',
        ),
        isError: true,
      );
      return;
    }

    final created = await showBlurredModalBottomSheet<SelfBuyoutRequest>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (_) => SelfBuyoutCreateSheet(
        availability: availability,
        alipayTopUpExperienced: alipayTopUpExperienced,
      ),
    );
    if (created != null && context.mounted) {
      ref.invalidate(selfBuyoutRequestsProvider);
      await _openQr(context, ref, created);
    }
  }

  Future<void> _onCardTap(
    BuildContext context,
    WidgetRef ref,
    SelfBuyoutRequest r,
  ) async {
    final action = await showBlurredModalBottomSheet<SelfBuyoutDetailAction>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (_) => SelfBuyoutDetailSheet(request: r),
    );
    if (!context.mounted) return;
    switch (action) {
      case SelfBuyoutDetailAction.continuePayment:
        await _openQr(context, ref, r);
      case SelfBuyoutDetailAction.correctRequisites:
        await _correctRequisites(context, ref, r);
      case SelfBuyoutDetailAction.cancel:
        await _cancelRequest(context, ref, r);
      case null:
        break;
    }
  }

  Future<void> _cancelRequest(
    BuildContext context,
    WidgetRef ref,
    SelfBuyoutRequest request,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          tr(context, ru: 'Отменить заявку?', zh: '取消申请？'),
          style: const TextStyle(
            fontFamily: 'Gilroy',
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          tr(
            context,
            ru: 'Заявка будет отменена и останется в истории. Восстановить отменённую заявку нельзя.',
            zh: '申请将被取消并保留在历史记录中，取消后无法恢复。',
          ),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontFamily: 'Gilroy',
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(tr(context, ru: 'Оставить заявку', zh: '保留申请')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
            ),
            child: Text(tr(context, ru: 'Отменить заявку', zh: '取消申请')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final cancelled = await ref
          .read(selfBuyoutServiceProvider)
          .cancel(request.id);
      if (!context.mounted) return;
      if (!cancelled) throw StateError('Cancellation failed');
      ref.invalidate(selfBuyoutRequestsProvider);
      AppToast.show(context, tr(context, ru: 'Заявка отменена', zh: '申请已取消'));
    } catch (_) {
      if (!context.mounted) return;
      AppToast.show(
        context,
        tr(context, ru: 'Не удалось отменить заявку', zh: '无法取消申请'),
        isError: true,
      );
    }
  }

  Future<void> _correctRequisites(
    BuildContext context,
    WidgetRef ref,
    SelfBuyoutRequest request,
  ) async {
    final corrected = await showBlurredModalBottomSheet<SelfBuyoutRequest>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (_) =>
          SelfBuyoutCreateSheet.correctRequisites(correctionRequest: request),
    );
    if (!context.mounted) return;
    if (corrected != null) {
      ref.invalidate(selfBuyoutRequestsProvider);
    }
  }

  Future<void> _openQr(
    BuildContext context,
    WidgetRef ref,
    SelfBuyoutRequest r,
  ) async {
    if (r.activePaymentId == null &&
        !await _ensurePaymentOperatorsWorking(context, ref)) {
      return;
    }
    if (!context.mounted) return;
    final changed = await showBlurredModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (_) => SelfBuyoutQrSheet(
        requestId: r.id,
        requestNumber: r.requestNumber,
        cnyAmount: r.requestedCnyAmount,
        hasExistingPayment: r.activePaymentId != null,
      ),
    );
    if (!context.mounted) return;
    if (changed == true) {
      ref.invalidate(selfBuyoutRequestsProvider);
    }
  }

  Future<bool> _ensurePaymentOperatorsWorking(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final current = ref.read(paymentOperatorStatusProvider).asData?.value;
    final status =
        current ??
        await ref.read(paymentOperatorStatusProvider.future) ??
        PaymentOperatorStatus.workingFallback;
    if (status.working) return true;
    if (context.mounted) {
      AppToast.show(
        context,
        tr(
          context,
          ru: 'Операторы оплаты сейчас отдыхают. QR временно недоступен.',
          zh: '支付客服当前休息，二维码暂不可用。',
        ),
        isError: true,
      );
    }
    return false;
  }
}

class _RequestCard extends StatelessWidget {
  final SelfBuyoutRequest request;
  final VoidCallback onTap;
  final bool trainingTarget;

  const _RequestCard({
    required this.request,
    required this.onTap,
    required this.trainingTarget,
  });

  @override
  Widget build(BuildContext context) {
    final color = selfBuyoutStatusColor(request.status);
    final requestNumber = Text(
      request.requestNumber,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontFamily: 'Gilroy',
        fontSize: 15,
        fontWeight: FontWeight.w900,
      ),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: PurchaseBlankUi.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: trainingTarget
                        ? TrainingTarget(
                            id: 'selfbuyout.request.open',
                            onActivate: onTap,
                            child: requestNumber,
                          )
                        : requestNumber,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      selfBuyoutStatusLabel(context, request.status),
                      style: TextStyle(
                        color: color,
                        fontFamily: 'Gilroy',
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _kv(
                      tr(context, ru: 'Юани', zh: '人民币'),
                      '${formatSelfBuyoutMoney(context, request.requestedCnyAmount)} RMB',
                    ),
                  ),
                  Expanded(
                    child: _kv(
                      tr(context, ru: 'К оплате', zh: '应付'),
                      '${formatSelfBuyoutMoney(context, request.paymentRubAmount)} ₽',
                    ),
                  ),
                ],
              ),
              if (request.status == 'new' ||
                  request.status == 'awaiting_payment') ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.qr_code_2_rounded,
                      size: 15,
                      color: context.brandPrimary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tr(context, ru: 'Нажмите, чтобы оплатить', zh: '点击付款'),
                      style: TextStyle(
                        color: context.brandPrimary,
                        fontFamily: 'Gilroy',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: PurchaseBlankUi.labelStyle),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontFamily: 'Gilroy',
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
