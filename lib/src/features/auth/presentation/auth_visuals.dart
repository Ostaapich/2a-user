import 'package:flutter/material.dart';

import '../../../core/ui/app_colors.dart';

class AuthVisuals {
  const AuthVisuals._();

  static const fallbackPrimary = Color(0xFFFF5E04);
  static const fallbackSecondary = Color(0xFF2563EB);
  static const fallbackWarm = Color(0xFFFFB547);
  static const ink = Color(0xFF101828);
  static const muted = Color(0xFF667085);

  static Color primary(BuildContext context) {
    final brand = context.brandPrimary;
    final hsl = HSLColor.fromColor(brand);
    if (hsl.saturation < 0.18) return fallbackPrimary;
    return brand;
  }

  static Color secondary(BuildContext context) {
    final brand = context.brandSecondary;
    final hsl = HSLColor.fromColor(brand);
    if (hsl.saturation < 0.18) return fallbackSecondary;
    return brand;
  }

  static LinearGradient gradient(BuildContext context) {
    final primaryColor = primary(context);
    final secondaryColor = secondary(context);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [primaryColor, fallbackWarm, secondaryColor],
      stops: const [0, 0.48, 1],
    );
  }

  static ButtonStyle primaryButtonStyle(BuildContext context) {
    final accent = primary(context);
    return FilledButton.styleFrom(
      backgroundColor: accent,
      foregroundColor: Colors.white,
      disabledBackgroundColor: accent.withValues(alpha: 0.45),
      disabledForegroundColor: Colors.white.withValues(alpha: 0.76),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  static ButtonStyle outlinedButtonStyle(BuildContext context) {
    final accent = primary(context);
    return OutlinedButton.styleFrom(
      foregroundColor: accent,
      side: BorderSide(color: accent.withValues(alpha: 0.34)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: Colors.white.withValues(alpha: 0.68),
    );
  }
}

class AuthTrustItem {
  final IconData icon;
  final String label;

  const AuthTrustItem({required this.icon, required this.label});
}

class AuthResponsiveContent extends StatelessWidget {
  final Widget child;

  const AuthResponsiveContent({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final maxWidth = width >= 900 ? 520.0 : 560.0;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

class AuthHeroHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String eyebrow;
  final List<AuthTrustItem> trustItems;

  const AuthHeroHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.eyebrow = 'Личный кабинет',
    this.trustItems = const [],
  });

  @override
  Widget build(BuildContext context) {
    final accent = AuthVisuals.primary(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  eyebrow,
                  style: TextStyle(
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              gradient: AuthVisuals.gradient(context),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.28),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Center(child: Icon(icon, color: Colors.white, size: 44)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 27,
            height: 1.08,
            fontWeight: FontWeight.w900,
            color: AuthVisuals.ink,
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              height: 1.42,
              fontWeight: FontWeight.w600,
              color: AuthVisuals.muted,
            ),
          ),
        ),
        if (trustItems.isNotEmpty) ...[
          const SizedBox(height: 18),
          AuthTrustChips(items: trustItems),
        ],
      ],
    );
  }
}

class AuthTrustChips extends StatelessWidget {
  final List<AuthTrustItem> items;

  const AuthTrustChips({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [for (final item in items) _AuthTrustChip(item: item)],
    );
  }
}

class _AuthTrustChip extends StatelessWidget {
  final AuthTrustItem item;

  const _AuthTrustChip({required this.item});

  @override
  Widget build(BuildContext context) {
    final accent = AuthVisuals.primary(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.14)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item.icon, color: accent, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              item.label,
              style: const TextStyle(
                color: AuthVisuals.ink,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AuthFormCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AuthFormCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    final accent = AuthVisuals.primary(context);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.74)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
          const BoxShadow(
            color: Color(0x10000000),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: padding,
      child: child,
    );
  }
}
