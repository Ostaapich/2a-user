import '../../../core/ui/app_search_field.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/app_cached_media_image.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/utils/locale_text.dart';
import '../data/sp_organizer_models.dart';
import '../data/sp_organizer_provider.dart';
import '../data/sp_v2_models.dart';
import '../data/sp_v2_provider.dart';
import 'sp_barcode_scanner_sheet.dart';
import 'sp_finance_ui.dart';

Future<bool?> showSpOrganizerCatalogItemSheet({
  required BuildContext context,
  required int purchaseId,
  SpBarcodeScannerLauncher barcodeScanner = showSpBarcodeScannerSheet,
}) {
  return showSpFinanceModalSheet<bool>(
    context: context,
    builder: (context) => _SpOrganizerCatalogItemSheet(
      purchaseId: purchaseId,
      barcodeScanner: barcodeScanner,
    ),
  );
}

class _SpOrganizerCatalogItemSheet extends ConsumerStatefulWidget {
  final int purchaseId;
  final SpBarcodeScannerLauncher barcodeScanner;

  const _SpOrganizerCatalogItemSheet({
    required this.purchaseId,
    required this.barcodeScanner,
  });

  @override
  ConsumerState<_SpOrganizerCatalogItemSheet> createState() =>
      _SpOrganizerCatalogItemSheetState();
}

class _SpOrganizerCatalogItemSheetState
    extends ConsumerState<_SpOrganizerCatalogItemSheet> {
  final _searchController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _purchasePriceController = TextEditingController();
  final _clientPriceController = TextEditingController();
  Timer? _searchDebounce;
  List<SpOrganizerProduct> _products = const [];
  SpOrganizerProduct? _selectedProduct;
  int? _selectedCustomerId;
  bool _loading = true;
  bool _saving = false;
  int _loadRevision = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _quantityController.dispose();
    _purchasePriceController.dispose();
    _clientPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final purchaseAsync = ref.watch(
      spV2PurchaseDetailProvider(widget.purchaseId),
    );
    final participantsAsync = ref.watch(
      spOrganizerParticipantsProvider(widget.purchaseId),
    );
    final purchase = purchaseAsync.asData?.value;
    final participants =
        participantsAsync.asData?.value.participants ?? const [];
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
          Padding(
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
                        Icons.playlist_add_rounded,
                        color: context.brandPrimary,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr(
                              context,
                              ru: 'Добавить из каталога',
                              zh: '从商品目录添加',
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
                              ru: 'Карточка останется связана с товаром',
                              zh: '采购明细将与商品保持关联',
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
          ),
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(18, 4, 18, 18 + bottomInset),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: AppSearchField(
                        key: const ValueKey('sp-catalog-search-field'),
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        hintText: tr(
                          context,
                          ru: 'Найти товар в каталоге',
                          zh: '在商品目录中搜索',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 44,
                      height: 48,
                      child: IconButton(
                        key: const ValueKey('sp-catalog-barcode-scan-button'),
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
                  ],
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  _CatalogNotice(
                    icon: Icons.error_outline_rounded,
                    message: tr(
                      context,
                      ru: 'Не удалось загрузить каталог',
                      zh: '无法加载商品目录',
                    ),
                    actionLabel: tr(context, ru: 'Повторить', zh: '重试'),
                    onAction: _loadProducts,
                  )
                else if (_products.isEmpty)
                  _CatalogNotice(
                    icon: Icons.inventory_2_outlined,
                    message: tr(
                      context,
                      ru: 'Подходящие товары не найдены',
                      zh: '未找到合适的商品',
                    ),
                  )
                else
                  ..._products.map(
                    (product) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _CatalogProductTile(
                        product: product,
                        selected: _selectedProduct?.id == product.id,
                        onTap: () => setState(() {
                          _selectedProduct = product;
                        }),
                      ),
                    ),
                  ),
                if (_selectedProduct != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    tr(context, ru: 'Параметры позиции', zh: '明细参数'),
                    style: SpFinanceUi.sectionTitleStyle,
                  ),
                  const SizedBox(height: 10),
                  if (participantsAsync.isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (participants.isEmpty)
                    _CatalogNotice(
                      icon: Icons.person_add_alt_rounded,
                      message: tr(
                        context,
                        ru: 'Сначала добавьте в закупку себя или клиента.',
                        zh: '请先将自己或客户添加到采购中。',
                      ),
                    )
                  else
                    DropdownButtonFormField<int>(
                      initialValue: _selectedCustomerId,
                      isExpanded: true,
                      decoration: SpFinanceUi.inputDecoration(
                        context,
                        labelText: tr(context, ru: 'Участник', zh: '参与者'),
                        prefixIcon: Icons.person_outline_rounded,
                      ),
                      items: participants
                          .map(
                            (participant) => DropdownMenuItem(
                              value: participant.spCustomerId,
                              child: Text(
                                participant.customer.displayName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        setState(() => _selectedCustomerId = value);
                      },
                    ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    decoration: SpFinanceUi.inputDecoration(
                      context,
                      labelText: tr(context, ru: 'Количество', zh: '数量'),
                      suffixText: tr(context, ru: 'шт.', zh: '件'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _purchasePriceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: SpFinanceUi.inputDecoration(
                            context,
                            labelText: tr(
                              context,
                              ru: 'Цена выкупа',
                              zh: '采购价',
                            ),
                            suffixText: _currencySymbol(purchase?.currency),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _clientPriceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: SpFinanceUi.inputDecoration(
                            context,
                            labelText: tr(
                              context,
                              ru: 'Цена клиента',
                              zh: '客户价',
                            ),
                            suffixText: _currencySymbol(purchase?.currency),
                          ),
                        ),
                      ),
                    ],
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
                onPressed:
                    _saving ||
                        purchase == null ||
                        _selectedProduct == null ||
                        _selectedCustomerId == null
                    ? null
                    : () => _save(purchase),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add_shopping_cart_rounded),
                label: Text(tr(context, ru: 'Добавить в закупку', zh: '添加到采购')),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _loadProducts);
  }

  Future<void> _scanBarcode() async {
    _searchDebounce?.cancel();
    FocusManager.instance.primaryFocus?.unfocus();
    final scannedCode = await widget.barcodeScanner(context);
    if (!mounted || scannedCode == null) return;

    final normalizedCode = scannedCode.trim();
    if (normalizedCode.isEmpty) return;
    _searchController.value = TextEditingValue(
      text: normalizedCode,
      selection: TextSelection.collapsed(offset: normalizedCode.length),
    );
    await _loadProducts();
    if (!mounted) return;

    SpOrganizerProduct? exactMatch;
    for (final product in _products) {
      if (product.barcode?.trim() == normalizedCode ||
          product.marketplaceCode?.trim() == normalizedCode) {
        exactMatch = product;
        break;
      }
    }
    if (exactMatch != null) {
      setState(() => _selectedProduct = exactMatch);
    }
  }

  Future<void> _loadProducts() async {
    final requestRevision = ++_loadRevision;
    final requestedQuery = _searchController.text;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(spOrganizerRepositoryProvider)
          .getProducts(query: requestedQuery, page: 1, limit: 40);
      if (!mounted || requestRevision != _loadRevision) return;
      setState(() {
        _products = page.items;
        _loading = false;
        if (_selectedProduct != null &&
            !_products.any((item) => item.id == _selectedProduct!.id)) {
          _selectedProduct = null;
        }
      });
    } catch (error) {
      if (!mounted || requestRevision != _loadRevision) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _save(SpV2Purchase purchase) async {
    if (_saving) return;
    final quantity = int.tryParse(_quantityController.text.trim());
    if (quantity == null || quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              ru: 'Количество должно быть больше нуля',
              zh: '数量必须大于零',
            ),
          ),
        ),
      );
      return;
    }
    final product = _selectedProduct!;
    setState(() => _saving = true);
    try {
      await ref
          .read(spV2RepositoryProvider)
          .createItem(
            purchase.id,
            CreateSpV2ItemInput(
              spCustomerId: _selectedCustomerId,
              spProductId: product.id,
              title: product.title,
              sourceUrl: product.sourceUrl,
              description: product.description,
              quantity: quantity,
              currency: purchase.currency,
              purchasePrice: _readDouble(_purchasePriceController.text),
              clientPriceYuan: purchase.currency == 'CNY'
                  ? _readDouble(_clientPriceController.text)
                  : null,
              clientPriceRub: purchase.currency == 'RUB'
                  ? _readDouble(_clientPriceController.text)
                  : null,
            ),
          );
      if (!mounted) return;
      ref.invalidate(spV2PurchaseDetailProvider(purchase.id));
      await ref
          .read(spOrganizerProductsControllerProvider.notifier)
          .load(silent: true);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${tr(context, ru: 'Не удалось добавить товар', zh: '无法添加商品')}: $error',
          ),
        ),
      );
    }
  }

  String _currencySymbol(String? currency) => currency == 'RUB' ? '₽' : '¥';

  double? _readDouble(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    return normalized.isEmpty ? null : double.tryParse(normalized);
  }
}

class _CatalogProductTile extends StatelessWidget {
  final SpOrganizerProduct product;
  final bool selected;
  final VoidCallback onTap;

  const _CatalogProductTile({
    required this.product,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? context.brandPrimary.withValues(alpha: 0.08)
          : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? context.brandPrimary : const Color(0xFFE7EAF0),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: product.imageUrl == null
                      ? Container(
                          color: context.brandPrimary.withValues(alpha: 0.08),
                          child: Icon(
                            Icons.inventory_2_outlined,
                            color: context.brandPrimary,
                          ),
                        )
                      : AppCachedMediaImage(
                          url: product.imageUrl!,
                          fit: BoxFit.cover,
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SpFinanceUi.bodyStyle.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (product.marketplaceCode != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        product.marketplaceCode!,
                        style: SpFinanceUi.labelStyle,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected
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

class _CatalogNotice extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _CatalogNotice({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: SpFinanceUi.softDecoration(context),
      child: Row(
        children: [
          Icon(icon, color: context.brandPrimary),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: SpFinanceUi.labelStyle)),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}
