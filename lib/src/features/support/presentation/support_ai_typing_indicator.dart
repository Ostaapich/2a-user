import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/ui/app_colors.dart';
import '../../../core/utils/locale_text.dart';

/// Ephemeral activity, deliberately separate from saved chat messages.
class SupportAiTypingIndicator extends StatefulWidget {
  const SupportAiTypingIndicator({super.key});

  @override
  State<SupportAiTypingIndicator> createState() =>
      _SupportAiTypingIndicatorState();
}

class _SupportAiTypingIndicatorState extends State<SupportAiTypingIndicator>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _animation.stop();
    } else if (!_animation.isAnimating) {
      _animation.repeat();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = tr(context, ru: 'Помощник печатает', zh: '助手正在输入');
    return Semantics(
      liveRegion: true,
      label: '$label…',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [context.brandPrimary, context.brandSecondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.support_agent_rounded,
                color: Colors.white,
                size: 17,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(22),
                    topRight: Radius.circular(22),
                    bottomLeft: Radius.circular(6),
                    bottomRight: Radius.circular(22),
                  ),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.035),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontFamily: 'Gilroy',
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedBuilder(
                      animation: _animation,
                      builder: (context, _) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(3, (index) {
                          final phase = _animation.value - index / 3;
                          final opacity =
                              MediaQuery.disableAnimationsOf(context)
                              ? 0.65
                              : 0.35 +
                                    0.65 *
                                        (1 + math.sin(phase * math.pi * 2)) /
                                        2;
                          return Padding(
                            padding: EdgeInsets.only(left: index == 0 ? 0 : 4),
                            child: Opacity(
                              key: ValueKey('assistant-typing-dot-$index'),
                              opacity: opacity,
                              child: Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                  color: AppColors.textSecondary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
