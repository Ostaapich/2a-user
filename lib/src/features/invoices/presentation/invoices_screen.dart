import 'package:twoalogisticcabineuser/src/core/media/authenticated_media.dart';
import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_toast.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../training/presentation/training_target.dart';
import '../../../core/ui/scroll_to_top_button.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:twoalogisticcabineuser/src/core/ui/blurred_modal_bottom_sheet.dart';
import '../../../core/network/api_client.dart';
import '../../../core/ui/app_layout.dart';
import '../../../core/ui/tutorial_card.dart';
import '../../../core/ui/empty_state.dart';
import '../../../core/ui/sheet_handle.dart';
import '../../../core/ui/status_timeline_sheet.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/ui/app_input_decoration.dart';
import '../../../core/network/api_config.dart';
import '../../../core/utils/locale_text.dart';
import '../../carriers/presentation/client_carrier_tracking_panel.dart';
import '../../payments/data/payment_operator_status.dart';
import '../../payments/presentation/bank_qr_payment_screen.dart';
import '../../payments/data/invoice_payment_options.dart';
import '../../payments/presentation/invoice_payment_method_sheet.dart';
import '../../payments/presentation/client_payment_summary_panel.dart';
import '../../payments/presentation/payment_operator_sleeping_notice.dart';
import '../../../core/utils/error_utils.dart';
import '../../clients/application/client_codes_controller.dart';
import '../../assemblies/domain/box.dart';
import '../../photos/domain/photo_item.dart';
import '../../photos/presentation/photo_viewer_screen.dart';
import '../../referral/data/referral_provider.dart';
import '../../shell/application/shell_branch_provider.dart';
import '../data/invoices_provider.dart';
import '../domain/early_payment_benefit.dart';
import '../domain/invoice_item.dart';

String _localizeMarket(String market) {
  switch (market.trim()) {
    case '19公里':
      return 'Южные ворота';
    case '柳布利诺':
      return 'Люблино';
    default:
      return market;
  }
}

List<StatusTimelineStatus> _invoiceTimelineStatuses(
  List<InvoiceStatus> statuses,
) {
  return statuses
      .map(
        (status) => StatusTimelineStatus(
          code: status.code,
          name: status.nameRu.isNotEmpty ? status.nameRu : status.code,
          color: _parseHexColor(status.color),
          sortOrder: status.sortOrder,
        ),
      )
      .toList(growable: false);
}

/// Парсит HEX цвет из строки
Color? _parseHexColor(String? hexString) {
  if (hexString == null || hexString.isEmpty) return null;
  try {
    String hex = hexString.replaceAll('#', '');
    if (hex.length == 6) {
      hex = 'FF$hex';
    }
    return Color(int.parse(hex, radix: 16));
  } catch (_) {
    return null;
  }
}

String _formatInvoiceAmount(num value) => NumberFormat.decimalPatternDigits(
  locale: 'ru',
  decimalDigits: 2,
).format(value);

String _formatUsdAmount(num value) => '\$${_formatInvoiceAmount(value)}';

bool _isInvoiceUnpaid(InvoiceItem item) {
  final status = item.status.toLowerCase();
  return status == 'unpaid' || status == 'pending';
}

@visibleForTesting
bool canStartInvoicePayment(InvoiceItem item) =>
    item.earlyPaymentBenefit?.requiresSelectionBeforePayment != true;

String _earlyPaymentBenefitTitle(
  BuildContext context,
  EarlyPaymentBenefitType type,
) {
  return switch (type) {
    EarlyPaymentBenefitType.priceLock => tr(
      context,
      ru: 'Защита от изменения таможенных пошлин',
      zh: '海关税费变动保障',
    ),
    EarlyPaymentBenefitType.freeInsurance => tr(
      context,
      ru: 'Бесплатная страховка',
      zh: '免费货物保险',
    ),
    EarlyPaymentBenefitType.bonusKg => tr(
      context,
      ru: 'Бонусные килограммы',
      zh: '奖励公斤数',
    ),
  };
}

IconData _earlyPaymentBenefitIcon(EarlyPaymentBenefitType type) {
  return switch (type) {
    EarlyPaymentBenefitType.priceLock => Icons.lock_outline_rounded,
    EarlyPaymentBenefitType.freeInsurance => Icons.verified_user_outlined,
    EarlyPaymentBenefitType.bonusKg => Icons.scale_outlined,
  };
}

String _earlyPaymentBenefitValue(
  BuildContext context,
  EarlyPaymentBenefitOption option,
) {
  final value = option.projectedValue;
  return switch (option.type) {
    EarlyPaymentBenefitType.priceLock =>
      value.unitRate == null
          ? tr(context, ru: 'Текущая цена доставки', zh: '当前运输价格')
          : '\$${value.unitRate!.toStringAsFixed(2)}/${value.unit == 'm3' ? 'м³' : 'кг'}',
    EarlyPaymentBenefitType.freeInsurance =>
      value.waivedInsuranceUsd == null || value.waivedInsuranceUsd! <= 0
          ? tr(context, ru: 'Страховка за наш счёт', zh: '保险费用由我们承担')
          : tr(
              context,
              ru: 'Экономия \$${value.waivedInsuranceUsd!.toStringAsFixed(2)}',
              zh: '节省 \$${value.waivedInsuranceUsd!.toStringAsFixed(2)}',
            ),
    EarlyPaymentBenefitType.bonusKg =>
      value.bonusKg == null
          ? tr(context, ru: 'Начисление после оплаты', zh: '付款后发放')
          : '+${value.bonusKg!.toStringAsFixed(3)} кг',
  };
}

String _earlyPaymentIdempotencyKey(
  String invoiceId,
  EarlyPaymentBenefitType type,
) {
  final random = Random.secure();
  final nonce = List<int>.generate(
    12,
    (_) => random.nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  return 'early-payment:$invoiceId:${type.serverValue}:$nonce';
}

@visibleForTesting
bool canOpenInvoicePayment(InvoiceItem item) {
  final status = item.status.toLowerCase();
  return (status == 'unpaid' ||
          status == 'pending' ||
          status == 'processing') &&
      item.paymentSummary?.isFullyCovered != true;
}

@visibleForTesting
bool canOpenInvoiceBankQr(InvoiceItem item) {
  final status = item.status.toLowerCase();
  final isPayableStatus =
      status == 'unpaid' ||
      status == 'pending' ||
      status == 'processing' ||
      status == 'payment_review';
  if (!isPayableStatus) return false;

  final paymentSummary = item.paymentSummary;
  if (paymentSummary != null) {
    if (paymentSummary.isPartial) return true;
    if (paymentSummary.isFullyCovered || paymentSummary.isUnknown) return false;
  }

  final hasBankQrPayment =
      item.bankQrPaymentId != null ||
      item.activeTopUp?.isPayableBankQr == true ||
      item.paymentProvider == 'bank_qr' ||
      item.paymentMethod == 'bank_qr';
  return item.bankQrPaymentAvailable ||
      (status == 'processing' && hasBankQrPayment);
}

Future<bool> _requestInvoicePaymentStatus(
  BuildContext context,
  WidgetRef ref,
  InvoiceItem item,
) async {
  final currentOperatorStatus = ref
      .read(paymentOperatorStatusProvider)
      .asData
      ?.value;
  final operatorStatus =
      currentOperatorStatus ??
      await ref.read(paymentOperatorStatusProvider.future) ??
      PaymentOperatorStatus.workingFallback;
  if (!context.mounted) return false;
  if (operatorStatus.sleeping) {
    AppToast.show(
      context,
      tr(
        context,
        ru: 'Операторы оплаты сейчас отдыхают. Все способы оплаты временно недоступны.',
        zh: '支付客服当前休息中，所有支付方式暂时不可用。',
      ),
      isError: true,
    );
    return false;
  }

  final apiClient = ref.read(apiClientProvider);
  final activeCode = ref.read(activeClientCodeProvider);

  void invalidateInvoiceData() {
    if (activeCode != null) {
      ref.invalidate(invoicesListProvider(activeCode));
      ref.invalidate(invoicesDigestProvider(activeCode));
      ref.invalidate(invoicesCountProvider(activeCode));
    }
    ref.invalidate(invoiceByIdProvider(item.id));
  }

  try {
    await requestInvoicePayment(apiClient, item.id);
    if (context.mounted) {
      invalidateInvoiceData();
    }
    return true;
  } on DioException catch (error) {
    if (!context.mounted) return false;

    invalidateInvoiceData();
    final responseData = error.response?.data;
    final operatorsAreSleeping =
        responseData is Map &&
        responseData['reason'] == 'exchange_operators_sleeping';
    AppToast.showFromSnackBar(
      context,
      SnackBar(
        content: Text(
          operatorsAreSleeping
              ? 'Операторы оплаты сейчас отдыхают. Все способы оплаты временно недоступны.'
              : 'Не удалось отправить счёт в обработку',
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.fixed,
      ),
    );
    return false;
  } catch (_) {
    if (!context.mounted) return false;
    invalidateInvoiceData();
    AppToast.showFromSnackBar(
      context,
      SnackBar(
        content: const Text('Не удалось отправить счёт в обработку'),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.fixed,
      ),
    );
    return false;
  }
}

class InvoicesScreen extends ConsumerStatefulWidget {
  final String? initialInvoiceId;
  final String? initialClientCode;

  const InvoicesScreen({
    super.key,
    this.initialInvoiceId,
    this.initialClientCode,
  });

  @override
  ConsumerState<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends ConsumerState<InvoicesScreen> {
  final ScrollController _scrollController = ScrollController();
  String? _selectedStatusCode; // null = "Все"
  String _query = '';

  final GlobalKey _invoicesListKey = GlobalKey();
  final GlobalKey _filtersKey = GlobalKey();
  final GlobalKey _firstInvoiceKey = GlobalKey();
  String? _handledInitialInvoiceId;
  String? _loadingInitialInvoiceId;
  String? _initialClientSwitchTarget;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant InvoicesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialInvoiceId != widget.initialInvoiceId ||
        oldWidget.initialClientCode != widget.initialClientCode) {
      _handledInitialInvoiceId = null;
      _loadingInitialInvoiceId = null;
      _initialClientSwitchTarget = null;
    }
  }

  List<InvoiceItem> _applyFilters(List<InvoiceItem> items) {
    final q = _query.trim().toLowerCase();
    return items.where((inv) {
      // Фильтр по статусу (сравниваем по коду статуса)
      final statusOk =
          _selectedStatusCode == null || inv.status == _selectedStatusCode;
      final queryOk = q.isEmpty
          ? true
          : inv.invoiceNumber.toLowerCase().contains(q) ||
                inv.tariffName?.toLowerCase().contains(q) == true;
      return statusOk && queryOk;
    }).toList();
  }

  String? _clientCodeSwitchTarget(String activeCode) {
    final requested = widget.initialClientCode?.trim();
    if (requested == null || requested.isEmpty) return null;
    if (requested.toUpperCase() == activeCode.toUpperCase()) return null;

    final codesState = ref.watch(clientCodesControllerProvider).asData?.value;
    if (codesState == null) return null;
    for (final code in codesState.codes) {
      if (code.toUpperCase() == requested.toUpperCase()) return code;
    }
    return null;
  }

  void _scheduleInitialClientSwitch(String targetCode) {
    if (_initialClientSwitchTarget == targetCode) return;
    _initialClientSwitchTarget = targetCode;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await ref
          .read(clientCodesControllerProvider.notifier)
          .selectClient(targetCode);
    });
  }

  Future<bool> _selectClientCodeIfAvailable(String? code) async {
    final requested = code?.trim();
    if (requested == null || requested.isEmpty) return false;

    final codesState = ref.read(clientCodesControllerProvider).asData?.value;
    if (codesState == null) return false;
    String? targetCode;
    for (final candidate in codesState.codes) {
      if (candidate.toUpperCase() == requested.toUpperCase()) {
        targetCode = candidate;
        break;
      }
    }
    if (targetCode == null) return false;

    final activeCode = ref.read(activeClientCodeProvider);
    if (activeCode?.toUpperCase() == targetCode.toUpperCase()) return true;

    await ref
        .read(clientCodesControllerProvider.notifier)
        .selectClient(targetCode);
    return true;
  }

  void _maybeOpenInitialInvoice(List<InvoiceItem> items, String clientCode) {
    final invoiceId = widget.initialInvoiceId;
    if (invoiceId == null || invoiceId.isEmpty) return;
    if (_handledInitialInvoiceId == invoiceId) return;

    InvoiceItem? invoice;
    for (final item in items) {
      if (item.id == invoiceId || item.invoiceNumber == invoiceId) {
        invoice = item;
        break;
      }
    }
    if (invoice == null) {
      _loadInitialInvoiceFromApi(invoiceId, clientCode);
      return;
    }

    _handledInitialInvoiceId = invoiceId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openInvoiceDetail(invoice!, clientCode);
    });
  }

  void _loadInitialInvoiceFromApi(String invoiceId, String clientCode) {
    if (_loadingInitialInvoiceId == invoiceId) return;
    _loadingInitialInvoiceId = invoiceId;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || widget.initialInvoiceId != invoiceId) return;
      try {
        final invoice = await ref.read(invoiceByIdProvider(invoiceId).future);
        if (!mounted || widget.initialInvoiceId != invoiceId) return;

        if (invoice == null) {
          _handledInitialInvoiceId = invoiceId;
          return;
        }

        final invoiceClientCode = invoice.clientCode;
        if (invoiceClientCode != null &&
            invoiceClientCode.toUpperCase() != clientCode.toUpperCase() &&
            await _selectClientCodeIfAvailable(invoiceClientCode)) {
          return;
        }

        _handledInitialInvoiceId = invoiceId;
        _openInvoiceDetail(invoice, invoiceClientCode ?? clientCode);
      } catch (e) {
        debugPrint('[InvoicesScreen] Failed to open initial invoice: $e');
      } finally {
        if (_loadingInitialInvoiceId == invoiceId) {
          _loadingInitialInvoiceId = null;
        }
      }
    });
  }

  void _openInvoiceDetail(InvoiceItem item, String clientCode) {
    final referral = ref
        .read(referralProvider)
        .whenOrNull(data: (value) => value);
    final bonusBalance = referral?.referralKgBalance ?? 0;
    final maxBonusPct = referral?.maxBonusPercent ?? 0;

    showBlurredModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (sheetContext) => _InvoiceDetailSheet(
        item: item,
        clientCode: clientCode,
        bonusBalance: bonusBalance,
        maxBonusPercent: maxBonusPct,
        onPay: () {
          Navigator.pop(sheetContext);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _goToPaymentChatFromDigest(item);
          });
        },
        onBonusApplied: () {
          final activeCode = ref.read(activeClientCodeProvider);
          if (activeCode != null) {
            ref.invalidate(invoicesListProvider(activeCode));
          }
          ref.invalidate(referralProvider);
        },
      ),
    );
  }

  Future<void> _goToPaymentChatFromDigest(InvoiceItem item) async {
    if (!mounted) return;
    final paymentRequested = await _requestInvoicePaymentStatus(
      context,
      ref,
      item,
    );
    if (!paymentRequested || !mounted) return;

    final buffer = StringBuffer();
    buffer.writeln('💳 **Запрос на оплату счёта**');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('🆔 ID: ${item.id}');
    buffer.writeln('🔢 Номер: ${item.invoiceNumber}');
    buffer.writeln('📊 Статус: В обработке');
    buffer.writeln('');
    buffer.writeln('💵 К оплате: ${_formatUsdAmount(item.totalCostUsd)}');
    if (item.totalCostCny > 0) {
      buffer.writeln(
        '🇨🇳 К оплате: ¥${_formatInvoiceAmount(item.totalCostCny)}',
      );
    }
    if (item.totalCostRub > 0) {
      buffer.writeln(
        '🇷🇺 К оплате: ${_formatInvoiceAmount(item.totalCostRub)} ₽',
      );
    }

    context.push(
      '/payment-chat',
      extra: {
        'message': buffer.toString(),
        'invoiceId': item.id,
        'invoiceNumber': item.invoiceNumber,
        'amount': item.totalCostUsd,
        if (item.totalCostCny > 0) 'totalCostCny': item.totalCostCny,
        if (item.totalCostRub > 0) 'totalCostRub': item.totalCostRub,
        if (item.clientRubRate != null) 'clientRubRate': item.clientRubRate,
        if (item.clientYuanRate != null) 'clientYuanRate': item.clientYuanRate,
      },
    );
  }

  Future<void> _showInvoiceFiltersSheet(List<InvoiceStatus> statuses) async {
    final result = await showBlurredModalBottomSheet<_InvoiceFiltersResult>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (sheetContext) => _InvoiceFiltersSheet(
        selectedStatusCode: _selectedStatusCode,
        statuses: statuses,
      ),
    );

    if (result == null || !mounted) return;
    setState(() => _selectedStatusCode = result.statusCode);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(activeShellBranchIndexProvider, (previous, next) {
      if (previous == next || next != ShellBranchIndex.invoices) return;
      final activeCode = ref.read(activeClientCodeProvider);
      if (activeCode != null) {
        ref.invalidate(invoicesListProvider(activeCode));
      }
      ref.invalidate(invoiceStatusesProvider);
    });

    final clientCode = ref.watch(activeClientCodeProvider);
    if (clientCode == null) {
      return const EmptyState(
        icon: Icons.badge_outlined,
        title: 'Выберите код клиента',
        message:
            'Чтобы увидеть счета, сначала выберите или добавьте код клиента.',
      );
    }
    final switchTarget = _clientCodeSwitchTarget(clientCode);
    if (switchTarget != null) {
      _scheduleInitialClientSwitch(switchTarget);
      return const Center(child: CircularProgressIndicator());
    }

    final invoicesAsync = ref.watch(invoicesListProvider(clientCode));
    final statusesAsync = ref.watch(invoiceStatusesProvider);
    final bottomPad = AppLayout.bottomScrollPadding(context);
    final topPad = AppLayout.topBarTotalHeight(context);

    Future<void> onRefresh() async {
      debugPrint('[Invoices] pull-to-refresh triggered');
      ref.invalidate(invoicesListProvider(clientCode));
      ref.invalidate(invoiceStatusesProvider);
      await ref.read(invoicesListProvider(clientCode).future);
      debugPrint('[Invoices] pull-to-refresh completed');
    }

    final List<InvoiceStatus> dbStatuses = statusesAsync.when(
      data: (statuses) => statuses,
      loading: () => <InvoiceStatus>[],
      error: (_, _) => <InvoiceStatus>[],
    );

    return invoicesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) {
        final errorInfo = ErrorUtils.getErrorInfo(e);
        return EmptyState(
          icon: errorInfo.icon,
          title: errorInfo.title,
          message: errorInfo.message,
        );
      },
      data: (items) {
        _maybeOpenInitialInvoice(items, clientCode);
        final filtered = _applyFilters(items);
        final firstPayableIndex = filtered.indexWhere(canOpenInvoicePayment);

        return TutorialScreenWrapper(
          screenKey: 'invoices',
          steps: [
            TutorialStep(
              icon: Icons.receipt_long_rounded,
              title: 'Счета на оплату',
              description:
                  'Счёт выставляется после взвешивания посылок на складе в России. Здесь указан точный итог к оплате.',
              targetKey: _invoicesListKey,
            ),
            TutorialStep(
              icon: Icons.info_rounded,
              title: 'Статус счёта',
              description:
                  '«Требует оплаты» — необходимо оплатить, посылка ждёт. «Оплачен» — посылка уже передана в доставку.',
              targetKey: _firstInvoiceKey,
            ),
            TutorialStep(
              icon: Icons.filter_alt_rounded,
              title: 'Фильтр и поиск',
              description:
                  'Фильтруйте счета по статусу или ищите по номеру. Актуально когда счетов накопилось много.',
              targetKey: _filtersKey,
            ),
            TutorialStep(
              icon: Icons.payment_rounded,
              title: 'Оплатить счёт',
              description:
                  'Нажмите на счёт → откроется карточка с деталями. Кнопка «Оплатить» открывает выбор способа оплаты.',
              targetKey: _firstInvoiceKey,
            ),
            TutorialStep(
              icon: Icons.redeem_rounded,
              title: 'Бонусные килограммы',
              description:
                  'Если у вас есть бонусный вес из реферальной программы — нажмите «Применить бонус» перед оплатой. Он вычтется из суммы счёта.',
              targetKey: _firstInvoiceKey,
            ),
          ],
          child: Stack(
            children: [
              RefreshIndicator(
                onRefresh: onRefresh,
                color: context.brandPrimary,
                child: ListView.builder(
                  controller: _scrollController,
                  key: _invoicesListKey,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    16,
                    topPad * 0.7 + 14,
                    16,
                    bottomPad + 16,
                  ),
                  addAutomaticKeepAlives: false,
                  addSemanticIndexes: false,
                  itemCount: filtered.isEmpty ? 4 : filtered.length + 3,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return const _InvoicesHeroHeader();
                    }
                    if (index == 1) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _InvoiceControlsCard(
                          filtersKey: _filtersKey,
                          isFilterActive: _selectedStatusCode != null,
                          query: _query,
                          onFilterTap: () =>
                              _showInvoiceFiltersSheet(dbStatuses),
                          onQueryChanged: (value) =>
                              setState(() => _query = value),
                          onClear: () => setState(() => _query = ''),
                        ),
                      );
                    }
                    if (index == 2) {
                      return const SizedBox(height: 15);
                    }
                    if (filtered.isEmpty) {
                      return const EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'Ничего не найдено',
                        message:
                            'Попробуйте изменить фильтры или строку поиска.',
                      );
                    }

                    final invoiceIndex = index - 3;
                    final invoiceTile = ClientInvoiceTile(
                      item: filtered[invoiceIndex],
                      clientCode: clientCode,
                      trainingTarget: invoiceIndex == 0,
                      trainingPayableTarget: invoiceIndex == firstPayableIndex,
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: invoiceIndex == 0
                          ? KeyedSubtree(
                              key: _firstInvoiceKey,
                              child: invoiceTile,
                            )
                          : invoiceTile,
                    );
                  },
                ),
              ),
              ScrollToTopButton(controller: _scrollController),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

class _InvoicesHeroHeader extends StatelessWidget {
  const _InvoicesHeroHeader();

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(24);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: context.brandGradient,
        borderRadius: radius,
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
        borderRadius: radius,
        child: Stack(
          children: [
            const Positioned.fill(child: _InvoicesHeaderGlowBackdrop()),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(17),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                        child: const Icon(
                          Icons.receipt_long_rounded,
                          color: Colors.white,
                          size: 25,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Счета',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontFamily: 'Gilroy',
                                fontWeight: FontWeight.w900,
                                fontSize: 24,
                                height: 1.04,
                                letterSpacing: -0.35,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Суммы, статусы и понятная расшифровка оплаты',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Color(0xE6FFFFFF),
                                fontFamily: 'Gilroy',
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                height: 1.18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoicesHeaderGlowBackdrop extends StatefulWidget {
  const _InvoicesHeaderGlowBackdrop();

  @override
  State<_InvoicesHeaderGlowBackdrop> createState() =>
      _InvoicesHeaderGlowBackdropState();
}

class _InvoicesHeaderGlowBackdropState
    extends State<_InvoicesHeaderGlowBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final wave = Curves.easeInOutCubic.transform(_controller.value);
            final shift = (wave * 2) - 1;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  right: -62,
                  top: -58,
                  child: Transform.translate(
                    offset: Offset(-10 * shift, 6 * shift),
                    child: _InvoicesHeaderGlowCircle(
                      size: 154,
                      color: Colors.white.withValues(alpha: 0.13),
                    ),
                  ),
                ),
                Positioned(
                  right: 22,
                  bottom: -68,
                  child: Transform.translate(
                    offset: Offset(9 * shift, -7 * shift),
                    child: _InvoicesHeaderGlowCircle(
                      size: 152,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                Positioned(
                  right: -14,
                  bottom: 16,
                  child: Transform.translate(
                    offset: Offset(5 * shift, -4 * shift),
                    child: _InvoicesHeaderGlowCircle(
                      size: 82,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _InvoicesHeaderGlowCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _InvoicesHeaderGlowCircle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _InvoiceControlsCard extends StatelessWidget {
  final GlobalKey filtersKey;
  final bool isFilterActive;
  final String query;
  final VoidCallback onFilterTap;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClear;

  const _InvoiceControlsCard({
    required this.filtersKey,
    required this.isFilterActive,
    required this.query,
    required this.onFilterTap,
    required this.onQueryChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 24,
            spreadRadius: -16,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _InvoiceSearchField(
              query: query,
              onChanged: onQueryChanged,
              onClear: onClear,
            ),
          ),
          const SizedBox(width: 10),
          _InvoiceHeaderIconButton(
            key: filtersKey,
            icon: Icons.filter_alt_rounded,
            tooltip: 'Фильтр',
            isActive: isFilterActive,
            onTap: onFilterTap,
          ),
        ],
      ),
    );
  }
}

class _InvoiceHeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onTap;

  const _InvoiceHeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.brandPrimary;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isActive ? accent : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
            ),
            child: Icon(
              icon,
              size: 22,
              color: isActive ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _InvoiceSearchField extends StatefulWidget {
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _InvoiceSearchField({
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  @override
  State<_InvoiceSearchField> createState() => _InvoiceSearchFieldState();
}

class _InvoiceSearchFieldState extends State<_InvoiceSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query);
  }

  @override
  void didUpdateWidget(covariant _InvoiceSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query && _controller.text != widget.query) {
      _controller.text = widget.query;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppOutlinedInputFrame(
      height: 48,
      radius: 18,
      fillColor: const Color(0xFFF8FAFC),
      borderColor: const Color(0xFFE3E7EE),
      builder: (context, focusNode) => TextField(
        focusNode: focusNode,
        controller: _controller,
        style: const TextStyle(
          fontFamily: 'Gilroy',
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: 0,
        ),
        decoration: InputDecoration(
          prefixIcon: focusNode.hasFocus
              ? null
              : Icon(
                  Icons.search_rounded,
                  color: context.brandPrimary,
                  size: 22,
                ),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _controller.clear();
                    setState(() {});
                    widget.onClear();
                  },
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                )
              : null,
          hintText: 'Поиск по счёту',
          hintStyle: const TextStyle(
            fontFamily: 'Gilroy',
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            letterSpacing: 0,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.fromLTRB(
            focusNode.hasFocus ? 16 : 0,
            14,
            12,
            14,
          ),
          isDense: true,
        ),
        onChanged: (value) {
          setState(() {});
          widget.onChanged(value);
        },
      ),
    );
  }
}

class _InvoiceSheetSurface extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? pinnedChild;
  final Widget? footer;
  final bool keyboardAware;

  const _InvoiceSheetSurface({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.pinnedChild,
    this.footer,
    this.keyboardAware = false,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final keyboardInset = keyboardAware
        ? MediaQuery.viewInsetsOf(context).bottom
        : 0.0;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.92,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: SizedBox(
                  width: 42,
                  child: TrainingTarget(
                    id: 'invoice.sheet.dismiss',
                    onActivate: () => Navigator.of(context).pop(),
                    child: const SheetHandle(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: _InvoiceSheetHeader(
                  icon: icon,
                  title: title,
                  subtitle: subtitle,
                ),
              ),
              if (pinnedChild != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: pinnedChild,
                ),
              Flexible(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: child,
                  ),
                ),
              ),
              if (footer != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + bottomPadding),
                  child: footer,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvoiceSheetHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InvoiceSheetHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: context.brandGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: context.brandPrimary.withValues(alpha: 0.18),
            blurRadius: 22,
            spreadRadius: -12,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Gilroy',
                    fontSize: 21,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.25,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xE6FFFFFF),
                    fontFamily: 'Gilroy',
                    fontSize: 12.8,
                    height: 1.15,
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

class _InvoiceSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _InvoiceSectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: context.brandPrimary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: context.brandPrimary, size: 17),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 14.5,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.05,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _InvoicePrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _InvoicePrimaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 50,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: enabled ? context.brandGradient : null,
            color: enabled ? null : const Color(0xFFE9ECEF),
            borderRadius: BorderRadius.circular(18),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: context.brandPrimary.withValues(alpha: 0.18),
                      blurRadius: 18,
                      spreadRadius: -10,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Gilroy',
                    fontSize: 14.5,
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

class _InvoiceSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _InvoiceSecondaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 50,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: context.brandPrimary.withValues(alpha: 0.34),
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.brandPrimary,
              fontFamily: 'Gilroy',
              fontSize: 14.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _InvoiceFiltersResult {
  final String? statusCode;

  const _InvoiceFiltersResult(this.statusCode);
}

class _InvoiceStatusOption {
  final String? code;
  final String label;

  const _InvoiceStatusOption({required this.code, required this.label});
}

class _InvoiceFiltersSheet extends StatefulWidget {
  final String? selectedStatusCode;
  final List<InvoiceStatus> statuses;

  const _InvoiceFiltersSheet({
    required this.selectedStatusCode,
    required this.statuses,
  });

  @override
  State<_InvoiceFiltersSheet> createState() => _InvoiceFiltersSheetState();
}

class _InvoiceFiltersSheetState extends State<_InvoiceFiltersSheet> {
  late String? _statusCode = widget.selectedStatusCode;

  @override
  Widget build(BuildContext context) {
    final options = <_InvoiceStatusOption>[
      const _InvoiceStatusOption(code: null, label: 'Все'),
      ...widget.statuses.map(
        (status) =>
            _InvoiceStatusOption(code: status.code, label: status.nameRu),
      ),
    ];

    return _InvoiceSheetSurface(
      icon: Icons.filter_alt_rounded,
      title: 'Фильтр',
      subtitle: 'Выберите нужный статус счёта',
      footer: Row(
        children: [
          Expanded(
            child: _InvoiceSecondaryButton(
              label: 'Сбросить',
              onTap: () =>
                  Navigator.pop(context, const _InvoiceFiltersResult(null)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _InvoicePrimaryButton(
              label: 'Применить',
              icon: Icons.check_rounded,
              onTap: () =>
                  Navigator.pop(context, _InvoiceFiltersResult(_statusCode)),
            ),
          ),
        ],
      ),
      child: _InvoiceSectionCard(
        icon: Icons.flag_rounded,
        title: 'Статус счёта',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              _InvoiceFilterChip(
                label: option.label,
                selected: option.code == _statusCode,
                onTap: () => setState(() => _statusCode = option.code),
              ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _InvoiceFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.brandPrimary;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? accent : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? accent : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check_rounded, color: Colors.white, size: 15),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.textPrimary,
                  fontFamily: 'Gilroy',
                  fontSize: 13,
                  height: 1,
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

class _InvoiceDetailSummaryCard extends StatelessWidget {
  final InvoiceItem item;

  const _InvoiceDetailSummaryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final amountUsd = _formatUsdAmount(item.totalCostUsd);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Стоимость в долларах',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Gilroy',
              fontSize: 11.5,
              height: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          TrainingTarget(
            id: 'invoice.amount',
            child: Text(
              amountUsd,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontFamily: 'Gilroy',
                fontSize: 31,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.65,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _InvoiceSmallAmount(
                  label: 'Стоимость в рублях',
                  value: item.totalCostRub > 0
                      ? '${_formatInvoiceAmount(item.totalCostRub)} ₽'
                      : '—',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _InvoiceSmallAmount(
                  label: 'Стоимость в юанях',
                  value: item.totalCostCny > 0
                      ? '¥${_formatInvoiceAmount(item.totalCostCny)}'
                      : '—',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InvoiceSmallAmount extends StatelessWidget {
  final String label;
  final String value;

  const _InvoiceSmallAmount({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
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
              fontSize: 10.5,
              height: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Gilroy',
              fontSize: 14,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Карточка счёта в списке ──────────────────────────────────────────────────

class ClientInvoiceTile extends ConsumerStatefulWidget {
  final InvoiceItem item;
  final String clientCode;
  final bool trainingTarget;
  final bool trainingPayableTarget;

  const ClientInvoiceTile({
    super.key,
    required this.item,
    required this.clientCode,
    this.trainingTarget = false,
    this.trainingPayableTarget = false,
  });

  @override
  ConsumerState<ClientInvoiceTile> createState() => ClientInvoiceTileState();
}

class ClientInvoiceTileState extends ConsumerState<ClientInvoiceTile> {
  bool _isNavigatingToPayment = false;

  void _showInvoiceStatusTimeline(
    BuildContext context,
    List<InvoiceStatus> statuses,
  ) {
    final item = widget.item;
    showStatusTimelineSheet(
      context: context,
      title: 'Статус счёта',
      currentStatusCode: item.status,
      currentStatusName: item.statusName ?? item.status,
      currentStatusColor: _parseHexColor(item.statusColor),
      history: item.statusHistory,
      statuses: _invoiceTimelineStatuses(statuses),
    );
  }

  void _openDetail(
    BuildContext context,
    double bonusBalance,
    double maxBonusPct,
  ) {
    showBlurredModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (sheetContext) => _InvoiceDetailSheet(
        item: widget.item,
        clientCode: widget.clientCode,
        bonusBalance: bonusBalance,
        maxBonusPercent: maxBonusPct,
        onPay: () {
          Navigator.pop(sheetContext);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _goToPayment(context);
          });
        },
        onBonusApplied: () {
          final clientCode = ref.read(activeClientCodeProvider);
          if (clientCode != null) {
            ref.invalidate(invoicesListProvider(clientCode));
          }
          ref.invalidate(referralProvider);
        },
      ),
    );
  }

  Future<void> _goToPayment(BuildContext context) async {
    if (_isNavigatingToPayment) return;
    _isNavigatingToPayment = true;

    final item = widget.item;
    final paymentRequested = await _requestInvoicePaymentStatus(
      context,
      ref,
      item,
    );
    if (!paymentRequested) {
      if (mounted) setState(() => _isNavigatingToPayment = false);
      return;
    }
    if (!mounted) return;

    // Ensure payment TG config is loaded before navigating
    String? paymentTgUsername = ref
        .read(paymentTgUsernameProvider)
        .whenOrNull(data: (v) => v);
    if (paymentTgUsername == null) {
      try {
        paymentTgUsername = await ref.read(paymentTgUsernameProvider.future);
      } catch (_) {}
      if (!mounted) return;
    }
    if (paymentTgUsername != null && paymentTgUsername.isNotEmpty) {
      final text = Uri.encodeComponent(
        'Добрый день! Хочу оплатить счет ${item.invoiceNumber}',
      );
      final tgUrl = 'tg://resolve?domain=$paymentTgUsername&text=$text';
      final webUrl = 'https://t.me/$paymentTgUsername';

      launchUrl(Uri.parse(tgUrl), mode: LaunchMode.externalApplication)
          .then((_) {
            if (mounted) setState(() => _isNavigatingToPayment = false);
          })
          .catchError((_) {
            launchUrl(
              Uri.parse(webUrl),
              mode: LaunchMode.externalApplication,
            ).whenComplete(() {
              if (mounted) setState(() => _isNavigatingToPayment = false);
            });
          });
      return;
    }

    // Fallback: in-app payment chat
    if (!context.mounted) return;
    _goToPaymentChat(context);
  }

  void _goToPaymentChat(BuildContext context) {
    if (!mounted) return;
    final item = widget.item;
    final buffer = StringBuffer();
    buffer.writeln('💳 **Запрос на оплату счёта**');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('🆔 ID: ${item.id}');
    buffer.writeln('🔢 Номер: ${item.invoiceNumber}');
    buffer.writeln('📊 Статус: В обработке');
    buffer.writeln('');
    buffer.writeln('💵 К оплате: ${_formatUsdAmount(item.totalCostUsd)}');
    if (item.totalCostCny > 0) {
      buffer.writeln(
        '🇨🇳 К оплате: ¥${_formatInvoiceAmount(item.totalCostCny)}',
      );
    }
    if (item.totalCostRub > 0) {
      buffer.writeln(
        '🇷🇺 К оплате: ${_formatInvoiceAmount(item.totalCostRub)} ₽',
      );
    }
    if (item.clientRubRate != null ||
        item.clientCnyRubRate != null ||
        item.clientYuanRate != null) {
      buffer.writeln('');
      if (item.clientRubRate != null) {
        buffer.writeln(
          '📈 Курс \$/₽: ${item.clientRubRate!.toStringAsFixed(2)}',
        );
      }
      if (item.clientCnyRubRate != null) {
        buffer.writeln(
          '📈 Курс RMB/₽: ${item.clientCnyRubRate!.toStringAsFixed(4)}',
        );
      } else if (item.clientYuanRate != null) {
        buffer.writeln(
          '📈 Курс \$/¥: ${item.clientYuanRate!.toStringAsFixed(2)}',
        );
      }
    }

    context
        .push(
          '/payment-chat',
          extra: {
            'message': buffer.toString(),
            'invoiceId': item.id,
            'invoiceNumber': item.invoiceNumber,
            'amount': item.totalCostUsd,
            if (item.totalCostCny > 0) 'totalCostCny': item.totalCostCny,
            if (item.totalCostRub > 0) 'totalCostRub': item.totalCostRub,
            if (item.clientRubRate != null) 'clientRubRate': item.clientRubRate,
            if (item.clientYuanRate != null)
              'clientYuanRate': item.clientYuanRate,
          },
        )
        .whenComplete(() {
          if (mounted) {
            setState(() => _isNavigatingToPayment = false);
            // Обновляем список счетов после возврата из чата оплаты
            final clientCode = ref.read(activeClientCodeProvider);
            if (clientCode != null) {
              ref.invalidate(invoicesListProvider(clientCode));
            }
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isPartial = item.paymentSummary?.isPartial == true;
    final statusColor = isPartial
        ? const Color(0xFFD97706)
        : _parseHexColor(item.statusColor);
    final statusText = isPartial
        ? tr(context, ru: 'Частично оплачено', zh: '部分付款')
        : item.statusName ?? item.status;
    final referralAsync = ref.watch(referralProvider);
    final invoiceStatuses =
        ref.watch(invoiceStatusesProvider).asData?.value ??
        const <InvoiceStatus>[];

    final double bonusBalance =
        referralAsync.whenOrNull(data: (r) => r.referralKgBalance) ?? 0;
    final double maxBonusPct =
        referralAsync.whenOrNull(data: (r) => r.maxBonusPercent) ?? 0;

    final createdText = _formatListDate(item.createdAt);
    final updatedAt =
        item.updatedAt ??
        item.paidAt ??
        item.sendDate ??
        item.arrivalDate ??
        item.createdAt;
    final updatedText = _formatListDate(updatedAt);

    final amountUsdText = _formatUsdAmount(item.totalCostUsd);
    final earlyPaymentBenefit = item.earlyPaymentBenefit;
    void openDetail() => _openDetail(context, bonusBalance, maxBonusPct);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: openDetail,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 24,
                spreadRadius: -16,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: context.brandPrimary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      Icons.receipt_long_rounded,
                      color: context.brandPrimary,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Номер счёта',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontFamily: 'Gilroy',
                            fontSize: 11.5,
                            height: 1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        TrainingTarget(
                          id: widget.trainingTarget
                              ? 'invoice.open'
                              : 'invoice.open.${item.id}',
                          onActivate: openDetail,
                          child: TrainingTarget(
                            id: widget.trainingPayableTarget
                                ? 'invoice.open-payable'
                                : 'invoice.open-payable.${item.id}',
                            onActivate: openDetail,
                            child: Text(
                              item.invoiceNumber,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Gilroy',
                                fontSize: 19,
                                height: 1.04,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.25,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        _showInvoiceStatusTimeline(context, invoiceStatuses),
                    child: _InvoiceCardStatusPill(
                      text: statusText,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: context.brandPrimary.withValues(alpha: 0.055),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: context.brandPrimary.withValues(alpha: 0.10),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: context.brandPrimary.withValues(alpha: 0.11),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        Icons.attach_money_rounded,
                        color: context.brandPrimary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: const Text(
                        'Итого к оплате',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontFamily: 'Gilroy',
                          fontSize: 13,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      amountUsdText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Gilroy',
                        fontSize: 25,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (earlyPaymentBenefit != null)
                    EarlyPaymentBenefitPill(benefit: earlyPaymentBenefit),
                  _InvoiceDateMeta(
                    icon: CupertinoIcons.plus_circle,
                    label: createdText,
                  ),
                  _InvoiceDateMeta(
                    icon: CupertinoIcons.arrow_2_circlepath_circle,
                    label: updatedText,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatListDate(DateTime? date) {
    if (date == null) return '--.--.--';
    return DateFormat('dd.MM.yy', 'ru').format(date);
  }
}

class _InvoiceDateMeta extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InvoiceDateMeta({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(width: 1),
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontFamily: 'Gilroy',
            fontSize: 12,
            height: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class EarlyPaymentBenefitPill extends StatefulWidget {
  final EarlyPaymentBenefit benefit;

  const EarlyPaymentBenefitPill({super.key, required this.benefit});

  @override
  State<EarlyPaymentBenefitPill> createState() =>
      _EarlyPaymentBenefitPillState();
}

class _EarlyPaymentBenefitPillState extends State<EarlyPaymentBenefitPill> {
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    _scheduleExpiry();
  }

  @override
  void didUpdateWidget(covariant EarlyPaymentBenefitPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.benefit.expiresAt != widget.benefit.expiresAt ||
        oldWidget.benefit.selectedType != widget.benefit.selectedType) {
      _scheduleExpiry();
    }
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    if (widget.benefit.selectedType != null ||
        !widget.benefit.isSelectionWindowOpen) {
      return;
    }
    _expiryTimer = Timer(
      widget.benefit.timeUntilSelectionCloses +
          const Duration(milliseconds: 25),
      () {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final benefit = widget.benefit;
    final selectedType = benefit.selectedType;
    final label = selectedType == null
        ? !benefit.isSelectionWindowOpen ||
                  benefit.state == EarlyPaymentBenefitState.expired
              ? tr(context, ru: 'Бонус истёк', zh: '优惠已过期')
              : benefit.state == EarlyPaymentBenefitState.cancelled
              ? tr(context, ru: 'Предложение отменено', zh: '优惠已取消')
              : benefit.state == EarlyPaymentBenefitState.reversed
              ? tr(context, ru: 'Бонус отменён', zh: '优惠已撤销')
              : tr(context, ru: 'Выберите бонус', zh: '选择优惠')
        : _earlyPaymentBenefitTitle(context, selectedType);
    final accent =
        !benefit.isSelectionWindowOpen ||
            benefit.state == EarlyPaymentBenefitState.expired ||
            benefit.state == EarlyPaymentBenefitState.cancelled ||
            benefit.state == EarlyPaymentBenefitState.reversed
        ? AppColors.textSecondary
        : context.brandPrimary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.card_giftcard_rounded, size: 14, color: accent),
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

class EarlyPaymentBenefitCard extends StatelessWidget {
  final EarlyPaymentBenefit benefit;
  final bool selecting;
  final VoidCallback? onChoose;

  const EarlyPaymentBenefitCard({
    super.key,
    required this.benefit,
    required this.selecting,
    required this.onChoose,
  });

  @override
  Widget build(BuildContext context) {
    final selectedOption = benefit.selectedOption;
    final options = selectedOption != null
        ? <EarlyPaymentBenefitOption>[selectedOption]
        : benefit.isSelectionWindowOpen
        ? benefit.options.where((option) => option.enabled).toList()
        : const <EarlyPaymentBenefitOption>[];
    final deadline = benefit.expiresAt;

    return _InvoiceSectionCard(
      icon: Icons.card_giftcard_rounded,
      title: tr(context, ru: 'Бонус за быструю оплату', zh: '快速付款优惠'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _earlyPaymentBenefitStateText(context, benefit),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Gilroy',
              fontSize: 13.5,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (deadline != null &&
              benefit.isSelectionWindowOpen &&
              (benefit.state == EarlyPaymentBenefitState.available ||
                  benefit.state ==
                      EarlyPaymentBenefitState.selectionRequired)) ...[
            const SizedBox(height: 6),
            Text(
              benefit.hasTimelyEvidence
                  ? tr(
                      context,
                      ru: 'Чек загружен вовремя. Выберите бонус до ${DateFormat('dd.MM.yyyy HH:mm').format(deadline.toLocal())}',
                      zh: '付款凭证已按时上传，请在 ${DateFormat('dd.MM.yyyy HH:mm').format(deadline.toLocal())} 前选择优惠',
                    )
                  : tr(
                      context,
                      ru: 'Выбор доступен до ${DateFormat('dd.MM.yyyy HH:mm').format(deadline.toLocal())}',
                      zh: '可选择至 ${DateFormat('dd.MM.yyyy HH:mm').format(deadline.toLocal())}',
                    ),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Gilroy',
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (options.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...options.map(
              (option) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: _EarlyPaymentBenefitOptionSummary(option: option),
              ),
            ),
          ],
          if (onChoose != null) ...[
            const SizedBox(height: 4),
            _InvoicePrimaryButton(
              label: selecting
                  ? tr(context, ru: 'Сохраняем…', zh: '正在保存…')
                  : tr(context, ru: 'Выбрать бонус', zh: '选择优惠'),
              icon: Icons.touch_app_rounded,
              onTap: selecting ? null : onChoose,
            ),
          ],
        ],
      ),
    );
  }
}

class _EarlyPaymentBenefitOptionSummary extends StatelessWidget {
  final EarlyPaymentBenefitOption option;

  const _EarlyPaymentBenefitOptionSummary({required this.option});

  @override
  Widget build(BuildContext context) {
    final enabled = option.available;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: enabled
            ? context.brandPrimary.withValues(alpha: 0.055)
            : const Color(0xFFF1F3F5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            _earlyPaymentBenefitIcon(option.type),
            size: 19,
            color: enabled ? context.brandPrimary : AppColors.textSecondary,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _earlyPaymentBenefitTitle(context, option.type),
                  style: TextStyle(
                    color: enabled
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontFamily: 'Gilroy',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  enabled
                      ? _earlyPaymentBenefitValue(context, option)
                      : _earlyPaymentUnavailableText(
                          context,
                          option.unavailableReason,
                        ),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'Gilroy',
                    fontSize: 11.5,
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

class _EarlyPaymentBenefitChoiceTile extends StatelessWidget {
  final EarlyPaymentBenefitOption option;
  final bool selected;
  final VoidCallback? onTap;

  const _EarlyPaymentBenefitChoiceTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: selected
                ? context.brandPrimary.withValues(alpha: 0.09)
                : option.available
                ? const Color(0xFFF8FAFC)
                : const Color(0xFFF1F3F5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? context.brandPrimary.withValues(alpha: 0.42)
                  : Colors.black.withValues(alpha: 0.04),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: context.brandPrimary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _earlyPaymentBenefitIcon(option.type),
                  color: option.available
                      ? context.brandPrimary
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _earlyPaymentBenefitTitle(context, option.type),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Gilroy',
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      option.available
                          ? _earlyPaymentBenefitValue(context, option)
                          : _earlyPaymentUnavailableText(
                              context,
                              option.unavailableReason,
                            ),
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
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: option.available
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

String _earlyPaymentBenefitStateText(
  BuildContext context,
  EarlyPaymentBenefit benefit,
) {
  final selected = benefit.selectedType;
  if (selected == null &&
      !benefit.isSelectionWindowOpen &&
      (benefit.state == EarlyPaymentBenefitState.available ||
          benefit.state == EarlyPaymentBenefitState.selectionRequired)) {
    return tr(context, ru: 'Срок выбора бонуса истёк.', zh: '优惠选择期限已过。');
  }
  return switch (benefit.state) {
    EarlyPaymentBenefitState.available => tr(
      context,
      ru: 'Выберите один бонус до начала оплаты. После выбора изменить его нельзя.',
      zh: '付款前请选择一项优惠，确认后不可更改。',
    ),
    EarlyPaymentBenefitState.selectionRequired =>
      benefit.hasTimelyEvidence
          ? tr(
              context,
              ru: 'Чек загружен вовремя. Выберите бонус — после этого мы продолжим проверку оплаты.',
              zh: '付款凭证已按时上传。请选择优惠，以便继续审核付款。',
            )
          : tr(
              context,
              ru: 'Оплата ожидает распределения. Сначала выберите бонус.',
              zh: '付款正在等待匹配，请先选择优惠。',
            ),
    EarlyPaymentBenefitState.selected => tr(
      context,
      ru: 'Выбран бонус «${selected == null ? '—' : _earlyPaymentBenefitTitle(context, selected)}». Он зафиксирован в счёте.',
      zh: '已选择“${selected == null ? '—' : _earlyPaymentBenefitTitle(context, selected)}”，并已记录到账单。',
    ),
    EarlyPaymentBenefitState.applied => tr(
      context,
      ru: 'Бонус применён и зафиксирован в оплаченной накладной.',
      zh: '优惠已生效并记录在已付款账单中。',
    ),
    EarlyPaymentBenefitState.expired => tr(
      context,
      ru: 'Срок выбора бонуса истёк.',
      zh: '优惠选择期限已过。',
    ),
    EarlyPaymentBenefitState.cancelled => tr(
      context,
      ru: 'Предложение бонуса отменено.',
      zh: '优惠已取消。',
    ),
    EarlyPaymentBenefitState.reversed => tr(
      context,
      ru: 'Бонус отменён после возврата оплаты. История сохранена.',
      zh: '付款撤销后优惠已撤销，历史记录已保留。',
    ),
    EarlyPaymentBenefitState.unknown => tr(
      context,
      ru: 'Статус бонуса обновляется.',
      zh: '优惠状态正在更新。',
    ),
  };
}

String _earlyPaymentUnavailableText(BuildContext context, String? reason) {
  return switch (reason) {
    'insurance_value_missing' => tr(
      context,
      ru: 'В счёте не указана страховая стоимость',
      zh: '账单中未填写保险价值',
    ),
    'insurance_limit_exceeded' => tr(
      context,
      ru: 'Страховая стоимость выше лимита предложения',
      zh: '保险价值超过优惠限额',
    ),
    _ => tr(context, ru: 'Недоступно для этого счёта', zh: '此账单不可用'),
  };
}

class _InvoiceCardStatusPill extends StatelessWidget {
  final String text;
  final Color? color;

  const _InvoiceCardStatusPill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final accent = color ?? context.brandPrimary;
    final isLight = accent.computeLuminance() > 0.58;
    final bg = isLight
        ? accent.withValues(alpha: 0.42)
        : accent.withValues(alpha: 0.12);
    final textColor = isLight ? AppColors.textPrimary : accent;

    return Container(
      constraints: const BoxConstraints(minHeight: 26, maxWidth: 96),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.20)),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Gilroy',
          fontSize: 11.6,
          height: 1,
          fontWeight: FontWeight.w900,
          color: textColor,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _InvoicePaymentReviewBanner extends StatelessWidget {
  const _InvoicePaymentReviewBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.brandPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.brandPrimary.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: context.brandPrimary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              Icons.hourglass_top_rounded,
              color: context.brandPrimary,
              size: 18,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, ru: 'Оплата на проверке', zh: '付款正在审核'),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 14.5,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(
                    context,
                    ru: 'Ваша оплата в обработке. Как только мы подтвердим платёж, статус счёта изменится на «Оплачен».',
                    zh: '您的付款正在处理中。我们确认付款后，账单状态将变为“已付款”。',
                  ),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'Gilroy',
                    fontSize: 12.8,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
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

class _InvoiceBankQrRateBanner extends StatelessWidget {
  const _InvoiceBankQrRateBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4EF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.brandPrimary.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: context.brandPrimary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              Icons.currency_exchange_rounded,
              color: context.brandPrimary,
              size: 18,
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
                    ru: 'Оплата в рублях временно недоступна',
                    zh: '卢布支付暂不可用',
                  ),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 14.5,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(
                    context,
                    ru: 'Оплатить счёт в рублях можно будет после обновления курса валют на текущий день. Пока можно выбрать оплату через менеджера.',
                    zh: '当天汇率更新后即可使用卢布支付。目前可选择通过经理付款。',
                  ),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'Gilroy',
                    fontSize: 12.8,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
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

// ─── Детальный лист счёта ─────────────────────────────────────────────────────

class _InvoiceDetailSheet extends ConsumerStatefulWidget {
  final InvoiceItem item;
  final String clientCode;
  final double bonusBalance;
  final double maxBonusPercent;
  final VoidCallback onPay;
  final VoidCallback onBonusApplied;

  const _InvoiceDetailSheet({
    required this.item,
    required this.clientCode,
    required this.bonusBalance,
    required this.maxBonusPercent,
    required this.onPay,
    required this.onBonusApplied,
  });

  @override
  ConsumerState<_InvoiceDetailSheet> createState() =>
      _InvoiceDetailSheetState();
}

class _InvoiceDetailSheetState extends ConsumerState<_InvoiceDetailSheet> {
  final _bonusKgCtrl = TextEditingController();
  final Map<EarlyPaymentBenefitType, String> _selectionKeys = {};
  bool _isApplyingBonus = false;
  bool _isSelectingEarlyPaymentBenefit = false;
  EarlyPaymentBenefit? _selectedBenefitOverride;
  Timer? _earlyPaymentExpiryTimer;
  NavigatorState? _benefitChoiceNavigator;
  DateTime? _scheduledBenefitExpiry;

  @override
  void initState() {
    super.initState();
    _scheduleBenefitExpiry(widget.item.earlyPaymentBenefit);
  }

  @override
  void dispose() {
    _earlyPaymentExpiryTimer?.cancel();
    _bonusKgCtrl.dispose();
    super.dispose();
  }

  void _scheduleBenefitExpiry(EarlyPaymentBenefit? benefit) {
    final expiry = benefit?.expiresAt;
    if (benefit == null ||
        benefit.selectedType != null ||
        !benefit.isSelectionWindowOpen) {
      _earlyPaymentExpiryTimer?.cancel();
      _scheduledBenefitExpiry = expiry;
      return;
    }
    if (_scheduledBenefitExpiry == expiry &&
        _earlyPaymentExpiryTimer?.isActive == true) {
      return;
    }
    _earlyPaymentExpiryTimer?.cancel();
    _scheduledBenefitExpiry = expiry;
    _earlyPaymentExpiryTimer = Timer(
      benefit.timeUntilSelectionCloses + const Duration(milliseconds: 25),
      () {
        if (!mounted) return;
        final navigator = _benefitChoiceNavigator;
        _benefitChoiceNavigator = null;
        if (navigator?.canPop() == true) navigator!.pop(false);
        setState(() {});
        _invalidateInvoiceData();
      },
    );
  }

  InvoiceItem get _currentItem =>
      ref.read(invoiceByIdProvider(widget.item.id)).asData?.value ??
      widget.item;

  EarlyPaymentBenefit? _benefitFor(InvoiceItem item) {
    final current = item.earlyPaymentBenefit;
    if (current?.selectedType != null || _selectedBenefitOverride == null) {
      return current;
    }
    return _selectedBenefitOverride;
  }

  void _invalidateInvoiceData() {
    final activeCode = ref.read(activeClientCodeProvider);
    if (activeCode != null) {
      ref.invalidate(invoicesListProvider(activeCode));
      ref.invalidate(invoicesDigestProvider(activeCode));
      ref.invalidate(invoicesCountProvider(activeCode));
    }
    ref.invalidate(invoiceByIdProvider(widget.item.id));
  }

  Future<bool> _selectBenefit(EarlyPaymentBenefitType type) async {
    if (_isSelectingEarlyPaymentBenefit) return false;
    final currentBenefit = _benefitFor(_currentItem);
    if (currentBenefit == null || !currentBenefit.canSelect) {
      AppToast.show(
        context,
        tr(context, ru: 'Срок выбора бонуса истёк', zh: '优惠选择期限已结束'),
        isError: true,
      );
      return false;
    }
    setState(() => _isSelectingEarlyPaymentBenefit = true);
    try {
      final benefit = await selectEarlyPaymentBenefit(
        ref.read(apiClientProvider),
        invoiceId: widget.item.id,
        benefitType: type,
        idempotencyKey: _selectionKeys.putIfAbsent(
          type,
          () => _earlyPaymentIdempotencyKey(widget.item.id, type),
        ),
      );
      if (!mounted) return false;
      setState(() => _selectedBenefitOverride = benefit);
      _scheduleBenefitExpiry(benefit);
      _invalidateInvoiceData();
      AppToast.show(
        context,
        tr(context, ru: 'Бонус выбран и сохранён в счёте', zh: '优惠已选择并保存到账单'),
      );
      return !benefit.requiresSelectionBeforePayment;
    } on DioException catch (error) {
      if (!mounted) return false;
      final responseData = error.response?.data;
      final message = responseData is Map
          ? responseData['error']?.toString()
          : null;
      AppToast.show(
        context,
        message?.isNotEmpty == true
            ? message!
            : tr(
                context,
                ru: 'Не удалось сохранить бонус. Попробуйте ещё раз.',
                zh: '无法保存优惠，请重试。',
              ),
        isError: true,
      );
      return false;
    } on FormatException {
      if (!mounted) return false;
      AppToast.show(
        context,
        tr(
          context,
          ru: 'Сервер вернул неполные данные. Обновите счёт и повторите.',
          zh: '服务器返回的数据不完整，请刷新账单后重试。',
        ),
        isError: true,
      );
      return false;
    } finally {
      if (mounted) setState(() => _isSelectingEarlyPaymentBenefit = false);
    }
  }

  Future<bool> _ensureEarlyPaymentBenefitSelected(InvoiceItem item) async {
    final benefit = _benefitFor(item);
    if (benefit?.requiresSelectionBeforePayment != true) return true;
    if (benefit == null || !benefit.canSelect) {
      AppToast.show(
        context,
        tr(
          context,
          ru: 'Сначала обновите счёт, чтобы выбрать бонус перед оплатой.',
          zh: '请先刷新账单，然后在付款前选择优惠。',
        ),
        isError: true,
      );
      return false;
    }
    await _showEarlyPaymentBenefitChoice(benefit);
    // Choosing a benefit is a separate, visible step. Keep the invoice open
    // so the client can review the saved choice before starting payment.
    return false;
  }

  Future<bool?> _showEarlyPaymentBenefitChoice(EarlyPaymentBenefit benefit) {
    if (!benefit.canSelect) return Future<bool?>.value(false);
    EarlyPaymentBenefitType? selectedType;
    _scheduleBenefitExpiry(benefit);
    final result = showBlurredModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (sheetContext) {
        _benefitChoiceNavigator = Navigator.of(sheetContext);
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) => _InvoiceSheetSurface(
            icon: Icons.card_giftcard_rounded,
            title: tr(sheetContext, ru: 'Выберите бонус', zh: '选择优惠'),
            subtitle: tr(
              sheetContext,
              ru: 'Один бонус за быструю оплату',
              zh: '快速付款可选一项优惠',
            ),
            footer: _InvoicePrimaryButton(
              label: _isSelectingEarlyPaymentBenefit
                  ? tr(sheetContext, ru: 'Сохраняем…', zh: '正在保存…')
                  : tr(sheetContext, ru: 'Выбрать бонус', zh: '确认选择'),
              icon: Icons.check_rounded,
              onTap: selectedType == null || _isSelectingEarlyPaymentBenefit
                  ? null
                  : () async {
                      final saved = await _selectBenefit(selectedType!);
                      if (!sheetContext.mounted) return;
                      if (saved) Navigator.of(sheetContext).pop(true);
                    },
            ),
            child: Column(
              children: benefit.options
                  .where((option) => option.enabled)
                  .map(
                    (option) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _EarlyPaymentBenefitChoiceTile(
                        option: option,
                        selected: selectedType == option.type,
                        onTap: option.available
                            ? () => setSheetState(() {
                                selectedType = option.type;
                              })
                            : null,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        );
      },
    );
    return result.whenComplete(() => _benefitChoiceNavigator = null);
  }

  Future<void> _openInvoicePayment() async {
    final item = _currentItem;
    if (!await _ensureEarlyPaymentBenefitSelected(item)) return;
    if (!mounted) return;
    if (!await _ensurePaymentOperatorsWorking()) return;
    if (!mounted) return;
    final invoiceNavigator = Navigator.of(context);
    while (mounted) {
      final selection =
          await showBlurredModalBottomSheet<InvoicePaymentSelection>(
            context: context,
            useRootNavigator: true,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.transparent,
            builder: (_) => InvoicePaymentMethodSheet(invoiceId: item.id),
          );
      if (!mounted || selection == null) return;
      _invalidateInvoiceData();
      if (selection.method == 'manager') {
        widget.onPay();
        return;
      }
      var changeRequested = false;
      final changed = await showBlurredModalBottomSheet<bool>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.22),
        builder: (paymentContext) => BankQrPaymentSheet(
          invoiceId: item.id,
          invoiceNumber: item.invoiceNumber,
          selection: selection,
          onChangeMethod: selection.canChange
              ? () {
                  changeRequested = true;
                  Navigator.of(paymentContext).pop(false);
                }
              : null,
        ),
      );
      if (!mounted) return;
      _invalidateInvoiceData();
      if (changed == true) {
        widget.onBonusApplied();
        invoiceNavigator.pop();
        return;
      }
      if (!changeRequested) return;
    }
  }

  Future<bool> _ensurePaymentOperatorsWorking() async {
    final current = ref.read(paymentOperatorStatusProvider).asData?.value;
    final status =
        current ??
        await ref.read(paymentOperatorStatusProvider.future) ??
        PaymentOperatorStatus.workingFallback;
    if (status.working) return true;
    if (mounted) {
      AppToast.show(
        context,
        tr(
          context,
          ru: 'Операторы оплаты сейчас отдыхают. Все способы оплаты временно недоступны.',
          zh: '支付客服当前休息中，所有支付方式暂时不可用。',
        ),
        isError: true,
      );
    }
    return false;
  }

  List<PhotoItem> _scalePhotoItems(InvoiceItem item) {
    final date = item.updatedAt ?? item.createdAt ?? DateTime.now();
    return item.scalePhotoUrls
        .map((url) => PhotoItem(url: ApiConfig.getMediaUrl(url), date: date))
        .toList(growable: false);
  }

  void _openScalePhoto(InvoiceItem item, int index) {
    final photos = _scalePhotoItems(item);
    if (index < 0 || index >= photos.length) return;

    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => PhotoViewerScreen(
          item: photos[index],
          allPhotos: photos,
          initialIndex: index,
        ),
      ),
    );
  }

  void _openWaybillPhoto(InvoiceItem item) {
    final url = item.tkWaybillPhotoUrl;
    if (url == null || url.isEmpty) return;

    final photo = PhotoItem(
      url: ApiConfig.getMediaUrl(url),
      date: item.updatedAt ?? item.createdAt ?? DateTime.now(),
    );

    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) =>
            PhotoViewerScreen(item: photo, allPhotos: [photo], initialIndex: 0),
      ),
    );
  }

  void _showInvoiceStatusTimeline(List<InvoiceStatus> statuses) {
    final item = _currentItem;
    showStatusTimelineSheet(
      context: context,
      title: 'Статус счёта',
      currentStatusCode: item.status,
      currentStatusName: item.statusName ?? item.status,
      currentStatusColor: _parseHexColor(item.statusColor),
      history: item.statusHistory,
      statuses: _invoiceTimelineStatuses(statuses),
    );
  }

  Future<void> _applyBonusKg() async {
    final item = _currentItem;
    final kg = double.tryParse(_bonusKgCtrl.text.replaceAll(',', '.'));
    if (kg == null || kg <= 0) return;

    final maxKg = (item.weight * widget.maxBonusPercent / 100).clamp(
      0.0,
      widget.bonusBalance,
    );
    if (kg > maxKg) {
      AppToast.showFromSnackBar(
        context,
        SnackBar(
          content: Text('Максимум: ${maxKg.toStringAsFixed(2)} кг'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isApplyingBonus = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.post(
        '/client/invoices/${item.id}/apply-bonus',
        data: {'bonusKg': kg},
      );
      _bonusKgCtrl.selection = const TextSelection.collapsed(offset: 0);
      _bonusKgCtrl.clear();
      widget.onBonusApplied();
      if (mounted) {
        AppToast.showFromSnackBar(
          context,
          SnackBar(
            content: Text('Применено ${kg.toStringAsFixed(2)} бонусных кг'),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        AppToast.showFromSnackBar(
          context,
          const SnackBar(
            content: Text('Ошибка применения бонуса'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isApplyingBonus = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item =
        ref.watch(invoiceByIdProvider(widget.item.id)).asData?.value ??
        widget.item;
    final operatorsSleeping = paymentOperatorStatusOrWorking(
      ref.watch(paymentOperatorStatusProvider),
    ).sleeping;
    final df = DateFormat('dd MMM yyyy', 'ru');
    final statusColor = _parseHexColor(item.statusColor);
    final invoiceStatuses =
        ref.watch(invoiceStatusesProvider).asData?.value ??
        const <InvoiceStatus>[];
    final pricePerKg = item.clientPricePerKg ?? item.tariffBaseCost ?? 0;
    final maxKg = (item.weight * widget.maxBonusPercent / 100).clamp(
      0.0,
      widget.bonusBalance,
    );
    final enteredKg =
        double.tryParse(_bonusKgCtrl.text.replaceAll(',', '.')) ?? 0;
    final bonusDiscount = (enteredKg * pricePerKg).clamp(
      0.0,
      item.totalCostUsd,
    );
    final isPaymentReview = item.status.toLowerCase() == 'payment_review';
    final paymentSummary = item.paymentSummary;
    final isUnpaid = _isInvoiceUnpaid(item);
    final canOpenPayment = canOpenInvoicePayment(item);
    final earlyPaymentBenefit = _benefitFor(item);
    _scheduleBenefitExpiry(earlyPaymentBenefit);
    final showBonusSection =
        isUnpaid && widget.bonusBalance > 0 && pricePerKg > 0;
    final showBankQrRateBanner =
        isUnpaid &&
        !item.bankQrPaymentAvailable &&
        (item.bankQrPaymentUnavailableReason == 'rate_stale' ||
            item.bankQrPaymentUnavailableReason == 'no_rate' ||
            item.bankQrPaymentUnavailableReason == 'rate_invalid');

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: _InvoiceSheetSurface(
        icon: Icons.receipt_long_rounded,
        title: 'Счёт ${item.invoiceNumber}',
        subtitle: 'Разбивка суммы и данные для оплаты',
        keyboardAware: true,
        pinnedChild: _InvoiceDetailSummaryCard(item: item),
        footer: canOpenPayment
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (operatorsSleeping) ...[
                    const TrainingTarget(
                      id: 'invoice.pay.unavailable',
                      child: PaymentOperatorSleepingNotice(compact: true),
                    ),
                    const SizedBox(height: 8),
                    _InvoiceSecondaryButton(
                      label: tr(context, ru: 'Закрыть', zh: '关闭'),
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ] else ...[
                    TrainingTarget(
                      id: 'invoice.pay',
                      child: _InvoicePrimaryButton(
                        label: tr(
                          context,
                          ru: paymentSummary?.isPartial == true
                              ? 'Доплатить'
                              : 'Оплатить',
                          zh: paymentSummary?.isPartial == true ? '补付款项' : '付款',
                        ),
                        icon: Icons.payments_rounded,
                        onTap: _openInvoicePayment,
                      ),
                    ),
                  ],
                ],
              )
            : _InvoiceSecondaryButton(
                label: 'Закрыть',
                onTap: () => Navigator.of(context).pop(),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (earlyPaymentBenefit != null) ...[
              EarlyPaymentBenefitCard(
                benefit: earlyPaymentBenefit,
                selecting: _isSelectingEarlyPaymentBenefit,
                onChoose: earlyPaymentBenefit.canSelect
                    ? () => _showEarlyPaymentBenefitChoice(earlyPaymentBenefit)
                    : null,
              ),
              const SizedBox(height: 12),
            ],
            if (isPaymentReview) ...[
              const _InvoicePaymentReviewBanner(),
              const SizedBox(height: 12),
            ],
            if (showBankQrRateBanner) ...[
              const _InvoiceBankQrRateBanner(),
              const SizedBox(height: 12),
            ],
            if (const {
              'bank_qr',
              'usdt_trc20',
              'alipay',
              'manager',
            }.contains(item.paymentMethod)) ...[
              _InvoiceSectionCard(
                icon: Icons.payments_rounded,
                title: tr(context, ru: 'Способ оплаты', zh: '付款方式'),
                child: Text(
                  invoicePaymentMethodLabel(
                    context,
                    item.paymentMethod!,
                    action: false,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (paymentSummary != null) ...[
              ClientPaymentSummaryPanel(
                summary: paymentSummary,
                terminalRefund: const {
                  'cancelled',
                  'refunded',
                }.contains(item.status.toLowerCase()),
              ),
              const SizedBox(height: 12),
            ],
            if (int.tryParse(item.id) case final invoiceId?)
              ClientCarrierTrackingPanel(
                target: (assemblyId: null, invoiceId: invoiceId),
                boxes: item.boxes,
                sectionBuilder: (context, child) => _InvoiceSectionCard(
                  icon: Icons.local_shipping_outlined,
                  title: tr(context, ru: 'Движение груза', zh: '货物运输动态'),
                  child: child,
                ),
              ),
            _buildSection('Курсы', [
              if (item.clientRubRate != null)
                _buildInfoRow(
                  context,
                  'Курс \$/рубль',
                  item.clientRubRate!.toStringAsFixed(2),
                ),
              if (item.clientCnyRubRate != null)
                _buildInfoRow(
                  context,
                  'Курс юань/рубль',
                  item.clientCnyRubRate!.toStringAsFixed(4),
                )
              else if (item.clientYuanRate != null)
                _buildInfoRow(
                  context,
                  'Курс \$/юань',
                  item.clientYuanRate!.toStringAsFixed(4),
                ),
            ], icon: Icons.currency_exchange_rounded),
            const SizedBox(height: 12),
            _buildSection('Данные счёта', [
              _buildStatusInfoRow(
                context,
                item: item,
                statusColor: statusColor,
                onTap: () => _showInvoiceStatusTimeline(invoiceStatuses),
              ),
              if (item.createdAt != null)
                _buildInfoRow(
                  context,
                  'Дата выставления',
                  df.format(item.createdAt!),
                ),
              if (item.paidAt != null)
                _buildInfoRow(context, 'Дата оплаты', df.format(item.paidAt!)),
              if (item.arrivalDate != null)
                _buildInfoRow(
                  context,
                  'Дата прибытия',
                  df.format(item.arrivalDate!),
                ),
              if (item.arrivalMarket != null && item.arrivalMarket!.isNotEmpty)
                _buildInfoRow(
                  context,
                  'Рынок прибытия',
                  _localizeMarket(item.arrivalMarket!),
                ),
            ], icon: Icons.receipt_long_rounded),
            const SizedBox(height: 12),
            _buildSection('Груз', [
              if (item.totalTracks > 0)
                _buildInfoRow(
                  context,
                  'Количество трек-номеров',
                  '${item.totalTracks}',
                ),
              if (item.placesCount > 0)
                _buildInfoRow(
                  context,
                  'Количество мест',
                  '${item.placesCount}',
                ),
              if (item.weight > 0)
                _buildInfoRow(
                  context,
                  'Вес',
                  '${item.weight.toStringAsFixed(2)} кг',
                ),
              if (item.volume > 0)
                _buildInfoRow(
                  context,
                  'Объём',
                  '${item.volume.toStringAsFixed(3)} м³',
                ),
              if (item.weight > 0 && item.volume > 0)
                _buildInfoRow(
                  context,
                  'Плотность',
                  '${(item.weight / item.volume).toStringAsFixed(2)} кг/м³',
                ),
            ], icon: Icons.inventory_2_rounded),
            if (item.boxes.isNotEmpty || item.scalePhotoUrls.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildBoxesSection(item),
            ],
            const SizedBox(height: 12),
            _buildSection('Расчёт суммы', [
              if (item.clientPricePerKg != null && item.clientPricePerKg! > 0)
                _buildInfoRow(
                  context,
                  'Тариф за кг',
                  '\$${item.clientPricePerKg!.toStringAsFixed(2)}/кг',
                ),
              if (item.packagingSurchargePerKg > 0)
                _buildPackagingSurchargeBlock(context, item),
              if (item.photoReportCoefficient != null &&
                  item.photoReportCoefficient! > 1.0)
                _buildInfoRow(
                  context,
                  'Коэфф. фото',
                  '×${item.photoReportCoefficient!.toStringAsFixed(2)}',
                ),
              if (item.clientPricePerKgWithPhoto != null &&
                  item.clientPricePerKgWithPhoto! > 0 &&
                  item.clientPricePerKgWithPhoto != item.clientPricePerKg)
                _buildInfoRow(
                  context,
                  'Итоговый тариф',
                  '\$${item.clientPricePerKgWithPhoto!.toStringAsFixed(2)}/кг',
                ),
              if (item.shippingCost != null && item.shippingCost! > 0)
                _buildInfoRow(
                  context,
                  'Доставка по тарифу',
                  '\$${item.shippingCost!.toStringAsFixed(2)}',
                ),
              if (item.photoReportCostUsd > 0)
                _buildInfoRow(
                  context,
                  tr(context, ru: 'Фотоотчёты, итог', zh: '拍照报告合计'),
                  '\$${item.photoReportCostUsd.toStringAsFixed(2)}',
                ),
              for (final charge in item.photoReportCharges)
                _buildInfoRow(
                  context,
                  tr(
                    context,
                    ru: 'Фотоотчёт · ${charge.trackNumber}',
                    zh: '拍照报告 · ${charge.trackNumber}',
                  ),
                  '\$${charge.amountUsd.toStringAsFixed(2)}',
                ),
              if (item.transshipmentCost != null && item.transshipmentCost! > 0)
                _buildInfoRow(
                  context,
                  'Разгрузка',
                  '\$${item.transshipmentCost!.toStringAsFixed(2)}',
                ),
              if (item.hasDetailedPackagingUsage)
                _buildPackagingUsageBlock(context, item)
              else if (item.resolvedPackagingCostTotal != null &&
                  item.resolvedPackagingCostTotal! > 0)
                _buildInfoRow(
                  context,
                  'Упаковка, итог',
                  '\$${item.resolvedPackagingCostTotal!.toStringAsFixed(2)}',
                ),
              if (!item.hasDetailedPackagingUsage &&
                  item.packagingNames.isNotEmpty)
                _buildInfoRow(
                  context,
                  'Использованные упаковки',
                  item.packagingNames,
                ),
              if (item.insuranceCostClient != null &&
                  item.insuranceCostClient! > 0)
                _buildInfoRow(
                  context,
                  'Страховка',
                  '\$${item.insuranceCostClient!.toStringAsFixed(2)}',
                )
              else if (item.insuranceCost != null && item.insuranceCost! > 0)
                _buildInfoRow(
                  context,
                  'Страховка',
                  '\$${item.insuranceCost!.toStringAsFixed(2)}',
                ),
              if (item.discountAmount != null && item.discountAmount! > 0)
                _buildInfoRow(
                  context,
                  'Скидка',
                  '−\$${item.discountAmount!.toStringAsFixed(2)}',
                ),
              if (item.bonusKgApplied > 0)
                _buildInfoRow(
                  context,
                  'Бонусные кг',
                  '−${item.bonusKgApplied.toStringAsFixed(2)} кг',
                ),
            ], icon: Icons.payments_rounded),
            if (showBonusSection) ...[
              const SizedBox(height: 12),
              _buildBonusSection(
                context: context,
                item: item,
                maxKg: maxKg,
                enteredKg: enteredKg,
                bonusDiscount: bonusDiscount,
              ),
            ],
            if (item.tkWaybillPhotoUrl != null) ...[
              const SizedBox(height: 12),
              _buildMediaSection(item),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBonusSection({
    required BuildContext context,
    required InvoiceItem item,
    required double maxKg,
    required double enteredKg,
    required double bonusDiscount,
  }) {
    return _buildSection('Бонусные кг', [
      _buildInfoRow(
        context,
        'Доступно',
        '${widget.bonusBalance.toStringAsFixed(2)} кг',
      ),
      _buildInfoRow(context, 'Можно списать', '${maxKg.toStringAsFixed(2)} кг'),
      if (item.bonusKgApplied > 0)
        _buildInfoRow(
          context,
          'Уже применено',
          '${item.bonusKgApplied.toStringAsFixed(2)} кг',
        ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _bonusKgCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+[.,]?\d*')),
              ],
              decoration: appInputDecoration(
                context,
                hintText: 'Кол-во кг',
                fillColor: Colors.white,
                isDense: true,
                borderColor: Colors.green.shade300,
                focusedBorderColor: Colors.green.shade600,
                focusedWidth: 2,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 46,
            child: ElevatedButton(
              onPressed: _isApplyingBonus ? null : _applyBonusKg,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: _isApplyingBonus
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Применить'),
            ),
          ),
        ],
      ),
      if (enteredKg > 0) ...[
        const SizedBox(height: 8),
        Text(
          'Предварительная скидка: ~\$${bonusDiscount.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 13,
            color: Colors.green.shade700,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ], icon: Icons.redeem_rounded);
  }

  Widget _buildStatusInfoRow(
    BuildContext context, {
    required InvoiceItem item,
    required Color? statusColor,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Статус счёта',
              style: TextStyle(
                color: Color(0xFF666666),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: _InvoiceCardStatusPill(
              text: item.statusName ?? item.status,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoxesSection(InvoiceItem item) {
    final children = <Widget>[];
    if (item.boxes.isNotEmpty) {
      for (var index = 0; index < item.boxes.length; index++) {
        if (index > 0) children.add(const SizedBox(height: 10));
        children.add(_buildInvoiceBoxCard(item, item.boxes[index]));
      }
    } else if (item.scalePhotoUrls.isNotEmpty) {
      children.add(_buildScalePhotoStrip(item, item.scalePhotoUrls));
    }
    return _buildSection(
      'Информация по коробкам',
      children,
      icon: Icons.inventory_2_outlined,
    );
  }

  Widget _buildInvoiceBoxCard(InvoiceItem item, Box box) {
    final photoUrls = box.photos
        .map((photo) => photo.url)
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Коробка №${box.number}',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Gilroy',
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (photoUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildScalePhotoStrip(item, photoUrls),
          ],
          const SizedBox(height: 8),
          if (box.weight > 0)
            _buildInfoRow(context, 'Вес коробки', box.weightDisplay),
          if (box.height > 0 && box.width > 0 && box.length > 0)
            _buildInfoRow(context, 'Габариты коробки', box.dimensionsDisplay),
          if (box.density > 0)
            _buildInfoRow(context, 'Плотность коробки', box.densityDisplay),
          if (box.volume > 0)
            _buildInfoRow(context, 'Объём коробки', box.volumeDisplay),
        ],
      ),
    );
  }

  Widget _buildScalePhotoStrip(InvoiceItem item, List<String> urls) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Фото с весов',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            addAutomaticKeepAlives: false,
            addSemanticIndexes: false,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final url = urls[index];
              final allPhotoIndex = item.scalePhotoUrls.indexOf(url);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: allPhotoIndex < 0
                    ? null
                    : () => _openScalePhoto(item, allPhotoIndex),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AuthenticatedImage.network(
                    ApiConfig.getMediaUrl(url),
                    width: 104,
                    height: 104,
                    cacheWidth: 240,
                    cacheHeight: 240,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                    errorBuilder: (_, _, _) => Container(
                      width: 104,
                      height: 104,
                      color: const Color(0xFFEEEEEE),
                      child: const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMediaSection(InvoiceItem item) {
    return _buildSection('Фото накладной', [
      if (item.tkWaybillPhotoUrl != null) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openWaybillPhoto(item),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AuthenticatedImage.network(
                ApiConfig.getMediaUrl(item.tkWaybillPhotoUrl!),
                width: 104,
                height: 104,
                cacheWidth: 240,
                cacheHeight: 240,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                errorBuilder: (_, _, _) => Container(
                  width: 104,
                  height: 104,
                  color: const Color(0xFFEEEEEE),
                  child: const Icon(Icons.broken_image, color: Colors.grey),
                ),
              ),
            ),
          ),
        ),
      ],
    ], icon: Icons.photo_library_rounded);
  }

  Widget _buildSection(
    String title,
    List<Widget> children, {
    required IconData icon,
  }) {
    if (children.isEmpty) return const SizedBox.shrink();
    return _InvoiceSectionCard(
      icon: icon,
      title: title,
      child: Column(children: children),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value, {
    bool isTotal = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                color: isTotal
                    ? const Color(0xFF333333)
                    : const Color(0xFF666666),
                fontSize: isTotal ? 15 : 14,
                fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                color: isTotal ? context.brandPrimary : const Color(0xFF333333),
                fontSize: isTotal ? 18 : 14,
                fontWeight: isTotal ? FontWeight.w900 : FontWeight.w600,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackagingSurchargeBlock(BuildContext context, InvoiceItem item) {
    final perKg = item.packagingSurchargePerKg;
    final total = item.packagingSurchargeTotal;
    final details = item.applicablePackagingSurcharges
        .map(
          (row) =>
              '${row.displayName()} +\$${row.amount.toStringAsFixed(2)}/кг',
        )
        .join(', ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildInfoRow(
            context,
            'Доплата за упаковку',
            '+\$${perKg.toStringAsFixed(2)}/кг',
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              total > 0
                  ? '$details · в доставке ≈ \$${total.toStringAsFixed(2)}'
                  : details,
              style: const TextStyle(
                color: Color(0xFF888888),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPackagingUsageBlock(BuildContext context, InvoiceItem item) {
    final total =
        item.resolvedPackagingCostTotal ?? item.packagingUsageClientTotal;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Упаковка, итог',
                  style: TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '\$${total.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Color(0xFF333333),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Использованные упаковки',
            style: TextStyle(
              color: Color(0xFF888888),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8EAEE)),
            ),
            child: Column(
              children: item.packagingUsage.map((usage) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: usage.isPrimary
                              ? context.brandPrimary.withValues(alpha: 0.10)
                              : Colors.blue.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          usage.isPrimary ? 'Основа' : 'Доп',
                          style: TextStyle(
                            color: usage.isPrimary
                                ? context.brandPrimary
                                : Colors.blue.shade700,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${usage.name} × ${usage.quantityDisplay()}',
                          style: const TextStyle(
                            color: Color(0xFF333333),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '\$${usage.effectiveClientTotalCost.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Color(0xFF333333),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
