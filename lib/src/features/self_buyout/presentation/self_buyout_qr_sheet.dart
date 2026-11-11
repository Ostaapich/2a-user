import '../../payments/utils/payment_qr_image.dart';
import '../../../core/services/analytics_service.dart';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/ui/app_colors.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/ui/sheet_handle.dart';
import '../../../core/utils/gallery_image_save_helper.dart';
import '../../../core/utils/locale_text.dart';
import '../../payments/data/payment_operator_status.dart';
import '../../payments/presentation/payment_operator_sleeping_notice.dart';
import '../../payments/presentation/payment_qr_timing_warning.dart';
import '../../payments/presentation/payment_receipt_picker.dart';
import '../data/self_buyout_models.dart';
import '../data/self_buyout_service.dart';
import 'self_buyout_ui.dart';

/// Модалка оплаты заявки самовыкупа в рублях: стартует QR, принимает чек.
class SelfBuyoutQrSheet extends ConsumerStatefulWidget {
  final int requestId;
  final String requestNumber;
  final double cnyAmount;
  final bool hasExistingPayment;

  const SelfBuyoutQrSheet({
    super.key,
    required this.requestId,
    required this.requestNumber,
    required this.cnyAmount,
    this.hasExistingPayment = false,
  });

  @override
  ConsumerState<SelfBuyoutQrSheet> createState() => _SelfBuyoutQrSheetState();
}

class _SelfBuyoutQrSheetState extends ConsumerState<SelfBuyoutQrSheet> {
  bool _loading = true;
  String? _error;
  SelfBuyoutPaymentInfo? _result;

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
    if (operatorStatus.sleeping && !widget.hasExistingPayment) {
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
      final service = ref.read(selfBuyoutServiceProvider);
      final res = operatorStatus.sleeping
          ? (await service.getDetail(widget.requestId)).payment
          : await service.startBankQr(widget.requestId);
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
      if (!_timingWarningShown) {
        _timingWarningShown = true;
        await showPaymentQrTimingWarning(
          context,
          paymentAttemptKey: 'self-buyout:${widget.requestId}:${res.paymentId}',
        );
      }
    } on DioException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = tr(
          context,
          ru: 'Оплата недоступна. Повторите.',
          zh: '支付不可用，请重试',
        );
      });
    }
  }

  String get _qrFileName {
    final safeNumber = widget.requestNumber
        .replaceAll(RegExp(r'[^A-Za-z0-9а-яА-ЯёЁ_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return '2a_self_buyout_${safeNumber.isEmpty ? widget.requestId : safeNumber}_qr.png';
  }

  Future<void> _downloadQr() async {
    final res = _result;
    if (res == null || _downloadingQr) return;
    setState(() => _downloadingQr = true);
    try {
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
      final ok = await ref
          .read(selfBuyoutServiceProvider)
          .uploadReceipt(
            paymentId: res.paymentId,
            bytes: bytes,
            fileName: _fileName ?? 'receipt',
            mimeType: _fileMime ?? 'application/octet-stream',
          );
      if (!mounted) return;
      setState(() => _uploading = false);
      if (!ok) {
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
              child: SelfBuyoutGradientHeader(
                icon: Icons.qr_code_2_rounded,
                title: tr(context, ru: 'Оплата в рублях', zh: '卢布支付'),
                subtitle: tr(
                  context,
                  ru: 'Заявка ${widget.requestNumber}',
                  zh: '申请 ${widget.requestNumber}',
                ),
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
                    ? _SelfBuyoutCard(
                        icon: Icons.hourglass_empty_rounded,
                        title: tr(context, ru: 'Готовим QR', zh: '正在生成二维码'),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 22),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      )
                    : _error != null
                    ? _buildError()
                    : _buildContent(),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + bottomPadding),
              child: operatorsSleeping && _result == null
                  ? SelfBuyoutSecondaryButton(
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
    return _SelfBuyoutCard(
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
          SelfBuyoutPrimaryButton(
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
        const PaymentQrTimingNotice(),
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
        _SelfBuyoutCard(
          icon: Icons.qr_code_2_rounded,
          title: tr(context, ru: 'QR для оплаты', zh: '付款二维码'),
          child: Column(
            children: [
              const PaymentRecipientWarning(),
              if (res.qrPayload.isNotEmpty)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.04),
                      ),
                    ),
                    child: QrImageView(
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
              const SizedBox(height: 10),
              Text(
                '${formatSelfBuyoutMoney(context, res.amountRub)} ₽',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'Gilroy',
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                res.purpose,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'Gilroy',
                  fontSize: 12,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              if (res.qrPayload.isNotEmpty)
                SelfBuyoutSecondaryButton(
                  label: _downloadingQr
                      ? tr(context, ru: 'Готовим файл…', zh: '正在准备文件…')
                      : tr(context, ru: 'Сохранить QR-код', zh: '保存二维码'),
                  icon: Icons.save_alt_rounded,
                  onTap: _downloadingQr ? null : _downloadQr,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SelfBuyoutCard(
          icon: Icons.upload_file_rounded,
          title: tr(context, ru: 'Чек об оплате', zh: '付款凭证'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(
                  context,
                  ru: 'Оплатите по QR и приложите чек. После успешной отправки заявка уйдёт сотруднику на проверку.',
                  zh: '扫码付款后附上凭证，发送成功后申请将提交审核。',
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
                SelfBuyoutSecondaryButton(
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

  Widget _buildFooter() {
    if (_loading) {
      return SelfBuyoutPrimaryButton(
        label: tr(context, ru: 'Подготовка QR…', zh: '正在生成二维码…'),
        icon: Icons.hourglass_empty_rounded,
        onTap: null,
      );
    }
    if (_error != null) {
      return SelfBuyoutSecondaryButton(
        label: tr(context, ru: 'Закрыть', zh: '关闭'),
        icon: Icons.close_rounded,
        onTap: () => Navigator.of(context).pop(false),
      );
    }
    return SelfBuyoutPrimaryButton(
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

class _SelfBuyoutCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _SelfBuyoutCard({
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
