import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/branding/company_branding_provider.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/ui/app_layout.dart';
import '../../../core/ui/empty_state.dart';
import '../../../core/ui/scroll_to_top_button.dart';
import '../../../core/utils/locale_text.dart';
import '../data/sp_organizer_analytics_models.dart';
import '../data/sp_organizer_models.dart';
import '../data/sp_organizer_provider.dart';
import 'sp_finance_date_range_sheet.dart';
import 'sp_finance_ui.dart';
import 'sp_organizer_navigation.dart';

class SpOrganizerAnalyticsScreen extends ConsumerStatefulWidget {
  final bool embedded;

  const SpOrganizerAnalyticsScreen({super.key, this.embedded = false});

  @override
  ConsumerState<SpOrganizerAnalyticsScreen> createState() =>
      _SpOrganizerAnalyticsScreenState();
}

class _SpOrganizerAnalyticsScreenState
    extends ConsumerState<SpOrganizerAnalyticsScreen> {
  final _scrollController = ScrollController();
  SpOrganizerAnalyticsFilter _filter = const SpOrganizerAnalyticsFilter();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final capabilitiesAsync = ref.watch(spOrganizerCapabilitiesProvider);
    final topPad = widget.embedded ? 0.0 : AppLayout.topBarTotalHeight(context);
    final bottomPad = AppLayout.bottomScrollPadding(context);

    return Stack(
      children: [
        RefreshIndicator(
          color: context.brandPrimary,
          onRefresh: _refresh,
          child: ListView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              16,
              widget.embedded ? 12 : topPad * 0.7 + 16,
              16,
              bottomPad + 20,
            ),
            children: [
              if (!widget.embedded) ...[
                SpPageHeader(
                  title: tr(context, ru: 'Аналитика СП', zh: '拼团分析'),
                  fallbackRoute: '/sp-finance',
                ),
                const SizedBox(height: 12),
              ],
              capabilitiesAsync.when(
                loading: () => const _AnalyticsLoadingCard(),
                error: (_, _) => _AnalyticsUnavailableCard(
                  onRetry: _refresh,
                  title: tr(
                    context,
                    ru: 'Аналитика временно недоступна',
                    zh: '分析暂不可用',
                  ),
                  message: tr(
                    context,
                    ru: 'Закупки и текущие данные продолжают работать.',
                    zh: '采购和现有数据仍可正常使用。',
                  ),
                ),
                data: (capabilities) {
                  if (!capabilities.analytics) {
                    return _AnalyticsUnavailableCard(
                      onRetry: _refresh,
                      title: tr(
                        context,
                        ru: 'Аналитика пока не включена',
                        zh: '分析尚未启用',
                      ),
                      message: tr(
                        context,
                        ru: 'Аналитика пока недоступна для вашего аккаунта. Можно обновить доступность.',
                        zh: '您的账户暂不能使用分析，可以刷新访问权限。',
                      ),
                    );
                  }
                  return _buildEnabledContent(context, capabilities);
                },
              ),
            ],
          ),
        ),
        ScrollToTopButton(controller: _scrollController),
      ],
    );
  }

  Widget _buildEnabledContent(
    BuildContext context,
    SpOrganizerCapabilities capabilities,
  ) {
    final analyticsAsync = ref.watch(spOrganizerAnalyticsProvider(_filter));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded) ...[
          SpOrganizerNavigation(
            capabilities: capabilities,
            selected: SpOrganizerSection.analytics,
          ),
          const SizedBox(height: 12),
        ],
        _AnalyticsFilters(
          filter: _filter,
          onPeriodSelected: (period) => unawaited(_selectPeriod(period)),
          onAudienceChanged: _selectAudience,
          onKindChanged: _selectKind,
          onSelfItemsAsPersonalChanged: _selectSelfItemsAsPersonal,
        ),
        const SizedBox(height: 12),
        analyticsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => EmptyState(
            icon: Icons.error_outline_rounded,
            title: tr(
              context,
              ru: 'Не удалось построить аналитику',
              zh: '无法生成分析',
            ),
            message: error.toString(),
          ),
          data: (analytics) => _AnalyticsContent(
            analytics: analytics,
            showHero: !widget.embedded,
          ),
        ),
      ],
    );
  }

  Future<void> _refresh() async {
    try {
      ref.invalidate(spOrganizerCapabilitiesProvider);
      final capabilities = await ref.read(
        spOrganizerCapabilitiesProvider.future,
      );
      if (!mounted || !capabilities.analytics) return;
      ref.invalidate(spOrganizerAnalyticsProvider(_filter));
      await ref.read(spOrganizerAnalyticsProvider(_filter).future);
    } catch (_) {
      // Provider error state displays a retry without discarding current filters.
    }
  }

  Future<void> _selectPeriod(String period) async {
    if (period != 'custom') {
      setState(() {
        _filter = _filter.copyWith(period: period, clearDates: true);
      });
      return;
    }
    final now = DateTime.now();
    final range = await showSpFinanceDateRangeSheet(
      context: context,
      title: tr(context, ru: 'Период аналитики', zh: '分析周期'),
      subtitle: tr(
        context,
        ru: 'Выберите даты для расчёта показателей',
        zh: '选择用于计算指标的日期',
      ),
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(
        start: _filter.dateFrom ?? now.subtract(const Duration(days: 89)),
        end: _filter.dateTo ?? now,
      ),
      startLabel: tr(context, ru: 'Дата начала', zh: '开始日期'),
      endLabel: tr(context, ru: 'Дата окончания', zh: '结束日期'),
      cancelText: tr(context, ru: 'Отмена', zh: '取消'),
      confirmText: tr(context, ru: 'Применить', zh: '应用'),
    );
    if (!mounted || range == null) return;
    setState(() {
      _filter = _filter.copyWith(
        period: 'custom',
        dateFrom: range.start,
        dateTo: range.end,
      );
    });
  }

  void _selectKind(String? kind) {
    if (kind == null || kind == _filter.kind) return;
    setState(() => _filter = _filter.copyWith(kind: kind));
  }

  void _selectAudience(String? audience) {
    if (audience == null || audience == _filter.audience) return;
    setState(() {
      _filter = _filter.copyWith(audience: audience, kind: 'all');
    });
  }

  void _selectSelfItemsAsPersonal(bool value) {
    if (value == _filter.selfItemsAsPersonal) return;
    setState(() => _filter = _filter.copyWith(selfItemsAsPersonal: value));
  }
}

class _AnalyticsContent extends StatelessWidget {
  final SpOrganizerAnalytics analytics;
  final bool showHero;

  const _AnalyticsContent({required this.analytics, required this.showHero});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHero) _AnalyticsHero(summary: analytics.summary),
        if (analytics.comparison.available &&
            analytics.comparison.previous != null &&
            analytics.comparison.changes != null) ...[
          if (showHero) const SizedBox(height: 12),
          _ComparisonCard(comparison: analytics.comparison),
        ],
        if (showHero ||
            (analytics.comparison.available &&
                analytics.comparison.previous != null &&
                analytics.comparison.changes != null))
          const SizedBox(height: 12),
        _MetricsGrid(summary: analytics.summary),
        const SizedBox(height: 12),
        _IntegrationsSection(integrations: analytics.integrations),
        if (analytics.series.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SeriesCard(series: analytics.series),
        ],
        if (analytics.topPurchases.isNotEmpty) ...[
          const SizedBox(height: 12),
          _TopPurchasesCard(purchases: analytics.topPurchases),
        ],
        if (analytics.topCustomers.isNotEmpty ||
            analytics.topProducts.isNotEmpty ||
            analytics.topMarketplaces.isNotEmpty) ...[
          const SizedBox(height: 12),
          _RankingsSection(analytics: analytics),
        ],
        const SizedBox(height: 12),
        _FormulaNotice(analytics: analytics),
      ],
    );
  }
}

class _AnalyticsHero extends StatelessWidget {
  final SpOrganizerAnalyticsSummary summary;

  const _AnalyticsHero({required this.summary});

  @override
  Widget build(BuildContext context) {
    return SpAnimatedHeroSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                child: const Icon(
                  Icons.query_stats_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(context, ru: 'Рабочая картина закупок', zh: '采购经营概览'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Gilroy',
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tr(
                        context,
                        ru: 'По полной выборке с сервера',
                        zh: '基于服务器完整数据集',
                      ),
                      style: const TextStyle(
                        color: Color(0xE6FFFFFF),
                        fontFamily: 'Gilroy',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeroValue(
                label: tr(context, ru: 'Оборот', zh: '营业额'),
                value: _rub(context, summary.turnoverRub),
              ),
              _HeroValue(
                label: tr(context, ru: 'Прибыль', zh: '利润'),
                value: _rub(context, summary.profitRub),
              ),
              _HeroValue(
                label: tr(context, ru: 'К получению', zh: '待收'),
                value: _rub(context, summary.receivableRub),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroValue extends StatelessWidget {
  final String label;
  final String value;

  const _HeroValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xD9FFFFFF),
              fontFamily: 'Gilroy',
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'Gilroy',
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  final SpOrganizerAnalyticsComparison comparison;

  const _ComparisonCard({required this.comparison});

  @override
  Widget build(BuildContext context) {
    final previous = comparison.previous!;
    final changes = comparison.changes!;
    final metrics = [
      _ComparisonMetricData(
        tr(context, ru: 'Оборот', zh: '营业额'),
        _rub(context, previous.turnoverRub),
        changes.turnoverRub,
      ),
      _ComparisonMetricData(
        tr(context, ru: 'Прибыль', zh: '利润'),
        _rub(context, previous.profitRub),
        changes.profitRub,
      ),
      _ComparisonMetricData(
        tr(context, ru: 'Закупки', zh: '采购'),
        '${previous.purchasesCount}',
        changes.purchasesCount,
      ),
      _ComparisonMetricData(
        tr(context, ru: 'Клиенты', zh: '客户'),
        '${previous.customersCount}',
        changes.customersCount,
      ),
      _ComparisonMetricData(
        tr(context, ru: 'Товары', zh: '商品'),
        '${previous.itemsCount}',
        changes.itemsCount,
      ),
      _ComparisonMetricData(
        tr(context, ru: 'Средняя закупка', zh: '平均采购'),
        _rub(context, previous.averagePurchaseRub),
        changes.averagePurchaseRub,
      ),
      _ComparisonMetricData(
        tr(context, ru: 'Средняя доставка', zh: '平均运输时长'),
        tr(
          context,
          ru: '${_number(context, previous.averageDeliveryDays, digits: 1)} дн.',
          zh: '${_number(context, previous.averageDeliveryDays, digits: 1)} 天',
        ),
        changes.averageDeliveryDays,
        lowerIsBetter: true,
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.compare_arrows_rounded,
                color: context.brandPrimary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr(
                    context,
                    ru: 'Сравнение с прошлым периодом',
                    zh: '与上一周期对比',
                  ),
                  style: SpFinanceUi.sectionTitleStyle,
                ),
              ),
            ],
          ),
          if (comparison.previousDateFrom != null &&
              comparison.previousDateTo != null) ...[
            const SizedBox(height: 5),
            Text(
              '${DateFormat('dd.MM.yyyy').format(comparison.previousDateFrom!.toLocal())}–${DateFormat('dd.MM.yyyy').format(comparison.previousDateTo!.toLocal())}',
              style: SpFinanceUi.labelStyle,
            ),
          ],
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 760 ? 4 : 2;
              final width =
                  (constraints.maxWidth - (columns - 1) * 8) / columns;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: metrics
                    .map(
                      (metric) => SizedBox(
                        width: width,
                        child: _ComparisonMetric(metric: metric),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ComparisonMetricData {
  final String label;
  final String previousValue;
  final double? change;
  final bool lowerIsBetter;

  const _ComparisonMetricData(
    this.label,
    this.previousValue,
    this.change, {
    this.lowerIsBetter = false,
  });
}

class _ComparisonMetric extends StatelessWidget {
  final _ComparisonMetricData metric;

  const _ComparisonMetric({required this.metric});

  @override
  Widget build(BuildContext context) {
    final change = metric.change;
    final improving =
        change != null && (metric.lowerIsBetter ? change < 0 : change > 0);
    final declining =
        change != null && (metric.lowerIsBetter ? change > 0 : change < 0);
    final color = improving
        ? const Color(0xFF239B63)
        : declining
        ? const Color(0xFFD94A4A)
        : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: SpFinanceUi.softDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            metric.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SpFinanceUi.labelStyle,
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Icon(
                change == null
                    ? Icons.remove_rounded
                    : change > 0
                    ? Icons.arrow_upward_rounded
                    : change < 0
                    ? Icons.arrow_downward_rounded
                    : Icons.horizontal_rule_rounded,
                color: color,
                size: 16,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  change == null
                      ? '—'
                      : '${change > 0 ? '+' : ''}${_number(context, change)}%',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SpFinanceUi.bodyStyle.copyWith(
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            tr(
              context,
              ru: 'было ${metric.previousValue}',
              zh: '此前 ${metric.previousValue}',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SpFinanceUi.labelStyle,
          ),
        ],
      ),
    );
  }
}

class _AnalyticsFilters extends StatelessWidget {
  final SpOrganizerAnalyticsFilter filter;
  final ValueChanged<String> onPeriodSelected;
  final ValueChanged<String?> onAudienceChanged;
  final ValueChanged<String?> onKindChanged;
  final ValueChanged<bool> onSelfItemsAsPersonalChanged;

  const _AnalyticsFilters({
    required this.filter,
    required this.onPeriodSelected,
    required this.onAudienceChanged,
    required this.onKindChanged,
    required this.onSelfItemsAsPersonalChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(context, ru: 'Период', zh: '周期'),
            style: SpFinanceUi.sectionTitleStyle,
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _periodButton(context, '30d', '30 дней', '30天'),
              _periodButton(context, '90d', '90 дней', '90天'),
              _periodButton(context, '12m', '12 месяцев', '12个月'),
              _periodButton(context, 'all', 'Всё время', '全部'),
              _periodButton(
                context,
                'custom',
                filter.period == 'custom' ? _rangeLabel(filter) : 'Свой период',
                filter.period == 'custom' ? _rangeLabel(filter) : '自定义',
                icon: Icons.date_range_outlined,
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 640;
              final audience = _audienceField(context);
              final subtype = _subtypeField(context);
              if (!wide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    audience,
                    if (filter.audience == 'client') ...[
                      const SizedBox(height: 10),
                      subtype,
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: audience),
                  if (filter.audience == 'client') ...[
                    const SizedBox(width: 10),
                    Expanded(child: subtype),
                  ],
                ],
              );
            },
          ),
          if (filter.audience != 'all') ...[
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 2),
              value: filter.selfItemsAsPersonal,
              activeThumbColor: context.brandPrimary,
              title: Text(
                tr(context, ru: 'Мои товары — как личные', zh: '我的商品计入个人采购'),
                style: SpFinanceUi.bodyStyle.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(
                tr(
                  context,
                  ru: filter.audience == 'client'
                      ? 'Исключать ваши товары внутри клиентской СП из клиентских показателей'
                      : 'Добавлять ваши товары из клиентских СП в личные показатели',
                  zh: filter.audience == 'client'
                      ? '客户拼团中的自购商品不计入客户指标'
                      : '客户拼团中的自购商品计入个人指标',
                ),
                style: SpFinanceUi.labelStyle,
              ),
              onChanged: onSelfItemsAsPersonalChanged,
            ),
          ],
        ],
      ),
    );
  }

  Widget _periodButton(
    BuildContext context,
    String value,
    String ru,
    String zh, {
    IconData? icon,
  }) {
    return _AnalyticsPeriodButton(
      key: ValueKey('sp-analytics-period-$value'),
      label: tr(context, ru: ru, zh: zh),
      icon: icon,
      selected: filter.period == value,
      onTap: () => onPeriodSelected(value),
    );
  }

  Widget _audienceField(BuildContext context) {
    final options = [
      _AnalyticsChoiceOption(
        value: 'all',
        label: tr(context, ru: 'Все закупки', zh: '全部采购'),
        icon: Icons.all_inclusive_rounded,
      ),
      _AnalyticsChoiceOption(
        value: 'client',
        label: tr(context, ru: 'Клиентские', zh: '客户采购'),
        icon: Icons.groups_2_outlined,
      ),
      _AnalyticsChoiceOption(
        value: 'personal',
        label: tr(context, ru: 'Личные', zh: '个人采购'),
        icon: Icons.person_outline_rounded,
      ),
    ];
    final selected = options.firstWhere(
      (option) => option.value == filter.audience,
      orElse: () => options.first,
    );
    return _AnalyticsSelectionField(
      key: const ValueKey('sp-analytics-audience-selector'),
      label: tr(context, ru: 'Тип аналитики', zh: '分析类型'),
      value: selected.label,
      icon: selected.icon,
      onTap: () => _selectAudience(context, options),
    );
  }

  Widget _subtypeField(BuildContext context) {
    final options = [
      _AnalyticsChoiceOption(
        value: 'all',
        label: tr(context, ru: 'Все', zh: '全部'),
        icon: Icons.dashboard_outlined,
      ),
      _AnalyticsChoiceOption(
        value: 'individual',
        label: tr(context, ru: 'Один клиент', zh: '单个客户'),
        icon: Icons.person_pin_outlined,
      ),
      _AnalyticsChoiceOption(
        value: 'group',
        label: tr(context, ru: 'Совместная', zh: '拼团'),
        icon: Icons.groups_outlined,
      ),
    ];
    final selected = options.firstWhere(
      (option) => option.value == filter.kind,
      orElse: () => options.first,
    );
    return _AnalyticsSelectionField(
      key: const ValueKey('sp-analytics-subtype-selector'),
      label: tr(context, ru: 'Подтип', zh: '子类型'),
      value: selected.label,
      icon: selected.icon,
      onTap: () => _selectSubtype(context, options),
    );
  }

  Future<void> _selectAudience(
    BuildContext context,
    List<_AnalyticsChoiceOption> options,
  ) async {
    final selected = await showSpFinanceModalSheet<String>(
      context: context,
      builder: (context) => _AnalyticsChoiceSheet(
        title: tr(context, ru: 'Выберите тип аналитики', zh: '选择分析类型'),
        subtitle: tr(
          context,
          ru: 'Показатели пересчитаются по выбранной группе закупок',
          zh: '指标将按所选采购分组重新计算',
        ),
        icon: Icons.analytics_outlined,
        selectedValue: filter.audience,
        keyPrefix: 'sp-analytics-audience',
        options: options,
      ),
    );
    if (!context.mounted || selected == null) return;
    onAudienceChanged(selected);
  }

  Future<void> _selectSubtype(
    BuildContext context,
    List<_AnalyticsChoiceOption> options,
  ) async {
    final selected = await showSpFinanceModalSheet<String>(
      context: context,
      builder: (context) => _AnalyticsChoiceSheet(
        title: tr(context, ru: 'Выберите подтип', zh: '选择子类型'),
        subtitle: tr(
          context,
          ru: 'Уточните формат клиентских закупок',
          zh: '指定客户采购的形式',
        ),
        icon: Icons.category_outlined,
        selectedValue: filter.kind,
        keyPrefix: 'sp-analytics-subtype',
        options: options,
      ),
    );
    if (!context.mounted || selected == null) return;
    onKindChanged(selected);
  }
}

class _AnalyticsPeriodButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _AnalyticsPeriodButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : AppColors.textSecondary;
    return Material(
      color: selected ? context.brandPrimary : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected ? context.brandPrimary : const Color(0xFFE1E5ED),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected || icon != null) ...[
                Icon(
                  selected ? Icons.check_rounded : icon,
                  size: 16,
                  color: foreground,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontFamily: 'Gilroy',
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalyticsSelectionField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  const _AnalyticsSelectionField({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: SpFinanceUi.labelStyle),
        const SizedBox(height: 6),
        Material(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE1E5ED)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: context.brandPrimary.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(icon, color: context.brandPrimary, size: 20),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Gilroy',
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnalyticsChoiceOption {
  final String value;
  final String label;
  final IconData icon;

  const _AnalyticsChoiceOption({
    required this.value,
    required this.label,
    required this.icon,
  });
}

class _AnalyticsChoiceSheet extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String selectedValue;
  final String keyPrefix;
  final List<_AnalyticsChoiceOption> options;

  const _AnalyticsChoiceSheet({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selectedValue,
    required this.keyPrefix,
    required this.options,
  });

  @override
  Widget build(BuildContext context) {
    return SpFinanceModalSurface(
      icon: icon,
      title: title,
      subtitle: subtitle,
      maxHeightFactor: 0.68,
      body: ListView.separated(
        shrinkWrap: true,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(height: 7),
        itemBuilder: (context, index) {
          final option = options[index];
          final selected = option.value == selectedValue;
          return Material(
            color: selected
                ? context.brandPrimary.withValues(alpha: 0.09)
                : Colors.white,
            borderRadius: BorderRadius.circular(17),
            child: ListTile(
              key: ValueKey('$keyPrefix-${option.value}'),
              onTap: () => Navigator.of(context).pop(option.value),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(17),
                side: BorderSide(
                  color: selected
                      ? context.brandPrimary.withValues(alpha: 0.28)
                      : const Color(0xFFE9ECF2),
                ),
              ),
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: context.brandPrimary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(option.icon, color: context.brandPrimary, size: 20),
              ),
              title: Text(
                option.label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'Gilroy',
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              trailing: selected
                  ? Icon(
                      Icons.check_circle_rounded,
                      color: context.brandPrimary,
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  final SpOrganizerAnalyticsSummary summary;

  const _MetricsGrid({required this.summary});

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _MetricData(
        Icons.payments_outlined,
        tr(context, ru: 'Получено', zh: '已收'),
        _rub(context, summary.paidRub),
      ),
      _MetricData(
        Icons.account_balance_wallet_outlined,
        tr(context, ru: 'Себестоимость', zh: '成本'),
        _rub(context, summary.costRub),
      ),
      _MetricData(
        Icons.groups_2_outlined,
        tr(context, ru: 'Закупки', zh: '采购'),
        '${summary.purchasesCount}',
      ),
      _MetricData(
        Icons.people_alt_outlined,
        tr(context, ru: 'Клиенты', zh: '客户'),
        '${summary.customersCount}',
      ),
      _MetricData(
        Icons.shopping_bag_outlined,
        tr(context, ru: 'Товары', zh: '商品'),
        '${summary.itemsCount}',
      ),
      _MetricData(
        Icons.inventory_2_outlined,
        tr(context, ru: 'Каталог', zh: '目录'),
        '${summary.catalogProductsCount}',
      ),
      _MetricData(
        Icons.receipt_long_outlined,
        tr(context, ru: 'Средняя закупка', zh: '平均采购'),
        _rub(context, summary.averagePurchaseRub),
      ),
      _MetricData(
        Icons.sell_outlined,
        tr(context, ru: 'Средний товар', zh: '平均商品'),
        _rub(context, summary.averageItemRub),
      ),
      _MetricData(
        Icons.schedule_outlined,
        tr(context, ru: 'Средняя доставка', zh: '平均运输时长'),
        tr(
          context,
          ru: '${_number(context, summary.averageDeliveryDays, digits: 1)} дн.',
          zh: '${_number(context, summary.averageDeliveryDays, digits: 1)} 天',
        ),
      ),
      _MetricData(
        Icons.scale_outlined,
        tr(context, ru: 'Фактический вес', zh: '实际重量'),
        '${_number(context, summary.totalWeightKg, digits: 3)} кг',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 4 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: metrics
              .map(
                (metric) => SizedBox(
                  width: width,
                  child: _MetricCard(metric: metric),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _MetricData {
  final IconData icon;
  final String label;
  final String value;

  const _MetricData(this.icon, this.label, this.value);
}

class _MetricCard extends StatelessWidget {
  final _MetricData metric;

  const _MetricCard({required this.metric});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 102),
      padding: const EdgeInsets.all(12),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(metric.icon, size: 21, color: context.brandPrimary),
          const SizedBox(height: 12),
          Text(
            metric.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Gilroy',
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            metric.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SpFinanceUi.labelStyle,
          ),
        ],
      ),
    );
  }
}

class _IntegrationsSection extends ConsumerWidget {
  final SpOrganizerAnalyticsIntegrations integrations;

  const _IntegrationsSection({required this.integrations});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companyName = ref.watch(companyNameProvider);
    final items = [
      _IntegrationData(
        Icons.currency_yuan_rounded,
        tr(context, ru: 'Выкуп через $companyName', zh: '通过$companyName采购'),
        integrations.buyoutLinkedItemsCount,
        integrations.buyoutLinkedItemsShare,
        tr(context, ru: 'товаров', zh: '件商品'),
      ),
      _IntegrationData(
        Icons.qr_code_2_rounded,
        tr(context, ru: 'Связано с треками', zh: '已关联运单'),
        integrations.trackLinkedItemsCount,
        integrations.trackLinkedItemsShare,
        tr(context, ru: 'товаров', zh: '件商品'),
      ),
      _IntegrationData(
        Icons.local_shipping_outlined,
        tr(context, ru: 'Логистика $companyName', zh: '$companyName物流'),
        integrations.fulfillmentPurchasesCount,
        integrations.fulfillmentPurchasesShare,
        tr(context, ru: 'закупок', zh: '个采购'),
      ),
      _IntegrationData(
        Icons.receipt_long_outlined,
        tr(context, ru: 'Со счётом $companyName', zh: '已关联$companyName账单'),
        integrations.invoiceLinkedPurchasesCount,
        integrations.invoiceLinkedPurchasesShare,
        tr(context, ru: 'закупок', zh: '个采购'),
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              context,
              ru: 'Использование $companyName',
              zh: '$companyName使用情况',
            ),
            style: SpFinanceUi.sectionTitleStyle,
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >= 720;
              final width = desktop
                  ? (constraints.maxWidth - 10) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: items
                    .map(
                      (item) => SizedBox(
                        width: width,
                        child: _IntegrationCard(item: item),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _IntegrationData {
  final IconData icon;
  final String label;
  final int count;
  final double share;
  final String countLabel;

  const _IntegrationData(
    this.icon,
    this.label,
    this.count,
    this.share,
    this.countLabel,
  );
}

class _IntegrationCard extends StatelessWidget {
  final _IntegrationData item;

  const _IntegrationCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: SpFinanceUi.softDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(item.icon, size: 20, color: context.brandPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.label,
                  style: SpFinanceUi.bodyStyle.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${_number(context, item.share)}%',
                style: SpFinanceUi.bodyStyle.copyWith(
                  color: context.brandPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (item.share / 100).clamp(0, 1),
              minHeight: 7,
              backgroundColor: context.brandPrimary.withValues(alpha: 0.08),
              color: context.brandPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${item.count} ${item.countLabel}',
            style: SpFinanceUi.labelStyle,
          ),
        ],
      ),
    );
  }
}

class _SeriesCard extends StatelessWidget {
  final List<SpOrganizerAnalyticsSeriesPoint> series;

  const _SeriesCard({required this.series});

  @override
  Widget build(BuildContext context) {
    final maxValue = series.fold<double>(
      0,
      (current, point) =>
          point.turnoverRub > current ? point.turnoverRub : current,
    );
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(context, ru: 'Динамика оборота', zh: '营业额趋势'),
            style: SpFinanceUi.sectionTitleStyle,
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < series.length; index++) ...[
            if (index > 0) const SizedBox(height: 11),
            _SeriesRow(point: series[index], maxValue: maxValue),
          ],
        ],
      ),
    );
  }
}

class _SeriesRow extends StatelessWidget {
  final SpOrganizerAnalyticsSeriesPoint point;
  final double maxValue;

  const _SeriesRow({required this.point, required this.maxValue});

  @override
  Widget build(BuildContext context) {
    final progress = maxValue > 0 ? point.turnoverRub / maxValue : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(
                _monthLabel(point.month),
                style: SpFinanceUi.labelStyle.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress.clamp(0, 1),
                  minHeight: 10,
                  backgroundColor: context.brandPrimary.withValues(alpha: 0.07),
                  color: context.brandPrimary,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Text(
              _rub(context, point.turnoverRub),
              style: SpFinanceUi.bodyStyle.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 64),
          child: Text(
            '${tr(context, ru: 'прибыль', zh: '利润')}: ${_rub(context, point.profitRub)} · ${tr(context, ru: 'закупок', zh: '采购')}: ${point.purchasesCount}',
            style: SpFinanceUi.labelStyle,
          ),
        ),
      ],
    );
  }
}

class _TopPurchasesCard extends StatelessWidget {
  final List<SpOrganizerAnalyticsTopPurchase> purchases;

  const _TopPurchasesCard({required this.purchases});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(context, ru: 'Крупнейшие закупки', zh: '最大采购'),
            style: SpFinanceUi.sectionTitleStyle,
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < purchases.length; index++) ...[
            if (index > 0)
              Divider(height: 1, color: Colors.black.withValues(alpha: 0.045)),
            _TopPurchaseRow(purchase: purchases[index]),
          ],
        ],
      ),
    );
  }
}

class _TopPurchaseRow extends StatelessWidget {
  final SpOrganizerAnalyticsTopPurchase purchase;

  const _TopPurchaseRow({required this.purchase});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => context.push('/sp-finance/purchases/${purchase.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: context.brandPrimary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  purchase.has2aFulfillment
                      ? Icons.local_shipping_outlined
                      : Icons.groups_2_outlined,
                  color: context.brandPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      purchase.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SpFinanceUi.bodyStyle.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_kindLabel(context, purchase.kind)} · ${purchase.itemsCount} ${tr(context, ru: 'тов.', zh: '件')}',
                      style: SpFinanceUi.labelStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _rub(context, purchase.turnoverRub),
                    style: SpFinanceUi.bodyStyle.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${tr(context, ru: 'прибыль', zh: '利润')} ${_rub(context, purchase.profitRub)}',
                    style: SpFinanceUi.labelStyle.copyWith(
                      color: const Color(0xFF239B63),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankingsSection extends StatelessWidget {
  final SpOrganizerAnalytics analytics;

  const _RankingsSection({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      if (analytics.topCustomers.isNotEmpty)
        _RankedListCard(
          icon: Icons.people_alt_outlined,
          title: tr(context, ru: 'Лучшие клиенты', zh: '重点客户'),
          items: analytics.topCustomers
              .map(
                (customer) => _RankedItem(
                  title: customer.displayName,
                  subtitle: tr(
                    context,
                    ru: '${customer.purchasesCount} закупок · ${customer.itemsCount} товаров',
                    zh: '${customer.purchasesCount} 次采购 · ${customer.itemsCount} 件商品',
                  ),
                  value: _rub(context, customer.turnoverRub),
                  secondary: tr(
                    context,
                    ru: 'прибыль ${_rub(context, customer.profitRub)}',
                    zh: '利润 ${_rub(context, customer.profitRub)}',
                  ),
                  onTap: () =>
                      context.push('/sp-finance/customers/${customer.id}'),
                ),
              )
              .toList(growable: false),
        ),
      if (analytics.topProducts.isNotEmpty)
        _RankedListCard(
          icon: Icons.inventory_2_outlined,
          title: tr(context, ru: 'Лучшие товары', zh: '热门商品'),
          items: analytics.topProducts
              .map(
                (product) => _RankedItem(
                  title: product.title,
                  subtitle: tr(
                    context,
                    ru: '${product.quantity} шт. · ${product.customersCount} клиентов',
                    zh: '${product.quantity} 件 · ${product.customersCount} 位客户',
                  ),
                  value: _rub(context, product.turnoverRub),
                  secondary: tr(
                    context,
                    ru: 'прибыль ${_rub(context, product.profitRub)}',
                    zh: '利润 ${_rub(context, product.profitRub)}',
                  ),
                  onTap: () =>
                      context.push('/sp-finance/products/${product.id}'),
                ),
              )
              .toList(growable: false),
        ),
      if (analytics.topMarketplaces.isNotEmpty)
        _RankedListCard(
          icon: Icons.storefront_outlined,
          title: tr(context, ru: 'Площадки', zh: '采购平台'),
          items: analytics.topMarketplaces
              .map(
                (marketplace) => _RankedItem(
                  title: marketplace.code,
                  subtitle: tr(
                    context,
                    ru: '${marketplace.productsCount} товаров · ${marketplace.purchasesCount} закупок',
                    zh: '${marketplace.productsCount} 个商品 · ${marketplace.purchasesCount} 次采购',
                  ),
                  value: _rub(context, marketplace.turnoverRub),
                  secondary: tr(
                    context,
                    ru: 'прибыль ${_rub(context, marketplace.profitRub)}',
                    zh: '利润 ${_rub(context, marketplace.profitRub)}',
                  ),
                ),
              )
              .toList(growable: false),
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 3
            : constraints.maxWidth >= 720
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cards
              .map((card) => SizedBox(width: width, child: card))
              .toList(growable: false),
        );
      },
    );
  }
}

class _RankedItem {
  final String title;
  final String subtitle;
  final String value;
  final String secondary;
  final VoidCallback? onTap;

  const _RankedItem({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.secondary,
    this.onTap,
  });
}

class _RankedListCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<_RankedItem> items;

  const _RankedListCard({
    required this.icon,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: context.brandPrimary, size: 21),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: SpFinanceUi.sectionTitleStyle),
              ),
            ],
          ),
          const SizedBox(height: 7),
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0)
              Divider(height: 1, color: Colors.black.withValues(alpha: 0.045)),
            _RankedRow(index: index, item: items[index]),
          ],
        ],
      ),
    );
  }
}

class _RankedRow extends StatelessWidget {
  final int index;
  final _RankedItem item;

  const _RankedRow({required this.index, required this.item});

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.brandPrimary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              '${index + 1}',
              style: SpFinanceUi.bodyStyle.copyWith(
                color: context.brandPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SpFinanceUi.bodyStyle.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SpFinanceUi.labelStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                item.value,
                style: SpFinanceUi.bodyStyle.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.secondary,
                style: SpFinanceUi.labelStyle.copyWith(
                  color: const Color(0xFF239B63),
                ),
              ),
            ],
          ),
          if (item.onTap != null) ...[
            const SizedBox(width: 3),
            const Icon(Icons.chevron_right_rounded, size: 18),
          ],
        ],
      ),
    );
    if (item.onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: item.onTap,
        child: content,
      ),
    );
  }
}

class _FormulaNotice extends StatelessWidget {
  final SpOrganizerAnalytics analytics;

  const _FormulaNotice({required this.analytics});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.brandPrimary.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.brandPrimary.withValues(alpha: 0.10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, color: context.brandPrimary, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              tr(
                context,
                ru: 'Только просмотр. Показатели рассчитаны сервером по тем же legacy-формулам, что текущий список СП. Период применяется по дате создания закупки; данные и суммы не изменяются.',
                zh: '仅查看。指标由服务器按当前拼团列表相同的旧版公式计算。周期按采购创建日期筛选；数据和金额不会改变。',
              ),
              style: SpFinanceUi.labelStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsLoadingCard extends StatelessWidget {
  const _AnalyticsLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      decoration: SpFinanceUi.cardDecoration(),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _AnalyticsUnavailableCard extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const _AnalyticsUnavailableCard({
    required this.title,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        children: [
          Icon(
            Icons.query_stats_outlined,
            size: 36,
            color: context.brandPrimary,
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: SpFinanceUi.sectionTitleStyle,
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: SpFinanceUi.labelStyle,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(tr(context, ru: 'Повторить', zh: '重试')),
            ),
          ],
        ],
      ),
    );
  }
}

String _rangeLabel(SpOrganizerAnalyticsFilter filter) {
  if (filter.dateFrom == null || filter.dateTo == null) return 'Свой период';
  final format = DateFormat('dd.MM.yy');
  return '${format.format(filter.dateFrom!)}–${format.format(filter.dateTo!)}';
}

String _kindLabel(BuildContext context, String kind) {
  return switch (kind) {
    'personal' => tr(context, ru: 'Для себя', zh: '自用'),
    'individual' => tr(context, ru: 'Индивидуальная', zh: '个人采购'),
    _ => tr(context, ru: 'Групповая', zh: '拼团'),
  };
}

String _monthLabel(String value) {
  final parts = value.split('-');
  if (parts.length != 2) return value;
  return '${parts[1]}.${parts[0]}';
}

String _rub(BuildContext context, double value) {
  return '${_number(context, value)} ₽';
}

String _number(BuildContext context, double value, {int digits = 2}) {
  final languageCode = Localizations.localeOf(context).languageCode;
  final format = NumberFormat.decimalPatternDigits(
    locale: languageCode,
    decimalDigits: value == value.roundToDouble() ? 0 : digits,
  );
  return format.format(value);
}
