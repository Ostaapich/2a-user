import '../utils/payment_qr_image.dart';
import '../../../core/services/analytics_service.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/ui/app_colors.dart';
import '../../../core/media/authenticated_media.dart';
import '../../../core/network/api_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/ui/sheet_handle.dart';
import '../../../core/utils/gallery_image_save_helper.dart';
import '../../../core/utils/locale_text.dart';
import '../data/bank_qr_payment.dart';
import '../data/invoice_payment_options.dart';
import 'invoice_payment_method_sheet.dart';
import '../data/payment_operator_status.dart';
import 'payment_operator_sleeping_notice.dart';
import 'payment_qr_timing_warning.dart';
import 'payment_receipt_picker.dart';

/// Bank QR — модалка оплаты счёта в рублях.
///
/// На открытии стартует QR-платёж, показывает сумму/QR/назначение,
/// после выбора чека отправляет его и переводит счёт в «На проверке».
class BankQrPaymentSheet extends ConsumerStatefulWidget {
  final String invoiceId;
  final String invoiceNumber;
  final InvoicePaymentSelection? selection;
  final VoidCallback? onChangeMethod;

  const BankQrPaymentSheet({
    super.key,
    required this.invoiceId,
    required this.invoiceNumber,
    this.selection,
    this.onChangeMethod,
  });

  @override
  ConsumerState<BankQrPaymentSheet> createState() => _BankQrPaymentSheetState();
}

class _BankQrPaymentSheetState extends ConsumerState<BankQrPaymentSheet> {
  bool get _receiptOnly => widget.selection?.receiptOnly == true;
  bool _loading = true;
  String? _error;
  BankQrPaymentResult? _result;

  Uint8List? _fileBytes;
  String? _fileName;
  String? _fileMime;

  bool _uploading = false;
  bool _downloadingQr = false;
  bool _timingWarningShown = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.trackFunnel(
      WorkflowAction.paymentQrStart,
      WorkflowStage.viewed,
    );
    Future<void>.microtask(_start);
  }

  Future<void> _start() async {
    final current = ref.read(paymentOperatorStatusProvider).asData?.value;
    final operatorStatus =
        current ??
        await ref.read(paymentOperatorStatusProvider.future) ??
        PaymentOperatorStatus.workingFallback;
    if (!mounted) return;
    if (operatorStatus.sleeping && widget.selection?.paymentId == null) {
      setState(() {
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final selection = widget.selection;
      final existing = selection?.paymentId != null;
      final res = existing
          ? BankQrPaymentResult(
              paymentId: selection!.paymentId!,
              invoiceId: int.parse(widget.invoiceId),
              invoiceNumber: widget.invoiceNumber,
              amountRub: selection.method == 'bank_qr' ? selection.amount : 0,
              sumKopecks: selection.sumKopecks ?? 0,
              purpose: selection.purpose ?? '',
              qrPayload: selection.qrPayload ?? '',
              status: 'pending',
            )
          : await ref
                .read(bankQrPaymentServiceProvider)
                .startBankQrPayment(widget.invoiceId);
      if (!mounted) return;
      if (res == null) {
        setState(() {
          _loading = false;
          _error = tr(context, ru: 'Не удалось начать оплату', zh: '无法开始支付');
        });
        return;
      }
      setState(() {
        _result = res;
        _loading = false;
      });
      if (!_receiptOnly &&
          !_timingWarningShown &&
          widget.selection?.method != 'usdt_trc20' &&
          widget.selection?.method != 'alipay') {
        _timingWarningShown = true;
        await showPaymentQrTimingWarning(
          context,
          paymentAttemptKey: 'invoice:${widget.invoiceId}:${res.paymentId}',
        );
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final reason = e.response?.data is Map
          ? (e.response?.data['reason']?.toString())
          : null;
      setState(() {
        _loading = false;
        _error = reason != null
            ? tr(context, ru: 'QR-оплата недоступна', zh: 'QR 支付不可用')
            : tr(context, ru: 'Ошибка сети. Повторите.', zh: '网络错误，请重试');
      });
    }
  }

  String get _qrFileName {
    final safeNumber = widget.invoiceNumber
        .replaceAll(RegExp(r'[^A-Za-z0-9а-яА-ЯёЁ_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return '2a_invoice_${safeNumber.isEmpty ? widget.invoiceId : safeNumber}_qr.png';
  }

  Future<void> _downloadQr() async {
    final res = _result;
    if (res == null || _downloadingQr || _receiptOnly) return;
    setState(() => _downloadingQr = true);
    try {
      final foreignQr = widget.selection?.qrImageUrl;
      if (foreignQr != null) {
        final bytes = await loadMediaBytes(
          ref.read(apiClientProvider),
          ApiConfig.getMediaUrl(foreignQr),
        );
        if (!mounted) return;
        final exportBytes = widget.selection?.method == 'bank_qr'
            ? await createPaymentQrImage(imageBytes: bytes)
            : bytes;
        if (!mounted) return;
        final result = await saveImageToGallery(
          bytes: exportBytes,
          fileName: _qrFileName,
        );
        if (!mounted) return;
        AppToast.show(
          context,
          result.success
              ? tr(context, ru: 'QR-код сохранён', zh: '二维码已保存')
              : tr(context, ru: 'Не удалось сохранить QR', zh: '无法保存二维码'),
          isError: !result.success,
        );
        return;
      }
      final bytes = await createPaymentQrImage(payload: res.qrPayload);
      if (!mounted) return;
      final saveResult = await saveImageToGallery(
        bytes: bytes,
        fileName: _qrFileName,
      );
      if (!mounted) return;
      final successMessage = switch (saveResult.destination) {
        SavedImageDestination.gallery => tr(
          context,
          ru: 'QR-код сохранён в галерею',
          zh: '二维码已保存到相册',
        ),
        SavedImageDestination.download => tr(
          context,
          ru: 'QR-код скачан',
          zh: '二维码已下载',
        ),
      };
      AppToast.show(
        context,
        saveResult.success
            ? successMessage
            : tr(context, ru: 'Не удалось сохранить QR', zh: '无法保存二维码'),
        isError: !saveResult.success,
      );
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          tr(context, ru: 'Не удалось сохранить QR', zh: '无法保存二维码'),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingQr = false);
    }
  }

  Future<void> _pickReceipt() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    try {
      final receipt = await pickPaymentReceipt(context);
      if (!mounted) return;
      setState(() => _uploading = false);
      if (receipt == null) return;
      setState(() {
        _fileBytes = receipt.bytes;
        _fileName = receipt.fileName;
        _fileMime = receipt.mimeType;
      });
      await _confirmPaid();
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploading = false);
      AppToast.show(
        context,
        tr(context, ru: 'Не удалось выбрать чек', zh: '无法选择付款凭证'),
        isError: true,
      );
    }
  }

  Future<void> _confirmPaid() async {
    final res = _result;
    final bytes = _fileBytes;
    if (res == null || bytes == null || _uploading) return;
    setState(() => _uploading = true);
    try {
      final upload = await ref
          .read(bankQrPaymentServiceProvider)
          .uploadBankQrReceipt(
            paymentId: res.paymentId,
            bytes: bytes,
            fileName: _fileName ?? 'receipt',
            mimeType: _fileMime ?? 'application/octet-stream',
          );
      if (!mounted) return;
      setState(() => _uploading = false);
      if (upload == null ||
          upload.invoiceStatus != 'payment_review' ||
          upload.paymentId != res.paymentId) {
        AppToast.show(
          context,
          tr(context, ru: 'Не удалось отправить чек', zh: '无法发送凭证'),
          isError: true,
        );
        return;
      }
      AppToast.show(
        context,
        tr(context, ru: 'Чек отправлен на проверку', zh: '凭证已提交审核'),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploading = false);
      AppToast.show(
        context,
        error is DioException && error.response?.statusCode == 409
            ? tr(
                context,
                ru: 'Платёж изменился. Обновите данные и проверьте статус чека.',
                zh: '付款状态已变更，请刷新并查看凭证状态。',
              )
            : tr(
                context,
                ru: 'Ошибка отправки чека. Повторите отправку.',
                zh: '发送凭证出错，请重试。',
              ),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final operatorsSleeping = paymentOperatorStatusOrWorking(
      ref.watch(paymentOperatorStatusProvider),
    ).sleeping;

    return SafeArea(
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
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: _BankQrHeader(
                invoiceNumber: widget.invoiceNumber,
                method: widget.selection?.method ?? 'bank_qr',
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: operatorsSleeping && _result == null
                    ? const PaymentOperatorSleepingNotice()
                    : _loading
                    ? const _BankQrLoadingCard()
                    : _error != null
                    ? _buildError()
                    : _buildContent(),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + bottomPadding),
              child: operatorsSleeping && _result == null
                  ? _BankQrSecondaryButton(
                      label: tr(context, ru: 'Закрыть', zh: '关闭'),
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.of(context).pop(false),
                    )
                  : _buildFooter(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return _BankQrSectionCard(
      icon: Icons.error_outline_rounded,
      title: tr(context, ru: 'Оплата недоступна', zh: '支付不可用'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Gilroy',
              fontSize: 14,
              height: 1.25,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          _BankQrPrimaryButton(
            label: tr(context, ru: 'Повторить', zh: '重试'),
            icon: Icons.refresh_rounded,
            onTap: _start,
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final res = _result!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_receiptOnly) const PaymentQrTimingNotice(),
        if (_receiptOnly)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              tr(
                context,
                ru: 'Новые переводы этим способом сейчас недоступны. Если вы уже оплатили ранее созданную оплату, приложите чек для проверки.',
                zh: '此方式暂不接受新的转账。如果您已支付先前创建的付款，请附上凭证以供审核。',
              ),
            ),
          ),
        if (paymentOperatorStatusOrWorking(
          ref.watch(paymentOperatorStatusProvider),
        ).sleeping)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              tr(
                context,
                ru: 'Операторы отдыхают. Если вы уже оплатили, отправьте чек сейчас. Его проверят после возобновления работы.',
                zh: '付款人员正在休息。如果您已经付款，请立即提交凭证。恢复工作后将进行审核。',
              ),
            ),
          ),
        _BankQrSectionCard(
          icon: Icons.payments_rounded,
          title: _receiptOnly
              ? tr(context, ru: 'Сумма ранее созданной оплаты', zh: '先前付款金额')
              : tr(context, ru: 'Сумма к оплате', zh: '应付金额'),
          child: Text(
            widget.selection?.method == 'usdt_trc20' ||
                    widget.selection?.method == 'alipay'
                ? '${widget.selection!.amount.toStringAsFixed(widget.selection!.method == 'usdt_trc20' ? 6 : 2)} ${widget.selection!.currency}'
                : _formatRubKopecks(res.sumKopecks),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Gilroy',
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (!_receiptOnly)
          _BankQrSectionCard(
            icon: Icons.qr_code_2_rounded,
            title: tr(context, ru: 'QR для оплаты', zh: '付款二维码'),
            child: Column(
              children: [
                if (widget.selection == null ||
                    widget.selection!.method == 'bank_qr')
                  const PaymentRecipientWarning(),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.04),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 24,
                          spreadRadius: -16,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: 220,
                      child: widget.selection?.qrImageUrl != null
                          ? Image(
                              image: authenticatedImageProvider(
                                context,
                                ApiConfig.getMediaUrl(
                                  widget.selection!.qrImageUrl!,
                                ),
                              ),
                              width: 220,
                              height: 220,
                              fit: BoxFit.contain,
                              frameBuilder:
                                  (context, child, frame, synchronous) {
                                    if (synchronous || frame != null) {
                                      return child;
                                    }
                                    return SizedBox(
                                      width: 220,
                                      height: 220,
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const CircularProgressIndicator(),
                                          const SizedBox(height: 12),
                                          Text(
                                            tr(
                                              context,
                                              ru: 'Загрузка QR-кода…',
                                              zh: '正在加载二维码…',
                                            ),
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                              errorBuilder: (_, error, stack) => SizedBox(
                                width: 220,
                                height: 220,
                                child: Center(
                                  child: Text(
                                    tr(
                                      context,
                                      ru: 'Не удалось загрузить QR',
                                      zh: '无法加载二维码',
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : QrImageView(
                              data: res.qrPayload,
                              version: QrVersions.auto,
                              size: 220,
                              backgroundColor: Colors.white,
                              errorStateBuilder: (context, error) => SizedBox(
                                width: 220,
                                height: 220,
                                child: Center(
                                  child: Text(
                                    tr(context, ru: 'Ошибка QR', zh: 'QR 错误'),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  tr(
                    context,
                    ru: widget.selection?.method == 'alipay'
                        ? 'Отсканируйте QR в Alipay'
                        : widget.selection?.method == 'usdt_trc20'
                        ? 'Отправляйте только USDT по сети TRC20'
                        : 'Отсканируйте QR в приложении банка',
                    zh: widget.selection?.method == 'alipay'
                        ? '请使用支付宝扫描二维码'
                        : widget.selection?.method == 'usdt_trc20'
                        ? '仅通过 TRC20 网络发送 USDT'
                        : '在银行应用中扫描二维码',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'Gilroy',
                    fontSize: 12.5,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _BankQrSecondaryButton(
                  label: _downloadingQr
                      ? tr(context, ru: 'Готовим файл…', zh: '正在准备文件…')
                      : tr(context, ru: 'Сохранить QR-код', zh: '保存二维码'),
                  icon: Icons.save_alt_rounded,
                  onTap: _downloadingQr ? null : _downloadQr,
                ),
              ],
            ),
          ),
        if (!_receiptOnly && widget.selection?.walletAddress != null) ...[
          const SizedBox(height: 12),
          _BankQrSectionCard(
            icon: Icons.account_balance_wallet_outlined,
            title:
                '${tr(context, ru: 'Адрес кошелька', zh: '钱包地址')} · ${widget.selection!.network ?? 'TRC20'}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectableText(widget.selection!.walletAddress!),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: widget.selection!.walletAddress!),
                    );
                    if (!mounted) return;
                    AppToast.show(
                      context,
                      tr(context, ru: 'Адрес скопирован', zh: '地址已复制'),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: Text(tr(context, ru: 'Копировать адрес', zh: '复制地址')),
                ),
              ],
            ),
          ),
        ],
        if (widget.onChangeMethod != null) ...[
          const SizedBox(height: 12),
          _BankQrSecondaryButton(
            label: tr(context, ru: 'Изменить способ оплаты', zh: '更改付款方式'),
            icon: Icons.swap_horiz_rounded,
            onTap: _uploading ? null : widget.onChangeMethod,
          ),
        ],
        const SizedBox(height: 12),
        _BankQrSectionCard(
          icon: Icons.upload_file_rounded,
          title: tr(context, ru: 'Чек об оплате', zh: '付款凭证'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(
                  context,
                  ru: _receiptOnly
                      ? 'Приложите чек ранее выполненного перевода. После успешной отправки счёт уйдёт сотруднику на проверку.'
                      : 'Оплатите выбранным способом и приложите чек. После успешной отправки счёт уйдёт сотруднику на проверку.',
                  zh: _receiptOnly
                      ? '请附上先前转账的凭证，发送成功后账单将提交给工作人员审核。'
                      : '付款后附上凭证，发送成功后账单将提交给工作人员审核。',
                ),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'Gilroy',
                  fontSize: 13,
                  height: 1.28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              if (_fileBytes != null)
                _BankQrSecondaryButton(
                  label: tr(context, ru: 'Заменить чек', zh: '更换凭证'),
                  icon: Icons.attach_file_rounded,
                  onTap: _uploading ? null : _pickReceipt,
                ),
              if (_fileBytes != null) ...[
                const SizedBox(height: 10),
                _receiptPreview(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _formatRubKopecks(int kopecks) {
    final safe = kopecks < 0 ? 0 : kopecks;
    return '${safe ~/ 100}.${(safe % 100).toString().padLeft(2, '0')} ₽';
  }

  Widget _buildFooter() {
    if (_loading) {
      return _BankQrPrimaryButton(
        label: tr(context, ru: 'Подготовка QR…', zh: '正在生成二维码…'),
        icon: Icons.hourglass_empty_rounded,
        onTap: null,
      );
    }
    if (_error != null) {
      return _BankQrSecondaryButton(
        label: tr(context, ru: 'Закрыть', zh: '关闭'),
        icon: Icons.close_rounded,
        onTap: () => Navigator.of(context).pop(false),
      );
    }
    return _BankQrPrimaryButton(
      label: _fileBytes == null
          ? tr(context, ru: 'Приложить чек', zh: '附加付款凭证')
          : tr(context, ru: 'Повторить отправку', zh: '重新发送'),
      icon: Icons.check_circle_outline_rounded,
      isLoading: _uploading,
      onTap: _uploading
          ? null
          : (_fileBytes == null ? _pickReceipt : _confirmPaid),
    );
  }

  Widget _receiptPreview() {
    final bytes = _fileBytes!;
    final isPdf = _fileMime == 'application/pdf';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isPdf
                  ? Colors.redAccent.withValues(alpha: 0.10)
                  : context.brandPrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: isPdf
                ? const Icon(
                    Icons.picture_as_pdf_rounded,
                    size: 28,
                    color: Colors.redAccent,
                  )
                : Image.memory(bytes, fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _fileName ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontFamily: 'Gilroy',
                fontSize: 13,
                height: 1.15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            onPressed: _uploading
                ? null
                : () => setState(() {
                    _fileBytes = null;
                    _fileName = null;
                    _fileMime = null;
                  }),
            icon: const Icon(Icons.close_rounded),
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _BankQrHeader extends StatelessWidget {
  final String invoiceNumber;
  final String method;

  const _BankQrHeader({required this.invoiceNumber, required this.method});

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
            child: const Icon(
              Icons.qr_code_2_rounded,
              color: Colors.white,
              size: 25,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  method == 'bank_qr'
                      ? tr(context, ru: 'Оплата в рублях', zh: '卢布支付')
                      : invoicePaymentMethodLabel(context, method),
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
                  tr(
                    context,
                    ru: 'Счёт $invoiceNumber',
                    zh: '账单 $invoiceNumber',
                  ),
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

class _BankQrLoadingCard extends StatelessWidget {
  const _BankQrLoadingCard();

  @override
  Widget build(BuildContext context) {
    return _BankQrSectionCard(
      icon: Icons.hourglass_empty_rounded,
      title: tr(context, ru: 'Готовим QR', zh: '正在生成二维码'),
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 22),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _BankQrSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _BankQrSectionCard({
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

class _BankQrPrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isLoading;

  const _BankQrPrimaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !isLoading;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: enabled ? onTap : null,
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
          child: isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : Row(
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

class _BankQrSecondaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _BankQrSecondaryButton({
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
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 140),
          opacity: enabled ? 1 : 0.52,
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: context.brandPrimary, size: 18),
                const SizedBox(width: 8),
                Flexible(
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
