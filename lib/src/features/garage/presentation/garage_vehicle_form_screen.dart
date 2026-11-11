import '../../../core/utils/locale_text.dart';
import '../../../core/ui/unsaved_changes_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/app_layout.dart';
import '../../../core/ui/app_toast.dart';
import '../application/garage_providers.dart';
import '../domain/garage_models.dart';
import 'garage_modal.dart';
import 'garage_ui.dart';

Future<bool?> showGarageVehicleFormModal(
  BuildContext context, {
  int? vehicleId,
}) {
  return showGarageModalSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    child: GarageVehicleFormScreen(vehicleId: vehicleId, modal: true),
  );
}

class GarageVehicleFormScreen extends ConsumerStatefulWidget {
  final int? vehicleId;
  final bool modal;

  const GarageVehicleFormScreen({
    super.key,
    this.vehicleId,
    this.modal = false,
  });

  @override
  ConsumerState<GarageVehicleFormScreen> createState() =>
      _GarageVehicleFormScreenState();
}

class _GarageVehicleFormScreenState
    extends ConsumerState<GarageVehicleFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _vin = TextEditingController();
  final _nickname = TextEditingController();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _year = TextEditingController();
  final _generation = TextEditingController();
  final _engine = TextEditingController();
  final _comment = TextEditingController();

  bool _loading = false;
  bool _saving = false;
  GarageVehicle? _vehicle;

  @override
  void initState() {
    super.initState();
    if (widget.vehicleId != null) {
      Future<void>.microtask(_load);
    }
  }

  @override
  void dispose() {
    _vin.dispose();
    _nickname.dispose();
    _make.dispose();
    _model.dispose();
    _year.dispose();
    _generation.dispose();
    _engine.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cached = ref
          .read(garageVehiclesControllerProvider)
          .asData
          ?.value
          .vehicles
          .where((vehicle) => vehicle.id == widget.vehicleId)
          .firstOrNull;
      final vehicle =
          cached ??
          await ref
              .read(garageRepositoryProvider)
              .getVehicle(widget.vehicleId!);
      if (!mounted) return;
      _vehicle = vehicle;
      _fill(vehicle);
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _show(
        tr(context, ru: 'Не удалось загрузить автомобиль', zh: '无法加载车辆'),
        error: true,
      );
    }
  }

  void _fill(GarageVehicle vehicle) {
    _vin.text = vehicle.vinNormalized;
    _nickname.text = vehicle.nickname ?? '';
    _make.text = vehicle.make;
    _model.text = vehicle.model;
    _year.text = vehicle.modelYear > 0 ? vehicle.modelYear.toString() : '';
    _generation.text = vehicle.generation ?? '';
    _engine.text = vehicle.engineCode ?? '';
    _comment.text = vehicle.comment ?? '';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    final input = GarageVehicleInput(
      vin: _vin.text,
      nickname: _nickname.text,
      make: _make.text,
      model: _model.text,
      modelYear: int.parse(_year.text.trim()),
      generation: _generation.text,
      engineCode: _engine.text,
      comment: _comment.text,
    );
    try {
      final controller = ref.read(garageVehiclesControllerProvider.notifier);
      if (widget.vehicleId == null) {
        await controller.createVehicle(input);
      } else {
        await controller.updateVehicle(widget.vehicleId!, input);
      }
      if (!mounted) return;
      _show(
        widget.vehicleId == null
            ? tr(context, ru: 'Автомобиль добавлен', zh: '车辆已添加')
            : tr(context, ru: 'Автомобиль обновлён', zh: '车辆已更新'),
      );
      if (widget.modal) {
        Navigator.of(context).pop(true);
      } else {
        context.pop();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _show(
        tr(context, ru: 'Не удалось сохранить автомобиль', zh: '无法保存车辆'),
        error: true,
      );
    }
  }

  Future<void> _delete() async {
    final vehicle = _vehicle;
    if (vehicle == null || vehicle.activeRequestCount > 0 || _saving) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(tr(context, ru: 'Удалить автомобиль?', zh: '删除车辆？')),
            content: Text(
              tr(
                context,
                ru: 'Автомобиль будет скрыт из Гаража. История заявок сохранится.',
                zh: '车辆将从车库中隐藏，申请记录将保留。',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(tr(context, ru: 'Отмена', zh: '取消')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(tr(context, ru: 'Удалить', zh: '删除')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(garageVehiclesControllerProvider.notifier)
          .deleteVehicle(vehicle.id);
      if (!mounted) return;
      if (widget.modal) {
        Navigator.of(context).pop(true);
      } else {
        context.pop();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _show(
        tr(context, ru: 'Не удалось удалить автомобиль', zh: '无法删除车辆'),
        error: true,
      );
    }
  }

  void _show(String message, {bool error = false}) {
    AppToast.show(context, message, isError: error);
  }

  @override
  Widget build(BuildContext context) {
    final top = widget.modal ? 0.0 : AppLayout.topBarTotalHeight(context);
    final bottom = widget.modal
        ? MediaQuery.viewInsetsOf(context).bottom + 24
        : AppLayout.bottomScrollPadding(context);
    final title = widget.vehicleId == null
        ? tr(context, ru: 'Добавление автомобиля', zh: '添加车辆')
        : tr(context, ru: 'Редактирование автомобиля', zh: '编辑车辆');
    if (_loading) {
      return ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          widget.modal ? 0 : top * 0.7 + 16,
          16,
          bottom + 24,
        ),
        children: [
          if (widget.modal)
            GarageModalHeader(
              icon: Icons.directions_car_filled_rounded,
              title: title,
              subtitle: tr(
                context,
                ru: 'Данные автомобиля для подбора запчастей',
                zh: '用于匹配配件的车辆信息',
              ),
            )
          else
            GaragePageHeader(title: title),
          const SizedBox(height: 12),
          const GarageCard(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }
    return UnsavedFormGuard(
      controllers: [
        _vin,
        _nickname,
        _make,
        _model,
        _year,
        _generation,
        _engine,
        _comment,
      ],
      extraState: '',
      isBusy: _saving,
      child: Form(
        key: _formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            16,
            widget.modal ? 0 : top * 0.7 + 16,
            16,
            bottom + 24,
          ),
          children: [
            if (widget.modal)
              GarageModalHeader(
                icon: Icons.directions_car_filled_rounded,
                title: title,
                subtitle: tr(
                  context,
                  ru: 'Данные автомобиля для подбора запчастей',
                  zh: '用于匹配配件的车辆信息',
                ),
              )
            else
              GaragePageHeader(title: title),
            const SizedBox(height: 12),
            GarageSectionCard(
              icon: Icons.badge_outlined,
              title: tr(context, ru: 'Основные данные', zh: '基本信息'),
              subtitle: tr(
                context,
                ru: 'VIN и понятное название автомобиля',
                zh: 'VIN和车辆名称',
              ),
              child: Column(
                children: [
                  TextFormField(
                    controller: _vin,
                    textInputAction: TextInputAction.next,
                    enabled: widget.vehicleId == null,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[A-HJ-NPR-Za-hj-npr-z0-9]'),
                      ),
                      LengthLimitingTextInputFormatter(17),
                    ],
                    decoration: InputDecoration(
                      labelText: 'VIN',
                      hintText: tr(context, ru: '17 символов', zh: '17个字符'),
                      prefixIcon: Icon(Icons.pin_rounded),
                    ),
                    validator: (value) =>
                        RegExp(
                          r'^[A-HJ-NPR-Z0-9]{17}$',
                        ).hasMatch((value ?? '').trim().toUpperCase())
                        ? null
                        : tr(
                            context,
                            ru: 'Введите корректный VIN',
                            zh: '请输入有效的VIN',
                          ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nickname,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: tr(
                        context,
                        ru: 'Название в Гараже',
                        zh: '车库中的名称',
                      ),
                      hintText: tr(
                        context,
                        ru: 'Например, Семейный автомобиль',
                        zh: '例如：家庭用车',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GarageSectionCard(
              icon: Icons.directions_car_outlined,
              title: tr(context, ru: 'Автомобиль', zh: '车辆'),
              subtitle: tr(
                context,
                ru: 'Марка, модель и год выпуска',
                zh: '品牌、型号和生产年份',
              ),
              child: Column(
                children: [
                  TextFormField(
                    controller: _make,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: tr(context, ru: 'Марка *', zh: '品牌 *'),
                    ),
                    validator: (value) => _required(context, value),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _model,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: tr(context, ru: 'Модель *', zh: '型号 *'),
                    ),
                    validator: (value) => _required(context, value),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _year,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: tr(context, ru: 'Год выпуска *', zh: '生产年份 *'),
                    ),
                    validator: (value) {
                      final year = int.tryParse(value ?? '');
                      final max = DateTime.now().year + 2;
                      return year != null && year >= 1886 && year <= max
                          ? null
                          : tr(
                              context,
                              ru: 'Введите год от 1886 до $max',
                              zh: '请输入1886至$max之间的年份',
                            );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GarageSectionCard(
              icon: Icons.tune_rounded,
              title: tr(context, ru: 'Дополнительно', zh: '其他信息'),
              subtitle: tr(
                context,
                ru: 'Комплектация и уточнения для менеджера',
                zh: '提供给经理的配置和说明',
              ),
              child: Column(
                children: [
                  TextFormField(
                    controller: _generation,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: tr(
                        context,
                        ru: 'Поколение / комплектация',
                        zh: '代次 / 配置',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _engine,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: tr(context, ru: 'Код двигателя', zh: '发动机代码'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _comment,
                    textInputAction: TextInputAction.newline,
                    minLines: 2,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: tr(context, ru: 'Комментарий', zh: '备注'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            GaragePrimaryButton(
              label: widget.vehicleId == null
                  ? tr(context, ru: 'Добавить автомобиль', zh: '添加车辆')
                  : tr(context, ru: 'Сохранить', zh: '保存'),
              icon: Icons.save_rounded,
              onPressed: _save,
              loading: _saving,
            ),
            if (widget.vehicleId != null) ...[
              const SizedBox(height: 10),
              GarageSecondaryButton(
                label: _vehicle?.activeRequestCount == 0
                    ? tr(context, ru: 'Удалить автомобиль', zh: '删除车辆')
                    : tr(
                        context,
                        ru: 'Нельзя удалить: есть активные заявки',
                        zh: '存在进行中的申请，暂不能删除',
                      ),
                icon: Icons.delete_outline_rounded,
                color: Colors.redAccent,
                onPressed: _vehicle?.activeRequestCount == 0 ? _delete : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String? _required(BuildContext context, String? value) {
  return value?.trim().isNotEmpty == true
      ? null
      : tr(context, ru: 'Обязательное поле', zh: '必填项');
}
