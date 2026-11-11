import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/app_colors.dart';
import '../../../core/ui/blurred_modal_bottom_sheet.dart';
import '../../../core/ui/sheet_handle.dart';
import '../domain/garage_models.dart';
import 'garage_modal.dart';

class GaragePageHeader extends StatelessWidget {
  final String title;
  final String fallbackLocation;

  const GaragePageHeader({
    super.key,
    required this.title,
    this.fallbackLocation = '/garage',
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: () {
              final navigator = Navigator.of(context);
              if (navigator.canPop()) {
                navigator.maybePop();
              } else {
                context.go(fallbackLocation);
              }
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 46,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.black.withValues(alpha: 0.035),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 18,
                    spreadRadius: -12,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Gilroy',
              fontSize: 26,
              height: 1.05,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.35,
            ),
          ),
        ),
      ],
    );
  }
}

class GarageHeroHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const GarageHeroHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      decoration: BoxDecoration(
        gradient: context.brandGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: context.brandPrimary.withValues(alpha: 0.18),
            blurRadius: 28,
            spreadRadius: -16,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
            ),
            child: Icon(icon, color: Colors.white, size: 25),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Gilroy',
                    fontSize: 24,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.35,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xE6FFFFFF),
                    fontFamily: 'Gilroy',
                    fontSize: 13,
                    height: 1.2,
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

class GarageModalHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const GarageModalHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

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
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Icon(icon, color: Colors.white, size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
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
                  subtitle,
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

class GarageSegmentedControl extends StatelessWidget {
  final int selectedIndex;
  final List<({IconData icon, String label})> items;
  final ValueChanged<int> onChanged;

  const GarageSegmentedControl({
    super.key,
    required this.selectedIndex,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
      ),
      child: Row(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            Expanded(
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(15),
                child: InkWell(
                  key: ValueKey('garage-segment-$index'),
                  onTap: () => onChanged(index),
                  borderRadius: BorderRadius.circular(15),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: index == selectedIndex
                          ? context.brandGradient
                          : null,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: index == selectedIndex
                          ? [
                              BoxShadow(
                                color: context.brandPrimary.withValues(
                                  alpha: 0.18,
                                ),
                                blurRadius: 12,
                                spreadRadius: -7,
                                offset: const Offset(0, 7),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          items[index].icon,
                          size: 17,
                          color: index == selectedIndex
                              ? Colors.white
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            items[index].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: index == selectedIndex
                                  ? Colors.white
                                  : AppColors.textPrimary,
                              fontFamily: 'Gilroy',
                              fontSize: 14,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.05,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (index != items.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class GarageSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  const GarageSectionCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
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
                  color: context.brandPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: context.brandPrimary, size: 17),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
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
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontFamily: 'Gilroy',
                          fontSize: 12.2,
                          height: 1.15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withValues(alpha: 0.03)),
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

class GarageVehiclePickerField extends StatelessWidget {
  final List<GarageVehicle> vehicles;
  final int? value;
  final ValueChanged<int?> onChanged;
  final bool enabled;

  const GarageVehiclePickerField({
    super.key,
    required this.vehicles,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final selected = vehicles
        .where((vehicle) => vehicle.id == value)
        .firstOrNull;
    return FormField<int>(
      key: ValueKey(value),
      initialValue: selected?.id,
      validator: (current) => current == null ? 'Выберите автомобиль' : null,
      builder: (field) {
        return InkWell(
          key: const ValueKey('garage-vehicle-picker'),
          borderRadius: BorderRadius.circular(12),
          onTap: !enabled || vehicles.isEmpty
              ? null
              : () async {
                  final selectedId = await showGarageVehiclePicker(
                    context: context,
                    vehicles: vehicles,
                    selectedVehicleId: field.value,
                  );
                  if (selectedId == null || !context.mounted) return;
                  field.didChange(selectedId);
                  onChanged(selectedId);
                },
          child: InputDecorator(
            isEmpty: false,
            decoration: InputDecoration(
              labelText: 'Автомобиль *',
              floatingLabelBehavior: FloatingLabelBehavior.always,
              prefixIcon: const Icon(Icons.directions_car_rounded),
              suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
              errorText: field.errorText,
              enabled: enabled,
            ),
            child: Text(
              selected == null
                  ? vehicles.isEmpty
                        ? 'Сначала добавьте автомобиль'
                        : 'Выберите автомобиль'
                  : garageVehicleLabel(selected),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected == null
                    ? AppColors.textSecondary
                    : AppColors.textPrimary,
                fontFamily: 'Gilroy',
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      },
    );
  }
}

class GaragePartPreferencePickerField extends StatelessWidget {
  final GaragePartPreference value;
  final ValueChanged<GaragePartPreference> onChanged;
  final bool enabled;

  const GaragePartPreferencePickerField({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return FormField<GaragePartPreference>(
      key: ValueKey(value),
      initialValue: value,
      builder: (field) {
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: !enabled
              ? null
              : () async {
                  final selected = await showGaragePartPreferencePicker(
                    context: context,
                    selectedPreference: field.value ?? value,
                  );
                  if (selected == null || !context.mounted) return;
                  field.didChange(selected);
                  onChanged(selected);
                },
          child: InputDecorator(
            isEmpty: false,
            decoration: InputDecoration(
              labelText: 'Тип запчасти *',
              floatingLabelBehavior: FloatingLabelBehavior.always,
              prefixIcon: const Icon(Icons.category_outlined),
              suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
              enabled: enabled,
            ),
            child: Text(
              garagePartPreferenceLabel(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontFamily: 'Gilroy',
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<int?> showGarageVehiclePicker({
  required BuildContext context,
  required List<GarageVehicle> vehicles,
  int? selectedVehicleId,
}) {
  return showBlurredModalBottomSheet<int>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.22),
    builder: (context) => _GarageVehiclePickerSheet(
      vehicles: vehicles,
      selectedVehicleId: selectedVehicleId,
    ),
  );
}

Future<GaragePartPreference?> showGaragePartPreferencePicker({
  required BuildContext context,
  required GaragePartPreference selectedPreference,
}) {
  return showBlurredModalBottomSheet<GaragePartPreference>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.22),
    builder: (context) => _GaragePartPreferencePickerSheet(
      selectedPreference: selectedPreference,
    ),
  );
}

class _GarageVehiclePickerSheet extends StatelessWidget {
  final List<GarageVehicle> vehicles;
  final int? selectedVehicleId;

  const _GarageVehiclePickerSheet({
    required this.vehicles,
    required this.selectedVehicleId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.78,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHandle(),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 2, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Выберите автомобиль',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'Gilroy',
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Заявка будет привязана к выбранному автомобилю.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'Gilroy',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                MediaQuery.paddingOf(context).bottom + 18,
              ),
              itemCount: vehicles.length,
              separatorBuilder: (_, _) => const SizedBox(height: 9),
              itemBuilder: (context, index) {
                final vehicle = vehicles[index];
                final selected = vehicle.id == selectedVehicleId;
                return GarageCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 13,
                  ),
                  onTap: () => Navigator.of(context).pop(vehicle.id),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: context.brandPrimary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.directions_car_filled_rounded,
                          color: context.brandPrimary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              garageVehicleLabel(vehicle),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontFamily: 'Gilroy',
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              vehicle.vinNormalized,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontFamily: 'Gilroy',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: selected
                            ? context.brandPrimary
                            : AppColors.textSecondary,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GaragePartPreferencePickerSheet extends StatelessWidget {
  final GaragePartPreference selectedPreference;

  const _GaragePartPreferencePickerSheet({required this.selectedPreference});

  static const _preferences = <GaragePartPreference>[
    GaragePartPreference.original,
    GaragePartPreference.analog,
    GaragePartPreference.any,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.78,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHandle(),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 2, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Выберите тип запчасти',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'Gilroy',
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Укажите, какой вариант должен подобрать менеджер.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'Gilroy',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                MediaQuery.paddingOf(context).bottom + 18,
              ),
              itemCount: _preferences.length,
              separatorBuilder: (_, _) => const SizedBox(height: 9),
              itemBuilder: (context, index) {
                final preference = _preferences[index];
                final selected = preference == selectedPreference;
                return GarageCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 13,
                  ),
                  onTap: () => Navigator.of(context).pop(preference),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: context.brandPrimary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          _garagePartPreferenceIcon(preference),
                          color: context.brandPrimary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              garagePartPreferenceLabel(preference),
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontFamily: 'Gilroy',
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              garagePartPreferenceDescription(preference),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontFamily: 'Gilroy',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: selected
                            ? context.brandPrimary
                            : AppColors.textSecondary,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class GarageCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const GarageCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final modal = GarageModalScope.active(context);
    final content = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: modal ? const Color(0xFFF8FAFC) : Colors.white,
        borderRadius: BorderRadius.circular(modal ? 18 : 24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
        boxShadow: modal
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 24,
                  spreadRadius: -16,
                  offset: const Offset(0, 14),
                ),
              ],
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(modal ? 18 : 24),
      child: InkWell(
        borderRadius: BorderRadius.circular(modal ? 18 : 24),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class GaragePrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool loading;

  const GaragePrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (GarageModalScope.active(context)) {
      final enabled = !loading && onPressed != null;
      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            height: 48,
            decoration: BoxDecoration(
              gradient: enabled ? context.brandGradient : null,
              color: enabled ? null : const Color(0xFFE8EAEE),
              borderRadius: BorderRadius.circular(16),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: context.brandPrimary.withValues(alpha: 0.18),
                        blurRadius: 14,
                        spreadRadius: -8,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  Icon(
                    icon,
                    color: enabled ? Colors.white : AppColors.textSecondary,
                    size: 19,
                  ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    loading ? 'Подождите…' : label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: enabled ? Colors.white : AppColors.textSecondary,
                      fontFamily: 'Gilroy',
                      fontSize: 14,
                      height: 1,
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
    return SizedBox(
      height: 52,
      child: FilledButton.icon(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: context.brandPrimary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFE4E7EC),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Gilroy',
            fontSize: 14.5,
            fontWeight: FontWeight.w900,
          ),
        ),
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon, size: 19),
        label: Text(loading ? 'Подождите…' : label),
      ),
    );
  }
}

class GarageSecondaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  const GarageSecondaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = color ?? context.brandPrimary;
    if (GarageModalScope.active(context)) {
      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: foreground.withValues(alpha: 0.24)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: foreground, size: 18),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontFamily: 'Gilroy',
                      fontSize: 14,
                      height: 1,
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
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          side: BorderSide(color: foreground.withValues(alpha: 0.35)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Gilroy',
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

class GarageStatusChip extends StatelessWidget {
  final String status;
  final GarageRequestStatusDefinition? definition;

  const GarageStatusChip({super.key, required this.status, this.definition});

  @override
  Widget build(BuildContext context) {
    final color =
        garageStatusColorFromHex(definition?.color) ??
        garageStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        definition?.nameRu.trim().isNotEmpty == true
            ? definition!.nameRu
            : garageStatusLabel(status),
        style: TextStyle(
          color: color,
          fontFamily: 'Gilroy',
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class GarageEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const GarageEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return GarageCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Icon(icon, size: 42, color: AppColors.textSecondary),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontFamily: 'Gilroy',
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Gilroy',
                fontSize: 13,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class GarageInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;

  const GarageInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Gilroy',
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: emphasized
                    ? context.brandPrimary
                    : AppColors.textPrimary,
                fontFamily: 'Gilroy',
                fontSize: emphasized ? 15 : 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GaragePartsBadge extends StatelessWidget {
  final String label;
  final bool compact;

  const GaragePartsBadge({
    super.key,
    required this.label,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: context.brandPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: context.brandPrimary,
          fontFamily: 'Gilroy',
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

String garageOptionTypeLabel(String value) {
  return switch (value.trim().toLowerCase()) {
    'original' => 'оригинал',
    'analog' || 'analogue' => 'аналог',
    'used' => 'б/у',
    'oem' => 'OEM',
    final normalized when normalized.isNotEmpty => normalized,
    _ => 'тип не указан',
  };
}

String garagePartPreferenceLabel(GaragePartPreference preference) {
  return switch (preference) {
    GaragePartPreference.original => 'Оригинал',
    GaragePartPreference.analog => 'Аналог',
    GaragePartPreference.any => 'Любой подходящий',
    GaragePartPreference.unknown => 'Не указано',
  };
}

String garagePartPreferenceDescription(GaragePartPreference preference) {
  return switch (preference) {
    GaragePartPreference.original => 'Только оригинальная запчасть',
    GaragePartPreference.analog => 'Подойдёт качественный аналог',
    GaragePartPreference.any => 'Менеджер предложит оптимальный вариант',
    GaragePartPreference.unknown => 'Тип запчасти не выбран',
  };
}

IconData _garagePartPreferenceIcon(GaragePartPreference preference) {
  return switch (preference) {
    GaragePartPreference.original => Icons.verified_outlined,
    GaragePartPreference.analog => Icons.compare_arrows_rounded,
    GaragePartPreference.any => Icons.auto_awesome_rounded,
    GaragePartPreference.unknown => Icons.help_outline_rounded,
  };
}

String garageVehicleLabel(GarageVehicle vehicle) {
  final title = [
    vehicle.make,
    vehicle.model,
  ].where((value) => value.isNotEmpty);
  final prefix = vehicle.nickname?.trim().isNotEmpty == true
      ? '${vehicle.nickname!.trim()} · '
      : '';
  return '$prefix${title.join(' ')} ${vehicle.modelYear > 0 ? vehicle.modelYear : ''}'
      .trim();
}

String garageStatusLabel(String status) {
  return switch (status) {
    'draft' => 'Черновик',
    'new' => 'Новая',
    'in_progress' => 'В работе',
    'pending_confirmation' => 'На согласовании',
    'unpaid' => 'Не оплачена',
    'payment_review' => 'На проверке оплаты',
    'paid' => 'Оплачена',
    'submitted' => 'Отправлена',
    'in_review' => 'На проверке',
    'needs_clarification' => 'Нужно уточнение',
    'offer_ready' => 'Предложение готово',
    'offer_expired' => 'Предложение истекло',
    'converted_to_order' => 'Создан заказ',
    'awaiting_payment' => 'Ожидает оплаты',
    'purchasing' => 'Выкупаем',
    'purchased' => 'Куплено',
    'partially_purchased' => 'Частично выкуплено',
    'completed' => 'Завершено',
    'cancelled' => 'Отменено',
    'refunded' => 'Возвращено',
    'partially_refunded' => 'Частичный возврат',
    'pending' => 'Ожидает',
    'approved' => 'Одобрено',
    'rejected' => 'Отклонено',
    'fulfilled' => 'Исполнено',
    _ => status.replaceAll('_', ' '),
  };
}

String garagePurchaseStatus(String? status) =>
    status == 'purchased' ? 'purchased' : 'pending';

Color garageStatusColor(String status) {
  return switch (status) {
    'draft' => const Color(0xFF667085),
    'new' || 'in_progress' => const Color(0xFF2E7DFF),
    'pending_confirmation' ||
    'unpaid' ||
    'payment_review' => const Color(0xFFF59E0B),
    'paid' => const Color(0xFF16A34A),
    'submitted' || 'in_review' || 'awaiting_payment' => const Color(0xFF2E7DFF),
    'needs_clarification' ||
    'offer_ready' ||
    'offer_expired' ||
    'pending' => const Color(0xFFF59E0B),
    'purchasing' ||
    'purchased' ||
    'partially_purchased' ||
    'completed' ||
    'approved' => const Color(0xFF16A34A),
    'cancelled' || 'rejected' => const Color(0xFFEF4444),
    'refunded' ||
    'partially_refunded' ||
    'fulfilled' => const Color(0xFF7C3AED),
    _ => const Color(0xFF667085),
  };
}

GarageRequestStatusDefinition? garageRequestStatusDefinition(
  Iterable<GarageRequestStatusDefinition> statuses,
  String code,
) {
  for (final status in statuses) {
    if (status.code == code) return status;
  }
  return null;
}

Color? garageStatusColorFromHex(String? value) {
  final source = value?.trim();
  if (source == null || source.isEmpty) return null;
  final hex = source.replaceFirst('#', '');
  if (hex.length != 6 && hex.length != 8) return null;
  try {
    return Color(int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16));
  } catch (_) {
    return null;
  }
}

String garageMoney(double value, String currency) {
  return '${value.toStringAsFixed(2)} $currency';
}
