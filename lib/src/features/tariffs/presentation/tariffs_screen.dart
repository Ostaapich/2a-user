import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../training/presentation/training_target.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/ui/app_layout.dart';
import '../../../core/ui/scroll_to_top_button.dart';
import '../../../core/ui/tutorial_card.dart';
import '../data/tariffs_provider.dart';
import '../../tracks/domain/photo_report_options.dart';
import '../../../core/utils/locale_text.dart';
import 'tariffs_ui.dart';

class TariffsScreen extends ConsumerStatefulWidget {
  const TariffsScreen({super.key});

  @override
  ConsumerState<TariffsScreen> createState() => _TariffsScreenState();
}

class _TariffsScreenState extends ConsumerState<TariffsScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _tariffsListKey = GlobalKey();
  final GlobalKey _weightTiersKey = GlobalKey();
  final GlobalKey _packagingKey = GlobalKey();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tariffsAsync = ref.watch(userTariffsProvider);
    final topPad = AppLayout.topBarTotalHeight(context);
    final bottomPad = AppLayout.bottomScrollPadding(context);

    Future<void> onRefresh() async {
      ref.invalidate(userTariffsProvider);
      await ref.read(userTariffsProvider.future);
    }

    Widget buildFrame({required List<Widget> children}) {
      return Stack(
        children: [
          RefreshIndicator(
            onRefresh: onRefresh,
            color: context.brandPrimary,
            child: ListView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                16,
                topPad * 0.7 + 16,
                16,
                bottomPad + 16,
              ),
              children: children,
            ),
          ),
          ScrollToTopButton(controller: _scrollController),
        ],
      );
    }

    List<Widget> baseHeader() {
      return const [
        TariffsPageHeader(),
        SizedBox(height: 12),
        TariffsHeroCard(),
        SizedBox(height: 14),
      ];
    }

    return tariffsAsync.when(
      loading: () => buildFrame(
        children: [
          ...baseHeader(),
          const TariffsStateCard(
            icon: Icons.price_change_rounded,
            title: 'Загружаем тарифы',
            message: 'Получаем актуальные тарифы доставки и услуг.',
            isLoading: true,
          ),
        ],
      ),
      error: (e, _) => buildFrame(
        children: [
          ...baseHeader(),
          TariffsStateCard(
            icon: Icons.error_outline_rounded,
            title: 'Не удалось загрузить тарифы',
            message: 'Проверьте соединение и попробуйте ещё раз.',
            isError: true,
            actionLabel: 'Повторить',
            onAction: () => ref.invalidate(userTariffsProvider),
          ),
        ],
      ),
      data: (data) {
        final hasDensityTariffs = data.deliveryTariffs.any(
          (tariff) => tariff.isDensityBased,
        );
        final isEmpty =
            data.deliveryTariffs.isEmpty &&
            data.packagingTypes.isEmpty &&
            data.photoReportOptions == null;

        if (isEmpty) {
          return buildFrame(
            children: [
              ...baseHeader(),
              const TariffsStateCard(
                icon: Icons.price_change_outlined,
                title: 'Тарифы не настроены',
                message:
                    'Когда агент добавит тарифы, они появятся на этой странице.',
              ),
            ],
          );
        }

        return TutorialScreenWrapper(
          screenKey: 'tariffs',
          steps: [
            TutorialStep(
              icon: Icons.local_shipping_rounded,
              title: 'Тарифы доставки',
              description: hasDensityTariffs
                  ? tr(
                      context,
                      ru: 'Актуальная стоимость доставки. Цена указана за 1 кг или 1 м³ в зависимости от тарифа. Тариф назначается менеджером при оформлении.',
                      zh: '当前运费根据运价按每千克或每立方米显示。办理运输时由经理分配运价。',
                    )
                  : 'Актуальная стоимость доставки по каждому тарифу. Цена указана за 1 кг. Тариф назначается менеджером при оформлении.',
              targetKey: _tariffsListKey,
            ),
            TutorialStep(
              icon: Icons.scale_rounded,
              title: hasDensityTariffs
                  ? tr(context, ru: 'Диапазоны тарифов', zh: '运价区间')
                  : 'Весовые диапазоны',
              description: hasDensityTariffs
                  ? tr(
                      context,
                      ru: 'Диапазон зависит от типа тарифа: веса партии или плотности (вес ÷ объём). Ставка за кг или м³ указана в каждой строке.',
                      zh: '区间取决于运价类型：货物重量或密度（重量 ÷ 体积）。每行注明按千克或立方米收费。',
                    )
                  : 'Чем тяжелее партия — тем ниже цена за кг. Итоговый тариф выбирается автоматически при выставлении счёта.',
              targetKey: _weightTiersKey,
            ),
            TutorialStep(
              icon: Icons.inventory_rounded,
              title: 'Упаковка',
              description:
                  'Стоимость дополнительной упаковки прибавляется к счёту. Упаковка защищает товар при транспортировке.',
              targetKey: _packagingKey,
            ),
          ],
          child: buildFrame(
            children: [
              ...baseHeader(),
              if (data.deliveryTariffs.isNotEmpty) ...[
                for (var i = 0; i < data.deliveryTariffs.length; i++) ...[
                  if (i == 0)
                    KeyedSubtree(
                      key: _weightTiersKey,
                      child: _DeliveryTariffCard(
                        tariff: data.deliveryTariffs[i],
                        trainingTarget: true,
                      ),
                    )
                  else
                    _DeliveryTariffCard(tariff: data.deliveryTariffs[i]),
                  if (i != data.deliveryTariffs.length - 1)
                    const SizedBox(height: 12),
                ],
                const SizedBox(height: 16),
              ],
              if (data.packagingTypes.isNotEmpty) ...[
                KeyedSubtree(
                  key: _packagingKey,
                  child: const _SectionTitle(
                    icon: Icons.inventory_2_rounded,
                    title: 'Упаковка',
                    subtitle: 'Дополнительная защита товара при перевозке.',
                  ),
                ),
                const SizedBox(height: 10),
                _PackagingCard(types: data.packagingTypes),
                const SizedBox(height: 16),
              ],
              if (data.photoReportOptions != null) ...[
                _SectionTitle(
                  icon: Icons.photo_camera_rounded,
                  title: tr(context, ru: 'Фотоотчёт', zh: '拍照报告'),
                  subtitle: tr(
                    context,
                    ru: 'Фиксированная цена за выполненный отчёт. Оплата в ближайшем счёте на доставку.',
                    zh: '按完成的报告固定收费，计入下一张运输账单。',
                  ),
                ),
                const SizedBox(height: 10),
                _PhotoReportCard(options: data.photoReportOptions!),
              ],
              const SizedBox(height: 12),
              const _TariffInfoNote(),
            ],
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: context.brandPrimary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: context.brandPrimary, size: 22),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TariffsUi.sectionTitleStyle),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'Gilroy',
                  fontSize: 13,
                  height: 17 / 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeliveryTariffCard extends StatelessWidget {
  final UserDeliveryTariff tariff;

  const _DeliveryTariffCard({
    required this.tariff,
    this.trainingTarget = false,
  });
  final bool trainingTarget;

  @override
  Widget build(BuildContext context) {
    final densityBased = tariff.isDensityBased;
    final hasTiers = densityBased
        ? tariff.densityTiers.isNotEmpty
        : tariff.weightTiers.isNotEmpty;
    final hasAllowed = tariff.allowedItems?.trim().isNotEmpty == true;
    final hasProhibited = tariff.prohibitedItems?.trim().isNotEmpty == true;

    return Container(
      decoration: TariffsUi.cardDecoration(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TrainingTarget(
                      id: trainingTarget
                          ? 'tariffs.name'
                          : 'tariffs.name.${tariff.id}',
                      child: Text(
                        tariff.name,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontFamily: 'Gilroy',
                          fontSize: 18,
                          height: 22 / 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.15,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        _SmallPill(
                          icon: tariff.requiresProductInfo
                              ? Icons.assignment_outlined
                              : Icons.assignment_turned_in_outlined,
                          label: tariff.requiresProductInfo
                              ? 'Нужны данные о товаре'
                              : 'Без данных о товаре',
                          color: tariff.requiresProductInfo
                              ? context.brandPrimary
                              : const Color(0xFF2EAD63),
                        ),
                        if (hasTiers)
                          _SmallPill(
                            icon: Icons.scale_rounded,
                            label: densityBased
                                ? tr(
                                    context,
                                    ru: 'Есть диапазоны плотности',
                                    zh: '按密度分区间',
                                  )
                                : 'Есть диапазоны веса',
                            color: const Color(0xFF3F7AE0),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _MainPriceBadge(
                pricePerKg: densityBased
                    ? tariff.minimumDensityPricePerKg
                    : _mainPrice(tariff),
                pricePerM3: densityBased
                    ? tariff.minimumDensityPricePerM3
                    : null,
                showFrom: true,
              ),
            ],
          ),
          if (hasTiers || densityBased) ...[
            const SizedBox(height: 12),
            Container(
              decoration: TariffsUi.softDecoration(),
              child: Material(
                color: Colors.transparent,
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  backgroundColor: Colors.transparent,
                  collapsedBackgroundColor: Colors.transparent,
                  iconColor: context.brandPrimary,
                  collapsedIconColor: context.brandPrimary,
                  title: Text(
                    tr(context, ru: 'Диапазоны и ставки', zh: '区间及费率'),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontFamily: 'Gilroy',
                      fontSize: 14,
                      height: 17 / 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  children: [
                    densityBased
                        ? _DensityTiersBlock(tiers: tariff.densityTiers)
                        : _WeightTiersBlock(tiers: tariff.weightTiers),
                  ],
                ),
              ),
            ),
          ],
          if (hasAllowed || hasProhibited) ...[
            const SizedBox(height: 12),
            if (hasAllowed)
              _RulesTextBlock(
                icon: Icons.check_circle_outline_rounded,
                title: 'Разрешено',
                text: tariff.allowedItems!.trim(),
                color: const Color(0xFF2EAD63),
              ),
            if (hasAllowed && hasProhibited) const SizedBox(height: 8),
            if (hasProhibited)
              _RulesTextBlock(
                icon: Icons.cancel_outlined,
                title: 'Запрещено',
                text: tariff.prohibitedItems!.trim(),
                color: const Color(0xFFE53935),
              ),
          ],
        ],
      ),
    );
  }

  static double _mainPrice(UserDeliveryTariff tariff) {
    final prices = <double>[
      if (tariff.baseCost > 0) tariff.baseCost,
      ...tariff.weightTiers
          .map((tier) => tier.pricePerKg)
          .where((price) => price > 0),
    ];
    if (prices.isEmpty) return tariff.baseCost;
    return prices.reduce((a, b) => a < b ? a : b);
  }
}

class _MainPriceBadge extends StatelessWidget {
  final double? pricePerKg;
  final double? pricePerM3;
  final bool showFrom;

  const _MainPriceBadge({
    this.pricePerKg,
    this.pricePerM3,
    this.showFrom = false,
  });

  @override
  Widget build(BuildContext context) {
    final rates = [
      if (pricePerKg != null)
        (pricePerKg!, tr(context, ru: 'за кг', zh: '每千克')),
      if (pricePerM3 != null)
        (pricePerM3!, tr(context, ru: 'за м³', zh: '每立方米')),
    ];
    return Container(
      constraints: const BoxConstraints(minWidth: 86),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: context.brandGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: context.brandPrimary.withValues(alpha: 0.18),
            blurRadius: 18,
            spreadRadius: -10,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (rates.isEmpty)
            Text(
              tr(context, ru: 'Цена не указана', zh: '价格未设置'),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          for (var i = 0; i < rates.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Text(
              showFrom
                  ? tr(
                      context,
                      ru: 'от \$${_fmt(rates[i].$1)}',
                      zh: '\$${_fmt(rates[i].$1)}起',
                    )
                  : '\$${_fmt(rates[i].$1)}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Gilroy',
                fontSize: 22,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              rates[i].$2,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xE6FFFFFF),
                fontFamily: 'Gilroy',
                fontSize: 11.5,
                height: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SmallPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _SmallPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontFamily: 'Gilroy',
                fontSize: 11.5,
                height: 1,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeightTiersBlock extends StatelessWidget {
  final List<UserWeightTier> tiers;

  const _WeightTiersBlock({required this.tiers});

  @override
  Widget build(BuildContext context) {
    final weightUnit = tr(context, ru: 'кг', zh: 'kg');
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.scale_rounded, color: context.brandPrimary, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  tr(context, ru: 'Весовые диапазоны', zh: '重量区间'),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 14,
                    height: 17 / 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < tiers.length; i++) ...[
            _ValueRow(
              label: tiers[i].maxWeight != null
                  ? '${_fmt(tiers[i].minWeight)} – ${_fmt(tiers[i].maxWeight!)} $weightUnit'
                  : tr(
                      context,
                      ru: 'от ${_fmt(tiers[i].minWeight)} $weightUnit',
                      zh: '${_fmt(tiers[i].minWeight)} $weightUnit 起',
                    ),
              value: '\$${_fmt(tiers[i].pricePerKg)} / $weightUnit',
            ),
            if (i != tiers.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _DensityTiersBlock extends StatelessWidget {
  final List<UserDensityTier> tiers;

  const _DensityTiersBlock({required this.tiers});

  @override
  Widget build(BuildContext context) {
    final densityUnit = tr(context, ru: 'кг/м³', zh: 'kg/m³');
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.scale_rounded, color: context.brandPrimary, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  tr(context, ru: 'Диапазоны плотности', zh: '密度区间'),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 14,
                    height: 17 / 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (tiers.isEmpty)
            Text(tr(context, ru: 'Диапазоны не настроены', zh: '未设置密度区间')),
          for (var i = 0; i < tiers.length; i++) ...[
            _ValueRow(
              label: tiers[i].maxDensity != null
                  ? '${_fmt(tiers[i].minDensity)} – ${_fmt(tiers[i].maxDensity!)} $densityUnit'
                  : tr(
                      context,
                      ru: 'от ${_fmt(tiers[i].minDensity)} $densityUnit',
                      zh: '${_fmt(tiers[i].minDensity)} $densityUnit 起',
                    ),
              value: tiers[i].price == null
                  ? tr(context, ru: 'Цена не указана', zh: '价格未设置')
                  : '\$${_fmt(tiers[i].price!)} / ${tiers[i].isVolumetric ? tr(context, ru: 'м³', zh: 'm³') : tr(context, ru: 'кг', zh: 'kg')}',
            ),
            if (i != tiers.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _RulesTextBlock extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final Color color;

  const _RulesTextBlock({
    required this.icon,
    required this.title,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: TariffsUi.softDecoration(
        color: color.withValues(alpha: 0.06),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 7),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontFamily: 'Gilroy',
                  fontSize: 13,
                  height: 16 / 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Gilroy',
              fontSize: 13,
              height: 17 / 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PackagingCard extends StatelessWidget {
  final List<UserPackagingType> types;

  const _PackagingCard({required this.types});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: TariffsUi.cardDecoration(),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          for (var i = 0; i < types.length; i++) ...[
            _ServicePriceRow(
              icon: Icons.inventory_2_rounded,
              title: types[i].name,
              price: '\$${_fmt(types[i].baseCost)}',
            ),
            if (i < types.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _PhotoReportCard extends StatelessWidget {
  final PhotoReportOptions options;
  const _PhotoReportCard({required this.options});

  @override
  Widget build(BuildContext context) => Container(
    decoration: TariffsUi.cardDecoration(),
    padding: const EdgeInsets.all(12),
    child: Column(
      children: [
        if (!options.standard.enabled && !options.custom.enabled)
          Text(
            tr(context, ru: 'Фотоотчёты сейчас недоступны', zh: '目前无法申请拍照报告'),
          ),
        for (final type in ['standard', 'custom'])
          if (options.option(type).enabled)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ServicePriceRow(
                icon: Icons.photo_camera_rounded,
                title: type == 'standard'
                    ? tr(context, ru: 'Стандартный фотоотчёт', zh: '标准拍照报告')
                    : tr(context, ru: 'Проверка по заданию', zh: '按要求检查'),
                price: options.option(type).price == 0
                    ? tr(context, ru: 'Бесплатно', zh: '免费')
                    : '\$${options.option(type).price.toStringAsFixed(2)}',
              ),
            ),
      ],
    ),
  );
}

class _ServicePriceRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String price;

  const _ServicePriceRow({
    required this.icon,
    required this.title,
    required this.price,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: TariffsUi.softDecoration(),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: context.brandPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: context.brandPrimary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontFamily: 'Gilroy',
                fontSize: 14,
                height: 18 / 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                price,
                style: TextStyle(
                  color: context.brandPrimary,
                  fontFamily: 'Gilroy',
                  fontSize: 16,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  final String label;
  final String value;

  const _ValueRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Gilroy',
              fontSize: 13.5,
              height: 18 / 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: TextStyle(
            color: context.brandPrimary,
            fontFamily: 'Gilroy',
            fontSize: 13.5,
            height: 18 / 13.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _TariffInfoNote extends StatelessWidget {
  const _TariffInfoNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: TariffsUi.cardDecoration(
        color: context.brandPrimary.withValues(alpha: 0.06),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: context.brandPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.info_outline_rounded,
              color: context.brandPrimary,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Итоговая стоимость может отличаться: менеджер учитывает фактический вес, упаковку и дополнительные услуги.',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontFamily: 'Gilroy',
                fontSize: 13,
                height: 17 / 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _fmt(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
