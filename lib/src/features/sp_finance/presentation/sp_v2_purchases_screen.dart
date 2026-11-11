import '../../../core/ui/app_search_field.dart';
import '../../../core/utils/locale_text.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../training/presentation/training_target.dart';
import '../../../core/branding/company_branding_provider.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/ui/app_layout.dart';
import '../../../core/ui/empty_state.dart';
import '../../../core/ui/scroll_to_top_button.dart';
import '../data/sp_organizer_provider.dart';
import '../data/sp_v2_models.dart';
import '../data/sp_v2_provider.dart';
import 'sp_finance_date_range_sheet.dart';
import 'sp_finance_ui.dart';
import 'sp_organizer_navigation.dart';
import 'sp_organizer_purchase_kind.dart';
import 'sp_purchase_client_sections_editor.dart';
import 'sp_purchase_status_dates.dart';
import 'sp_v2_help_sheet.dart';

class SpV2PurchasesScreen extends ConsumerStatefulWidget {
  final bool embedded;

  const SpV2PurchasesScreen({super.key, this.embedded = false});

  @override
  ConsumerState<SpV2PurchasesScreen> createState() =>
      _SpV2PurchasesScreenState();
}

class _SpV2PurchasesScreenState extends ConsumerState<SpV2PurchasesScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _createSheetPending = false;

  @override
  void initState() {
    super.initState();
    _searchController.text = ref.read(spV2PurchasesControllerProvider).query;
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(spV2PurchasesControllerProvider.notifier).load();
    });
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
    final state = ref.watch(spV2PurchasesControllerProvider);
    final organizerCapabilities = ref
        .watch(spOrganizerCapabilitiesProvider)
        .asData
        ?.value;
    final topPad = widget.embedded ? 0.0 : AppLayout.topBarTotalHeight(context);
    final bottomPad = AppLayout.bottomScrollPadding(context);

    return Stack(
      children: [
        RefreshIndicator(
          color: context.brandPrimary,
          onRefresh: () =>
              ref.read(spV2PurchasesControllerProvider.notifier).load(),
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
                  title: 'Совместные покупки',
                  trailing: SpV2HelpButton(
                    onTap: () => showSpV2HelpSheet(context),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (!widget.embedded) ...[
                _SpV2Hero(state: state),
                if (organizerCapabilities?.hasOrganizerTools == true) ...[
                  const SizedBox(height: 12),
                  SpOrganizerNavigation(
                    capabilities: organizerCapabilities!,
                    selected: SpOrganizerSection.purchases,
                  ),
                ],
                const SizedBox(height: 14),
              ],
              _SearchCreateBar(
                controller: _searchController,
                isLoading: state.isLoading,
                filterCount: state.directoryQuery.activeFilterCount,
                onChanged: _onSearchChanged,
                onFilter: () => _showDirectoryFilters(
                  showKinds: organizerCapabilities?.purchaseKinds == true,
                ),
                onCreate: _showCreatePurchaseSheet,
              ),
              const SizedBox(height: 14),
              if (state.error != null && state.purchases.isNotEmpty) ...[
                _DirectoryInlineError(
                  message: state.error!,
                  onRetry: () =>
                      ref.read(spV2PurchasesControllerProvider.notifier).load(),
                ),
                const SizedBox(height: 12),
              ],
              if (state.error != null && state.purchases.isEmpty)
                EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Не удалось загрузить СП',
                  message: state.error!,
                )
              else if (state.isLoading && state.purchases.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 42),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (state.purchases.isEmpty)
                const _SpV2EmptyCard()
              else
                _PurchaseDirectoryGrid(
                  state: state,
                  showKind: organizerCapabilities?.purchaseKinds == true,
                  onLoadMore: () => ref
                      .read(spV2PurchasesControllerProvider.notifier)
                      .loadMore(),
                ),
            ],
          ),
        ),
        ScrollToTopButton(controller: _scrollController),
      ],
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.extentAfter > 420) return;
    ref.read(spV2PurchasesControllerProvider.notifier).loadMore();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(spV2PurchasesControllerProvider.notifier).search(value);
    });
  }

  Future<void> _showDirectoryFilters({required bool showKinds}) async {
    final state = ref.read(spV2PurchasesControllerProvider);
    final updated = await showSpFinanceModalSheet<SpV2PurchaseDirectoryQuery>(
      context: context,
      builder: (context) => _PurchaseDirectoryFilterSheet(
        initial: state.directoryQuery,
        statusOptions: state.statusOptions,
        showKinds: showKinds,
      ),
    );
    if (!mounted || updated == null) return;
    await ref
        .read(spV2PurchasesControllerProvider.notifier)
        .updateDirectoryQuery(updated);
    if (!mounted) return;
  }

  Future<void> _showCreatePurchaseSheet() async {
    if (_createSheetPending) return;
    _createSheetPending = true;
    try {
      final purchaseKindsEnabled =
          ref
              .read(spOrganizerCapabilitiesProvider)
              .asData
              ?.value
              .purchaseKinds ??
          false;
      final created = await showSpFinanceModalSheet<SpV2Purchase>(
        context: context,
        builder: (context) =>
            _CreatePurchaseSheet(purchaseKindsEnabled: purchaseKindsEnabled),
      );
      if (!mounted || created == null) return;
      context.push('/sp-finance/purchases/${created.id}');
    } finally {
      _createSheetPending = false;
    }
  }
}

class _SpV2Hero extends StatelessWidget {
  final SpV2PurchasesState state;

  const _SpV2Hero({required this.state});

  @override
  Widget build(BuildContext context) {
    final active = state.summary.activePurchasesCount;
    final items = state.summary.itemsCount;

    return SpAnimatedHeroSurface(
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: const Icon(
              Icons.groups_2_rounded,
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
                  'Закупки организатора',
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Gilroy',
                    fontSize: 23,
                    height: 1.04,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.25,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'Ведите клиентов, товары, выкуп, треки, оплаты и отправки в одном процессе.',
                  style: TextStyle(
                    color: Color(0xE6FFFFFF),
                    fontFamily: 'Gilroy',
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SpHeroChip(
                      icon: Icons.playlist_add_check_rounded,
                      label: '$active активных',
                    ),
                    SpHeroChip(
                      icon: Icons.shopping_bag_rounded,
                      label: '$items товаров',
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

class _SearchCreateBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final int filterCount;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilter;
  final VoidCallback onCreate;

  const _SearchCreateBar({
    required this.controller,
    required this.isLoading,
    required this.filterCount,
    required this.onChanged,
    required this.onFilter,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: SpFinanceUi.cardDecoration(),
      child: Row(
        children: [
          Expanded(
            child: AppSearchField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              hintText: 'Найти СП по названию',
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: filterCount > 0
                ? context.brandPrimary.withValues(alpha: 0.12)
                : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              key: const Key('sp-purchase-filter-button'),
              onTap: onFilter,
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: 48,
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      color: filterCount > 0
                          ? context.brandPrimary
                          : AppColors.textSecondary,
                    ),
                    if (filterCount > 0)
                      Positioned(
                        top: 7,
                        right: 6,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 18),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: context.brandPrimary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$filterCount',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'Gilroy',
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: context.brandPrimary,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: isLoading ? null : onCreate,
              borderRadius: BorderRadius.circular(18),
              child: const SizedBox(
                width: 56,
                height: 56,
                child: Icon(Icons.add_rounded, color: Colors.white, size: 30),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectoryInlineError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _DirectoryInlineError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFFEA580C)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontFamily: 'Gilroy',
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Повторить')),
        ],
      ),
    );
  }
}

class _PurchaseDirectoryGrid extends StatelessWidget {
  final SpV2PurchasesState state;
  final bool showKind;
  final VoidCallback onLoadMore;

  const _PurchaseDirectoryGrid({
    required this.state,
    required this.showKind,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1080
            ? 3
            : constraints.maxWidth >= 680
            ? 2
            : 1;
        const spacing = 12.0;
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Column(
          children: [
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: state.purchases
                  .map(
                    (purchase) => SizedBox(
                      width: cardWidth,
                      child: _SpV2PurchaseCard(
                        purchase: purchase,
                        showKind: showKind,
                        trainingTarget: purchase.id == state.purchases.first.id,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            if (state.isLoadingMore) ...[
              const SizedBox(height: 18),
              const Center(child: CircularProgressIndicator()),
            ] else if (state.hasNextPage) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const Key('sp-purchase-load-more'),
                onPressed: onLoadMore,
                icon: const Icon(Icons.expand_more_rounded),
                label: Text(
                  'Показать ещё · ${state.purchases.length} из '
                  '${state.pagination.total}',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.brandPrimary,
                  minimumSize: const Size.fromHeight(48),
                  side: BorderSide(
                    color: context.brandPrimary.withValues(alpha: 0.22),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Gilroy',
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _PurchaseDirectoryFilterSheet extends StatefulWidget {
  final SpV2PurchaseDirectoryQuery initial;
  final List<SpV2PurchaseDirectoryStatus> statusOptions;
  final bool showKinds;

  const _PurchaseDirectoryFilterSheet({
    required this.initial,
    required this.statusOptions,
    required this.showKinds,
  });

  @override
  State<_PurchaseDirectoryFilterSheet> createState() =>
      _PurchaseDirectoryFilterSheetState();
}

class _PurchaseDirectoryFilterSheetState
    extends State<_PurchaseDirectoryFilterSheet> {
  late String? _status;
  late String? _kind;
  late String _scope;
  late String _sortBy;
  late String _sortDirection;
  DateTimeRange? _period;

  @override
  void initState() {
    super.initState();
    _status = widget.initial.status;
    _kind = widget.initial.kind;
    _scope = widget.initial.scope;
    _sortBy = widget.initial.sortBy;
    _sortDirection = widget.initial.sortDirection;
    final from = widget.initial.dateFrom;
    final to = widget.initial.dateTo;
    if (from != null || to != null) {
      final fallback = from ?? to!;
      _period = DateTimeRange(start: from ?? fallback, end: to ?? fallback);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statuses = widget.statusOptions.isEmpty
        ? SpV2PurchaseStatusInfo.all
              .map(
                (status) => SpV2PurchaseDirectoryStatus(
                  code: status.code,
                  label: status.label,
                ),
              )
              .toList(growable: false)
        : widget.statusOptions;

    return SpFinanceModalSurface(
      key: const Key('sp-purchase-filter-sheet'),
      icon: Icons.tune_rounded,
      title: 'Фильтры и сортировка',
      subtitle: 'Статус, период и порядок отображения закупок',
      contentPadding: EdgeInsets.zero,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FilterSectionTitle(label: 'Показывать'),
            _FilterChoiceWrap(
              values: const [
                ('active', 'Активные'),
                ('archived', 'Архив'),
                ('all', 'Все'),
              ],
              selected: _scope,
              onSelected: (value) => setState(() => _scope = value),
            ),
            const SizedBox(height: 18),
            _FilterSectionTitle(label: 'Статус'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DirectoryChoiceChip(
                  label: 'Все статусы',
                  selected: _status == null,
                  onSelected: () => setState(() => _status = null),
                ),
                ...statuses.map(
                  (status) => _DirectoryChoiceChip(
                    key: Key('sp-purchase-status-${status.code}'),
                    label: status.label,
                    selected: _status == status.code,
                    onSelected: () => setState(() => _status = status.code),
                  ),
                ),
              ],
            ),
            if (widget.showKinds) ...[
              const SizedBox(height: 18),
              _FilterSectionTitle(label: 'Формат закупки'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _DirectoryChoiceChip(
                    label: 'Все форматы',
                    selected: _kind == null,
                    onSelected: () => setState(() => _kind = null),
                  ),
                  _DirectoryChoiceChip(
                    label: 'Персональная',
                    selected: _kind == 'personal',
                    onSelected: () => setState(() => _kind = 'personal'),
                  ),
                  _DirectoryChoiceChip(
                    label: 'Индивидуальная',
                    selected: _kind == 'individual',
                    onSelected: () => setState(() => _kind = 'individual'),
                  ),
                  _DirectoryChoiceChip(
                    label: 'Групповая',
                    selected: _kind == 'group',
                    onSelected: () => setState(() => _kind = 'group'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            _FilterSectionTitle(label: 'Период создания'),
            InkWell(
              key: const Key('sp-purchase-period'),
              onTap: _selectPeriod,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.date_range_rounded, color: context.brandPrimary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _period == null
                            ? 'За всё время'
                            : '${DateFormat('dd.MM.yyyy').format(_period!.start)}'
                                  ' — '
                                  '${DateFormat('dd.MM.yyyy').format(_period!.end)}',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontFamily: 'Gilroy',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (_period != null)
                      IconButton(
                        tooltip: 'Сбросить период',
                        onPressed: () => setState(() => _period = null),
                        icon: const Icon(Icons.close_rounded),
                      )
                    else
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textSecondary,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            _FilterSectionTitle(label: 'Сортировка'),
            _FilterChoiceWrap(
              values: const [
                ('createdAt', 'Дата создания'),
                ('updatedAt', 'Обновление'),
                ('title', 'Название'),
                ('itemsCount', 'Товары'),
                ('totalDueRub', 'Сумма'),
                ('totalProfitRub', 'Прибыль'),
              ],
              selected: _sortBy,
              onSelected: (value) => setState(() => _sortBy = value),
            ),
            const SizedBox(height: 10),
            _FilterChoiceWrap(
              values: const [
                ('desc', 'По убыванию'),
                ('asc', 'По возрастанию'),
              ],
              selected: _sortDirection,
              onSelected: (value) => setState(() => _sortDirection = value),
            ),
          ],
        ),
      ),
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: const Key('sp-purchase-filter-reset'),
              onPressed: _reset,
              style: OutlinedButton.styleFrom(
                foregroundColor: context.brandPrimary,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: const Text(
                'Сбросить',
                style: TextStyle(
                  fontFamily: 'Gilroy',
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              key: const Key('sp-purchase-filter-apply'),
              onPressed: _apply,
              style: ElevatedButton.styleFrom(
                backgroundColor: context.brandPrimary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: const Text(
                'Показать закупки',
                style: TextStyle(
                  fontFamily: 'Gilroy',
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectPeriod() async {
    final now = DateTime.now();
    final selected = await showSpFinanceDateRangeSheet(
      context: context,
      title: 'Период создания закупки',
      subtitle: 'Укажите даты, за которые нужно показать закупки',
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 3, 12, 31),
      initialDateRange: _period,
      cancelText: 'Отмена',
      confirmText: 'Выбрать',
    );
    if (!mounted || selected == null) return;
    setState(() => _period = selected);
  }

  void _reset() {
    Navigator.of(context).pop(
      SpV2PurchaseDirectoryQuery(
        query: widget.initial.query,
        limit: widget.initial.limit,
      ),
    );
  }

  void _apply() {
    Navigator.of(context).pop(
      widget.initial.copyWith(
        status: _status,
        kind: widget.showKinds ? _kind : widget.initial.kind,
        scope: _scope,
        dateFrom: _period?.start,
        dateTo: _period?.end,
        sortBy: _sortBy,
        sortDirection: _sortDirection,
        page: 1,
      ),
    );
  }
}

class _FilterSectionTitle extends StatelessWidget {
  final String label;

  const _FilterSectionTitle({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontFamily: 'Gilroy',
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _FilterChoiceWrap extends StatelessWidget {
  final List<(String, String)> values;
  final String selected;
  final ValueChanged<String> onSelected;

  const _FilterChoiceWrap({
    required this.values,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values
          .map(
            (value) => _DirectoryChoiceChip(
              label: value.$2,
              selected: selected == value.$1,
              onSelected: () => onSelected(value.$1),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _DirectoryChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _DirectoryChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: context.brandPrimary.withValues(alpha: 0.14),
      backgroundColor: const Color(0xFFF8FAFC),
      side: BorderSide(
        color: selected
            ? context.brandPrimary.withValues(alpha: 0.28)
            : const Color(0xFFE2E8F0),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      labelStyle: TextStyle(
        color: selected ? context.brandPrimary : AppColors.textSecondary,
        fontFamily: 'Gilroy',
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
      showCheckmark: false,
    );
  }
}

class _SpV2PurchaseCard extends StatelessWidget {
  final SpV2Purchase purchase;
  final bool showKind;

  const _SpV2PurchaseCard({
    required this.purchase,
    required this.showKind,
    this.trainingTarget = false,
  });
  final bool trainingTarget;

  @override
  Widget build(BuildContext context) {
    final directory = purchase.directory;
    final formatter = NumberFormat.currency(
      locale: 'ru_RU',
      symbol: '₽',
      decimalDigits: 0,
    );
    final stageAt =
        directory.stageAt ?? purchase.updatedAt ?? purchase.createdAt;
    final lifecycleStage = spPurchaseCreationStageForStatus(purchase.status);
    final startedAt = purchase.startedAt ?? purchase.createdAt;
    final dispatchedAt =
        purchase.dispatchedFromChinaAt ??
        (purchase.status == 'in_transit' ? stageAt : null);
    final completedAt =
        purchase.completedAt ??
        (lifecycleStage == SpPurchaseCreationStage.delivered ? stageAt : null);
    final costRub = directory.available
        ? directory.costRub
        : purchase.stats.totalDueRub - purchase.stats.totalProfitRub;
    final profitRub = directory.available
        ? directory.profitRub
        : purchase.stats.totalProfitRub;
    final outstandingRub = directory.available
        ? directory.outstandingRub
        : purchase.stats.totalDueRub - purchase.stats.paidRub;
    final metadata = <Widget>[
      if (showKind)
        _MetricChip(
          icon: spOrganizerPurchaseKindIcon(purchase.kind),
          label: spOrganizerPurchaseKindLabel(context, purchase.kind),
        ),
      _MetricChip(
        icon: Icons.person_rounded,
        label: '${purchase.stats.customersCount} клиентов',
      ),
      _MetricChip(
        icon: Icons.shopping_bag_rounded,
        label: '${purchase.stats.itemsCount} товаров',
      ),
      _MetricChip(
        icon: purchase.currency == 'RUB'
            ? Icons.currency_ruble_rounded
            : Icons.currency_yuan_rounded,
        label: purchase.currency == 'RUB' ? 'Рубли' : 'Юани',
      ),
      if (directory.weightKg > 0)
        _MetricChip(
          icon: Icons.scale_rounded,
          label:
              '${NumberFormat('0.###', 'ru_RU').format(directory.weightKg)} кг'
              '${directory.weightSource == 'declared' ? ' заявл.' : ''}',
        ),
    ];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/sp-finance/purchases/${purchase.id}'),
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          key: ValueKey('sp-purchase-card-${purchase.id}'),
          padding: const EdgeInsets.all(12),
          decoration: SpFinanceUi.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: context.brandPrimary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.groups_rounded,
                      color: context.brandPrimary,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TrainingTarget(
                          id: trainingTarget
                              ? 'organizer.open'
                              : 'organizer.open.${purchase.id}',
                          onActivate: () => context.push(
                            '/sp-finance/purchases/${purchase.id}',
                          ),
                          child: Text(
                            purchase.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontFamily: 'Gilroy',
                              fontSize: 18,
                              height: 1.08,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        _StatusPill(
                          label: purchase.statusLabel,
                          isActive: purchase.isAcceptingItems,
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textSecondary,
                    size: 22,
                  ),
                ],
              ),
              if (startedAt != null) ...[
                const SizedBox(height: 8),
                _CompactPurchaseLifecycle(
                  currentStage: lifecycleStage,
                  startedAt: startedAt,
                  dispatchedFromChinaAt: dispatchedAt,
                  completedAt: completedAt,
                ),
              ],
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < metadata.length; index++) ...[
                      metadata[index],
                      if (index < metadata.length - 1) const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _PurchaseFinanceSummary(
                cost: formatter.format(costRub),
                due: formatter.format(purchase.stats.totalDueRub),
                profit: formatter.format(profitRub),
                positiveProfit: profitRub > 0,
              ),
              if (outstandingRub > 0) ...[
                const SizedBox(height: 6),
                _PurchaseOutstanding(value: formatter.format(outstandingRub)),
              ],
              if (directory.available) ...[
                const SizedBox(height: 8),
                _PurchaseIntegrations(integrations: directory.integrations),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactPurchaseLifecycle extends StatelessWidget {
  final SpPurchaseCreationStage currentStage;
  final DateTime? startedAt;
  final DateTime? dispatchedFromChinaAt;
  final DateTime? completedAt;

  const _CompactPurchaseLifecycle({
    required this.currentStage,
    required this.startedAt,
    required this.dispatchedFromChinaAt,
    required this.completedAt,
  });

  @override
  Widget build(BuildContext context) {
    final stages = [
      ('Создана', startedAt),
      ('Отправлена', dispatchedFromChinaAt),
      ('Получена', completedAt),
    ];

    return Semantics(
      label: 'Этапы и даты закупки',
      child: Row(
        key: const Key('sp-purchase-lifecycle-summary'),
        children: [
          for (var index = 0; index < stages.length; index++) ...[
            Expanded(
              child: _CompactPurchaseLifecycleStage(
                label: stages[index].$1,
                date: stages[index].$2,
                active: index <= currentStage.index,
              ),
            ),
            if (index < stages.length - 1)
              Container(
                width: 8,
                height: 1.5,
                color: index < currentStage.index
                    ? context.brandPrimary.withValues(alpha: 0.38)
                    : const Color(0xFFE1E5ED),
              ),
          ],
        ],
      ),
    );
  }
}

class _CompactPurchaseLifecycleStage extends StatelessWidget {
  final String label;
  final DateTime? date;
  final bool active;

  const _CompactPurchaseLifecycleStage({
    required this.label,
    required this.date,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.brandPrimary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: active
                ? accent.withValues(alpha: 0.10)
                : const Color(0xFFF1F3F6),
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? accent : const Color(0xFFD9DEE7),
            ),
          ),
          child: Icon(
            active ? Icons.check_rounded : Icons.more_horiz_rounded,
            size: 11,
            color: active ? accent : const Color(0xFFADB4C0),
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active
                      ? AppColors.textPrimary
                      : const Color(0xFFADB4C0),
                  fontFamily: 'Gilroy',
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                date == null ? '—' : DateFormat('dd.MM.yy').format(date!),
                maxLines: 1,
                style: TextStyle(
                  color: active
                      ? AppColors.textSecondary
                      : const Color(0xFFB8BEC8),
                  fontFamily: 'Gilroy',
                  fontSize: 8.5,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PurchaseFinanceSummary extends StatelessWidget {
  final String cost;
  final String due;
  final String profit;
  final bool positiveProfit;

  const _PurchaseFinanceSummary({
    required this.cost,
    required this.due,
    required this.profit,
    required this.positiveProfit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFEFF2F6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _PurchaseFinanceValue(label: 'Себестоимость', value: cost),
          ),
          const _PurchaseFinanceDivider(),
          Expanded(
            child: _PurchaseFinanceValue(label: 'Клиентам', value: due),
          ),
          const _PurchaseFinanceDivider(),
          Expanded(
            child: _PurchaseFinanceValue(
              label: 'Прибыль',
              value: profit,
              positive: positiveProfit,
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchaseFinanceDivider extends StatelessWidget {
  const _PurchaseFinanceDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 28, color: const Color(0xFFE5E9F0));
  }
}

class _PurchaseFinanceValue extends StatelessWidget {
  final String label;
  final String value;
  final bool positive;

  const _PurchaseFinanceValue({
    required this.label,
    required this.value,
    this.positive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Gilroy',
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: positive
                    ? const Color(0xFF15803D)
                    : AppColors.textPrimary,
                fontFamily: 'Gilroy',
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchaseOutstanding extends StatelessWidget {
  final String value;

  const _PurchaseOutstanding({required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.schedule_send_rounded,
          size: 14,
          color: context.brandPrimary,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            'Ожидается от клиентов: $value',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Gilroy',
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _PurchaseIntegrations extends ConsumerWidget {
  final SpV2PurchaseDirectoryIntegrations integrations;

  const _PurchaseIntegrations({required this.integrations});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companyName = ref.watch(companyNameProvider);
    final badges = <Widget>[
      if (integrations.selfBuyoutRequestsCount > 0)
        _IntegrationBadge(
          tooltip: 'Самовыкуп',
          icon: Icons.shopping_cart_checkout_rounded,
          count: integrations.selfBuyoutRequestsCount,
        ),
      if (integrations.garageOrderItemsCount > 0)
        _IntegrationBadge(
          tooltip: 'Гараж',
          icon: Icons.directions_car_filled_rounded,
          count: integrations.garageOrderItemsCount,
        ),
      if (integrations.tracksCount > 0)
        _IntegrationBadge(
          tooltip: 'Треки',
          icon: Icons.local_shipping_rounded,
          count: integrations.tracksCount,
        ),
      if (integrations.photosCount > 0 || integrations.photoRequestsCount > 0)
        _IntegrationBadge(
          tooltip: integrations.photoRequestsCount > 0
              ? 'Фото и запросы фото'
              : 'Фото',
          icon: Icons.photo_camera_rounded,
          count: integrations.photosCount + integrations.photoRequestsCount,
        ),
      if (integrations.assembliesCount > 0)
        _IntegrationBadge(
          tooltip: 'Сборки',
          icon: Icons.inventory_2_rounded,
          count: integrations.assembliesCount,
        ),
      if (integrations.invoicesCount > 0)
        _IntegrationBadge(
          tooltip: 'Счета',
          icon: Icons.receipt_long_rounded,
          count: integrations.invoicesCount,
        ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: context.brandPrimary.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.brandPrimary.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              integrations.hasAny
                  ? tr(
                      context,
                      ru: 'Сервисы $companyName',
                      zh: '$companyName服务',
                    )
                  : tr(
                      context,
                      ru: 'Сервисы $companyName не связаны',
                      zh: '未关联$companyName服务',
                    ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Gilroy',
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (badges.isNotEmpty) ...[
            const SizedBox(width: 6),
            Expanded(
              flex: 3,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < badges.length; index++) ...[
                      badges[index],
                      if (index < badges.length - 1) const SizedBox(width: 4),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _IntegrationBadge extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final int count;

  const _IntegrationBadge({
    required this.tooltip,
    required this.icon,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$tooltip: $count',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: context.brandPrimary.withValues(alpha: 0.14),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: context.brandPrimary, size: 12),
            const SizedBox(width: 2),
            Text(
              '$count',
              style: TextStyle(
                color: context.brandPrimary,
                fontFamily: 'Gilroy',
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final bool isActive;

  const _StatusPill({required this.label, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final color = isActive ? context.brandPrimary : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontFamily: 'Gilroy',
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetricChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.025)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: context.brandPrimary, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Gilroy',
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpV2EmptyCard extends StatelessWidget {
  const _SpV2EmptyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        children: [
          Icon(
            Icons.add_business_rounded,
            color: context.brandPrimary,
            size: 38,
          ),
          const SizedBox(height: 12),
          const Text(
            'Создайте первую совместную покупку',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Gilroy',
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Совместная покупка теперь начинается до сборки: сначала клиенты и товары, потом выкуп, треки, расчёт и отправки.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Gilroy',
              fontSize: 13,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CreatePurchaseSheet extends ConsumerStatefulWidget {
  final bool purchaseKindsEnabled;

  const _CreatePurchaseSheet({required this.purchaseKindsEnabled});

  @override
  ConsumerState<_CreatePurchaseSheet> createState() =>
      _CreatePurchaseSheetState();
}

class _CreatePurchaseSheetState extends ConsumerState<_CreatePurchaseSheet> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _purchaseRateController = TextEditingController();
  String _kind = 'group';
  String _currency = 'CNY';
  late SpPurchaseCreationTimelineValue _timeline;
  SpV2ClientCardSections _clientCardSections = const SpV2ClientCardSections();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _timeline = SpPurchaseCreationTimelineValue.initial();
    _titleController.text =
        'СП от ${DateFormat('dd.MM.yyyy').format(DateTime.now())}';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _purchaseRateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SpFinanceModalSurface(
        icon: Icons.add_business_rounded,
        title: 'Новая СП',
        subtitle: 'Основные параметры, статусы и данные для клиентов',
        maxHeightFactor: 0.92,
        keyboardAware: true,
        contentPadding: EdgeInsets.zero,
        body: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          children: [
            if (widget.purchaseKindsEnabled) ...[
              SpOrganizerPurchaseKindSelector(
                value: _kind,
                onChanged: (value) => setState(() => _kind = value),
              ),
              const SizedBox(height: 10),
            ],
            SpCurrencySelector(
              value: _currency,
              onChanged: (value) => setState(() => _currency = value),
            ),
            const SizedBox(height: 10),
            SpInfoNotice(
              title: 'На что влияет валюта',
              message: _currency == 'CNY'
                  ? 'Цены выкупа и цены для клиента будут вводиться в юанях. Чтобы финансы и оплаты считались в рублях, укажите курс ¥ → ₽.'
                  : 'Цены выкупа и цены для клиента будут вводиться сразу в рублях. Курс юаня для этой СП не нужен.',
              icon: _currency == 'CNY'
                  ? Icons.currency_yuan_rounded
                  : Icons.currency_ruble_rounded,
            ),
            if (_currency == 'CNY') ...[
              const SizedBox(height: 10),
              TextField(
                controller: _purchaseRateController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: SpFinanceUi.inputDecoration(
                  context,
                  labelText: 'Курс юаня',
                  hintText: 'Например: 12.80',
                  suffixText: '₽ за ¥',
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _titleController,
              decoration: SpFinanceUi.inputDecoration(
                context,
                labelText: 'Название СП',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descriptionController,
              minLines: 2,
              maxLines: 4,
              decoration: SpFinanceUi.inputDecoration(
                context,
                labelText: 'Комментарий',
                hintText: 'Например: закупка обуви / майский выкуп',
              ),
            ),
            const SizedBox(height: 12),
            SpPurchaseStatusDatesEditor(
              value: _timeline,
              onChanged: (value) => setState(() => _timeline = value),
            ),
            const SizedBox(height: 12),
            SpPurchaseClientSectionsEditor(
              value: _clientCardSections,
              onChanged: (value) => setState(() => _clientCardSections = value),
            ),
          ],
        ),
        footer: SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded),
            label: const Text('Создать СП'),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.brandPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              textStyle: const TextStyle(
                fontFamily: 'Gilroy',
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      final purchase = await ref
          .read(spV2PurchasesControllerProvider.notifier)
          .createPurchase(
            CreateSpV2PurchaseInput(
              title: title,
              kind: widget.purchaseKindsEnabled ? _kind : null,
              description: _descriptionController.text.trim(),
              status: _timeline.backendStatus,
              currency: _currency,
              purchaseRate: _currency == 'CNY'
                  ? _readDouble(_purchaseRateController.text)
                  : null,
              startedAt: _timeline.startedAt,
              dispatchedFromChinaAt: _timeline.dispatchedFromChinaAt,
              completedAt: _timeline.completedAt,
              clientCardSections: _clientCardSections,
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop(purchase);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  double? _readDouble(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }
}
