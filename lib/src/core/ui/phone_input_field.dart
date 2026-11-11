import 'package:flutter/material.dart';
import 'package:phone_form_field/phone_form_field.dart';

import 'app_colors.dart';
import 'app_input_decoration.dart';

class PhoneInputField extends StatelessWidget {
  final PhoneController? controller;
  final PhoneNumber? initialValue;
  final bool isRequired;
  final String hintText;
  final ValueChanged<PhoneNumber>? onChanged;
  final bool enabled;
  final TextInputAction? textInputAction;

  /// Matches gradient-framed delivery fields; existing callers keep their style.
  final bool gradientFrame;

  const PhoneInputField({
    super.key,
    this.controller,
    this.initialValue,
    this.isRequired = false,
    this.hintText = 'Номер телефона',
    this.onChanged,
    this.enabled = true,
    this.textInputAction,
    this.gradientFrame = false,
  });

  static PhoneNumber? parse(String? phone) {
    if (phone == null || phone.trim().isEmpty) return null;
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.isEmpty) return null;

    try {
      return PhoneNumber.parse(cleaned.startsWith('+') ? cleaned : '+$cleaned');
    } catch (_) {
      return null;
    }
  }

  static String? internationalValue(PhoneNumber phone) {
    if (phone.nsn.trim().isEmpty || !phone.isValid()) return null;
    return phone.international;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = context.brandPrimary;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final topInset = MediaQuery.viewPaddingOf(context).top;
    final maxCountrySheetSize = ((screenHeight - topInset - 24) / screenHeight)
        .clamp(0.78, 0.94 - 24 / screenHeight);

    final field = Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(primary: primary),
      ),
      child: PhoneFormField(
        controller: controller,
        initialValue: controller != null
            ? null
            : (initialValue ?? const PhoneNumber(isoCode: IsoCode.RU, nsn: '')),
        countrySelectorNavigator: CountrySelectorNavigator.draggableBottomSheet(
          initialChildSize: 0.78,
          minChildSize: 0.45,
          maxChildSize: maxCountrySheetSize,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          backgroundColor: Colors.white,
          favorites: const [
            IsoCode.RU,
            IsoCode.CN,
            IsoCode.KZ,
            IsoCode.BY,
            IsoCode.KG,
            IsoCode.UZ,
          ],
          showDialCode: true,
          sortCountries: true,
          noResultMessage: 'Страна не найдена',
          flagSize: 28,
          searchBoxIconColor: primary,
          titleStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
          subtitleStyle: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
          searchBoxTextStyle: const TextStyle(
            fontSize: 15,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          searchBoxDecoration: appInputDecoration(
            context,
            hintText: 'Поиск страны',
            hintStyle: const TextStyle(
              color: Color(0xFF999999),
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: Icon(Icons.search_rounded, color: primary),
            fillColor: const Color(0xFFF7F7FA),
            borderColor: const Color(0xFFE0E0E0),
            focusedBorderColor: primary,
            focusedWidth: 2,
            radius: kAppInputLargeRadius,
          ),
        ),
        isCountryButtonPersistent: true,
        countryButtonStyle: CountryButtonStyle(
          showDialCode: true,
          showIsoCode: false,
          showFlag: true,
          flagSize: 20,
          dropdownIconColor: primary,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        decoration: gradientFrame
            ? InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF999999),
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                prefixIconConstraints: const BoxConstraints(minHeight: 0),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              )
            : appInputDecoration(
                context,
                hintText: hintText,
                hintStyle: const TextStyle(
                  color: Color(0xFF999999),
                  fontWeight: FontWeight.w500,
                ),
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                borderColor: const Color(0xFFE0E0E0),
                focusedBorderColor: primary,
                radius: kAppInputLargeRadius,
                focusedWidth: 2,
              ),
        enabled: enabled,
        textInputAction: textInputAction,
        onChanged: onChanged,
        validator: isRequired
            ? PhoneValidator.compose([
                PhoneValidator.required(
                  context,
                  errorText: 'Укажите номер телефона',
                ),
                PhoneValidator.valid(
                  context,
                  errorText: 'Введите корректный номер телефона',
                ),
              ])
            : PhoneValidator.valid(
                context,
                errorText: 'Введите корректный номер телефона',
              ),
      ),
    );
    return gradientFrame ? AppGradientInputFrame(child: field) : field;
  }
}
