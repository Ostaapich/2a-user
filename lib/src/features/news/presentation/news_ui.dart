import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/app_colors.dart';

const newsTextColor = Color(0xFF2F2F2F);
const newsMutedTextColor = Color(0x992F2F2F);

class NewsUi {
  const NewsUi._();

  static BoxDecoration cardDecoration({Color color = Colors.white}) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 24,
          spreadRadius: -14,
          offset: const Offset(0, 14),
        ),
      ],
    );
  }

  static BoxDecoration softDecoration() {
    return BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.black.withValues(alpha: 0.025)),
    );
  }

  static TextStyle get sectionTitleStyle {
    return const TextStyle(
      color: AppColors.textPrimary,
      fontFamily: 'Gilroy',
      fontSize: 18,
      height: 22 / 18,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.15,
    );
  }
}

class NewsPageHeader extends StatelessWidget {
  final String title;

  const NewsPageHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
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

class NewsHeroCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> chips;
  final int? titleMaxLines;

  const NewsHeroCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.chips = const [],
    this.titleMaxLines = 2,
  });

  @override
  Widget build(BuildContext context) {
    final showIcon =
        titleMaxLines != null &&
        MediaQuery.textScalerOf(context).scale(1) <= 1.3;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: context.brandGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: context.brandPrimary.withValues(alpha: 0.22),
            blurRadius: 28,
            spreadRadius: -12,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            const Positioned.fill(child: NewsHeaderGlowBackdrop()),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (showIcon)
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Icon(icon, color: Colors.white, size: 30),
                        ),
                      if (showIcon) const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: titleMaxLines,
                              overflow: titleMaxLines == null
                                  ? TextOverflow.visible
                                  : TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'Gilroy',
                                fontSize: 24,
                                height: 1.04,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              subtitle,
                              maxLines: 3,
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
                  if (chips.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(spacing: 8, runSpacing: 8, children: chips),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NewsHeroChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const NewsHeroChip({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'Gilroy',
              fontSize: 12.5,
              height: 1,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class NewsHeaderGlowBackdrop extends StatefulWidget {
  const NewsHeaderGlowBackdrop({super.key});

  @override
  State<NewsHeaderGlowBackdrop> createState() => _NewsHeaderGlowBackdropState();
}

class _NewsHeaderGlowBackdropState extends State<NewsHeaderGlowBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final wave = Curves.easeInOutCubic.transform(_controller.value);
            final shift = (wave * 2) - 1;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  right: -62,
                  top: -58,
                  child: Transform.translate(
                    offset: Offset(-10 * shift, 6 * shift),
                    child: _NewsGlowCircle(
                      size: 154,
                      color: Colors.white.withValues(alpha: 0.13),
                    ),
                  ),
                ),
                Positioned(
                  right: 22,
                  bottom: -68,
                  child: Transform.translate(
                    offset: Offset(9 * shift, -7 * shift),
                    child: _NewsGlowCircle(
                      size: 152,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                Positioned(
                  right: -14,
                  bottom: 16,
                  child: Transform.translate(
                    offset: Offset(5 * shift, -4 * shift),
                    child: _NewsGlowCircle(
                      size: 82,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NewsGlowCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _NewsGlowCircle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class NewsStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final bool isLoading;
  final bool isError;

  const NewsStateCard({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.isLoading = false,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isError ? const Color(0xFFE53935) : context.brandPrimary;
    return Container(
      decoration: NewsUi.cardDecoration(),
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: isLoading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accent,
                      ),
                    )
                  : Icon(icon, color: accent, size: 24),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 18,
                    height: 22 / 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.1,
                  ),
                ),
                if (message != null && message!.trim().isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    message!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontFamily: 'Gilroy',
                      fontSize: 13.5,
                      height: 18 / 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class NewsDatePill extends StatelessWidget {
  final String label;
  final Color? color;

  const NewsDatePill({super.key, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final accent = color ?? context.brandPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_today_rounded, size: 13, color: accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Gilroy',
              fontSize: 12,
              height: 1,
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}
