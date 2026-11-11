import 'package:flutter/material.dart';

import '../../../core/ui/app_colors.dart';
import '../../../core/utils/locale_text.dart';

class HomeStatsGrid extends StatelessWidget {
  final String tracksValue;
  final String? pendingTracksValue;
  final String? warehouseTracksValue;
  final String assembliesValue;
  final String invoicesValue;
  final String bonusKgValue;
  final VoidCallback onTracksTap;
  final VoidCallback onAssembliesTap;
  final VoidCallback onInvoicesTap;
  final VoidCallback onBonusKgTap;

  const HomeStatsGrid({
    super.key,
    required this.tracksValue,
    this.pendingTracksValue,
    this.warehouseTracksValue,
    required this.assembliesValue,
    required this.invoicesValue,
    required this.bonusKgValue,
    required this.onTracksTap,
    required this.onAssembliesTap,
    required this.onInvoicesTap,
    required this.onBonusKgTap,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final cards = [
        _HomeStatCard(
          title: tr(context, ru: 'Треки', zh: '运单'),
          value: tracksValue,
          details: [
            if (pendingTracksValue != null)
              tr(
                context,
                ru: 'В ожидании: $pendingTracksValue',
                zh: '待入库：$pendingTracksValue',
              ),
            if (warehouseTracksValue != null)
              tr(
                context,
                ru: 'На складе: $warehouseTracksValue',
                zh: '已入库：$warehouseTracksValue',
              ),
          ],
          icon: Icons.local_shipping_rounded,
          onTap: onTracksTap,
        ),
        _HomeStatCard(
          title: tr(context, ru: 'Сборки', zh: '合箱'),
          value: assembliesValue,
          icon: Icons.inventory_2_rounded,
          onTap: onAssembliesTap,
        ),
        _HomeStatCard(
          title: tr(context, ru: 'Счета', zh: '账单'),
          value: invoicesValue,
          icon: Icons.receipt_long_rounded,
          onTap: onInvoicesTap,
        ),
        _HomeStatCard(
          title: tr(context, ru: 'Бонусные кг', zh: '奖励公斤'),
          value: bonusKgValue,
          icon: Icons.scale_rounded,
          onTap: onBonusKgTap,
        ),
      ];
      Widget row(List<Widget> items) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: items[i]),
            ],
          ],
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row(cards.take(2).toList()),
          const SizedBox(height: 8),
          row(cards.skip(2).toList()),
        ],
      );
    },
  );
}

class _HomeStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final List<String> details;
  final VoidCallback onTap;
  const _HomeStatCard({
    required this.title,
    required this.value,
    required this.icon,
    this.details = const [],
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: context.brandPrimary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: context.brandPrimary, size: 19),
                ),
                const Spacer(),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Gilroy',
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: const TextStyle(
                  fontFamily: 'Gilroy',
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 25,
                  height: 1.1,
                ),
              ),
            ),
            for (final detail in details) ...[
              const SizedBox(height: 5),
              Text(
                detail,
                style: const TextStyle(
                  fontFamily: 'Gilroy',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
