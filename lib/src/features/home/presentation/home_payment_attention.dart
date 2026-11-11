import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/app_colors.dart';
import '../../../core/ui/blurred_modal_bottom_sheet.dart';
import '../../../core/ui/sheet_handle.dart';
import '../../../core/utils/locale_text.dart';
import '../../clients/application/client_codes_controller.dart';
import '../../auth/data/auth_provider.dart';
import '../../invoices/data/invoices_provider.dart';
import '../../invoices/presentation/invoices_screen.dart';

/// The count and selector share the server's unpaid invoice filter.
class HomePaymentAttentionCard extends StatelessWidget {
  const HomePaymentAttentionCard({
    super.key,
    required this.clientCode,
    required this.count,
  });

  final String clientCode;
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.black.withValues(alpha: .04)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .05),
          offset: const Offset(0, 8),
          blurRadius: 22,
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        key: const ValueKey('home-payment-attention'),
        borderRadius: BorderRadius.circular(22),
        onTap: () => showBlurredModalBottomSheet<void>(
          context: context,
          useRootNavigator: true,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _HomePaymentAttentionSheet(clientCode: clientCode),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.brandPrimary.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  color: context.brandPrimary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tr(
                        context,
                        ru: 'Требуют оплаты: $count',
                        zh: '待付款账单：$count',
                      ),
                      style: const TextStyle(
                        fontFamily: 'Gilroy',
                        fontSize: 16,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      tr(
                        context,
                        ru: 'Выберите счёт и способ оплаты',
                        zh: '选择账单和付款方式',
                      ),
                      style: const TextStyle(
                        fontFamily: 'Gilroy',
                        fontSize: 12.5,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: context.brandPrimary,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _HomePaymentAttentionSheet extends ConsumerStatefulWidget {
  const _HomePaymentAttentionSheet({required this.clientCode});
  final String clientCode;

  @override
  ConsumerState<_HomePaymentAttentionSheet> createState() =>
      _HomePaymentAttentionSheetState();
}

class _HomePaymentAttentionSheetState
    extends ConsumerState<_HomePaymentAttentionSheet> {
  int _pages = 1;
  InvoiceDirectoryPage? _lastPage;
  (int?, String?, bool)? _owner;

  InvoiceDirectoryQuery get _query => (
    clientCode: widget.clientCode,
    search: '',
    status: 'unpaid',
    pages: _pages,
  );

  void _retry() {
    ref.invalidate(
      invoiceDirectoryPageProvider((
        clientCode: widget.clientCode,
        search: '',
        status: 'unpaid',
        page: _pages,
      )),
    );
    ref.invalidate(invoiceDirectoryProvider(_query));
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(
      authProvider.select(
        (state) => (state.clientId, state.userDomain, state.isLoggedIn),
      ),
    );
    final owner = session;
    _owner ??= owner;
    final isCurrentCode =
        ref.watch(activeClientCodeProvider) == widget.clientCode &&
        _owner == owner;
    if (!isCurrentCode) {
      _lastPage = null;
    }
    final AsyncValue<InvoiceDirectoryPage>? state = isCurrentCode
        ? ref.watch(invoiceDirectoryProvider(_query))
        : null;
    final latest = state?.asData?.value;
    if (latest != null) {
      _lastPage = latest;
    }
    final page = latest ?? _lastPage;
    final hasError = state?.hasError == true;
    final isLoading = state?.isLoading == true;

    Widget body;
    if (!isCurrentCode) {
      body = _PaymentListMessage(
        message: tr(
          context,
          ru: 'Выбранный клиент изменился. Откройте список счетов заново.',
          zh: '当前客户已更改。请重新打开账单列表。',
        ),
      );
    } else if (page == null) {
      body = hasError
          ? _PaymentListMessage(
              message: tr(
                context,
                ru: 'Не удалось загрузить счета',
                zh: '无法加载账单',
              ),
              onRetry: _retry,
            )
          : const Center(child: CircularProgressIndicator());
    } else if (page.items.isEmpty) {
      body = _PaymentListMessage(
        message: tr(context, ru: 'Нет счетов, требующих оплаты', zh: '暂无待付款账单'),
      );
    } else {
      body = ListView.separated(
        key: const ValueKey('home-payment-invoice-list'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        itemCount: page.items.length + (page.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == page.items.length) {
            return OutlinedButton.icon(
              key: const ValueKey('home-payment-invoices-more'),
              onPressed: isLoading || hasError
                  ? null
                  : () => setState(() => _pages++),
              icon: const Icon(Icons.expand_more_rounded),
              label: Text(tr(context, ru: 'Показать ещё', zh: '加载更多')),
            );
          }
          return ClientInvoiceTile(
            item: page.items[index],
            clientCode: widget.clientCode,
          );
        },
      );
    }

    return Container(
      key: const ValueKey('home-payment-invoices-sheet'),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      color: Colors.white,
      child: Column(
        children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: _PaymentAttentionHeader(
              subtitle: isCurrentCode && page != null
                  ? tr(
                      context,
                      ru: 'Всего: ${page.total}',
                      zh: '共 ${page.total} 个',
                    )
                  : tr(
                      context,
                      ru: 'Выберите счёт, чтобы открыть детали',
                      zh: '选择账单查看详情',
                    ),
            ),
          ),
          if (isLoading && page != null) const LinearProgressIndicator(),
          if (hasError && page != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _PaymentListMessage(
                message: tr(
                  context,
                  ru: 'Не удалось загрузить следующую страницу',
                  zh: '无法加载下一页',
                ),
                onRetry: _retry,
              ),
            ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _PaymentAttentionHeader extends StatelessWidget {
  const _PaymentAttentionHeader({required this.subtitle});
  final String subtitle;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('home-payment-invoices-header'),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      gradient: context.brandGradient,
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: context.brandPrimary.withValues(alpha: .18),
          blurRadius: 22,
          spreadRadius: -12,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .18),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: .22)),
          ),
          child: const Icon(
            Icons.receipt_long_rounded,
            color: Colors.white,
            size: 23,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(context, ru: 'Счета к оплате', zh: '待付款账单'),
                maxLines: 2,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Gilroy',
                  fontSize: 20,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                maxLines: 2,
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
        const SizedBox(width: 4),
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            tooltip: tr(context, ru: 'Закрыть', zh: '关闭'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ),
      ],
    ),
  );
}

class _PaymentListMessage extends StatelessWidget {
  const _PaymentListMessage({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Gilroy',
                color: AppColors.textSecondary,
              ),
            ),
            if (onRetry != null)
              TextButton.icon(
                key: const ValueKey('home-payment-invoices-retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(tr(context, ru: 'Повторить', zh: '重试')),
              ),
          ],
        ),
      ),
    ),
  );
}
