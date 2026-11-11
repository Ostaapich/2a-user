import 'sp_status_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/branding/company_branding_provider.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/ui/app_layout.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/ui/empty_state.dart';
import '../../../core/ui/scroll_to_top_button.dart';
import '../../../core/utils/locale_text.dart';
import '../data/sp_organizer_customer_models.dart';
import '../data/sp_organizer_models.dart';
import '../data/sp_organizer_provider.dart';
import 'sp_finance_ui.dart';
import 'sp_organizer_navigation.dart';
import 'sp_organizer_purchase_kind.dart';

class SpOrganizerCustomerDetailScreen extends ConsumerStatefulWidget {
  final int customerId;

  const SpOrganizerCustomerDetailScreen({super.key, required this.customerId});

  @override
  ConsumerState<SpOrganizerCustomerDetailScreen> createState() =>
      _SpOrganizerCustomerDetailScreenState();
}

class _SpOrganizerCustomerDetailScreenState
    extends ConsumerState<SpOrganizerCustomerDetailScreen> {
  final _scrollController = ScrollController();
  SpOrganizerCustomerDetail? _detail;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isArchiving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final capabilities = await ref.read(spOrganizerCapabilitiesProvider.future);
    if (!mounted || !capabilities.customersDirectory) return;
    await _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final detail = await ref
          .read(spOrganizerRepositoryProvider)
          .getCustomerDetail(widget.customerId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadMore() async {
    final detail = _detail;
    if (detail == null || !detail.hasMore || _isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final next = await ref
          .read(spOrganizerRepositoryProvider)
          .getCustomerDetail(
            widget.customerId,
            page: detail.history.page + 1,
            limit: detail.history.limit,
          );
      if (!mounted) return;
      setState(() {
        _detail = detail.mergePage(next);
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
        _error = error.toString();
      });
      AppToast.show(
        context,
        '${tr(context, ru: 'Не удалось загрузить историю', zh: '无法加载历史')}: $error',
        isError: true,
      );
    }
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
          onRefresh: _loadFirstPage,
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
                title:
                    _detail?.customer.fullName ??
                    tr(context, ru: 'Карточка клиента', zh: '客户详情'),
                fallbackRoute: '/sp-finance/customers',
                trailing: _detail == null
                    ? null
                    : IconButton(
                        tooltip: _detail!.customer.isArchived
                            ? tr(context, ru: 'Восстановить', zh: '恢复')
                            : tr(context, ru: 'В архив', zh: '归档'),
                        onPressed: _toggleArchive,
                        icon: Icon(
                          _detail!.customer.isArchived
                              ? Icons.unarchive_outlined
                              : Icons.archive_outlined,
                          color: context.brandPrimary,
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              capabilitiesAsync.when(
                loading: () => const _DetailLoadingCard(),
                error: (_, _) => _DetailUnavailableCard(
                  message: tr(
                    context,
                    ru: 'Текущие закупки продолжают работать.',
                    zh: '现有采购仍可正常使用。',
                  ),
                ),
                data: (capabilities) {
                  if (!capabilities.customersDirectory) {
                    return _DetailUnavailableCard(
                      message: tr(
                        context,
                        ru: 'Карточка клиента пока выключена на сервере.',
                        zh: '服务器尚未启用客户详情。',
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
    final companyName = ref.watch(companyNameProvider);
    final detail = _detail;
    if (_isLoading && detail == null) return const _DetailLoadingCard();
    if (_error != null && detail == null) {
      return EmptyState(
        icon: Icons.error_outline_rounded,
        title: tr(context, ru: 'Не удалось открыть клиента', zh: '无法打开客户'),
        message: _error!,
      );
    }
    if (detail == null) {
      return _DetailUnavailableCard(
        message: tr(
          context,
          ru: 'Данные клиента пока недоступны.',
          zh: '客户数据暂不可用。',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CustomerDetailHero(detail: detail),
        const SizedBox(height: 12),
        SpOrganizerNavigation(
          capabilities: capabilities,
          selected: SpOrganizerSection.customers,
        ),
        const SizedBox(height: 12),
        _CustomerSummaryGrid(metrics: detail.metrics),
        const SizedBox(height: 12),
        _CustomerContactsCard(customer: detail.customer),
        if (detail.customer.comment != null) ...[
          const SizedBox(height: 12),
          _CustomerNoteCard(comment: detail.customer.comment!),
        ],
        const SizedBox(height: 12),
        SpInfoNotice(
          icon: Icons.account_balance_wallet_outlined,
          title: tr(context, ru: 'Баланс внутри СП', zh: '拼团内部余额'),
          message: tr(
            context,
            ru: 'Начисления и оплаты ниже относятся только к этому покупателю организатора и не являются счетами $companyName.',
            zh: '以下应收和付款只属于该团长客户，不是$companyName账单。',
          ),
        ),
        const SizedBox(height: 12),
        _HistoryHeader(total: detail.history.total),
        const SizedBox(height: 10),
        if (detail.history.items.isEmpty)
          EmptyState(
            icon: Icons.history_rounded,
            title: tr(context, ru: 'Истории пока нет', zh: '暂无历史'),
            message: tr(
              context,
              ru: 'Закупки, товары, оплаты и отправки клиента появятся здесь.',
              zh: '该客户的采购、商品、付款和发货会显示在这里。',
            ),
          )
        else
          ...detail.history.items.map(
            (purchase) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _CustomerPurchaseCard(purchase: purchase),
            ),
          ),
        if (detail.hasMore)
          OutlinedButton.icon(
            onPressed: _isLoadingMore ? null : _loadMore,
            icon: _isLoadingMore
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.expand_more_rounded),
            label: Text(tr(context, ru: 'Показать ещё', zh: '加载更多')),
          ),
      ],
    );
  }

  Future<void> _toggleArchive() async {
    if (_isArchiving) return;
    final detail = _detail;
    if (detail == null) return;
    setState(() => _isArchiving = true);
    try {
      if (!detail.customer.isArchived) {
        final confirmed = await showSpFinanceConfirmationSheet(
          context: context,
          icon: Icons.archive_rounded,
          title: tr(context, ru: 'Архивировать клиента?', zh: '归档此客户？'),
          message: tr(
            context,
            ru: 'История ${detail.customer.fullName}, товары, оплаты и отправки останутся доступными. Клиента можно восстановить.',
            zh: '${detail.customer.fullName} 的历史、商品、付款和发货会保留，并可随时恢复。',
          ),
          confirmLabel: tr(context, ru: 'Перенести в архив', zh: '移至归档'),
          cancelLabel: tr(context, ru: 'Отмена', zh: '取消'),
        );
        if (!mounted || confirmed != true) return;
      }
      final repository = ref.read(spOrganizerRepositoryProvider);
      if (detail.customer.isArchived) {
        await repository.restoreCustomer(detail.customer.id);
      } else {
        await repository.archiveCustomer(detail.customer.id);
      }
      if (!mounted) return;
      await ref
          .read(spOrganizerCustomersControllerProvider.notifier)
          .load(silent: true);
      if (!mounted) return;
      await _loadFirstPage();
      if (!mounted) return;
      AppToast.show(
        context,
        detail.customer.isArchived
            ? tr(context, ru: 'Клиент восстановлен', zh: '客户已恢复')
            : tr(context, ru: 'Клиент перенесён в архив', zh: '客户已归档'),
      );
    } catch (error) {
      if (!mounted) return;
      AppToast.show(
        context,
        '${tr(context, ru: 'Не удалось выполнить действие', zh: '操作失败')}: $error',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isArchiving = false);
    }
  }
}

class _CustomerDetailHero extends StatelessWidget {
  final SpOrganizerCustomerDetail detail;

  const _CustomerDetailHero({required this.detail});

  @override
  Widget build(BuildContext context) {
    final customer = detail.customer;
    return SpAnimatedHeroSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                child: Icon(
                  customer.isArchived
                      ? Icons.person_off_outlined
                      : Icons.person_rounded,
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
                    if (customer.city != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        customer.city!,
                        style: const TextStyle(
                          color: Color(0xE6FFFFFF),
                          fontFamily: 'Gilroy',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SpHeroChip(
                icon: Icons.shopping_bag_outlined,
                label: tr(
                  context,
                  ru: '${detail.metrics.purchasesCount} закупок',
                  zh: '${detail.metrics.purchasesCount} 次采购',
                ),
              ),
              SpHeroChip(
                icon: Icons.inventory_2_outlined,
                label: tr(
                  context,
                  ru: '${detail.metrics.itemsCount} товаров',
                  zh: '${detail.metrics.itemsCount} 件商品',
                ),
              ),
              if (customer.isArchived)
                SpHeroChip(
                  icon: Icons.archive_outlined,
                  label: tr(context, ru: 'В архиве', zh: '已归档'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CustomerSummaryGrid extends StatelessWidget {
  final SpOrganizerCustomerMetrics metrics;

  const _CustomerSummaryGrid({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final values = [
      (
        tr(context, ru: 'Оборот', zh: '成交额'),
        _rub(context, metrics.turnoverRub),
        Icons.payments_outlined,
      ),
      (
        tr(context, ru: 'Получено', zh: '已收'),
        _rub(context, metrics.paidRub),
        Icons.check_circle_outline_rounded,
      ),
      (
        tr(context, ru: 'Текущий долг', zh: '当前欠款'),
        _rub(context, metrics.debtRub),
        Icons.schedule_rounded,
      ),
      (
        tr(context, ru: 'Прибыль', zh: '利润'),
        _rub(context, metrics.profitRub),
        Icons.trending_up_rounded,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 4 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values
              .map(
                (value) => SizedBox(
                  width: width,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: SpFinanceUi.cardDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(value.$3, color: context.brandPrimary, size: 20),
                        const SizedBox(height: 8),
                        Text(
                          value.$2,
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
                        Text(value.$1, style: SpFinanceUi.labelStyle),
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

class _CustomerContactsCard extends StatelessWidget {
  final SpOrganizerCustomer customer;

  const _CustomerContactsCard({required this.customer});

  @override
  Widget build(BuildContext context) {
    final entries = <(IconData, String, String)>[
      if (customer.phone != null)
        (
          Icons.phone_outlined,
          tr(context, ru: 'Телефон', zh: '电话'),
          customer.phone!,
        ),
      if (customer.email != null)
        (
          Icons.email_outlined,
          tr(context, ru: 'Email', zh: '邮箱'),
          customer.email!,
        ),
      if (customer.telegram != null)
        (Icons.send_outlined, 'Telegram', customer.telegram!),
      if (customer.whatsapp != null)
        (Icons.chat_outlined, 'WhatsApp', customer.whatsapp!),
      if (customer.wechat != null)
        (Icons.forum_outlined, 'WeChat', customer.wechat!),
      if (customer.vk != null)
        (Icons.alternate_email_rounded, 'VK', customer.vk!),
      if (customer.max != null) (Icons.message_outlined, 'MAX', customer.max!),
      if (customer.deliveryAddress != null)
        (
          Icons.location_on_outlined,
          tr(context, ru: 'Адрес доставки', zh: '收货地址'),
          customer.deliveryAddress!,
        ),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(context, ru: 'Контакты и доставка', zh: '联系方式与配送'),
            style: SpFinanceUi.sectionTitleStyle,
          ),
          const SizedBox(height: 10),
          if (entries.isEmpty)
            Text(
              tr(context, ru: 'Контакты пока не заполнены.', zh: '尚未填写联系方式。'),
              style: SpFinanceUi.bodyStyle,
            )
          else
            ...entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(entry.$1, color: context.brandPrimary, size: 19),
                    const SizedBox(width: 9),
                    SizedBox(
                      width: 92,
                      child: Text(entry.$2, style: SpFinanceUi.labelStyle),
                    ),
                    Expanded(
                      child: SelectableText(
                        entry.$3,
                        style: SpFinanceUi.bodyStyle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CustomerNoteCard extends StatelessWidget {
  final String comment;

  const _CustomerNoteCard({required this.comment});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: SpFinanceUi.cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.sticky_note_2_outlined, color: context.brandPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, ru: 'Заметка', zh: '备注'),
                  style: SpFinanceUi.sectionTitleStyle,
                ),
                const SizedBox(height: 6),
                Text(comment, style: SpFinanceUi.bodyStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  final int total;

  const _HistoryHeader({required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            tr(context, ru: 'История закупок', zh: '采购历史'),
            style: SpFinanceUi.sectionTitleStyle,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: SpFinanceUi.softDecoration(context),
          child: Text('$total', style: SpFinanceUi.labelStyle),
        ),
      ],
    );
  }
}

class _CustomerPurchaseCard extends StatelessWidget {
  final SpOrganizerCustomerHistoryPurchase purchase;

  const _CustomerPurchaseCard({required this.purchase});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: context.brandPrimary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  spOrganizerPurchaseKindIcon(purchase.kind),
                  color: context.brandPrimary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      purchase.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SpFinanceUi.sectionTitleStyle,
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        _HistoryChip(
                          label: spOrganizerPurchaseKindLabel(
                            context,
                            purchase.kind,
                          ),
                        ),
                        _HistoryChip(
                          label: spStatusText(context, purchase.status),
                        ),
                        if (purchase.createdAt != null)
                          _HistoryChip(
                            label: DateFormat(
                              'dd.MM.yyyy',
                            ).format(purchase.createdAt!.toLocal()),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: tr(context, ru: 'Открыть закупку', zh: '打开采购'),
                onPressed: () =>
                    context.push('/sp-finance/purchases/${purchase.id}'),
                icon: const Icon(Icons.open_in_new_rounded),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: _HistoryMetric(
                  label: tr(context, ru: 'Начислено', zh: '应收'),
                  value: _rub(context, purchase.metrics.turnoverRub),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HistoryMetric(
                  label: tr(context, ru: 'Получено', zh: '已收'),
                  value: _rub(context, purchase.metrics.paidRub),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HistoryMetric(
                  label: tr(context, ru: 'Остаток', zh: '余额'),
                  value: _rub(context, purchase.metrics.balanceRub),
                ),
              ),
            ],
          ),
          if (purchase.items.isNotEmpty) ...[
            const SizedBox(height: 11),
            _LedgerGroup(
              icon: Icons.inventory_2_outlined,
              title: tr(
                context,
                ru: 'Товары · ${purchase.items.length}',
                zh: '商品 · ${purchase.items.length}',
              ),
              lines: purchase.items
                  .take(3)
                  .map(
                    (item) =>
                        '${item.quantity}× ${item.title} · ${spStatusText(context, item.status)}',
                  )
                  .toList(growable: false),
            ),
          ],
          if (purchase.payments.isNotEmpty) ...[
            const SizedBox(height: 8),
            _LedgerGroup(
              icon: Icons.payments_outlined,
              title: tr(
                context,
                ru: 'Оплаты · ${purchase.payments.length}',
                zh: '付款 · ${purchase.payments.length}',
              ),
              lines: purchase.payments
                  .take(3)
                  .map(
                    (payment) =>
                        '${spStatusText(context, payment.title)} · ${_rub(context, payment.amountRub)} · ${spStatusText(context, payment.status)}',
                  )
                  .toList(growable: false),
            ),
          ],
          if (purchase.shipments.isNotEmpty) ...[
            const SizedBox(height: 8),
            _LedgerGroup(
              icon: Icons.local_shipping_outlined,
              title: tr(
                context,
                ru: 'Отправки · ${purchase.shipments.length}',
                zh: '发货 · ${purchase.shipments.length}',
              ),
              lines: purchase.shipments
                  .take(3)
                  .map(
                    (shipment) => [
                      shipment.title,
                      shipment.trackingNumber,
                      spStatusText(context, shipment.status),
                    ].whereType<String>().join(' · '),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryChip extends StatelessWidget {
  final String label;

  const _HistoryChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: context.brandPrimary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: context.brandPrimary,
          fontFamily: 'Gilroy',
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
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
              fontSize: 13,
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

class _LedgerGroup extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> lines;

  const _LedgerGroup({
    required this.icon,
    required this.title,
    required this.lines,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: SpFinanceUi.softDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: context.brandPrimary),
              const SizedBox(width: 7),
              Expanded(child: Text(title, style: SpFinanceUi.labelStyle)),
            ],
          ),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                line,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SpFinanceUi.bodyStyle.copyWith(fontSize: 12.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailLoadingCard extends StatelessWidget {
  const _DetailLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      decoration: SpFinanceUi.cardDecoration(),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _DetailUnavailableCard extends StatelessWidget {
  final String message;

  const _DetailUnavailableCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.person_outline_rounded,
      title: tr(context, ru: 'Карточка клиента недоступна', zh: '客户详情不可用'),
      message: message,
    );
  }
}

String _rub(BuildContext context, double value) {
  final locale = Localizations.localeOf(context).languageCode;
  final format = NumberFormat.decimalPatternDigits(
    locale: locale,
    decimalDigits: value == value.roundToDouble() ? 0 : 2,
  );
  return '${format.format(value)} ₽';
}
