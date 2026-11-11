import 'package:flutter/material.dart';

import '../../../core/ui/app_colors.dart';
import '../../../core/ui/app_input_decoration.dart';
import '../../../core/utils/locale_text.dart';
import '../domain/calculator_cargo_places.dart';

/// The parent owns scrolling and may keep this mounted offstage across modes.
class CalculatorCargoPlacesEditor extends StatefulWidget {
  const CalculatorCargoPlacesEditor({super.key, required this.onChanged});

  final ValueChanged<CargoPlacesTotals?> onChanged;

  @override
  State<CalculatorCargoPlacesEditor> createState() =>
      _CalculatorCargoPlacesEditorState();
}

class _CargoPlaceRow {
  _CargoPlaceRow(this.id);
  final int id;
  final length = TextEditingController();
  final width = TextEditingController();
  final height = TextEditingController();
  final weight = TextEditingController();

  double _number(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.')) ??
      double.nan;

  CargoPlaceDimensions get dimensions => CargoPlaceDimensions(
    lengthCm: _number(length),
    widthCm: _number(width),
    heightCm: _number(height),
    weightKg: _number(weight),
  );

  void dispose() {
    length.dispose();
    width.dispose();
    height.dispose();
    weight.dispose();
  }
}

class _CalculatorCargoPlacesEditorState
    extends State<CalculatorCargoPlacesEditor> {
  final _rows = [_CargoPlaceRow(0)];
  final _retiredRows = <_CargoPlaceRow>{};
  int _nextId = 1;

  void _emit() => widget.onChanged(
    calculateCargoPlacesTotals(_rows.map((row) => row.dimensions).toList()),
  );

  void _add() {
    FocusScope.of(context).unfocus();
    setState(() => _rows.add(_CargoPlaceRow(_nextId++)));
    _emit();
  }

  void _remove(_CargoPlaceRow row) {
    if (_rows.length == 1) return;
    FocusScope.of(context).unfocus();
    setState(() => _rows.remove(row));
    // The old EditableText stays attached until this frame rebuilds. Keep
    // ownership here so disposing the editor before that frame is also safe.
    _retiredRows.add(row);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_retiredRows.remove(row)) row.dispose();
    });
    _emit();
  }

  @override
  void dispose() {
    for (final row in [..._rows, ..._retiredRows]) {
      row.dispose();
    }
    _retiredRows.clear();
    super.dispose();
  }

  Widget _field(
    BuildContext context,
    _CargoPlaceRow row,
    String part,
    TextEditingController controller,
    String label,
  ) => Column(
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
      TextField(
        key: ValueKey('cargo-place-${row.id}-$part'),
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        scrollPadding: const EdgeInsets.all(24),
        onSubmitted: (_) => FocusScope.of(context).unfocus(),
        onChanged: (_) => _emit(),
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontFamily: 'Gilroy',
          fontSize: 15,
          height: 18 / 15,
          fontWeight: FontWeight.w800,
        ),
        decoration: appInputDecoration(
          context,
          hintText: '0',
          radius: 18,
          focusedWidth: 1.6,
          isDense: true,
          fillColor: const Color(0xFFF8FAFC),
          borderColor: const Color(0xFFE1E5ED),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
        ),
      ),
    ],
  );

  Widget _place(
    BuildContext context,
    _CargoPlaceRow row,
    int index,
  ) => Container(
    key: ValueKey('cargo-place-row-${row.id}'),
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE1E5ED)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                tr(context, ru: 'Место ${index + 1}', zh: '第 ${index + 1} 件'),
                style: const TextStyle(
                  fontFamily: 'Gilroy',
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              key: ValueKey('cargo-place-remove-${row.id}'),
              tooltip: tr(
                context,
                ru: 'Удалить место ${index + 1}',
                zh: '删除第 ${index + 1} 件',
              ),
              onPressed: _rows.length > 1 ? () => _remove(row) : null,
              icon: const Icon(Icons.delete_outline_rounded),
              color: context.brandPrimary,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _field(
                context,
                row,
                'length',
                row.length,
                tr(context, ru: 'Длина, см', zh: '长度，厘米'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _field(
                context,
                row,
                'width',
                row.width,
                tr(context, ru: 'Ширина, см', zh: '宽度，厘米'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _field(
                context,
                row,
                'height',
                row.height,
                tr(context, ru: 'Высота, см', zh: '高度，厘米'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _field(
                context,
                row,
                'weight',
                row.weight,
                tr(context, ru: 'Вес, кг', zh: '重量，公斤'),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < _rows.length; index++)
        _place(context, _rows[index], index),
      FilledButton.icon(
        key: const ValueKey('cargo-place-add'),
        onPressed: _add,
        style: FilledButton.styleFrom(
          backgroundColor: context.brandPrimary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Gilroy',
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        icon: const Icon(Icons.add_rounded),
        label: Text(tr(context, ru: 'Добавить место', zh: '添加货件')),
      ),
    ],
  );
}
