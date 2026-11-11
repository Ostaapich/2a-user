import 'package:twoalogisticcabineuser/src/core/media/authenticated_media.dart';
import 'package:flutter/material.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/ui/app_input_decoration.dart';
import '../../../core/ui/tutorial_card.dart';
import '../../../core/ui/app_layout.dart';
import '../data/purchase_provider.dart';
import '../domain/purchase_list.dart';

class PurchaseListScreen extends ConsumerStatefulWidget {
  const PurchaseListScreen({super.key});

  @override
  ConsumerState<PurchaseListScreen> createState() => _PurchaseListScreenState();
}

class _PurchaseListScreenState extends ConsumerState<PurchaseListScreen> {
  final _noteController = TextEditingController();
  bool _isSubmitting = false;
  final _updatingItems = <int>{};

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(activePurchaseListProvider);
    final topPad = AppLayout.topBarTotalHeight(context);
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return listAsync.when(
      data: (list) {
        if (list == null || list.items.isEmpty) {
          return _buildEmpty(context, topPad);
        }
        return TutorialScreenWrapper(
          screenKey: 'purchase_list',
          steps: const [
            TutorialStep(
              icon: Icons.shopping_bag_rounded,
              title: 'Список выкупа',
              description:
                  'Здесь товары, которые вы добавили из каталога. Перед отправкой можно изменить количество или удалить позиции.',
            ),
            TutorialStep(
              icon: Icons.add_circle_outline_rounded,
              title: 'Изменить количество',
              description:
                  'Кнопки «−» и «+» рядом с товаром меняют количество. Кнопка корзины (×) удаляет товар из списка.',
            ),
            TutorialStep(
              icon: Icons.send_rounded,
              title: 'Отправить на сборку',
              description:
                  'Кнопка «Отправить на сборку» внизу экрана отправляет весь список менеджеру для оформления и выкупа.',
            ),
          ],
          child: Column(
            children: [
              Expanded(child: _buildContent(context, list, topPad)),
              _buildSubmitBar(context, list, bottomPad),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Ошибка загрузки',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => ref.invalidate(activePurchaseListProvider),
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, double topPad) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, topPad * 0.7 + 16, 16, 100),
      children: [
        Text(
          'Список выкупа',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 60),
        Center(
          child: Column(
            children: [
              Icon(
                Icons.shopping_cart_outlined,
                size: 64,
                color: Colors.grey.shade300,
              ),
              const SizedBox(height: 16),
              Text(
                'Список пуст',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Добавьте товары из каталога',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.search, size: 20),
                label: const Text('Перейти в каталог'),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, PurchaseList list, double topPad) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, topPad * 0.7 + 16, 16, 16),
      children: [
        Text(
          'Список выкупа',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          '${list.totalItems} товаров',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 16),

        // Items
        ...list.items.map(
          (item) => _PurchaseItemCard(
            item: item,
            listId: list.id,
            onQuantityChanged: (newQty) =>
                _updateQuantity(list.id, item.id, newQty),
            isUpdating: _updatingItems.contains(item.id),
            onDelete: () => _deleteItem(list.id, item.id),
            onTap: () => context.push(
              Uri(
                path: '/shop/item/${item.externalItemId}',
                queryParameters: {'provider': item.provider},
              ).toString(),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Note field
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Комментарий к заявке',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _noteController,
                maxLines: 3,
                decoration: appInputDecoration(
                  context,
                  hintText: 'Пожелания, уточнения...',
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  radius: 12,
                  fillColor: Colors.white,
                  borderColor: Colors.grey.shade300,
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitBar(
    BuildContext context,
    PurchaseList list,
    double bottomPad,
  ) {
    // Total price
    double totalPrice = 0;
    for (final item in list.items) {
      totalPrice += item.price * item.quantity;
    }

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomPad),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '¥${totalPrice.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: context.brandPrimary,
                  ),
                ),
                Text(
                  '${list.totalItems} товаров',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _isSubmitting || _updatingItems.isNotEmpty
                ? null
                : () => _submitList(list.id),
            icon: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded, size: 20),
            label: Text(
              _isSubmitting ? 'Отправляем...' : 'Отправить менеджеру',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateQuantity(int listId, int itemId, int newQty) async {
    if (newQty < 1 || _isSubmitting || _updatingItems.contains(itemId)) return;
    setState(() => _updatingItems.add(itemId));
    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.patch(
        '/shop/purchase-lists/$listId/items/$itemId',
        data: {'quantity': newQty},
      );
      if (!mounted) return;
      ref.invalidate(activePurchaseListProvider);
    } catch (e) {
      if (mounted) {
        AppToast.showFromSnackBar(
          context,
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingItems.remove(itemId));
    }
  }

  Future<void> _deleteItem(int listId, int itemId) async {
    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.delete('/shop/purchase-lists/$listId/items/$itemId');
      ref.invalidate(activePurchaseListProvider);
    } catch (e) {
      if (mounted) {
        AppToast.showFromSnackBar(
          context,
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _submitList(int listId) async {
    if (_isSubmitting || _updatingItems.isNotEmpty) return;
    setState(() => _isSubmitting = true);
    try {
      final apiClient = ref.read(apiClientProvider);

      // Update note if filled
      final note = _noteController.text.trim();
      await apiClient.post(
        '/shop/purchase-lists/$listId/submit',
        data: note.isNotEmpty ? {'note': note} : {},
      );

      ref.invalidate(activePurchaseListProvider);
      ref.invalidate(purchaseListsProvider);

      if (mounted) {
        AppToast.showFromSnackBar(
          context,
          SnackBar(
            content: const Text('Заявка отправлена менеджеру!'),
            backgroundColor: context.brandPrimary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        AppToast.showFromSnackBar(
          context,
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}

class _PurchaseItemCard extends StatelessWidget {
  final PurchaseItem item;
  final int listId;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onDelete;
  final VoidCallback onTap;
  final bool isUpdating;

  const _PurchaseItemCard({
    required this.item,
    required this.listId,
    required this.onQuantityChanged,
    required this.onDelete,
    required this.onTap,
    this.isUpdating = false,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(item.id),
      direction: isUpdating
          ? DismissDirection.none
          : DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                      ? AuthenticatedCachedImage(
                          imageUrl: item.imageUrl!,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(
                            width: 72,
                            height: 72,
                            color: Colors.grey.shade100,
                          ),
                          errorWidget: (_, _, _) => Container(
                            width: 72,
                            height: 72,
                            color: Colors.grey.shade100,
                            child: const Icon(Icons.image_outlined),
                          ),
                        )
                      : Container(
                          width: 72,
                          height: 72,
                          color: Colors.grey.shade100,
                          child: Icon(
                            Icons.image_outlined,
                            color: Colors.grey.shade300,
                          ),
                        ),
                ),
                const SizedBox(width: 12),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (item.skuPropertiesDisplay.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.skuPropertiesDisplay,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            item.priceDisplay,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: context.brandPrimary,
                            ),
                          ),
                          const Spacer(),
                          // Quantity controls
                          _QuantityControls(
                            quantity: item.quantity,
                            onChanged: isUpdating ? null : onQuantityChanged,
                            isUpdating: isUpdating,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuantityControls extends StatelessWidget {
  final int quantity;
  final ValueChanged<int>? onChanged;
  final bool isUpdating;

  const _QuantityControls({
    required this.quantity,
    required this.onChanged,
    this.isUpdating = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: quantity > 1 && onChanged != null
              ? () => onChanged!(quantity - 1)
              : () {},
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: quantity > 1 ? Colors.grey.shade200 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.remove,
              size: 16,
              color: quantity > 1
                  ? AppColors.textPrimary
                  : Colors.grey.shade400,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: isUpdating
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  '$quantity',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
        ),
        GestureDetector(
          onTap: onChanged == null ? () {} : () => onChanged!(quantity + 1),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.add,
              size: 16,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
