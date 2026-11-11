import '../../../core/ui/app_search_field.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branding/company_branding_provider.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/utils/locale_text.dart';
import '../data/sp_organizer_fulfillment_models.dart';
import '../data/sp_organizer_models.dart';
import '../data/sp_organizer_provider.dart';
import 'sp_finance_ui.dart';

Future<bool?> showSpOrganizerFulfillmentLinkSheet({
  required BuildContext context,
  required int purchaseId,
  required SpOrganizerFulfillmentOverview overview,
  required SpOrganizerCapabilities capabilities,
}) {
  return showSpFinanceModalSheet<bool>(
    context: context,
    builder: (context) => _SpOrganizerFulfillmentLinkSheet(
      purchaseId: purchaseId,
      overview: overview,
      capabilities: capabilities,
    ),
  );
}

class _SpOrganizerFulfillmentLinkSheet extends ConsumerStatefulWidget {
  final int purchaseId;
  final SpOrganizerFulfillmentOverview overview;
  final SpOrganizerCapabilities capabilities;

  const _SpOrganizerFulfillmentLinkSheet({
    required this.purchaseId,
    required this.overview,
    required this.capabilities,
  });

  @override
  ConsumerState<_SpOrganizerFulfillmentLinkSheet> createState() =>
      _SpOrganizerFulfillmentLinkSheetState();
}

class _SpOrganizerFulfillmentLinkSheetState
    extends ConsumerState<_SpOrganizerFulfillmentLinkSheet> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  late final List<SpOrganizerFulfillmentLinkKind> _availableKinds;
  late SpOrganizerFulfillmentLinkKind _kind;
  int? _itemId;
  List<SpOrganizerFulfillmentCandidate> _candidates = const [];
  SpOrganizerFulfillmentCandidate? _selected;
  int _page = 1;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _saving = false;
  int _loadRevision = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _availableKinds = SpOrganizerFulfillmentLinkKind.values
        .where(_isKindAvailable)
        .toList(growable: false);
    _kind = _preferredInitialKind();
    _itemId = widget.overview.items.isEmpty
        ? null
        : widget.overview.items.first.id;
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool _isKindAvailable(SpOrganizerFulfillmentLinkKind kind) {
    return switch (kind) {
      SpOrganizerFulfillmentLinkKind.selfBuyout =>
        widget.capabilities.selfBuyoutLinks,
      SpOrganizerFulfillmentLinkKind.garage => widget.capabilities.garageImport,
      SpOrganizerFulfillmentLinkKind.track => widget.capabilities.trackLinks,
      SpOrganizerFulfillmentLinkKind.assembly =>
        widget.capabilities.assemblyLinks,
      SpOrganizerFulfillmentLinkKind.invoice =>
        widget.capabilities.invoiceLinks,
    };
  }

  SpOrganizerFulfillmentLinkKind _preferredInitialKind() {
    if (widget.overview.items.isEmpty) {
      for (final kind in _availableKinds) {
        if (!kind.itemScoped) return kind;
      }
    }
    return _availableKinds.first;
  }

  @override
  Widget build(BuildContext context) {
    final companyName = ref.watch(companyNameProvider);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(18, 4, 18, 18 + bottomInset),
              children: [
                Text(
                  tr(context, ru: 'Что связать', zh: '选择关联类型'),
                  style: SpFinanceUi.sectionTitleStyle,
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: _availableKinds
                      .map(
                        (kind) => ChoiceChip(
                          avatar: Icon(_kindIcon(kind), size: 17),
                          label: Text(_kindLabel(context, kind)),
                          selected: _kind == kind,
                          onSelected:
                              kind.itemScoped && widget.overview.items.isEmpty
                              ? null
                              : (_) => _selectKind(kind),
                        ),
                      )
                      .toList(growable: false),
                ),
                if (_kind.itemScoped) ...[
                  const SizedBox(height: 12),
                  if (widget.overview.items.isEmpty)
                    _LinkNotice(
                      icon: Icons.inventory_2_outlined,
                      message: tr(
                        context,
                        ru: 'В закупке нет товаров для связи.',
                        zh: '采购中没有可关联的商品。',
                      ),
                    )
                  else
                    DropdownButtonFormField<int>(
                      initialValue: _itemId,
                      isExpanded: true,
                      decoration: SpFinanceUi.inputDecoration(
                        context,
                        labelText: tr(context, ru: 'Товар закупки', zh: '采购商品'),
                        prefixIcon: Icons.shopping_bag_outlined,
                      ),
                      items: widget.overview.items
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.id,
                              child: Text(
                                item.title,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _selectItem,
                    ),
                ],
                const SizedBox(height: 12),
                AppSearchField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  onSubmitted: (_) => _load(),
                  textInputAction: TextInputAction.search,
                  hintText: _searchHint(context, _kind, companyName),
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  _LinkNotice(
                    icon: Icons.error_outline_rounded,
                    message: tr(
                      context,
                      ru: 'Не удалось загрузить доступные операции $companyName.',
                      zh: '无法加载可用的$companyName操作。',
                    ),
                    actionLabel: tr(context, ru: 'Повторить', zh: '重试'),
                    onAction: _load,
                  )
                else if (_candidates.isEmpty)
                  _LinkNotice(
                    icon: Icons.search_off_rounded,
                    message: tr(
                      context,
                      ru: 'Подходящие операции не найдены.',
                      zh: '未找到合适的操作。',
                    ),
                  )
                else ...[
                  for (final candidate in _candidates)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _CandidateTile(
                        candidate: candidate,
                        selected: _selected?.id == candidate.id,
                        onTap: candidate.linked
                            ? null
                            : () => setState(() => _selected = candidate),
                      ),
                    ),
                  if (_hasMore)
                    Center(
                      child: TextButton.icon(
                        onPressed: _loadingMore ? null : _loadMore,
                        icon: _loadingMore
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.expand_more_rounded),
                        label: Text(
                          tr(context, ru: 'Показать ещё', zh: '加载更多'),
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 6),
                _LinkNotice(
                  icon: Icons.shield_outlined,
                  message: tr(
                    context,
                    ru: 'Создаётся только связь с существующей операцией. Статусы, суммы и данные $companyName не изменяются; отвязка здесь не предусмотрена.',
                    zh: '仅创建与现有操作的关联。$companyName状态、金额和数据不会更改；此处不支持取消关联。',
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              10,
              18,
              18 + MediaQuery.paddingOf(context).bottom,
            ),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                onPressed:
                    _saving ||
                        _selected == null ||
                        (_kind.itemScoped && _itemId == null)
                    ? null
                    : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add_link_rounded),
                label: Text(tr(context, ru: 'Добавить связь', zh: '添加关联')),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final companyName = ref.watch(companyNameProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 10, 10),
      child: Column(
        children: [
          Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFE1E5ED),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.brandPrimary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.hub_outlined, color: context.brandPrimary),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(
                        context,
                        ru: 'Связать с операцией $companyName',
                        zh: '关联$companyName操作',
                      ),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Gilroy',
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tr(
                        context,
                        ru: 'Выберите подходящую сборку для товаров',
                        zh: '为商品选择合适的集运',
                      ),
                      style: SpFinanceUi.labelStyle,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: tr(context, ru: 'Закрыть', zh: '关闭'),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _selectKind(SpOrganizerFulfillmentLinkKind kind) {
    if (_kind == kind) return;
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _kind = kind;
      _selected = null;
      _candidates = const [];
    });
    _load();
  }

  void _selectItem(int? itemId) {
    if (_itemId == itemId) return;
    setState(() {
      _itemId = itemId;
      _selected = null;
      _candidates = const [];
    });
    _load();
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _load({bool append = false}) async {
    final requestRevision = ++_loadRevision;
    if (_kind.itemScoped && _itemId == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _candidates = const [];
        _hasMore = false;
      });
      return;
    }
    final requestedKind = _kind;
    final requestedItemId = _itemId;
    final requestedQuery = _searchController.text.trim();
    final requestedPage = append ? _page + 1 : 1;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
        _selected = null;
      }
      _error = null;
    });
    try {
      final page = await ref
          .read(spOrganizerRepositoryProvider)
          .getFulfillmentCandidates(
            purchaseId: widget.purchaseId,
            kind: requestedKind,
            itemId: requestedItemId,
            query: requestedQuery,
            page: requestedPage,
          );
      if (!mounted ||
          requestRevision != _loadRevision ||
          requestedKind != _kind ||
          requestedItemId != _itemId ||
          requestedQuery != _searchController.text.trim()) {
        return;
      }
      setState(() {
        _page = page.page;
        _hasMore = page.hasMore;
        _candidates = append
            ? _mergeCandidates(_candidates, page.candidates)
            : page.candidates;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || requestRevision != _loadRevision) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadMore() => _load(append: true);

  Future<void> _save() async {
    if (_saving) return;
    final selected = _selected;
    if (selected == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(spOrganizerRepositoryProvider)
          .linkFulfillmentCandidate(
            purchaseId: widget.purchaseId,
            kind: _kind,
            targetId: selected.id,
            itemId: _itemId,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${tr(context, ru: 'Не удалось добавить связь', zh: '无法添加关联')}: $error',
          ),
        ),
      );
    }
  }
}

class _CandidateTile extends StatelessWidget {
  final SpOrganizerFulfillmentCandidate candidate;
  final bool selected;
  final VoidCallback? onTap;

  const _CandidateTile({
    required this.candidate,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    final statusColor =
        SpFinanceUi.parseHexColor(candidate.status.color) ??
        context.brandPrimary;
    return Material(
      color: selected
          ? context.brandPrimary.withValues(alpha: 0.08)
          : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? context.brandPrimary : const Color(0xFFE7EAF0),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      candidate.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SpFinanceUi.bodyStyle.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (candidate.subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        candidate.subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SpFinanceUi.labelStyle,
                      ),
                    ],
                    if (candidate.amountRub != null ||
                        candidate.amountCny != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        _candidateAmount(candidate),
                        style: SpFinanceUi.bodyStyle.copyWith(
                          color: context.brandPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        _SmallBadge(
                          label: candidate.status.labelFor(languageCode),
                          color: statusColor,
                        ),
                        if (candidate.linked)
                          _SmallBadge(
                            label: tr(context, ru: 'Уже связано', zh: '已关联'),
                            color: const Color(0xFF64748B),
                          )
                        else if (candidate.legacyLinked)
                          _SmallBadge(
                            label: tr(context, ru: 'Legacy-связь', zh: '旧版关联'),
                            color: const Color(0xFFD97706),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                candidate.linked
                    ? Icons.check_circle_outline_rounded
                    : selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: candidate.linked
                    ? AppColors.textSecondary
                    : selected
                    ? context.brandPrimary
                    : AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _SmallBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: SpFinanceUi.labelStyle.copyWith(color: color)),
    );
  }
}

class _LinkNotice extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _LinkNotice({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: SpFinanceUi.softDecoration(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: context.brandPrimary, size: 20),
          const SizedBox(width: 9),
          Expanded(child: Text(message, style: SpFinanceUi.labelStyle)),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

List<SpOrganizerFulfillmentCandidate> _mergeCandidates(
  List<SpOrganizerFulfillmentCandidate> current,
  List<SpOrganizerFulfillmentCandidate> next,
) {
  final result = [...current];
  final ids = current.map((candidate) => candidate.id).toSet();
  for (final candidate in next) {
    if (ids.add(candidate.id)) result.add(candidate);
  }
  return result;
}

IconData _kindIcon(SpOrganizerFulfillmentLinkKind kind) {
  return switch (kind) {
    SpOrganizerFulfillmentLinkKind.selfBuyout => Icons.currency_yuan_rounded,
    SpOrganizerFulfillmentLinkKind.garage =>
      Icons.directions_car_filled_outlined,
    SpOrganizerFulfillmentLinkKind.track => Icons.qr_code_2_rounded,
    SpOrganizerFulfillmentLinkKind.assembly => Icons.inventory_2_outlined,
    SpOrganizerFulfillmentLinkKind.invoice => Icons.receipt_long_outlined,
  };
}

String _kindLabel(BuildContext context, SpOrganizerFulfillmentLinkKind kind) {
  return switch (kind) {
    SpOrganizerFulfillmentLinkKind.selfBuyout => tr(
      context,
      ru: 'Самовыкуп',
      zh: '自主采购',
    ),
    SpOrganizerFulfillmentLinkKind.garage => tr(context, ru: 'Гараж', zh: '车库'),
    SpOrganizerFulfillmentLinkKind.track => tr(context, ru: 'Трек', zh: '运单'),
    SpOrganizerFulfillmentLinkKind.assembly => tr(
      context,
      ru: 'Сборка',
      zh: '集货',
    ),
    SpOrganizerFulfillmentLinkKind.invoice => tr(context, ru: 'Счёт', zh: '账单'),
  };
}

String _searchHint(
  BuildContext context,
  SpOrganizerFulfillmentLinkKind kind,
  String companyName,
) {
  return switch (kind) {
    SpOrganizerFulfillmentLinkKind.selfBuyout => tr(
      context,
      ru: 'Номер заявки самовыкупа',
      zh: '自主采购申请编号',
    ),
    SpOrganizerFulfillmentLinkKind.garage => tr(
      context,
      ru: 'Деталь, артикул или заказ Garage',
      zh: '零件、货号或Garage订单',
    ),
    SpOrganizerFulfillmentLinkKind.track => tr(
      context,
      ru: 'Номер китайского трека',
      zh: '中国运单号',
    ),
    SpOrganizerFulfillmentLinkKind.assembly => tr(
      context,
      ru: 'Номер или название сборки',
      zh: '集货编号或名称',
    ),
    SpOrganizerFulfillmentLinkKind.invoice => tr(
      context,
      ru: 'Номер счёта $companyName',
      zh: '$companyName账单编号',
    ),
  };
}

String _candidateAmount(SpOrganizerFulfillmentCandidate candidate) {
  final values = <String>[
    if (candidate.amountCny != null)
      '${candidate.amountCny!.toStringAsFixed(2).replaceAll('.', ',')} ¥',
    if (candidate.amountRub != null)
      '${candidate.amountRub!.toStringAsFixed(2).replaceAll('.', ',')} ₽',
  ];
  return values.join(' · ');
}
