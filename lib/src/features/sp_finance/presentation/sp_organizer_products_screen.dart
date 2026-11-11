import '../../../core/ui/app_search_field.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/ui/app_cached_media_image.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/ui/app_layout.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/ui/empty_state.dart';
import '../../../core/ui/scroll_to_top_button.dart';
import '../../../core/utils/locale_text.dart';
import '../data/sp_organizer_models.dart';
import '../data/sp_organizer_provider.dart';
import '../data/sp_v2_provider.dart';
import 'sp_barcode_scanner_sheet.dart';
import 'sp_finance_ui.dart';
import 'sp_organizer_navigation.dart';

class SpOrganizerProductsScreen extends ConsumerStatefulWidget {
  final bool embedded;

  const SpOrganizerProductsScreen({super.key, this.embedded = false});

  @override
  ConsumerState<SpOrganizerProductsScreen> createState() =>
      _SpOrganizerProductsScreenState();
}

class _SpOrganizerProductsScreenState
    extends ConsumerState<SpOrganizerProductsScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  final Set<int> _busyProductIds = <int>{};
  bool _productSheetPending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final capabilities = await ref.read(
        spOrganizerCapabilitiesProvider.future,
      );
      if (!mounted || !capabilities.products) return;
      await ref.read(spOrganizerProductsControllerProvider.notifier).load();
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
    final capabilitiesAsync = ref.watch(spOrganizerCapabilitiesProvider);
    final state = ref.watch(spOrganizerProductsControllerProvider);
    final topPad = widget.embedded ? 0.0 : AppLayout.topBarTotalHeight(context);
    final bottomPad = AppLayout.bottomScrollPadding(context);

    return Stack(
      children: [
        RefreshIndicator(
          color: context.brandPrimary,
          onRefresh: () async {
            final capabilities = capabilitiesAsync.asData?.value;
            if (capabilities?.products != true) return;
            await ref
                .read(spOrganizerProductsControllerProvider.notifier)
                .load();
          },
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
                  title: tr(context, ru: 'Каталог товаров', zh: '商品目录'),
                  fallbackRoute: '/sp-finance',
                ),
                const SizedBox(height: 12),
              ],
              capabilitiesAsync.when(
                loading: () => const _ProductsLoadingCard(),
                error: (_, _) => _ProductsUnavailableCard(
                  title: tr(
                    context,
                    ru: 'Каталог временно недоступен',
                    zh: '商品目录暂不可用',
                  ),
                  message: tr(
                    context,
                    ru: 'Основные совместные покупки продолжают работать.',
                    zh: '现有拼团功能仍可正常使用。',
                  ),
                ),
                data: (capabilities) {
                  if (!capabilities.products) {
                    return _ProductsUnavailableCard(
                      title: tr(
                        context,
                        ru: 'Каталог пока не включён',
                        zh: '商品目录尚未启用',
                      ),
                      message: tr(
                        context,
                        ru: 'Новая функция выключена на сервере. Данные текущих СП не изменяются.',
                        zh: '服务器尚未启用此功能，现有拼团数据不会改变。',
                      ),
                    );
                  }
                  return _buildEnabledContent(context, capabilities, state);
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
    SpOrganizerProductsState state,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded) ...[
          _ProductsHero(total: state.total),
          const SizedBox(height: 12),
          SpOrganizerNavigation(
            capabilities: capabilities,
            selected: SpOrganizerSection.products,
          ),
          const SizedBox(height: 12),
        ],
        _ProductsToolbar(
          controller: _searchController,
          includeArchived: state.includeArchived,
          isLoading: state.isLoading,
          onChanged: _onSearchChanged,
          onArchivedChanged: (value) {
            ref
                .read(spOrganizerProductsControllerProvider.notifier)
                .setIncludeArchived(value);
          },
          onCreate: _showProductSheet,
        ),
        const SizedBox(height: 14),
        if (state.error != null && state.products.isEmpty)
          EmptyState(
            icon: Icons.error_outline_rounded,
            title: tr(context, ru: 'Не удалось загрузить товары', zh: '无法加载商品'),
            message: state.error!,
          )
        else if (state.isLoading && state.products.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (state.products.isEmpty)
          _ProductsEmptyCard(onCreate: _showProductSheet)
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >= 760;
              final cardWidth = desktop
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: state.products
                    .map(
                      (product) => SizedBox(
                        width: cardWidth,
                        child: _ProductCard(
                          product: product,
                          onOpen: () => context.push(
                            '/sp-finance/products/${product.id}',
                          ),
                          onEdit: () => _showProductSheet(product: product),
                          onArchive: product.isArchived
                              ? () => _restoreProduct(product)
                              : () => _archiveProduct(product),
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
          if (state.hasMore) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: state.isLoadingMore
                  ? null
                  : () => ref
                        .read(spOrganizerProductsControllerProvider.notifier)
                        .loadMore(),
              icon: state.isLoadingMore
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded),
              label: Text(tr(context, ru: 'Показать ещё', zh: '加载更多')),
            ),
          ],
        ],
      ],
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(spOrganizerProductsControllerProvider.notifier).search(value);
    });
  }

  Future<void> _showProductSheet({SpOrganizerProduct? product}) async {
    if (_productSheetPending) return;
    _productSheetPending = true;
    try {
      final saved = await showSpFinanceModalSheet<bool>(
        context: context,
        builder: (context) => _ProductEditorSheet(product: product),
      );
      if (!mounted || saved != true) return;
      AppToast.show(
        context,
        product == null
            ? tr(context, ru: 'Товар добавлен', zh: '商品已添加')
            : tr(context, ru: 'Товар обновлён', zh: '商品已更新'),
      );
    } finally {
      _productSheetPending = false;
    }
  }

  Future<void> _archiveProduct(SpOrganizerProduct product) async {
    if (_busyProductIds.contains(product.id)) return;
    setState(() => _busyProductIds.add(product.id));
    try {
      final confirmed = await showSpFinanceConfirmationSheet(
        context: context,
        icon: Icons.archive_rounded,
        title: tr(context, ru: 'Перенести товар в архив?', zh: '将商品归档？'),
        message: tr(
          context,
          ru: '«${product.title}» останется в базе и его можно будет восстановить.',
          zh: '“${product.title}”仍会保留在数据库中，并可随时恢复。',
        ),
        confirmLabel: tr(context, ru: 'В архив', zh: '归档'),
        cancelLabel: tr(context, ru: 'Отмена', zh: '取消'),
      );
      if (!mounted || confirmed != true) return;
      await ref
          .read(spOrganizerProductsControllerProvider.notifier)
          .archiveProduct(product.id);
      if (!mounted) return;
      AppToast.show(
        context,
        tr(context, ru: 'Товар перенесён в архив', zh: '商品已归档'),
      );
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    } finally {
      if (mounted) setState(() => _busyProductIds.remove(product.id));
    }
  }

  Future<void> _restoreProduct(SpOrganizerProduct product) async {
    if (_busyProductIds.contains(product.id)) return;
    setState(() => _busyProductIds.add(product.id));
    try {
      await ref
          .read(spOrganizerProductsControllerProvider.notifier)
          .restoreProduct(product.id);
      if (!mounted) return;
      AppToast.show(
        context,
        tr(context, ru: 'Товар восстановлен', zh: '商品已恢复'),
      );
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    } finally {
      if (mounted) setState(() => _busyProductIds.remove(product.id));
    }
  }

  void _showError(Object error) {
    AppToast.show(
      context,
      '${tr(context, ru: 'Не удалось выполнить действие', zh: '操作失败')}: $error',
      isError: true,
    );
  }
}

class _ProductsHero extends StatelessWidget {
  final int total;

  const _ProductsHero({required this.total});

  @override
  Widget build(BuildContext context) {
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
              Icons.inventory_2_rounded,
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
                  tr(context, ru: 'Товары организатора', zh: '团长商品'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Gilroy',
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  tr(
                    context,
                    ru: 'Повторно используйте карточки товаров в новых закупках.',
                    zh: '在新的拼团中重复使用商品卡片。',
                  ),
                  style: const TextStyle(
                    color: Color(0xE6FFFFFF),
                    fontFamily: 'Gilroy',
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                SpHeroChip(
                  icon: Icons.inventory_rounded,
                  label: tr(context, ru: '$total товаров', zh: '$total 件商品'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductsToolbar extends StatelessWidget {
  final TextEditingController controller;
  final bool includeArchived;
  final bool isLoading;
  final ValueChanged<String> onChanged;
  final ValueChanged<bool> onArchivedChanged;
  final VoidCallback onCreate;

  const _ProductsToolbar({
    required this.controller,
    required this.includeArchived,
    required this.isLoading,
    required this.onChanged,
    required this.onArchivedChanged,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: AppSearchField(
                  controller: controller,
                  onChanged: onChanged,
                  textInputAction: TextInputAction.search,
                  hintText: tr(
                    context,
                    ru: 'Название, артикул или ссылка',
                    zh: '名称、货号或链接',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: tr(context, ru: 'Добавить товар', zh: '添加商品'),
                child: Semantics(
                  button: true,
                  label: tr(context, ru: 'Добавить товар', zh: '添加商品'),
                  enabled: !isLoading,
                  child: Material(
                    color: context.brandPrimary,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      onTap: isLoading ? null : onCreate,
                      borderRadius: BorderRadius.circular(18),
                      child: const SizedBox(
                        width: 56,
                        height: 56,
                        child: Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            value: includeArchived,
            activeTrackColor: context.brandPrimary,
            onChanged: isLoading ? null : onArchivedChanged,
            title: Text(
              tr(context, ru: 'Показывать архив', zh: '显示归档'),
              style: SpFinanceUi.bodyStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final SpOrganizerProduct product;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  const _ProductCard({
    required this.product,
    required this.onOpen,
    required this.onEdit,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: tr(
              context,
              ru: 'Открыть историю товара ${product.title}',
              zh: '打开商品历史 ${product.title}',
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onOpen,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(17),
                        child: SizedBox(
                          width: 72,
                          height: 72,
                          child: product.imageUrl == null
                              ? Container(
                                  color: context.brandPrimary.withValues(
                                    alpha: 0.09,
                                  ),
                                  child: Icon(
                                    Icons.inventory_2_outlined,
                                    color: context.brandPrimary,
                                    size: 30,
                                  ),
                                )
                              : AppCachedMediaImage(
                                  url: product.imageUrl!,
                                  fit: BoxFit.cover,
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: SpFinanceUi.sectionTitleStyle,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 7,
                              runSpacing: 7,
                              children: [
                                if (product.marketplaceCode != null)
                                  _ProductChip(
                                    icon: Icons.storefront_rounded,
                                    label: product.marketplaceCode!,
                                  ),
                                if (product.barcode != null)
                                  _ProductChip(
                                    icon: Icons.qr_code_2_rounded,
                                    label: product.barcode!,
                                  ),
                                _ProductChip(
                                  icon: Icons.shopping_bag_outlined,
                                  label: tr(
                                    context,
                                    ru: '${product.itemsCount} позиций',
                                    zh: '${product.itemsCount} 个明细',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: context.brandPrimary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (product.description != null) ...[
            const SizedBox(height: 12),
            Text(
              product.description!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: SpFinanceUi.labelStyle,
            ),
          ],
          if (product.isArchived) ...[
            const SizedBox(height: 10),
            _ProductChip(
              icon: Icons.archive_rounded,
              label: tr(context, ru: 'В архиве', zh: '已归档'),
              color: AppColors.textSecondary,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: product.isArchived ? null : onEdit,
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: Text(tr(context, ru: 'Изменить', zh: '编辑')),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: product.isArchived
                    ? tr(context, ru: 'Восстановить', zh: '恢复')
                    : tr(context, ru: 'В архив', zh: '归档'),
                onPressed: onArchive,
                icon: Icon(
                  product.isArchived
                      ? Icons.unarchive_rounded
                      : Icons.archive_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProductChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _ProductChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? context.brandPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: effectiveColor),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: effectiveColor,
                fontFamily: 'Gilroy',
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductsEmptyCard extends StatelessWidget {
  final VoidCallback onCreate;

  const _ProductsEmptyCard({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            color: context.brandPrimary,
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(
            tr(context, ru: 'Каталог пока пуст', zh: '商品目录为空'),
            textAlign: TextAlign.center,
            style: SpFinanceUi.sectionTitleStyle,
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              context,
              ru: 'Добавьте товар один раз, чтобы использовать его в следующих закупках.',
              zh: '添加一次商品，即可在之后的拼团中重复使用。',
            ),
            textAlign: TextAlign.center,
            style: SpFinanceUi.labelStyle,
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: Text(tr(context, ru: 'Добавить товар', zh: '添加商品')),
          ),
        ],
      ),
    );
  }
}

class _ProductsLoadingCard extends StatelessWidget {
  const _ProductsLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      decoration: SpFinanceUi.cardDecoration(),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _ProductsUnavailableCard extends StatelessWidget {
  final String title;
  final String message;

  const _ProductsUnavailableCard({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        children: [
          Icon(Icons.lock_clock_rounded, color: context.brandPrimary, size: 40),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: SpFinanceUi.sectionTitleStyle,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: SpFinanceUi.labelStyle,
          ),
        ],
      ),
    );
  }
}

class _ProductEditorSheet extends ConsumerStatefulWidget {
  final SpOrganizerProduct? product;

  const _ProductEditorSheet({this.product});

  @override
  ConsumerState<_ProductEditorSheet> createState() =>
      _ProductEditorSheetState();
}

class _ProductEditorSheetState extends ConsumerState<_ProductEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _sourceUrlController;
  late final TextEditingController _marketplaceController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _descriptionController;
  _PickedProductImage? _pickedPhoto;
  _PickedProductImage? _pickedQr;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _titleController = TextEditingController(text: product?.title);
    _sourceUrlController = TextEditingController(text: product?.sourceUrl);
    _marketplaceController = TextEditingController(
      text: product?.marketplaceCode,
    );
    _barcodeController = TextEditingController(text: product?.barcode);
    _descriptionController = TextEditingController(text: product?.description);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _sourceUrlController.dispose();
    _marketplaceController.dispose();
    _barcodeController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCreating = widget.product == null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SpFinanceModalSurface(
        icon: isCreating ? Icons.add_box_rounded : Icons.edit_note_rounded,
        title: isCreating
            ? tr(context, ru: 'Новый товар', zh: '新商品')
            : tr(context, ru: 'Изменить товар', zh: '编辑商品'),
        subtitle: tr(
          context,
          ru: 'Фото, ссылка, штрихкод и данные каталога',
          zh: '商品图片、链接、条形码和目录信息',
        ),
        maxHeightFactor: 0.92,
        keyboardAware: true,
        contentPadding: EdgeInsets.zero,
        body: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProductImagePickerCard(
                  key: const Key('sp-product-main-photo'),
                  isQr: false,
                  title: tr(context, ru: 'Фото товара', zh: '商品图片'),
                  prompt: tr(
                    context,
                    ru: 'Нажмите, чтобы выбрать фото',
                    zh: '点击选择商品图片',
                  ),
                  existingUrl: widget.product?.imageUrl,
                  picked: _pickedPhoto,
                  onPick: () => _pickImage(isQr: false),
                  onClearPicked: _pickedPhoto == null
                      ? null
                      : () => setState(() => _pickedPhoto = null),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _titleController,
                  decoration: SpFinanceUi.inputDecoration(
                    context,
                    labelText: tr(context, ru: 'Название', zh: '名称'),
                    prefixIcon: Icons.inventory_2_outlined,
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? tr(
                          context,
                          ru: 'Введите название товара',
                          zh: '请输入商品名称',
                        )
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _sourceUrlController,
                  keyboardType: TextInputType.url,
                  decoration: SpFinanceUi.inputDecoration(
                    context,
                    labelText: tr(context, ru: 'Ссылка на товар', zh: '商品链接'),
                    prefixIcon: Icons.link_rounded,
                  ),
                ),
                const SizedBox(height: 12),
                _ProductImagePickerCard(
                  key: const Key('sp-product-qr-photo'),
                  isQr: true,
                  title: tr(context, ru: 'QR-код', zh: '二维码'),
                  prompt: tr(
                    context,
                    ru: 'Загрузить изображение QR',
                    zh: '上传二维码图片',
                  ),
                  existingUrl: widget.product?.qrImageUrl,
                  picked: _pickedQr,
                  onPick: () => _pickImage(isQr: true),
                  onClearPicked: _pickedQr == null
                      ? null
                      : () => setState(() => _pickedQr = null),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _marketplaceController,
                        decoration: SpFinanceUi.inputDecoration(
                          context,
                          labelText: tr(context, ru: 'Площадка', zh: '平台'),
                          prefixIcon: Icons.storefront_rounded,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _barcodeController,
                        decoration:
                            SpFinanceUi.inputDecoration(
                              context,
                              labelText: tr(
                                context,
                                ru: 'Артикул / штрихкод',
                                zh: '货号 / 条形码',
                              ),
                              prefixIcon: Icons.qr_code_2_rounded,
                            ).copyWith(
                              suffixIcon: IconButton(
                                key: const ValueKey(
                                  'sp-product-barcode-scan-button',
                                ),
                                tooltip: tr(
                                  context,
                                  ru: 'Сканировать штрихкод',
                                  zh: '扫描条形码',
                                ),
                                onPressed: _scanBarcode,
                                icon: Icon(
                                  Icons.qr_code_scanner_rounded,
                                  color: context.brandPrimary,
                                ),
                              ),
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: SpFinanceUi.inputDecoration(
                    context,
                    labelText: tr(context, ru: 'Описание', zh: '描述'),
                    prefixIcon: Icons.notes_rounded,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        footer: SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(tr(context, ru: 'Сохранить', zh: '保存')),
            style: FilledButton.styleFrom(
              backgroundColor: context.brandPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: const TextStyle(
                fontFamily: 'Gilroy',
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final mediaUrls = <String>[];
    var qrImageUrl = widget.product?.qrImageUrl;
    try {
      if (_pickedPhoto case final image?) {
        final uploaded = await _uploadProductImage(image);
        if (!mounted) return;
        mediaUrls.add(uploaded);
      }
      if (_pickedQr case final image?) {
        qrImageUrl = await _uploadProductImage(image);
        if (!mounted) return;
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${tr(context, ru: 'Не удалось загрузить изображение', zh: '图片上传失败')}: $error',
          ),
        ),
      );
      return;
    }
    final input = SpOrganizerProductInput(
      title: _titleController.text.trim(),
      sourceUrl: _sourceUrlController.text.trim(),
      marketplaceCode: _marketplaceController.text.trim(),
      barcode: _barcodeController.text.trim(),
      qrImageUrl: qrImageUrl,
      description: _descriptionController.text.trim(),
      mediaUrls: mediaUrls,
    );
    try {
      final controller = ref.read(
        spOrganizerProductsControllerProvider.notifier,
      );
      if (widget.product == null) {
        await controller.createProduct(input);
      } else {
        await controller.updateProduct(widget.product!.id, input);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${tr(context, ru: 'Не удалось сохранить товар', zh: '无法保存商品')}: $error',
          ),
        ),
      );
    }
  }

  Future<void> _scanBarcode() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final scannedCode = await showSpBarcodeScannerSheet(context);
    if (!mounted || scannedCode == null) return;

    final normalizedCode = scannedCode.trim();
    if (normalizedCode.isEmpty) return;
    _barcodeController.value = TextEditingValue(
      text: normalizedCode,
      selection: TextSelection.collapsed(offset: normalizedCode.length),
    );
  }

  Future<void> _pickImage({required bool isQr}) async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      const maxSize = 20 * 1024 * 1024;
      if (bytes.isEmpty || bytes.length > maxSize) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                ru: 'Изображение должно быть не больше 20 МБ',
                zh: '图片大小不能超过 20 MB',
              ),
            ),
          ),
        );
        return;
      }
      final mimeType = _productImageMimeType(file);
      if (!_allowedProductImageTypes.contains(mimeType)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                ru: 'Поддерживаются JPEG, PNG, WebP и HEIC',
                zh: '支持 JPEG、PNG、WebP 和 HEIC',
              ),
            ),
          ),
        );
        return;
      }
      final image = _PickedProductImage(
        bytes: bytes,
        fileName: file.name,
        mimeType: mimeType,
      );
      setState(() {
        if (isQr) {
          _pickedQr = image;
        } else {
          _pickedPhoto = image;
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${tr(context, ru: 'Не удалось выбрать изображение', zh: '无法选择图片')}: $error',
          ),
        ),
      );
    }
  }

  Future<String> _uploadProductImage(_PickedProductImage image) async {
    final url = await ref
        .read(spV2RepositoryProvider)
        .uploadMedia(
          bytes: image.bytes,
          fileName: image.fileName,
          mimeType: image.mimeType,
          type: 'sp-v2-product',
        );
    if (url == null || url.trim().isEmpty) {
      throw StateError('server returned an empty image URL');
    }
    return url;
  }
}

const _allowedProductImageTypes = {
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
};

String _productImageMimeType(XFile file) {
  final explicit = file.mimeType?.trim().toLowerCase();
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final name = file.name.toLowerCase();
  if (name.endsWith('.png')) return 'image/png';
  if (name.endsWith('.webp')) return 'image/webp';
  if (name.endsWith('.heic')) return 'image/heic';
  if (name.endsWith('.heif')) return 'image/heif';
  return 'image/jpeg';
}

class _PickedProductImage {
  final Uint8List bytes;
  final String fileName;
  final String mimeType;

  const _PickedProductImage({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });
}

class _ProductImagePickerCard extends StatelessWidget {
  final bool isQr;
  final String title;
  final String prompt;
  final String? existingUrl;
  final _PickedProductImage? picked;
  final VoidCallback onPick;
  final VoidCallback? onClearPicked;

  const _ProductImagePickerCard({
    super.key,
    required this.isQr,
    required this.title,
    required this.prompt,
    required this.existingUrl,
    required this.picked,
    required this.onPick,
    required this.onClearPicked,
  });

  @override
  Widget build(BuildContext context) {
    final hasPreview =
        picked != null || (existingUrl != null && existingUrl!.isNotEmpty);
    return Semantics(
      button: true,
      label: '$title. $prompt',
      child: Material(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 148,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: context.brandPrimary.withValues(alpha: 0.20),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (picked != null)
                  Image.memory(picked!.bytes, fit: BoxFit.cover)
                else if (existingUrl != null && existingUrl!.isNotEmpty)
                  AppCachedMediaImage(url: existingUrl!, fit: BoxFit.cover)
                else
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isQr
                            ? Icons.qr_code_2_rounded
                            : Icons.add_photo_alternate_rounded,
                        color: context.brandPrimary,
                        size: 34,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontFamily: 'Gilroy',
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        prompt,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.brandPrimary,
                          fontFamily: 'Gilroy',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'JPEG, PNG, WebP, HEIC · до 20 МБ',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontFamily: 'Gilroy',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                if (hasPreview)
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.64),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Gilroy',
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                if (hasPreview)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: IconButton.filled(
                      tooltip: tr(context, ru: 'Заменить', zh: '替换'),
                      onPressed: onPick,
                      icon: const Icon(Icons.edit_rounded, size: 18),
                    ),
                  ),
                if (onClearPicked != null)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: IconButton.filledTonal(
                      tooltip: tr(context, ru: 'Отменить выбор', zh: '取消选择'),
                      onPressed: onClearPicked,
                      icon: const Icon(Icons.undo_rounded, size: 18),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
