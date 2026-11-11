import '../../../core/ui/app_search_field.dart';
import 'sp_status_text.dart';
import '../../../core/utils/commerce_text.dart';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../training/presentation/training_target.dart';
import '../../../core/network/api_config.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/ui/unsaved_changes_guard.dart';
import '../../../core/ui/app_cached_media_image.dart';
import '../../../core/ui/app_layout.dart';
import '../../../core/ui/empty_state.dart';
import '../../../core/utils/file_download_helper.dart';
import '../../../core/utils/image_compressor.dart';
import '../../../core/utils/locale_text.dart';
import '../../photos/domain/photo_item.dart';
import '../../photos/presentation/photo_viewer_screen.dart';
import '../data/sp_organizer_export_xlsx.dart';
import '../data/sp_organizer_provider.dart';
import '../data/sp_v2_models.dart';
import '../data/sp_v2_provider.dart';
import '../data/sp_v2_repository.dart';
import 'sp_finance_ui.dart';
import 'sp_organizer_garage_import_sheet.dart';
import 'sp_organizer_previous_purchase_import_sheet.dart';
import 'sp_organizer_purchase_blank_import_sheet.dart';
import 'sp_organizer_purchase_kind.dart';
import 'sp_organizer_track_import_sheet.dart';
import 'sp_organizer_workspace_panel.dart';
import 'sp_purchase_client_sections_editor.dart';
import 'sp_purchase_status_dates.dart';
import 'sp_v2_bulk_actions_sheet.dart';
import 'sp_v2_help_sheet.dart';

enum _PurchaseDetailTab { items, participants, finance, tracks, settings }

class SpV2PurchaseDetailScreen extends ConsumerStatefulWidget {
  final int purchaseId;

  const SpV2PurchaseDetailScreen({super.key, required this.purchaseId});

  @override
  ConsumerState<SpV2PurchaseDetailScreen> createState() =>
      _SpV2PurchaseDetailScreenState();
}

class _SpV2PurchaseDetailScreenState
    extends ConsumerState<SpV2PurchaseDetailScreen> {
  final _scrollController = ScrollController();
  _PurchaseDetailTab _selectedTab = _PurchaseDetailTab.items;
  bool _isExporting = false;
  bool _isUpdatingPurchaseStatus = false;
  final Set<int> _updatingItemStatusIds = <int>{};
  final Set<String> _updatingPaymentKeys = <String>{};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(spV2PurchaseDetailProvider(widget.purchaseId));
    final organizerCapabilities = ref
        .watch(spOrganizerCapabilitiesProvider)
        .asData
        ?.value;
    final topPad = AppLayout.topBarTotalHeight(context);
    final bottomPad = AppLayout.bottomScrollPadding(context);

    return detail.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Не удалось открыть СП',
        message: error.toString(),
      ),
      data: (purchase) {
        final showSettingsTab =
            purchase.currency == 'CNY' ||
            organizerCapabilities?.calculationProfiles == true ||
            organizerCapabilities?.fulfillmentOverview == true;
        final activeTab =
            _selectedTab == _PurchaseDetailTab.settings && !showSettingsTab
            ? _PurchaseDetailTab.items
            : _selectedTab;

        return RefreshIndicator(
          color: context.brandPrimary,
          onRefresh: () async {
            ref.invalidate(spV2PurchaseDetailProvider(widget.purchaseId));
            ref.invalidate(spOrganizerParticipantsProvider(widget.purchaseId));
            ref.invalidate(
              spOrganizerCalculationPreviewProvider(widget.purchaseId),
            );
            await ref.read(
              spV2PurchaseDetailProvider(widget.purchaseId).future,
            );
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
                title: tr(context, ru: 'СП', zh: '采购'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PurchaseEditButton(
                      onTap: () => _showEditPurchaseSheet(
                        purchase,
                        purchaseKindsEnabled:
                            organizerCapabilities?.purchaseKinds == true,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (organizerCapabilities?.purchaseExport == true) ...[
                      _PurchaseExportButton(
                        isLoading: _isExporting,
                        onTap: () => _exportPurchase(purchase),
                      ),
                      const SizedBox(width: 6),
                    ],
                    SpV2HelpButton(onTap: () => showSpV2HelpSheet(context)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _DetailHero(purchase: purchase),
              const SizedBox(height: 12),
              Container(
                decoration: SpFinanceUi.cardDecoration(),
                child: ExpansionTile(
                  key: PageStorageKey('sp-purchase-management-${purchase.id}'),
                  title: Text(tr(context, ru: 'Управление СП', zh: '采购管理')),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  children: [
                    if (purchase.description?.trim().isNotEmpty == true) ...[
                      Text(purchase.description!, style: SpFinanceUi.bodyStyle),
                      const SizedBox(height: 12),
                    ],
                    _PurchaseLifecycleCard(purchase: purchase),
                    const SizedBox(height: 12),
                    _QuickActions(
                      purchase: purchase,
                      onStatusChanged: (status) => _updateStatus(status),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _TabsBar(
                selectedTab: activeTab,
                showSettings: showSettingsTab,
                onChanged: (tab) => setState(() => _selectedTab = tab),
              ),
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: switch (activeTab) {
                  _PurchaseDetailTab.items => _ItemsTab(
                    key: const ValueKey('items'),
                    purchase: purchase,
                    onAddItem: () => _showAddItemSheet(purchase),
                    onBulkPrice: () => _showBulkClientPriceSheet(
                      purchase,
                      atomicBulkEnabled:
                          organizerCapabilities?.bulkOperations == true,
                    ),
                    onBulkDelivery: () => _showBulkDeliverySheet(
                      purchase,
                      atomicBulkEnabled:
                          organizerCapabilities?.bulkOperations == true,
                    ),
                    onBulkManage: organizerCapabilities?.bulkOperations == true
                        ? () => _showBulkActionsSheet(purchase)
                        : null,
                    onEditItem: (item) => _showEditItemSheet(purchase, item),
                    onTogglePurchased: _toggleItemPurchased,
                    onToggleGoodsPaid: (item) =>
                        _toggleItemPayment(purchase, item, 'goods_payment'),
                    onToggleDeliveryPaid: (item) =>
                        _toggleItemPayment(purchase, item, 'delivery_payment'),
                  ),
                  _PurchaseDetailTab.participants => Column(
                    key: const ValueKey('participants'),
                    children: [
                      if (organizerCapabilities?.participants == true) ...[
                        SpOrganizerWorkspacePanel(
                          purchaseId: widget.purchaseId,
                          showCalculation: false,
                          showFulfillment: false,
                        ),
                        const SizedBox(height: 12),
                      ],
                      _CustomersTab(
                        purchase: purchase,
                        onCustomerTap: _showCustomerSheet,
                        onToggleCustomerGoodsPaid: _toggleCustomerGoodsPaid,
                        onToggleCustomerDeliveryPaid:
                            _toggleCustomerDeliveryPaid,
                        onToggleCustomerExtraPaid: _toggleCustomerExtraPaid,
                      ),
                    ],
                  ),
                  _PurchaseDetailTab.finance => _FinanceTab(
                    key: const ValueKey('finance'),
                    purchase: purchase,
                    onToggleCustomerGoodsPaid: _toggleCustomerGoodsPaid,
                    onToggleCustomerDeliveryPaid: _toggleCustomerDeliveryPaid,
                    onToggleCustomerExtraPaid: _toggleCustomerExtraPaid,
                    onAddExpense: _showExpenseSheet,
                    onBulkDelivery: (purchase) => _showBulkDeliverySheet(
                      purchase,
                      atomicBulkEnabled:
                          organizerCapabilities?.bulkOperations == true,
                    ),
                  ),
                  _PurchaseDetailTab.tracks => _TracksTab(
                    key: const ValueKey('tracks'),
                    purchase: purchase,
                  ),
                  _PurchaseDetailTab.settings => _PurchaseSettingsTab(
                    key: const ValueKey('settings'),
                    purchase: purchase,
                    purchaseId: widget.purchaseId,
                    showCalculation:
                        organizerCapabilities?.calculationProfiles == true,
                    showFulfillment:
                        organizerCapabilities?.fulfillmentOverview == true,
                    onEditRate: () => _showRateSheet(purchase),
                  ),
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAddItemSheet(SpV2Purchase purchase) async {
    final created = await showSpFinanceModalSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => _AddItemSheet(purchase: purchase),
    );
    if (!mounted || created != true) return;
    ref.invalidate(spV2PurchaseDetailProvider(widget.purchaseId));
    unawaited(
      ref.read(spV2PurchasesControllerProvider.notifier).load(silent: true),
    );
  }

  Future<void> _exportPurchase(SpV2Purchase purchase) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final export = await ref
          .read(spOrganizerRepositoryProvider)
          .getPurchaseExport(purchase.id);
      if (!mounted) return;
      final bytes = buildSpOrganizerPurchaseXlsx(
        export,
        languageCode: Localizations.localeOf(context).languageCode,
      );
      final saved = await downloadFile(bytes: bytes, fileName: export.fileName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? tr(
                    context,
                    ru: 'Экспортировано товаров: ${export.totalRows}',
                    zh: '已导出商品：${export.totalRows}',
                  )
                : tr(context, ru: 'Не удалось сохранить файл', zh: '无法保存文件'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(context, ru: 'Не удалось экспортировать закупку', zh: '无法导出采购'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _showEditItemSheet(SpV2Purchase purchase, SpV2Item item) async {
    final updated = await showSpFinanceModalSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => _EditItemSheet(purchase: purchase, item: item),
    );
    if (!mounted || updated != true) return;
    ref.invalidate(spV2PurchaseDetailProvider(widget.purchaseId));
    unawaited(
      ref.read(spV2PurchasesControllerProvider.notifier).load(silent: true),
    );
  }

  Future<void> _showBulkClientPriceSheet(
    SpV2Purchase purchase, {
    bool atomicBulkEnabled = false,
  }) async {
    final updated = await showSpFinanceModalSheet<bool>(
      context: context,
      builder: (context) => _BulkClientPriceSheet(
        purchase: purchase,
        atomicBulkEnabled: atomicBulkEnabled,
      ),
    );
    if (!mounted || updated != true) return;
    _refreshDetail();
  }

  Future<void> _showBulkDeliverySheet(
    SpV2Purchase purchase, {
    bool atomicBulkEnabled = false,
  }) async {
    final updated = await showSpFinanceModalSheet<bool>(
      context: context,
      builder: (context) => _BulkDeliverySheet(
        purchase: purchase,
        atomicBulkEnabled: atomicBulkEnabled,
      ),
    );
    if (!mounted || updated != true) return;
    _refreshDetail();
  }

  Future<void> _showBulkActionsSheet(SpV2Purchase purchase) async {
    final updated = await showSpFinanceModalSheet<bool>(
      context: context,
      builder: (context) => SpV2BulkActionsSheet(purchase: purchase),
    );
    if (!mounted || updated != true) return;
    _refreshDetail();
    unawaited(
      ref.read(spV2PurchasesControllerProvider.notifier).load(silent: true),
    );
  }

  Future<void> _showCustomerSheet(
    SpV2Purchase purchase,
    SpV2Customer customer,
  ) async {
    await showSpFinanceModalSheet<void>(
      context: context,
      builder: (context) => _CustomerDetailSheet(
        purchase: purchase,
        customer: customer,
        onToggleGoodsPaid: _toggleCustomerGoodsPaid,
        onToggleDeliveryPaid: _toggleCustomerDeliveryPaid,
        onToggleExtraPaid: _toggleCustomerExtraPaid,
        onEditCustomer: _showEditCustomerSheet,
        onEditShipment: _showShipmentSheet,
      ),
    );
  }

  Future<void> _showEditCustomerSheet(SpV2Customer customer) async {
    final updated = await showSpFinanceModalSheet<bool>(
      context: context,
      builder: (context) => _EditCustomerSheet(customer: customer),
    );
    if (!mounted || updated != true) return;
    ref.invalidate(spV2CustomersProvider);
    _refreshDetail();
  }

  Future<void> _showExpenseSheet(SpV2Purchase purchase) async {
    final created = await showSpFinanceModalSheet<bool>(
      context: context,
      builder: (context) => _AddExpenseSheet(purchase: purchase),
    );
    if (!mounted || created != true) return;
    _refreshDetail();
  }

  Future<void> _showRateSheet(SpV2Purchase purchase) async {
    final updated = await showSpFinanceModalSheet<bool>(
      context: context,
      builder: (context) => _PurchaseRateSheet(purchase: purchase),
    );
    if (!mounted || updated != true) return;
    _refreshDetail();
  }

  Future<void> _showEditPurchaseSheet(
    SpV2Purchase purchase, {
    required bool purchaseKindsEnabled,
  }) async {
    final updated = await showSpFinanceModalSheet<bool>(
      context: context,
      builder: (context) => _EditPurchaseSheet(
        purchase: purchase,
        purchaseKindsEnabled: purchaseKindsEnabled,
      ),
    );
    if (!mounted || updated != true) return;
    _refreshDetail();
  }

  Future<void> _showShipmentSheet(
    SpV2Purchase purchase,
    SpV2Customer customer,
  ) async {
    SpV2CustomerShipment? shipment;
    for (final entry in purchase.shipments) {
      if (entry.spCustomerId == customer.id) {
        shipment = entry;
        break;
      }
    }
    final updated = await showSpFinanceModalSheet<bool>(
      context: context,
      builder: (context) => _EditShipmentSheet(
        purchase: purchase,
        customer: customer,
        shipment: shipment,
      ),
    );
    if (!mounted || updated != true) return;
    _refreshDetail();
  }

  Future<void> _updateStatus(String status) async {
    if (_isUpdatingPurchaseStatus) return;
    _isUpdatingPurchaseStatus = true;
    try {
      await ref
          .read(spV2RepositoryProvider)
          .updatePurchase(
            widget.purchaseId,
            status: status,
            isAcceptingItems: status == 'open',
          );
      if (!mounted) return;
      ref.invalidate(spV2PurchaseDetailProvider(widget.purchaseId));
      unawaited(
        ref.read(spV2PurchasesControllerProvider.notifier).load(silent: true),
      );
    } catch (error) {
      if (!mounted) return;
      _showActionError(error, action: 'обновить статус СП');
    } finally {
      _isUpdatingPurchaseStatus = false;
    }
  }

  Future<void> _toggleItemPurchased(SpV2Item item) async {
    if (!_updatingItemStatusIds.add(item.id)) return;
    try {
      await ref
          .read(spV2RepositoryProvider)
          .updateItem(
            item.id,
            status: item.isPurchased ? 'approved' : 'purchased',
          );
      if (!mounted) return;
      _refreshDetail();
    } catch (error) {
      if (!mounted) return;
      _showActionError(error, action: 'обновить статус товара');
    } finally {
      _updatingItemStatusIds.remove(item.id);
    }
  }

  Future<void> _toggleItemPayment(
    SpV2Purchase purchase,
    SpV2Item item,
    String type,
  ) async {
    final actionKey = 'item:${item.id}:$type';
    if (!_updatingPaymentKeys.add(actionKey)) return;
    final isPaid = type == 'goods_payment'
        ? item.isGoodsPaid
        : item.isDeliveryPaid;
    try {
      await ref
          .read(spV2RepositoryProvider)
          .setItemPayment(
            item.id,
            type: type,
            paid: !isPaid,
            amountRub: type == 'goods_payment'
                ? _goodsPaymentAmountRub(item, purchase)
                : _deliveryPaymentAmountRub(item),
          );
      if (!mounted) return;
      _refreshDetail();
    } catch (error) {
      if (!mounted) return;
      _showActionError(
        error,
        action: type == 'goods_payment'
            ? 'отметить оплату товара'
            : 'отметить оплату доставки',
      );
    } finally {
      _updatingPaymentKeys.remove(actionKey);
    }
  }

  Future<void> _toggleCustomerGoodsPaid(
    SpV2Purchase purchase,
    SpV2Customer customer,
  ) async {
    await _toggleCustomerPayment(purchase, customer, 'goods_payment');
  }

  Future<void> _toggleCustomerDeliveryPaid(
    SpV2Purchase purchase,
    SpV2Customer customer,
  ) async {
    await _toggleCustomerPayment(purchase, customer, 'delivery_payment');
  }

  Future<void> _toggleCustomerExtraPaid(
    SpV2Purchase purchase,
    SpV2Customer customer,
  ) async {
    final actionKey = 'customer:${customer.id}:extra_payment';
    if (!_updatingPaymentKeys.add(actionKey)) return;
    final finance = _PurchaseFinance.fromPurchase(
      purchase,
    ).forCustomer(customer.id);
    if (finance == null || finance.extraDueRub <= 0) {
      _updatingPaymentKeys.remove(actionKey);
      return;
    }
    try {
      await ref
          .read(spV2RepositoryProvider)
          .setCustomerPayment(
            customer.id,
            purchaseId: purchase.id,
            type: 'extra_payment',
            paid: !finance.allExtraPaid,
            amountRub: finance.extraDueRub,
          );
      if (!mounted) return;
      _refreshDetail();
    } catch (error) {
      if (!mounted) return;
      _showActionError(error, action: 'отметить оплату доп. расходов');
    } finally {
      _updatingPaymentKeys.remove(actionKey);
    }
  }

  Future<void> _toggleCustomerPayment(
    SpV2Purchase purchase,
    SpV2Customer customer,
    String type,
  ) async {
    final actionKey = 'customer:${customer.id}:$type';
    if (!_updatingPaymentKeys.add(actionKey)) return;
    final items = purchase.items
        .where((item) => item.customer?.id == customer.id)
        .toList(growable: false);
    if (items.isEmpty) {
      _updatingPaymentKeys.remove(actionKey);
      return;
    }

    final allPaid = items.every(
      (item) =>
          type == 'goods_payment' ? item.isGoodsPaid : item.isDeliveryPaid,
    );
    final nextPaid = !allPaid;
    final repository = ref.read(spV2RepositoryProvider);
    try {
      if (items.any((item) => item.updatedAt == null)) {
        _refreshDetail();
        _showActionError(
          StateError('missing-version'),
          action: 'отметить оплату клиента',
        );
        return;
      }
      await repository.setCustomerItemsPayment(
        customer.id,
        purchaseId: purchase.id,
        type: type,
        paid: nextPaid,
        items: items
            .map(
              (item) => (
                id: item.id,
                expectedUpdatedAt: item.updatedAt!,
                amountRub: type == 'goods_payment'
                    ? _goodsPaymentAmountRub(item, purchase)
                    : _deliveryPaymentAmountRub(item),
              ),
            )
            .toList(growable: false),
      );
      if (!mounted) return;
      _refreshDetail();
    } catch (error) {
      if (!mounted) return;
      _showActionError(
        error,
        action: type == 'goods_payment'
            ? 'отметить оплату товаров клиента'
            : 'отметить оплату доставки клиента',
      );
    } finally {
      _updatingPaymentKeys.remove(actionKey);
      if (mounted) _refreshDetail();
    }
  }

  void _refreshDetail() {
    ref.invalidate(spV2PurchaseDetailProvider(widget.purchaseId));
    unawaited(
      ref.read(spV2PurchasesControllerProvider.notifier).load(silent: true),
    );
  }

  void _showActionError(Object error, {required String action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_spActionErrorMessage(context, error, action: action)),
      ),
    );
  }
}

String _spActionErrorMessage(
  BuildContext context,
  Object error, {
  required String action,
}) {
  if ((error is DioException &&
          error.response?.data is Map &&
          (error.response?.data as Map)['code'] == 'SP_BULK_ITEMS_STALE') ||
      (error is StateError && error.message == 'missing-version')) {
    return tr(
      context,
      ru: 'Данные товаров изменились. Обновите закупку и повторите действие.',
      zh: '商品数据已改变，请刷新采购后重试。',
    );
  }
  if ((error is StateError && error.message == 'atomic-bulk-unavailable') ||
      (error is DioException && error.response?.statusCode == 404)) {
    return tr(
      context,
      ru: 'Действие сейчас недоступно. Обновите закупку; если проблема повторится, обратитесь в поддержку.',
      zh: '此操作暂不可用，请刷新采购。如果问题持续，请联系支持。',
    );
  }
  return tr(
    context,
    ru: 'Не удалось $action. Данные сохранены в форме. Проверьте соединение и повторите попытку.',
    zh: '操作失败，表单内容已保留。请检查网络后重试。',
  );
}

String _currencySymbol(String currency) => currency == 'RUB' ? '₽' : '¥';

String _formatRub(double value) => '${value.toStringAsFixed(0)} ₽';

int? _readPositiveInt(String value) {
  final parsed = int.tryParse(value.trim());
  return parsed != null && parsed > 0 ? parsed : null;
}

double? _readDecimalInput(String value) {
  final normalized = value.trim().replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  return double.tryParse(normalized);
}

double _itemBaseRub(SpV2Item item, SpV2Purchase purchase) {
  final quantity = item.quantity <= 0 ? 1 : item.quantity;
  if (purchase.currency == 'RUB') {
    return item.clientPriceRub * quantity;
  }
  if (item.clientPriceRub > 0) return item.clientPriceRub * quantity;
  if (purchase.purchaseRate > 0 && item.clientPriceYuan > 0) {
    return item.clientPriceYuan * purchase.purchaseRate * quantity;
  }
  return 0;
}

double _itemCostRub(SpV2Item item, SpV2Purchase purchase) {
  final quantity = item.quantity <= 0 ? 1 : item.quantity;
  if (item.costPriceRub > 0) return item.costPriceRub * quantity;
  if (purchase.purchaseRate > 0 && item.purchasePriceYuan > 0) {
    return item.purchasePriceYuan * purchase.purchaseRate * quantity;
  }
  return 0;
}

double _itemProfitRub(SpV2Item item, SpV2Purchase purchase) {
  final goods = _itemBaseRub(item, purchase);
  final cost = _itemCostRub(item, purchase);
  final goodsMargin = goods - cost;
  final deliveryMargin =
      item.shippingCostRub > 0 || item.shippingCostActualRub > 0
      ? item.shippingCostRub - item.shippingCostActualRub
      : 0.0;
  return goodsMargin + deliveryMargin;
}

double? _itemTotalRubWithClientPrice(
  SpV2Item item,
  SpV2Purchase purchase,
  double clientPrice,
) {
  final quantity = item.quantity <= 0 ? 1 : item.quantity;
  final goodsRub = purchase.currency == 'RUB'
      ? clientPrice * quantity
      : purchase.purchaseRate > 0
      ? clientPrice * purchase.purchaseRate * quantity
      : null;
  if (goodsRub == null) return null;
  return goodsRub + item.shippingCostRub + item.additionalExpensesRub;
}

double? _goodsPaymentAmountRub(SpV2Item item, SpV2Purchase purchase) {
  final value = _itemBaseRub(item, purchase);
  return value > 0 ? value : null;
}

double? _deliveryPaymentAmountRub(SpV2Item item) {
  return item.shippingCostRub > 0 ? item.shippingCostRub : null;
}

double _itemGoodsPaidRub(SpV2Item item, SpV2Purchase purchase) {
  final paid = item.payments
      .where((payment) => payment.type == 'goods_payment' && payment.isPaid)
      .fold<double>(0, (sum, payment) => sum + payment.amountRub);
  if (paid > 0) return paid;
  return item.isGoodsPaid ? _itemBaseRub(item, purchase) : 0;
}

double _itemDeliveryPaidRub(SpV2Item item) {
  final paid = item.payments
      .where((payment) => payment.type == 'delivery_payment' && payment.isPaid)
      .fold<double>(0, (sum, payment) => sum + payment.amountRub);
  if (paid > 0) return paid;
  return item.isDeliveryPaid ? item.shippingCostRub : 0;
}

double _itemTotalRub(SpV2Item item, SpV2Purchase purchase) {
  if (item.totalDueRub > 0) return item.totalDueRub;
  return _itemBaseRub(item, purchase) +
      item.shippingCostRub +
      item.additionalExpensesRub;
}

String _digitsOnly(String value) => value.replaceAll(RegExp(r'\D'), '');

String _telegramUsername(String value) {
  var username = value.trim();
  if (username.startsWith('https://t.me/')) {
    username = username.replaceFirst('https://t.me/', '');
  }
  if (username.startsWith('http://t.me/')) {
    username = username.replaceFirst('http://t.me/', '');
  }
  if (username.startsWith('@')) username = username.substring(1);
  return username.split('/').first.trim();
}

Future<void> _launchContactUrl(
  BuildContext context,
  String value,
  Uri Function(String value) uriBuilder, {
  Uri Function(String value)? fallbackBuilder,
  String? copyValue,
  String copyMessage = 'Контакт скопирован',
}) async {
  final prepared = value.trim();
  if (prepared.isEmpty) return;
  try {
    final primary = uriBuilder(prepared);
    final opened = await launchUrl(
      primary,
      mode: LaunchMode.externalApplication,
    );
    if (opened) return;
    if (fallbackBuilder != null) {
      final fallbackOpened = await launchUrl(
        fallbackBuilder(prepared),
        mode: LaunchMode.externalApplication,
      );
      if (fallbackOpened) return;
    }
  } catch (_) {
    // Если диплинк не поддержан, ниже дадим безопасный fallback через копирование.
  }

  await Clipboard.setData(ClipboardData(text: copyValue ?? prepared));
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(copyMessage)));
}

Uri? _normalizeExternalLink(String value) {
  var prepared = value.trim();
  if (prepared.isEmpty) return null;
  if (!prepared.contains('://')) {
    prepared = 'https://$prepared';
  }
  final uri = Uri.tryParse(prepared);
  if (uri == null || uri.host.trim().isEmpty) return null;
  return uri;
}

String _externalLinkHostLabel(String value) {
  final uri = _normalizeExternalLink(value);
  if (uri == null) return value.trim();
  return uri.host.replaceFirst(RegExp(r'^www\.'), '');
}

Future<void> _openExternalLink(BuildContext context, String value) async {
  final uri = _normalizeExternalLink(value);
  if (uri == null) {
    await Clipboard.setData(ClipboardData(text: value.trim()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Ссылка скопирована')));
    return;
  }

  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (opened) return;
  } catch (_) {
    // Если система не смогла открыть ссылку, ниже даём fallback.
  }

  await Clipboard.setData(ClipboardData(text: uri.toString()));
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('Ссылка скопирована')));
}

List<PhotoItem> _spMediaPhotos(List<SpV2Media> media) {
  return media
      .where((entry) => entry.url.trim().isNotEmpty)
      .map(
        (entry) => PhotoItem(
          id: entry.id,
          url: ApiConfig.getMediaUrl(entry.url),
          date: DateTime.now(),
        ),
      )
      .toList(growable: false);
}

void _openSpMediaGallery(
  BuildContext context,
  List<SpV2Media> media, {
  int initialIndex = 0,
}) {
  final photos = _spMediaPhotos(media);
  if (photos.isEmpty) return;
  final safeIndex = initialIndex.clamp(0, photos.length - 1).toInt();
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PhotoViewerScreen(
        item: photos[safeIndex],
        allPhotos: photos,
        initialIndex: safeIndex,
      ),
    ),
  );
}

class _CustomerContactActions extends StatelessWidget {
  final SpV2Customer customer;
  final bool compact;
  final VoidCallback? onEdit;

  const _CustomerContactActions({
    required this.customer,
    this.compact = false,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[];
    final phone = customer.phone?.trim();
    if (phone != null && phone.isNotEmpty) {
      actions.add(
        _ContactActionChip(
          icon: Icons.call_rounded,
          label: compact ? null : 'Позвонить',
          onTap: () => _launchContactUrl(
            context,
            phone,
            (value) => Uri(scheme: 'tel', path: value),
            copyMessage: 'Телефон скопирован',
          ),
        ),
      );
    }
    final telegram = customer.telegram?.trim();
    if (telegram != null && telegram.isNotEmpty) {
      actions.add(
        _ContactActionChip(
          icon: Icons.send_rounded,
          label: compact ? null : 'Telegram',
          onTap: () async {
            final username = _telegramUsername(telegram);
            await _launchContactUrl(
              context,
              username,
              (value) => Uri.parse('tg://resolve?domain=$value'),
              fallbackBuilder: (value) => Uri.parse('https://t.me/$value'),
              copyValue: username.isEmpty ? telegram : '@$username',
              copyMessage: 'Telegram скопирован',
            );
          },
        ),
      );
    }
    final whatsapp = customer.whatsapp?.trim().isNotEmpty == true
        ? customer.whatsapp!.trim()
        : phone;
    if (whatsapp != null && whatsapp.isNotEmpty) {
      actions.add(
        _ContactActionChip(
          icon: Icons.chat_bubble_rounded,
          label: compact ? null : 'WhatsApp',
          onTap: () => _launchContactUrl(
            context,
            _digitsOnly(whatsapp),
            (value) => Uri.parse('https://wa.me/$value'),
            copyValue: whatsapp,
            copyMessage: 'WhatsApp/телефон скопирован',
          ),
        ),
      );
    }
    final wechat = customer.wechat?.trim();
    if (wechat != null && wechat.isNotEmpty) {
      actions.add(
        _ContactActionChip(
          icon: Icons.forum_rounded,
          label: compact ? null : 'WeChat',
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: wechat));
            if (!context.mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('WeChat скопирован')));
          },
        ),
      );
    }
    final vk = customer.vk?.trim();
    if (vk != null && vk.isNotEmpty) {
      actions.add(
        _ContactActionChip(
          icon: Icons.alternate_email_rounded,
          label: compact ? null : 'VK',
          onTap: () => _launchContactUrl(
            context,
            vk,
            (value) => value.startsWith('http')
                ? Uri.parse(value)
                : Uri.parse('https://vk.com/$value'),
            copyValue: vk,
            copyMessage: 'VK скопирован',
          ),
        ),
      );
    }
    final max = customer.max?.trim();
    if (max != null && max.isNotEmpty) {
      actions.add(
        _ContactActionChip(
          icon: Icons.forum_rounded,
          label: compact ? null : 'MAX',
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: max));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('MAX контакт скопирован')),
            );
          },
        ),
      );
    }
    if (onEdit != null) {
      actions.add(
        _ContactActionChip(
          icon: Icons.edit_rounded,
          label: compact ? null : 'Изменить',
          onTap: onEdit!,
        ),
      );
    }

    if (actions.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: actions);
  }
}

class _ContactActionChip extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;

  const _ContactActionChip({
    required this.icon,
    required this.onTap,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.brandPrimary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: label == null ? 10 : 12,
            vertical: 9,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: context.brandPrimary),
              if (label != null) ...[
                const SizedBox(width: 6),
                Text(
                  label!,
                  style: TextStyle(
                    color: context.brandPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailHero extends StatelessWidget {
  final SpV2Purchase purchase;
  const _DetailHero({required this.purchase});

  @override
  Widget build(BuildContext context) => SpAnimatedHeroSurface(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          purchase.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'Gilroy',
            fontSize: 20,
            height: 1.1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        SpHeroChip(
          icon: Icons.flag_rounded,
          label: isZh(context)
              ? spStatusText(context, purchase.status)
              : purchase.statusLabel,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              tr(
                context,
                ru: 'Клиентов: ${purchase.stats.customersCount}',
                zh: '客户：${purchase.stats.customersCount}',
              ),
              style: _metadataStyle,
            ),
            Text(
              tr(
                context,
                ru: 'Товаров: ${purchase.stats.itemsCount}',
                zh: '商品：${purchase.stats.itemsCount}',
              ),
              style: _metadataStyle,
            ),
            Text(
              tr(
                context,
                ru: 'Расчёт в ${_currencySymbol(purchase.currency)}',
                zh: '结算货币：${_currencySymbol(purchase.currency)}',
              ),
              style: _metadataStyle,
            ),
          ],
        ),
      ],
    ),
  );
  static const _metadataStyle = TextStyle(
    color: Color(0xE6FFFFFF),
    fontFamily: 'Gilroy',
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w700,
  );
}

class _PurchaseLifecycleCard extends StatelessWidget {
  final SpV2Purchase purchase;

  const _PurchaseLifecycleCard({required this.purchase});

  @override
  Widget build(BuildContext context) {
    final stage = spPurchaseCreationStageForStatus(purchase.status);
    final fallbackStageAt = purchase.updatedAt ?? purchase.createdAt;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route_rounded, color: context.brandPrimary, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Этапы закупки',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'Gilroy',
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SpPurchaseLifecycleSummary(
            currentStage: stage,
            startedAt: purchase.startedAt ?? purchase.createdAt,
            dispatchedFromChinaAt:
                purchase.dispatchedFromChinaAt ??
                (purchase.status == 'in_transit' ? fallbackStageAt : null),
            completedAt:
                purchase.completedAt ??
                (stage == SpPurchaseCreationStage.delivered
                    ? fallbackStageAt
                    : null),
          ),
        ],
      ),
    );
  }
}

class _PurchaseEditButton extends StatelessWidget {
  final VoidCallback onTap;

  const _PurchaseEditButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SpFinanceHeaderActionButton(
      buttonKey: const Key('sp-purchase-edit'),
      tooltip: 'Изменить закупку',
      onTap: onTap,
      child: Icon(Icons.edit_rounded, color: context.brandPrimary, size: 20),
    );
  }
}

class _EditPurchaseSheet extends ConsumerStatefulWidget {
  final SpV2Purchase purchase;
  final bool purchaseKindsEnabled;

  const _EditPurchaseSheet({
    required this.purchase,
    required this.purchaseKindsEnabled,
  });

  @override
  ConsumerState<_EditPurchaseSheet> createState() => _EditPurchaseSheetState();
}

class _EditPurchaseSheetState extends ConsumerState<_EditPurchaseSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final SpPurchaseCreationStage _initialStage;
  late SpPurchaseCreationTimelineValue _timeline;
  late String _kind;
  late String _currency;
  late SpV2ClientCardSections _clientCardSections;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.purchase.title);
    _descriptionController = TextEditingController(
      text: widget.purchase.description ?? '',
    );
    _kind = widget.purchase.kind;
    _currency = widget.purchase.currency;
    _clientCardSections = widget.purchase.clientCardSections;
    _initialStage = spPurchaseCreationStageForStatus(widget.purchase.status);
    _timeline = SpPurchaseCreationTimelineValue.fromExisting(
      status: widget.purchase.status,
      startedAt: widget.purchase.startedAt,
      dispatchedFromChinaAt: widget.purchase.dispatchedFromChinaAt,
      completedAt: widget.purchase.completedAt,
      createdAt: widget.purchase.createdAt,
      updatedAt: widget.purchase.updatedAt,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.94;
    return SafeArea(
      bottom: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 58,
              height: 6,
              decoration: BoxDecoration(
                color: const Color(0xFFE1E5ED),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: context.brandPrimary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.edit_calendar_rounded,
                      color: context.brandPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Редактирование СП',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontFamily: 'Gilroy',
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Название, формат, валюта, статус и даты',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontFamily: 'Gilroy',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                children: [
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
                    ),
                  ),
                  if (widget.purchaseKindsEnabled) ...[
                    const SizedBox(height: 10),
                    SpOrganizerPurchaseKindSelector(
                      value: _kind,
                      onChanged: (value) => setState(() => _kind = value),
                    ),
                  ],
                  const SizedBox(height: 10),
                  SpCurrencySelector(
                    value: _currency,
                    onChanged: (value) => setState(() => _currency = value),
                  ),
                  const SizedBox(height: 12),
                  SpPurchaseStatusDatesEditor(
                    value: _timeline,
                    onChanged: (value) => setState(() {
                      _timeline = value;
                      _error = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  SpPurchaseClientSectionsEditor(
                    value: _clientCardSections,
                    onChanged: (value) => setState(() {
                      _clientCardSections = value;
                      _error = null;
                    }),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    SpInfoNotice(
                      title: 'Не удалось сохранить',
                      message: _error!,
                      icon: Icons.error_outline_rounded,
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(18, 10, 18, 18 + bottomPadding),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFEFF2F6))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.brandPrimary,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      key: const Key('sp-purchase-edit-save'),
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
                      label: const Text('Сохранить'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.brandPrimary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Укажите название СП');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final stageChanged = _timeline.stage != _initialStage;
      final status = stageChanged
          ? _timeline.backendStatus
          : widget.purchase.status;
      await ref
          .read(spV2RepositoryProvider)
          .updatePurchaseLifecycle(
            widget.purchase.id,
            title: title,
            kind: widget.purchaseKindsEnabled ? _kind : null,
            description: _descriptionController.text.trim(),
            status: status,
            currency: _currency,
            isAcceptingItems: status == 'open',
            startedAt: _timeline.startedAt,
            dispatchedFromChinaAt: _timeline.dispatchedFromChinaAt,
            completedAt: _timeline.completedAt,
            clientCardSections: _clientCardSections,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _PurchaseExportButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;

  const _PurchaseExportButton({required this.isLoading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SpFinanceHeaderActionButton(
      tooltip: tr(context, ru: 'Экспортировать закупку', zh: '导出采购'),
      onTap: isLoading ? null : onTap,
      child: isLoading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.brandPrimary,
              ),
            )
          : Icon(
              Icons.file_download_outlined,
              color: context.brandPrimary,
              size: 21,
            ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final SpV2Purchase purchase;
  final ValueChanged<String> onStatusChanged;

  const _QuickActions({required this.purchase, required this.onStatusChanged});

  @override
  Widget build(BuildContext context) {
    return _ActionButton(
      icon: purchase.isAcceptingItems
          ? Icons.lock_rounded
          : Icons.lock_open_rounded,
      label: purchase.isAcceptingItems
          ? tr(context, ru: 'Закрыть приём', zh: '停止接收')
          : tr(context, ru: 'Открыть приём', zh: '开放接收'),
      filled: purchase.isAcceptingItems,
      onTap: () => onStatusChanged(
        purchase.isAcceptingItems ? 'closed_for_items' : 'open',
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = filled ? Colors.white : context.brandPrimary;
    return Material(
      color: filled
          ? context.brandPrimary
          : context.brandPrimary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontFamily: 'Gilroy',
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PurchaseRateCard extends StatelessWidget {
  final SpV2Purchase purchase;
  final VoidCallback onTap;

  const _PurchaseRateCard({required this.purchase, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasRate = purchase.purchaseRate > 0;
    return SpInfoNotice(
      icon: Icons.currency_exchange_rounded,
      title: hasRate
          ? 'Курс юаня: 1 ¥ = ${purchase.purchaseRate.toStringAsFixed(2)} ₽'
          : 'Укажите курс юаня',
      message: hasRate
          ? 'Цены товаров вводятся в юанях, а финансы и отметки оплат считаются в рублях по этому курсу.'
          : 'Без курса приложение сохранит цены в юанях, но рублёвые итоги, оплаты и прибыль по товарам будут неполными.',
      trailing: _MiniEditButton(
        label: hasRate ? 'Изменить' : 'Указать',
        onTap: onTap,
      ),
    );
  }
}

class _MiniEditButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _MiniEditButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: context.brandPrimary.withValues(alpha: 0.16),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: context.brandPrimary,
              fontFamily: 'Gilroy',
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _PurchaseRateSheet extends ConsumerStatefulWidget {
  final SpV2Purchase purchase;

  const _PurchaseRateSheet({required this.purchase});

  @override
  ConsumerState<_PurchaseRateSheet> createState() => _PurchaseRateSheetState();
}

class _PurchaseRateSheetState extends ConsumerState<_PurchaseRateSheet> {
  late final TextEditingController _rateController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _rateController = TextEditingController(
      text: widget.purchase.purchaseRate > 0
          ? widget.purchase.purchaseRate.toStringAsFixed(2)
          : '',
    );
  }

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SafeArea(
        bottom: false,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(18, 10, 18, 18 + bottomInset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE1E5ED),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                SpAnimatedHeroSurface(
                  padding: const EdgeInsets.all(16),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.currency_exchange_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Курс юаня',
                              style: TextStyle(
                                color: Colors.white,
                                fontFamily: 'Gilroy',
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Нужен для рублёвых итогов, оплат и прибыли.',
                              style: TextStyle(
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
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _rateController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: SpFinanceUi.inputDecoration(
                    context,
                    labelText: '1 ¥ в рублях',
                    hintText: 'Например: 12.80',
                    suffixText: '₽',
                  ),
                ),
                const SizedBox(height: 10),
                const SpInfoNotice(
                  title: 'Что пересчитается',
                  message:
                      'Цена клиента и цена выкупа в юанях будут использовать этот курс для расчёта рублёвых оплат и прибыли. Сами введённые цены в юанях не изменятся.',
                  icon: Icons.calculate_rounded,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
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
                    label: const Text('Сохранить курс'),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final rate = double.tryParse(
      _rateController.text.trim().replaceAll(',', '.'),
    );
    if (rate == null || rate <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите курс юаня больше 0')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(spV2RepositoryProvider)
          .updatePurchase(widget.purchase.id, purchaseRate: rate);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить курс: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _TabsBar extends StatelessWidget {
  final _PurchaseDetailTab selectedTab;
  final bool showSettings;
  final ValueChanged<_PurchaseDetailTab> onChanged;

  const _TabsBar({
    required this.selectedTab,
    required this.showSettings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tabs = [
      (
        Icons.shopping_bag_rounded,
        tr(context, ru: 'Товары', zh: '商品'),
        _PurchaseDetailTab.items,
      ),
      (
        Icons.people_rounded,
        tr(context, ru: 'Участники', zh: '参与者'),
        _PurchaseDetailTab.participants,
      ),
      (
        Icons.payments_rounded,
        tr(context, ru: 'Финансы', zh: '财务'),
        _PurchaseDetailTab.finance,
      ),
      (
        Icons.local_shipping_rounded,
        tr(context, ru: 'Треки', zh: '包裹'),
        _PurchaseDetailTab.tracks,
      ),
      if (showSettings)
        (
          Icons.tune_rounded,
          tr(context, ru: 'Настройки', zh: '设置'),
          _PurchaseDetailTab.settings,
        ),
    ];
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final width = textScale > 1.3 ? 124.0 : 88.0;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: SpFinanceUi.cardDecoration(),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              key: const ValueKey('sp-purchase-tabs-scroll'),
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        right: i == tabs.length - 1 ? 0 : 6,
                      ),
                      child: SizedBox(
                        width: width,
                        child: TrainingTarget(
                          id: 'organizer.tab.${tabs[i].$3.name}',
                          onActivate: () => onChanged(tabs[i].$3),
                          child: _TabButton(
                            icon: tabs[i].$1,
                            label: tabs[i].$2,
                            selected: selectedTab == tabs[i].$3,
                            onTap: () => onChanged(tabs[i].$3),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Tooltip(
            message: tr(context, ru: 'Прокрутите разделы', zh: '横向滑动查看页面'),
            child: const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? context.brandPrimary : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : context.brandPrimary,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.textSecondary,
                  fontFamily: 'Gilroy',
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PurchaseSettingsTab extends StatelessWidget {
  final SpV2Purchase purchase;
  final int purchaseId;
  final bool showCalculation;
  final bool showFulfillment;
  final VoidCallback onEditRate;

  const _PurchaseSettingsTab({
    super.key,
    required this.purchase,
    required this.purchaseId,
    required this.showCalculation,
    required this.showFulfillment,
    required this.onEditRate,
  });

  @override
  Widget build(BuildContext context) {
    final hasWorkspace = showCalculation || showFulfillment;
    return Column(
      children: [
        if (purchase.currency == 'CNY') ...[
          _PurchaseRateCard(purchase: purchase, onTap: onEditRate),
          if (hasWorkspace) const SizedBox(height: 12),
        ],
        if (hasWorkspace)
          SpOrganizerWorkspacePanel(
            purchaseId: purchaseId,
            showParticipants: false,
            showCalculation: showCalculation,
            showFulfillment: showFulfillment,
          ),
      ],
    );
  }
}

class _ItemsTab extends StatelessWidget {
  final SpV2Purchase purchase;
  final VoidCallback onAddItem;
  final VoidCallback onBulkPrice;
  final VoidCallback onBulkDelivery;
  final VoidCallback? onBulkManage;
  final ValueChanged<SpV2Item> onEditItem;
  final ValueChanged<SpV2Item> onTogglePurchased;
  final ValueChanged<SpV2Item> onToggleGoodsPaid;
  final ValueChanged<SpV2Item> onToggleDeliveryPaid;

  const _ItemsTab({
    super.key,
    required this.purchase,
    required this.onAddItem,
    required this.onBulkPrice,
    required this.onBulkDelivery,
    required this.onBulkManage,
    required this.onEditItem,
    required this.onTogglePurchased,
    required this.onToggleGoodsPaid,
    required this.onToggleDeliveryPaid,
  });

  @override
  Widget build(BuildContext context) {
    if (purchase.items.isEmpty) {
      return _TabEmptyCard(
        icon: Icons.shopping_bag_outlined,
        title: 'Товаров пока нет',
        message:
            'Добавьте клиента и то, что он хочет купить: ссылку, фото/описание, цену и параметры.',
        actionLabel: 'Добавить товар',
        onAction: onAddItem,
      );
    }
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('sp-add-item-tab-action'),
            onPressed: onAddItem,
            icon: const Icon(Icons.add_shopping_cart_rounded),
            label: Text(commerceText(context, 'Добавить товар')),
            style: FilledButton.styleFrom(
              backgroundColor: context.brandPrimary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(17),
              ),
              textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontFamily: 'Gilroy',
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          title: Text(tr(context, ru: 'Массовые действия', zh: '批量操作')),
          children: [
            if (onBulkManage != null) ...[
              _BulkManageActionCard(
                itemsCount: purchase.items.length,
                onTap: onBulkManage!,
              ),
              const SizedBox(height: 12),
            ],
            _BulkPriceActionCard(purchase: purchase, onTap: onBulkPrice),
            const SizedBox(height: 12),
            _BulkDeliveryActionCard(purchase: purchase, onTap: onBulkDelivery),
          ],
        ),
        const SizedBox(height: 12),
        ...purchase.items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ItemCard(
              item: item,
              purchase: purchase,
              onTap: () => onEditItem(item),
              onTogglePurchased: () => onTogglePurchased(item),
              onToggleGoodsPaid: () => onToggleGoodsPaid(item),
              onToggleDeliveryPaid: () => onToggleDeliveryPaid(item),
            ),
          ),
        ),
      ],
    );
  }
}

class _BulkManageActionCard extends StatelessWidget {
  final int itemsCount;
  final VoidCallback onTap;

  const _BulkManageActionCard({required this.itemsCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: itemsCount == 0 ? null : onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: SpFinanceUi.cardDecoration(
            color: context.brandPrimary.withValues(alpha: 0.065),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.brandPrimary.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.done_all_rounded,
                  color: context.brandPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Массовые действия',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Gilroy',
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Статус, перенос клиенту или в другую закупку, архив. Товаров: $itemsCount.',
                      style: SpFinanceUi.labelStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: itemsCount == 0
                    ? AppColors.textSecondary.withValues(alpha: 0.45)
                    : context.brandPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BulkPriceActionCard extends StatelessWidget {
  final SpV2Purchase purchase;
  final VoidCallback onTap;

  const _BulkPriceActionCard({required this.purchase, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final itemsWithPurchasePrice = purchase.items
        .where((item) => item.purchasePriceForCurrency(purchase.currency) > 0)
        .length;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: itemsWithPurchasePrice == 0 ? null : onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: SpFinanceUi.cardDecoration(
            color: context.brandPrimary.withValues(alpha: 0.055),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.brandPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.calculate_rounded,
                  color: context.brandPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Рассчитать цены клиента',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Gilroy',
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      itemsWithPurchasePrice == 0
                          ? 'Сначала заполните цену выкупа у товаров'
                          : 'Массово проставить цену клиента: без наценки, +% или фиксированно.',
                      style: SpFinanceUi.labelStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: itemsWithPurchasePrice == 0
                    ? AppColors.textSecondary.withValues(alpha: 0.45)
                    : context.brandPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BulkDeliveryActionCard extends StatelessWidget {
  final SpV2Purchase purchase;
  final VoidCallback onTap;

  const _BulkDeliveryActionCard({required this.purchase, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final itemsCount = purchase.items.length;
    final hasWeights = purchase.items.any((item) => item.actualWeightKg > 0);
    final clientDelivery = purchase.items.fold<double>(
      0,
      (sum, item) => sum + item.shippingCostRub,
    );
    final actualDelivery = purchase.items.fold<double>(
      0,
      (sum, item) => sum + item.shippingCostActualRub,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: itemsCount == 0 ? null : onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: SpFinanceUi.cardDecoration(
            color: context.brandPrimary.withValues(alpha: 0.045),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.brandPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.local_shipping_rounded,
                  color: context.brandPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Рассчитать доставку',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Gilroy',
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      itemsCount == 0
                          ? 'Сначала добавьте товары в СП'
                          : hasWeights
                          ? 'Распределить фактическую доставку СП и сумму клиентам по весу, товарам или клиентам.'
                          : 'Распределить доставку по товарам, количеству или клиентам. Для расчёта по весу заполните вес.',
                      style: SpFinanceUi.labelStyle,
                    ),
                    if (actualDelivery > 0 || clientDelivery > 0) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (actualDelivery > 0)
                            _InfoChip(
                              icon: Icons.receipt_long_rounded,
                              label: 'СП: ${_formatRub(actualDelivery)}',
                            ),
                          if (clientDelivery > 0)
                            _InfoChip(
                              icon: Icons.sell_rounded,
                              label: 'Клиентам: ${_formatRub(clientDelivery)}',
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: itemsCount == 0
                    ? AppColors.textSecondary.withValues(alpha: 0.45)
                    : context.brandPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _BulkClientPriceMode { same, percent, fixed }

class _BulkClientPriceSheet extends ConsumerStatefulWidget {
  final SpV2Purchase purchase;
  final bool atomicBulkEnabled;

  const _BulkClientPriceSheet({
    required this.purchase,
    required this.atomicBulkEnabled,
  });

  @override
  ConsumerState<_BulkClientPriceSheet> createState() =>
      _BulkClientPriceSheetState();
}

class _BulkClientPriceSheetState extends ConsumerState<_BulkClientPriceSheet> {
  final _percentController = TextEditingController(text: '10');
  final _fixedController = TextEditingController();
  _BulkClientPriceMode _mode = _BulkClientPriceMode.percent;
  bool _onlyEmpty = true;
  bool _isSaving = false;

  @override
  void dispose() {
    _percentController.dispose();
    _fixedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.86;
    final symbol = _currencySymbol(widget.purchase.currency);
    final eligible = _eligibleItems().length;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SafeArea(
        bottom: false,
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 58,
                height: 6,
                decoration: BoxDecoration(
                  color: const Color(0xFFE1E5ED),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: SpAnimatedHeroSurface(
                  padding: const EdgeInsets.all(16),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.calculate_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Цены клиента',
                              style: TextStyle(
                                color: Colors.white,
                                fontFamily: 'Gilroy',
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Массовый расчёт от цены выкупа',
                              style: TextStyle(
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
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(18, 0, 18, 18 + bottomInset),
                  children: [
                    SpInfoNotice(
                      title: 'На что влияет расчёт',
                      message:
                          'Будет заполнено поле «Цена клиента за 1 шт.» у выбранных товаров. Финансы и прибыль пересчитаются от новой цены клиента.',
                      icon: Icons.info_outline_rounded,
                    ),
                    const SizedBox(height: 12),
                    _BulkModeTile(
                      title: 'Без наценки',
                      subtitle: 'Цена клиента = цена выкупа',
                      icon: Icons.price_check_rounded,
                      selected: _mode == _BulkClientPriceMode.same,
                      onTap: () =>
                          setState(() => _mode = _BulkClientPriceMode.same),
                    ),
                    const SizedBox(height: 8),
                    _BulkModeTile(
                      title: 'Добавить процент',
                      subtitle: 'Например, цена выкупа +10%',
                      icon: Icons.percent_rounded,
                      selected: _mode == _BulkClientPriceMode.percent,
                      onTap: () =>
                          setState(() => _mode = _BulkClientPriceMode.percent),
                    ),
                    if (_mode == _BulkClientPriceMode.percent) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _percentController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: SpFinanceUi.inputDecoration(
                          context,
                          labelText: 'Наценка',
                          suffixText: '%',
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    _BulkModeTile(
                      title: 'Добавить фиксированно',
                      subtitle: 'Например, к каждому товару +20 $symbol',
                      icon: Icons.add_card_rounded,
                      selected: _mode == _BulkClientPriceMode.fixed,
                      onTap: () =>
                          setState(() => _mode = _BulkClientPriceMode.fixed),
                    ),
                    if (_mode == _BulkClientPriceMode.fixed) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _fixedController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: SpFinanceUi.inputDecoration(
                          context,
                          labelText: 'Фиксированная наценка',
                          suffixText: symbol,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _onlyEmpty,
                      activeThumbColor: context.brandPrimary,
                      onChanged: (value) => setState(() => _onlyEmpty = value),
                      title: const Text(
                        'Только пустые цены клиента',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontFamily: 'Gilroy',
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      subtitle: Text(
                        'Если выключить — пересчитаем все товары с ценой выкупа.',
                        style: SpFinanceUi.labelStyle,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _FinanceMiniMetric(
                      label: 'Будет обновлено',
                      value: '$eligible товаров',
                      warning: eligible == 0,
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
                    label: const Text('Проставить цены'),
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
            ],
          ),
        ),
      ),
    );
  }

  List<SpV2Item> _eligibleItems() {
    return widget.purchase.items
        .where((item) {
          final purchasePrice = item.purchasePriceForCurrency(
            widget.purchase.currency,
          );
          if (purchasePrice <= 0) return false;
          if (!_onlyEmpty) return true;
          return item.clientPriceForCurrency(widget.purchase.currency) <= 0;
        })
        .toList(growable: false);
  }

  double? _clientPriceFor(SpV2Item item) {
    final base = item.purchasePriceForCurrency(widget.purchase.currency);
    if (base <= 0) return null;
    final value = switch (_mode) {
      _BulkClientPriceMode.same => base,
      _BulkClientPriceMode.percent =>
        base * (1 + ((_readDecimalInput(_percentController.text) ?? 0) / 100)),
      _BulkClientPriceMode.fixed =>
        base + (_readDecimalInput(_fixedController.text) ?? 0),
    };
    return double.parse(value.clamp(0, double.infinity).toStringAsFixed(2));
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final items = _eligibleItems();
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нет товаров с ценой выкупа для обновления'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repository = ref.read(spV2RepositoryProvider);
      final canApplyAtomically =
          widget.atomicBulkEnabled &&
          items.every((item) => item.updatedAt != null);
      if (canApplyAtomically) {
        await repository.applyBulkItemUpdates(
          widget.purchase.id,
          operation: 'client_price',
          items: items
              .map((item) {
                final clientPrice = _clientPriceFor(item)!;
                return SpV2BulkItemUpdate(
                  id: item.id,
                  expectedUpdatedAt: item.updatedAt!,
                  clientPriceRub: widget.purchase.currency == 'RUB'
                      ? clientPrice
                      : null,
                  clientPriceYuan: widget.purchase.currency == 'RUB'
                      ? null
                      : clientPrice,
                  totalDueRub: _itemTotalRubWithClientPrice(
                    item,
                    widget.purchase,
                    clientPrice,
                  ),
                );
              })
              .toList(growable: false),
        );
      } else {
        throw StateError('atomic-bulk-unavailable');
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _spActionErrorMessage(
              context,
              error,
              action: 'массово проставить цены клиента',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

enum _BulkDeliveryMode { weight, items, units, customers }

class _BulkDeliverySheet extends ConsumerStatefulWidget {
  final SpV2Purchase purchase;
  final bool atomicBulkEnabled;

  const _BulkDeliverySheet({
    required this.purchase,
    required this.atomicBulkEnabled,
  });

  @override
  ConsumerState<_BulkDeliverySheet> createState() => _BulkDeliverySheetState();
}

class _BulkDeliverySheetState extends ConsumerState<_BulkDeliverySheet> {
  final _actualTotalController = TextEditingController();
  final _clientTotalController = TextEditingController();
  _BulkDeliveryMode _mode = _BulkDeliveryMode.customers;
  bool _onlyEmpty = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (_hasWeights) _mode = _BulkDeliveryMode.weight;
    _actualTotalController.addListener(_rebuildPreview);
    _clientTotalController.addListener(_rebuildPreview);
  }

  @override
  void dispose() {
    _actualTotalController.removeListener(_rebuildPreview);
    _clientTotalController.removeListener(_rebuildPreview);
    _actualTotalController.dispose();
    _clientTotalController.dispose();
    super.dispose();
  }

  bool get _hasWeights =>
      widget.purchase.items.any((item) => item.actualWeightKg > 0);

  void _rebuildPreview() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;
    final items = _targetItems();
    final actualTotal = _readDecimalInput(_actualTotalController.text) ?? 0;
    final clientTotal = _readDecimalInput(_clientTotalController.text) ?? 0;
    final actualMap = _allocate(actualTotal, items);
    final clientMap = _allocate(clientTotal, items);
    final margin = clientTotal - actualTotal;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SafeArea(
        bottom: false,
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 58,
                height: 6,
                decoration: BoxDecoration(
                  color: const Color(0xFFE1E5ED),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: SpAnimatedHeroSurface(
                  padding: const EdgeInsets.all(16),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.local_shipping_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Расчёт доставки',
                              style: TextStyle(
                                color: Colors.white,
                                fontFamily: 'Gilroy',
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Себестоимость СП и сумма для клиентов',
                              style: TextStyle(
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
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(18, 0, 18, 18 + bottomInset),
                  children: [
                    const SpInfoNotice(
                      title: 'Как это работает',
                      message:
                          '«Доставка оплачена СП» — ваша себестоимость. «Доставка клиенту» — сумма, которую платят клиенты. Разница попадёт в расчётную прибыль организатора.',
                      icon: Icons.info_outline_rounded,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _actualTotalController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: SpFinanceUi.inputDecoration(
                              context,
                              labelText: 'СП оплатил',
                              hintText: 'Себестоимость',
                              suffixText: '₽',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _clientTotalController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: SpFinanceUi.inputDecoration(
                              context,
                              labelText: 'Клиентам',
                              hintText: 'К оплате',
                              suffixText: '₽',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _BulkModeTile(
                      title: 'По весу товаров',
                      subtitle: _hasWeights
                          ? 'Чем больше фактический вес, тем больше доля'
                          : 'Сначала заполните фактический вес у товаров',
                      icon: Icons.scale_rounded,
                      selected: _mode == _BulkDeliveryMode.weight,
                      enabled: _hasWeights,
                      onTap: () =>
                          setState(() => _mode = _BulkDeliveryMode.weight),
                    ),
                    const SizedBox(height: 8),
                    _BulkModeTile(
                      title: 'Поровну по товарам',
                      subtitle: 'Каждая позиция получит одинаковую долю',
                      icon: Icons.inventory_2_rounded,
                      selected: _mode == _BulkDeliveryMode.items,
                      onTap: () =>
                          setState(() => _mode = _BulkDeliveryMode.items),
                    ),
                    const SizedBox(height: 8),
                    _BulkModeTile(
                      title: 'По количеству штук',
                      subtitle: 'Доля зависит от количества в товаре',
                      icon: Icons.tag_rounded,
                      selected: _mode == _BulkDeliveryMode.units,
                      onTap: () =>
                          setState(() => _mode = _BulkDeliveryMode.units),
                    ),
                    const SizedBox(height: 8),
                    _BulkModeTile(
                      title: 'Поровну по клиентам',
                      subtitle:
                          'Сначала делим между клиентами, потом внутри клиента по его товарам',
                      icon: Icons.groups_rounded,
                      selected: _mode == _BulkDeliveryMode.customers,
                      onTap: () =>
                          setState(() => _mode = _BulkDeliveryMode.customers),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _onlyEmpty,
                      activeThumbColor: context.brandPrimary,
                      onChanged: (value) => setState(() => _onlyEmpty = value),
                      title: const Text(
                        'Только пустые суммы доставки',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontFamily: 'Gilroy',
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      subtitle: Text(
                        'Если выключить — текущие суммы доставки будут пересчитаны.',
                        style: SpFinanceUi.labelStyle,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _FinanceMiniMetric(
                            label: 'Будет обновлено',
                            value: '${items.length} товаров',
                            warning: items.isEmpty,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _FinanceMiniMetric(
                            label: 'Доход на доставке',
                            value: _formatRub(margin),
                            positive: margin > 0,
                            warning: margin < 0,
                          ),
                        ),
                      ],
                    ),
                    if (items.isNotEmpty &&
                        (actualTotal > 0 || clientTotal > 0)) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Превью распределения',
                        style: SpFinanceUi.sectionTitleStyle.copyWith(
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...items
                          .take(5)
                          .map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _DeliveryPreviewTile(
                                item: item,
                                actualRub: actualMap[item.id] ?? 0,
                                clientRub: clientMap[item.id] ?? 0,
                              ),
                            ),
                          ),
                      if (items.length > 5)
                        Text(
                          'И ещё ${items.length - 5} товаров будут рассчитаны при сохранении.',
                          style: SpFinanceUi.labelStyle,
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
                    label: const Text('Проставить доставку'),
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
            ],
          ),
        ),
      ),
    );
  }

  List<SpV2Item> _targetItems() {
    return widget.purchase.items
        .where((item) {
          if (!_onlyEmpty) return true;
          return item.shippingCostRub <= 0 || item.shippingCostActualRub <= 0;
        })
        .toList(growable: false);
  }

  Map<int, double> _allocate(double total, List<SpV2Item> items) {
    if (total <= 0 || items.isEmpty) {
      return {for (final item in items) item.id: 0};
    }
    if (_mode == _BulkDeliveryMode.customers) {
      return _allocateByCustomers(total, items);
    }
    return _allocateByWeight(total, items, _weightForMode);
  }

  double _weightForMode(SpV2Item item) {
    return switch (_mode) {
      _BulkDeliveryMode.weight => item.actualWeightKg,
      _BulkDeliveryMode.units =>
        (item.quantity <= 0 ? 1 : item.quantity).toDouble(),
      _BulkDeliveryMode.items || _BulkDeliveryMode.customers => 1,
    };
  }

  Map<int, double> _allocateByCustomers(double total, List<SpV2Item> items) {
    final groups = <int, List<SpV2Item>>{};
    for (final item in items) {
      final key = item.customer?.id ?? -item.id;
      groups.putIfAbsent(key, () => <SpV2Item>[]).add(item);
    }
    final fakeGroupItems = groups.entries
        .map((entry) => _DeliveryGroupShare(entry.key))
        .toList(growable: false);
    final groupShares = _allocateShares(
      total,
      fakeGroupItems,
      (_) => 1,
      (group) => group.id,
    );

    final result = <int, double>{};
    for (final entry in groups.entries) {
      final groupItems = entry.value;
      final groupTotal = groupShares[entry.key] ?? 0;
      final hasGroupWeights = groupItems.any((item) => item.actualWeightKg > 0);
      result.addAll(
        _allocateByWeight(
          groupTotal,
          groupItems,
          hasGroupWeights ? (item) => item.actualWeightKg : (_) => 1,
        ),
      );
    }
    return result;
  }

  Map<int, double> _allocateByWeight(
    double total,
    List<SpV2Item> items,
    double Function(SpV2Item item) weightFor,
  ) {
    return _allocateShares(total, items, weightFor, (item) => item.id);
  }

  Map<int, double> _allocateShares<T>(
    double total,
    List<T> entries,
    double Function(T entry) weightFor,
    int Function(T entry) idFor,
  ) {
    if (entries.isEmpty) return {};
    final weights = entries.map((entry) => weightFor(entry)).toList();
    final totalWeight = weights.fold<double>(
      0,
      (sum, weight) => sum + (weight > 0 ? weight : 0),
    );
    final safeWeights = totalWeight > 0
        ? weights.map((weight) => weight > 0 ? weight : 0).toList()
        : List<double>.filled(entries.length, 1);
    final safeTotal = totalWeight > 0 ? totalWeight : entries.length.toDouble();
    final result = <int, double>{};
    var distributed = 0.0;
    for (var index = 0; index < entries.length; index += 1) {
      final id = idFor(entries[index]);
      final value = index == entries.length - 1
          ? total - distributed
          : total * safeWeights[index] / safeTotal;
      final rounded = double.parse(value.toStringAsFixed(2));
      result[id] = rounded < 0 ? 0 : rounded;
      distributed += result[id] ?? 0;
    }
    return result;
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final items = _targetItems();
    final actualTotal = _readDecimalInput(_actualTotalController.text) ?? 0;
    final clientTotal = _readDecimalInput(_clientTotalController.text) ?? 0;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет товаров для обновления доставки')),
      );
      return;
    }
    if (actualTotal <= 0 && clientTotal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите хотя бы одну сумму доставки')),
      );
      return;
    }
    if (_mode == _BulkDeliveryMode.weight && !_hasWeights) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Для распределения по весу заполните вес товаров'),
        ),
      );
      return;
    }

    final actualMap = _allocate(actualTotal, items);
    final clientMap = _allocate(clientTotal, items);

    setState(() => _isSaving = true);
    try {
      final repository = ref.read(spV2RepositoryProvider);
      double actualFor(SpV2Item item) =>
          _onlyEmpty && item.shippingCostActualRub > 0
          ? item.shippingCostActualRub
          : actualMap[item.id] ?? 0;
      double clientFor(SpV2Item item) => _onlyEmpty && item.shippingCostRub > 0
          ? item.shippingCostRub
          : clientMap[item.id] ?? 0;
      final canApplyAtomically =
          widget.atomicBulkEnabled &&
          items.every((item) => item.updatedAt != null);
      if (canApplyAtomically) {
        await repository.applyBulkItemUpdates(
          widget.purchase.id,
          operation: 'delivery',
          items: items
              .map((item) {
                final clientRub = clientFor(item);
                return SpV2BulkItemUpdate(
                  id: item.id,
                  expectedUpdatedAt: item.updatedAt!,
                  shippingCostActualRub: actualFor(item),
                  shippingCostRub: clientRub,
                  totalDueRub:
                      _itemBaseRub(item, widget.purchase) +
                      clientRub +
                      item.additionalExpensesRub,
                );
              })
              .toList(growable: false),
        );
      } else {
        throw StateError('atomic-bulk-unavailable');
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _spActionErrorMessage(
              context,
              error,
              action: 'массово рассчитать доставку',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _DeliveryGroupShare {
  final int id;

  const _DeliveryGroupShare(this.id);
}

class _DeliveryPreviewTile extends StatelessWidget {
  final SpV2Item item;
  final double actualRub;
  final double clientRub;

  const _DeliveryPreviewTile({
    required this.item,
    required this.actualRub,
    required this.clientRub,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: SpFinanceUi.softDecoration(context),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: context.brandPrimary.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.inventory_2_rounded,
              color: context.brandPrimary,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SpFinanceUi.sectionTitleStyle.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  item.customer?.fullName ?? 'Клиент не указан',
                  maxLines: 1,
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
                'СП ${_formatRub(actualRub)}',
                style: SpFinanceUi.labelStyle,
              ),
              const SizedBox(height: 2),
              Text(
                'Клиент ${_formatRub(clientRub)}',
                style: TextStyle(
                  color: context.brandPrimary,
                  fontFamily: 'Gilroy',
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BulkModeTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  const _BulkModeTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: !enabled
          ? const Color(0xFFF8FAFC).withValues(alpha: 0.58)
          : selected
          ? context.brandPrimary.withValues(alpha: 0.09)
          : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? context.brandPrimary.withValues(alpha: 0.35)
                  : !enabled
                  ? Colors.black.withValues(alpha: 0.02)
                  : Colors.black.withValues(alpha: 0.035),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: selected
                      ? context.brandPrimary.withValues(alpha: 0.14)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: selected
                      ? context.brandPrimary
                      : !enabled
                      ? AppColors.textSecondary.withValues(alpha: 0.35)
                      : AppColors.textSecondary,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: SpFinanceUi.sectionTitleStyle.copyWith(
                        fontSize: 15,
                        color: enabled
                            ? AppColors.textPrimary
                            : AppColors.textSecondary.withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: SpFinanceUi.labelStyle),
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
                    : !enabled
                    ? AppColors.textSecondary.withValues(alpha: 0.35)
                    : AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final SpV2Item item;
  final SpV2Purchase purchase;
  final VoidCallback onTap;
  final VoidCallback? onTogglePurchased;
  final VoidCallback? onToggleGoodsPaid;
  final VoidCallback? onToggleDeliveryPaid;
  final bool showClientPrice;
  final bool showFinance;
  final bool showDelivery;

  const _ItemCard({
    required this.item,
    required this.purchase,
    required this.onTap,
    this.onTogglePurchased,
    this.onToggleGoodsPaid,
    this.onToggleDeliveryPaid,
    this.showClientPrice = true,
    this.showFinance = true,
    this.showDelivery = true,
  });

  @override
  Widget build(BuildContext context) {
    final currency = purchase.currency;
    final priceSymbol = currency == 'RUB' ? '₽' : '¥';
    final clientPrice = item.clientPriceForCurrency(currency);
    final purchasePrice = item.purchasePriceForCurrency(currency);
    final quantity = item.quantity <= 0 ? 1 : item.quantity;
    final goodsTotalRub = _itemBaseRub(item, purchase);
    final profitRub = _itemProfitRub(item, purchase);
    final clientPriceLabel = clientPrice > 0
        ? '$priceSymbol${clientPrice.toStringAsFixed(currency == 'RUB' ? 0 : 2)}'
        : 'Цена не указана';
    final purchasePriceLabel = purchasePrice > 0
        ? '$priceSymbol${purchasePrice.toStringAsFixed(currency == 'RUB' ? 0 : 2)}'
        : null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: SpFinanceUi.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ItemPreviewImage(item: item),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontFamily: 'Gilroy',
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            height: 1.08,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.customer?.fullName ?? 'Клиент не указан',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontFamily: 'Gilroy',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _SoftStatusPill(
                    label: isZh(context)
                        ? spStatusText(context, item.status)
                        : item.statusLabel,
                  ),
                  _ItemMiniBadge(
                    icon: Icons.inventory_2_rounded,
                    label: '$quantity шт.',
                  ),
                  if (item.sourceUrl?.trim().isNotEmpty == true)
                    _ItemMiniBadge(
                      icon: Icons.link_rounded,
                      label: _externalLinkHostLabel(item.sourceUrl!),
                      onTap: () => _openExternalLink(context, item.sourceUrl!),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (item.media.isNotEmpty) ...[
                _ItemMediaStrip(media: item.media),
                const SizedBox(height: 12),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (purchasePriceLabel != null)
                    _InfoChip(
                      icon: currency == 'RUB'
                          ? Icons.currency_ruble_rounded
                          : Icons.currency_yuan_rounded,
                      label:
                          'Выкуп: $purchasePriceLabel${quantity > 1 ? ' × $quantity' : ''}',
                    ),
                  if (showClientPrice)
                    _InfoChip(
                      icon: Icons.sell_rounded,
                      label:
                          'Клиент: $clientPriceLabel${quantity > 1 ? ' × $quantity' : ''}',
                    ),
                  if (showFinance && goodsTotalRub > 0)
                    _InfoChip(
                      icon: Icons.functions_rounded,
                      label: 'Товар всего: ${_formatRub(goodsTotalRub)}',
                    ),
                  if (item.shippingCostActualRub > 0)
                    _InfoChip(
                      icon: Icons.receipt_long_rounded,
                      label:
                          'Доставка СП: ${_formatRub(item.shippingCostActualRub)}',
                    ),
                  if (showDelivery && item.shippingCostRub > 0)
                    _InfoChip(
                      icon: Icons.local_shipping_rounded,
                      label:
                          'Доставка клиенту: ${_formatRub(item.shippingCostRub)}',
                    ),
                  if (showFinance && profitRub != 0)
                    _InfoChip(
                      icon: Icons.trending_up_rounded,
                      label: 'Доход: ${_formatRub(profitRub)}',
                    ),
                  if (item.tracks.isNotEmpty)
                    _InfoChip(
                      icon: Icons.local_shipping_rounded,
                      label: '${item.tracks.length} трек',
                    ),
                ],
              ),
              if (item.sourceUrl?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 12),
                _ItemSourceLinkButton(url: item.sourceUrl!),
              ],
              if (item.description != null || item.sellerInfo != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: SpFinanceUi.softDecoration(context),
                  child: Text(
                    item.description ?? item.sellerInfo!,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontFamily: 'Gilroy',
                      fontSize: 13,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              if (onTogglePurchased != null ||
                  onToggleGoodsPaid != null ||
                  onToggleDeliveryPaid != null) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (onTogglePurchased != null)
                      _ItemQuickAction(
                        icon: Icons.shopping_cart_checkout_rounded,
                        label: item.isPurchased ? 'Выкуплен' : 'Отметить выкуп',
                        selected: item.isPurchased,
                        onTap: onTogglePurchased!,
                      ),
                    if (showFinance && onToggleGoodsPaid != null)
                      _ItemQuickAction(
                        icon: Icons.payments_rounded,
                        label: item.isGoodsPaid
                            ? 'Товар оплачен'
                            : 'Оплатили товар',
                        selected: item.isGoodsPaid,
                        onTap: onToggleGoodsPaid!,
                      ),
                    if (showFinance &&
                        showDelivery &&
                        onToggleDeliveryPaid != null)
                      _ItemQuickAction(
                        icon: Icons.local_shipping_rounded,
                        label: item.isDeliveryPaid
                            ? 'Доставка оплачена'
                            : 'Оплатили доставку',
                        selected: item.isDeliveryPaid,
                        onTap: onToggleDeliveryPaid!,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemPreviewImage extends StatelessWidget {
  final SpV2Item item;

  const _ItemPreviewImage({required this.item});

  @override
  Widget build(BuildContext context) {
    final firstMedia = item.media.isNotEmpty ? item.media.first : null;
    if (firstMedia == null || firstMedia.url.trim().isEmpty) {
      return Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: context.brandPrimary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(Icons.shopping_bag_rounded, color: context.brandPrimary),
      );
    }

    final previewUrl = ApiConfig.getMediaUrl(
      (firstMedia.thumbnailUrl?.trim().isNotEmpty == true
              ? firstMedia.thumbnailUrl
              : firstMedia.url)!
          .trim(),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openSpMediaGallery(context, item.media),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: 54,
              height: 54,
              child: AppCachedMediaImage(
                url: previewUrl,
                fit: BoxFit.cover,
                memCacheWidth: 180,
                memCacheHeight: 180,
              ),
            ),
          ),
          if (item.media.length > 1)
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: context.brandPrimary,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Text(
                  '+${item.media.length - 1}',
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
    );
  }
}

class _ItemMiniBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ItemMiniBadge({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: context.brandPrimary.withValues(
          alpha: onTap == null ? 0.08 : 0.12,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: context.brandPrimary.withValues(
            alpha: onTap == null ? 0.12 : 0.20,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: context.brandPrimary, size: 13),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.brandPrimary,
                fontFamily: 'Gilroy',
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: content,
      ),
    );
  }
}

class _ItemSourceLinkButton extends StatelessWidget {
  final String url;

  const _ItemSourceLinkButton({required this.url});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.brandPrimary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => _openExternalLink(context, url),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(Icons.link_rounded, color: context.brandPrimary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Открыть ссылку на товар',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Gilroy',
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _externalLinkHostLabel(url),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontFamily: 'Gilroy',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.open_in_new_rounded,
                color: context.brandPrimary,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemMediaStrip extends StatelessWidget {
  final List<SpV2Media> media;

  const _ItemMediaStrip({required this.media});

  @override
  Widget build(BuildContext context) {
    final photos = _spMediaPhotos(media);
    if (photos.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final photo = photos[index];
          return GestureDetector(
            onTap: () =>
                _openSpMediaGallery(context, media, initialIndex: index),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: 92,
                height: 74,
                child: AppCachedMediaImage(
                  url: photo.url,
                  fit: BoxFit.cover,
                  memCacheWidth: 220,
                  memCacheHeight: 180,
                ),
              ),
            ),
          );
        },
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemCount: photos.length,
      ),
    );
  }
}

class _CustomersTab extends StatelessWidget {
  final SpV2Purchase purchase;
  final void Function(SpV2Purchase purchase, SpV2Customer customer)
  onCustomerTap;
  final void Function(SpV2Purchase purchase, SpV2Customer customer)
  onToggleCustomerGoodsPaid;
  final void Function(SpV2Purchase purchase, SpV2Customer customer)
  onToggleCustomerDeliveryPaid;
  final void Function(SpV2Purchase purchase, SpV2Customer customer)
  onToggleCustomerExtraPaid;

  const _CustomersTab({
    required this.purchase,
    required this.onCustomerTap,
    required this.onToggleCustomerGoodsPaid,
    required this.onToggleCustomerDeliveryPaid,
    required this.onToggleCustomerExtraPaid,
  });

  @override
  Widget build(BuildContext context) {
    final customers = <int, SpV2Customer>{};
    final clientSections = purchase.clientCardSections;
    for (final item in purchase.items) {
      final customer = item.customer;
      if (customer != null) customers[customer.id] = customer;
    }

    if (customers.isEmpty) {
      return const _TabEmptyCard(
        icon: Icons.people_outline_rounded,
        title: 'Клиентов пока нет',
        message: 'Клиент появится здесь, когда вы добавите первый товар в СП.',
      );
    }

    final finance = _PurchaseFinance.fromPurchase(purchase);

    return Column(
      children: customers.values
          .map((customer) {
            final itemCount = purchase.items
                .where((item) => item.customer?.id == customer.id)
                .length;
            final customerItems = purchase.items
                .where((item) => item.customer?.id == customer.id)
                .toList(growable: false);
            final allGoodsPaid =
                customerItems.isNotEmpty &&
                customerItems.every((item) => item.isGoodsPaid);
            final allDeliveryPaid =
                customerItems.isNotEmpty &&
                customerItems.every((item) => item.isDeliveryPaid);
            final customerFinance = finance.forCustomer(customer.id);
            final hasExtraDue = (customerFinance?.extraDueRub ?? 0) > 0;
            final allExtraPaid = customerFinance?.allExtraPaid ?? false;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onCustomerTap(purchase, customer),
                  borderRadius: BorderRadius.circular(24),
                  child: Ink(
                    padding: const EdgeInsets.all(16),
                    decoration: SpFinanceUi.cardDecoration(),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: context.brandPrimary.withValues(
                                  alpha: 0.10,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                Icons.person_rounded,
                                color: context.brandPrimary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    customer.fullName,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontFamily: 'Gilroy',
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    [
                                              customer.phone,
                                              customer.telegram,
                                              customer.wechat,
                                            ]
                                            .whereType<String>()
                                            .join(' · ')
                                            .isEmpty
                                        ? '$itemCount товаров'
                                        : '${[customer.phone, customer.telegram, customer.wechat].whereType<String>().join(' · ')} · $itemCount товаров',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontFamily: 'Gilroy',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: AppColors.textSecondary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _CustomerContactActions(
                          customer: customer,
                          compact: true,
                        ),
                        if (clientSections.showFinance) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _CustomerPayButton(
                                  label: allGoodsPaid
                                      ? 'Товар оплачен'
                                      : 'Оплатить товар',
                                  selected: allGoodsPaid,
                                  onTap: () => onToggleCustomerGoodsPaid(
                                    purchase,
                                    customer,
                                  ),
                                ),
                              ),
                              if (clientSections.showDelivery) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _CustomerPayButton(
                                    label: allDeliveryPaid
                                        ? 'Доставка оплачена'
                                        : 'Оплатить доставку',
                                    selected: allDeliveryPaid,
                                    onTap: () => onToggleCustomerDeliveryPaid(
                                      purchase,
                                      customer,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                        if (clientSections.showFinance && hasExtraDue) ...[
                          const SizedBox(height: 8),
                          _CustomerPayButton(
                            label: allExtraPaid
                                ? 'Доп. расходы оплачены'
                                : 'Оплатить доп. расходы',
                            selected: allExtraPaid,
                            onTap: () =>
                                onToggleCustomerExtraPaid(purchase, customer),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _CustomerDetailSheet extends StatelessWidget {
  final SpV2Purchase purchase;
  final SpV2Customer customer;
  final void Function(SpV2Purchase purchase, SpV2Customer customer)
  onToggleGoodsPaid;
  final void Function(SpV2Purchase purchase, SpV2Customer customer)
  onToggleDeliveryPaid;
  final void Function(SpV2Purchase purchase, SpV2Customer customer)
  onToggleExtraPaid;
  final Future<void> Function(SpV2Customer customer) onEditCustomer;
  final Future<void> Function(SpV2Purchase purchase, SpV2Customer customer)
  onEditShipment;

  const _CustomerDetailSheet({
    required this.purchase,
    required this.customer,
    required this.onToggleGoodsPaid,
    required this.onToggleDeliveryPaid,
    required this.onToggleExtraPaid,
    required this.onEditCustomer,
    required this.onEditShipment,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;
    final items = purchase.items
        .where((item) => item.customer?.id == customer.id)
        .toList(growable: false);
    final customerFinance = _PurchaseFinance.fromPurchase(
      purchase,
    ).forCustomer(customer.id);
    final totalDue =
        customerFinance?.totalDueRub ??
        items.fold<double>(
          0,
          (sum, item) => sum + _itemTotalRub(item, purchase),
        );
    final totalWeight = items.fold<double>(
      0,
      (sum, item) => sum + item.actualWeightKg,
    );
    final allGoodsPaid =
        items.isNotEmpty && items.every((item) => item.isGoodsPaid);
    final allDeliveryPaid =
        items.isNotEmpty && items.every((item) => item.isDeliveryPaid);
    final hasExtraDue = (customerFinance?.extraDueRub ?? 0) > 0;
    final allExtraPaid = customerFinance?.allExtraPaid ?? false;
    final clientSections = purchase.clientCardSections;
    SpV2CustomerShipment? shipment;
    for (final entry in purchase.shipments) {
      if (entry.spCustomerId == customer.id) {
        shipment = entry;
        break;
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SafeArea(
        bottom: false,
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 58,
                height: 6,
                decoration: BoxDecoration(
                  color: const Color(0xFFE1E5ED),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: SpAnimatedHeroSurface(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(19),
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customer.fullName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'Gilroy',
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              [
                                customer.phone,
                                customer.telegram,
                                customer.wechat,
                              ].whereType<String>().join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(18, 0, 18, 18 + bottomInset),
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoChip(
                          icon: Icons.shopping_bag_rounded,
                          label: '${items.length} товаров',
                        ),
                        _InfoChip(
                          icon: Icons.monitor_weight_rounded,
                          label: totalWeight > 0
                              ? '${totalWeight.toStringAsFixed(2)} кг'
                              : 'Вес не задан',
                        ),
                        if (clientSections.showFinance)
                          _InfoChip(
                            icon: Icons.payments_rounded,
                            label: 'Итого ${_formatRub(totalDue)}',
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _CustomerContactActions(
                      customer: customer,
                      onEdit: () async {
                        Navigator.of(context).pop();
                        await onEditCustomer(customer);
                      },
                    ),
                    if (clientSections.showTariff) ...[
                      const SizedBox(height: 12),
                      _ClientTariffSummaryTile(purchase: purchase),
                    ],
                    if (clientSections.showDelivery) ...[
                      const SizedBox(height: 12),
                      _ShipmentSummaryTile(
                        shipment: shipment,
                        onTap: () async {
                          Navigator.of(context).pop();
                          await onEditShipment(purchase, customer);
                        },
                      ),
                    ],
                    if (clientSections.showFinance) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _CustomerPayButton(
                              label: allGoodsPaid
                                  ? 'Товары оплачены'
                                  : 'Отметить товары',
                              selected: allGoodsPaid,
                              onTap: () =>
                                  onToggleGoodsPaid(purchase, customer),
                            ),
                          ),
                          if (clientSections.showDelivery) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: _CustomerPayButton(
                                label: allDeliveryPaid
                                    ? 'Доставка оплачена'
                                    : 'Отметить доставку',
                                selected: allDeliveryPaid,
                                onTap: () =>
                                    onToggleDeliveryPaid(purchase, customer),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                    if (clientSections.showFinance && hasExtraDue) ...[
                      const SizedBox(height: 8),
                      _CustomerPayButton(
                        label: allExtraPaid
                            ? 'Доп. расходы оплачены'
                            : 'Отметить доп. расходы',
                        selected: allExtraPaid,
                        onTap: () => onToggleExtraPaid(purchase, customer),
                      ),
                    ],
                    if ((clientSections.showDelivery &&
                            (customer.deliveryAddress?.isNotEmpty == true ||
                                customer.city?.isNotEmpty == true)) ||
                        customer.comment?.isNotEmpty == true) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: SpFinanceUi.softDecoration(context),
                        child: Text(
                          [
                            if (clientSections.showDelivery &&
                                customer.city?.isNotEmpty == true)
                              'Город: ${customer.city}',
                            if (clientSections.showDelivery &&
                                customer.deliveryAddress?.isNotEmpty == true)
                              'Адрес: ${customer.deliveryAddress}',
                            if (customer.comment?.isNotEmpty == true)
                              'Комментарий: ${customer.comment}',
                          ].join('\n'),
                          style: SpFinanceUi.bodyStyle,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Товары клиента',
                      style: SpFinanceUi.sectionTitleStyle,
                    ),
                    const SizedBox(height: 10),
                    if (items.isEmpty)
                      const _TabEmptyCard(
                        icon: Icons.shopping_bag_outlined,
                        title: 'Товаров нет',
                        message:
                            'У этого клиента пока нет товаров в текущей СП.',
                      )
                    else
                      ...items.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ItemCard(
                            item: item,
                            purchase: purchase,
                            onTap: () {},
                            showClientPrice: clientSections.showCustomPrice,
                            showFinance: clientSections.showFinance,
                            showDelivery: clientSections.showDelivery,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: bottomSafe),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditCustomerSheet extends ConsumerStatefulWidget {
  final SpV2Customer customer;

  const _EditCustomerSheet({required this.customer});

  @override
  ConsumerState<_EditCustomerSheet> createState() => _EditCustomerSheetState();
}

class _EditCustomerSheetState extends ConsumerState<_EditCustomerSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _telegramController;
  late final TextEditingController _whatsappController;
  late final TextEditingController _wechatController;
  late final TextEditingController _vkController;
  late final TextEditingController _maxController;
  late final TextEditingController _cityController;
  late final TextEditingController _addressController;
  late final TextEditingController _commentController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final customer = widget.customer;
    _nameController = TextEditingController(text: customer.fullName);
    _phoneController = TextEditingController(text: customer.phone ?? '');
    _emailController = TextEditingController(text: customer.email ?? '');
    _telegramController = TextEditingController(text: customer.telegram ?? '');
    _whatsappController = TextEditingController(text: customer.whatsapp ?? '');
    _wechatController = TextEditingController(text: customer.wechat ?? '');
    _vkController = TextEditingController(text: customer.vk ?? '');
    _maxController = TextEditingController(text: customer.max ?? '');
    _cityController = TextEditingController(text: customer.city ?? '');
    _addressController = TextEditingController(
      text: customer.deliveryAddress ?? '',
    );
    _commentController = TextEditingController(text: customer.comment ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _telegramController.dispose();
    _whatsappController.dispose();
    _wechatController.dispose();
    _vkController.dispose();
    _maxController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Введите имя клиента')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(spV2RepositoryProvider)
          .updateCustomer(
            widget.customer.id,
            fullName: name,
            phone: _optional(_phoneController),
            email: _optional(_emailController),
            telegram: _optional(_telegramController),
            whatsapp: _optional(_whatsappController),
            wechat: _optional(_wechatController),
            vk: _optional(_vkController),
            max: _optional(_maxController),
            city: _optional(_cityController),
            deliveryAddress: _optional(_addressController),
            comment: _optional(_commentController),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить клиента: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.90;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SafeArea(
        bottom: false,
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 58,
                height: 6,
                decoration: BoxDecoration(
                  color: const Color(0xFFE1E5ED),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: SpAnimatedHeroSurface(
                  padding: const EdgeInsets.all(16),
                  child: const Row(
                    children: [
                      Icon(Icons.edit_rounded, color: Colors.white, size: 34),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Клиент СП',
                              style: TextStyle(
                                color: Colors.white,
                                fontFamily: 'Gilroy',
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Контакты, мессенджеры и адрес доставки.',
                              style: TextStyle(
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
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(18, 0, 18, 18 + bottomInset),
                  children: [
                    TextField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      decoration: SpFinanceUi.inputDecoration(
                        context,
                        labelText: 'ФИО / имя клиента',
                        prefixIcon: Icons.person_rounded,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: SpFinanceUi.inputDecoration(
                        context,
                        labelText: 'Телефон',
                        prefixIcon: Icons.call_rounded,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: SpFinanceUi.inputDecoration(
                        context,
                        labelText: 'Email',
                        prefixIcon: Icons.mail_rounded,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _telegramController,
                      textInputAction: TextInputAction.next,
                      decoration: SpFinanceUi.inputDecoration(
                        context,
                        labelText: 'Telegram / ник',
                        prefixIcon: Icons.send_rounded,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _whatsappController,
                            textInputAction: TextInputAction.next,
                            decoration: SpFinanceUi.inputDecoration(
                              context,
                              labelText: 'WhatsApp',
                              prefixIcon: Icons.chat_bubble_rounded,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _wechatController,
                            textInputAction: TextInputAction.next,
                            decoration: SpFinanceUi.inputDecoration(
                              context,
                              labelText: 'WeChat',
                              prefixIcon: Icons.forum_rounded,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _vkController,
                            textInputAction: TextInputAction.next,
                            decoration: SpFinanceUi.inputDecoration(
                              context,
                              labelText: 'VK',
                              prefixIcon: Icons.alternate_email_rounded,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _maxController,
                            textInputAction: TextInputAction.next,
                            decoration: SpFinanceUi.inputDecoration(
                              context,
                              labelText: 'MAX',
                              prefixIcon: Icons.forum_rounded,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _cityController,
                      textInputAction: TextInputAction.next,
                      decoration: SpFinanceUi.inputDecoration(
                        context,
                        labelText: 'Город',
                        prefixIcon: Icons.location_city_rounded,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _addressController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: SpFinanceUi.inputDecoration(
                        context,
                        labelText: 'Адрес доставки',
                        prefixIcon: Icons.location_on_rounded,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _commentController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: SpFinanceUi.inputDecoration(
                        context,
                        labelText: 'Комментарий',
                        prefixIcon: Icons.notes_rounded,
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
                child: _ActionButton(
                  icon: Icons.save_rounded,
                  label: _saving ? 'Сохраняем...' : 'Сохранить клиента',
                  onTap: _saving ? () {} : _save,
                  filled: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClientTariffSummaryTile extends StatelessWidget {
  final SpV2Purchase purchase;

  const _ClientTariffSummaryTile({required this.purchase});

  @override
  Widget build(BuildContext context) {
    final isCny = purchase.currency == 'CNY';
    final hasRate = purchase.purchaseRate > 0;
    final subtitle = isCny
        ? hasRate
              ? 'Курс СП: ${purchase.purchaseRate.toStringAsFixed(2)} ₽ за ¥'
              : 'Курс юаня пока не указан'
        : 'Расчёт закупки ведётся сразу в рублях';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: SpFinanceUi.softDecoration(context),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: context.brandPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.calculate_rounded,
              color: context.brandPrimary,
              size: 21,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Тариф и расчёт',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'Gilroy',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShipmentSummaryTile extends StatelessWidget {
  final SpV2CustomerShipment? shipment;
  final VoidCallback onTap;

  const _ShipmentSummaryTile({required this.shipment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = shipment?.status ?? 'draft';
    final hasData = shipment != null;
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
          ),
          child: Row(
            children: [
              Icon(Icons.local_shipping_rounded, color: context.brandPrimary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Отправка клиенту',
                      style: SpFinanceUi.sectionTitleStyle.copyWith(
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasData
                          ? [
                                  SpV2ShipmentStatusInfo.labelFor(status),
                                  shipment?.carrierName,
                                  shipment?.trackingNumber,
                                ]
                                .whereType<String>()
                                .where((v) => v.isNotEmpty)
                                .join(' · ')
                          : 'ТК, трек отправки и стоимость можно заполнить позже',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SpFinanceUi.labelStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: context.brandPrimary),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditShipmentSheet extends ConsumerStatefulWidget {
  final SpV2Purchase purchase;
  final SpV2Customer customer;
  final SpV2CustomerShipment? shipment;

  const _EditShipmentSheet({
    required this.purchase,
    required this.customer,
    this.shipment,
  });

  @override
  ConsumerState<_EditShipmentSheet> createState() => _EditShipmentSheetState();
}

class _EditShipmentSheetState extends ConsumerState<_EditShipmentSheet> {
  late String _status;
  late final TextEditingController _carrierController;
  late final TextEditingController _trackingController;
  late final TextEditingController _costController;
  late final TextEditingController _commentController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final shipment = widget.shipment;
    _status = shipment?.status ?? 'draft';
    _carrierController = TextEditingController(
      text: shipment?.carrierName ?? '',
    );
    _trackingController = TextEditingController(
      text: shipment?.trackingNumber ?? '',
    );
    _costController = TextEditingController(
      text: shipment != null && shipment.costRub > 0
          ? shipment.costRub.toStringAsFixed(2)
          : '',
    );
    _commentController = TextEditingController(text: shipment?.comment ?? '');
  }

  @override
  void dispose() {
    _carrierController.dispose();
    _trackingController.dispose();
    _costController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  double? _readCost() {
    final value = _costController.text.trim();
    if (value.isEmpty) return null;
    return double.tryParse(value.replaceAll(',', '.'));
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(spV2RepositoryProvider)
          .upsertShipment(
            widget.purchase.id,
            customerId: widget.customer.id,
            status: _status,
            carrierName: _optional(_carrierController),
            trackingNumber: _optional(_trackingController),
            costRub: _readCost(),
            comment: _optional(_commentController),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить отправку: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.86;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SafeArea(
        bottom: false,
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 58,
                height: 6,
                decoration: BoxDecoration(
                  color: const Color(0xFFE1E5ED),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: SpAnimatedHeroSurface(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.local_shipping_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Отправка ${widget.customer.fullName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'Gilroy',
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Транспортная компания, трек и расходы на отправку.',
                              style: TextStyle(
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
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(18, 0, 18, 18 + bottomInset),
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: SpV2ShipmentStatusInfo.all
                          .map((status) {
                            final selected = status.code == _status;
                            return ChoiceChip(
                              label: Text(commerceText(context, status.label)),
                              selected: selected,
                              onSelected: (_) =>
                                  setState(() => _status = status.code),
                              selectedColor: context.brandPrimary.withValues(
                                alpha: 0.15,
                              ),
                              backgroundColor: const Color(0xFFF8FAFC),
                              side: BorderSide(
                                color: selected
                                    ? context.brandPrimary.withValues(
                                        alpha: 0.25,
                                      )
                                    : Colors.black.withValues(alpha: 0.04),
                              ),
                              labelStyle: TextStyle(
                                color: selected
                                    ? context.brandPrimary
                                    : AppColors.textSecondary,
                                fontFamily: 'Gilroy',
                                fontWeight: FontWeight.w800,
                              ),
                            );
                          })
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _carrierController,
                      textInputAction: TextInputAction.next,
                      decoration: SpFinanceUi.inputDecoration(
                        context,
                        labelText: 'Транспортная компания',
                        hintText: 'СДЭК, Почта, Boxberry...',
                        prefixIcon: Icons.local_shipping_rounded,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _trackingController,
                      textInputAction: TextInputAction.next,
                      decoration: SpFinanceUi.inputDecoration(
                        context,
                        labelText: 'Трек отправки клиенту',
                        prefixIcon: Icons.numbers_rounded,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _costController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.next,
                      decoration: SpFinanceUi.inputDecoration(
                        context,
                        labelText: 'Стоимость отправки',
                        suffixText: '₽',
                        prefixIcon: Icons.payments_rounded,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _commentController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: SpFinanceUi.inputDecoration(
                        context,
                        labelText: 'Комментарий',
                        prefixIcon: Icons.notes_rounded,
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
                child: _ActionButton(
                  icon: Icons.save_rounded,
                  label: _saving ? 'Сохраняем...' : 'Сохранить отправку',
                  onTap: _saving ? () {} : _save,
                  filled: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerPayButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CustomerPayButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF16A34A) : context.brandPrimary;
    return Material(
      color: color.withValues(alpha: selected ? 0.12 : 0.08),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: SizedBox(
          height: 42,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontFamily: 'Gilroy',
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FinanceTab extends StatelessWidget {
  final SpV2Purchase purchase;
  final void Function(SpV2Purchase purchase, SpV2Customer customer)
  onToggleCustomerGoodsPaid;
  final void Function(SpV2Purchase purchase, SpV2Customer customer)
  onToggleCustomerDeliveryPaid;
  final void Function(SpV2Purchase purchase, SpV2Customer customer)
  onToggleCustomerExtraPaid;
  final void Function(SpV2Purchase purchase) onAddExpense;
  final void Function(SpV2Purchase purchase) onBulkDelivery;

  const _FinanceTab({
    super.key,
    required this.purchase,
    required this.onToggleCustomerGoodsPaid,
    required this.onToggleCustomerDeliveryPaid,
    required this.onToggleCustomerExtraPaid,
    required this.onAddExpense,
    required this.onBulkDelivery,
  });

  @override
  Widget build(BuildContext context) {
    final finance = _PurchaseFinance.fromPurchase(purchase);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SpInfoNotice(
          title: 'Как читать финансы',
          message: purchase.currency == 'CNY'
              ? 'Цены товаров вводятся в юанях, но долги, оплаты и прибыль показываются в рублях по курсу СП. Товары, доставка и доп. расходы отмечаются как оплаченные отдельно.'
              : 'Цены товаров вводятся в рублях. Товары, доставка и доп. расходы отмечаются как оплаченные отдельно, чтобы было видно кто что уже оплатил.',
          icon: Icons.help_outline_rounded,
        ),
        const SizedBox(height: 12),
        _BulkDeliveryActionCard(
          purchase: purchase,
          onTap: () => onBulkDelivery(purchase),
        ),
        const SizedBox(height: 12),
        _FinanceSummaryCard(
          title: 'Товары',
          subtitle: 'Сумма за сами позиции клиентов',
          icon: Icons.shopping_bag_rounded,
          dueRub: finance.goodsDueRub,
          paidRub: finance.goodsPaidRub,
        ),
        const SizedBox(height: 12),
        _FinanceSummaryCard(
          title: 'Доставка',
          subtitle: 'Доставка из Китая и распределённые суммы по товарам',
          icon: Icons.local_shipping_rounded,
          dueRub: finance.deliveryDueRub,
          paidRub: finance.deliveryPaidRub,
        ),
        if (finance.extraDueRub > 0 || finance.extraPaidRub > 0) ...[
          const SizedBox(height: 12),
          _FinanceSummaryCard(
            title: 'Доп. расходы',
            subtitle: 'Расходы, которые добавлены сверх товара и доставки',
            icon: Icons.receipt_long_rounded,
            dueRub: finance.extraDueRub,
            paidRub: finance.extraPaidRub,
          ),
        ],
        const SizedBox(height: 12),
        _FinanceTotalCard(finance: finance),
        const SizedBox(height: 16),
        _ExpensesCard(
          expenses: finance.globalExpenses,
          onAddExpense: () => onAddExpense(purchase),
        ),
        const SizedBox(height: 16),
        Text('Оплаты по клиентам', style: SpFinanceUi.sectionTitleStyle),
        const SizedBox(height: 10),
        if (finance.customers.isEmpty)
          const _TabEmptyCard(
            icon: Icons.people_outline_rounded,
            title: 'Клиентов пока нет',
            message:
                'Добавьте товары клиентов, чтобы видеть финансы по каждому участнику СП.',
          )
        else
          ...finance.customers.map(
            (customerFinance) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _CustomerFinanceCard(
                finance: customerFinance,
                onToggleGoodsPaid: () => onToggleCustomerGoodsPaid(
                  purchase,
                  customerFinance.customer,
                ),
                onToggleDeliveryPaid: () => onToggleCustomerDeliveryPaid(
                  purchase,
                  customerFinance.customer,
                ),
                onToggleExtraPaid: () => onToggleCustomerExtraPaid(
                  purchase,
                  customerFinance.customer,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PurchaseFinance {
  final double goodsDueRub;
  final double goodsPaidRub;
  final double deliveryDueRub;
  final double deliveryPaidRub;
  final double extraDueRub;
  final double extraPaidRub;
  final double profitRub;
  final List<SpV2Expense> globalExpenses;
  final List<_CustomerFinance> customers;

  const _PurchaseFinance({
    required this.goodsDueRub,
    required this.goodsPaidRub,
    required this.deliveryDueRub,
    required this.deliveryPaidRub,
    required this.extraDueRub,
    required this.extraPaidRub,
    required this.profitRub,
    required this.globalExpenses,
    required this.customers,
  });

  double get totalDueRub => goodsDueRub + deliveryDueRub + extraDueRub;
  double get totalPaidRub => goodsPaidRub + deliveryPaidRub + extraPaidRub;
  double get totalRemainingRub =>
      (totalDueRub - totalPaidRub).clamp(0, double.infinity).toDouble();

  _CustomerFinance? forCustomer(int customerId) {
    for (final customer in customers) {
      if (customer.customer.id == customerId) return customer;
    }
    return null;
  }

  factory _PurchaseFinance.fromPurchase(SpV2Purchase purchase) {
    final customerMap = <int, _CustomerFinanceBuilder>{};
    var goodsDue = 0.0;
    var goodsPaid = 0.0;
    var deliveryDue = 0.0;
    var deliveryPaid = 0.0;
    var extraDue = 0.0;
    var profitRub = 0.0;

    for (final item in purchase.items) {
      final customer = item.customer;
      if (customer == null) continue;
      final quantity = item.quantity <= 0 ? 1 : item.quantity;
      final goods = _itemBaseRub(item, purchase);
      final goodsPaidItem = _itemGoodsPaidRub(item, purchase);
      final delivery = item.shippingCostRub;
      final deliveryPaidItem = _itemDeliveryPaidRub(item);
      final extra = item.additionalExpensesRub;

      goodsDue += goods;
      goodsPaid += goodsPaidItem;
      deliveryDue += delivery;
      deliveryPaid += deliveryPaidItem;
      extraDue += extra;
      profitRub += _itemProfitRub(item, purchase);

      final builder = customerMap.putIfAbsent(
        customer.id,
        () => _CustomerFinanceBuilder(customer),
      );
      builder.itemsCount += 1;
      builder.unitsCount += quantity;
      builder.goodsDueRub += goods;
      builder.goodsPaidRub += goodsPaidItem;
      builder.deliveryDueRub += delivery;
      builder.deliveryPaidRub += deliveryPaidItem;
      builder.extraDueRub += extra;
      builder.weightKg += item.actualWeightKg;
      builder.allGoodsPaid = builder.allGoodsPaid && item.isGoodsPaid;
      builder.allDeliveryPaid = builder.allDeliveryPaid && item.isDeliveryPaid;
    }

    final builders = customerMap.values.toList(growable: false);
    final globalExpenses = purchase.expenses
        .where((expense) => expense.scope == 'purchase')
        .toList(growable: false);
    for (final expense in globalExpenses) {
      extraDue += expense.amountRub;
      if (builders.isEmpty) continue;
      final totalWeight = builders.fold<double>(
        0,
        (sum, b) => sum + b.weightKg,
      );
      final totalItems = builders.fold<int>(0, (sum, b) => sum + b.itemsCount);
      final totalUnits = builders.fold<int>(0, (sum, b) => sum + b.unitsCount);
      final totalGoods = builders.fold<double>(
        0,
        (sum, b) => sum + b.goodsDueRub,
      );
      for (final builder in builders) {
        builder.extraDueRub += _allocatedExpenseShare(
          expense,
          builder,
          customersCount: builders.length,
          totalWeight: totalWeight,
          totalItems: totalUnits > 0 ? totalUnits : totalItems,
          totalGoods: totalGoods,
        );
      }
    }

    for (final payment in purchase.payments) {
      if (payment.type != 'extra_payment' || !payment.isPaid) continue;
      final customerId = payment.spCustomerId;
      if (customerId == null) continue;
      final builder = customerMap[customerId];
      if (builder == null) continue;
      builder.extraPaidRub += payment.amountRub;
    }

    return _PurchaseFinance(
      goodsDueRub: goodsDue,
      goodsPaidRub: goodsPaid,
      deliveryDueRub: deliveryDue,
      deliveryPaidRub: deliveryPaid,
      extraDueRub: extraDue,
      extraPaidRub: customerMap.values.fold<double>(
        0,
        (sum, builder) => sum + builder.extraPaidRub,
      ),
      profitRub: profitRub,
      globalExpenses: globalExpenses,
      customers: customerMap.values
          .map((builder) => builder.build())
          .toList(growable: false),
    );
  }
}

double _allocatedExpenseShare(
  SpV2Expense expense,
  _CustomerFinanceBuilder builder, {
  required int customersCount,
  required double totalWeight,
  required int totalItems,
  required double totalGoods,
}) {
  if (expense.amountRub <= 0 || customersCount <= 0) return 0;
  switch (expense.allocationMethod) {
    case 'by_weight':
      if (totalWeight > 0 && builder.weightKg > 0) {
        return expense.amountRub * builder.weightKg / totalWeight;
      }
      return expense.amountRub / customersCount;
    case 'by_item_count':
      if (totalItems > 0 && builder.itemsCount > 0) {
        return expense.amountRub * builder.itemsCount / totalItems;
      }
      return expense.amountRub / customersCount;
    case 'by_purchase_amount':
      if (totalGoods > 0 && builder.goodsDueRub > 0) {
        return expense.amountRub * builder.goodsDueRub / totalGoods;
      }
      return expense.amountRub / customersCount;
    case 'manual':
    case 'equal':
    default:
      return expense.amountRub / customersCount;
  }
}

class _CustomerFinanceBuilder {
  final SpV2Customer customer;
  int itemsCount = 0;
  int unitsCount = 0;
  double goodsDueRub = 0;
  double goodsPaidRub = 0;
  double deliveryDueRub = 0;
  double deliveryPaidRub = 0;
  double extraDueRub = 0;
  double extraPaidRub = 0;
  double weightKg = 0;
  bool allGoodsPaid = true;
  bool allDeliveryPaid = true;

  _CustomerFinanceBuilder(this.customer);

  _CustomerFinance build() {
    return _CustomerFinance(
      customer: customer,
      itemsCount: itemsCount,
      goodsDueRub: goodsDueRub,
      goodsPaidRub: goodsPaidRub,
      deliveryDueRub: deliveryDueRub,
      deliveryPaidRub: deliveryPaidRub,
      extraDueRub: extraDueRub,
      extraPaidRub: extraPaidRub,
      allGoodsPaid: itemsCount > 0 && allGoodsPaid,
      allDeliveryPaid: itemsCount > 0 && allDeliveryPaid,
      allExtraPaid: extraDueRub <= 0 || extraPaidRub >= extraDueRub - 0.01,
    );
  }
}

class _CustomerFinance {
  final SpV2Customer customer;
  final int itemsCount;
  final double goodsDueRub;
  final double goodsPaidRub;
  final double deliveryDueRub;
  final double deliveryPaidRub;
  final double extraDueRub;
  final double extraPaidRub;
  final bool allGoodsPaid;
  final bool allDeliveryPaid;
  final bool allExtraPaid;

  const _CustomerFinance({
    required this.customer,
    required this.itemsCount,
    required this.goodsDueRub,
    required this.goodsPaidRub,
    required this.deliveryDueRub,
    required this.deliveryPaidRub,
    required this.extraDueRub,
    required this.extraPaidRub,
    required this.allGoodsPaid,
    required this.allDeliveryPaid,
    required this.allExtraPaid,
  });

  double get totalDueRub => goodsDueRub + deliveryDueRub + extraDueRub;
  double get totalPaidRub => goodsPaidRub + deliveryPaidRub + extraPaidRub;
}

class _ExpensesCard extends StatelessWidget {
  final List<SpV2Expense> expenses;
  final VoidCallback onAddExpense;

  const _ExpensesCard({required this.expenses, required this.onAddExpense});

  @override
  Widget build(BuildContext context) {
    final total = expenses.fold<double>(
      0,
      (sum, expense) => sum + expense.amountRub,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: context.brandPrimary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  color: context.brandPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Общие расходы СП',
                      style: SpFinanceUi.sectionTitleStyle,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      expenses.isEmpty
                          ? 'Расходы на всю СП: терминал, бензин, переупаковка. Они распределяются между клиентами.'
                          : '${expenses.length} расходов · ${_formatRub(total)}',
                      style: SpFinanceUi.labelStyle,
                    ),
                  ],
                ),
              ),
              _ContactActionChip(
                icon: Icons.add_rounded,
                label: 'Добавить',
                onTap: onAddExpense,
              ),
            ],
          ),
          if (expenses.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...expenses.map(
              (expense) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: SpFinanceUi.softDecoration(context),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              expense.title,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontFamily: 'Gilroy',
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              SpV2ExpenseAllocationInfo.labelFor(
                                expense.allocationMethod,
                              ),
                              style: SpFinanceUi.labelStyle,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _formatRub(expense.amountRub),
                        style: TextStyle(
                          color: context.brandPrimary,
                          fontFamily: 'Gilroy',
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AddExpenseSheet extends ConsumerStatefulWidget {
  final SpV2Purchase purchase;

  const _AddExpenseSheet({required this.purchase});

  @override
  ConsumerState<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends ConsumerState<_AddExpenseSheet> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _commentController = TextEditingController();
  String _allocationMethod = 'equal';
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  double? _readAmount() {
    return double.tryParse(_amountController.text.replaceAll(',', '.').trim());
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _titleController.text.trim();
    final amount = _readAmount();
    if (title.isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите название и сумму расхода')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(spV2RepositoryProvider)
          .createExpense(
            widget.purchase.id,
            CreateSpV2ExpenseInput(
              title: title,
              amountRub: amount,
              allocationMethod: _allocationMethod,
              comment: _commentController.text.trim(),
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _spActionErrorMessage(
              context,
              error,
              action: 'добавить общий расход',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.84;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SafeArea(
        bottom: false,
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 58,
                height: 6,
                decoration: BoxDecoration(
                  color: const Color(0xFFE1E5ED),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: SpAnimatedHeroSurface(
                  padding: const EdgeInsets.all(16),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.receipt_long_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Общий расход',
                              style: TextStyle(
                                color: Colors.white,
                                fontFamily: 'Gilroy',
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Запишите расход и выберите как разделить его между клиентами.',
                              style: TextStyle(
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
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(18, 0, 18, 18 + bottomInset),
                  children: [
                    TextField(
                      controller: _titleController,
                      textInputAction: TextInputAction.next,
                      decoration: SpFinanceUi.inputDecoration(
                        context,
                        labelText: 'Название расхода',
                        hintText: 'Например, доставка с терминала',
                        prefixIcon: Icons.edit_note_rounded,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.next,
                      decoration: SpFinanceUi.inputDecoration(
                        context,
                        labelText: 'Сумма в рублях',
                        suffixText: '₽',
                        prefixIcon: Icons.payments_rounded,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Как распределить',
                      style: SpFinanceUi.sectionTitleStyle,
                    ),
                    const SizedBox(height: 10),
                    const SpInfoNotice(
                      title: 'Это общий расход на всю СП',
                      message:
                          'Выберите правило — приложение добавит долю этого расхода каждому клиенту. Если расход относится только к одному товару, добавляйте его в редактировании товара.',
                      icon: Icons.call_split_rounded,
                    ),
                    const SizedBox(height: 10),
                    ...SpV2ExpenseAllocationInfo.all.map((method) {
                      final selected = method.code == _allocationMethod;
                      final color = selected
                          ? context.brandPrimary
                          : AppColors.textSecondary;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: selected
                              ? context.brandPrimary.withValues(alpha: 0.10)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            onTap: () =>
                                setState(() => _allocationMethod = method.code),
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: selected
                                      ? context.brandPrimary.withValues(
                                          alpha: 0.22,
                                        )
                                      : Colors.black.withValues(alpha: 0.035),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selected
                                        ? Icons.check_circle_rounded
                                        : Icons.circle_outlined,
                                    color: color,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          method.label,
                                          style: TextStyle(
                                            color: selected
                                                ? AppColors.textPrimary
                                                : color,
                                            fontFamily: 'Gilroy',
                                            fontSize: 15,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          method.description,
                                          style: SpFinanceUi.labelStyle,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _commentController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: SpFinanceUi.inputDecoration(
                        context,
                        labelText: 'Комментарий',
                        prefixIcon: Icons.notes_rounded,
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
                child: _ActionButton(
                  icon: Icons.add_rounded,
                  label: _saving ? 'Добавляем...' : 'Добавить расход',
                  onTap: _saving ? () {} : _save,
                  filled: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FinanceSummaryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final double dueRub;
  final double paidRub;

  const _FinanceSummaryCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.dueRub,
    required this.paidRub,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = (dueRub - paidRub).clamp(0, double.infinity).toDouble();
    final progress = dueRub <= 0
        ? 0.0
        : (paidRub / dueRub).clamp(0.0, 1.0).toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: context.brandPrimary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(icon, color: context.brandPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: SpFinanceUi.sectionTitleStyle),
                    const SizedBox(height: 3),
                    Text(subtitle, style: SpFinanceUi.labelStyle),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _FinanceMiniMetric(
                  label: 'Начислено',
                  value: _formatRub(dueRub),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FinanceMiniMetric(
                  label: 'Оплачено',
                  value: _formatRub(paidRub),
                  positive: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FinanceMiniMetric(
                  label: 'Остаток',
                  value: _formatRub(remaining),
                  warning: remaining > 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              color: const Color(0xFF16A34A),
              backgroundColor: Colors.black.withValues(alpha: 0.06),
            ),
          ),
        ],
      ),
    );
  }
}

class _FinanceMiniMetric extends StatelessWidget {
  final String label;
  final String value;
  final bool positive;
  final bool warning;

  const _FinanceMiniMetric({
    required this.label,
    required this.value,
    this.positive = false,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = positive
        ? const Color(0xFF16A34A)
        : warning
        ? context.brandPrimary
        : AppColors.textPrimary;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: SpFinanceUi.softDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: SpFinanceUi.labelStyle),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontFamily: 'Gilroy',
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _FinanceTotalCard extends StatelessWidget {
  final _PurchaseFinance finance;

  const _FinanceTotalCard({required this.finance});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: SpFinanceUi.cardDecoration(
        color: context.brandPrimary.withValues(alpha: 0.06),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _FinanceMiniMetric(
                  label: 'Всего начислено',
                  value: _formatRub(finance.totalDueRub),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FinanceMiniMetric(
                  label: 'Всего оплачено',
                  value: _formatRub(finance.totalPaidRub),
                  positive: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FinanceMiniMetric(
                  label: 'Осталось',
                  value: _formatRub(finance.totalRemainingRub),
                  warning: finance.totalRemainingRub > 0,
                ),
              ),
            ],
          ),
          if (finance.profitRub != 0) ...[
            const SizedBox(height: 8),
            _FinanceMiniMetric(
              label: 'Расчётная прибыль организатора',
              value: _formatRub(finance.profitRub),
              positive: finance.profitRub > 0,
              warning: finance.profitRub < 0,
            ),
          ],
        ],
      ),
    );
  }
}

class _CustomerFinanceCard extends StatelessWidget {
  final _CustomerFinance finance;
  final VoidCallback onToggleGoodsPaid;
  final VoidCallback onToggleDeliveryPaid;
  final VoidCallback onToggleExtraPaid;

  const _CustomerFinanceCard({
    required this.finance,
    required this.onToggleGoodsPaid,
    required this.onToggleDeliveryPaid,
    required this.onToggleExtraPaid,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: SpFinanceUi.cardDecoration(),
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
                child: Icon(Icons.person_rounded, color: context.brandPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      finance.customer.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SpFinanceUi.sectionTitleStyle.copyWith(
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${finance.itemsCount} товаров · всего ${_formatRub(finance.totalDueRub)}',
                      style: SpFinanceUi.labelStyle,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _CustomerFinanceLine(
            title: 'Товары',
            dueRub: finance.goodsDueRub,
            paidRub: finance.goodsPaidRub,
          ),
          const SizedBox(height: 8),
          _CustomerFinanceLine(
            title: 'Доставка',
            dueRub: finance.deliveryDueRub,
            paidRub: finance.deliveryPaidRub,
          ),
          if (finance.extraDueRub > 0) ...[
            const SizedBox(height: 8),
            _CustomerFinanceLine(
              title: 'Доп. расходы',
              dueRub: finance.extraDueRub,
              paidRub: finance.extraPaidRub,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _CustomerPayButton(
                  label: finance.allGoodsPaid
                      ? 'Товар оплачен'
                      : 'Оплатить товар',
                  selected: finance.allGoodsPaid,
                  onTap: onToggleGoodsPaid,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CustomerPayButton(
                  label: finance.allDeliveryPaid
                      ? 'Доставка оплачена'
                      : 'Оплатить доставку',
                  selected: finance.allDeliveryPaid,
                  onTap: onToggleDeliveryPaid,
                ),
              ),
            ],
          ),
          if (finance.extraDueRub > 0) ...[
            const SizedBox(height: 8),
            _CustomerPayButton(
              label: finance.allExtraPaid
                  ? 'Доп. расходы оплачены'
                  : 'Оплатить доп. расходы',
              selected: finance.allExtraPaid,
              onTap: onToggleExtraPaid,
            ),
          ],
        ],
      ),
    );
  }
}

class _CustomerFinanceLine extends StatelessWidget {
  final String title;
  final double dueRub;
  final double paidRub;

  const _CustomerFinanceLine({
    required this.title,
    required this.dueRub,
    required this.paidRub,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = (dueRub - paidRub).clamp(0, double.infinity).toDouble();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: SpFinanceUi.softDecoration(context),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontFamily: 'Gilroy',
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            '${_formatRub(paidRub)} / ${_formatRub(dueRub)}',
            style: SpFinanceUi.labelStyle,
          ),
          if (remaining > 0) ...[
            const SizedBox(width: 8),
            Text(
              'ост. ${_formatRub(remaining)}',
              style: TextStyle(
                color: context.brandPrimary,
                fontFamily: 'Gilroy',
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TracksTab extends StatelessWidget {
  final SpV2Purchase purchase;

  const _TracksTab({super.key, required this.purchase});

  @override
  Widget build(BuildContext context) {
    final tracks = purchase.items
        .expand((item) => item.tracks.map((track) => (item, track)))
        .toList(growable: false);
    if (tracks.isEmpty) {
      return const _TabEmptyCard(
        icon: Icons.local_shipping_outlined,
        title: 'Треки ещё не привязаны',
        message:
            'После выкупа можно будет привязать трек к товару. Тогда на странице треков подтянется информация о товаре СП.',
      );
    }

    return Column(
      children: tracks
          .map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: SpFinanceUi.cardDecoration(),
                child: Row(
                  children: [
                    Icon(
                      Icons.local_shipping_rounded,
                      color: context.brandPrimary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.$2.trackNumber,
                            style: SpFinanceUi.sectionTitleStyle,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            entry.$1.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SpFinanceUi.labelStyle,
                          ),
                        ],
                      ),
                    ),
                    _SoftStatusPill(label: entry.$2.status),
                  ],
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _TabEmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _TabEmptyCard({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        children: [
          Icon(icon, color: context.brandPrimary, size: 34),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Gilroy',
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Gilroy',
              fontSize: 13,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            _ActionButton(
              icon: Icons.add_rounded,
              label: actionLabel!,
              onTap: onAction!,
              filled: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _SoftStatusPill extends StatelessWidget {
  final String label;

  const _SoftStatusPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: context.brandPrimary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.brandPrimary.withValues(alpha: 0.16)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: context.brandPrimary,
          fontFamily: 'Gilroy',
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: context.brandPrimary, size: 15),
          const SizedBox(width: 6),
          Flexible(child: Text(label, style: SpFinanceUi.labelStyle)),
        ],
      ),
    );
    return content;
  }
}

class _ItemQuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ItemQuickAction({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF16A34A) : context.brandPrimary;
    return Material(
      color: color.withValues(alpha: selected ? 0.12 : 0.08),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : icon,
                color: color,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontFamily: 'Gilroy',
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusSelectTile extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _StatusSelectTile({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE1E5ED)),
          ),
          child: Row(
            children: [
              Icon(Icons.flag_rounded, color: context.brandPrimary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      commerceText(context, 'Статус товара'),
                      style: SpFinanceUi.labelStyle,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Gilroy',
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemStatusSheet extends StatelessWidget {
  final String selectedStatus;

  const _ItemStatusSheet({required this.selectedStatus});

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.74;
    return SafeArea(
      bottom: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 58,
              height: 6,
              decoration: BoxDecoration(
                color: const Color(0xFFE1E5ED),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: SpAnimatedHeroSurface(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.flag_rounded, color: Colors.white, size: 34),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            commerceText(context, 'Статус товара'),
                            style: TextStyle(
                              color: Colors.white,
                              fontFamily: 'Gilroy',
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            commerceText(
                              context,
                              'Выберите этап обработки позиции в СП.',
                            ),
                            style: TextStyle(
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
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  18,
                  0,
                  18,
                  18 + MediaQuery.paddingOf(context).bottom,
                ),
                itemBuilder: (context, index) {
                  final status = SpV2ItemStatusInfo.all[index];
                  final selected = status.code == selectedStatus;
                  final color = selected
                      ? const Color(0xFF16A34A)
                      : context.brandPrimary;
                  return Material(
                    color: selected
                        ? color.withValues(alpha: 0.10)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(status.code),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: selected
                                ? color.withValues(alpha: 0.22)
                                : Colors.black.withValues(alpha: 0.035),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selected
                                  ? Icons.check_circle_rounded
                                  : Icons.circle_outlined,
                              color: color,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                commerceText(context, status.label),
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontFamily: 'Gilroy',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemCount: SpV2ItemStatusInfo.all.length,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditCustomerBlock extends StatelessWidget {
  final SpV2Customer? customer;

  const _EditCustomerBlock({required this.customer});

  @override
  Widget build(BuildContext context) {
    final customer = this.customer;
    final contacts = customer == null
        ? ''
        : [customer.phone, customer.telegram, customer.wechat]
              .whereType<String>()
              .where((value) => value.trim().isNotEmpty)
              .join(' · ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: SpFinanceUi.softDecoration(context),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: context.brandPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(Icons.person_rounded, color: context.brandPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Клиент', style: SpFinanceUi.labelStyle),
                const SizedBox(height: 3),
                Text(
                  customer?.fullName ?? 'Клиент не указан',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (contacts.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    contacts,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SpFinanceUi.labelStyle,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditItemCustomerSelect extends StatelessWidget {
  final List<SpV2Customer> customers;
  final int? selectedCustomerId;
  final SpV2Customer? fallbackCustomer;
  final ValueChanged<int?> onChanged;

  const _EditItemCustomerSelect({
    required this.customers,
    required this.selectedCustomerId,
    required this.fallbackCustomer,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = <SpV2Customer>[
      ...customers,
      if (fallbackCustomer != null &&
          !customers.any((customer) => customer.id == fallbackCustomer!.id))
        fallbackCustomer!,
    ];
    if (options.isEmpty) {
      return _EditCustomerBlock(customer: fallbackCustomer);
    }

    final selected =
        options.any((customer) => customer.id == selectedCustomerId)
        ? selectedCustomerId
        : fallbackCustomer?.id;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: SpFinanceUi.softDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: context.brandPrimary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(Icons.person_rounded, color: context.brandPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Клиент товара',
                  style: SpFinanceUi.sectionTitleStyle.copyWith(fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: selected,
            decoration: SpFinanceUi.inputDecoration(
              context,
              labelText: 'Перенести товар на клиента',
            ),
            items: options
                .map(
                  (customer) => DropdownMenuItem<int>(
                    value: customer.id,
                    child: Text(
                      customer.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: onChanged,
          ),
          const SizedBox(height: 8),
          const Text(
            'При смене клиента оплаты, фото и расходы этого товара будут перенесены вместе с товаром.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Gilroy',
              fontSize: 12,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkTextField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;

  const _LinkTextField({required this.controller, required this.labelText});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final link = value.text.trim();
        return TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: SpFinanceUi.inputDecoration(context, labelText: labelText)
              .copyWith(
                suffixIcon: link.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Открыть ссылку',
                        icon: Icon(
                          Icons.open_in_new_rounded,
                          color: context.brandPrimary,
                        ),
                        onPressed: () => _openExternalLink(context, link),
                      ),
              ),
        );
      },
    );
  }
}

class _ExistingItemImagesBlock extends StatelessWidget {
  final List<SpV2Media> media;

  const _ExistingItemImagesBlock({required this.media});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: SpFinanceUi.softDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            media.isEmpty
                ? 'Изображения товара'
                : 'Изображения товара (${media.length})',
            style: SpFinanceUi.sectionTitleStyle.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 8),
          if (media.isEmpty)
            const Text(
              'Изображения ещё не добавлены.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Gilroy',
                fontSize: 12,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            _ItemMediaStrip(media: media),
        ],
      ),
    );
  }
}

class _PickedSpImage {
  final Uint8List bytes;
  final String fileName;
  final String? mimeType;

  const _PickedSpImage({
    required this.bytes,
    required this.fileName,
    this.mimeType,
  });
}

String _spFileNameWithExtension(String fileName, String extension) {
  final cleanExtension = extension.startsWith('.')
      ? extension.substring(1)
      : extension;
  if (cleanExtension.isEmpty) return fileName;

  final dotIndex = fileName.lastIndexOf('.');
  final baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
  return '$baseName.$cleanExtension';
}

String? _mimeTypeForName(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.heic')) return 'image/heic';
  if (lower.endsWith('.heif')) return 'image/heif';
  return null;
}

Future<_PickedSpImage> _compressSpItemImage(_PickedSpImage image) async {
  const maxMultipartSafeBytes = 9 * 1024 * 1024;
  var compressed = await ImageCompressor.compressForUpload(
    image.bytes,
    sourceName: image.fileName,
  );
  if (compressed.bytes.lengthInBytes > maxMultipartSafeBytes) {
    compressed = await ImageCompressor.compressForUpload(
      image.bytes,
      sourceName: image.fileName,
      maxSide: 1600,
      quality: 75,
    );
  }
  if (compressed.bytes.lengthInBytes > maxMultipartSafeBytes) {
    throw Exception('фото не удалось сжать до 10 MB');
  }

  return _PickedSpImage(
    bytes: compressed.bytes,
    fileName: _spFileNameWithExtension(image.fileName, compressed.extension),
    mimeType: compressed.mimeType,
  );
}

Future<List<_PickedSpImage>> _pickSpItemImages(BuildContext context) async {
  try {
    final pickedFiles = await ImagePicker().pickMultiImage(imageQuality: 92);
    final images = <_PickedSpImage>[];
    for (final file in pickedFiles) {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) continue;
      images.add(
        _PickedSpImage(
          bytes: bytes,
          fileName: file.name,
          mimeType: _mimeTypeForName(file.name),
        ),
      );
    }
    return images;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось выбрать фото: $error')),
      );
    }
    return const [];
  }
}

Future<List<String>?> _uploadSpItemImages(
  BuildContext context,
  SpV2Repository repository,
  List<_PickedSpImage> images,
) async {
  if (images.isEmpty) return const [];

  final mediaUrls = <String>[];
  try {
    for (final image in images) {
      final uploadImage = await _compressSpItemImage(image);
      final url = await repository.uploadMedia(
        bytes: uploadImage.bytes,
        fileName: uploadImage.fileName,
        mimeType: uploadImage.mimeType,
      );
      if (!context.mounted) return null;
      if (url == null || url.trim().isEmpty) {
        throw Exception('сервер не вернул URL изображения');
      }
      mediaUrls.add(url);
    }
    return mediaUrls;
  } catch (error) {
    debugPrint('SP v2 item image upload failed: $error');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось загрузить фото товара. Товар не сохранён.'),
        ),
      );
    }
    return null;
  }
}

class _PickedImagesBlock extends StatelessWidget {
  final List<_PickedSpImage> images;
  final VoidCallback onPick;
  final ValueChanged<int> onRemove;

  const _PickedImagesBlock({
    required this.images,
    required this.onPick,
    required this.onRemove,
  });

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
              Expanded(
                child: Text(
                  images.isEmpty
                      ? 'Изображения товара'
                      : 'Изображения товара (${images.length})',
                  style: SpFinanceUi.sectionTitleStyle.copyWith(fontSize: 16),
                ),
              ),
              TextButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
                label: const Text('Добавить'),
                style: TextButton.styleFrom(
                  foregroundColor: context.brandPrimary,
                  textStyle: const TextStyle(
                    fontFamily: 'Gilroy',
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          if (images.isEmpty)
            const Text(
              'Можно прикрепить фото или скрин товара из WeChat/магазина.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Gilroy',
                fontSize: 12,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            )
          else ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 82,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  final image = images[index];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.memory(
                          image.bytes,
                          width: 92,
                          height: 82,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 5,
                        right: 5,
                        child: GestureDetector(
                          onTap: () => onRemove(index),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemCount: images.length,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AddItemSheet extends ConsumerStatefulWidget {
  final SpV2Purchase purchase;

  const _AddItemSheet({required this.purchase});

  @override
  ConsumerState<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends ConsumerState<_AddItemSheet> {
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _customerTelegramController = TextEditingController();
  final _customerWhatsappController = TextEditingController();
  final _customerWechatController = TextEditingController();
  final _titleController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _sourceUrlController = TextEditingController();
  final _sellerInfoController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _purchasePriceController = TextEditingController();
  final _clientPriceController = TextEditingController();
  final _shippingActualController = TextEditingController();
  final _shippingClientController = TextEditingController();
  final List<_PickedSpImage> _pickedImages = [];
  int? _selectedCustomerId;
  bool _useExistingCustomer = false;
  bool _showCustomerContacts = false;
  bool _showDelivery = false;
  bool _showDetails = false;
  bool _isSaving = false;
  bool _importSheetPending = false;

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _customerTelegramController.dispose();
    _customerWhatsappController.dispose();
    _customerWechatController.dispose();
    _titleController.dispose();
    _quantityController.dispose();
    _sourceUrlController.dispose();
    _sellerInfoController.dispose();
    _descriptionController.dispose();
    _purchasePriceController.dispose();
    _clientPriceController.dispose();
    _shippingActualController.dispose();
    _shippingClientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(spV2CustomersProvider);
    final capabilities = ref
        .watch(spOrganizerCapabilitiesProvider)
        .asData
        ?.value;
    final trackImportEnabled = capabilities?.trackImport == true;
    final purchaseBlankImportEnabled =
        capabilities?.purchaseBlankImport == true;
    final previousPurchaseImportEnabled =
        capabilities?.previousPurchaseImport == true;
    final garageImportEnabled = capabilities?.garageImport == true;
    final hasImports =
        trackImportEnabled ||
        purchaseBlankImportEnabled ||
        previousPurchaseImportEnabled ||
        garageImportEnabled;
    final currency = widget.purchase.currency;
    final priceSuffix = _currencySymbol(currency);

    return UnsavedFormGuard(
      controllers: [
        _customerNameController,
        _customerPhoneController,
        _customerTelegramController,
        _customerWhatsappController,
        _customerWechatController,
        _titleController,
        _quantityController,
        _sourceUrlController,
        _sellerInfoController,
        _descriptionController,
        _purchasePriceController,
        _clientPriceController,
        _shippingActualController,
        _shippingClientController,
      ],
      extraState:
          '$_selectedCustomerId:${_pickedImages.length}:$_useExistingCustomer',
      isBusy: _isSaving,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SpFinanceModalSurface(
          key: const ValueKey('add-item-modal'),
          icon: Icons.add_shopping_cart_rounded,
          title: commerceText(context, 'Добавить товар'),
          maxHeightFactor: 0.94,
          keyboardAware: true,
          body: ListView(
            key: const ValueKey('add-item-form-list'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(top: 14),
            children: [
              if (hasImports) ...[
                ExpansionTile(
                  title: Text(tr(context, ru: 'Импорт товара', zh: '导入商品')),
                  children: [
                    Column(
                      children: [
                        if (trackImportEnabled) ...[
                          _ItemImportEntry(
                            valueKey: 'track-import-entry',
                            icon: Icons.qr_code_2_rounded,
                            title: commerceText(context, 'Добавить из трека'),
                            subtitle: commerceText(
                              context,
                              'Фото, название, количество и трек-номер перенесутся в СП.',
                            ),
                            onTap: _openTrackImport,
                          ),
                          const SizedBox(height: 9),
                        ],
                        if (previousPurchaseImportEnabled) ...[
                          _ItemImportEntry(
                            valueKey: 'previous-purchase-import-entry',
                            icon: Icons.history_rounded,
                            title: commerceText(context, 'Из прошлой закупки'),
                            subtitle: commerceText(
                              context,
                              'Карточка, фото и цены за единицу заполнятся автоматически.',
                            ),
                            onTap: _openPreviousPurchaseImport,
                          ),
                          const SizedBox(height: 9),
                        ],
                        if (purchaseBlankImportEnabled) ...[
                          _ItemImportEntry(
                            valueKey: 'purchase-blank-import-entry',
                            icon: Icons.receipt_long_outlined,
                            title: commerceText(context, 'Из бланка выкупа'),
                            subtitle: commerceText(
                              context,
                              'Фото, ссылка, параметры, количество и цена выкупа перенесутся автоматически.',
                            ),
                            onTap: _openPurchaseBlankImport,
                          ),
                          const SizedBox(height: 9),
                        ],
                        if (garageImportEnabled)
                          _ItemImportEntry(
                            valueKey: 'garage-import-entry',
                            icon: Icons.garage_outlined,
                            title: commerceText(context, 'Из Garage'),
                            subtitle: commerceText(
                              context,
                              'Карточка, фото, количество и цена покупки перенесутся автоматически.',
                            ),
                            onTap: _openGarageImport,
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (currency == 'CNY' && widget.purchase.purchaseRate <= 0) ...[
                SpInfoNotice(
                  title: commerceText(context, 'Курс юаня пока не указан'),
                  message: commerceText(
                    context,
                    'Товар можно добавить сейчас. Рублёвые итоги и оплаты появятся после указания курса в настройках СП.',
                  ),
                  icon: Icons.currency_exchange_rounded,
                ),
                const SizedBox(height: 12),
              ],
              _AddItemSectionCard(
                key: const ValueKey('add-item-customer-section'),
                icon: Icons.person_outline_rounded,
                title: commerceText(context, 'Участник'),
                subtitle: commerceText(
                  context,
                  'Выберите существующего или создайте нового клиента.',
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    customers.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, _) => const SizedBox.shrink(),
                      data: (items) => items.isEmpty
                          ? const SizedBox.shrink()
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final buttons = <Widget>[
                                  _AddItemModeButton(
                                    key: const ValueKey(
                                      'add-item-new-customer-mode',
                                    ),
                                    icon: Icons.person_add_alt_1_rounded,
                                    label: commerceText(context, 'Новый'),
                                    selected: !_useExistingCustomer,
                                    onTap: () => setState(() {
                                      _useExistingCustomer = false;
                                      _selectedCustomerId = null;
                                    }),
                                  ),
                                  _AddItemModeButton(
                                    key: const ValueKey(
                                      'add-item-existing-customer-mode',
                                    ),
                                    icon: Icons.people_alt_outlined,
                                    label: commerceText(context, 'Из списка'),
                                    selected: _useExistingCustomer,
                                    onTap: () => _selectExistingCustomer(items),
                                  ),
                                ];
                                if (MediaQuery.textScalerOf(context).scale(1) >
                                        1.3 &&
                                    constraints.maxWidth < 300) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      buttons.first,
                                      const SizedBox(height: 8),
                                      buttons.last,
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    Expanded(child: buttons.first),
                                    const SizedBox(width: 8),
                                    Expanded(child: buttons.last),
                                  ],
                                );
                              },
                            ),
                    ),
                    if (_useExistingCustomer) ...[
                      const SizedBox(height: 10),
                      customers.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (_, _) => const SizedBox.shrink(),
                        data: (items) {
                          SpV2Customer? selected;
                          for (final customer in items) {
                            if (customer.id == _selectedCustomerId) {
                              selected = customer;
                              break;
                            }
                          }
                          return _SelectedAddItemCustomer(
                            key: const ValueKey('add-item-selected-customer'),
                            customer: selected,
                            onTap: () => _selectExistingCustomer(items),
                          );
                        },
                      ),
                    ] else ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _customerNameController,
                        textInputAction: TextInputAction.next,
                        decoration: SpFinanceUi.inputDecoration(
                          context,
                          labelText: commerceText(context, 'Имя участника *'),
                          hintText: commerceText(
                            context,
                            'Например, Иван Иванов',
                          ),
                          prefixIcon: Icons.badge_outlined,
                        ),
                      ),
                      const SizedBox(height: 9),
                      _AddItemOptionalSection(
                        key: const ValueKey('add-item-customer-contacts'),
                        title: commerceText(context, 'Контакты участника'),
                        subtitle: commerceText(
                          context,
                          'Телефон и мессенджеры — необязательно',
                        ),
                        icon: Icons.chat_bubble_outline_rounded,
                        expanded: _showCustomerContacts,
                        onToggle: () => setState(
                          () => _showCustomerContacts = !_showCustomerContacts,
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: _customerPhoneController,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              decoration: SpFinanceUi.inputDecoration(
                                context,
                                labelText: commerceText(context, 'Телефон'),
                              ),
                            ),
                            const SizedBox(height: 9),
                            TextField(
                              controller: _customerTelegramController,
                              textInputAction: TextInputAction.next,
                              decoration: SpFinanceUi.inputDecoration(
                                context,
                                labelText: 'Telegram',
                                hintText: commerceText(
                                  context,
                                  '@username или ссылка',
                                ),
                              ),
                            ),
                            const SizedBox(height: 9),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final fields = [
                                  TextField(
                                    controller: _customerWhatsappController,
                                    textInputAction: TextInputAction.next,
                                    decoration: SpFinanceUi.inputDecoration(
                                      context,
                                      labelText: 'WhatsApp',
                                    ),
                                  ),
                                  TextField(
                                    controller: _customerWechatController,
                                    textInputAction: TextInputAction.next,
                                    decoration: SpFinanceUi.inputDecoration(
                                      context,
                                      labelText: 'WeChat',
                                    ),
                                  ),
                                ];
                                if (constraints.maxWidth < 380) {
                                  return Column(
                                    children: [
                                      fields.first,
                                      const SizedBox(height: 9),
                                      fields.last,
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    Expanded(child: fields.first),
                                    const SizedBox(width: 9),
                                    Expanded(child: fields.last),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _AddItemSectionCard(
                key: const ValueKey('add-item-product-section'),
                icon: Icons.shopping_bag_outlined,
                title: commerceText(context, 'Товар'),
                subtitle: commerceText(
                  context,
                  'Название и количество обязательны.',
                ),
                child: Column(
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final titleField = TextField(
                          controller: _titleController,
                          textInputAction: TextInputAction.next,
                          decoration: SpFinanceUi.inputDecoration(
                            context,
                            labelText: commerceText(
                              context,
                              'Название товара *',
                            ),
                            hintText: commerceText(context, 'Что покупаем'),
                          ),
                        );
                        final quantityField = TextField(
                          controller: _quantityController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: SpFinanceUi.inputDecoration(
                            context,
                            labelText: commerceText(context, 'Количество *'),
                            suffixText: commerceText(context, 'шт.'),
                          ),
                        );
                        if (constraints.maxWidth < 360) {
                          return Column(
                            children: [
                              titleField,
                              const SizedBox(height: 9),
                              quantityField,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: titleField),
                            const SizedBox(width: 9),
                            SizedBox(width: 116, child: quantityField),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 9),
                    _LinkTextField(
                      controller: _sourceUrlController,
                      labelText: commerceText(context, 'Ссылка на товар'),
                    ),
                    const SizedBox(height: 10),
                    _PickedImagesBlock(
                      images: _pickedImages,
                      onPick: _pickImages,
                      onRemove: (index) =>
                          setState(() => _pickedImages.removeAt(index)),
                    ),
                    const SizedBox(height: 10),
                    _AddItemOptionalSection(
                      key: const ValueKey('add-item-details-section'),
                      title: commerceText(context, 'Параметры и комментарий'),
                      subtitle: commerceText(
                        context,
                        'Размер, цвет, продавец и заметки',
                      ),
                      icon: Icons.tune_rounded,
                      expanded: _showDetails,
                      onToggle: () =>
                          setState(() => _showDetails = !_showDetails),
                      child: Column(
                        children: [
                          TextField(
                            controller: _sellerInfoController,
                            minLines: 2,
                            maxLines: 3,
                            decoration: SpFinanceUi.inputDecoration(
                              context,
                              labelText: commerceText(
                                context,
                                'Параметры товара / продавец',
                              ),
                              hintText: commerceText(
                                context,
                                'Размер, цвет, модель, продавец, WeChat',
                              ),
                            ),
                          ),
                          const SizedBox(height: 9),
                          TextField(
                            controller: _descriptionController,
                            minLines: 2,
                            maxLines: 4,
                            decoration: SpFinanceUi.inputDecoration(
                              context,
                              labelText: commerceText(context, 'Комментарий'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _AddItemSectionCard(
                key: const ValueKey('add-item-prices-section'),
                icon: Icons.payments_outlined,
                title: commerceText(context, 'Цены'),
                subtitle: commerceText(
                  context,
                  'Укажите цену за одну штуку. Маржа посчитается автоматически.',
                ),
                child: Column(
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final purchaseField = TextField(
                          controller: _purchasePriceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textInputAction: TextInputAction.next,
                          decoration: SpFinanceUi.inputDecoration(
                            context,
                            labelText: commerceText(context, 'Цена выкупа'),
                            hintText: commerceText(context, 'Себестоимость'),
                            suffixText: priceSuffix,
                          ),
                        );
                        final clientField = TextField(
                          controller: _clientPriceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textInputAction: TextInputAction.next,
                          decoration: SpFinanceUi.inputDecoration(
                            context,
                            labelText: commerceText(context, 'Цена участника'),
                            hintText: commerceText(context, 'С наценкой'),
                            suffixText: priceSuffix,
                          ),
                        );
                        if (constraints.maxWidth < 400) {
                          return Column(
                            children: [
                              purchaseField,
                              const SizedBox(height: 9),
                              clientField,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: purchaseField),
                            const SizedBox(width: 9),
                            Expanded(child: clientField),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 9),
                    _AddItemHelperLine(
                      icon: Icons.calculate_outlined,
                      text: commerceText(
                        context,
                        'Итог участника = цена участника × количество. Разница с ценой выкупа — ваша маржа.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _AddItemOptionalSection(
                key: const ValueKey('add-item-delivery-section'),
                title: commerceText(context, 'Доставка'),
                subtitle: commerceText(context, 'Можно заполнить позже'),
                icon: Icons.local_shipping_outlined,
                expanded: _showDelivery,
                onToggle: () => setState(() => _showDelivery = !_showDelivery),
                child: Column(
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final actualField = TextField(
                          controller: _shippingActualController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: SpFinanceUi.inputDecoration(
                            context,
                            labelText: commerceText(context, 'Оплачено СП'),
                            hintText: commerceText(context, 'Себестоимость'),
                            suffixText: '₽',
                          ),
                        );
                        final clientField = TextField(
                          controller: _shippingClientController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: SpFinanceUi.inputDecoration(
                            context,
                            labelText: commerceText(
                              context,
                              'Начислить участнику',
                            ),
                            hintText: commerceText(context, 'К оплате'),
                            suffixText: '₽',
                          ),
                        );
                        if (constraints.maxWidth < 400) {
                          return Column(
                            children: [
                              actualField,
                              const SizedBox(height: 9),
                              clientField,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: actualField),
                            const SizedBox(width: 9),
                            Expanded(child: clientField),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 9),
                    _AddItemHelperLine(
                      icon: Icons.info_outline_rounded,
                      text: commerceText(
                        context,
                        'Разница между начислением участнику и фактической оплатой попадёт в прибыль.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
          footer: FilledButton.icon(
            key: const ValueKey('add-item-submit'),
            onPressed: _isSaving ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: context.brandPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(17),
              ),
              textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontFamily: 'Gilroy',
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
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
            label: Text(commerceText(context, 'Добавить товар')),
          ),
        ),
      ),
    );
  }

  Future<void> _selectExistingCustomer(List<SpV2Customer> customers) async {
    final selected = await showSpCustomerPickerSheet(
      context: context,
      customers: customers,
      selectedCustomerId: _selectedCustomerId,
    );
    if (!mounted || selected == null) return;
    setState(() {
      _selectedCustomerId = selected.id;
      _useExistingCustomer = true;
    });
  }

  Future<void> _pickImages() async {
    final picked = await _pickSpItemImages(context);
    if (!mounted || picked.isEmpty) return;
    setState(() => _pickedImages.addAll(picked));
  }

  Future<void> _openPurchaseBlankImport() => _openImportSheet(
    () => showSpOrganizerPurchaseBlankImportSheet(
      context: context,
      purchaseId: widget.purchase.id,
    ),
  );

  Future<void> _openTrackImport() => _openImportSheet(
    () => showSpOrganizerTrackImportSheet(
      context: context,
      purchaseId: widget.purchase.id,
    ),
  );

  Future<void> _openPreviousPurchaseImport() => _openImportSheet(
    () => showSpOrganizerPreviousPurchaseImportSheet(
      context: context,
      purchaseId: widget.purchase.id,
    ),
  );

  Future<void> _openGarageImport() => _openImportSheet(
    () => showSpOrganizerGarageImportSheet(
      context: context,
      purchaseId: widget.purchase.id,
    ),
  );

  Future<void> _openImportSheet(Future<bool?> Function() showSheet) async {
    if (_importSheetPending) return;
    _importSheetPending = true;
    try {
      final imported = await showSheet();
      if (!mounted || imported != true) return;
      Navigator.of(context).pop(true);
    } finally {
      _importSheetPending = false;
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final title = _titleController.text.trim();
    final customerName = _customerNameController.text.trim();
    final quantity = _readPositiveInt(_quantityController.text);
    if (title.isEmpty ||
        (!_useExistingCustomer && customerName.isEmpty) ||
        (_useExistingCustomer && _selectedCustomerId == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(commerceText(context, 'Укажите клиента и товар')),
        ),
      );
      return;
    }
    if (quantity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            commerceText(context, 'Количество должно быть больше 0'),
          ),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repository = ref.read(spV2RepositoryProvider);
      final mediaUrls = await _uploadSpItemImages(
        context,
        repository,
        _pickedImages,
      );
      if (!mounted || mediaUrls == null) return;

      await repository.createItem(
        widget.purchase.id,
        CreateSpV2ItemInput(
          spCustomerId: _useExistingCustomer ? _selectedCustomerId : null,
          customerName: _useExistingCustomer ? null : customerName,
          customerPhone: _useExistingCustomer
              ? null
              : _customerPhoneController.text.trim(),
          customerTelegram: _useExistingCustomer
              ? null
              : _customerTelegramController.text.trim(),
          customerWhatsapp: _useExistingCustomer
              ? null
              : _customerWhatsappController.text.trim(),
          customerWechat: _useExistingCustomer
              ? null
              : _customerWechatController.text.trim(),
          title: title,
          sourceUrl: _sourceUrlController.text.trim(),
          sellerInfo: _sellerInfoController.text.trim(),
          description: _descriptionController.text.trim(),
          quantity: quantity,
          currency: widget.purchase.currency,
          purchasePrice: _readDouble(_purchasePriceController.text),
          clientPriceYuan: widget.purchase.currency == 'CNY'
              ? _readDouble(_clientPriceController.text)
              : null,
          clientPriceRub: widget.purchase.currency == 'RUB'
              ? _readDouble(_clientPriceController.text)
              : null,
          shippingCostActualRub: _readDouble(_shippingActualController.text),
          shippingCostRub: _readDouble(_shippingClientController.text),
          mediaUrls: mediaUrls,
        ),
      );
      if (!mounted) return;
      ref.invalidate(spV2CustomersProvider);
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _spActionErrorMessage(context, error, action: 'сохранить товар'),
          ),
        ),
      );
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

Future<SpV2Customer?> showSpCustomerPickerSheet({
  required BuildContext context,
  required List<SpV2Customer> customers,
  int? selectedCustomerId,
}) {
  return showSpFinanceModalSheet<SpV2Customer>(
    context: context,
    builder: (context) => _SpCustomerPickerSheet(
      customers: customers,
      selectedCustomerId: selectedCustomerId,
    ),
  );
}

class _SpCustomerPickerSheet extends StatefulWidget {
  final List<SpV2Customer> customers;
  final int? selectedCustomerId;

  const _SpCustomerPickerSheet({
    required this.customers,
    this.selectedCustomerId,
  });

  @override
  State<_SpCustomerPickerSheet> createState() => _SpCustomerPickerSheetState();
}

class _SpCustomerPickerSheetState extends State<_SpCustomerPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.customers
        : widget.customers
              .where(
                (customer) =>
                    _customerSearchText(customer).toLowerCase().contains(query),
              )
              .toList(growable: false);

    return SpFinanceModalSurface(
      key: const ValueKey('add-item-customer-picker-modal'),
      icon: Icons.people_alt_outlined,
      title: commerceText(context, 'Выбрать участника'),
      subtitle: tr(
        context,
        ru: 'Найдите клиента по имени, телефону или мессенджеру. Всего: ${widget.customers.length}.',
        zh: '按姓名、电话或即时通讯账号搜索客户，共${widget.customers.length}位。',
      ),
      maxHeightFactor: 0.88,
      keyboardAware: true,
      body: Column(
        children: [
          const SizedBox(height: 14),
          AppSearchField(
            key: const ValueKey('add-item-customer-search'),
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            textInputAction: TextInputAction.search,
            autofocus: true,
            hintText: commerceText(context, 'Имя, телефон, Telegram, WeChat…'),
            onClear: () => setState(() => _query = ''),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: filtered.isEmpty
                ? const _CustomerPickerEmptyState()
                : ListView.separated(
                    key: const ValueKey('add-item-customer-results'),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final customer = filtered[index];
                      return _CustomerPickerTile(
                        customer: customer,
                        selected: customer.id == widget.selectedCustomerId,
                        onTap: () => Navigator.of(context).pop(customer),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SelectedAddItemCustomer extends StatelessWidget {
  final SpV2Customer? customer;
  final VoidCallback onTap;

  const _SelectedAddItemCustomer({
    super.key,
    required this.customer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final customer = this.customer;
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: customer == null
                  ? const Color(0xFFE1E5ED)
                  : context.brandPrimary.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: customer == null
                      ? const Color(0xFFEFF3F8)
                      : context.brandPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  customer == null
                      ? Icons.person_search_rounded
                      : Icons.check_rounded,
                  color: customer == null
                      ? AppColors.textSecondary
                      : context.brandPrimary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer?.fullName ??
                          commerceText(context, 'Выберите участника'),
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
                      customer == null
                          ? commerceText(context, 'Откроется список с поиском')
                          : (_customerPrimaryContact(customer) ??
                                commerceText(context, 'Участник выбран')),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SpFinanceUi.labelStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                customer == null
                    ? commerceText(context, 'Выбрать')
                    : commerceText(context, 'Изменить'),
                style: TextStyle(
                  color: context.brandPrimary,
                  fontFamily: 'Gilroy',
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 3),
              Icon(
                Icons.chevron_right_rounded,
                size: 19,
                color: context.brandPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerPickerTile extends StatelessWidget {
  final SpV2Customer customer;
  final bool selected;
  final VoidCallback onTap;

  const _CustomerPickerTile({
    required this.customer,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final contact = _customerPrimaryContact(customer);
    return Material(
      color: selected
          ? context.brandPrimary.withValues(alpha: 0.08)
          : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: ValueKey('add-item-customer-result-${customer.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? context.brandPrimary : const Color(0xFFE1E5ED),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.brandPrimary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _customerInitials(context, customer.fullName),
                  style: TextStyle(
                    color: context.brandPrimary,
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
                    Text(
                      customer.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Gilroy',
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (contact != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        contact,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                    : Icons.chevron_right_rounded,
                color: selected
                    ? const Color(0xFF16A34A)
                    : AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerPickerEmptyState extends StatelessWidget {
  const _CustomerPickerEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_search_rounded,
              size: 42,
              color: context.brandPrimary,
            ),
            const SizedBox(height: 10),
            Text(
              commerceText(context, 'Участник не найден'),
              style: TextStyle(
                color: AppColors.textPrimary,
                fontFamily: 'Gilroy',
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              commerceText(
                context,
                'Проверьте запрос или добавьте нового клиента.',
              ),
              textAlign: TextAlign.center,
              style: SpFinanceUi.labelStyle,
            ),
          ],
        ),
      ),
    );
  }
}

String _customerSearchText(SpV2Customer customer) {
  return [
    customer.fullName,
    customer.phone,
    customer.email,
    customer.telegram,
    customer.whatsapp,
    customer.wechat,
    customer.vk,
    customer.max,
  ].whereType<String>().join(' ');
}

String? _customerPrimaryContact(SpV2Customer customer) {
  for (final value in [
    customer.phone,
    customer.telegram,
    customer.whatsapp,
    customer.wechat,
    customer.email,
  ]) {
    if (value != null && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

String _customerInitials(BuildContext context, String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .toList(growable: false);
  if (parts.isEmpty) return commerceText(context, 'К');
  return parts.map((part) => part.substring(0, 1).toUpperCase()).join();
}

class _AddItemSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _AddItemSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AddItemSectionHeading(icon: icon, title: title, subtitle: subtitle),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _AddItemSectionHeading extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _AddItemSectionHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: context.brandPrimary.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, size: 20, color: context.brandPrimary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'Gilroy',
                  fontSize: 16,
                  height: 1.15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(subtitle, style: SpFinanceUi.labelStyle),
            ],
          ),
        ),
      ],
    );
  }
}

class _AddItemModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AddItemModeButton({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? context.brandPrimary.withValues(alpha: 0.1)
          : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? context.brandPrimary.withValues(alpha: 0.55)
                  : const Color(0xFFE1E5ED),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? context.brandPrimary
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? context.brandPrimary
                        : AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddItemOptionalSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  const _AddItemOptionalSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: SpFinanceUi.cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: context.brandPrimary.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(icon, size: 20, color: context.brandPrimary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontFamily: 'Gilroy',
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(subtitle, style: SpFinanceUi.labelStyle),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: child,
            ),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
      ),
    );
  }
}

class _AddItemHelperLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _AddItemHelperLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: SpFinanceUi.softDecoration(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: context.brandPrimary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: SpFinanceUi.labelStyle)),
        ],
      ),
    );
  }
}

class _ItemImportEntry extends StatelessWidget {
  final String valueKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ItemImportEntry({
    required this.valueKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.brandPrimary.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        key: ValueKey(valueKey),
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: context.brandPrimary.withValues(alpha: 0.22),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.brandPrimary,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Gilroy',
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontFamily: 'Gilroy',
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: context.brandPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditItemSheet extends ConsumerStatefulWidget {
  final SpV2Purchase purchase;
  final SpV2Item item;

  const _EditItemSheet({required this.purchase, required this.item});

  @override
  ConsumerState<_EditItemSheet> createState() => _EditItemSheetState();
}

class _EditItemSheetState extends ConsumerState<_EditItemSheet> {
  late String _status;
  int? _selectedCustomerId;
  late final TextEditingController _titleController;
  late final TextEditingController _quantityController;
  late final TextEditingController _sourceUrlController;
  late final TextEditingController _sellerInfoController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _trackController;
  late final TextEditingController _purchasePriceController;
  late final TextEditingController _clientPriceController;
  late final TextEditingController _weightController;
  late final TextEditingController _shippingController;
  late final TextEditingController _shippingActualController;
  late final TextEditingController _expensesController;
  late final TextEditingController _totalController;
  final List<_PickedSpImage> _pickedImages = [];
  bool _manualTotalEnabled = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _status = widget.item.status;
    _selectedCustomerId = widget.item.customer?.id;
    _titleController = TextEditingController(text: widget.item.title);
    _quantityController = TextEditingController(
      text: (widget.item.quantity <= 0 ? 1 : widget.item.quantity).toString(),
    )..addListener(_syncAutoTotal);
    _sourceUrlController = TextEditingController(
      text: widget.item.sourceUrl ?? '',
    );
    _sellerInfoController = TextEditingController(
      text: widget.item.sellerInfo ?? '',
    );
    _descriptionController = TextEditingController(
      text: widget.item.description ?? widget.item.comment ?? '',
    );
    _trackController = TextEditingController(
      text: widget.item.tracks.isNotEmpty
          ? widget.item.tracks.first.trackNumber
          : '',
    );
    _purchasePriceController = TextEditingController(
      text: widget.item.purchasePriceForCurrency(widget.purchase.currency) > 0
          ? widget.item
                .purchasePriceForCurrency(widget.purchase.currency)
                .toStringAsFixed(widget.purchase.currency == 'RUB' ? 0 : 2)
          : '',
    );
    _clientPriceController = TextEditingController(
      text: widget.item.clientPriceForCurrency(widget.purchase.currency) > 0
          ? widget.item
                .clientPriceForCurrency(widget.purchase.currency)
                .toStringAsFixed(widget.purchase.currency == 'RUB' ? 0 : 2)
          : '',
    );
    _weightController = TextEditingController(
      text: widget.item.actualWeightKg > 0
          ? widget.item.actualWeightKg.toStringAsFixed(3)
          : '',
    );
    _shippingController = TextEditingController(
      text: widget.item.shippingCostRub > 0
          ? widget.item.shippingCostRub.toStringAsFixed(2)
          : '',
    )..addListener(_syncAutoTotal);
    _shippingActualController = TextEditingController(
      text: widget.item.shippingCostActualRub > 0
          ? widget.item.shippingCostActualRub.toStringAsFixed(2)
          : '',
    );
    _expensesController = TextEditingController(
      text: widget.item.additionalExpensesRub > 0
          ? widget.item.additionalExpensesRub.toStringAsFixed(2)
          : '',
    )..addListener(_syncAutoTotal);
    _totalController = TextEditingController(
      text: widget.item.totalDueRub > 0
          ? widget.item.totalDueRub.toStringAsFixed(2)
          : '',
    );
    _clientPriceController.addListener(_syncAutoTotal);
    final autoTotal = _calculateAutoTotal();
    _manualTotalEnabled =
        widget.item.totalDueRub > 0 &&
        (widget.item.totalDueRub - autoTotal).abs() > 0.01;
    if (!_manualTotalEnabled) {
      _syncAutoTotal();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _quantityController.dispose();
    _sourceUrlController.dispose();
    _sellerInfoController.dispose();
    _descriptionController.dispose();
    _trackController.dispose();
    _purchasePriceController.dispose();
    _clientPriceController.dispose();
    _weightController.dispose();
    _shippingController.dispose();
    _shippingActualController.dispose();
    _expensesController.dispose();
    _totalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.90;
    final priceSuffix = _currencySymbol(widget.purchase.currency);
    final autoTotal = _calculateAutoTotal();
    final customers = ref.watch(spV2CustomersProvider);

    return UnsavedFormGuard(
      controllers: [
        _titleController,
        _quantityController,
        _sourceUrlController,
        _sellerInfoController,
        _descriptionController,
        _trackController,
        _purchasePriceController,
        _clientPriceController,
        _weightController,
        _shippingController,
        _shippingActualController,
        _expensesController,
        _totalController,
      ],
      extraState:
          '$_selectedCustomerId:${_pickedImages.length}:$_status:$_manualTotalEnabled',
      isBusy: _isSaving,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          bottom: false,
          child: Container(
            constraints: BoxConstraints(maxHeight: maxHeight),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 58,
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE1E5ED),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: SpAnimatedHeroSurface(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.edit_note_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'Gilroy',
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.item.customer?.fullName ??
                                    commerceText(context, 'Клиент не указан'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(18, 0, 18, 18 + bottomInset),
                    children: [
                      if (widget.purchase.currency == 'CNY' &&
                          widget.purchase.purchaseRate <= 0) ...[
                        SpInfoNotice(
                          title: commerceText(
                            context,
                            'Курс юаня пока не указан',
                          ),
                          message: commerceText(
                            context,
                            'Суммы в юанях сохранятся, но рублёвый итог, оплаты и прибыль будут неполными до указания курса в карточке СП.',
                          ),
                          icon: Icons.currency_exchange_rounded,
                        ),
                        const SizedBox(height: 10),
                      ],
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ItemQuickAction(
                            icon: Icons.shopping_cart_checkout_rounded,
                            label: widget.item.isPurchased
                                ? commerceText(context, 'Выкуплен')
                                : commerceText(context, 'Отметить выкуп'),
                            selected: widget.item.isPurchased,
                            onTap: _togglePurchasedFromSheet,
                          ),
                          _ItemQuickAction(
                            icon: Icons.payments_rounded,
                            label: widget.item.isGoodsPaid
                                ? commerceText(context, 'Товар оплачен')
                                : commerceText(context, 'Оплатили товар'),
                            selected: widget.item.isGoodsPaid,
                            onTap: () =>
                                _togglePaymentFromSheet('goods_payment'),
                          ),
                          _ItemQuickAction(
                            icon: Icons.local_shipping_rounded,
                            label: widget.item.isDeliveryPaid
                                ? commerceText(context, 'Доставка оплачена')
                                : commerceText(context, 'Оплатили доставку'),
                            selected: widget.item.isDeliveryPaid,
                            onTap: () =>
                                _togglePaymentFromSheet('delivery_payment'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      customers.when(
                        loading: () =>
                            _EditCustomerBlock(customer: widget.item.customer),
                        error: (_, _) =>
                            _EditCustomerBlock(customer: widget.item.customer),
                        data: (items) => _EditItemCustomerSelect(
                          customers: items,
                          selectedCustomerId: _selectedCustomerId,
                          fallbackCustomer: widget.item.customer,
                          onChanged: (value) =>
                              setState(() => _selectedCustomerId = value),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _titleController,
                              textInputAction: TextInputAction.next,
                              decoration: SpFinanceUi.inputDecoration(
                                context,
                                labelText: commerceText(context, 'Что купить'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 104,
                            child: TextField(
                              controller: _quantityController,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: SpFinanceUi.inputDecoration(
                                context,
                                labelText: commerceText(context, 'Кол-во'),
                                suffixText: commerceText(context, 'шт.'),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _LinkTextField(
                        controller: _sourceUrlController,
                        labelText: commerceText(context, 'Ссылка на товар'),
                      ),
                      const SizedBox(height: 10),
                      _StatusSelectTile(
                        label: commerceText(
                          context,
                          SpV2ItemStatusInfo.labelFor(_status),
                        ),
                        onTap: _selectStatus,
                      ),
                      const SizedBox(height: 10),
                      SpInfoNotice(
                        title: commerceText(
                          context,
                          'Трек можно привязать позже',
                        ),
                        message: commerceText(
                          context,
                          'Если указать трек-номер, на странице «Треки и сборки» у этого трека появится информация о товаре СП и клиенте.',
                        ),
                        icon: Icons.local_shipping_rounded,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _trackController,
                        decoration: SpFinanceUi.inputDecoration(
                          context,
                          labelText: commerceText(context, 'Трек-номер'),
                          hintText: commerceText(
                            context,
                            'Опционально, если товар уже привязан к складу',
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SpInfoNotice(
                        title: commerceText(
                          context,
                          'Цена выкупа и цена клиента',
                        ),
                        message: widget.purchase.currency == 'CNY'
                            ? commerceText(
                                context,
                                'Суммы здесь за 1 шт. в юанях. Для рублёвых итогов используется курс СП, а общий товарный долг считается с учётом количества.',
                              )
                            : commerceText(
                                context,
                                'Суммы здесь за 1 шт. в рублях. Общий товарный долг считается как цена клиента × количество.',
                              ),
                        icon: Icons.payments_rounded,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _purchasePriceController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: SpFinanceUi.inputDecoration(
                                context,
                                labelText: commerceText(
                                  context,
                                  'Выкуп за 1 шт.',
                                ),
                                suffixText: priceSuffix,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _clientPriceController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: SpFinanceUi.inputDecoration(
                                context,
                                labelText: commerceText(
                                  context,
                                  'Клиент за 1 шт.',
                                ),
                                suffixText: priceSuffix,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _ExistingItemImagesBlock(media: widget.item.media),
                      const SizedBox(height: 10),
                      _PickedImagesBlock(
                        images: _pickedImages,
                        onPick: _pickImages,
                        onRemove: (index) =>
                            setState(() => _pickedImages.removeAt(index)),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _sellerInfoController,
                        minLines: 2,
                        maxLines: 3,
                        decoration: SpFinanceUi.inputDecoration(
                          context,
                          labelText: commerceText(
                            context,
                            'Данные продавца / параметры товара',
                          ),
                          hintText: commerceText(
                            context,
                            'Размер, цвет, модель, продавец, заметки из WeChat',
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _descriptionController,
                        minLines: 2,
                        maxLines: 4,
                        decoration: SpFinanceUi.inputDecoration(
                          context,
                          labelText: commerceText(context, 'Комментарий'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _weightController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: SpFinanceUi.inputDecoration(
                          context,
                          labelText: commerceText(context, 'Фактический вес'),
                          suffixText: commerceText(context, 'кг'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _shippingActualController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: SpFinanceUi.inputDecoration(
                                context,
                                labelText: commerceText(
                                  context,
                                  'Доставка оплачена СП',
                                ),
                                hintText: commerceText(
                                  context,
                                  'Себестоимость',
                                ),
                                suffixText: '₽',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _shippingController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: SpFinanceUi.inputDecoration(
                                context,
                                labelText: commerceText(
                                  context,
                                  'Доставка клиенту',
                                ),
                                hintText: commerceText(
                                  context,
                                  'К оплате клиентом',
                                ),
                                suffixText: '₽',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SpInfoNotice(
                        title: commerceText(context, 'Доставка и доход'),
                        message: commerceText(
                          context,
                          'Если доставка для клиента выше себестоимости, разница попадёт в расчётную прибыль организатора. Если наценки на товар нет, доход можно фиксировать именно здесь.',
                        ),
                        icon: Icons.receipt_long_rounded,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _expensesController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: SpFinanceUi.inputDecoration(
                          context,
                          labelText: commerceText(context, 'Доп. расходы'),
                          suffixText: '₽',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _totalController,
                        enabled: _manualTotalEnabled,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: SpFinanceUi.inputDecoration(
                          context,
                          labelText: _manualTotalEnabled
                              ? commerceText(
                                  context,
                                  'Итого к оплате — ручная корректировка',
                                )
                              : commerceText(
                                  context,
                                  'Итого к оплате — авторасчёт',
                                ),
                          hintText: _formatRub(autoTotal),
                          suffixText: '₽',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: SpFinanceUi.softDecoration(context),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                tr(
                                  context,
                                  ru: 'Авто: цена клиента × количество + доставка + доп. расходы = ${_formatRub(autoTotal)}',
                                  zh: '自动：客户单价 × 数量 + 运费 + 额外费用 = ${_formatRub(autoTotal)}',
                                ),
                                style: SpFinanceUi.labelStyle,
                              ),
                            ),
                            TextButton(
                              onPressed: () => setState(() {
                                _manualTotalEnabled = !_manualTotalEnabled;
                                if (!_manualTotalEnabled) _syncAutoTotal();
                              }),
                              child: Text(
                                _manualTotalEnabled
                                    ? commerceText(context, 'Вернуть авто')
                                    : commerceText(context, 'Скорректировать'),
                              ),
                            ),
                          ],
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
                      label: Text(commerceText(context, 'Сохранить')),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _syncAutoTotal() {
    if (_manualTotalEnabled) return;
    final total = _calculateAutoTotal();
    final text = total > 0 ? total.toStringAsFixed(2) : '';
    if (_totalController.text != text) {
      _totalController.text = text;
    }
  }

  double _calculateAutoTotal() {
    final clientPrice = _readDouble(_clientPriceController.text) ?? 0;
    final quantity = _readPositiveInt(_quantityController.text) ?? 1;
    final clientRub = widget.purchase.currency == 'RUB'
        ? clientPrice
        : clientPrice * widget.purchase.purchaseRate;
    return clientRub * quantity +
        (_readDouble(_shippingController.text) ?? 0) +
        (_readDouble(_expensesController.text) ?? 0);
  }

  Future<void> _selectStatus() async {
    FocusScope.of(context).unfocus();
    final selected = await showSpFinanceModalSheet<String>(
      context: context,
      builder: (context) => _ItemStatusSheet(selectedStatus: _status),
    );
    if (!mounted || selected == null || selected == _status) return;
    setState(() => _status = selected);
  }

  Future<void> _pickImages() async {
    final picked = await _pickSpItemImages(context);
    if (!mounted || picked.isEmpty) return;
    setState(() => _pickedImages.addAll(picked));
  }

  Future<void> _togglePurchasedFromSheet() async {
    setState(() => _isSaving = true);
    try {
      await ref
          .read(spV2RepositoryProvider)
          .updateItem(
            widget.item.id,
            status: widget.item.isPurchased ? 'approved' : 'purchased',
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _togglePaymentFromSheet(String type) async {
    final isPaid = type == 'goods_payment'
        ? widget.item.isGoodsPaid
        : widget.item.isDeliveryPaid;
    setState(() => _isSaving = true);
    try {
      await ref
          .read(spV2RepositoryProvider)
          .setItemPayment(
            widget.item.id,
            type: type,
            paid: !isPaid,
            amountRub: type == 'goods_payment'
                ? _goodsPaymentAmountRub(widget.item, widget.purchase)
                : _deliveryPaymentAmountRub(widget.item),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final quantity = _readPositiveInt(_quantityController.text);
    if (quantity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            commerceText(context, 'Количество должно быть больше 0'),
          ),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repository = ref.read(spV2RepositoryProvider);
      final mediaUrls = await _uploadSpItemImages(
        context,
        repository,
        _pickedImages,
      );
      if (!mounted || mediaUrls == null) return;

      await repository.updateItem(
        widget.item.id,
        spCustomerId: _selectedCustomerId,
        title: _titleController.text.trim(),
        sourceUrl: _sourceUrlController.text.trim(),
        sellerInfo: _sellerInfoController.text.trim(),
        description: _descriptionController.text.trim(),
        comment: _descriptionController.text.trim(),
        quantity: quantity,
        status: _status,
        trackNumber: _trackController.text.trim().isEmpty
            ? null
            : _trackController.text.trim(),
        currency: widget.purchase.currency,
        purchasePrice: _readDouble(_purchasePriceController.text),
        clientPrice: _readDouble(_clientPriceController.text),
        actualWeightKg: _readDouble(_weightController.text),
        shippingCostRub: _readDouble(_shippingController.text),
        shippingCostActualRub: _readDouble(_shippingActualController.text),
        additionalExpensesRub: _readDouble(_expensesController.text),
        totalDueRub: _manualTotalEnabled
            ? _readDouble(_totalController.text)
            : _calculateAutoTotal(),
        mediaUrls: mediaUrls,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _spActionErrorMessage(
              context,
              error,
              action: 'сохранить изменения',
            ),
          ),
        ),
      );
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
