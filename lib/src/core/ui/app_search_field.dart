import 'package:flutter/material.dart';

import '../utils/locale_text.dart';
import 'app_input_decoration.dart';
import 'app_colors.dart';
import 'app_keyboard_dismiss.dart';

/// Shared appearance only: callers keep query, filtering and request ownership.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.textInputAction = TextInputAction.done,
    this.autofocus = false,
    this.focusNode,
    this.hasError = false,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final TextInputAction textInputAction;
  final bool autofocus;

  /// Borrowed from the caller; its lifecycle remains caller-owned.
  final FocusNode? focusNode;
  final bool hasError;

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    builder: (context, value, _) => AppOutlinedInputFrame(
      height: 48,
      radius: 16,
      fillColor: const Color(0xFFF8FAFC),
      borderColor: hasError ? const Color(0xFFE53935) : const Color(0xFFE3E7EE),
      focusedBorderColor: hasError ? const Color(0xFFE53935) : null,
      builder: (context, frameFocusNode) {
        final inputFocusNode = focusNode ?? frameFocusNode;
        final field = TextField(
          controller: controller,
          focusNode: inputFocusNode,
          textInputAction: textInputAction,
          autofocus: autofocus,
          onChanged: onChanged,
          onSubmitted: (value) {
            AppKeyboardDismissRegion.dismiss(scope: FocusScope.of(context));
            onSubmitted?.call(value);
          },
          onTapOutside: (_) =>
              AppKeyboardDismissRegion.dismiss(scope: FocusScope.of(context)),
          style: const TextStyle(
            fontFamily: 'Gilroy',
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(
              fontFamily: 'Gilroy',
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
            prefixIcon: inputFocusNode.hasFocus
                ? null
                : Icon(
                    Icons.search_rounded,
                    color: context.brandPrimary,
                    size: 22,
                  ),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: tr(context, ru: 'Очистить поиск', zh: '清除搜索'),
                    onPressed: () {
                      controller.clear();
                      if (onClear != null) {
                        onClear!();
                      } else {
                        onChanged('');
                      }
                    },
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        );
        // The frame observes descendant focus without adopting or disposing
        // a caller-owned node, and without adding another tab stop.
        return focusNode == null
            ? field
            : Focus(
                focusNode: frameFocusNode,
                skipTraversal: true,
                canRequestFocus: false,
                child: field,
              );
      },
    ),
  );
}
