import '../../../core/ui/app_search_field.dart';
import '../../../core/utils/locale_text.dart';
import '../../tracks/data/tracks_provider.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/app_cached_media_image.dart';
import '../../../core/ui/app_colors.dart';
import '../data/sp_organizer_provider.dart';
import '../data/sp_organizer_track_import_models.dart';
import '../data/sp_v2_provider.dart';
import 'sp_finance_ui.dart';

Future<bool?> showSpOrganizerTrackImportSheet({
  required BuildContext context,
  required int purchaseId,
}) {
  return showSpFinanceModalSheet<bool>(
    context: context,
    builder: (context) => _SpOrganizerTrackImportSheet(purchaseId: purchaseId),
  );
}

class _SpOrganizerTrackImportSheet extends ConsumerStatefulWidget {
  final int purchaseId;

  const _SpOrganizerTrackImportSheet({required this.purchaseId});

  @override
  ConsumerState<_SpOrganizerTrackImportSheet> createState() =>
      _SpOrganizerTrackImportSheetState();
}

class _SpOrganizerTrackImportSheetState
    extends ConsumerState<_SpOrganizerTrackImportSheet> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<SpOrganizerTrackImportCandidate> _candidates = const [];
  SpOrganizerTrackImportCandidate? _selected;
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
    final selectedAlreadyLinked =
        _selected?.isLinkedToCustomer(_customerId) ?? false;

    return SpFinanceModalSurface(
      key: const ValueKey('track-import-modal'),
      icon: Icons.qr_code_2_rounded,
      title: 'Добавить из трека',
      subtitle:
          'Выберите участника и его товар. Фото, название, количество и трек-номер перенесутся в СП.',
      maxHeightFactor: 0.92,
      keyboardAware: true,
      body: ListView(
        key: const ValueKey('track-import-list'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(top: 14),
        children: [
          const _TrackImportNotice(
            icon: Icons.shield_outlined,
            message:
                'Трек, его статус, фотоотчёты и складские данные не изменяются. В закупке создаётся отдельная карточка со связью на исходный трек.',
          ),
          const SizedBox(height: 12),
          _ImportStepTitle(
            number: '1',
            title: 'Кому принадлежит товар',
            subtitle: 'Позиция появится у выбранного участника закупки.',
          ),
          const SizedBox(height: 9),
          customers.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const _TrackImportNotice(
              icon: Icons.error_outline_rounded,
              message: 'Не удалось загрузить участников закупки.',
            ),
            data: (items) => items.isEmpty
                ? const _TrackImportNotice(
                    icon: Icons.person_add_alt_1_outlined,
                    message:
                        'Сначала добавьте участника во вкладке «Участники».',
                  )
                : DropdownButtonFormField<int>(
                    key: const ValueKey('track-import-customer-selector'),
                    initialValue: _customerId,
                    isExpanded: true,
                    decoration: SpFinanceUi.inputDecoration(
                      context,
                      labelText: 'Участник закупки',
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
                    onChanged: (value) => setState(() => _customerId = value),
                  ),
          ),
          const SizedBox(height: 18),
          _ImportStepTitle(
            number: '2',
            title: 'Выберите трек',
            subtitle: 'Ищите по трек-номеру или названию товара.',
          ),
          const SizedBox(height: 9),
          AppSearchField(
            key: const ValueKey('track-import-search'),
            controller: _searchController,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            hintText: 'Например, 773… или «куртка»',
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 34),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _TrackImportNotice(
              icon: Icons.error_outline_rounded,
              message: 'Не удалось загрузить треки.',
              actionLabel: 'Повторить',
              onAction: _load,
            )
          else if (_candidates.isEmpty)
            const _TrackImportNotice(
              icon: Icons.inventory_2_outlined,
              message:
                  'Подходящих треков не найдено. Измените запрос или проверьте, что трек добавлен в личный кабинет.',
            )
          else ...[
            for (final candidate in _candidates) ...[
              _TrackImportCandidateTile(
                candidate: candidate,
                selected: _selected?.id == candidate.id,
                linkedToSelectedCustomer: candidate.isLinkedToCustomer(
                  _customerId,
                ),
                onTap: () => setState(() => _selected = candidate),
              ),
              const SizedBox(height: 9),
            ],
            if (_hasMore)
              OutlinedButton.icon(
                onPressed: _loadingMore ? null : _loadMore,
                icon: _loadingMore
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more_rounded),
                label: const Text('Показать ещё'),
              ),
          ],
        ],
      ),
      footer: FilledButton.icon(
        key: const ValueKey('track-import-submit'),
        onPressed:
            _saving ||
                _selected == null ||
                _customerId == null ||
                selectedAlreadyLinked
            ? null
            : _save,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: context.brandPrimary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Gilroy',
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        icon: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(
                selectedAlreadyLinked
                    ? Icons.check_circle_rounded
                    : Icons.add_rounded,
              ),
        label: Text(
          selectedAlreadyLinked
              ? 'Уже добавлен этому участнику'
              : 'Добавить товар из трека',
        ),
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
          .getTrackImportCandidates(
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
            ? _mergeTrackCandidates(_candidates, page.candidates)
            : page.candidates;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || requestRevision != _loadRevision) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = 'load_failed';
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
          .importTrackItem(
            purchaseId: widget.purchaseId,
            trackId: selected.id,
            customerId: customerId,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось добавить товар из трека: $error')),
      );
    }
  }
}

class _ImportStepTitle extends StatelessWidget {
  final String number;
  final String title;
  final String subtitle;

  const _ImportStepTitle({
    required this.number,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.brandPrimary,
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'Gilroy',
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: SpFinanceUi.bodyStyle),
              const SizedBox(height: 2),
              Text(subtitle, style: SpFinanceUi.labelStyle),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrackImportCandidateTile extends ConsumerWidget {
  final SpOrganizerTrackImportCandidate candidate;
  final bool selected;
  final bool linkedToSelectedCustomer;
  final VoidCallback onTap;

  const _TrackImportCandidateTile({
    required this.candidate,
    required this.selected,
    required this.linkedToSelectedCustomer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoUrl = candidate.primaryPhotoUrl;
    final statuses =
        ref.watch(trackStatusesProvider).asData?.value ?? const <TrackStatus>[];
    final metadata = statuses
        .where((s) => s.code == candidate.status)
        .firstOrNull;
    final statusText = metadata == null
        ? tr(context, ru: 'Статус уточняется', zh: '状态待更新')
        : isZh(context)
        ? metadata.nameZh ?? metadata.nameRu
        : metadata.nameRu;
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
              color: selected ? context.brandPrimary : const Color(0xFFE1E5ED),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 66,
                  height: 66,
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
                          memCacheWidth: 198,
                          memCacheHeight: 198,
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
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(
                          Icons.qr_code_2_rounded,
                          size: 15,
                          color: context.brandPrimary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            candidate.trackNumber,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.brandPrimary,
                              fontFamily: 'Gilroy',
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        _TrackMetaChip(label: '${candidate.quantity} шт.'),
                        if (candidate.clientCode.isNotEmpty)
                          _TrackMetaChip(label: candidate.clientCode),
                        if (candidate.status.isNotEmpty)
                          _TrackMetaChip(label: statusText),
                        if (linkedToSelectedCustomer)
                          const _TrackMetaChip(
                            label: 'Уже у участника',
                            highlighted: true,
                          )
                        else if (candidate.linkedCount > 0)
                          _TrackMetaChip(
                            label: 'В СП: ${candidate.linkedCount}',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                linkedToSelectedCustomer
                    ? Icons.check_circle_rounded
                    : selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: linkedToSelectedCustomer
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

class _TrackMetaChip extends StatelessWidget {
  final String label;
  final bool highlighted;

  const _TrackMetaChip({required this.label, this.highlighted = false});

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

class _TrackImportNotice extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _TrackImportNotice({
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

List<SpOrganizerTrackImportCandidate> _mergeTrackCandidates(
  List<SpOrganizerTrackImportCandidate> current,
  List<SpOrganizerTrackImportCandidate> next,
) {
  final byId = {
    for (final candidate in current) candidate.id: candidate,
    for (final candidate in next) candidate.id: candidate,
  };
  return byId.values.toList(growable: false);
}
