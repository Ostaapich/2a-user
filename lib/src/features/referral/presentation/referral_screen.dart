import 'package:flutter/material.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../training/presentation/training_target.dart';
import '../../../core/branding/company_branding_provider.dart';
import '../../../core/network/api_client.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/utils/locale_text.dart';
import '../../../core/ui/app_input_decoration.dart';
import '../../../core/ui/app_layout.dart';
import '../../../core/ui/scroll_to_top_button.dart';
import '../../../core/ui/tutorial_card.dart';
import '../../../core/utils/clipboard_helper.dart';
import '../data/referral_provider.dart';

const _textColor = Color(0xFF2F2F2F);
const _mutedTextColor = Color(0x992F2F2F);

BoxDecoration _referralCardDecoration({Color color = Colors.white}) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.05),
        blurRadius: 24,
        spreadRadius: -14,
        offset: const Offset(0, 14),
      ),
    ],
  );
}

BoxDecoration _referralSoftDecoration() {
  return BoxDecoration(
    color: const Color(0xFFF8FAFC),
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: Colors.black.withValues(alpha: 0.025)),
  );
}

TextStyle get _sectionTitleStyle {
  return const TextStyle(
    color: AppColors.textPrimary,
    fontFamily: 'Gilroy',
    fontSize: 18,
    height: 22 / 18,
    fontWeight: FontWeight.w900,
    letterSpacing: -0.15,
  );
}

String _formatKg(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String _formatPercent(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

class ReferralScreen extends ConsumerStatefulWidget {
  const ReferralScreen({super.key});

  @override
  ConsumerState<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends ConsumerState<ReferralScreen> {
  final _linkCodeController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isLinking = false;

  final GlobalKey _referralInfoKey = GlobalKey();
  final GlobalKey _codeCardKey = GlobalKey();
  final GlobalKey _balanceKey = GlobalKey();

  @override
  void dispose() {
    _scrollController.dispose();
    _linkCodeController.dispose();
    super.dispose();
  }

  Future<void> _linkReferralCode() async {
    final code = _linkCodeController.text.trim().toUpperCase();
    if (code.isEmpty || _isLinking) return;

    setState(() => _isLinking = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/client/referral/link', data: {'code': code});
      if (!mounted) return;
      _linkCodeController.clear();
      ref.invalidate(referralProvider);
      _showSnackbar('Реферальный код привязан!', true);
    } catch (e) {
      if (!mounted) return;
      _showSnackbar('Ошибка привязки кода', false);
    } finally {
      if (mounted) setState(() => _isLinking = false);
    }
  }

  void _showSnackbar(String message, bool success) {
    AppToast.showFromSnackBar(
      context,
      SnackBar(
        content: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: AppToast.hide,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  success
                      ? Icons.check_circle_outline_rounded
                      : Icons.error_outline_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Gilroy',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: success
            ? context.brandPrimary
            : const Color(0xFFE53935),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          AppLayout.bottomBarObstruction(context) + 12,
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(referralProvider);
    await ref.read(referralProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final companyName = ref.watch(companyNameProvider);
    final referralAsync = ref.watch(referralProvider);
    final topPad = AppLayout.topBarTotalHeight(context);
    final bottomPad = AppLayout.bottomScrollPadding(context);

    return TutorialScreenWrapper(
      screenKey: 'referral',
      steps: [
        TutorialStep(
          icon: Icons.group_add_rounded,
          title: 'Реферальная программа',
          description:
              'Приглашайте друзей и коллег. После первой оплаты приглашённого клиента бонусные килограммы появятся на вашем балансе.',
          targetKey: _referralInfoKey,
        ),
        TutorialStep(
          icon: Icons.qr_code_rounded,
          title: 'Ваш реферальный код',
          description:
              'Скопируйте код и отправьте его другу. Он вводит код при регистрации, а вы получаете бонус после его первой оплаты.',
          targetKey: _codeCardKey,
        ),
        TutorialStep(
          icon: Icons.scale_rounded,
          title: 'Бонусный баланс',
          description:
              'Накопленные килограммы можно применить к счёту за доставку. Лимит применения указан в карточке баланса.',
          targetKey: _balanceKey,
        ),
      ],
      child: referralAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: context.brandPrimary),
        ),
        error: (e, _) => _ReferralErrorState(
          onRetry: () => ref.invalidate(referralProvider),
        ),
        data: (data) => Stack(
          children: [
            RefreshIndicator(
              onRefresh: _refresh,
              color: context.brandPrimary,
              child: ListView(
                controller: _scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  16,
                  topPad * 0.7 + 16,
                  16,
                  bottomPad + 16,
                ),
                children: [
                  const _ReferralPageHeader(),
                  const SizedBox(height: 12),
                  KeyedSubtree(
                    key: _referralInfoKey,
                    child: _ReferralHeroCard(data: data),
                  ),
                  const SizedBox(height: 14),
                  KeyedSubtree(
                    key: _codeCardKey,
                    child: KeyedSubtree(
                      key: _balanceKey,
                      child: _CodeCard(
                        data: data,
                        onCopied: () => _showSnackbar('Код скопирован', true),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const _ReferralIntroCard(),
                  const SizedBox(height: 14),
                  if (data.referredByName == null)
                    _LinkCodeCard(
                      controller: _linkCodeController,
                      isLinking: _isLinking,
                      onLink: _linkReferralCode,
                      companyName: companyName,
                    )
                  else
                    _InfoCard(
                      icon: Icons.person_outline_rounded,
                      title: 'Вас пригласил',
                      value:
                          '${data.referredByName} (${data.referredByCode ?? ''})',
                    ),
                  const SizedBox(height: 14),
                  _SectionCard(
                    title: 'Ваши рефералы',
                    trailing: '${data.referrals.length}',
                    child: data.referrals.isEmpty
                        ? const _EmptyState(
                            icon: Icons.group_add_rounded,
                            title: 'Рефералов пока нет',
                            description:
                                'Скопируйте код выше и отправьте его друзьям или коллегам.',
                          )
                        : Column(
                            children: [
                              for (
                                var i = 0;
                                i < data.referrals.length;
                                i++
                              ) ...[
                                if (i > 0) const SizedBox(height: 10),
                                _ReferralEntryTile(entry: data.referrals[i]),
                              ],
                            ],
                          ),
                  ),
                  const SizedBox(height: 14),
                  _SectionCard(
                    title: 'История бонусов',
                    trailing: '${data.transactions.length}',
                    child: data.transactions.isEmpty
                        ? const _EmptyState(
                            icon: Icons.history_rounded,
                            title: 'История пока пустая',
                            description:
                                'Начисления появятся после первых оплат приглашённых клиентов.',
                          )
                        : Column(
                            children: [
                              for (
                                var i = 0;
                                i < data.transactions.length;
                                i++
                              ) ...[
                                if (i > 0) const SizedBox(height: 10),
                                _TransactionTile(
                                  transaction: data.transactions[i],
                                ),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
            ScrollToTopButton(controller: _scrollController),
          ],
        ),
      ),
    );
  }
}

class _ReferralPageHeader extends StatelessWidget {
  const _ReferralPageHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 46,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.black.withValues(alpha: 0.035),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 18,
                    spreadRadius: -12,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Реферальная программа',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Gilroy',
              fontSize: 26,
              height: 1.05,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReferralHeroCard extends StatelessWidget {
  final ReferralData data;

  const _ReferralHeroCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: context.brandGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: context.brandPrimary.withValues(alpha: 0.22),
            blurRadius: 28,
            spreadRadius: -12,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            const Positioned.fill(child: _ReferralHeaderGlowBackdrop()),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                        child: const Icon(
                          Icons.card_giftcard_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Приглашайте и экономьте',
                              style: TextStyle(
                                color: Colors.white,
                                fontFamily: 'Gilroy',
                                fontSize: 24,
                                height: 1.04,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                              ),
                            ),
                            SizedBox(height: 7),
                            Text(
                              'Бонусные килограммы можно применять при оплате доставки.',
                              style: TextStyle(
                                color: Color(0xE6FFFFFF),
                                fontFamily: 'Gilroy',
                                fontSize: 13,
                                height: 1.2,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ReferralHeroChip(
                    icon: Icons.info_outline_rounded,
                    label: tr(
                      context,
                      ru: 'Бонус после первой оплаты друга',
                      zh: '好友首次付款后获得奖励',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReferralHeroChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ReferralHeroChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'Gilroy',
              fontSize: 12.5,
              height: 1,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferralHeaderGlowBackdrop extends StatefulWidget {
  const _ReferralHeaderGlowBackdrop();

  @override
  State<_ReferralHeaderGlowBackdrop> createState() =>
      _ReferralHeaderGlowBackdropState();
}

class _ReferralHeaderGlowBackdropState
    extends State<_ReferralHeaderGlowBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final wave = Curves.easeInOutCubic.transform(_controller.value);
            final shift = (wave * 2) - 1;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  right: -62,
                  top: -58,
                  child: Transform.translate(
                    offset: Offset(-10 * shift, 6 * shift),
                    child: _ReferralGlowCircle(
                      size: 154,
                      color: Colors.white.withValues(alpha: 0.13),
                    ),
                  ),
                ),
                Positioned(
                  right: 22,
                  bottom: -68,
                  child: Transform.translate(
                    offset: Offset(9 * shift, -7 * shift),
                    child: _ReferralGlowCircle(
                      size: 152,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                Positioned(
                  right: -14,
                  bottom: 16,
                  child: Transform.translate(
                    offset: Offset(5 * shift, -4 * shift),
                    child: _ReferralGlowCircle(
                      size: 82,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ReferralGlowCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _ReferralGlowCircle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _CodeCard extends StatelessWidget {
  final ReferralData data;
  final VoidCallback onCopied;

  const _CodeCard({required this.data, required this.onCopied});

  @override
  Widget build(BuildContext context) {
    final referralCode = data.referralCode;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _referralCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionTitleRow(
            icon: Icons.qr_code_rounded,
            title: 'Ваш код для приглашений',
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.brandPrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: context.brandPrimary.withValues(alpha: 0.10),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    referralCode ?? 'Код пока не доступен',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: referralCode == null
                          ? _mutedTextColor
                          : AppColors.textPrimary,
                      fontFamily: 'Gilroy',
                      fontSize: referralCode == null ? 15 : 27,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                      letterSpacing: referralCode == null ? 0 : 2.1,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (referralCode != null)
                  TrainingTarget(
                    id: 'referral.copy',
                    child: Material(
                      color: context.brandPrimary,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        onTap: () async {
                          final copied = await AppClipboard.copyText(
                            referralCode,
                          );
                          if (!context.mounted) return;
                          if (copied) {
                            onCopied();
                          } else {
                            AppToast.showFromSnackBar(
                              context,
                              SnackBar(
                                content: const Text('Не удалось скопировать'),
                                backgroundColor: Colors.red.shade700,
                              ),
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: const SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(
                            Icons.copy_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ReferralMetric(
                  icon: Icons.scale_rounded,
                  label: 'Баланс',
                  value: '${_formatKg(data.referralKgBalance)} кг',
                  color: context.brandPrimary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ReferralMetric(
                  icon: Icons.percent_rounded,
                  label: 'Лимит',
                  value: '${_formatPercent(data.maxBonusPercent)}%',
                  color: context.brandPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ReferralMetric(
            icon: Icons.people_alt_rounded,
            label: 'Приглашённых клиентов',
            value: '${data.referrals.length}',
            color: context.brandPrimary,
            wide: true,
          ),
        ],
      ),
    );
  }
}

class _ReferralMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool wide;

  const _ReferralMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: wide ? 56 : 72),
      padding: const EdgeInsets.all(10),
      decoration: _referralSoftDecoration(),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(13),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'Gilroy',
                    fontSize: 12,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                TrainingTarget(
                  id: label == 'Баланс'
                      ? 'referral.balance'
                      : 'referral.metric.$label',
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontFamily: 'Gilroy',
                      fontSize: 18,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferralIntroCard extends StatelessWidget {
  const _ReferralIntroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _referralCardDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitleRow(
            icon: Icons.route_rounded,
            title: 'Как это работает',
          ),
          const SizedBox(height: 14),
          _HowItWorksStep(
            number: '1',
            title: 'Отправьте код',
            description: 'Скопируйте код и передайте его другу или клиенту.',
            color: context.brandPrimary,
          ),
          const SizedBox(height: 10),
          _HowItWorksStep(
            number: '2',
            title: 'Клиент регистрируется',
            description: 'При регистрации он указывает ваш реферальный код.',
            color: context.brandPrimary,
          ),
          const SizedBox(height: 10),
          _HowItWorksStep(
            number: '3',
            title: 'Вы получаете бонус',
            description:
                'После первой оплаты бонусные килограммы появляются на балансе.',
            color: context.brandPrimary,
          ),
        ],
      ),
    );
  }
}

class _HowItWorksStep extends StatelessWidget {
  final String number;
  final String title;
  final String description;
  final Color color;

  const _HowItWorksStep({
    required this.number,
    required this.title,
    required this.description,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _referralSoftDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Text(
              number,
              style: TextStyle(
                color: color,
                fontFamily: 'Gilroy',
                fontSize: 15,
                height: 1,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 14.5,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'Gilroy',
                    fontSize: 13,
                    height: 1.22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String? trailing;
  final Widget child;

  const _SectionCard({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _referralCardDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: _sectionTitleStyle)),
              if (trailing != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: context.brandPrimary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    trailing!,
                    style: TextStyle(
                      color: context.brandPrimary,
                      fontFamily: 'Gilroy',
                      fontSize: 12,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _SectionTitleRow extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitleRow({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: context.brandPrimary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, size: 22, color: context.brandPrimary),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: _sectionTitleStyle)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _referralSoftDecoration(),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.brandPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 23, color: context.brandPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 14.5,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'Gilroy',
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkCodeCard extends StatelessWidget {
  final TextEditingController controller;
  final bool isLinking;
  final VoidCallback onLink;
  final String companyName;

  const _LinkCodeCard({
    required this.controller,
    required this.isLinking,
    required this.onLink,
    required this.companyName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _referralCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitleRow(
            icon: Icons.link_rounded,
            title: 'Вас пригласили?',
          ),
          const SizedBox(height: 10),
          Text(
            'Введите код человека, который пригласил вас в $companyName. После условий программы бонус будет начислен автоматически.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Gilroy',
              fontSize: 13.5,
              height: 1.25,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.characters,
                  decoration: appInputDecoration(
                    context,
                    hintText: 'ABC123',
                    fillColor: const Color(0xFFF8FAFC),
                    borderColor: const Color(0xFFE1E5ED),
                    focusedBorderColor: context.brandPrimary,
                    focusedWidth: 1.6,
                    radius: 18,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 15,
                    ),
                  ),
                  style: const TextStyle(
                    color: _textColor,
                    fontFamily: 'Gilroy',
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: isLinking ? null : onLink,
                  style: FilledButton.styleFrom(
                    backgroundColor: context.brandPrimary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: context.brandPrimary.withValues(
                      alpha: 0.35,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    elevation: 0,
                  ),
                  child: isLinking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'ОК',
                          style: TextStyle(
                            fontFamily: 'Gilroy',
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _referralCardDecoration(),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: context.brandPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(17),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: context.brandPrimary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'Gilroy',
                    fontSize: 12,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 15,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferralEntryTile extends StatelessWidget {
  final ReferralEntry entry;

  const _ReferralEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final initial =
        (entry.fullName?.isNotEmpty == true
                ? entry.fullName!.characters.first
                : '?')
            .toUpperCase();
    final joinedAt = entry.joinedAt;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _referralSoftDecoration(),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.brandPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              initial,
              style: TextStyle(
                color: context.brandPrimary,
                fontFamily: 'Gilroy',
                fontSize: 17,
                height: 1,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.fullName ?? 'Без имени',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 15,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _MiniChip(
                      icon: Icons.receipt_long_rounded,
                      label: '${entry.paidInvoicesCount} счетов',
                    ),
                    if (joinedAt != null)
                      _MiniChip(
                        icon: Icons.calendar_today_rounded,
                        label: DateFormat('dd.MM.yyyy').format(joinedAt),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (entry.earnedKg > 0) ...[
            const SizedBox(width: 8),
            _KgAmountPill(
              value: '+${_formatKg(entry.earnedKg)} кг',
              color: Colors.green.shade700,
            ),
          ],
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final ReferralTransaction transaction;

  const _TransactionTile({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd.MM.yyyy');
    final isPositive =
        transaction.type == 'earned' ||
        transaction.type == 'referee_bonus' ||
        (transaction.type == 'admin_credit' && transaction.kgAmount > 0);
    final color = isPositive ? Colors.green.shade700 : Colors.orange.shade700;
    final prefix = isPositive ? '+' : '-';

    String typeLabel;
    IconData icon;
    switch (transaction.type) {
      case 'earned':
        typeLabel = 'Начислено за реферала';
        icon = Icons.add_circle_outline_rounded;
        break;
      case 'used':
        typeLabel = 'Использовано в счёте';
        icon = Icons.remove_circle_outline_rounded;
        break;
      case 'referee_bonus':
        typeLabel = 'Стартовый бонус';
        icon = Icons.card_giftcard_rounded;
        break;
      case 'expired':
        typeLabel = 'Истёк срок';
        icon = Icons.timer_off_outlined;
        break;
      case 'admin_credit':
        typeLabel = transaction.kgAmount > 0
            ? 'Начислено администратором'
            : 'Списано администратором';
        icon = transaction.kgAmount > 0
            ? Icons.admin_panel_settings_rounded
            : Icons.remove_circle_outline_rounded;
        break;
      default:
        typeLabel = transaction.type;
        icon = Icons.info_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _referralSoftDecoration(),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  typeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 14.5,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (transaction.description != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    transaction.description!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontFamily: 'Gilroy',
                      fontSize: 12.5,
                      height: 1.18,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 6),
                _MiniChip(
                  icon: Icons.calendar_today_rounded,
                  label: dateFormat.format(transaction.createdAt),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _KgAmountPill(
            value: '$prefix${_formatKg(transaction.kgAmount.abs())} кг',
            color: color,
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MiniChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Gilroy',
              fontSize: 11.5,
              height: 1,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _KgAmountPill extends StatelessWidget {
  final String value;
  final Color color;

  const _KgAmountPill({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.13)),
      ),
      child: Text(
        value,
        style: TextStyle(
          fontFamily: 'Gilroy',
          fontSize: 12,
          height: 1,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

class _ReferralErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ReferralErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: _referralCardDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.error_outline,
                  size: 30,
                  color: Colors.red.shade400,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Не удалось загрузить данные',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'Gilroy',
                  fontSize: 18,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Проверьте подключение и попробуйте ещё раз.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'Gilroy',
                  fontSize: 13,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: context.brandPrimary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                ),
                child: const Text(
                  'Повторить',
                  style: TextStyle(
                    fontFamily: 'Gilroy',
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
