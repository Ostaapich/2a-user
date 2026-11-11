import '../../../core/utils/locale_text.dart';
import '../../../core/ui/unsaved_changes_guard.dart';
import 'package:twoalogisticcabineuser/src/core/media/authenticated_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/ui/app_colors.dart';
import '../../../core/network/api_config.dart';
import '../../../core/utils/image_compressor.dart';
import '../../../core/ui/app_layout.dart';
import '../../../core/ui/app_toast.dart';
import '../../clients/application/client_codes_controller.dart';
import '../application/garage_providers.dart';
import '../domain/garage_models.dart';
import 'garage_modal.dart';
import 'garage_ui.dart';

Future<int?> showGarageRequestFormModal(
  BuildContext context, {
  int? requestId,
  int? initialVehicleId,
}) {
  return showGarageModalSheet<int>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    child: GarageRequestFormScreen(
      initialVehicleId: initialVehicleId,
      requestId: requestId,
      modal: true,
    ),
  );
}

class GarageRequestFormScreen extends ConsumerStatefulWidget {
  final int? initialVehicleId;
  final int? requestId;
  final bool modal;

  const GarageRequestFormScreen({
    super.key,
    this.initialVehicleId,
    this.requestId,
    this.modal = false,
  });

  @override
  ConsumerState<GarageRequestFormScreen> createState() =>
      _GarageRequestFormScreenState();
}

class _GarageRequestFormScreenState
    extends ConsumerState<GarageRequestFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _comment = TextEditingController();
  final _items = <_PartDraft>[_PartDraft()];
  final _deletedItemIds = <int>{};
  int? _vehicleId;
  int? _clientCodeId;
  bool _loading = false;
  bool _saving = false;
  String? _loadError;

  bool get _isEditing => widget.requestId != null;
  bool get _uploadingImages => _items.any((item) => item.uploadingImage);

  @override
  void initState() {
    super.initState();
    _vehicleId = widget.initialVehicleId;
    _loading = _isEditing;
    Future<void>.microtask(_initialize);
  }

  @override
  void dispose() {
    _comment.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _addItem() {
    setState(() => _items.add(_PartDraft()));
  }

  void _removeItem(int index) {
    if (_items.length == 1) return;
    final removed = _items.removeAt(index);
    if (removed.itemId != null) {
      _deletedItemIds.add(removed.itemId!);
    }
    removed.dispose();
    setState(() {});
  }

  Future<void> _pickPartImage(_PartDraft draft) async {
    if (_saving || draft.uploadingImage) return;
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 2200,
      maxHeight: 2200,
    );
    if (image == null) return;
    setState(() => draft.uploadingImage = true);
    try {
      final sourceBytes = await image.readAsBytes();
      final sourceMimeType =
          image.mimeType ?? _garagePartImageMimeType(image.name);
      final needsTranscode = !const {
        'image/jpeg',
        'image/png',
        'image/webp',
      }.contains(sourceMimeType.toLowerCase());
      final prepared = await ImageCompressor.compressForUpload(
        sourceBytes,
        sourceName: image.name,
        maxSide: 2200,
        quality: 85,
        forceTranscode: needsTranscode,
      );
      final originalBaseName = image.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      final url = await ref
          .read(garageRepositoryProvider)
          .uploadRequestItemImage(
            bytes: prepared.bytes,
            fileName: '$originalBaseName.${prepared.extension}',
            mimeType: prepared.mimeType,
          );
      if (!mounted) return;
      setState(() {
        draft.imageUrl = url;
        draft.uploadingImage = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => draft.uploadingImage = false);
      _show(
        tr(
          context,
          ru: 'Не удалось загрузить изображение детали',
          zh: '无法上传配件图片',
        ),
        error: true,
      );
    }
  }

  Future<void> _initialize() async {
    final controller = ref.read(garageRequestDraftControllerProvider.notifier);
    if (!_isEditing) {
      controller.reset();
      return;
    }
    try {
      final request = await controller.load(widget.requestId!);
      if (!mounted) return;
      if (request.status != 'draft') {
        setState(() {
          _loading = false;
          _loadError = tr(
            context,
            ru: 'Эту заявку уже нельзя редактировать',
            zh: '此申请已不能编辑',
          );
        });
        return;
      }
      for (final item in _items) {
        item.dispose();
      }
      setState(() {
        _vehicleId = request.vehicleId;
        _clientCodeId = request.clientCodeId;
        _comment.text = request.clientComment ?? '';
        _items
          ..clear()
          ..addAll(request.items.map(_PartDraft.fromItem));
        if (_items.isEmpty) {
          _items.add(_PartDraft());
        }
        _deletedItemIds.clear();
        _loading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = tr(
          context,
          ru: 'Не удалось загрузить черновик',
          zh: '无法加载草稿',
        );
      });
    }
  }

  Future<void> _persist({required bool submit}) async {
    if (_saving || _uploadingImages || !_formKey.currentState!.validate()) {
      return;
    }
    if (_vehicleId == null) {
      _show(tr(context, ru: 'Выберите автомобиль', zh: '选择车辆'), error: true);
      return;
    }
    final clientCodeId = _clientCodeId ?? ref.read(activeClientCodeIdProvider);
    if (clientCodeId == null) {
      _show(
        tr(
          context,
          ru: 'Не удалось определить активный код клиента',
          zh: '无法确定当前客户代码',
        ),
        error: true,
      );
      return;
    }
    setState(() => _saving = true);
    final controller = ref.read(garageRequestDraftControllerProvider.notifier);
    try {
      var request = _isEditing
          ? await controller.update(
              GarageRequestUpdate(
                vehicleId: _vehicleId,
                clientCodeId: clientCodeId,
                clientComment: _comment.text,
              ),
            )
          : await controller.create(
              GarageRequestInput(
                vehicleId: _vehicleId!,
                clientCodeId: clientCodeId,
                clientComment: _comment.text,
              ),
              idempotencyKey: const Uuid().v4(),
            );
      for (final itemId in _deletedItemIds) {
        await controller.deleteItem(itemId);
      }
      for (final item in _items) {
        if (item.itemId == null) {
          await controller.addItem(item.toInput());
        } else {
          await controller.updateItem(item.itemId!, item.toInput());
        }
      }
      if (submit) {
        request = await controller.submit(idempotencyKey: const Uuid().v4());
      } else {
        request =
            ref.read(garageRequestDraftControllerProvider).request ?? request;
      }
      if (!mounted) return;
      ref.invalidate(garageRequestsProvider);
      ref.invalidate(garageRequestProvider(request.id));
      _show(
        submit
            ? tr(context, ru: 'Заявка отправлена', zh: '申请已提交')
            : tr(context, ru: 'Черновик сохранён', zh: '草稿已保存'),
      );
      if (widget.modal) {
        Navigator.of(context).pop(request.id);
      } else {
        context.go('/garage/requests/${request.id}');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (_isEditing) {
        _show(
          tr(context, ru: 'Не удалось сохранить изменения', zh: '无法保存更改'),
          error: true,
        );
        return;
      }
      final partial = ref.read(garageRequestDraftControllerProvider).request;
      if (partial != null) {
        _show(
          tr(
            context,
            ru: 'Черновик создан, но не все данные удалось сохранить. Откройте его и проверьте позиции.',
            zh: '草稿已创建，但部分内容保存失败。请打开草稿检查商品。',
          ),
          error: true,
        );
        if (widget.modal) {
          Navigator.of(context).pop(partial.id);
        } else {
          context.go('/garage/requests/${partial.id}');
        }
      } else {
        _show(
          tr(context, ru: 'Не удалось сохранить заявку', zh: '无法保存申请'),
          error: true,
        );
      }
    }
  }

  void _show(String message, {bool error = false}) {
    AppToast.show(context, message, isError: error);
  }

  @override
  Widget build(BuildContext context) {
    final vehicles = ref.watch(garageVehiclesControllerProvider);
    final top = widget.modal ? 0.0 : AppLayout.topBarTotalHeight(context);
    final bottom = widget.modal
        ? MediaQuery.viewInsetsOf(context).bottom + 26
        : AppLayout.bottomScrollPadding(context);
    final title = _isEditing
        ? tr(context, ru: 'Редактирование заявки', zh: '编辑申请')
        : tr(context, ru: 'Новая заявка', zh: '新申请');

    if (_loading || _loadError != null) {
      return ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          widget.modal ? 0 : top * 0.7 + 16,
          16,
          bottom + 26,
        ),
        children: [
          if (widget.modal)
            GarageModalHeader(
              icon: Icons.playlist_add_rounded,
              title: title,
              subtitle: tr(
                context,
                ru: 'Автомобиль, детали и пожелания по подбору',
                zh: '车辆、配件和匹配要求',
              ),
            )
          else
            GaragePageHeader(title: title),
          const SizedBox(height: 12),
          if (_loading)
            const GarageCard(child: Center(child: CircularProgressIndicator()))
          else
            GarageEmptyState(
              icon: Icons.error_outline_rounded,
              title: tr(context, ru: 'Черновик не загрузился', zh: '草稿加载失败'),
              subtitle: _loadError!,
              action: GarageSecondaryButton(
                label: tr(context, ru: 'Повторить', zh: '重试'),
                icon: Icons.refresh_rounded,
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _loadError = null;
                  });
                  _initialize();
                },
              ),
            ),
        ],
      );
    }

    return UnsavedFormGuard(
      controllers: [
        _comment,
        ..._items.expand(
          (i) => [
            i.name,
            i.number,
            i.russiaAnalogueUrl,
            i.quantity,
            i.side,
            i.position,
            i.comment,
          ],
        ),
      ],
      extraState:
          '$_vehicleId:$_clientCodeId:${_items.map((i) => '${i.itemId}:${i.imageUrl}:${i.preference}:${i.optional}').join('|')}',
      isBusy: _saving || _uploadingImages,
      child: Form(
        key: _formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            16,
            widget.modal ? 0 : top * 0.7 + 16,
            16,
            bottom + 26,
          ),
          children: [
            if (widget.modal)
              GarageModalHeader(
                icon: Icons.playlist_add_rounded,
                title: title,
                subtitle: tr(
                  context,
                  ru: 'Автомобиль, детали и пожелания по подбору',
                  zh: '车辆、配件和匹配要求',
                ),
              )
            else
              GaragePageHeader(title: title),
            const SizedBox(height: 12),
            GarageSectionCard(
              icon: Icons.directions_car_outlined,
              title: tr(context, ru: 'Основное', zh: '基本信息'),
              subtitle: tr(
                context,
                ru: 'Выберите автомобиль и добавьте общий комментарий',
                zh: '选择车辆并填写备注',
              ),
              child: vehicles.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => GarageSecondaryButton(
                  label: tr(
                    context,
                    ru: 'Повторить загрузку автомобилей',
                    zh: '重新加载车辆',
                  ),
                  icon: Icons.refresh_rounded,
                  onPressed: () =>
                      ref.invalidate(garageVehiclesControllerProvider),
                ),
                data: (state) => Column(
                  children: [
                    GarageVehiclePickerField(
                      vehicles: state.vehicles,
                      value:
                          state.vehicles.any(
                            (vehicle) => vehicle.id == _vehicleId,
                          )
                          ? _vehicleId
                          : null,
                      enabled: !_saving,
                      onChanged: (value) => setState(() => _vehicleId = value),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _comment,
                      textInputAction: TextInputAction.newline,
                      minLines: 2,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: tr(
                          context,
                          ru: 'Общий комментарий',
                          zh: '申请备注',
                        ),
                        hintText: tr(
                          context,
                          ru: 'Пожелания по заявке',
                          zh: '申请要求',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            for (var index = 0; index < _items.length; index++) ...[
              _PartCard(
                index: index,
                draft: _items[index],
                canRemove: _items.length > 1,
                enabled: !_saving,
                onDraftChanged: () => setState(() {}),
                onPickImage: () => _pickPartImage(_items[index]),
                onRemoveImage: () =>
                    setState(() => _items[index].imageUrl = null),
                onRemove: () => _removeItem(index),
              ),
              const SizedBox(height: 12),
            ],
            GarageSecondaryButton(
              label: tr(context, ru: 'Добавить ещё одну позицию', zh: '添加其他配件'),
              icon: Icons.add_rounded,
              onPressed: _saving ? null : _addItem,
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 430;
                final draftButton = GarageSecondaryButton(
                  label: _isEditing
                      ? tr(context, ru: 'Сохранить изменения', zh: '保存更改')
                      : tr(context, ru: 'Сохранить черновик', zh: '保存草稿'),
                  icon: Icons.save_outlined,
                  onPressed: _saving || _uploadingImages
                      ? null
                      : () => _persist(submit: false),
                );
                final submitButton = GaragePrimaryButton(
                  label: _isEditing
                      ? tr(context, ru: 'Сохранить и отправить', zh: '保存并提交')
                      : tr(context, ru: 'Отправить заявку', zh: '提交申请'),
                  icon: Icons.send_rounded,
                  onPressed: _uploadingImages
                      ? null
                      : () => _persist(submit: true),
                  loading: _saving,
                );
                if (compact) {
                  return Column(
                    children: [
                      SizedBox(width: double.infinity, child: submitButton),
                      const SizedBox(height: 10),
                      SizedBox(width: double.infinity, child: draftButton),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: draftButton),
                    const SizedBox(width: 10),
                    Expanded(child: submitButton),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PartCard extends StatefulWidget {
  final int index;
  final _PartDraft draft;
  final bool canRemove;
  final bool enabled;
  final VoidCallback onRemove;
  final VoidCallback onPickImage;
  final VoidCallback onRemoveImage;
  final VoidCallback onDraftChanged;

  const _PartCard({
    required this.index,
    required this.draft,
    required this.canRemove,
    required this.enabled,
    required this.onRemove,
    required this.onPickImage,
    required this.onRemoveImage,
    required this.onDraftChanged,
  });

  @override
  State<_PartCard> createState() => _PartCardState();
}

class _PartCardState extends State<_PartCard> {
  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return GarageCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(
                    context,
                    ru: 'Позиция ${widget.index + 1}',
                    zh: '配件 ${widget.index + 1}',
                  ),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (widget.canRemove)
                IconButton(
                  tooltip: tr(context, ru: 'Удалить позицию', zh: '删除配件'),
                  onPressed: widget.enabled ? widget.onRemove : null,
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: Colors.redAccent,
                ),
            ],
          ),
          const SizedBox(height: 8),
          _PartImageField(
            imageUrl: draft.imageUrl,
            uploading: draft.uploadingImage,
            enabled: widget.enabled,
            onPick: widget.onPickImage,
            onRemove: widget.onRemoveImage,
          ),
          const SizedBox(height: 11),
          TextFormField(
            controller: draft.name,
            textInputAction: TextInputAction.next,
            enabled: widget.enabled,
            decoration: InputDecoration(
              labelText: tr(context, ru: 'Название детали *', zh: '配件名称 *'),
            ),
            validator: (value) => _required(context, value),
          ),
          const SizedBox(height: 11),
          TextFormField(
            controller: draft.number,
            textInputAction: TextInputAction.next,
            enabled: widget.enabled,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: tr(context, ru: 'Артикул *', zh: '零件编号 *'),
            ),
            validator: (value) => _required(context, value),
          ),
          const SizedBox(height: 11),
          TextFormField(
            controller: draft.russiaAnalogueUrl,
            textInputAction: TextInputAction.next,
            enabled: widget.enabled,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: tr(
                context,
                ru: 'Аналогичный товар в России',
                zh: '俄罗斯的类似商品',
              ),
              hintText: tr(
                context,
                ru: 'Необязательная ссылка на любой сайт',
                zh: '可选：任意网站的链接',
              ),
            ),
            validator: (value) => _validateOptionalWebUrl(context, value),
          ),
          const SizedBox(height: 11),
          GaragePartPreferencePickerField(
            key: ValueKey('garage-part-preference-picker-${widget.index}'),
            value: draft.preference,
            enabled: widget.enabled,
            onChanged: (value) {
              setState(() => draft.preference = value);
              widget.onDraftChanged();
            },
          ),
          const SizedBox(height: 11),
          TextFormField(
            controller: draft.quantity,
            textInputAction: TextInputAction.next,
            enabled: widget.enabled,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: tr(context, ru: 'Количество *', zh: '数量 *'),
            ),
            validator: (value) {
              final quantity = int.tryParse(value ?? '');
              return quantity != null && quantity > 0 && quantity <= 999
                  ? null
                  : tr(context, ru: 'От 1 до 999', zh: '1至999');
            },
          ),
          const SizedBox(height: 11),
          TextFormField(
            controller: draft.side,
            textInputAction: TextInputAction.next,
            enabled: widget.enabled,
            decoration: InputDecoration(
              labelText: tr(
                context,
                ru: 'Сторона / расположение',
                zh: '方向 / 位置',
              ),
              hintText: tr(context, ru: 'Передняя левая', zh: '左前'),
            ),
          ),
          const SizedBox(height: 11),
          TextFormField(
            controller: draft.position,
            textInputAction: TextInputAction.next,
            enabled: widget.enabled,
            decoration: InputDecoration(
              labelText: tr(
                context,
                ru: 'Позиция / место установки',
                zh: '安装位置',
              ),
              hintText: tr(context, ru: 'Например, передняя ось', zh: '例如：前轴'),
            ),
          ),
          const SizedBox(height: 11),
          TextFormField(
            controller: draft.comment,
            textInputAction: TextInputAction.newline,
            enabled: widget.enabled,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: tr(context, ru: 'Комментарий', zh: '备注'),
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(tr(context, ru: 'Позиция необязательная', zh: '可选配件')),
            subtitle: Text(
              tr(
                context,
                ru: 'Можно исключить из итогового заказа',
                zh: '可以不包含在最终订单中',
              ),
            ),
            value: draft.optional,
            onChanged: widget.enabled
                ? (value) {
                    setState(() => draft.optional = value);
                    widget.onDraftChanged();
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

class _PartDraft {
  final int? itemId;
  final TextEditingController name;
  final TextEditingController number;
  final TextEditingController russiaAnalogueUrl;
  String? imageUrl;
  bool uploadingImage = false;
  final TextEditingController quantity;
  final TextEditingController side;
  final TextEditingController position;
  final TextEditingController comment;
  GaragePartPreference preference;
  bool optional;

  _PartDraft({GarageRequestItem? item})
    : itemId = item?.id,
      name = TextEditingController(text: item?.partName ?? ''),
      number = TextEditingController(text: item?.partNumber ?? ''),
      russiaAnalogueUrl = TextEditingController(
        text: item?.russiaAnalogueUrl ?? '',
      ),
      imageUrl = item?.imageUrl,
      quantity = TextEditingController(text: '${item?.quantity ?? 1}'),
      side = TextEditingController(text: item?.side ?? ''),
      position = TextEditingController(text: item?.position ?? ''),
      comment = TextEditingController(text: item?.clientComment ?? ''),
      preference = item?.preference ?? GaragePartPreference.any,
      optional = item?.isOptional ?? false;

  factory _PartDraft.fromItem(GarageRequestItem item) {
    return _PartDraft(item: item);
  }

  GarageRequestItemInput toInput() {
    return GarageRequestItemInput(
      partName: name.text,
      partNumber: number.text,
      preference: preference,
      russiaAnalogueUrl: russiaAnalogueUrl.text,
      imageUrl: imageUrl,
      quantity: int.parse(quantity.text),
      side: side.text,
      position: position.text,
      clientComment: comment.text,
      isOptional: optional,
    );
  }

  void dispose() {
    name.dispose();
    number.dispose();
    russiaAnalogueUrl.dispose();
    quantity.dispose();
    side.dispose();
    position.dispose();
    comment.dispose();
  }
}

String? _required(BuildContext context, String? value) {
  return value?.trim().isNotEmpty == true
      ? null
      : tr(context, ru: 'Обязательное поле', zh: '必填项');
}

String? _validateOptionalWebUrl(BuildContext context, String? value) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) return null;
  final uri = Uri.tryParse(normalized);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return tr(
      context,
      ru: 'Укажите корректную ссылку http:// или https://',
      zh: '请输入有效的http://或https://链接',
    );
  }
  return null;
}

String _garagePartImageMimeType(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.heic')) return 'image/heic';
  if (lower.endsWith('.heif')) return 'image/heif';
  return 'image/jpeg';
}

class _PartImageField extends StatelessWidget {
  final String? imageUrl;
  final bool uploading;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _PartImageField({
    required this.imageUrl,
    required this.uploading,
    required this.enabled,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl?.trim().isNotEmpty == true;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 72,
              height: 72,
              child: uploading
                  ? const ColoredBox(
                      color: Colors.white,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : hasImage
                  ? AuthenticatedImage.network(
                      ApiConfig.getMediaThumbnailUrl(imageUrl!, size: 360),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: Colors.white,
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    )
                  : const ColoredBox(
                      color: Colors.white,
                      child: Icon(
                        Icons.add_photo_alternate_outlined,
                        color: AppColors.textSecondary,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, ru: 'Изображение детали', zh: '配件图片'),
                  style: TextStyle(
                    fontFamily: 'Gilroy',
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  tr(
                    context,
                    ru: 'Поможет менеджеру точнее подобрать запчасть',
                    zh: '帮助经理准确匹配配件',
                  ),
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  children: [
                    TextButton.icon(
                      onPressed: enabled && !uploading ? onPick : null,
                      icon: Icon(
                        hasImage ? Icons.refresh_rounded : Icons.add_rounded,
                        size: 17,
                      ),
                      label: Text(
                        hasImage
                            ? tr(context, ru: 'Заменить', zh: '替换')
                            : tr(context, ru: 'Добавить', zh: '添加'),
                      ),
                    ),
                    if (hasImage)
                      TextButton(
                        onPressed: enabled && !uploading ? onRemove : null,
                        child: Text(tr(context, ru: 'Удалить', zh: '删除')),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
