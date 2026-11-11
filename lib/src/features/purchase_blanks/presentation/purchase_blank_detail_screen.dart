import '../../../core/ui/unsaved_changes_guard.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_target.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:twoalogisticcabineuser/src/core/ui/blurred_modal_bottom_sheet.dart';

import '../../../core/ui/animated_hero_glow_backdrop.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/ui/app_layout.dart';
import '../../../core/ui/sheet_handle.dart';
import '../data/purchase_blank_model.dart';
import '../data/blank_item_save_session.dart';
import '../data/purchase_blanks_provider.dart';
import 'purchase_blank_ui.dart';
import 'widgets/blank_item_card.dart';
import 'widgets/blank_item_form.dart';

class PurchaseBlankDetailScreen extends ConsumerStatefulWidget {
  final int blankId;

  const PurchaseBlankDetailScreen({super.key, required this.blankId});

  @override
  ConsumerState<PurchaseBlankDetailScreen> createState() =>
      _PurchaseBlankDetailScreenState();
}

class _PurchaseBlankDetailScreenState
    extends ConsumerState<PurchaseBlankDetailScreen> {
  bool _showAddForm = false;
  int? _editingItemId;
  final _addFormKey = GlobalKey();
  BlankItemSaveSession? _addSaveSession;
  final _editSaveSessions = <int, BlankItemSaveSession>{};

  Future<void> _openAddForm() async {
    if ((_editingItemId != null || _showAddForm) &&
        !await confirmDiscardChanges(context)) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _showAddForm = true;
      _editingItemId = null;
      _addSaveSession = BlankItemSaveSession();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final formContext = _addFormKey.currentContext;
      if (formContext != null) {
        Scrollable.ensureVisible(
          formContext,
          duration: const Duration(milliseconds: 250),
          alignment: 0.08,
        );
      }
    });
  }

  Future<void> _openEditForm(int itemId) async {
    if ((_editingItemId != null || _showAddForm) &&
        !await confirmDiscardChanges(context)) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _showAddForm = false;
      _editingItemId = itemId;
    });
  }

  void _cancelAddForm() {
    final savedItemId = _addSaveSession?.savedItemId;
    setState(() {
      _showAddForm = false;
      _addSaveSession = null;
    });
    if (savedItemId != null) {
      ref.invalidate(purchaseBlankDetailProvider(widget.blankId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(purchaseBlankDetailProvider(widget.blankId));

    return detailAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text('Ошибка загрузки: $e'),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () =>
                  ref.invalidate(purchaseBlankDetailProvider(widget.blankId)),
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
      data: (blank) {
        if (blank == null) {
          return const Center(child: Text('Бланк не найден'));
        }
        return _buildContent(context, blank);
      },
    );
  }

  Widget _buildContent(BuildContext context, PurchaseBlank blank) {
    final isEditable = blank.status.isEditableByClient;
    final isCancellable = blank.status.isCancellableByClient;
    final topPad = AppLayout.topBarTotalHeight(context);
    final bottomPad = AppLayout.bottomScrollPadding(context);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(purchaseBlankDetailProvider(widget.blankId));
        await ref.read(purchaseBlankDetailProvider(widget.blankId).future);
      },
      color: context.brandPrimary,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, topPad * 0.7 + 16, 16, bottomPad + 16),
        children: [
          PurchaseBlankPageHeader(title: 'Бланк #${blank.id}'),
          const SizedBox(height: 12),

          // ── Сводка ──────────────────────────────────
          _buildHeaderSection(context, blank),
          const SizedBox(height: 14),

          // ── Финансовая информация ────────────────────
          _buildFinanceSection(context, blank),
          const SizedBox(height: 14),

          // ── Список товаров ───────────────────────────
          _buildItemsHeader(context, blank, isEditable),
          const SizedBox(height: 10),

          ...blank.items.map((item) {
            if (_editingItemId == item.id) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: BlankItemForm(
                  key: ValueKey('blank-item-${item.id}'),
                  existingItem: item,
                  onSave:
                      ({
                        required String productName,
                        required String productUrl,
                        String? characteristics,
                        required int quantity,
                        required double unitPrice,
                        List<Uint8List>? newPhotos,
                        List<String>? newPhotoNames,
                      }) async {
                        await _updateItem(
                          blank.id,
                          item.id,
                          productName: productName,
                          productUrl: productUrl,
                          characteristics: characteristics,
                          quantity: quantity,
                          unitPrice: unitPrice,
                          newPhotos: newPhotos,
                          newPhotoNames: newPhotoNames,
                        );
                      },
                  onCancel: () {
                    _editSaveSessions.remove(item.id);
                    setState(() => _editingItemId = null);
                    ref.invalidate(purchaseBlankDetailProvider(widget.blankId));
                  },
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: BlankItemCard(
                item: item,
                isEditable: isEditable,
                onEdit: () => _openEditForm(item.id),
                onDelete: () => _deleteItem(blank.id, item.id),
              ),
            );
          }),

          // ── Форма добавления товара ──────────────────
          if (_showAddForm && isEditable) ...[
            BlankItemForm(
              key: _addFormKey,
              onSave:
                  ({
                    required String productName,
                    required String productUrl,
                    String? characteristics,
                    required int quantity,
                    required double unitPrice,
                    List<Uint8List>? newPhotos,
                    List<String>? newPhotoNames,
                  }) async {
                    await _addItem(
                      blank.id,
                      productName: productName,
                      productUrl: productUrl,
                      characteristics: characteristics,
                      quantity: quantity,
                      unitPrice: unitPrice,
                      newPhotos: newPhotos,
                      newPhotoNames: newPhotoNames,
                    );
                  },
              onCancel: _cancelAddForm,
            ),
            const SizedBox(height: 16),
          ],

          // ── Пустое состояние товаров ─────────────────
          if (blank.items.isEmpty && !_showAddForm)
            _buildEmptyItemsState(context, isEditable),

          // ── Кнопки действий ──────────────────────────
          if (isEditable) ...[
            const SizedBox(height: 16),
            _buildActionButtons(context, blank, isCancellable),
          ] else if (!blank.status.isFinal) ...[
            const SizedBox(height: 16),
            _buildReadOnlyNotice(context, blank, isCancellable),
          ],

          // ── Сноска ──────────────────────────────────
          if (!isEditable && !blank.status.isFinal) ...[
            const SizedBox(height: 20),
            Text(
              'Бланк на рассмотрении. Редактирование невозможно.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Заголовок ──────────────────────────────────────────────

  Widget _buildHeaderSection(BuildContext context, PurchaseBlank blank) {
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');

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
            const Positioned.fill(child: AnimatedHeroGlowBackdrop()),
            Padding(
              padding: const EdgeInsets.all(16),
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
                          Icons.assignment_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Бланк #${blank.id}',
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
                              'Создан ${dateFormat.format(blank.createdAt)}',
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
                      PurchaseBlankHeroChip(
                        icon: Icons.shopping_bag_rounded,
                        label: '${blank.itemsCount} товаров',
                      ),
                      PurchaseBlankHeroChip(
                        icon: Icons.currency_yuan_rounded,
                        label: blank.clientTotalCny > 0
                            ? '¥${blank.clientTotalCny.toStringAsFixed(2)}'
                            : 'Сумма не указана',
                      ),
                      PurchaseBlankHeroChip(
                        icon: blank.status.icon,
                        label: blank.status.localizedLabel(context),
                      ),
                    ],
                  ),
                  if (blank.employeeComment != null &&
                      blank.employeeComment!.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.20),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.comment_rounded,
                            size: 17,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              blank.employeeComment!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'Gilroy',
                                fontSize: 12.8,
                                height: 1.24,
                                fontWeight: FontWeight.w700,
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
          ],
        ),
      ),
    );
  }

  // ── Финансовая секция ──────────────────────────────────────

  Widget _buildFinanceSection(BuildContext context, PurchaseBlank blank) {
    final chinaShippingTotal = blank.items.fold<double>(
      0,
      (sum, item) => sum + (item.chinaShippingCostYuan ?? 0),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: PurchaseBlankUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  Icons.payments_rounded,
                  color: context.brandPrimary,
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Финансы',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Gilroy',
                        fontSize: 18,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Стоимость товаров, комиссия и итог после проверки',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontFamily: 'Gilroy',
                        fontSize: 12.5,
                        height: 1.18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black.withValues(alpha: 0.025)),
            ),
            child: Column(
              children: [
                _FinanceRow(
                  label: 'Стоимость товаров',
                  value: blank.clientTotalCny > 0
                      ? '¥${blank.clientTotalCny.toStringAsFixed(2)}'
                      : '—',
                  isEmpty: blank.clientTotalCny == 0,
                ),
                _FinanceRow(
                  label: 'Комиссия за выкуп',
                  value: blank.commissionPercent != null
                      ? '${blank.commissionPercent!.toStringAsFixed(1)}%'
                      : '—',
                  isEmpty: blank.commissionPercent == null,
                ),
                _FinanceRow(
                  label: 'Доставка по Китаю',
                  value: chinaShippingTotal > 0
                      ? '¥${chinaShippingTotal.toStringAsFixed(2)}'
                      : '—',
                  isEmpty: chinaShippingTotal <= 0,
                ),
                _FinanceRow(
                  label: 'Курс USD/CNY',
                  value: blank.usdToCny != null
                      ? blank.usdToCny!.toStringAsFixed(4)
                      : '—',
                  isEmpty: blank.usdToCny == null,
                ),
                _FinanceRow(
                  label: 'Курс USD/RUB',
                  value: blank.usdToRub != null
                      ? blank.usdToRub!.toStringAsFixed(2)
                      : '—',
                  isEmpty: blank.usdToRub == null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TotalPill(
                  label: 'Итого ¥',
                  value: blank.totalAmountCny != null
                      ? '¥${blank.totalAmountCny!.toStringAsFixed(2)}'
                      : (blank.clientTotalCny > 0
                            ? '≈ ¥${blank.clientTotalCny.toStringAsFixed(2)}'
                            : '—'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TotalPill(
                  label: 'Итого ₽',
                  value: blank.totalAmountRub != null
                      ? '₽${blank.totalAmountRub!.toStringAsFixed(0)}'
                      : '—',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Прочерки заполняются сотрудником после проверки бланка.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Gilroy',
              fontSize: 11.5,
              height: 1.2,
              fontWeight: FontWeight.w600,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  // ── Заголовок списка товаров ───────────────────────────────

  Widget _buildItemsHeader(
    BuildContext context,
    PurchaseBlank blank,
    bool isEditable,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: PurchaseBlankUi.cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: context.brandPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              Icons.shopping_bag_rounded,
              color: context.brandPrimary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Товары (${blank.itemsCount})',
                  style: PurchaseBlankUi.sectionTitleStyle,
                ),
                const SizedBox(height: 3),
                const Text(
                  'Ссылки, характеристики, цена и фото для выкупа',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'Gilroy',
                    fontSize: 12,
                    height: 1.16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (isEditable && !_showAddForm)
            TrainingTarget(
              id: 'purchase.item.add',
              child: Material(
                color: context.brandPrimary,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: _openAddForm,
                  borderRadius: BorderRadius.circular(16),
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      Icons.add_rounded,
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Пустое состояние товаров ───────────────────────────────

  Widget _buildEmptyItemsState(BuildContext context, bool isEditable) {
    return Container(
      decoration: PurchaseBlankUi.cardDecoration(),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.brandPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.shopping_bag_outlined,
              size: 25,
              color: context.brandPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Нет товаров',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 18,
                    height: 22 / 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isEditable
                      ? 'Добавьте первый товар в бланк'
                      : 'Товары ещё не добавлены',
                  style: PurchaseBlankUi.bodyStyle.copyWith(
                    color: PurchaseBlankUi.mutedTextColor,
                  ),
                ),
              ],
            ),
          ),
          if (isEditable) ...[
            const SizedBox(width: 10),
            TrainingTarget(
              id: 'purchase.item.add.empty',
              child: IconButton.filled(
                onPressed: _openAddForm,
                style: IconButton.styleFrom(
                  backgroundColor: context.brandPrimary,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.add_rounded),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Кнопки действий (черновик) ─────────────────────────────

  Widget _buildActionButtons(
    BuildContext context,
    PurchaseBlank blank,
    bool isCancellable,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: PurchaseBlankUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (blank.items.isNotEmpty)
            SizedBox(
              height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: context.brandGradient,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: context.brandPrimary.withValues(alpha: 0.18),
                      blurRadius: 18,
                      spreadRadius: -10,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: TrainingTarget(
                  id: 'purchase.submit',
                  child: FilledButton.icon(
                    onPressed: () => _submitBlank(blank.id),
                    icon: const Icon(Icons.send_rounded, size: 20),
                    label: const Text(
                      'Отправить бланк на проверку',
                      style: TextStyle(
                        fontFamily: 'Gilroy',
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            const Text(
              'Добавьте хотя бы один товар, чтобы отправить бланк на проверку.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Gilroy',
                fontSize: 13,
                height: 1.22,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (isCancellable) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 46,
              child: OutlinedButton.icon(
                onPressed: () => _cancelBlank(blank.id),
                icon: const Icon(Icons.cancel_rounded, size: 18),
                label: const Text(
                  'Отменить бланк',
                  style: TextStyle(
                    fontFamily: 'Gilroy',
                    fontWeight: FontWeight.w800,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: BorderSide(color: Colors.red.withValues(alpha: 0.55)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Кнопки для не-черновика ────────────────────────────────

  Widget _buildReadOnlyNotice(
    BuildContext context,
    PurchaseBlank blank,
    bool isCancellable,
  ) {
    if (!isCancellable) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: PurchaseBlankUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Бланк уже передан сотруднику. Если он больше не нужен, его можно отменить.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Gilroy',
              fontSize: 13,
              height: 1.22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 46,
            child: OutlinedButton.icon(
              onPressed: () => _cancelBlank(blank.id),
              icon: const Icon(Icons.cancel_rounded, size: 18),
              label: const Text(
                'Отменить бланк',
                style: TextStyle(
                  fontFamily: 'Gilroy',
                  fontWeight: FontWeight.w800,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: BorderSide(color: Colors.red.withValues(alpha: 0.55)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Действия ──────────────────────────────────────────────

  Future<void> _addItem(
    int blankId, {
    required String productName,
    required String productUrl,
    String? characteristics,
    required int quantity,
    required double unitPrice,
    List<Uint8List>? newPhotos,
    List<String>? newPhotoNames,
  }) async {
    final notifier = ref.read(purchaseBlanksProvider.notifier);
    final session = _addSaveSession ??= BlankItemSaveSession();
    await session.save(
      saveItem: (savedId) async {
        final item = savedId == null
            ? await notifier.addItem(
                blankId,
                productName: productName,
                productUrl: productUrl,
                characteristics: characteristics,
                quantity: quantity,
                unitPrice: unitPrice,
              )
            : await notifier.updateItem(
                blankId,
                savedId,
                productName: productName,
                productUrl: productUrl,
                characteristics: characteristics,
                quantity: quantity,
                unitPrice: unitPrice,
              );
        return item?.id;
      },
      photos: newPhotos ?? const [],
      uploadPhoto: (itemId, bytes, index) => notifier.uploadItemPhoto(
        blankId,
        itemId,
        bytes.toList(),
        newPhotoNames?[index] ?? 'photo_$index.jpg',
      ),
    );

    if (mounted) {
      setState(() => _showAddForm = false);
      _addSaveSession = null;
      ref.invalidate(purchaseBlankDetailProvider(widget.blankId));
    }
  }

  Future<void> _updateItem(
    int blankId,
    int itemId, {
    required String productName,
    required String productUrl,
    String? characteristics,
    required int quantity,
    required double unitPrice,
    List<Uint8List>? newPhotos,
    List<String>? newPhotoNames,
  }) async {
    final notifier = ref.read(purchaseBlanksProvider.notifier);
    final session = _editSaveSessions.putIfAbsent(
      itemId,
      () => BlankItemSaveSession(savedItemId: itemId),
    );
    await session.save(
      saveItem: (_) async => (await notifier.updateItem(
        blankId,
        itemId,
        productName: productName,
        productUrl: productUrl,
        characteristics: characteristics,
        quantity: quantity,
        unitPrice: unitPrice,
      ))?.id,
      photos: newPhotos ?? const [],
      uploadPhoto: (savedId, bytes, index) => notifier.uploadItemPhoto(
        blankId,
        savedId,
        bytes.toList(),
        newPhotoNames?[index] ?? 'photo_$index.jpg',
      ),
    );

    if (mounted) {
      setState(() => _editingItemId = null);
      _editSaveSessions.remove(itemId);
      ref.invalidate(purchaseBlankDetailProvider(widget.blankId));
    }
  }

  Future<bool> _showPurchaseBlankConfirmSheet({
    required IconData icon,
    required String title,
    required String message,
    required String confirmLabel,
    String cancelLabel = 'Отмена',
    bool destructive = false,
  }) async {
    final result = await showBlurredModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (sheetContext) {
        final bottomPadding = MediaQuery.paddingOf(sheetContext).bottom;
        final accentColor = destructive
            ? const Color(0xFFE53935)
            : sheetContext.brandPrimary;

        Widget confirmButton = SizedBox(
          height: 52,
          child: destructive
              ? FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    confirmLabel,
                    style: const TextStyle(
                      fontFamily: 'Gilroy',
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: sheetContext.brandGradient,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: sheetContext.brandPrimary.withValues(
                          alpha: 0.18,
                        ),
                        blurRadius: 18,
                        spreadRadius: -10,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Text(
                      confirmLabel,
                      style: const TextStyle(
                        fontFamily: 'Gilroy',
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
        );

        return SafeArea(
          top: false,
          bottom: false,
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 18 + bottomPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SheetHandle(),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Icon(icon, color: accentColor, size: 25),
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
                                fontSize: 22,
                                height: 1.05,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              message,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontFamily: 'Gilroy',
                                fontSize: 13.5,
                                height: 1.24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.of(sheetContext).pop(false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textPrimary,
                              side: BorderSide(
                                color: Colors.black.withValues(alpha: 0.08),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: Text(
                              cancelLabel,
                              style: const TextStyle(
                                fontFamily: 'Gilroy',
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: confirmButton),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    return result ?? false;
  }

  Future<void> _deleteItem(int blankId, int itemId) async {
    final confirmed = await _showPurchaseBlankConfirmSheet(
      icon: Icons.delete_rounded,
      title: 'Удалить товар?',
      message: 'Товар будет удалён из бланка. Это действие нельзя отменить.',
      confirmLabel: 'Удалить',
      destructive: true,
    );
    if (!mounted || !confirmed) return;

    await ref.read(purchaseBlanksProvider.notifier).deleteItem(blankId, itemId);
    if (!mounted) return;
    ref.invalidate(purchaseBlankDetailProvider(widget.blankId));
  }

  Future<void> _submitBlank(int blankId) async {
    final confirmed = await _showPurchaseBlankConfirmSheet(
      icon: Icons.send_rounded,
      title: 'Отправить бланк?',
      message:
          'После отправки редактирование будет недоступно. Сотрудник проверит товары, комиссию и итоговую стоимость.',
      confirmLabel: 'Отправить',
    );
    if (!mounted || !confirmed) return;

    final success = await ref
        .read(purchaseBlanksProvider.notifier)
        .submitBlank(blankId);
    if (mounted) {
      ref.invalidate(purchaseBlankDetailProvider(widget.blankId));
      if (success) {
        _showSnackBar('Бланк отправлен на обработку');
      } else {
        _showSnackBar('Ошибка отправки бланка', isError: true);
      }
    }
  }

  Future<void> _cancelBlank(int blankId) async {
    final confirmed = await _showPurchaseBlankConfirmSheet(
      icon: Icons.cancel_rounded,
      title: 'Отменить бланк?',
      message:
          'Бланк будет отменён, а обработка по нему остановится. Это действие нельзя отменить.',
      confirmLabel: 'Отменить',
      cancelLabel: 'Нет',
      destructive: true,
    );
    if (!mounted || !confirmed) return;

    final success = await ref
        .read(purchaseBlanksProvider.notifier)
        .cancelBlank(blankId);
    if (mounted) {
      ref.invalidate(purchaseBlankDetailProvider(widget.blankId));
      if (success) {
        _showSnackBar('Бланк отменён');
      } else {
        _showSnackBar('Ошибка отмены', isError: true);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    AppToast.showFromSnackBar(
      context,
      SnackBar(
        content: Row(
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
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError
            ? const Color(0xFFE53935)
            : context.brandPrimary,
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
}

// ── Строка финансовых данных ─────────────────────────────────

class _TotalPill extends StatelessWidget {
  final String label;
  final String value;

  const _TotalPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.brandPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.brandPrimary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Gilroy',
              fontSize: 11,
              height: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.brandPrimary,
              fontFamily: 'Gilroy',
              fontSize: 16,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _FinanceRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isEmpty;

  const _FinanceRow({
    required this.label,
    required this.value,
    this.isEmpty = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Gilroy',
                fontSize: 13,
                height: 16 / 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Gilroy',
              fontSize: 13,
              height: 16 / 13,
              fontWeight: FontWeight.w900,
              color: isEmpty ? Colors.grey.shade400 : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
