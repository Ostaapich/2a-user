import 'package:twoalogisticcabineuser/src/core/media/authenticated_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/network/api_config.dart';
import '../../../../core/ui/app_colors.dart';
import '../../../../core/ui/unsaved_changes_guard.dart';
import '../../../../core/ui/app_input_decoration.dart';
import '../../../../core/utils/locale_text.dart';
import '../../data/purchase_blank_model.dart';
import '../../data/blank_item_save_session.dart';
import '../purchase_blank_ui.dart';

typedef BlankItemPhotoPicker = Future<List<XFile>> Function();

/// Форма добавления / редактирования товара в бланке
class BlankItemForm extends StatefulWidget {
  /// Если передан — режим редактирования
  final PurchaseBlankItem? existingItem;

  /// Callback при сохранении
  final Future<void> Function({
    required String productName,
    required String productUrl,
    String? characteristics,
    required int quantity,
    required double unitPrice,
    List<Uint8List>? newPhotos,
    List<String>? newPhotoNames,
  })
  onSave;

  final VoidCallback? onCancel;
  final BlankItemPhotoPicker? photoPicker;

  const BlankItemForm({
    super.key,
    this.existingItem,
    required this.onSave,
    this.onCancel,
    this.photoPicker,
  });

  @override
  State<BlankItemForm> createState() => _BlankItemFormState();
}

class _BlankItemFormState extends State<BlankItemForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _charCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _priceCtrl;

  final List<_PickedPhoto> _pickedPhotos = [];
  bool _isSaving = false;
  bool _isPickingPhotos = false;
  String? _saveError;
  late final List<String> _initialValues;
  List<TextEditingController> get _controllers => [
    _nameCtrl,
    _urlCtrl,
    _charCtrl,
    _qtyCtrl,
    _priceCtrl,
  ];
  bool get _hasChanges =>
      _pickedPhotos.isNotEmpty ||
      List.generate(
        _controllers.length,
        (i) => _controllers[i].text != _initialValues[i],
      ).any((v) => v);
  Future<void> _cancel() async {
    if (_isSaving || _isPickingPhotos) return;
    if (_hasChanges && !await confirmDiscardChanges(context)) return;
    if (!mounted) return;
    widget.onCancel?.call();
  }

  @override
  void initState() {
    super.initState();
    final item = widget.existingItem;
    _nameCtrl = TextEditingController(text: item?.productName ?? '');
    _urlCtrl = TextEditingController(text: item?.productUrl ?? '');
    _charCtrl = TextEditingController(text: item?.characteristics ?? '');
    _qtyCtrl = TextEditingController(
      text: item != null ? '${item.quantity}' : '1',
    );
    _priceCtrl = TextEditingController(
      text: item != null ? item.unitPrice.toStringAsFixed(2) : '',
    );
    _initialValues = _controllers.map((c) => c.text).toList();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _charCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    if (_isPickingPhotos) return;
    setState(() => _isPickingPhotos = true);
    try {
      final images =
          await (widget.photoPicker?.call() ??
              ImagePicker().pickMultiImage(
                maxWidth: 1200,
                maxHeight: 1200,
                imageQuality: 80,
              ));
      if (!mounted || images.isEmpty) return;

      for (final xFile in images) {
        final bytes = await xFile.readAsBytes();
        if (!mounted) return;
        setState(() {
          _pickedPhotos.add(_PickedPhoto(bytes: bytes, name: xFile.name));
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isPickingPhotos = false);
      } else {
        _isPickingPhotos = false;
      }
    }
  }

  void _removePhoto(int index) {
    setState(() {
      _pickedPhotos.removeAt(index);
    });
  }

  Future<void> _save() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    try {
      await widget.onSave(
        productName: _nameCtrl.text.trim(),
        productUrl: _urlCtrl.text.trim(),
        characteristics: _charCtrl.text.trim().isEmpty
            ? null
            : _charCtrl.text.trim(),
        quantity: int.tryParse(_qtyCtrl.text.trim()) ?? 1,
        unitPrice:
            double.tryParse(_priceCtrl.text.trim().replaceAll(',', '.')) ?? 0,
        newPhotos: _pickedPhotos.isNotEmpty
            ? _pickedPhotos.map((p) => p.bytes).toList()
            : null,
        newPhotoNames: _pickedPhotos.isNotEmpty
            ? _pickedPhotos.map((p) => p.name).toList()
            : null,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saveError =
            error is BlankItemSaveFailure &&
                error.stage == BlankItemSaveStage.photo
            ? tr(
                context,
                ru: 'Товар сохранён, но не все фото загрузились. Повторите сохранение — уже загруженные фото не повторятся.',
                zh: '商品已保存，但部分照片上传失败。请重试，已上传的照片不会重复。',
              )
            : tr(
                context,
                ru: 'Не удалось сохранить товар. Введённые данные оставлены в форме. Проверьте соединение и повторите.',
                zh: '无法保存商品。已保留填写内容，请检查网络后重试。',
              );
      });
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingItem != null;

    return UnsavedFormGuard(
      controllers: _controllers,
      extraState: '${_pickedPhotos.length}',
      isBusy: _isSaving || _isPickingPhotos,
      child: Container(
        decoration: PurchaseBlankUi.cardDecoration(),
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Заголовок ──────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: context.brandPrimary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      isEditing ? Icons.edit_rounded : Icons.add_rounded,
                      color: context.brandPrimary,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEditing
                              ? tr(
                                  context,
                                  ru: 'Редактирование товара',
                                  zh: '编辑商品',
                                )
                              : tr(context, ru: 'Новый товар', zh: '新商品'),
                          style: PurchaseBlankUi.sectionTitleStyle,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          tr(
                            context,
                            ru: 'Добавьте ссылку, параметры, цену и фото товара',
                            zh: '填写商品链接、参数、价格和图片',
                          ),
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontFamily: 'Gilroy',
                            fontSize: 12,
                            height: 1.18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onCancel != null) ...[
                    const SizedBox(width: 8),
                    Material(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: _isSaving ? null : _cancel,
                        borderRadius: BorderRadius.circular(14),
                        child: const SizedBox(
                          width: 38,
                          height: 38,
                          child: Icon(
                            Icons.close_rounded,
                            size: 20,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              // ── Название товара ────────────
              _FormField(
                controller: _nameCtrl,
                label: tr(context, ru: 'Название товара *', zh: '商品名称 *'),
                hint: tr(
                  context,
                  ru: 'Например: Кроссовки Nike Air Max 90',
                  zh: '例如：Nike Air Max 90运动鞋',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? tr(context, ru: 'Обязательное поле', zh: '必填项')
                    : null,
              ),
              const SizedBox(height: 12),

              // ── Ссылка на товар ────────────
              _FormField(
                controller: _urlCtrl,
                label: tr(context, ru: 'Ссылка на товар *', zh: '商品链接 *'),
                hint: 'https://...',
                keyboardType: TextInputType.url,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? tr(context, ru: 'Обязательное поле', zh: '必填项')
                    : null,
              ),
              const SizedBox(height: 12),

              // ── Характеристики ─────────────
              _FormField(
                controller: _charCtrl,
                label: tr(context, ru: 'Характеристики', zh: '规格'),
                hint: tr(
                  context,
                  ru: 'Размер, цвет, модель...',
                  zh: '尺寸、颜色、型号……',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),

              // ── Количество + Цена ──────────
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _FormField(
                      controller: _qtyCtrl,
                      label: tr(context, ru: 'Кол-во', zh: '数量'),
                      hint: '1',
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        return (n == null || n < 1)
                            ? tr(context, ru: 'Мин. 1', zh: '至少1件')
                            : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: _FormField(
                      controller: _priceCtrl,
                      label: tr(context, ru: 'Цена за шт. (¥)', zh: '单价（¥）'),
                      hint: '0.00',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+[.,]?\d{0,2}'),
                        ),
                      ],
                      validator: (v) {
                        final n = double.tryParse(
                          (v ?? '').replaceAll(',', '.'),
                        );
                        return (n == null || n <= 0)
                            ? tr(context, ru: 'Укажите цену', zh: '请输入价格')
                            : null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ── Фото ──────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.025),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(context, ru: 'Фото товара', zh: '商品图片'),
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Gilroy',
                        fontSize: 13,
                        height: 16 / 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr(
                        context,
                        ru: 'Можно добавить несколько снимков, чтобы сотруднику было проще выкупить товар.',
                        zh: '可以添加多张图片，方便工作人员采购商品。',
                      ),
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontFamily: 'Gilroy',
                        fontSize: 11.5,
                        height: 1.22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // Существующие фото (если редактирование)
                        if (widget.existingItem != null)
                          ...widget.existingItem!.photoUrls.map(
                            (url) => _PhotoThumb(imageUrl: url),
                          ),
                        // Новые фото
                        ..._pickedPhotos.asMap().entries.map(
                          (e) => _PhotoThumb(
                            bytes: e.value.bytes,
                            onRemove: () => _removePhoto(e.key),
                          ),
                        ),
                        // Кнопка добавления
                        Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            key: const Key('blank_item_add_photos'),
                            onTap: _isPickingPhotos ? null : _pickPhotos,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: context.brandPrimary.withValues(
                                    alpha: 0.18,
                                  ),
                                  width: 1.2,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                Icons.add_a_photo_rounded,
                                color: context.brandPrimary,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              if (_saveError != null) ...[
                Text(_saveError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
              ],
              // ── Кнопка сохранения ─────────
              SizedBox(
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: _isSaving ? null : context.brandGradient,
                    color: _isSaving
                        ? context.brandPrimary.withValues(alpha: 0.55)
                        : null,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: _isSaving
                        ? null
                        : [
                            BoxShadow(
                              color: context.brandPrimary.withValues(
                                alpha: 0.18,
                              ),
                              blurRadius: 18,
                              spreadRadius: -10,
                              offset: const Offset(0, 10),
                            ),
                          ],
                  ),
                  child: FilledButton(
                    onPressed: _isSaving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            isEditing
                                ? tr(
                                    context,
                                    ru: 'Сохранить изменения',
                                    zh: '保存更改',
                                  )
                                : tr(context, ru: 'Добавить товар', zh: '添加商品'),
                            style: const TextStyle(
                              fontFamily: 'Gilroy',
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              height: 18 / 15,
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
}

// ── Поле формы ──────────────────────────────────────────────

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;

  const _FormField({
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontFamily: 'Gilroy',
            fontSize: 13,
            height: 16 / 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        AppOutlinedInputFrame(
          radius: 18,
          borderWidth: 1.2,
          focusedBorderWidth: 1.6,
          fillColor: const Color(0xFFF8FAFC),
          borderColor: const Color(0xFFE1E5ED),
          focusedBorderColor: context.brandPrimary,
          builder: (context, focusNode) {
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              maxLines: maxLines,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              validator: validator,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontFamily: 'Gilroy',
                fontSize: 15,
                height: 18 / 15,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  color: Color(0xFFB0B4BE),
                  fontFamily: 'Gilroy',
                  fontSize: 14,
                  height: 16 / 14,
                  fontWeight: FontWeight.w600,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                isDense: true,
              ),
            );
          },
        ),
      ],
    );
  }
}

// ── Модель выбранного фото ──────────────────────────────────

class _PickedPhoto {
  final Uint8List bytes;
  final String name;
  const _PickedPhoto({required this.bytes, required this.name});
}

// ── Миниатюра фото ─────────────────────────────────────────

class _PhotoThumb extends StatelessWidget {
  final String? imageUrl;
  final Uint8List? bytes;
  final VoidCallback? onRemove;

  const _PhotoThumb({this.imageUrl, this.bytes, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 82,
      height: 82,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: imageUrl != null
                  ? AuthenticatedImage.network(
                      ApiConfig.getMediaUrl(imageUrl!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: Colors.white,
                        child: const Icon(
                          Icons.broken_image_rounded,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  : Image.memory(bytes!, fit: BoxFit.cover),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.88),
                  width: 2,
                ),
              ),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: -6,
              right: -6,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
