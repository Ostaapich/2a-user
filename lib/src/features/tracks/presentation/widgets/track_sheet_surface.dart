import 'package:flutter/material.dart';

import '../../../../core/ui/app_colors.dart';
import '../../../../core/ui/sheet_handle.dart';
import '../../../training/presentation/training_target.dart';

class TrackSheetSurface extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? pinnedChild;
  final Widget? footer;
  final EdgeInsetsGeometry contentPadding;
  final bool keyboardAware;
  final ScrollController? scrollController;
  final bool useMaxHeight;
  final bool showHandle;

  const TrackSheetSurface({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.pinnedChild,
    this.footer,
    this.contentPadding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
    this.keyboardAware = false,
    this.scrollController,
    this.useMaxHeight = false,
    this.showHandle = true,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final keyboardInset = keyboardAware
        ? MediaQuery.viewInsetsOf(context).bottom
        : 0.0;
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.9;

    return Stack(
      children: [
        if (keyboardInset > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: keyboardInset,
            child: const ColoredBox(color: Colors.white),
          ),
        AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(bottom: keyboardInset),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Container(
              height: useMaxHeight ? maxSheetHeight : null,
              constraints: BoxConstraints(maxHeight: maxSheetHeight),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showHandle)
                    Center(
                      child: TrainingTarget(
                        id: 'track.sheet.dismiss-handle',
                        onActivate: () => Navigator.of(context).pop(),
                        child: const SizedBox(width: 42, child: SheetHandle()),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      showHandle ? 0 : 16,
                      16,
                      14,
                    ),
                    child: _TrackSheetHeader(
                      icon: icon,
                      title: title,
                      subtitle: subtitle,
                    ),
                  ),
                  if (pinnedChild != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: pinnedChild,
                    ),
                  Flexible(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Padding(padding: contentPadding, child: child),
                    ),
                  ),
                  if (footer != null)
                    ColoredBox(
                      color: Colors.white,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          12,
                          16,
                          12 + bottomPadding,
                        ),
                        child: footer,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TrackSheetHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _TrackSheetHeader({
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

class TrackSheetOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final int titleMaxLines;
  final bool radioIndicator;

  const TrackSheetOptionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.titleMaxLines = 1,
    this.radioIndicator = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.brandPrimary;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.10)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.22)
                  : Colors.black.withValues(alpha: 0.035),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: selected
                      ? accent.withValues(alpha: 0.13)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  icon,
                  color: selected ? accent : AppColors.textSecondary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: titleMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? accent : AppColors.textPrimary,
                        fontFamily: 'Gilroy',
                        fontSize: 15,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontFamily: 'Gilroy',
                        fontSize: 12.5,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: selected ? accent : Colors.white,
                  borderRadius: BorderRadius.circular(radioIndicator ? 14 : 10),
                  border: Border.all(
                    color: selected
                        ? accent
                        : Colors.black.withValues(alpha: 0.08),
                  ),
                ),
                child: selected
                    ? Icon(
                        radioIndicator ? Icons.circle : Icons.check_rounded,
                        color: Colors.white,
                        size: radioIndicator ? 12 : 18,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TrackSheetPrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const TrackSheetPrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 48,
          decoration: BoxDecoration(
            gradient: onTap == null ? null : context.brandGradient,
            color: onTap == null ? const Color(0xFFE8EAEE) : null,
            borderRadius: BorderRadius.circular(16),
            boxShadow: onTap == null
                ? null
                : [
                    BoxShadow(
                      color: context.brandPrimary.withValues(alpha: 0.18),
                      blurRadius: 14,
                      spreadRadius: -8,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: onTap == null ? AppColors.textSecondary : Colors.white,
                size: 19,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onTap == null
                        ? AppColors.textSecondary
                        : Colors.white,
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
}
