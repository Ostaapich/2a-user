import '../../../core/services/analytics_service.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_target.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/ui/app_colors.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/ui/blurred_modal_bottom_sheet.dart';
import '../../../core/ui/sheet_handle.dart';
import '../../../core/utils/locale_text.dart';
import '../../clients/application/client_codes_controller.dart';
import '../data/self_buyout_models.dart';
import '../data/self_buyout_service.dart';
import 'self_buyout_ui.dart';

const _imgExt = ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'];

String _mimeForExt(String ext) {
  switch (ext.toLowerCase()) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'heic':
      return 'image/heic';
    case 'heif':
      return 'image/heif';
    default:
      return 'application/octet-stream';
  }
}

double _floorWhole(double x) => x.floorToDouble();

String _formatAmount(double value) => value
    .toStringAsFixed(2)
    .replaceFirst(RegExp(r'\.00$'), '')
    .replaceFirst(RegExp(r'(\.\d)0$'), r'$1');

/// Модалка создания заявки самовыкупа. Возвращает созданную заявку (pop).
class SelfBuyoutCreateSheet extends ConsumerStatefulWidget {
  final SelfBuyoutAvailability? availability;
  final SelfBuyoutRequest? correctionRequest;
  final bool? alipayTopUpExperienced;

  const SelfBuyoutCreateSheet({
    super.key,
    required this.availability,
    this.alipayTopUpExperienced,
  }) : correctionRequest = null;

  const SelfBuyoutCreateSheet.correctRequisites({
    super.key,
    required this.correctionRequest,
  }) : availability = null,
       alipayTopUpExperienced = null,
       assert(correctionRequest != null);

  @override
  ConsumerState<SelfBuyoutCreateSheet> createState() =>
      _SelfBuyoutCreateSheetState();
}

class _SelfBuyoutCreateSheetState extends ConsumerState<SelfBuyoutCreateSheet> {
  @override
  void initState() {
    super.initState();
    if (widget.correctionRequest == null) {
      AnalyticsService.trackFunnel(
        WorkflowAction.selfBuyoutCreate,
        WorkflowStage.viewed,
      );
    }
  }

  final _cnyCtrl = TextEditingController();
  final _rubCtrl = TextEditingController();
  bool _syncing = false;
  String _enteredIn = 'cny';

  Uint8List? _fileBytes;
  String? _fileName;
  String? _fileMime;
  bool _warningAccepted = false;
  bool _submitting = false;

  double get _rate =>
      widget.correctionRequest?.clientCnyRubRate ??
      widget.availability?.clientCnyRubRate ??
      0;

  bool get _isCorrection => widget.correctionRequest != null;

  double? get _effectiveMaxCny {
    final availability = widget.availability;
    if (availability == null || !availability.firstExchangeActive) return null;
    if (availability.maxCny != null) return availability.maxCny;
    return widget.alipayTopUpExperienced == false
        ? availability.firstExchangeInexperiencedMaxCny
        : null;
  }

  @override
  void dispose() {
    _cnyCtrl.dispose();
    _rubCtrl.dispose();
    super.dispose();
  }

  void _onCnyChanged(String v) {
    if (_syncing) return;
    _enteredIn = 'cny';
    final cny = double.tryParse(v.replaceAll(',', '.')) ?? 0;
    _syncing = true;
    _rubCtrl.text = cny > 0 && _rate > 0
        ? _floorWhole(_floorWhole(cny) * _rate).toStringAsFixed(0)
        : '';
    _syncing = false;
    setState(() {});
  }

  void _onRubChanged(String v) {
    if (_syncing) return;
    _enteredIn = 'rub';
    final rub = double.tryParse(v.replaceAll(',', '.')) ?? 0;
    _syncing = true;
    _cnyCtrl.text = rub > 0 && _rate > 0
        ? _floorWhole(_floorWhole(rub) / _rate).toStringAsFixed(0)
        : '';
    _syncing = false;
    setState(() {});
  }

  Future<void> _setPickedImage({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final ext = fileName.split('.').last.toLowerCase();
    if (!_imgExt.contains(ext)) {
      if (!mounted) return;
      AppToast.show(
        context,
        tr(context, ru: 'Неподдерживаемый формат', zh: '不支持的格式'),
        isError: true,
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _fileBytes = bytes;
      _fileName = fileName;
      _fileMime = _mimeForExt(ext);
    });
  }

  Future<void> _pickImageFromFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _imgExt,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      if (!mounted) return;
      final f = result.files.first;
      final bytes = f.bytes ?? await f.xFile.readAsBytes();
      if (!mounted) return;
      final ext = (f.extension ?? f.name.split('.').last).toLowerCase();
      final fileName = f.name.contains('.') ? f.name : '${f.name}.$ext';
      await _setPickedImage(bytes: bytes, fileName: fileName);
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          tr(context, ru: 'Не удалось выбрать файл', zh: '无法选择文件'),
          isError: true,
        );
      }
    }
  }

  Future<void> _pickImageFromPhotos() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      if (!mounted) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      await _setPickedImage(bytes: bytes, fileName: picked.name);
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          tr(context, ru: 'Не удалось выбрать фото', zh: '无法选择照片'),
          isError: true,
        );
      }
    }
  }

  Future<void> _pickImage() async {
    FocusScope.of(context).unfocus();
    final source = await showBlurredModalBottomSheet<String>(
      context: context,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_rounded,
                  color: AppColors.brandOrange,
                ),
                title: Text(
                  tr(context, ru: 'Выбрать из фото', zh: '从相册选择'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                onTap: () => Navigator.of(sheetContext).pop('photos'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.folder_rounded,
                  color: AppColors.brandOrange,
                ),
                title: Text(
                  tr(context, ru: 'Выбрать из файлов', zh: '从文件选择'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                onTap: () => Navigator.of(sheetContext).pop('files'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!mounted || source == null) return;
    if (source == 'photos') {
      await _pickImageFromPhotos();
    } else if (source == 'files') {
      await _pickImageFromFiles();
    }
  }

  String? _validate() {
    if (_isCorrection) {
      if (_fileBytes == null) {
        return tr(
          context,
          ru: 'Приложите новое изображение QR или реквизитов',
          zh: '请上传新的二维码或收款信息图片',
        );
      }
      return null;
    }

    final cny = double.tryParse(_cnyCtrl.text.replaceAll(',', '.')) ?? 0;
    final rub = double.tryParse(_rubCtrl.text.replaceAll(',', '.')) ?? 0;
    if (cny <= 0 || rub <= 0) {
      return tr(context, ru: 'Введите сумму', zh: '请输入金额');
    }
    final availability = widget.availability!;
    if (availability.isBelowMinimum(cny)) {
      final min = availability.minCny!;
      return tr(
        context,
        ru: 'Минимальная сумма самовыкупа — ${_formatAmount(min)} ¥',
        zh: '自助代购最低金额为 ${_formatAmount(min)} ¥',
      );
    }
    if (_effectiveMaxCny != null && cny > _effectiveMaxCny!) {
      return tr(
        context,
        ru: 'Для первого пополнения максимальная сумма — ${_formatAmount(_effectiveMaxCny!)} ¥',
        zh: '首次充值最高金额为 ${_formatAmount(_effectiveMaxCny!)} ¥',
      );
    }
    final activeCodeId = ref.read(activeClientCodeIdProvider);
    if (activeCodeId == null) {
      return tr(
        context,
        ru: 'Выберите код клиента в верхнем меню',
        zh: '请在顶部菜单选择客户代码',
      );
    }
    if (_fileBytes == null) {
      return tr(
        context,
        ru: 'Приложите изображение QR или реквизитов',
        zh: '请上传二维码或收款信息图片',
      );
    }
    if (!_warningAccepted) {
      return tr(context, ru: 'Подтвердите условия', zh: '请确认条款');
    }
    return null;
  }

  Future<void> _submit() async {
    final err = _validate();
    if (err != null) {
      AppToast.show(context, err, isError: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      final service = ref.read(selfBuyoutServiceProvider);
      final correctionRequest = widget.correctionRequest;
      final result = correctionRequest != null
          ? await service.correctTransferRequisites(
              requestId: correctionRequest.id,
              fileBytes: _fileBytes!,
              fileName: _fileName!,
              fileMime: _fileMime!,
            )
          : await service.createRequest(
              clientCodeId: ref.read(activeClientCodeIdProvider)!,
              amountEnteredIn: _enteredIn,
              amount: _enteredIn == 'cny'
                  ? double.parse(_cnyCtrl.text.replaceAll(',', '.'))
                  : double.parse(_rubCtrl.text.replaceAll(',', '.')),
              warningAccepted: true,
              alipayTopUpExperienced: widget.alipayTopUpExperienced,
              fileBytes: _fileBytes!,
              fileName: _fileName!,
              fileMime: _fileMime!,
            );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final data = e.response?.data is Map
          ? e.response?.data as Map
          : const <dynamic, dynamic>{};
      final code = data['code']?.toString();
      final serverMinCny = (data['minCny'] as num?)?.toDouble();
      final serverMaxCny = (data['maxCny'] as num?)?.toDouble();
      final reason =
          code == 'SELF_BUYOUT_AMOUNT_BELOW_MINIMUM' && serverMinCny != null
          ? tr(
              context,
              ru: 'Минимальная сумма самовыкупа — ${_formatAmount(serverMinCny)} ¥',
              zh: '自助代购最低金额为 ${_formatAmount(serverMinCny)} ¥',
            )
          : code == 'FIRST_SELF_BUYOUT_AMOUNT_ABOVE_MAXIMUM' &&
                serverMaxCny != null
          ? tr(
              context,
              ru: 'Для первого пополнения максимальная сумма — ${_formatAmount(serverMaxCny)} ¥',
              zh: '首次充值最高金额为 ${_formatAmount(serverMaxCny)} ¥',
            )
          : code == 'REQUEST_IN_PROGRESS'
          ? tr(
              context,
              ru: 'Заявка ещё создаётся. Повторите через несколько секунд — повтор не создаст новую заявку.',
              zh: '申请正在创建。请稍后重试，重复操作不会新建申请。',
            )
          : (e.response == null || (e.response?.statusCode ?? 0) >= 500) &&
                !_isCorrection
          ? tr(
              context,
              ru: 'Не удалось подтвердить создание заявки. Повторите с теми же данными — повтор не создаст дубликат.',
              zh: '无法确认申请是否创建成功。请使用相同数据重试，不会重复创建。',
            )
          : data['error']?.toString();
      AppToast.show(
        context,
        reason ??
            (_isCorrection
                ? tr(
                    context,
                    ru: 'Не удалось обновить реквизиты',
                    zh: '无法更新收款信息',
                  )
                : tr(context, ru: 'Не удалось создать заявку', zh: '无法创建申请')),
        isError: true,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppToast.show(
        context,
        tr(
          context,
          ru: 'Не удалось завершить запрос. Данные сохранены в форме, попробуйте ещё раз.',
          zh: '无法完成请求。表单数据已保留，请重试。',
        ),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final activeCode = ref.watch(activeClientCodeProvider);
    final rateStr = _rate > 0 ? _rate.toStringAsFixed(2) : '—';
    final correctionRequest = widget.correctionRequest;

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
                icon: correctionRequest == null
                    ? Icons.add_card_rounded
                    : Icons.edit_rounded,
                title: correctionRequest == null
                    ? tr(context, ru: 'Новая заявка', zh: '新申请')
                    : tr(context, ru: 'Исправить реквизиты', zh: '修改收款信息'),
                subtitle: tr(
                  context,
                  ru: correctionRequest == null
                      ? 'Самовыкуп — помощь с юанями'
                      : correctionRequest.requestNumber,
                  zh: correctionRequest == null
                      ? '自助代购 — 人民币支持'
                      : correctionRequest.requestNumber,
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (correctionRequest == null) ...[
                      _individualOnlyNotice(),
                      const SizedBox(height: 12),
                      _rateCard(rateStr),
                      const SizedBox(height: 12),
                      _converterCard(),
                      if (_effectiveMaxCny != null) ...[
                        const SizedBox(height: 10),
                        _firstExchangeLimitNotice(_effectiveMaxCny!),
                      ],
                      const SizedBox(height: 12),
                      _activeCodeCard(activeCode),
                      const SizedBox(height: 12),
                    ] else ...[
                      _correctionSummaryCard(correctionRequest),
                      const SizedBox(height: 12),
                    ],
                    _requisitesCard(),
                    if (correctionRequest == null) ...[
                      const SizedBox(height: 12),
                      _warningCard(),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + bottomPadding),
              child: TrainingTarget(
                id: 'selfbuyout.submit',
                child: SelfBuyoutPrimaryButton(
                  label: correctionRequest == null
                      ? tr(context, ru: 'Создать заявку', zh: '创建申请')
                      : tr(
                          context,
                          ru: 'Отправить на рассмотрение',
                          zh: '提交审核',
                        ),
                  icon: correctionRequest == null
                      ? Icons.check_rounded
                      : Icons.send_rounded,
                  isLoading: _submitting,
                  onTap: _submitting ? null : _submit,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
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
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 14.5,
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

  Widget _individualOnlyNotice() {
    return Container(
      key: const ValueKey('self-buyout-individual-only-notice'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF97316), Color(0xFFEA580C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33EA580C),
            blurRadius: 18,
            spreadRadius: -8,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
            ),
            child: const Icon(
              Icons.person_rounded,
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
                  tr(context, ru: 'Только для физических лиц', zh: '仅限个人用户'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Gilroy',
                    fontSize: 18,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  tr(
                    context,
                    ru: 'Услуга предоставляется только физическим лицам. Если вы ИП, напишите менеджеру в чат поддержки.',
                    zh: '本服务仅向个人提供。如果您是个体经营者，请在客服聊天中联系经理。',
                  ),
                  style: const TextStyle(
                    color: Color(0xF2FFFFFF),
                    fontFamily: 'Gilroy',
                    fontSize: 13.5,
                    height: 1.3,
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

  Widget _firstExchangeLimitNotice(double maxCny) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, color: Color(0xFFD97706), size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              tr(
                context,
                ru: 'Так как вы ранее не пополняли Alipay минимум 3 раза, сумма первого пополнения ограничена ${_formatAmount(maxCny)} ¥.',
                zh: '由于您此前未完成至少 3 次支付宝充值，首次充值金额上限为 ${_formatAmount(maxCny)} ¥。',
              ),
              style: const TextStyle(
                color: Color(0xFF92400E),
                fontFamily: 'Gilroy',
                fontSize: 12.5,
                height: 1.3,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rateCard(String rateStr) {
    return _card(
      icon: Icons.currency_exchange_rounded,
      title: tr(context, ru: 'Текущий курс', zh: '当前汇率'),
      child: Row(
        children: [
          Text(
            '1 RMB = $rateStr ₽',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Gilroy',
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          if (widget.availability?.rateDate != null)
            Text(
              widget.availability!.rateDate!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Gilroy',
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }

  Widget _converterCard() {
    return _card(
      icon: Icons.swap_vert_rounded,
      title: tr(context, ru: 'Сумма', zh: '金额'),
      child: Column(
        children: [
          if ((widget.availability?.minCny ?? 0) > 0) ...[
            _minimumAmountNotice(widget.availability!.minCny!),
            const SizedBox(height: 10),
          ],
          TrainingTarget(
            id: 'selfbuyout.amount',
            child: _amountField(
              controller: _cnyCtrl,
              label: tr(context, ru: 'Нужно юаней (RMB)', zh: '需要人民币 (RMB)'),
              onChanged: _onCnyChanged,
            ),
          ),
          const SizedBox(height: 10),
          _amountField(
            controller: _rubCtrl,
            label: tr(context, ru: 'К оплате рублей (₽)', zh: '应付卢布 (₽)'),
            onChanged: _onRubChanged,
          ),
        ],
      ),
    );
  }

  Widget _minimumAmountNotice(double minCny) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.brandPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.brandPrimary.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: context.brandPrimary,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    context,
                    ru: 'Минимум — ${_formatAmount(minCny)} ¥',
                    zh: '最低金额 — ${_formatAmount(minCny)} ¥',
                  ),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  tr(
                    context,
                    ru: 'Можно указать любую большую сумму — верхнего лимита нет.',
                    zh: '可输入任意更高金额，不设上限。',
                  ),
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
        ],
      ),
    );
  }

  Widget _amountField({
    required TextEditingController controller,
    required String label,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: false),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontFamily: 'Gilroy',
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontFamily: 'Gilroy',
          fontWeight: FontWeight.w700,
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: context.brandPrimary.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  Widget _activeCodeCard(String? activeCode) {
    return _card(
      icon: Icons.qr_code_rounded,
      title: tr(context, ru: 'Код клиента', zh: '客户代码'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                activeCode ?? tr(context, ru: 'Код не выбран', zh: '未选择客户代码'),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'Gilroy',
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              tr(context, ru: 'из верхнего меню', zh: '来自顶部菜单'),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Gilroy',
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _requisitesCard() {
    return _card(
      icon: Icons.account_balance_wallet_rounded,
      title: tr(context, ru: 'Куда перевести юани', zh: '人民币转入哪里'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(
              context,
              ru: 'Загрузите изображение QR-кода или реквизитов получателя.',
              zh: '请上传收款人的二维码或收款信息图片。',
            ),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Gilroy',
              fontSize: 13,
              height: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          TrainingTarget(
            id: 'selfbuyout.requisites',
            child: SelfBuyoutSecondaryButton(
              label: _fileBytes == null
                  ? tr(context, ru: 'Приложить QR/изображение', zh: '附上二维码/图片')
                  : tr(context, ru: 'Заменить изображение', zh: '更换图片'),
              icon: Icons.qr_code_2_rounded,
              onTap: _pickImage,
            ),
          ),
          if (_fileBytes != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(_fileBytes!, height: 120, fit: BoxFit.cover),
            ),
          ],
        ],
      ),
    );
  }

  Widget _correctionSummaryCard(SelfBuyoutRequest request) {
    return _card(
      icon: Icons.paid_outlined,
      title: tr(context, ru: 'Оплата уже подтверждена', zh: '付款已确认'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${formatSelfBuyoutMoney(context, request.requestedCnyAmount)} RMB · '
            '${formatSelfBuyoutMoney(context, request.paymentRubAmount)} ₽',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Gilroy',
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            tr(
              context,
              ru: 'Повторно платить не нужно. После загрузки правильного изображения заявка вернётся партнёру на рассмотрение.',
              zh: '无需再次付款。上传正确图片后，申请将重新交由合作伙伴审核。',
            ),
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
    );
  }

  Widget _warningCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              context,
              ru: 'Оплата принимается только с карт физических лиц граждан РФ. Если оплата будет произведена не в день создания заявки, расчёт может быть пересчитан по актуальному курсу на день оплаты. После поступления юаней у вас есть 14 дней, чтобы оформить доставку товаров на наш склад в Китае. Иначе мы не сможем впредь оказывать помощь в самовыкупе.',
              zh: '仅接受俄罗斯公民个人银行卡付款。如果未在创建申请当天付款，金额可能会按付款当天的最新汇率重新计算。人民币到账后，您有 14 天时间安排货物送达我们在中国的仓库，否则我们将无法继续提供自助代购协助。',
            ),
            style: const TextStyle(
              color: Color(0xFF92400E),
              fontFamily: 'Gilroy',
              fontSize: 12.5,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          TrainingTarget(
            id: 'selfbuyout.terms',
            child: InkWell(
              onTap: () => setState(() => _warningAccepted = !_warningAccepted),
              borderRadius: BorderRadius.circular(10),
              child: Row(
                children: [
                  Icon(
                    _warningAccepted
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    color: context.brandPrimary,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr(context, ru: 'Я понимаю условия', zh: '我已了解条款'),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Gilroy',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
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
