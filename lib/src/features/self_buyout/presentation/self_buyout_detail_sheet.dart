import 'package:twoalogisticcabineuser/src/features/training/presentation/training_target.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/app_colors.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/ui/sheet_handle.dart';
import '../../../core/utils/file_download_helper.dart';
import '../../../core/utils/locale_text.dart';
import '../../purchase_blanks/presentation/purchase_blank_ui.dart';
import '../data/self_buyout_models.dart';
import '../data/self_buyout_service.dart';
import 'self_buyout_ui.dart';

enum SelfBuyoutDetailAction { continuePayment, correctRequisites, cancel }

class SelfBuyoutDetailSheet extends ConsumerStatefulWidget {
  final SelfBuyoutRequest request;

  const SelfBuyoutDetailSheet({super.key, required this.request});

  @override
  ConsumerState<SelfBuyoutDetailSheet> createState() =>
      _SelfBuyoutDetailSheetState();
}

class _SelfBuyoutDetailSheetState extends ConsumerState<SelfBuyoutDetailSheet> {
  final Map<int, Future<Uint8List>> _proofBytes = {};

  SelfBuyoutDetail? _detail;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await ref
          .read(selfBuyoutServiceProvider)
          .getDetail(widget.request.id);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = tr(
          context,
          ru: 'Не удалось загрузить информацию по заявке',
          zh: '无法加载申请信息',
        );
      });
    }
  }

  Future<Uint8List> _bytes(SelfBuyoutTransferProof proof) {
    return _proofBytes.putIfAbsent(
      proof.id,
      () => ref
          .read(selfBuyoutServiceProvider)
          .getTransferProofBytes(proof.fileUrl),
    );
  }

  Future<void> _openProof(SelfBuyoutTransferProof proof) async {
    try {
      final bytes = await _bytes(proof);
      if (!mounted) return;
      await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => _TransferProofViewer(
            bytes: bytes,
            fileName: proof.fileName,
            onDownload: () => _downloadProof(proof),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      AppToast.show(
        context,
        tr(context, ru: 'Не удалось открыть подтверждение', zh: '无法打开转账凭证'),
        isError: true,
      );
    }
  }

  Future<void> _downloadProof(SelfBuyoutTransferProof proof) async {
    try {
      final bytes = await _bytes(proof);
      final saved = await downloadFile(bytes: bytes, fileName: proof.fileName);
      if (!mounted) return;
      AppToast.show(
        context,
        saved
            ? tr(context, ru: 'Файл сохранён', zh: '文件已保存')
            : tr(context, ru: 'Не удалось сохранить файл', zh: '无法保存文件'),
        isError: !saved,
      );
    } catch (_) {
      if (!mounted) return;
      AppToast.show(
        context,
        tr(context, ru: 'Не удалось скачать файл', zh: '无法下载文件'),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentRequest = _detail?.request ?? widget.request;
    final canContinuePayment =
        currentRequest.status == 'new' ||
        currentRequest.status == 'awaiting_payment';
    final canCancel = currentRequest.status == 'awaiting_payment';
    final canCorrectRequisites =
        _detail?.cancellation?.canCorrectRequisites == true;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

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
            Center(
              child: TrainingTarget(
                id: 'selfbuyout.sheet.dismiss',
                onActivate: () => Navigator.of(context).pop(),
                child: const SizedBox(width: 42, child: SheetHandle()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: SelfBuyoutGradientHeader(
                icon: Icons.savings_rounded,
                title: currentRequest.requestNumber,
                subtitleTrainingTargetId: 'selfbuyout.request.status',
                subtitle: tr(
                  context,
                  ru: 'Самовыкуп · ${selfBuyoutStatusLabel(context, currentRequest.status)}',
                  zh: '自助代购 · ${selfBuyoutStatusLabel(context, currentRequest.status)}',
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _error != null
                    ? _errorCard()
                    : _content(_detail!),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + bottomPadding),
              child: canContinuePayment
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SelfBuyoutPrimaryButton(
                          label: tr(
                            context,
                            ru: 'Продолжить оплату',
                            zh: '继续付款',
                          ),
                          icon: Icons.qr_code_2_rounded,
                          onTap: () => Navigator.of(
                            context,
                          ).pop(SelfBuyoutDetailAction.continuePayment),
                        ),
                        if (canCancel) ...[
                          const SizedBox(height: 10),
                          SelfBuyoutSecondaryButton(
                            label: tr(
                              context,
                              ru: 'Отменить заявку',
                              zh: '取消申请',
                            ),
                            icon: Icons.delete_outline_rounded,
                            onTap: () => Navigator.of(
                              context,
                            ).pop(SelfBuyoutDetailAction.cancel),
                          ),
                        ],
                      ],
                    )
                  : canCorrectRequisites
                  ? SelfBuyoutPrimaryButton(
                      label: tr(
                        context,
                        ru: 'Исправить реквизиты',
                        zh: '修改收款信息',
                      ),
                      icon: Icons.edit_rounded,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(SelfBuyoutDetailAction.correctRequisites),
                    )
                  : SelfBuyoutSecondaryButton(
                      label: tr(context, ru: 'Закрыть', zh: '关闭'),
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard() {
    return _DetailCard(
      icon: Icons.error_outline_rounded,
      title: tr(context, ru: 'Ошибка загрузки', zh: '加载错误'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Gilroy',
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          SelfBuyoutSecondaryButton(
            label: tr(context, ru: 'Повторить', zh: '重试'),
            icon: Icons.refresh_rounded,
            onTap: _load,
          ),
        ],
      ),
    );
  }

  Widget _content(SelfBuyoutDetail detail) {
    final request = detail.request;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DetailCard(
          icon: Icons.info_outline_rounded,
          title: tr(context, ru: 'Информация о заявке', zh: '申请信息'),
          child: Column(
            children: [
              _InfoRow(
                label: tr(context, ru: 'Юани', zh: '人民币'),
                value:
                    '${formatSelfBuyoutMoney(context, request.requestedCnyAmount)} RMB',
              ),
              _InfoRow(
                label: tr(context, ru: 'К оплате', zh: '应付'),
                value:
                    '${formatSelfBuyoutMoney(context, request.paymentRubAmount)} ₽',
              ),
              _InfoRow(
                label: tr(context, ru: 'Курс', zh: '汇率'),
                value:
                    '1 RMB = ${request.clientCnyRubRate.toStringAsFixed(2)} ₽',
              ),
              if (request.createdAt != null)
                _InfoRow(
                  label: tr(context, ru: 'Создана', zh: '创建时间'),
                  value: _formatDate(request.createdAt!),
                ),
              if (request.yuanDeliveryDeadlineAt != null)
                _InfoRow(
                  label: tr(context, ru: 'Срок доставки', zh: '交付期限'),
                  value: _formatDate(request.yuanDeliveryDeadlineAt!),
                ),
            ],
          ),
        ),
        if (detail.payment != null) ...[
          const SizedBox(height: 12),
          _paymentCard(detail.payment!),
        ],
        if (detail.cancellation != null) ...[
          const SizedBox(height: 12),
          _cancellationCard(detail.cancellation!),
        ],
        const SizedBox(height: 12),
        _proofsCard(detail.transferProofs),
      ],
    );
  }

  Widget _paymentCard(SelfBuyoutPaymentInfo payment) {
    return _DetailCard(
      icon: Icons.payments_outlined,
      title: tr(context, ru: 'Оплата', zh: '付款'),
      child: Column(
        children: [
          _InfoRow(
            label: tr(context, ru: 'Сумма', zh: '金额'),
            value: '${formatSelfBuyoutMoney(context, payment.amountRub)} ₽',
          ),
          _InfoRow(
            label: tr(context, ru: 'Статус оплаты', zh: '付款状态'),
            value: _paymentStatusLabel(payment.status),
          ),
          if (payment.receiptStatus != null)
            _InfoRow(
              label: tr(context, ru: 'Чек клиента', zh: '客户凭证'),
              value: _receiptStatusLabel(payment.receiptStatus!),
            ),
          if (payment.receiptRejectReason != null &&
              payment.receiptRejectReason!.isNotEmpty)
            _InfoRow(
              label: tr(context, ru: 'Причина отклонения', zh: '拒绝原因'),
              value: payment.receiptRejectReason!,
              valueColor: Colors.redAccent,
            ),
        ],
      ),
    );
  }

  Widget _proofsCard(List<SelfBuyoutTransferProof> proofs) {
    return _DetailCard(
      icon: Icons.verified_outlined,
      title: tr(context, ru: 'Подтверждение перевода', zh: '转账凭证'),
      child: proofs.isEmpty
          ? Text(
              tr(
                context,
                ru: 'Партнёр пока не загрузил подтверждение перевода.',
                zh: '合作伙伴尚未上传转账凭证。',
              ),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Gilroy',
                fontSize: 13,
                height: 1.3,
                fontWeight: FontWeight.w700,
              ),
            )
          : Column(
              children: [
                for (var index = 0; index < proofs.length; index++) ...[
                  if (index > 0) const SizedBox(height: 12),
                  _TransferProofCard(
                    proof: proofs[index],
                    bytesFuture: _bytes(proofs[index]),
                    onOpen: () => _openProof(proofs[index]),
                    onDownload: () => _downloadProof(proofs[index]),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _cancellationCard(SelfBuyoutCancellation cancellation) {
    return _DetailCard(
      icon: Icons.cancel_outlined,
      title: tr(context, ru: 'Причина отмены', zh: '取消原因'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cancellation.source == 'partner') ...[
            Text(
              tr(context, ru: 'Отменено платёжным партнёром', zh: '由支付合作伙伴取消'),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Gilroy',
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            cancellation.reason,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Gilroy',
              fontSize: 13.5,
              height: 1.3,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (cancellation.canCorrectRequisites) ...[
            const SizedBox(height: 9),
            Text(
              tr(
                context,
                ru: 'Партнёр указал, что реквизиты неверны. Загрузите правильное изображение QR или реквизитов и повторно отправьте эту заявку.',
                zh: '合作伙伴指出收款信息有误。请上传正确的二维码或收款信息图片并重新提交申请。',
              ),
              style: TextStyle(
                color: context.brandPrimary,
                fontFamily: 'Gilroy',
                fontSize: 12.5,
                height: 1.3,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _paymentStatusLabel(String status) {
    switch (status) {
      case 'success':
        return tr(context, ru: 'Оплачено', zh: '已付款');
      case 'underpaid':
        return tr(context, ru: 'Недоплата', zh: '付款不足');
      case 'overpaid':
        return tr(context, ru: 'Переплата', zh: '多付');
      case 'fail':
        return tr(context, ru: 'Ошибка', zh: '失败');
      case 'refunded':
        return tr(context, ru: 'Возвращено', zh: '已退款');
      case 'chargeback':
        return tr(context, ru: 'Возврат платежа', zh: '退款处理');
      default:
        return tr(context, ru: 'Ожидает оплаты', zh: '待付款');
    }
  }

  String _receiptStatusLabel(String status) {
    switch (status) {
      case 'approved':
        return tr(context, ru: 'Подтверждён', zh: '已确认');
      case 'rejected':
        return tr(context, ru: 'Отклонён', zh: '已拒绝');
      case 'replaced':
        return tr(context, ru: 'Заменён', zh: '已替换');
      default:
        return tr(context, ru: 'На проверке', zh: '待审核');
    }
  }
}

class _DetailCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _DetailCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: PurchaseBlankUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: context.brandPrimary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: context.brandPrimary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
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
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Gilroy',
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: valueColor ?? AppColors.textPrimary,
                fontFamily: 'Gilroy',
                fontSize: 13,
                height: 1.2,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferProofCard extends StatelessWidget {
  final SelfBuyoutTransferProof proof;
  final Future<Uint8List> bytesFuture;
  final VoidCallback onOpen;
  final VoidCallback onDownload;

  const _TransferProofCard({
    required this.proof,
    required this.bytesFuture,
    required this.onOpen,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: bytesFuture,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        final bytes = snapshot.data;
        final loaded = bytes != null && bytes.isNotEmpty;
        return Material(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: loaded ? onOpen : null,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          proof.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontFamily: 'Gilroy',
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: tr(context, ru: 'Скачать', zh: '下载'),
                        onPressed: loaded ? onDownload : null,
                        icon: const Icon(Icons.download_rounded),
                        color: context.brandPrimary,
                      ),
                    ],
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: double.infinity,
                      height: 190,
                      color: Colors.white,
                      alignment: Alignment.center,
                      child: loading
                          ? const CircularProgressIndicator()
                          : !loaded
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.broken_image_outlined,
                                  color: AppColors.textSecondary,
                                  size: 38,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  tr(
                                    context,
                                    ru: 'Не удалось загрузить фото',
                                    zh: '无法加载图片',
                                  ),
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontFamily: 'Gilroy',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            )
                          : Image.memory(
                              bytes,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.broken_image_outlined,
                                color: AppColors.textSecondary,
                                size: 38,
                              ),
                            ),
                    ),
                  ),
                  if (proof.comment != null &&
                      proof.comment!.trim().isNotEmpty) ...[
                    const SizedBox(height: 9),
                    Text(
                      proof.comment!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontFamily: 'Gilroy',
                        fontSize: 12.5,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 7),
                  Text(
                    [
                      if (proof.createdAt != null)
                        _formatDate(proof.createdAt!),
                      _formatFileSize(proof.size),
                    ].join(' · '),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontFamily: 'Gilroy',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TransferProofViewer extends StatelessWidget {
  final Uint8List bytes;
  final String fileName;
  final VoidCallback onDownload;

  const _TransferProofViewer({
    required this.bytes,
    required this.fileName,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: tr(context, ru: 'Скачать', zh: '下载'),
            onPressed: onDownload,
            icon: const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 5,
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
