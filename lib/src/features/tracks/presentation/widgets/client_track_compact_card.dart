import 'package:flutter/material.dart';

import '../../../../core/ui/app_colors.dart';
import '../../../training/presentation/training_target.dart';

Widget _trainingTarget(String? id, Widget child, {VoidCallback? onActivate}) =>
    id == null
    ? child
    : TrainingTarget(id: id, onActivate: onActivate, child: child);

class ClientTrackIndicator {
  final IconData icon;
  final String title;
  final String value;
  final String label;
  final Color color;
  final int tabIndex;
  final String? trainingTargetId;

  const ClientTrackIndicator({
    required this.icon,
    required this.title,
    required this.value,
    required this.label,
    required this.color,
    required this.tabIndex,
    this.trainingTargetId,
  });
}

class ClientTrackQuickAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  final String? trainingTargetId;

  const ClientTrackQuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.trainingTargetId,
  });
}

class ClientTrackCompactCard extends StatelessWidget {
  final String trackNumber;
  final String status;
  final Color statusColor;
  final String productName;
  final bool selectable;
  final bool selected;
  final VoidCallback? onToggleSelection;
  final VoidCallback onCopyTrack;
  final ValueChanged<int> onOpenDetails;
  final List<ClientTrackIndicator> indicators;
  final List<ClientTrackQuickAction> actions;
  final Widget? footer;
  final String entityLabel;
  final IconData leadingIcon;
  final bool showCopyAction;
  final String? trainingOpenId;
  final String? trainingStatusId;
  final String? trainingSelectionId;

  const ClientTrackCompactCard({
    super.key,
    required this.trackNumber,
    required this.status,
    required this.statusColor,
    required this.productName,
    required this.selectable,
    required this.selected,
    required this.onToggleSelection,
    required this.onCopyTrack,
    required this.onOpenDetails,
    required this.indicators,
    required this.actions,
    this.footer,
    this.entityLabel = 'Трек',
    this.leadingIcon = Icons.local_shipping_rounded,
    this.showCopyAction = true,
    this.trainingOpenId,
    this.trainingStatusId,
    this.trainingSelectionId,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.brandPrimary;
    final displayProductName = productName.trim();
    return Semantics(
      button: true,
      selected: selected,
      label: '$entityLabel $trackNumber, $status',
      onTap: () => onOpenDetails(0),
      child: Material(
        color: Colors.white,
        elevation: 0,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.64)
                  : Colors.black.withValues(alpha: 0.035),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: selected
                    ? accent.withValues(alpha: 0.13)
                    : Colors.black.withValues(alpha: 0.055),
                blurRadius: 24,
                spreadRadius: -13,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: InkWell(
            key: ValueKey('client-track-card-$trackNumber'),
            onTap: () => onOpenDetails(0),
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                14,
                14,
                14,
                actions.isNotEmpty && footer == null ? 0 : 13,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (selectable) ...[
                        _trainingTarget(
                          trainingSelectionId,
                          _SelectionButton(
                            selected: selected,
                            accent: accent,
                            onTap: onToggleSelection!,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ] else ...[
                        _TrackIconTile(accent: accent, icon: leadingIcon),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: _trainingTarget(
                                    trainingOpenId,
                                    Text(
                                      trackNumber,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: 'Gilroy',
                                        fontSize: 16,
                                        height: 1.1,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.1,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    onActivate: () => onOpenDetails(0),
                                  ),
                                ),
                                if (showCopyAction) ...[
                                  const SizedBox(width: 2),
                                  _CopyButton(onTap: onCopyTrack),
                                ],
                              ],
                            ),
                            if (displayProductName.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                displayProductName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Gilroy',
                                  fontSize: 11.5,
                                  height: 1.05,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary.withValues(
                                    alpha: 0.68,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 7),
                      _trainingTarget(
                        trainingStatusId,
                        _StatusPill(text: status, color: statusColor),
                      ),
                    ],
                  ),
                  if (indicators.isNotEmpty) ...[
                    const SizedBox(height: 11),
                    _IndicatorPanel(
                      indicators: indicators,
                      onOpenDetails: onOpenDetails,
                    ),
                  ],
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _QuickActionPanel(actions: actions),
                  ],
                  if (footer != null) ...[const SizedBox(height: 10), footer!],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ClientTrackDetailTabs extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<int> visibleIndices;

  const ClientTrackDetailTabs({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.visibleIndices = const [0, 1, 2, 3, 4],
  });

  static const labels = [
    'Основное',
    'Доставка до склада',
    'Фотоотчёт',
    'Вопросы',
    'Возвраты',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            for (
              var position = 0;
              position < visibleIndices.length;
              position++
            ) ...[
              if (position > 0) const SizedBox(width: 6),
              Builder(
                builder: (_) {
                  final index = visibleIndices[position];
                  return _DetailTabButton(
                    index: index,
                    label: labels[index],
                    selected: selectedIndex == index,
                    onTap: () => onSelected(index),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailTabButton extends StatelessWidget {
  final int index;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DetailTabButton({
    required this.index,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: 44,
        constraints: const BoxConstraints(minWidth: 104),
        decoration: BoxDecoration(
          gradient: selected ? context.brandGradient : null,
          color: selected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: context.brandPrimary.withValues(alpha: 0.18),
                    blurRadius: 14,
                    spreadRadius: -8,
                    offset: const Offset(0, 7),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('client-track-detail-tab-$index'),
            onTap: selected ? null : onTap,
            borderRadius: BorderRadius.circular(14),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'Gilroy',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: selected ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionButton extends StatelessWidget {
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _SelectionButton({
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      checked: selected,
      label: selected ? 'Убрать трек из выбора' : 'Выбрать трек для сборки',
      child: InkResponse(
        key: const ValueKey('client-track-selection'),
        onTap: onTap,
        radius: 24,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: selected ? accent : const Color(0xFFF5F5F7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: selected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 17,
                      color: Colors.white,
                    )
                  : Icon(
                      Icons.add_rounded,
                      size: 17,
                      color: AppColors.textSecondary.withValues(alpha: 0.72),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CopyButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CopyButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Скопировать трек-номер',
      child: InkResponse(
        key: const ValueKey('client-track-copy'),
        onTap: onTap,
        radius: 20,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 27,
              height: 27,
              decoration: BoxDecoration(
                color: context.brandPrimary.withValues(alpha: 0.075),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                Icons.copy_rounded,
                size: 14,
                color: context.brandPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackIconTile extends StatelessWidget {
  final Color accent;
  final IconData icon;

  const _TrackIconTile({required this.accent, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, size: 20, color: accent),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String text;
  final Color color;

  const _StatusPill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 112),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.115),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'Gilroy',
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _IndicatorPanel extends StatelessWidget {
  final List<ClientTrackIndicator> indicators;
  final ValueChanged<int> onOpenDetails;

  const _IndicatorPanel({
    required this.indicators,
    required this.onOpenDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < indicators.length; index++) ...[
          if (index > 0) const SizedBox(width: 6),
          Expanded(
            child: _trainingTarget(
              indicators[index].trainingTargetId,
              _IndicatorCell(
                indicator: indicators[index],
                onTap: () => onOpenDetails(indicators[index].tabIndex),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _IndicatorCell extends StatelessWidget {
  final ClientTrackIndicator indicator;
  final VoidCallback onTap;

  const _IndicatorCell({required this.indicator, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: indicator.label,
      excludeSemantics: true,
      child: Material(
        color: indicator.color.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: ValueKey('client-track-indicator-${indicator.tabIndex}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(indicator.icon, size: 14, color: indicator.color),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      indicator.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Gilroy',
                        fontSize: 11,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        color: indicator.color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActionPanel extends StatelessWidget {
  final List<ClientTrackQuickAction> actions;
  const _QuickActionPanel({required this.actions});
  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('client-track-action-panel'),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: const BoxDecoration(
        color: Color(0xFFF7F8FB),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(23),
          bottomRight: Radius.circular(23),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
          final columns = actions.length <= 4 && !largeText
              ? actions.length
              : (largeText
                    ? 2
                    : constraints.maxWidth >= 350
                    ? 4
                    : 3);
          final width = (constraints.maxWidth - 4 * (columns - 1)) / columns;
          return Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final action in actions)
                SizedBox(
                  width: width,
                  child: _QuickActionButton(action: action),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final ClientTrackQuickAction action;

  const _QuickActionButton({required this.action});

  @override
  Widget build(BuildContext context) {
    final color = action.destructive ? Colors.redAccent : context.brandPrimary;
    return _trainingTarget(
      action.trainingTargetId,
      Semantics(
        button: true,
        label: action.label,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('client-track-action-${action.label}'),
            onTap: action.onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 25,
                      height: 25,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(action.icon, size: 14, color: color),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      action.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Gilroy',
                        fontSize: 11,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        color: action.destructive
                            ? color
                            : AppColors.textPrimary.withValues(alpha: 0.76),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
