import '../../../core/ui/app_search_field.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/app_cached_media_image.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/utils/locale_text.dart';
import '../data/sp_organizer_provider.dart';
import '../data/sp_organizer_purchase_blank_models.dart';
import '../data/sp_v2_provider.dart';
import 'sp_finance_ui.dart';

Future<bool?> showSpOrganizerPurchaseBlankImportSheet({
  required BuildContext context,
  required int purchaseId,
}) {
  return showSpFinanceModalSheet<bool>(
    context: context,
    builder: (context) =>
        _SpOrganizerPurchaseBlankImportSheet(purchaseId: purchaseId),
  );
}

class _SpOrganizerPurchaseBlankImportSheet extends ConsumerStatefulWidget {
  final int purchaseId;

  const _SpOrganizerPurchaseBlankImportSheet({required this.purchaseId});

  @override
  ConsumerState<_SpOrganizerPurchaseBlankImportSheet> createState() =>
      _SpOrganizerPurchaseBlankImportSheetState();
}

class _SpOrganizerPurchaseBlankImportSheetState
    extends ConsumerState<_SpOrganizerPurchaseBlankImportSheet> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<SpOrganizerPurchaseBlankCandidate> _candidates = const [];
  SpOrganizerPurchaseBlankCandidate? _selected;
  int? _customerId;
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
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(spV2CustomersProvider);
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
                const _ImportNotice(
                  icon: Icons.shield_outlined,
                  message:
                      'Бланк останется без изменений. В СП копируются название, ссылка, параметры, количество, цена выкупа и фото; цену для участника можно задать отдельно.',
                ),
                const SizedBox(height: 12),
                customers.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => _ImportNotice(
                    icon: Icons.error_outline_rounded,
                    message: tr(
                      context,
                      ru: 'Не удалось загрузить клиентов организатора.',
                      zh: '无法加载团购客户。',
                    ),
                  ),
                  data: (items) => items.isEmpty
                      ? _ImportNotice(
                          icon: Icons.person_add_alt_1_outlined,
                          message: tr(
                            context,
                            ru: 'Сначала добавьте клиента в закупку.',
                            zh: '请先在采购中添加客户。',
                          ),
                        )
                      : DropdownButtonFormField<int>(
                          key: const ValueKey(
                            'purchase-blank-customer-selector',
                          ),
                          initialValue: _customerId,
                          isExpanded: true,
                          decoration: SpFinanceUi.inputDecoration(
                            context,
                            labelText: tr(
                              context,
                              ru: 'Участник закупки',
                              zh: '采购参与者',
                            ),
                            prefixIcon: Icons.person_outline_rounded,
                          ),
                          items: items
                              .map(
                                (customer) => DropdownMenuItem<int>(
                                  value: customer.id,
                                  child: Text(
                                    customer.fullName,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) =>
                              setState(() => _customerId = value),
                        ),
                ),
                const SizedBox(height: 12),
                AppSearchField(
                  key: const ValueKey('purchase-blank-search'),
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  onSubmitted: (_) => _load(),
                  textInputAction: TextInputAction.search,
                  hintText: tr(
                    context,
                    ru: 'Название, ссылка, трек или параметры',
                    zh: '名称、链接、运单号或规格',
                  ),
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  _ImportNotice(
                    icon: Icons.error_outline_rounded,
                    message: tr(
                      context,
                      ru: 'Не удалось загрузить позиции из бланков.',
                      zh: '无法加载采购单商品。',
                    ),
                    actionLabel: tr(context, ru: 'Повторить', zh: '重试'),
                    onAction: _load,
                  )
                else if (_candidates.isEmpty)
                  _ImportNotice(
                    icon: Icons.search_off_rounded,
                    message: tr(
                      context,
                      ru: 'Подходящие позиции не найдены.',
                      zh: '未找到合适的商品。',
                    ),
                  )
                else ...[
                  for (final candidate in _candidates)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PurchaseBlankCandidateTile(
                        candidate: candidate,
                        selected: _selected?.id == candidate.id,
                        onTap: candidate.imported
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
                key: const ValueKey('purchase-blank-import-submit'),
                onPressed: _saving || _selected == null || _customerId == null
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
                    : const Icon(Icons.download_done_rounded),
                label: Text(tr(context, ru: 'Импортировать в СП', zh: '导入团购')),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
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
                child: Icon(
                  Icons.receipt_long_outlined,
                  color: context.brandPrimary,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(context, ru: 'Импорт из бланка выкупа', zh: '从采购单导入'),
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
                        ru: 'Без повторного заполнения карточки товара',
                        zh: '无需重复填写商品信息',
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

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _load({bool append = false}) async {
    final requestRevision = ++_loadRevision;
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
          .getPurchaseBlankImportCandidates(
            purchaseId: widget.purchaseId,
            query: requestedQuery,
            page: requestedPage,
          );
      if (!mounted ||
          requestRevision != _loadRevision ||
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
    final customerId = _customerId;
    if (selected == null || customerId == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(spOrganizerRepositoryProvider)
          .importPurchaseBlankItem(
            purchaseId: widget.purchaseId,
            purchaseBlankItemId: selected.id,
            customerId: customerId,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${tr(context, ru: 'Не удалось импортировать товар', zh: '无法导入商品')}: $error',
          ),
        ),
      );
    }
  }
}

class _PurchaseBlankCandidateTile extends StatelessWidget {
  final SpOrganizerPurchaseBlankCandidate candidate;
  final bool selected;
  final VoidCallback? onTap;

  const _PurchaseBlankCandidateTile({
    required this.candidate,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final photoUrl = candidate.primaryPhotoUrl;
    return Material(
      color: selected
          ? context.brandPrimary.withValues(alpha: 0.08)
          : candidate.imported
          ? const Color(0xFFF1F5F9)
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
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: photoUrl == null
                      ? Container(
                          color: const Color(0xFFEFF3F8),
                          child: const Icon(
                            Icons.inventory_2_outlined,
                            color: AppColors.textSecondary,
                          ),
                        )
                      : AppCachedMediaImage(
                          url: photoUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 192,
                          memCacheHeight: 192,
                        ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      candidate.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Gilroy',
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        _MetaChip(
                          label:
                              'Бланк №${candidate.blankId} · #${candidate.orderNumber}',
                        ),
                        _MetaChip(label: '${candidate.quantity} шт.'),
                        if (candidate.unitPriceYuan != null)
                          _MetaChip(
                            label:
                                '${_formatNumber(candidate.unitPriceYuan!)} ¥/шт.',
                          ),
                        if (candidate.trackNumber != null)
                          _MetaChip(label: candidate.trackNumber!),
                        if (candidate.imported)
                          _MetaChip(
                            label: tr(
                              context,
                              ru: 'Уже импортирован',
                              zh: '已导入',
                            ),
                            highlighted: true,
                          ),
                      ],
                    ),
                    if (candidate.characteristics != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        candidate.characteristics!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SpFinanceUi.labelStyle,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                candidate.imported
                    ? Icons.check_circle_rounded
                    : selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: candidate.imported
                    ? const Color(0xFF16A34A)
                    : selected
                    ? context.brandPrimary
                    : AppColors.textSecondary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final bool highlighted;

  const _MetaChip({required this.label, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFDCFCE7) : const Color(0xFFEFF3F8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: highlighted
              ? const Color(0xFF15803D)
              : AppColors.textSecondary,
          fontFamily: 'Gilroy',
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ImportNotice extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _ImportNotice({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: SpFinanceUi.softDecoration(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: context.brandPrimary),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Gilroy',
                fontSize: 12,
                height: 1.3,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

List<SpOrganizerPurchaseBlankCandidate> _mergeCandidates(
  List<SpOrganizerPurchaseBlankCandidate> current,
  List<SpOrganizerPurchaseBlankCandidate> next,
) {
  final byId = {
    for (final candidate in current) candidate.id: candidate,
    for (final candidate in next) candidate.id: candidate,
  };
  return byId.values.toList(growable: false);
}

String _formatNumber(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
