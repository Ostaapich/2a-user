import 'package:flutter/material.dart';

import '../../../core/ui/app_colors.dart';
import '../../../core/ui/blurred_modal_bottom_sheet.dart';
import '../../../core/utils/locale_text.dart';
import '../../tracks/presentation/widgets/track_sheet_surface.dart';

Future<DateTime?> showPhotoDateSheet({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? initialDate,
}) {
  return showBlurredModalBottomSheet<DateTime>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PhotoDateSheet(
      firstDate: DateUtils.dateOnly(firstDate),
      lastDate: DateUtils.dateOnly(lastDate),
      initialDate: DateUtils.dateOnly(initialDate ?? DateTime.now()),
    ),
  );
}

class PhotoDateSheet extends StatefulWidget {
  const PhotoDateSheet({
    super.key,
    required this.firstDate,
    required this.lastDate,
    required this.initialDate,
  });

  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime initialDate;

  @override
  State<PhotoDateSheet> createState() => _PhotoDateSheetState();
}

class _PhotoDateSheetState extends State<PhotoDateSheet> {
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDate.isBefore(widget.firstDate)
        ? widget.firstDate
        : widget.initialDate.isAfter(widget.lastDate)
        ? widget.lastDate
        : widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.brandPrimary;
    return TrackSheetSurface(
      icon: Icons.calendar_month_rounded,
      title: tr(context, ru: 'Выбор даты', zh: '选择日期'),
      subtitle: MaterialLocalizations.of(context).formatFullDate(_selected),
      contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      footer: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  backgroundColor: Colors.white,
                  side: BorderSide(color: accent.withValues(alpha: .24)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Gilroy',
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                child: Text(tr(context, ru: 'Отмена', zh: '取消')),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TrackSheetPrimaryButton(
              label: tr(context, ru: 'Применить', zh: '应用'),
              icon: Icons.check_rounded,
              onTap: () => Navigator.of(context).pop(_selected),
            ),
          ),
        ],
      ),
      child: DatePickerTheme(
        data: DatePickerTheme.of(context).copyWith(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          dayBackgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? accent
                : Colors.transparent,
          ),
          dayForegroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? AppColors.textSecondary.withValues(alpha: .38)
                : states.contains(WidgetState.selected)
                ? Colors.white
                : AppColors.textPrimary,
          ),
          yearBackgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? accent
                : Colors.transparent,
          ),
          yearForegroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Colors.white
                : AppColors.textPrimary,
          ),
        ),
        child: CalendarDatePicker(
          initialDate: _selected,
          firstDate: widget.firstDate,
          lastDate: widget.lastDate,
          onDateChanged: (date) => setState(() => _selected = date),
        ),
      ),
    );
  }
}
