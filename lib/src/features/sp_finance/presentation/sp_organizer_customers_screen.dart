import '../../../core/ui/app_search_field.dart';
import 'dart:async';

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

class SpOrganizerCustomersScreen extends ConsumerStatefulWidget {
  final bool embedded;

  const SpOrganizerCustomersScreen({super.key, this.embedded = false});

  @override
  ConsumerState<SpOrganizerCustomersScreen> createState() =>
      _SpOrganizerCustomersScreenState();
}

class _SpOrganizerCustomersScreenState
    extends ConsumerState<SpOrganizerCustomersScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  final Set<int> _busyCustomerIds = <int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final capabilities = await ref.read(
        spOrganizerCapabilitiesProvider.future,
      );
      if (!mounted || !capabilities.customersDirectory) return;
      await ref.read(spOrganizerCustomersControllerProvider.notifier).load();
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
    final state = ref.watch(spOrganizerCustomersControllerProvider);
    final topPad = widget.embedded ? 0.0 : AppLayout.topBarTotalHeight(context);
    final bottomPad = AppLayout.bottomScrollPadding(context);

    return Stack(
      children: [
        RefreshIndicator(
          color: context.brandPrimary,
          onRefresh: () async {
            if (capabilitiesAsync.asData?.value.customersDirectory != true) {
              return;
            }
            await ref
                .read(spOrganizerCustomersControllerProvider.notifier)
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
                  title: tr(context, ru: 'Клиенты организатора', zh: '团长客户'),
                  fallbackRoute: '/sp-finance',
                ),
                const SizedBox(height: 12),
              ],
              capabilitiesAsync.when(
                loading: () => const _CustomersLoadingCard(),
                error: (_, _) => _CustomersUnavailableCard(
                  title: tr(
                    context,
                    ru: 'Справочник временно недоступен',
                    zh: '客户目录暂不可用',
                  ),
                  message: tr(
                    context,
                    ru: 'Текущие закупки и участники продолжают работать.',
                    zh: '现有采购和参与者仍可正常使用。',
                  ),
                ),
                data: (capabilities) {
                  if (!capabilities.customersDirectory) {
                    return _CustomersUnavailableCard(
                      title: tr(
                        context,
                        ru: 'Справочник пока не включён',
                        zh: '客户目录尚未启用',
                      ),
                      message: tr(
                        context,
                        ru: 'Новый раздел выключен на сервере. Существующие данные СП не изменяются.',
                        zh: '服务器尚未启用此页面，现有拼团数据不会改变。',
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
    SpOrganizerCustomersState state,
  ) {
    final companyName = ref.watch(companyNameProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded) ...[
          _CustomersHero(total: state.total, scope: state.scope),
          const SizedBox(height: 12),
          SpOrganizerNavigation(
            capabilities: capabilities,
            selected: SpOrganizerSection.customers,
          ),
          const SizedBox(height: 12),
        ],
        _CustomersToolbar(
          controller: _searchController,
          scope: state.scope,
          isLoading: state.isLoading,
          onChanged: _onSearchChanged,
          onScopeChanged: (scope) {
            ref
                .read(spOrganizerCustomersControllerProvider.notifier)
                .setScope(scope);
          },
        ),
        const SizedBox(height: 14),
        if (state.error != null && state.customers.isEmpty)
          EmptyState(
            icon: Icons.error_outline_rounded,
            title: tr(
              context,
              ru: 'Не удалось загрузить клиентов',
              zh: '无法加载客户',
            ),
            message: state.error!,
          )
        else if (state.isLoading && state.customers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (state.customers.isEmpty)
          _CustomersEmptyCard(scope: state.scope)
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
                children: state.customers
                    .map(
                      (customer) => SizedBox(
                        width: cardWidth,
                        child: _CustomerCard(
                          customer: customer,
                          onOpen: () => context.push(
                            '/sp-finance/customers/${customer.id}',
                          ),
                          onArchive: customer.isArchived
                              ? () => _restoreCustomer(customer)
                              : () => _archiveCustomer(customer),
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
                        .read(spOrganizerCustomersControllerProvider.notifier)
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
        const SizedBox(height: 12),
        SpInfoNotice(
          icon: Icons.lock_outline_rounded,
          title: tr(context, ru: 'Отдельный внутренний учёт', zh: '独立内部账本'),
          message: tr(
            context,
            ru: 'Долги клиентов организатора не смешиваются со счетами организатора перед $companyName. Архив не удаляет историю.',
            zh: '团长客户欠款不会与团长对$companyName的账单混合，归档不会删除历史。',
          ),
        ),
      ],
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(spOrganizerCustomersControllerProvider.notifier).search(value);
    });
  }

  Future<void> _archiveCustomer(SpOrganizerCustomer customer) async {
    if (_busyCustomerIds.contains(customer.id)) return;
    setState(() => _busyCustomerIds.add(customer.id));
    try {
      final confirmed = await showSpFinanceConfirmationSheet(
        context: context,
        icon: Icons.archive_rounded,
        title: tr(context, ru: 'Архивировать клиента?', zh: '归档此客户？'),
        message: tr(
          context,
          ru: '${customer.fullName} исчезнет из выбора для новых товаров. История, оплаты и отправки сохранятся.',
          zh: '${customer.fullName} 将不再出现在新商品的客户选择中，历史、付款和发货都会保留。',
        ),
        confirmLabel: tr(context, ru: 'Перенести в архив', zh: '移至归档'),
        cancelLabel: tr(context, ru: 'Отмена', zh: '取消'),
      );
      if (!mounted || confirmed != true) return;
      await ref
          .read(spOrganizerCustomersControllerProvider.notifier)
          .archiveCustomer(customer.id);
      if (!mounted) return;
      AppToast.show(
        context,
        tr(context, ru: 'Клиент перенесён в архив', zh: '客户已归档'),
      );
    } catch (error) {
      if (!mounted) return;
      AppToast.show(
        context,
        '${tr(context, ru: 'Не удалось архивировать клиента', zh: '无法归档客户')}: $error',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busyCustomerIds.remove(customer.id));
    }
  }

  Future<void> _restoreCustomer(SpOrganizerCustomer customer) async {
    if (_busyCustomerIds.contains(customer.id)) return;
    setState(() => _busyCustomerIds.add(customer.id));
    try {
      await ref
          .read(spOrganizerCustomersControllerProvider.notifier)
          .restoreCustomer(customer.id);
      if (!mounted) return;
      AppToast.show(
        context,
        tr(context, ru: 'Клиент восстановлен', zh: '客户已恢复'),
      );
    } catch (error) {
      if (!mounted) return;
      AppToast.show(
        context,
        '${tr(context, ru: 'Не удалось восстановить клиента', zh: '无法恢复客户')}: $error',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busyCustomerIds.remove(customer.id));
    }
  }
}

class _CustomersHero extends StatelessWidget {
  final int total;
  final String scope;

  const _CustomersHero({required this.total, required this.scope});

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
              Icons.people_alt_rounded,
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
                  tr(context, ru: 'Вся клиентская база', zh: '完整客户库'),
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
                    ru: 'Контакты, история закупок, оплаты и отправки в одном месте.',
                    zh: '集中查看联系方式、采购历史、付款和发货。',
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
                  icon: scope == 'archived'
                      ? Icons.archive_rounded
                      : Icons.person_rounded,
                  label: scope == 'archived'
                      ? tr(context, ru: '$total в архиве', zh: '$total 位已归档')
                      : tr(context, ru: '$total активных', zh: '$total 位活跃客户'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomersToolbar extends StatelessWidget {
  final TextEditingController controller;
  final String scope;
  final bool isLoading;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onScopeChanged;

  const _CustomersToolbar({
    required this.controller,
    required this.scope,
    required this.isLoading,
    required this.onChanged,
    required this.onScopeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: SpFinanceUi.cardDecoration(),
      child: Column(
        children: [
          AppSearchField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            hintText: tr(
              context,
              ru: 'Имя, телефон, email или мессенджер',
              zh: '姓名、电话、邮箱或聊天账号',
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _ScopeButton(
                  selected: scope == 'active',
                  icon: Icons.people_alt_rounded,
                  label: tr(context, ru: 'Активные', zh: '活跃'),
                  onTap: isLoading ? null : () => onScopeChanged('active'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ScopeButton(
                  selected: scope == 'archived',
                  icon: Icons.archive_outlined,
                  label: tr(context, ru: 'Архив', zh: '归档'),
                  onTap: isLoading ? null : () => onScopeChanged('archived'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScopeButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ScopeButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : AppColors.textSecondary;
    return Material(
      color: selected ? context.brandPrimary : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
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

class _CustomerCard extends StatelessWidget {
  final SpOrganizerCustomer customer;
  final VoidCallback onOpen;
  final VoidCallback onArchive;

  const _CustomerCard({
    required this.customer,
    required this.onOpen,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final contacts = customer.compactContacts;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: SpFinanceUi.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: context.brandPrimary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Icon(
                      customer.isArchived
                          ? Icons.person_off_outlined
                          : Icons.person_rounded,
                      color: context.brandPrimary,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer.fullName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: SpFinanceUi.sectionTitleStyle,
                        ),
                        if (customer.city != null) ...[
                          const SizedBox(height: 4),
                          Text(customer.city!, style: SpFinanceUi.labelStyle),
                        ],
                        if (contacts.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            contacts.take(2).join(' • '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: SpFinanceUi.labelStyle,
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: customer.isArchived
                        ? tr(context, ru: 'Восстановить', zh: '恢复')
                        : tr(context, ru: 'В архив', zh: '归档'),
                    onPressed: onArchive,
                    icon: Icon(
                      customer.isArchived
                          ? Icons.unarchive_outlined
                          : Icons.archive_outlined,
                      color: context.brandPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _CustomerMetric(
                      label: tr(context, ru: 'Закупки', zh: '采购'),
                      value: '${customer.metrics.purchasesCount}',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CustomerMetric(
                      label: tr(context, ru: 'Оборот', zh: '成交额'),
                      value: _rub(context, customer.metrics.turnoverRub),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CustomerMetric(
                      label: tr(context, ru: 'Долг', zh: '欠款'),
                      value: _rub(context, customer.metrics.debtRub),
                      warning: customer.metrics.debtRub > 0,
                    ),
                  ),
                ],
              ),
              if (customer.metrics.lastPurchase case final purchase?) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 9,
                  ),
                  decoration: SpFinanceUi.softDecoration(context),
                  child: Row(
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 17,
                        color: context.brandPrimary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr(
                            context,
                            ru: 'Последняя: ${purchase.title}',
                            zh: '最近：${purchase.title}',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SpFinanceUi.labelStyle,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 19,
                        color: AppColors.textSecondary,
                      ),
                    ],
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

class _CustomerMetric extends StatelessWidget {
  final String label;
  final String value;
  final bool warning;

  const _CustomerMetric({
    required this.label,
    required this.value,
    this.warning = false,
  });

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
            style: TextStyle(
              color: warning ? const Color(0xFFE65100) : AppColors.textPrimary,
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

class _CustomersEmptyCard extends StatelessWidget {
  final String scope;

  const _CustomersEmptyCard({required this.scope});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: scope == 'archived'
          ? Icons.archive_outlined
          : Icons.people_outline_rounded,
      title: scope == 'archived'
          ? tr(context, ru: 'Архив пуст', zh: '归档为空')
          : tr(context, ru: 'Клиенты не найдены', zh: '未找到客户'),
      message: scope == 'archived'
          ? tr(
              context,
              ru: 'Архивированные клиенты появятся здесь без потери истории.',
              zh: '归档客户会显示在这里，历史不会丢失。',
            )
          : tr(
              context,
              ru: 'Новый клиент появится после добавления участника или товара в закупку.',
              zh: '在采购中添加参与者或商品后，客户会显示在这里。',
            ),
    );
  }
}

class _CustomersLoadingCard extends StatelessWidget {
  const _CustomersLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      decoration: SpFinanceUi.cardDecoration(),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _CustomersUnavailableCard extends StatelessWidget {
  final String title;
  final String message;

  const _CustomersUnavailableCard({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.people_outline_rounded,
      title: title,
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
