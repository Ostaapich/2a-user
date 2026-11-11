import '../../../core/ui/app_search_field.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/ui/app_cached_media_image.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/ui/app_layout.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/ui/empty_state.dart';
import '../../../core/ui/scroll_to_top_button.dart';
import '../../../core/utils/locale_text.dart';
import '../data/sp_organizer_models.dart';
import '../data/sp_organizer_provider.dart';
import 'sp_finance_ui.dart';
import 'sp_organizer_navigation.dart';
import 'sp_organizer_purchase_kind.dart';

class SpOrganizerProductDetailScreen extends ConsumerStatefulWidget {
  final int productId;

  const SpOrganizerProductDetailScreen({super.key, required this.productId});

  @override
  ConsumerState<SpOrganizerProductDetailScreen> createState() =>
      _SpOrganizerProductDetailScreenState();
}

class _SpOrganizerProductDetailScreenState
    extends ConsumerState<SpOrganizerProductDetailScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  late SpOrganizerProductDetailQuery _query;

  @override
  void initState() {
    super.initState();
    _query = SpOrganizerProductDetailQuery(productId: widget.productId);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final capabilitiesAsync = ref.watch(spOrganizerCapabilitiesProvider);
    final topPad = AppLayout.topBarTotalHeight(context);
    final bottomPad = AppLayout.bottomScrollPadding(context);

    return Stack(
      children: [
        RefreshIndicator(
          color: context.brandPrimary,
          onRefresh: () async {
            ref.invalidate(spOrganizerProductDetailProvider(_query));
            await ref.read(spOrganizerProductDetailProvider(_query).future);
          },
          child: ListView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              16,
              topPad * 0.7 + 16,
              16,
              bottomPad + 20,
            ),
            children: [
              SpPageHeader(
                title: tr(context, ru: 'Карточка товара', zh: '商品详情'),
                fallbackRoute: '/sp-finance/products',
              ),
              const SizedBox(height: 12),
              capabilitiesAsync.when(
                loading: () => const _ProductDetailLoading(),
                error: (_, _) => _ProductDetailUnavailable(
                  message: tr(
                    context,
                    ru: 'Каталог временно недоступен. Текущие СП продолжают работать.',
                    zh: '商品目录暂不可用，现有拼团仍可正常使用。',
                  ),
                ),
                data: (capabilities) {
                  if (!capabilities.products) {
                    return _ProductDetailUnavailable(
                      message: tr(
                        context,
                        ru: 'Карточка товара пока выключена на сервере.',
                        zh: '服务器尚未启用商品详情。',
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
    final detailAsync = ref.watch(spOrganizerProductDetailProvider(_query));
    return detailAsync.when(
      loading: () => const _ProductDetailLoading(),
      error: (error, _) => EmptyState(
        icon: Icons.error_outline_rounded,
        title: tr(context, ru: 'Не удалось открыть товар', zh: '无法打开商品'),
        message: error.toString(),
      ),
      data: (detail) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProductDetailHero(product: detail.product),
          const SizedBox(height: 12),
          SpOrganizerNavigation(
            capabilities: capabilities,
            selected: SpOrganizerSection.products,
          ),
          const SizedBox(height: 12),
          _ProductSummaryGrid(summary: detail.summary),
          const SizedBox(height: 12),
          _ProductFactsCard(
            product: detail.product,
            onOpenSource: detail.product.sourceUrl == null
                ? null
                : () => _openSource(detail.product.sourceUrl!),
          ),
          const SizedBox(height: 12),
          SpInfoNotice(
            icon: Icons.history_rounded,
            title: tr(
              context,
              ru: 'Полная история использования',
              zh: '完整使用历史',
            ),
            message: tr(
              context,
              ru: 'Показатели считаются на сервере по всем связанным закупкам. Архивные позиции сохраняются и не удаляются.',
              zh: '指标由服务器按所有关联采购计算，归档明细会保留且不会删除。',
            ),
          ),
          const SizedBox(height: 12),
          _HistoryToolbar(
            controller: _searchController,
            query: _query,
            detail: detail,
            onSearchChanged: _onSearchChanged,
            onScopeChanged: (scope) =>
                _changeQuery(_query.copyWith(scope: scope, page: 1)),
            onStatusChanged: (status) =>
                _changeQuery(_query.copyWith(status: status, page: 1)),
            onSortChanged: (sort) =>
                _changeQuery(_query.copyWith(sortBy: sort, page: 1)),
          ),
          const SizedBox(height: 12),
          if (detail.history.items.isEmpty)
            EmptyState(
              icon: Icons.inventory_2_outlined,
              title: tr(context, ru: 'История пока пуста', zh: '暂无使用历史'),
              message: tr(
                context,
                ru: 'Позиции этого товара из закупок появятся здесь.',
                zh: '采购中使用该商品的明细会显示在这里。',
              ),
            )
          else
            ...detail.history.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ProductHistoryCard(
                  item: item,
                  status: detail.statusOptions
                      .where((option) => option.code == item.status)
                      .firstOrNull,
                ),
              ),
            ),
          if (detail.history.totalPages > 1)
            _HistoryPagination(
              page: detail.history.page,
              totalPages: detail.history.totalPages,
              onPrevious: detail.history.page > 1
                  ? () => _changeQuery(
                      _query.copyWith(page: detail.history.page - 1),
                    )
                  : null,
              onNext: detail.history.hasMore
                  ? () => _changeQuery(
                      _query.copyWith(page: detail.history.page + 1),
                    )
                  : null,
            ),
        ],
      ),
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _changeQuery(_query.copyWith(query: value.trim(), page: 1));
    });
  }

  void _changeQuery(SpOrganizerProductDetailQuery query) {
    if (query == _query) return;
    setState(() => _query = query);
  }

  Future<void> _openSource(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      AppToast.show(
        context,
        tr(context, ru: 'Ссылка товара некорректна', zh: '商品链接无效'),
        isError: true,
      );
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted || opened) return;
    AppToast.show(
      context,
      tr(context, ru: 'Не удалось открыть ссылку', zh: '无法打开链接'),
      isError: true,
    );
  }
}

class _ProductDetailHero extends StatelessWidget {
  final SpOrganizerProduct product;

  const _ProductDetailHero({required this.product});

  @override
  Widget build(BuildContext context) {
    return SpAnimatedHeroSurface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              width: 78,
              height: 78,
              child: product.imageUrl == null
                  ? Container(
                      color: Colors.white.withValues(alpha: 0.16),
                      child: const Icon(
                        Icons.inventory_2_outlined,
                        color: Colors.white,
                        size: 34,
                      ),
                    )
                  : AppCachedMediaImage(
                      url: product.imageUrl!,
                      fit: BoxFit.cover,
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Gilroy',
                    fontSize: 22,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    if (product.marketplaceCode != null)
                      SpHeroChip(
                        icon: Icons.storefront_rounded,
                        label: product.marketplaceCode!,
                      ),
                    SpHeroChip(
                      icon: Icons.shopping_bag_outlined,
                      label: tr(
                        context,
                        ru: '${product.itemsCount} позиций',
                        zh: '${product.itemsCount} 个明细',
                      ),
                    ),
                    if (product.isArchived)
                      SpHeroChip(
                        icon: Icons.archive_outlined,
                        label: tr(context, ru: 'В архиве', zh: '已归档'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductSummaryGrid extends StatelessWidget {
  final SpOrganizerProductUsageSummary summary;

  const _ProductSummaryGrid({required this.summary});

  @override
  Widget build(BuildContext context) {
    final metrics = [
      (
        tr(context, ru: 'Средняя цена', zh: '平均售价'),
        _rub(context, summary.averageClientPriceRub),
        Icons.sell_outlined,
      ),
      (
        tr(context, ru: 'Средняя себестоимость', zh: '平均成本'),
        _rub(context, summary.averageCostRub),
        Icons.receipt_long_outlined,
      ),
      (
        tr(context, ru: 'Оборот', zh: '成交额'),
        _rub(context, summary.turnoverRub),
        Icons.payments_outlined,
      ),
      (
        tr(context, ru: 'Прибыль', zh: '利润'),
        _rub(context, summary.profitRub),
        Icons.trending_up_rounded,
      ),
      (
        tr(context, ru: 'Закупки', zh: '采购'),
        '${summary.purchasesCount}',
        Icons.shopping_bag_outlined,
      ),
      (
        tr(context, ru: 'Клиенты', zh: '客户'),
        '${summary.customersCount}',
        Icons.people_alt_outlined,
      ),
      (
        tr(context, ru: 'Количество', zh: '数量'),
        '${summary.totalQuantity}',
        Icons.numbers_rounded,
      ),
      (
        tr(context, ru: 'Общий вес', zh: '总重量'),
        '${_decimal(context, summary.totalWeightKg)} кг',
        Icons.scale_outlined,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 4 : 2;
        final cardWidth = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: metrics
              .map(
                (metric) => SizedBox(
                  width: cardWidth,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: SpFinanceUi.cardDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(metric.$3, color: context.brandPrimary, size: 20),
                        const SizedBox(height: 8),
                        Text(
                          metric.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontFamily: 'Gilroy',
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          metric.$1,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: SpFinanceUi.labelStyle,
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _ProductFactsCard extends StatelessWidget {
  final SpOrganizerProduct product;
  final VoidCallback? onOpenSource;

  const _ProductFactsCard({required this.product, required this.onOpenSource});

  @override
  Widget build(BuildContext context) {
    final facts = <(IconData, String, String)>[
      if (product.marketplaceCode != null)
        (
          Icons.storefront_outlined,
          tr(context, ru: 'Маркетплейс / артикул', zh: '平台 / 货号'),
          product.marketplaceCode!,
        ),
      if (product.barcode != null)
        (
          Icons.qr_code_2_rounded,
          tr(context, ru: 'Штрихкод', zh: '条码'),
          product.barcode!,
        ),
      if (product.qrImageUrl != null)
        (
          Icons.qr_code_scanner_rounded,
          tr(context, ru: 'QR-код', zh: '二维码'),
          tr(context, ru: 'Изображение сохранено', zh: '图片已保存'),
        ),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(context, ru: 'Информация о товаре', zh: '商品信息'),
            style: SpFinanceUi.sectionTitleStyle,
          ),
          if (product.description != null) ...[
            const SizedBox(height: 8),
            Text(product.description!, style: SpFinanceUi.bodyStyle),
          ],
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...facts.map(
              (fact) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(fact.$1, color: context.brandPrimary, size: 19),
                    const SizedBox(width: 9),
                    SizedBox(
                      width: 112,
                      child: Text(fact.$2, style: SpFinanceUi.labelStyle),
                    ),
                    Expanded(
                      child: SelectableText(
                        fact.$3,
                        style: SpFinanceUi.bodyStyle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (onOpenSource != null) ...[
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: onOpenSource,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(
                tr(context, ru: 'Открыть товар у поставщика', zh: '打开供应商商品'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryToolbar extends StatelessWidget {
  final TextEditingController controller;
  final SpOrganizerProductDetailQuery query;
  final SpOrganizerProductDetail detail;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onScopeChanged;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<String> onSortChanged;

  const _HistoryToolbar({
    required this.controller,
    required this.query,
    required this.detail,
    required this.onSearchChanged,
    required this.onScopeChanged,
    required this.onStatusChanged,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(context, ru: 'История по закупкам', zh: '采购使用历史'),
                  style: SpFinanceUi.sectionTitleStyle,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: SpFinanceUi.softDecoration(context),
                child: Text(
                  '${detail.history.total}',
                  style: SpFinanceUi.labelStyle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AppSearchField(
            controller: controller,
            onChanged: onSearchChanged,
            textInputAction: TextInputAction.search,
            hintText: tr(
              context,
              ru: 'Закупка, клиент или название позиции',
              zh: '采购、客户或商品名称',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _HistoryMenuChip(
                label: _scopeLabel(context, query.scope),
                icon: Icons.archive_outlined,
                options: const ['active', 'archived', 'all'],
                optionLabel: (value) => _scopeLabel(context, value),
                onSelected: onScopeChanged,
              ),
              _HistoryMenuChip(
                label: query.status == null
                    ? tr(context, ru: 'Все статусы', zh: '全部状态')
                    : detail.statusOptions
                              .where((status) => status.code == query.status)
                              .map((status) => _statusName(context, status))
                              .firstOrNull ??
                          query.status!,
                icon: Icons.flag_outlined,
                options: <String>[
                  _allStatusesValue,
                  ...detail.statusOptions.map((e) => e.code),
                ],
                optionLabel: (value) {
                  if (value == _allStatusesValue) {
                    return tr(context, ru: 'Все статусы', zh: '全部状态');
                  }
                  final option = detail.statusOptions
                      .where((status) => status.code == value)
                      .firstOrNull;
                  return option == null ? value : _statusName(context, option);
                },
                onSelected: (value) =>
                    onStatusChanged(value == _allStatusesValue ? null : value),
              ),
              _HistoryMenuChip(
                label: _sortLabel(context, query.sortBy),
                icon: Icons.sort_rounded,
                options: const [
                  'createdAt',
                  'quantity',
                  'clientPriceRub',
                  'costPriceRub',
                ],
                optionLabel: (value) => _sortLabel(context, value),
                onSelected: onSortChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryMenuChip<T> extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<T> options;
  final String Function(T value) optionLabel;
  final ValueChanged<T> onSelected;

  const _HistoryMenuChip({
    required this.label,
    required this.icon,
    required this.options,
    required this.optionLabel,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: label,
      onSelected: onSelected,
      itemBuilder: (context) => options
          .map(
            (value) =>
                PopupMenuItem<T>(value: value, child: Text(optionLabel(value))),
          )
          .toList(growable: false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: SpFinanceUi.softDecoration(context),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: context.brandPrimary, size: 16),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SpFinanceUi.labelStyle,
              ),
            ),
            const SizedBox(width: 3),
            const Icon(Icons.expand_more_rounded, size: 17),
          ],
        ),
      ),
    );
  }
}

class _ProductHistoryCard extends StatelessWidget {
  final SpOrganizerProductHistoryItem item;
  final SpOrganizerProductHistoryStatus? status;

  const _ProductHistoryCard({required this.item, required this.status});

  @override
  Widget build(BuildContext context) {
    final accent =
        SpFinanceUi.parseHexColor(status?.color) ?? context.brandPrimary;
    final rate = item.purchaseRate > 0
        ? item.purchaseRate
        : item.purchase.purchaseRate;
    final clientUnitRub = item.clientPriceRub > 0
        ? item.clientPriceRub
        : item.clientPriceYuan * rate;
    final costUnitRub = item.costPriceRub > 0
        ? item.costPriceRub
        : item.purchasePriceYuan * rate;
    final clientTotal = clientUnitRub * item.quantity;
    final costTotal = costUnitRub * item.quantity;
    final profitTotal = clientTotal - costTotal;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/sp-finance/purchases/${item.purchase.id}'),
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: SpFinanceUi.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: context.brandPrimary.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      spOrganizerPurchaseKindIcon(item.purchase.kind),
                      color: context.brandPrimary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.purchase.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: SpFinanceUi.sectionTitleStyle,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          item.customer.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SpFinanceUi.bodyStyle,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _HistoryBadge(
                    label: item.statusLabel,
                    icon: Icons.flag_outlined,
                    color: accent,
                  ),
                  _HistoryBadge(
                    label: item.purchase.statusLabel,
                    icon: Icons.shopping_bag_outlined,
                  ),
                  _HistoryBadge(
                    label: tr(
                      context,
                      ru: '${item.quantity} шт.',
                      zh: '${item.quantity} 件',
                    ),
                    icon: Icons.numbers_rounded,
                  ),
                  if (item.createdAt != null)
                    _HistoryBadge(
                      label: DateFormat(
                        'dd.MM.yyyy',
                      ).format(item.createdAt!.toLocal()),
                      icon: Icons.calendar_today_outlined,
                    ),
                  if (item.isArchived)
                    _HistoryBadge(
                      label: tr(context, ru: 'Архив', zh: '归档'),
                      icon: Icons.archive_outlined,
                      color: AppColors.textSecondary,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 360;
                  final children = [
                    Expanded(
                      child: _HistoryMetric(
                        label: tr(context, ru: 'Цена клиенту', zh: '客户价'),
                        value: _rub(context, clientTotal),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HistoryMetric(
                        label: tr(context, ru: 'Себестоимость', zh: '成本'),
                        value: _rub(context, costTotal),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HistoryMetric(
                        label: tr(context, ru: 'Маржа', zh: '利润'),
                        value: _rub(context, profitTotal),
                      ),
                    ),
                  ];
                  if (!compact) return Row(children: children);
                  return Column(
                    children: [
                      Row(children: children.take(3).toList()),
                      const SizedBox(height: 8),
                      _HistoryMetric(
                        label: tr(context, ru: 'Маржа', zh: '利润'),
                        value: _rub(context, profitTotal),
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

class _HistoryBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;

  const _HistoryBadge({required this.label, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final accent = color ?? context.brandPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontFamily: 'Gilroy',
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryMetric extends StatelessWidget {
  final String label;
  final String value;

  const _HistoryMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: SpFinanceUi.softDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
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
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SpFinanceUi.labelStyle,
          ),
        ],
      ),
    );
  }
}

class _HistoryPagination extends StatelessWidget {
  final int page;
  final int totalPages;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _HistoryPagination({
    required this.page,
    required this.totalPages,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.outlined(
          tooltip: tr(context, ru: 'Предыдущая страница', zh: '上一页'),
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Text(
            tr(
              context,
              ru: 'Страница $page из $totalPages',
              zh: '第 $page / $totalPages 页',
            ),
            textAlign: TextAlign.center,
            style: SpFinanceUi.bodyStyle,
          ),
        ),
        IconButton.outlined(
          tooltip: tr(context, ru: 'Следующая страница', zh: '下一页'),
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

class _ProductDetailLoading extends StatelessWidget {
  const _ProductDetailLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 210,
      decoration: SpFinanceUi.cardDecoration(),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _ProductDetailUnavailable extends StatelessWidget {
  final String message;

  const _ProductDetailUnavailable({required this.message});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.inventory_2_outlined,
      title: tr(context, ru: 'Карточка недоступна', zh: '商品详情不可用'),
      message: message,
    );
  }
}

String _scopeLabel(BuildContext context, String value) {
  return switch (value) {
    'active' => tr(context, ru: 'Активные позиции', zh: '有效明细'),
    'archived' => tr(context, ru: 'Архивные позиции', zh: '归档明细'),
    _ => tr(context, ru: 'Вся история', zh: '全部历史'),
  };
}

String _sortLabel(BuildContext context, String value) {
  return switch (value) {
    'quantity' => tr(context, ru: 'По количеству', zh: '按数量'),
    'clientPriceRub' => tr(context, ru: 'По цене клиенту', zh: '按客户价'),
    'costPriceRub' => tr(context, ru: 'По себестоимости', zh: '按成本'),
    _ => tr(context, ru: 'Сначала новые', zh: '最新优先'),
  };
}

String _statusName(
  BuildContext context,
  SpOrganizerProductHistoryStatus status,
) {
  final locale = Localizations.localeOf(context).languageCode;
  if (locale == 'zh' && status.nameZh?.isNotEmpty == true) {
    return status.nameZh!;
  }
  return status.nameRu;
}

const _allStatusesValue = '__all__';

String _rub(BuildContext context, double value) {
  final locale = Localizations.localeOf(context).languageCode == 'zh'
      ? 'zh_CN'
      : 'ru_RU';
  final format = NumberFormat.decimalPatternDigits(
    locale: locale,
    decimalDigits: value.abs() >= 100 ? 0 : 2,
  );
  return '${format.format(value)} ₽';
}

String _decimal(BuildContext context, double value) {
  final locale = Localizations.localeOf(context).languageCode == 'zh'
      ? 'zh_CN'
      : 'ru_RU';
  return NumberFormat('0.###', locale).format(value);
}
