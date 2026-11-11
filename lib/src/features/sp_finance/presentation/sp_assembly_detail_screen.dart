import 'package:twoalogisticcabineuser/src/core/media/authenticated_media.dart';
import 'package:flutter/material.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/network/api_config.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/ui/app_layout.dart';
import '../../../core/ui/scroll_to_top_button.dart';
import '../../../core/ui/tutorial_card.dart';
import '../../../core/utils/clipboard_helper.dart';
import '../../../core/utils/locale_text.dart';
import '../../assemblies/domain/box.dart';
import '../data/sp_models.dart';
import '../data/sp_provider.dart';
import 'sp_finance_ui.dart';

/// Показывает стилизованный SnackBar в едином дизайне приложения
void _showStyledSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
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
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
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
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError ? const Color(0xFFE53935) : context.brandPrimary,
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

class SpAssemblyDetailScreen extends ConsumerStatefulWidget {
  final int assemblyId;

  const SpAssemblyDetailScreen({super.key, required this.assemblyId});

  @override
  ConsumerState<SpAssemblyDetailScreen> createState() =>
      _SpAssemblyDetailScreenState();
}

class _SpAssemblyDetailScreenState
    extends ConsumerState<SpAssemblyDetailScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(spAssembliesControllerProvider.notifier).loadAssemblies();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(spAssembliesControllerProvider);
    final topPad = AppLayout.topBarTotalHeight(context);
    final bottomPad = AppLayout.bottomScrollPadding(context);
    final assembly = _firstWhereOrNull<SpAssembly>(
      state.assemblies,
      (a) => a.id == widget.assemblyId,
    );
    if (assembly == null) {
      if (state.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                topPad * 0.7 + 16,
                16,
                bottomPad,
              ),
              children: [
                SpPageHeader(
                  title: tr(
                    context,
                    ru: state.error == null
                        ? 'Сборка не найдена'
                        : 'Не удалось загрузить сборку',
                    zh: state.error == null ? '未找到集运' : '无法加载集运',
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: SpFinanceUi.cardDecoration(),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: context.brandPrimary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.info_outline_rounded,
                          color: context.brandPrimary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Сборка больше не найдена. Обновите список СП и попробуйте открыть её снова.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontFamily: 'Gilroy',
                            fontSize: 13,
                            height: 1.24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
              onPressed: () => ref
                  .read(spAssembliesControllerProvider.notifier)
                  .loadAssemblies(),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(
                tr(context, ru: 'Обновить данные сборки', zh: '刷新集运数据'),
              ),
            ),
          ),
        ],
      );
    }

    return TutorialScreenWrapper(
      screenKey: 'sp_assembly_detail',
      steps: const [
        TutorialStep(
          icon: Icons.group_rounded,
          title: 'Участники сборки',
          description:
              'Список всех участников совместной покупки с их треками, весом и долей в общем счёте.',
        ),
        TutorialStep(
          icon: Icons.calculate_rounded,
          title: 'Финансы',
          description:
              'Итоговая сумма к оплате для каждого участника рассчитывается автоматически по весу и тарифу.',
        ),
        TutorialStep(
          icon: Icons.edit_rounded,
          title: 'Редактирование трека',
          description:
              'Нажмите на трек, чтобы заполнить СП-данные: имя участника, цену в юанях и чистый вес.',
        ),
        TutorialStep(
          icon: Icons.check_circle_outline_rounded,
          title: 'Отметить оплату',
          description:
              'Чекбокс «Оплачено» рядом с участником — отметьте, когда получите оплату от конкретного человека.',
        ),
        TutorialStep(
          icon: Icons.copy_rounded,
          title: 'Скопировать для отправки',
          description:
              '«Скопировать для отправки» формирует текст с суммой для участника — удобно отправить в мессенджер.',
        ),
      ],
      child: Stack(
        children: [
          RefreshIndicator(
            color: context.brandPrimary,
            onRefresh: () async {
              await ref
                  .read(spAssembliesControllerProvider.notifier)
                  .loadAssemblies();
            },
            child: ListView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                16,
                topPad * 0.7 + 16,
                16,
                bottomPad + 16,
              ),
              children: [
                SpPageHeader(title: assembly.displayName),
                const SizedBox(height: 15),
                _AssemblySummaryCard(assembly: assembly),
                const SizedBox(height: 15),
                _StatsSection(assembly: assembly),
                const SizedBox(height: 15),
                if (assembly.boxes.isNotEmpty) ...[
                  _BoxesSection(assembly: assembly),
                  const SizedBox(height: 15),
                ],
                _ParticipantsSection(assembly: assembly),
                const SizedBox(height: 15),
                _TracksSection(assembly: assembly),
              ],
            ),
          ),
          ScrollToTopButton(controller: _scrollController),
        ],
      ),
    );
  }

  T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T item) test) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

class _AssemblySummaryCard extends StatelessWidget {
  final SpAssembly assembly;

  const _AssemblySummaryCard({required this.assembly});

  @override
  Widget build(BuildContext context) {
    final stats = assembly.stats;
    final paidCount = stats.participants.where((p) => p.isPaid).length;
    final totalParticipants = stats.participants.length;
    final unfilledTracks = stats.tracksTotal - stats.tracksWithSP;
    final createdDate = DateFormat('dd.MM.yyyy').format(assembly.createdAt);
    final statusText = assembly.statusDisplayName;

    return SpAnimatedHeroSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                  Icons.groups_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Совместная покупка',
                      style: TextStyle(
                        color: Color(0xE6FFFFFF),
                        fontFamily: 'Gilroy',
                        fontSize: 12.5,
                        height: 1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      assembly.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Gilroy',
                        fontSize: 24,
                        height: 1.04,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'Создана $createdDate',
                      style: const TextStyle(
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SpHeroChip(label: statusText),
              SpHeroChip(
                icon: Icons.people_rounded,
                label: '$totalParticipants участников',
              ),
              SpHeroChip(
                icon: paidCount == totalParticipants && totalParticipants > 0
                    ? Icons.check_circle_rounded
                    : Icons.payments_rounded,
                label: 'Оплата $paidCount/$totalParticipants',
              ),
              SpHeroChip(
                icon: unfilledTracks > 0
                    ? Icons.warning_rounded
                    : Icons.verified_rounded,
                label: unfilledTracks > 0
                    ? 'Без СП: $unfilledTracks'
                    : 'Треки заполнены',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InlineStatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _InlineStatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: SpFinanceUi.labelStyle.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsSection extends StatelessWidget {
  final SpAssembly assembly;

  const _StatsSection({required this.assembly});

  @override
  Widget build(BuildContext context) {
    final stats = assembly.stats;

    // Получаем данные из счета
    final invoice = assembly.invoices.isNotEmpty ? assembly.invoices[0] : null;
    final deliveryCostRub = invoice?.deliveryCostRub ?? 0;
    final grossWeightKg = stats.grossWeightKg ?? invoice?.weight ?? 0;
    final netWeightKg = stats.totalNetWeightKg;

    // Расчет стоимости за кг
    final costPerKgGross = grossWeightKg > 0
        ? deliveryCostRub / grossWeightKg
        : 0.0;
    final costPerKgNet = netWeightKg > 0 ? deliveryCostRub / netWeightKg : 0.0;

    // Проверка на нераспределенные треки
    final hasUndistributed = stats.tracksWithSP < stats.tracksTotal;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.analytics_rounded,
            title: 'Финансы и вес',
            trailing: hasUndistributed ? 'есть нераспределённые' : null,
            trailingColor: Colors.orange.shade700,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetricTile(
                    width: itemWidth,
                    icon: Icons.people_rounded,
                    label: 'Участники',
                    value: '${stats.participants.length}',
                  ),
                  _MetricTile(
                    width: itemWidth,
                    icon: Icons.shopping_bag_rounded,
                    label: 'Треки СП',
                    value: '${stats.tracksWithSP}/${stats.tracksTotal}',
                    color: hasUndistributed ? Colors.orange.shade700 : null,
                  ),
                  _MetricTile(
                    width: itemWidth,
                    icon: Icons.local_shipping_rounded,
                    label: 'Доставка',
                    value: '${deliveryCostRub.toStringAsFixed(0)} ₽',
                  ),
                  _MetricTile(
                    width: itemWidth,
                    icon: Icons.scale_rounded,
                    label: 'Чистый вес',
                    value: '${netWeightKg.toStringAsFixed(2)} кг',
                  ),
                  _MetricTile(
                    width: itemWidth,
                    icon: Icons.inventory_2_rounded,
                    label: 'Грязный вес',
                    value: '${grossWeightKg.toStringAsFixed(2)} кг',
                  ),
                  _MetricTile(
                    width: itemWidth,
                    icon: Icons.price_change_rounded,
                    label: 'Цена/кг чист.',
                    value: '${costPerKgNet.toStringAsFixed(2)} ₽',
                  ),
                  _MetricTile(
                    width: itemWidth,
                    icon: Icons.price_change_outlined,
                    label: 'Цена/кг гряз.',
                    value: '${costPerKgGross.toStringAsFixed(2)} ₽',
                  ),
                  _MetricTile(
                    width: itemWidth,
                    icon: Icons.trending_up_rounded,
                    label: 'Прибыль',
                    value: '${stats.totalProfitRub.toStringAsFixed(0)} ₽',
                    color: stats.totalProfitRub >= 0
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailing;
  final Color? trailingColor;

  const _SectionHeader({
    required this.icon,
    required this.title,
    this.trailing,
    this.trailingColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: context.brandPrimary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, size: 22, color: context.brandPrimary),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: SpFinanceUi.sectionTitleStyle)),
        if (trailing != null)
          Builder(
            builder: (context) {
              final color = trailingColor ?? context.brandPrimary;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color.withValues(alpha: 0.16)),
                ),
                child: Text(
                  trailing!,
                  style: TextStyle(
                    color: color,
                    fontFamily: 'Gilroy',
                    fontWeight: FontWeight.w900,
                    fontSize: 11.5,
                    height: 1,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final double width;
  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  const _MetricTile({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? context.brandPrimary;
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: SpFinanceUi.softDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: resolvedColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 15, color: resolvedColor),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SpFinanceUi.labelStyle.copyWith(fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  color: resolvedColor,
                  fontFamily: 'Gilroy',
                  fontSize: 18,
                  height: 22 / 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParticipantsSection extends StatelessWidget {
  final SpAssembly assembly;

  const _ParticipantsSection({required this.assembly});

  @override
  Widget build(BuildContext context) {
    if (assembly.stats.participants.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.people_rounded,
            title: 'Участники',
            trailing: '${assembly.stats.participants.length}',
          ),
          const SizedBox(height: 12),
          ...assembly.stats.participants.map((participant) {
            // Получаем треки участника
            final participantTracks = assembly.tracks
                .where((t) => t.spParticipantName == participant.name)
                .toList();

            // Считаем прибыль по участнику (сумма organizerMarginRub)
            final participantProfit = participantTracks.fold<double>(
              0,
              (sum, t) => sum + (t.organizerMarginRub ?? 0),
            );

            return _ParticipantCard(
              assemblyId: assembly.id,
              participant: participant,
              tracks: participantTracks,
              profit: participantProfit,
            );
          }),
        ],
      ),
    );
  }
}

class _ParticipantCard extends ConsumerStatefulWidget {
  final int assemblyId;
  final SpParticipant participant;
  final List<SpTrack> tracks;
  final double profit;

  const _ParticipantCard({
    required this.assemblyId,
    required this.participant,
    required this.tracks,
    required this.profit,
  });

  @override
  ConsumerState<_ParticipantCard> createState() => _ParticipantCardState();
}

class _ParticipantCardState extends ConsumerState<_ParticipantCard> {
  bool _expanded = false;
  bool _isUpdating = false;

  /// Переключает статус оплаты через API
  Future<void> _togglePaymentStatus() async {
    if (_isUpdating) return;

    setState(() => _isUpdating = true);

    final newStatus = !widget.participant.isPaid;
    final success = await ref
        .read(spAssembliesControllerProvider.notifier)
        .toggleParticipantPayment(
          widget.assemblyId,
          widget.participant.name,
          newStatus,
        );

    if (mounted) {
      setState(() => _isUpdating = false);

      if (!success) {
        _showStyledSnackBar(
          context,
          'Ошибка обновления статуса оплаты',
          isError: true,
        );
      }
    }
  }

  /// Формирует текст для копирования и отправки участнику
  Future<void> _copyParticipantInfo() async {
    final buffer = StringBuffer();

    // Итоги
    double totalClientPrice = 0;
    double totalShipping = 0;
    double totalAdditionalExpenses = 0;

    // Для каждого трека: номер, цена товара, стоимость доставки
    for (final track in widget.tracks) {
      final clientPrice = track.clientPriceRub ?? 0;
      final shipping = track.shippingCostRub ?? 0;
      final additionalExpenses = track.additionalExpensesRub ?? 0;

      totalClientPrice += clientPrice;
      totalShipping += shipping;
      totalAdditionalExpenses += additionalExpenses;

      buffer.writeln(
        '${track.trackNumber}, ${clientPrice.toStringAsFixed(2)} ₽, ${shipping.toStringAsFixed(2)} ₽',
      );
    }

    // Итого доставка = доставка + доп. расходы
    final totalShippingWithExpenses = totalShipping + totalAdditionalExpenses;

    // Итого
    buffer.writeln();
    buffer.writeln('Итого товары: ${totalClientPrice.toStringAsFixed(2)} ₽');
    buffer.writeln(
      'Итого доставка: ${totalShippingWithExpenses.toStringAsFixed(2)} ₽',
    );
    buffer.writeln(
      'ВСЕГО: ${(totalClientPrice + totalShippingWithExpenses).toStringAsFixed(2)} ₽',
    );

    final copied = await AppClipboard.copyText(buffer.toString());
    if (!mounted) return;
    if (!copied) {
      _showStyledSnackBar(context, 'Не удалось скопировать', isError: true);
      return;
    }
    _showStyledSnackBar(context, 'Данные скопированы');
  }

  @override
  Widget build(BuildContext context) {
    // Итоги для отображения
    double totalClientPrice = 0;
    double totalShipping = 0;
    double totalAdditionalExpenses = 0;
    for (final track in widget.tracks) {
      totalClientPrice += track.clientPriceRub ?? 0;
      totalShipping += track.shippingCostRub ?? 0;
      totalAdditionalExpenses += track.additionalExpensesRub ?? 0;
    }
    // Итого доставка = доставка + доп. расходы
    final totalShippingWithExpenses = totalShipping + totalAdditionalExpenses;

    final isPaid = widget.participant.isPaid;
    final statusColor = isPaid ? Colors.green.shade700 : context.brandPrimary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: statusColor.withValues(alpha: 0.14)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.045),
              blurRadius: 22,
              spreadRadius: -14,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          children: [
            // Заголовок участника
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(22),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    // Чекбокс оплаты
                    GestureDetector(
                      onTap: _isUpdating ? null : _togglePaymentStatus,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: isPaid ? statusColor : Colors.white,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: isPaid ? statusColor : Colors.grey.shade300,
                            width: 2,
                          ),
                        ),
                        child: isPaid
                            ? const Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        widget.participant.name[0].toUpperCase(),
                        style: TextStyle(
                          color: statusColor,
                          fontFamily: 'Gilroy',
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
                            widget.participant.name,
                            style: SpFinanceUi.bodyStyle.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.participant.trackCount} треков • ${widget.participant.weight.toStringAsFixed(2)} кг',
                            style: SpFinanceUi.labelStyle.copyWith(
                              color: SpFinanceUi.mutedTextColor,
                            ),
                          ),
                          const SizedBox(height: 5),
                          _InlineStatusChip(
                            label: isPaid ? 'Оплачено' : 'Ожидает оплату',
                            color: statusColor,
                          ),
                        ],
                      ),
                    ),
                    // Прибыль
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${widget.profit.toStringAsFixed(0)} ₽',
                          style: TextStyle(
                            fontFamily: 'Gilroy',
                            fontSize: 15,
                            height: 18 / 15,
                            fontWeight: FontWeight.w700,
                            color: widget.profit > 0
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                          ),
                        ),
                        Text(
                          'прибыль',
                          style: SpFinanceUi.labelStyle.copyWith(
                            color: SpFinanceUi.mutedTextColor,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.grey.shade600,
                    ),
                  ],
                ),
              ),
            ),

            // Список треков (раскрывающийся)
            if (_expanded) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Заголовок таблицы
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              'Трек',
                              style: SpFinanceUi.labelStyle.copyWith(
                                color: SpFinanceUi.mutedTextColor,
                                fontSize: 10,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'Цена',
                              style: SpFinanceUi.labelStyle.copyWith(
                                color: SpFinanceUi.mutedTextColor,
                                fontSize: 10,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'Доставка',
                              style: SpFinanceUi.labelStyle.copyWith(
                                color: SpFinanceUi.mutedTextColor,
                                fontSize: 10,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Таблица треков
                    ...widget.tracks.map((track) {
                      return _TrackInfoRow(track: track);
                    }),

                    // Итого
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Итого товары:',
                          style: SpFinanceUi.bodyStyle.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${totalClientPrice.toStringAsFixed(2)} ₽',
                          style: SpFinanceUi.bodyStyle.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Итого доставка:',
                          style: SpFinanceUi.bodyStyle.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${totalShippingWithExpenses.toStringAsFixed(2)} ₽',
                          style: SpFinanceUi.bodyStyle.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'ВСЕГО:',
                          style: SpFinanceUi.bodyStyle.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${(totalClientPrice + totalShippingWithExpenses).toStringAsFixed(2)} ₽',
                          style: SpFinanceUi.bodyStyle.copyWith(
                            fontWeight: FontWeight.w700,
                            color: context.brandPrimary,
                          ),
                        ),
                      ],
                    ),

                    // Кнопка копирования
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _copyParticipantInfo,
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text(
                          'Скопировать для отправки',
                          style: TextStyle(
                            fontFamily: 'Gilroy',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrackInfoRow extends StatelessWidget {
  final SpTrack track;

  const _TrackInfoRow({required this.track});

  @override
  Widget build(BuildContext context) {
    final clientPrice = track.clientPriceRub ?? 0;
    final shipping = track.shippingCostRub ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          // Трек номер
          Expanded(
            flex: 2,
            child: Text(
              track.trackNumber,
              style: const TextStyle(
                color: SpFinanceUi.textColor,
                fontFamily: 'Gilroy',
                fontWeight: FontWeight.w600,
                fontSize: 11,
                height: 13 / 11,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Цена товара
          Expanded(
            child: Text(
              '${clientPrice.toStringAsFixed(2)} ₽',
              style: SpFinanceUi.labelStyle.copyWith(fontSize: 11),
              textAlign: TextAlign.right,
            ),
          ),
          // Доставка
          Expanded(
            child: Text(
              '${shipping.toStringAsFixed(2)} ₽',
              style: SpFinanceUi.labelStyle.copyWith(fontSize: 11),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _TracksSection extends StatelessWidget {
  final SpAssembly assembly;

  const _TracksSection({required this.assembly});

  @override
  Widget build(BuildContext context) {
    final allTracks = assembly.tracks;
    final spTracksCount = allTracks
        .where((t) => t.spParticipantName != null)
        .length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.local_shipping_rounded,
            title: 'Треки',
            trailing: '$spTracksCount/${allTracks.length} СП',
          ),
          const SizedBox(height: 12),
          if (allTracks.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Нет треков в сборке',
                  style: SpFinanceUi.bodyStyle.copyWith(
                    color: SpFinanceUi.mutedTextColor,
                  ),
                ),
              ),
            )
          else
            ...allTracks.map((track) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _TrackCard(track: track, assembly: assembly),
              );
            }),
        ],
      ),
    );
  }
}

class _TrackCard extends StatelessWidget {
  final SpTrack track;
  final SpAssembly assembly;

  const _TrackCard({required this.track, required this.assembly});

  /// Проверяет, все ли обязательные поля заполнены
  bool get isComplete {
    return track.spParticipantName != null &&
        track.spParticipantName!.isNotEmpty &&
        track.clientPriceYuan != null &&
        track.clientPriceYuan! > 0 &&
        track.netWeightKg != null &&
        track.netWeightKg! > 0 &&
        track.purchaseRate != null &&
        track.purchaseRate! > 0;
  }

  /// Рассчитывает стоимость доставки автоматически
  double? _calculateShippingCost() {
    final netWeight = track.netWeightKg;
    if (netWeight == null || netWeight <= 0) return null;

    // Проверяем, что у всех СП-треков заполнен вес
    final spTracks = assembly.tracks
        .where(
          (t) => t.spParticipantName != null && t.spParticipantName!.isNotEmpty,
        )
        .toList();
    if (spTracks.isEmpty) return null;

    double totalNetWeight = 0;
    for (final t in spTracks) {
      if (t.netWeightKg == null || t.netWeightKg! <= 0) return null;
      totalNetWeight += t.netWeightKg!;
    }

    if (totalNetWeight <= 0) return null;

    // Общая стоимость доставки
    double totalDeliveryCost = assembly.totalShippingCostRub ?? 0;
    if (totalDeliveryCost == 0 && assembly.invoices.isNotEmpty) {
      for (final invoice in assembly.invoices) {
        totalDeliveryCost += invoice.deliveryCostRub;
      }
    }

    if (totalDeliveryCost <= 0) return null;

    return netWeight * (totalDeliveryCost / totalNetWeight);
  }

  @override
  Widget build(BuildContext context) {
    // Расчёты
    final clientPriceRub =
        track.clientPriceRub ??
        (track.clientPriceYuan != null && track.purchaseRate != null
            ? track.clientPriceYuan! * track.purchaseRate!
            : null);
    final shippingCostRub = _calculateShippingCost() ?? track.shippingCostRub;
    final totalRub = clientPriceRub != null
        ? clientPriceRub + (shippingCostRub ?? 0)
        : null;
    final profitRub =
        track.organizerMarginRub ??
        (track.clientPriceRub != null && track.costPriceRub != null
            ? track.clientPriceRub! - track.costPriceRub!
            : null);

    // Информация о товаре
    final productName = track.productInfo?.title ?? track.productTitle;
    final productTitle = productName?.trim();
    final productQty = track.productInfo?.quantity ?? 1;
    final participantName = track.spParticipantName?.trim();
    final statusColor = isComplete
        ? Colors.green.shade700
        : Colors.orange.shade700;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () {
          context.push(
            '/sp-finance/tracks/${track.id}',
            extra: {'assemblyId': assembly.id},
          );
        },
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Colors.white,
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
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.local_shipping_rounded,
                      color: statusColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.trackNumber,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontFamily: 'Gilroy',
                            fontSize: 17,
                            height: 1.1,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _InlineStatusChip(
                          label: isComplete ? 'Заполнено' : 'Не заполнено',
                          color: statusColor,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.025),
                      ),
                    ),
                    child: const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),

              if ((productTitle != null && productTitle.isNotEmpty) ||
                  (participantName != null && participantName.isNotEmpty)) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: SpFinanceUi.softDecoration(context),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (productTitle != null && productTitle.isNotEmpty)
                        _TrackMetaPill(
                          icon: Icons.inventory_2_rounded,
                          label: '$productTitle × $productQty шт.',
                        ),
                      if (participantName != null && participantName.isNotEmpty)
                        _TrackMetaPill(
                          icon: Icons.person_rounded,
                          label: participantName,
                          color: context.brandPrimary,
                        ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final itemWidth = (constraints.maxWidth - 8) / 2;

                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _FinanceItem(
                        width: itemWidth,
                        label: 'Цена товара',
                        value: clientPriceRub,
                        color: context.brandPrimary,
                      ),
                      _FinanceItem(
                        width: itemWidth,
                        label: 'Доставка',
                        value: shippingCostRub,
                        color: context.brandPrimary,
                      ),
                      _FinanceItem(
                        width: itemWidth,
                        label: 'Итого',
                        value: totalRub,
                        color: context.brandPrimary,
                        isBold: true,
                      ),
                      _FinanceItem(
                        width: itemWidth,
                        label: 'Прибыль',
                        value: profitRub,
                        color: profitRub != null && profitRub > 0
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                        isBold: true,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackMetaPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _TrackMetaPill({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppColors.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width - 150,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontFamily: 'Gilroy',
                fontSize: 11.5,
                height: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FinanceItem extends StatelessWidget {
  final double width;
  final String label;
  final double? value;
  final Color color;
  final bool isBold;

  const _FinanceItem({
    required this.width,
    required this.label,
    required this.value,
    required this.color,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;

    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isBold
              ? color.withValues(alpha: 0.075)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isBold
                ? color.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.025),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SpFinanceUi.labelStyle.copyWith(fontSize: 10.5, height: 1),
            ),
            const SizedBox(height: 6),
            Text(
              hasValue ? '${value!.toStringAsFixed(0)} ₽' : '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Gilroy',
                fontSize: isBold ? 14 : 13,
                height: 1,
                color: hasValue ? color : Colors.grey.shade400,
                fontWeight: isBold ? FontWeight.w900 : FontWeight.w800,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Секция с фото на весах
class _BoxesSection extends StatelessWidget {
  final SpAssembly assembly;

  const _BoxesSection({required this.assembly});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.inventory_2_outlined,
            title: tr(context, ru: 'Коробки', zh: '箱子'),
            trailing: '${assembly.boxes.length} шт.',
          ),
          const SizedBox(height: 16),
          // Отображаем каждую коробку
          ...assembly.boxes.asMap().entries.map((entry) {
            final index = entry.key;
            final box = entry.value;
            return Padding(
              padding: EdgeInsets.only(
                bottom: index < assembly.boxes.length - 1 ? 12 : 0,
              ),
              child: _buildBoxCard(context, box),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBoxCard(BuildContext context, Box box) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.brandPrimary.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок с номером коробки
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: context.brandPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Center(
                  child: Text(
                    '#${box.number}',
                    style: TextStyle(
                      fontFamily: 'Gilroy',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      height: 18 / 15,
                      color: context.brandPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  box.displayName(context),
                  style: const TextStyle(
                    color: SpFinanceUi.textColor,
                    fontFamily: 'Gilroy',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    height: 19 / 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Параметры коробки в сетке 2x2
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildBoxParam(
                        context,
                        icon: Icons.straighten,
                        label: tr(context, ru: 'Габариты', zh: '尺寸'),
                        value: box.dimensionsDisplay,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildBoxParam(
                        context,
                        icon: Icons.scale,
                        label: tr(context, ru: 'Вес', zh: '重量'),
                        value: box.weightDisplay,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildBoxParam(
                        context,
                        icon: Icons.inventory_2_outlined,
                        label: tr(context, ru: 'Объём', zh: '体积'),
                        value: box.volumeDisplay,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildBoxParam(
                        context,
                        icon: Icons.compress,
                        label: tr(context, ru: 'Плотность', zh: '密度'),
                        value: box.densityDisplay,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Фото на весах
          if (box.photos.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              tr(
                context,
                ru: 'Фото на весах (${box.photos.length})',
                zh: '称重照片 (${box.photos.length})',
              ),
              style: const TextStyle(
                fontFamily: 'Gilroy',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                height: 15 / 13,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 90,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: box.photos.length,
                itemBuilder: (context, index) {
                  final photo = box.photos[index];
                  final photoUrl = ApiConfig.getMediaUrl(photo.url);

                  return Padding(
                    padding: EdgeInsets.only(
                      right: index < box.photos.length - 1 ? 10 : 0,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            // TODO: Добавить просмотр фото
                          },
                          child: Container(
                            width: 90,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: AuthenticatedCachedImage(
                              imageUrl: photoUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, _) => Container(
                                color: Colors.black.withValues(alpha: 0.06),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                              errorWidget: (_, _, _) => Container(
                                color: Colors.black.withValues(alpha: 0.06),
                                child: const Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBoxParam(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: Colors.black45),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Gilroy',
                fontSize: 12,
                height: 14 / 12,
                color: Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Gilroy',
            fontSize: 14,
            height: 17 / 14,
            fontWeight: FontWeight.w700,
            color: SpFinanceUi.textColor,
          ),
        ),
      ],
    );
  }
}
