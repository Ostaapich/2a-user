import 'package:twoalogisticcabineuser/src/core/media/authenticated_media.dart';
// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_toast.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_config.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/utils/locale_text.dart';
import '../../../core/ui/app_layout.dart';
import '../../../core/ui/tutorial_card.dart';
import '../../photos/domain/photo_item.dart';
import '../../photos/presentation/photo_viewer_screen.dart';
import '../data/sp_models.dart';
import '../data/sp_provider.dart';
import 'sp_finance_ui.dart';

/// Показывает стилизованный SnackBar в едином дизайне приложения
void _showStyledSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  AppToast.showFromSnackBar(
    context,
    SnackBar(
      content: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: AppToast.hide,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Gilroy',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError ? const Color(0xFFE53935) : context.brandPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        AppLayout.bottomBarObstruction(context) + 12,
      ),
      duration: const Duration(seconds: 3),
    ),
  );
}

class SpTrackEditScreen extends ConsumerStatefulWidget {
  final int trackId;
  final int assemblyId;

  const SpTrackEditScreen({
    super.key,
    required this.trackId,
    required this.assemblyId,
  });

  @override
  ConsumerState<SpTrackEditScreen> createState() => _SpTrackEditScreenState();
}

class _TrackEditHero extends StatelessWidget {
  final SpTrack track;
  final double? totalRub;
  final double? profit;

  const _TrackEditHero({
    required this.track,
    required this.totalRub,
    required this.profit,
  });

  @override
  Widget build(BuildContext context) {
    final participant = track.spParticipantName?.trim();
    return SpAnimatedHeroSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
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
                child: const Icon(
                  Icons.edit_note_rounded,
                  color: Colors.white,
                  size: 31,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.trackNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Gilroy',
                        fontSize: 22,
                        height: 1.04,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.25,
                      ),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'Заполните участника, цену, курс и чистый вес — расчёты обновятся автоматически.',
                      style: TextStyle(
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
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SpHeroChip(
                icon: Icons.person_rounded,
                label: participant != null && participant.isNotEmpty
                    ? participant
                    : 'Участник не задан',
              ),
              SpHeroChip(
                icon: Icons.receipt_long_rounded,
                label: totalRub != null
                    ? '${totalRub!.toStringAsFixed(0)} ₽ к оплате'
                    : 'Итог не рассчитан',
              ),
              SpHeroChip(
                icon: Icons.trending_up_rounded,
                label: profit != null
                    ? '${profit!.toStringAsFixed(0)} ₽ прибыль'
                    : 'Прибыль не рассчитана',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpTrackEditScreenState extends ConsumerState<SpTrackEditScreen> {
  late TextEditingController _participantController;
  late TextEditingController _supplierPriceController;
  late TextEditingController _purchasePriceController;
  late TextEditingController _purchaseRateController;
  late TextEditingController _clientPriceController;
  late TextEditingController _netWeightController;
  late TextEditingController _additionalExpensesController;
  late TextEditingController _noteController;

  SpTrack? _track;
  SpAssembly? _assembly;
  bool _isLoading = false;
  String? _missingTrackMessage;

  @override
  void initState() {
    super.initState();
    _participantController = TextEditingController();
    _supplierPriceController = TextEditingController();
    _purchasePriceController = TextEditingController();
    _purchaseRateController = TextEditingController();
    _clientPriceController = TextEditingController();
    _netWeightController = TextEditingController();
    _additionalExpensesController = TextEditingController();
    _noteController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(spAssembliesControllerProvider.notifier).loadAssemblies();
      }
    });
  }

  @override
  void dispose() {
    _participantController.dispose();
    _supplierPriceController.dispose();
    _purchasePriceController.dispose();
    _purchaseRateController.dispose();
    _clientPriceController.dispose();
    _netWeightController.dispose();
    _additionalExpensesController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _loadTrack() {
    final state = ref.read(spAssembliesControllerProvider);
    final assembly = _firstWhereOrNull<SpAssembly>(
      state.assemblies,
      (a) => a.id == widget.assemblyId,
    );
    if (assembly == null) {
      _missingTrackMessage = 'Сборка больше не найдена. Обновите список СП.';
      return;
    }

    final track = _firstWhereOrNull<SpTrack>(
      assembly.tracks,
      (t) => t.id == widget.trackId,
    );
    if (track == null) {
      _missingTrackMessage = 'Трек больше не найден. Обновите сборку.';
      return;
    }

    _missingTrackMessage = null;
    _track = track;
    _assembly = assembly;
    _participantController.text = track.spParticipantName ?? '';
    _supplierPriceController.text =
        track.supplierPriceYuan?.toStringAsFixed(2) ?? '';
    _purchasePriceController.text =
        track.purchasePriceYuan?.toStringAsFixed(2) ?? '';
    _purchaseRateController.text = track.purchaseRate?.toStringAsFixed(4) ?? '';
    _clientPriceController.text =
        track.clientPriceYuan?.toStringAsFixed(2) ?? '';
    _netWeightController.text = track.netWeightKg?.toStringAsFixed(3) ?? '';
    _additionalExpensesController.text =
        track.additionalExpensesRub?.toStringAsFixed(2) ?? '';
    _noteController.text = track.note ?? '';
  }

  /// Рассчитывает стоимость доставки для трека автоматически
  /// Формула: netWeight × (totalDeliveryCost / totalNetWeight)
  double? _calculateShippingCost() {
    if (_assembly == null) return null;

    // Текущий вес трека (из поля ввода)
    final currentNetWeight = double.tryParse(
      _netWeightController.text.replaceAll(',', '.'),
    );
    if (currentNetWeight == null || currentNetWeight <= 0) return null;

    // Проверяем, что у всех треков заполнен чистый вес
    bool allTracksHaveWeight = true;
    double totalNetWeight = 0;

    for (final track in _assembly!.tracks) {
      double? trackWeight;
      if (track.id == widget.trackId) {
        // Для текущего трека берём значение из поля ввода
        trackWeight = currentNetWeight;
      } else {
        trackWeight = track.netWeightKg;
      }

      if (trackWeight == null || trackWeight <= 0) {
        allTracksHaveWeight = false;
        break;
      }
      totalNetWeight += trackWeight;
    }

    if (!allTracksHaveWeight || totalNetWeight <= 0) return null;

    // Общая стоимость доставки сборки
    // Сначала берём totalShippingCostRub, если нет - считаем из счетов
    double totalDeliveryCost = _assembly!.totalShippingCostRub ?? 0;
    if (totalDeliveryCost == 0 && _assembly!.invoices.isNotEmpty) {
      for (final invoice in _assembly!.invoices) {
        totalDeliveryCost += invoice.deliveryCostRub;
      }
    }

    if (totalDeliveryCost <= 0) return null;

    // Стоимость за кг
    final costPerKg = totalDeliveryCost / totalNetWeight;

    // Стоимость доставки для данного трека
    return currentNetWeight * costPerKg;
  }

  // Цена поставщика (руб) = цена поставщика (юань) × курс
  double? _calculateSupplierPriceRub() {
    final supplierPriceYuan = double.tryParse(
      _supplierPriceController.text.replaceAll(',', '.'),
    );
    final rate = double.tryParse(
      _purchaseRateController.text.replaceAll(',', '.'),
    );

    if (supplierPriceYuan != null && rate != null) {
      return supplierPriceYuan * rate;
    }
    return null;
  }

  // Себестоимость = цена выкупа × курс
  double? _calculateCostPrice() {
    final purchasePrice = double.tryParse(
      _purchasePriceController.text.replaceAll(',', '.'),
    );
    final rate = double.tryParse(
      _purchaseRateController.text.replaceAll(',', '.'),
    );

    if (purchasePrice != null && rate != null) {
      return purchasePrice * rate;
    }
    return null;
  }

  // Цена для участника (руб) = цена участника (юань) × курс
  double? _calculateClientPriceRub() {
    final clientPriceYuan = double.tryParse(
      _clientPriceController.text.replaceAll(',', '.'),
    );
    final rate = double.tryParse(
      _purchaseRateController.text.replaceAll(',', '.'),
    );

    if (clientPriceYuan != null && rate != null) {
      return clientPriceYuan * rate;
    }
    return null;
  }

  // Итого к оплате = цена участника (руб) + доставка + дополнительные расходы
  double? _calculateTotalRub() {
    final clientPriceRub = _calculateClientPriceRub();
    // Используем авто-расчёт доставки если доступен
    final shippingCostRub =
        _calculateShippingCost() ?? _track?.shippingCostRub ?? 0;
    // Дополнительные расходы
    final additionalExpenses =
        double.tryParse(
          _additionalExpensesController.text.replaceAll(',', '.'),
        ) ??
        0;

    if (clientPriceRub != null) {
      return clientPriceRub + shippingCostRub + additionalExpenses;
    }
    return null;
  }

  // Получить текущую стоимость доставки (авто или сохранённую)
  double? _getShippingCost() {
    return _calculateShippingCost() ?? _track?.shippingCostRub;
  }

  // Прибыль = цена участника (руб) - себестоимость
  double? _calculateProfit() {
    final clientPriceRub = _calculateClientPriceRub();
    final costPrice = _calculateCostPrice();

    if (clientPriceRub != null && costPrice != null) {
      return clientPriceRub - costPrice;
    }
    return null;
  }

  Future<void> _saveTrack() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final update = SpTrackUpdate(
        spParticipantName: _participantController.text.isNotEmpty
            ? _participantController.text
            : null,
        supplierPriceYuan: double.tryParse(
          _supplierPriceController.text.replaceAll(',', '.'),
        ),
        purchasePriceYuan: double.tryParse(
          _purchasePriceController.text.replaceAll(',', '.'),
        ),
        purchaseRate: double.tryParse(
          _purchaseRateController.text.replaceAll(',', '.'),
        ),
        clientPriceYuan: double.tryParse(
          _clientPriceController.text.replaceAll(',', '.'),
        ),
        netWeightKg: double.tryParse(
          _netWeightController.text.replaceAll(',', '.'),
        ),
        additionalExpensesRub: double.tryParse(
          _additionalExpensesController.text.replaceAll(',', '.'),
        ),
        note: _noteController.text.isNotEmpty ? _noteController.text : null,
      );

      final success = await ref
          .read(spTrackEditControllerProvider.notifier)
          .updateTrack(widget.trackId, update);

      if (!mounted) return;

      if (success) {
        _showStyledSnackBar(context, 'Трек сохранён');
        context.pop();
      } else {
        final error = ref.read(spTrackEditControllerProvider).error;
        _showStyledSnackBar(
          context,
          error ?? 'Ошибка сохранения',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _openPhotoViewer(int index) {
    if (_track?.photos == null || _track!.photos!.isEmpty) return;

    // Конвертируем SpPhoto в PhotoItem
    final photoItems = _track!.photos!.map((photo) {
      return PhotoItem(
        id: photo.id,
        url: photo.url,
        date: photo.createdAt,
        trackingNumber: _track!.trackNumber,
      );
    }).toList();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PhotoViewerScreen(
          item: photoItems[index],
          allPhotos: photoItems,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final assembliesState = ref.watch(spAssembliesControllerProvider);
    if (_track == null && assembliesState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final topPad = AppLayout.topBarTotalHeight(context);
    final bottomPad = AppLayout.bottomScrollPadding(context);

    if (_track == null) {
      _loadTrack();
    }

    final supplierPriceRub = _calculateSupplierPriceRub();
    final costPrice = _calculateCostPrice();
    final clientPriceRub = _calculateClientPriceRub();
    final totalRub = _calculateTotalRub();
    final profit = _calculateProfit();

    return TutorialScreenWrapper(
      screenKey: 'sp_track_edit',
      steps: const [
        TutorialStep(
          icon: Icons.person_pin_rounded,
          title: 'Участник СП',
          description:
              'Укажите имя участника, которому принадлежит этот трек. Имя отображается в расчётах сборки.',
        ),
        TutorialStep(
          icon: Icons.currency_yuan_rounded,
          title: 'Цена и вес',
          description:
              'Введите стоимость товара в юанях и чистый вес. По этим данным считается доля в сборке.',
        ),
        TutorialStep(
          icon: Icons.save_rounded,
          title: 'Сохранить',
          description:
              'Нажмите «Сохранить» внизу страницы — данные обновятся в сборке для всех участников.',
        ),
      ],
      child: _track == null
          ? _buildMissingTrackState(context, topPad, bottomPad)
          : ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                topPad * 0.7 + 16,
                16,
                bottomPad + 16,
              ),
              children: [
                SpPageHeader(title: _track!.trackNumber),
                const SizedBox(height: 12),
                _TrackEditHero(
                  track: _track!,
                  totalRub: totalRub,
                  profit: profit,
                ),
                const SizedBox(height: 14),

                // 1. Имя участника
                Builder(
                  builder: (_) {
                    final w = _buildCard(
                      title: 'Участник СП',
                      child: TextField(
                        controller: _participantController,
                        style: SpFinanceUi.bodyStyle,
                        decoration: SpFinanceUi.inputDecoration(
                          context,
                          labelText: 'Имя участника',
                          hintText: 'Введите имя участника',
                          prefixIcon: Icons.person_rounded,
                        ),
                      ),
                    );
                    return w;
                  },
                ),
                const SizedBox(height: 15),

                // 2. Комментарий (всегда показываем, редактируемый)
                _buildCard(
                  title: 'Комментарий',
                  child: TextField(
                    controller: _noteController,
                    maxLines: 3,
                    style: SpFinanceUi.bodyStyle,
                    decoration: SpFinanceUi.inputDecoration(
                      context,
                      hintText: 'Введите комментарий к треку...',
                      prefixIcon: Icons.comment_rounded,
                    ),
                  ),
                ),
                const SizedBox(height: 15),

                // 3. О товаре
                if (_track!.productInfo != null) ...[
                  _buildProductInfoSection(),
                  const SizedBox(height: 15),
                ],

                // 4. Фото отчёт
                if (_track!.photos != null && _track!.photos!.isNotEmpty) ...[
                  _buildPhotoSection(),
                  const SizedBox(height: 15),
                ],

                // 4. Вес и доставка
                _buildWeightSection(),
                const SizedBox(height: 15),

                // 5-8. Цены в юанях и курс
                Builder(
                  builder: (_) {
                    final w = _buildCard(
                      title: 'Цены в юанях',
                      child: Column(
                        children: [
                          // 5. Цена поставщика
                          TextField(
                            controller: _supplierPriceController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: SpFinanceUi.bodyStyle,
                            decoration: SpFinanceUi.inputDecoration(
                              context,
                              labelText: 'Цена поставщика',
                              hintText: '0.00',
                              suffixText: '¥',
                              prefixIcon: Icons.store_rounded,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d+[.,]?\d{0,2}'),
                              ),
                            ],
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 16),

                          // 6. Цена выкупа
                          TextField(
                            controller: _purchasePriceController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: SpFinanceUi.bodyStyle,
                            decoration: SpFinanceUi.inputDecoration(
                              context,
                              labelText: 'Цена выкупа (со скидкой)',
                              hintText: '0.00',
                              suffixText: '¥',
                              prefixIcon: Icons.shopping_cart_rounded,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d+[.,]?\d{0,2}'),
                              ),
                            ],
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 16),

                          // 7. Цена участника
                          TextField(
                            controller: _clientPriceController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: SpFinanceUi.bodyStyle,
                            decoration: SpFinanceUi.inputDecoration(
                              context,
                              labelText: 'Цена для участника',
                              hintText: '0.00',
                              suffixText: '¥',
                              prefixIcon: Icons.account_balance_wallet_rounded,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d+[.,]?\d{0,2}'),
                              ),
                            ],
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 16),

                          // 8. Курс юаня
                          TextField(
                            controller: _purchaseRateController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: SpFinanceUi.bodyStyle,
                            decoration: SpFinanceUi.inputDecoration(
                              context,
                              labelText: 'Курс юаня (¥→₽)',
                              hintText: '0.0000',
                              prefixIcon: Icons.currency_exchange_rounded,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d+[.,]?\d{0,4}'),
                              ),
                            ],
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    );
                    return w;
                  },
                ),
                const SizedBox(height: 15),

                // 9-14. Расчётные цены в рублях
                Builder(
                  builder: (_) {
                    final w = _buildCard(
                      title: 'Расчёт в рублях',
                      child: Column(
                        children: [
                          // 9. Цена поставщика (руб)
                          _buildCalculatedRow(
                            icon: Icons.store_rounded,
                            label: 'Цена поставщика',
                            value: supplierPriceRub,
                            color: Colors.grey,
                          ),

                          // 10. Цена выкупа / Себестоимость (руб)
                          _buildCalculatedRow(
                            icon: Icons.shopping_cart_rounded,
                            label: 'Себестоимость (цена выкупа)',
                            value: costPrice,
                            color: Colors.orange,
                          ),

                          // 11. Цена для участника (руб)
                          _buildCalculatedRow(
                            icon: Icons.account_balance_wallet_rounded,
                            label: 'Цена для участника',
                            value: clientPriceRub,
                            color: Colors.blue,
                          ),

                          // 12. Стоимость доставки (руб)
                          _buildCalculatedRow(
                            icon: Icons.local_shipping_rounded,
                            label: 'Стоимость доставки',
                            value: _getShippingCost(),
                            color: Colors.purple,
                          ),

                          // 12a. Дополнительные расходы (руб)
                          _buildCalculatedRow(
                            icon: Icons.add_shopping_cart_rounded,
                            label: 'Дополнительные расходы',
                            value: double.tryParse(
                              _additionalExpensesController.text.replaceAll(
                                ',',
                                '.',
                              ),
                            ),
                            color: Colors.deepOrange,
                          ),

                          // 13. Итого к оплате (руб)
                          _buildCalculatedRow(
                            icon: Icons.receipt_long_rounded,
                            label: 'Итого к оплате',
                            value: totalRub,
                            color: Colors.teal,
                            isHighlighted: true,
                          ),

                          // 14. Прибыль (руб)
                          _buildCalculatedRow(
                            icon: profit != null && profit > 0
                                ? Icons.trending_up_rounded
                                : Icons.trending_down_rounded,
                            label: 'Прибыль',
                            value: profit,
                            color: profit != null && profit > 0
                                ? Colors.green
                                : Colors.red,
                            isHighlighted: true,
                            isLast: true,
                          ),
                        ],
                      ),
                    );
                    return w;
                  },
                ),
                const SizedBox(height: 15),

                // Кнопка сохранения
                Builder(
                  builder: (_) {
                    final w = SizedBox(
                      height: 54,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: _isLoading ? null : context.brandGradient,
                          color: _isLoading
                              ? context.brandPrimary.withValues(alpha: 0.55)
                              : null,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: _isLoading
                              ? null
                              : [
                                  BoxShadow(
                                    color: context.brandPrimary.withValues(
                                      alpha: 0.18,
                                    ),
                                    blurRadius: 18,
                                    spreadRadius: -10,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                        ),
                        child: FilledButton.icon(
                          onPressed: _isLoading ? null : _saveTrack,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_rounded),
                          label: Text(
                            _isLoading ? 'Сохранение...' : 'Сохранить',
                            style: const TextStyle(
                              fontFamily: 'Gilroy',
                              fontSize: 16,
                              height: 18 / 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            disabledBackgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.white,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                      ),
                    );
                    return w;
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }

  T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T item) test) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }

  Widget _buildMissingTrackState(
    BuildContext context,
    double topPad,
    double bottomPad,
  ) {
    final message =
        _missingTrackMessage ??
        'Данные трека загружаются. Если экран не обновится, вернитесь назад и откройте сборку снова.';
    return ListView(
      padding: EdgeInsets.fromLTRB(16, topPad * 0.7 + 16, 16, bottomPad + 16),
      children: [
        const SpPageHeader(title: 'Трек не найден'),
        const SizedBox(height: 24),
        _buildCard(
          title: 'Нет актуальных данных',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: SpFinanceUi.bodyStyle),
              OutlinedButton.icon(
                onPressed: () => ref
                    .read(spAssembliesControllerProvider.notifier)
                    .loadAssemblies(),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(tr(context, ru: 'Повторить загрузку', zh: '重新加载')),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.pop(),
                  child: const Text('Вернуться к сборке'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCard({required String title, required Widget child}) {
    return Container(
      decoration: SpFinanceUi.cardDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: SpFinanceUi.sectionTitleStyle),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildWeightSection() {
    final netWeight = double.tryParse(
      _netWeightController.text.replaceAll(',', '.'),
    );

    // Сначала пробуем рассчитать автоматически, если не получается - берём сохранённое значение
    final calculatedShipping = _calculateShippingCost();
    final shippingCost = calculatedShipping ?? _track?.shippingCostRub;
    final isAutoCalculated = calculatedShipping != null;

    // Расчёт стоимости за кг (если есть доставка и вес)
    double? costPerKg;
    if (shippingCost != null &&
        shippingCost > 0 &&
        netWeight != null &&
        netWeight > 0) {
      costPerKg = shippingCost / netWeight;
    }

    // Проверяем, у скольких треков не заполнен вес
    int tracksWithoutWeight = 0;
    if (_assembly != null && calculatedShipping == null) {
      for (final track in _assembly!.tracks) {
        final trackWeight = track.id == widget.trackId
            ? netWeight
            : track.netWeightKg;
        if (trackWeight == null || trackWeight <= 0) {
          tracksWithoutWeight++;
        }
      }
    }

    return Container(
      decoration: SpFinanceUi.cardDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Вес и доставка', style: SpFinanceUi.sectionTitleStyle),
            const SizedBox(height: 12),

            // Чистый вес (редактируемое поле)
            TextField(
              controller: _netWeightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: SpFinanceUi.bodyStyle,
              decoration: SpFinanceUi.inputDecoration(
                context,
                labelText: 'Чистый вес (кг)',
                hintText: '0.000',
                suffixText: 'кг',
                prefixIcon: Icons.scale_rounded,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+[.,]?\d{0,3}')),
              ],
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            // Дополнительные расходы (редактируемое поле)
            TextField(
              controller: _additionalExpensesController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: SpFinanceUi.bodyStyle,
              decoration: SpFinanceUi.inputDecoration(
                context,
                labelText: 'Дополнительные расходы',
                hintText: '0.00',
                suffixText: '₽',
                prefixIcon: Icons.add_shopping_cart_rounded,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+[.,]?\d{0,2}')),
              ],
              onChanged: (_) => setState(() {}),
            ),

            // Стоимость доставки (если рассчитана)
            if (shippingCost != null && shippingCost > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.local_shipping_rounded,
                          color: Colors.purple.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Стоимость доставки',
                                style: SpFinanceUi.bodyStyle.copyWith(
                                  color: Colors.purple.shade700,
                                ),
                              ),
                              if (isAutoCalculated)
                                Text(
                                  'рассчитано автоматически',
                                  style: SpFinanceUi.labelStyle.copyWith(
                                    color: Colors.purple.shade400,
                                    fontSize: 10,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          '${shippingCost.toStringAsFixed(2)} ₽',
                          style: TextStyle(
                            fontFamily: 'Gilroy',
                            fontSize: 16,
                            height: 19 / 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.purple.shade700,
                          ),
                        ),
                      ],
                    ),
                    if (costPerKg != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.price_change_rounded,
                            color: Colors.purple.shade400,
                            size: 18,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Цена за кг',
                              style: SpFinanceUi.labelStyle.copyWith(
                                color: Colors.purple.shade600,
                              ),
                            ),
                          ),
                          Text(
                            '${costPerKg.toStringAsFixed(2)} ₽/кг',
                            style: SpFinanceUi.bodyStyle.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.purple.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],

            // Подсказка если доставка не рассчитана
            if (shippingCost == null || shippingCost == 0) ...[
              const SizedBox(height: 12),
              if (tracksWithoutWeight > 0)
                Text(
                  'Для расчёта доставки заполните вес у всех треков (осталось: $tracksWithoutWeight)',
                  style: SpFinanceUi.labelStyle.copyWith(
                    color: Colors.orange.shade700,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                Text(
                  'Укажите чистый вес для расчёта стоимости доставки',
                  style: SpFinanceUi.labelStyle.copyWith(
                    color: SpFinanceUi.mutedTextColor,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoSection() {
    return Container(
      decoration: SpFinanceUi.cardDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Фото отчёт', style: SpFinanceUi.sectionTitleStyle),
                Text(
                  '${_track!.photos!.length} фото',
                  style: SpFinanceUi.labelStyle,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _track!.photos!.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final photo = _track!.photos![index];
                  final fullUrl = ApiConfig.getMediaUrl(
                    photo.thumbnailUrl ?? photo.url,
                  );
                  return GestureDetector(
                    onTap: () => _openPhotoViewer(index),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AuthenticatedCachedImage(
                            imageUrl: fullUrl,
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              width: 120,
                              height: 120,
                              color: Colors.grey.shade200,
                              child: const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              width: 120,
                              height: 120,
                              color: Colors.grey.shade200,
                              child: const Icon(Icons.image_not_supported),
                            ),
                          ),
                        ),
                        // Иконка для открытия просмотра
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.open_in_full_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Нажмите на фото для просмотра, скачивания или отправки',
              style: SpFinanceUi.labelStyle.copyWith(
                color: SpFinanceUi.mutedTextColor,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductInfoSection() {
    final productInfo = _track!.productInfo!;
    final hasImage =
        productInfo.imageUrl != null && productInfo.imageUrl!.isNotEmpty;

    return Container(
      decoration: SpFinanceUi.cardDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('О товаре', style: SpFinanceUi.sectionTitleStyle),
            const SizedBox(height: 12),

            // Название товара
            if (productInfo.title != null && productInfo.title!.isNotEmpty)
              _buildInfoRow(
                icon: Icons.label_rounded,
                label: 'Название',
                value: productInfo.title!,
              ),

            // Количество
            _buildInfoRow(
              icon: Icons.numbers_rounded,
              label: 'Количество',
              value: '${productInfo.quantity} шт.',
            ),

            // Фото товара
            if (hasImage) ...[
              const SizedBox(height: 12),
              Text(
                'Фото товара',
                style: SpFinanceUi.labelStyle.copyWith(
                  color: SpFinanceUi.mutedTextColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _openProductPhotoViewer(),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AuthenticatedCachedImage(
                        imageUrl: ApiConfig.getMediaUrl(productInfo.imageUrl!),
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          width: 120,
                          height: 120,
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: 120,
                          height: 120,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.image_not_supported),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.open_in_full_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Нажмите на фото для просмотра, скачивания или отправки',
                style: SpFinanceUi.labelStyle.copyWith(
                  color: SpFinanceUi.mutedTextColor,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: SpFinanceUi.bodyStyle.copyWith(
              color: SpFinanceUi.mutedTextColor,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: SpFinanceUi.bodyStyle.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openProductPhotoViewer() {
    if (_track?.productInfo?.imageUrl == null) return;

    final photoItem = PhotoItem(
      url: _track!.productInfo!.imageUrl!,
      date: DateTime.now(),
      trackingNumber: _track!.trackNumber,
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PhotoViewerScreen(item: photoItem),
      ),
    );
  }

  Widget _buildCalculatedRow({
    required IconData icon,
    required String label,
    required double? value,
    required Color color,
    bool isHighlighted = false,
    bool isLast = false,
  }) {
    if (value == null) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isHighlighted
                ? color.withValues(alpha: 0.1)
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: isHighlighted
                ? Border.all(color: color.withValues(alpha: 0.3))
                : null,
          ),
          child: Row(
            children: [
              Icon(icon, color: color.withValues(alpha: 0.8), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: SpFinanceUi.bodyStyle.copyWith(
                    color: SpFinanceUi.textColor,
                  ),
                ),
              ),
              Text(
                '${value.toStringAsFixed(2)} ₽',
                style: TextStyle(
                  fontFamily: 'Gilroy',
                  fontSize: 16,
                  height: 19 / 16,
                  fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w600,
                  color: isHighlighted ? color : SpFinanceUi.textColor,
                ),
              ),
            ],
          ),
        ),
        if (!isLast) const SizedBox(height: 8),
      ],
    );
  }
}
