import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/ui/app_colors.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/ui/blurred_modal_bottom_sheet.dart';
import '../../../core/ui/sheet_handle.dart';
import '../../../core/utils/locale_text.dart';
import '../../payments/data/payment_operator_status.dart';
import '../../payments/presentation/payment_operator_sleeping_notice.dart';
import '../../payments/presentation/payment_qr_timing_warning.dart';
import '../../payments/presentation/payment_receipt_picker.dart';
import '../application/garage_providers.dart';
import '../domain/garage_models.dart';
import 'garage_ui.dart';

Future<bool?> showGaragePaymentSheet({
  required BuildContext context,
  required int orderId,
  required String orderNumber,
}) {
  return showBlurredModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        GaragePaymentSheet(orderId: orderId, orderNumber: orderNumber),
  );
}

class GaragePaymentSheet extends ConsumerStatefulWidget {
  final int orderId;
  final String orderNumber;

  const GaragePaymentSheet({
    super.key,
    required this.orderId,
    required this.orderNumber,
  });

  @override
  ConsumerState<GaragePaymentSheet> createState() => _GaragePaymentSheetState();
}

class _GaragePaymentSheetState extends ConsumerState<GaragePaymentSheet> {
  GarageBankQrPayment? _payment;
  Uint8List? _receiptBytes;
  String? _receiptName;
  String? _receiptMime;
  String? _error;
  bool _loading = true;
  bool _uploading = false;
  bool _timingWarningShown = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_start);
  }

  Future<void> _start() async {
    final current = ref.read(paymentOperatorStatusProvider).asData?.value;
    final operatorStatus =
        current ??
        await ref.read(paymentOperatorStatusProvider.future) ??
        PaymentOperatorStatus.workingFallback;
    if (!mounted) return;
    if (operatorStatus.sleeping) {
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
      final payment = await ref
          .read(garageRepositoryProvider)
          .startBankQrPayment(
            widget.orderId,
            idempotencyKey: const Uuid().v4(),
          );
      if (!mounted) return;
      setState(() {
        _payment = payment;
        _loading = false;
      });
      if (!_timingWarningShown) {
        _timingWarningShown = true;
        await showPaymentQrTimingWarning(context);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = tr(
          context,
          ru: 'Не удалось подготовить QR для оплаты',
          zh: '无法生成付款二维码',
        );
      });
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
        _receiptBytes = receipt.bytes;
        _receiptName = receipt.fileName;
        _receiptMime = receipt.mimeType;
      });
      await _upload();
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

  Future<void> _upload() async {
    final payment = _payment;
    final bytes = _receiptBytes;
    if (payment == null || bytes == null || _uploading) return;
    setState(() => _uploading = true);
    try {
      final upload = await ref
          .read(garageRepositoryProvider)
          .uploadPaymentReceipt(
            paymentId: payment.paymentId,
            bytes: bytes,
            fileName: _receiptName ?? 'receipt',
            mimeType: _receiptMime ?? 'application/octet-stream',
          );
      if (!mounted) return;
      if (upload.invoiceStatus != 'payment_review' ||
          upload.paymentId != payment.paymentId) {
        throw StateError('Receipt review was not confirmed');
      }
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
                ru: 'Не удалось отправить чек. Повторите отправку.',
                zh: '无法提交付款凭证，请重试。',
              ),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final operatorsSleeping = paymentOperatorStatusOrWorking(
      ref.watch(paymentOperatorStatusProvider),
    ).sleeping;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF7F9FC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: Row(
              children: [
                Icon(
                  Icons.qr_code_2_rounded,
                  color: context.brandPrimary,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(context, ru: 'Оплата автозапчастей', zh: '汽车配件付款'),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontFamily: 'Gilroy',
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        tr(
                          context,
                          ru: 'Заказ ${widget.orderNumber}',
                          zh: '订单 ${widget.orderNumber}',
                        ),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontFamily: 'Gilroy',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 4, 16, bottom + 18),
              child: operatorsSleeping
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const PaymentOperatorSleepingNotice(),
                        const SizedBox(height: 12),
                        GarageSecondaryButton(
                          label: tr(context, ru: 'Закрыть', zh: '关闭'),
                          icon: Icons.close_rounded,
                          onPressed: () => Navigator.of(context).pop(false),
                        ),
                      ],
                    )
                  : _loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 70),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _error != null
                  ? GarageEmptyState(
                      icon: Icons.error_outline_rounded,
                      title: tr(context, ru: 'Оплата недоступна', zh: '无法付款'),
                      subtitle: _error!,
                      action: GarageSecondaryButton(
                        label: tr(context, ru: 'Повторить', zh: '重试'),
                        icon: Icons.refresh_rounded,
                        onPressed: _start,
                      ),
                    )
                  : _content(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    final payment = _payment!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GarageCard(
          child: Column(
            children: [
              const PaymentRecipientWarning(),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: QrImageView(
                  data: payment.qrPayload,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                  errorStateBuilder: (_, _) => SizedBox(
                    width: 220,
                    height: 220,
                    child: Center(
                      child: Text(
                        tr(context, ru: 'QR-код недоступен', zh: '二维码不可用'),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _formatRubKopecks(payment.sumKopecks),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'Gilroy',
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (payment.invoiceNumber.trim().isNotEmpty) ...[
                const SizedBox(height: 5),
                SelectableText(
                  tr(
                    context,
                    ru: 'Счёт ${payment.invoiceNumber}',
                    zh: '账单 ${payment.invoiceNumber}',
                  ),
                  key: const ValueKey('garage-payment-invoice-number'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              const SizedBox(height: 5),
              Text(
                payment.purpose,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'Gilroy',
                  fontSize: 12.5,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GarageCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(context, ru: 'Чек об оплате', zh: '付款凭证'),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'Gilroy',
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr(
                  context,
                  ru: 'Оплатите по QR, приложите фото или PDF чека. Платёж перейдёт на проверку.',
                  zh: '扫码付款后，请上传图片或 PDF 凭证。付款将提交审核。',
                ),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'Gilroy',
                  fontSize: 13,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              if (_receiptBytes != null)
                GarageSecondaryButton(
                  label: tr(context, ru: 'Заменить чек', zh: '更换凭证'),
                  icon: Icons.attach_file_rounded,
                  onPressed: _uploading ? null : _pickReceipt,
                ),
              if (_receiptBytes != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F9FC),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _receiptMime == 'application/pdf'
                            ? Icons.picture_as_pdf_rounded
                            : Icons.image_rounded,
                        color: context.brandPrimary,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          _receiptName ?? tr(context, ru: 'Чек', zh: '付款凭证'),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Gilroy',
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              GaragePrimaryButton(
                label: _receiptBytes == null
                    ? tr(context, ru: 'Приложить чек', zh: '附加付款凭证')
                    : tr(context, ru: 'Повторить отправку', zh: '重新发送'),
                icon: Icons.check_circle_outline_rounded,
                onPressed: _uploading
                    ? null
                    : (_receiptBytes == null ? _pickReceipt : _upload),
                loading: _uploading,
              ),
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
}
