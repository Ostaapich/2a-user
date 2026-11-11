import '../../../core/utils/commerce_text.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';
import 'package:twoalogisticcabineuser/src/core/ui/blurred_modal_bottom_sheet.dart';

import '../../../core/ui/app_colors.dart';
import '../../../core/branding/company_branding_provider.dart';
import '../../../core/utils/locale_text.dart';
import '../../../core/ui/app_input_decoration.dart';
import '../../../core/ui/tutorial_card.dart';
import '../../shell/presentation/app_shell.dart';
import '../data/purchase_provider.dart';
import '../data/shop_availability_provider.dart';
import '../data/shop_provider.dart';
import '../domain/marketplace.dart';
import '../domain/shop_category.dart';
import 'shop_search_results.dart';
import 'widgets/marketplace_selector.dart';
import 'widgets/shop_search_bar.dart';

/// Сортировки каталога. Маппинг на официальный API задаёт backend-адаптер.
const _sortOptions = <(String, String)>[
  ('Default', 'По умолчанию'),
  ('TotalSales:Desc', 'По продажам'),
  ('Price:Asc', 'Цена ↑'),
  ('Price:Desc', 'Цена ↓'),
  ('Volume:Desc', 'По популярности'),
];

const _jdSortOptions = <(String, String)>[
  ('Default', 'По умолчанию'),
  ('Modified:Desc', 'Недавно обновлённые'),
  ('Modified:Asc', 'Сначала старые'),
];

class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key});

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  String _searchQuery = '';
  String? _searchCategoryId;
  String? _searchCategoryName;
  String _orderBy = 'Default';
  double? _minPrice;
  double? _maxPrice;

  void _onSearch(String query) {
    setState(() {
      _searchQuery = query;
      _searchCategoryId = null;
      _searchCategoryName = null;
    });
  }

  void _onMarketplaceChanged(Marketplace marketplace) {
    ref.read(selectedMarketplaceProvider.notifier).select(marketplace);
    setState(() {
      _searchQuery = '';
      _searchCategoryId = null;
      _searchCategoryName = null;
      _orderBy = 'Default';
      _minPrice = null;
      _maxPrice = null;
    });
  }

  void _onCategorySearch(ShopCategory category) {
    setState(() {
      _searchQuery = '';
      _searchCategoryId = category.id;
      _searchCategoryName = category.name;
    });
  }

  void _clearCategorySearch() {
    setState(() {
      _searchCategoryId = null;
      _searchCategoryName = null;
    });
  }

  void _showFiltersSheet() {
    final minCtrl = TextEditingController(
      text: _minPrice != null ? _minPrice!.toStringAsFixed(0) : '',
    );
    final maxCtrl = TextEditingController(
      text: _maxPrice != null ? _maxPrice!.toStringAsFixed(0) : '',
    );

    ref.read(bottomNavVisibleProvider.notifier).hide();

    showBlurredModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                commerceText(context, 'Фильтр по цене (¥)'),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: minCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+[.,]?\d*'),
                        ),
                      ],
                      decoration: appInputDecoration(
                        context,
                        labelText: commerceText(context, 'От'),
                        radius: 12,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: maxCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+[.,]?\d*'),
                        ),
                      ],
                      decoration: appInputDecoration(
                        context,
                        labelText: commerceText(context, 'До'),
                        radius: 12,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _minPrice = null;
                          _maxPrice = null;
                        });
                        Navigator.pop(ctx);
                      },
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(commerceText(context, 'Сбросить')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        setState(() {
                          final minVal = double.tryParse(
                            minCtrl.text.replaceAll(',', '.'),
                          );
                          final maxVal = double.tryParse(
                            maxCtrl.text.replaceAll(',', '.'),
                          );
                          _minPrice = minVal;
                          _maxPrice = maxVal;
                        });
                        Navigator.pop(ctx);
                      },
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(commerceText(context, 'Применить')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ).whenComplete(() {
      ref.read(bottomNavVisibleProvider.notifier).show();
    });
  }

  @override
  Widget build(BuildContext context) {
    final companyName = ref.watch(companyNameProvider);
    final availability = ref.watch(shopAvailabilityProvider).asData?.value;
    final availableMarketplaces = Marketplace.values
        .where(
          (marketplace) => availability?.canBrowse(marketplace.apiKey) == true,
        )
        .toList(growable: false);
    final selectedMarketplace = ref.watch(selectedMarketplaceProvider);
    final marketplace = availableMarketplaces.contains(selectedMarketplace)
        ? selectedMarketplace
        : availableMarketplaces.isNotEmpty
        ? availableMarketplaces.first
        : Marketplace.alibaba1688;
    final sortOptions = marketplace == Marketplace.jd
        ? _jdSortOptions
        : _sortOptions;
    final effectiveOrderBy = sortOptions.any((option) => option.$1 == _orderBy)
        ? _orderBy
        : 'Default';

    final showSearchResults =
        _searchQuery.isNotEmpty || _searchCategoryId != null;

    final cartCount = ref.watch(cartItemCountProvider);

    return TutorialScreenWrapper(
      screenKey: 'marketplaces',
      steps: [
        TutorialStep(
          icon: Icons.store_rounded,
          title: commerceText(context, 'Каталоги маркетплейсов'),
          description: commerceText(
            context,
            'Выберите доступную площадку, найдите товар и подготовьте список для выкупа.',
          ),
        ),
        TutorialStep(
          icon: Icons.search_rounded,
          title: commerceText(context, 'Поиск товара'),
          description: commerceText(
            context,
            'Введите название товара или вставьте ссылку с площадки в строку поиска — мы найдём и покажем карточку.',
          ),
        ),
        TutorialStep(
          icon: Icons.category_rounded,
          title: commerceText(context, 'Категории'),
          description: commerceText(
            context,
            'Выберите категорию, чтобы просматривать товары по разделам. Нажмите на товар для перехода к деталям.',
          ),
        ),
        TutorialStep(
          icon: Icons.filter_alt_rounded,
          title: commerceText(context, 'Фильтр по цене'),
          description: commerceText(
            context,
            'Нажмите иконку фильтра (воронка) рядом со строкой поиска, чтобы задать диапазон цен в юанях.',
          ),
        ),
        TutorialStep(
          icon: Icons.shopping_cart_rounded,
          title: commerceText(context, 'Список выкупа'),
          description: commerceText(
            context,
            'Иконка корзины вверху открывает ваш текущий список выкупа. Там собраны все товары перед отправкой заявки.',
          ),
        ),
      ],
      child: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 70),

              if (availableMarketplaces.isNotEmpty) ...[
                MarketplaceSelector(
                  marketplaces: availableMarketplaces,
                  selected: marketplace,
                  onChanged: _onMarketplaceChanged,
                ),
                const SizedBox(height: 8),
              ],

              // Search bar
              ShopSearchBar(
                onSearch: _onSearch,
                initialQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
              ),
              const SizedBox(height: 8),

              // Sort + Filter row (only when results are shown)
              if (showSearchResults)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      // Sort dropdown
                      Expanded(
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: effectiveOrderBy,
                              isExpanded: true,
                              icon: Icon(
                                Icons.sort,
                                size: 20,
                                color: Colors.grey.shade600,
                              ),
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade800,
                              ),
                              items: sortOptions
                                  .map(
                                    (opt) => DropdownMenuItem(
                                      value: opt.$1,
                                      child: Text(
                                        commerceText(context, opt.$2),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _orderBy = value);
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                      if (marketplace != Marketplace.jd) ...[
                        const SizedBox(width: 8),
                        // Cloud Trade getSkuList does not support a price
                        // predicate. Do not emulate it on a loaded page.
                        GestureDetector(
                          onTap: _showFiltersSheet,
                          child: Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: (_minPrice != null || _maxPrice != null)
                                  ? context.brandPrimary.withValues(alpha: 0.1)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(10),
                              border: (_minPrice != null || _maxPrice != null)
                                  ? Border.all(
                                      color: context.brandPrimary,
                                      width: 1,
                                    )
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.tune,
                                  size: 20,
                                  color:
                                      (_minPrice != null || _maxPrice != null)
                                      ? context.brandPrimary
                                      : Colors.grey.shade600,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _buildFilterLabel(),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color:
                                        (_minPrice != null || _maxPrice != null)
                                        ? context.brandPrimary
                                        : Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              if (showSearchResults) const SizedBox(height: 8),

              // Category filter chip
              if (_searchCategoryId != null)
                Padding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 8,
                  ),
                  child: Row(
                    children: [
                      Flexible(
                        child: Chip(
                          label: Text(
                            _searchCategoryName ??
                                commerceText(context, 'Категория'),
                            style: TextStyle(
                              fontSize: 13,
                              color: context.brandPrimary,
                            ),
                          ),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: _clearCategorySearch,
                          backgroundColor: context.brandPrimary.withValues(
                            alpha: 0.1,
                          ),
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Content
              Expanded(
                child: showSearchResults
                    ? ShopSearchResults(
                        params: ShopSearchParams(
                          query: _searchQuery,
                          marketplace: marketplace,
                          categoryId: _searchCategoryId,
                          orderBy: effectiveOrderBy,
                          minPrice: _minPrice,
                          maxPrice: _maxPrice,
                        ),
                      )
                    : marketplace == Marketplace.jd
                    ? _MarketplaceSearchHint(
                        title: commerceText(context, 'Каталог JD'),
                        description: tr(
                          context,
                          ru: tr(
                            context,
                            ru: 'Введите название товара. Каталог JD загружается из товарного канала, выданного компании $companyName.',
                            zh: '请输入商品名称。京东目录来自为$companyName提供的商品渠道。',
                          ),
                          zh: '请输入商品名称。JD 目录来自为 $companyName 提供的商品渠道。',
                        ),
                      )
                    : _CategoriesView(
                        marketplace: marketplace,
                        onCategorySearch: _onCategorySearch,
                      ),
              ),
            ],
          ),

          // Floating history button
          Positioned(
            right: 16,
            bottom: cartCount > 0 ? 181 : 115,
            child: GestureDetector(
              onTap: () => context.push('/shop/purchases'),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  color: context.brandPrimary,
                  size: 22,
                ),
              ),
            ),
          ),

          // Floating cart button
          if (cartCount > 0)
            Positioned(
              right: 16,
              bottom: 115,
              child: GestureDetector(
                onTap: () => context.push('/shop/cart'),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [context.brandPrimary, context.brandSecondary],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: context.brandPrimary.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(
                        Icons.shopping_cart_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          child: Text(
                            '$cartCount',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _buildFilterLabel() {
    if (_minPrice != null && _maxPrice != null) {
      return '¥${_minPrice!.toStringAsFixed(0)}–${_maxPrice!.toStringAsFixed(0)}';
    }
    if (_minPrice != null) {
      return tr(
        context,
        ru: 'от ¥${_minPrice!.toStringAsFixed(0)}',
        zh: '最低 ¥${_minPrice!.toStringAsFixed(0)}',
      );
    }
    if (_maxPrice != null) {
      return tr(
        context,
        ru: 'до ¥${_maxPrice!.toStringAsFixed(0)}',
        zh: '最高 ¥${_maxPrice!.toStringAsFixed(0)}',
      );
    }
    return commerceText(context, 'Цена');
  }
}

class _CategoriesView extends ConsumerStatefulWidget {
  final Marketplace marketplace;
  final ValueChanged<ShopCategory> onCategorySearch;

  const _CategoriesView({
    required this.marketplace,
    required this.onCategorySearch,
  });

  @override
  ConsumerState<_CategoriesView> createState() => _CategoriesViewState();
}

class _CategoriesViewState extends ConsumerState<_CategoriesView> {
  /// Stack of (parentId, title) — for navigation breadcrumbs
  final List<({String? parentId, String title})> _stack = [];

  String? get _currentParentId =>
      _stack.isNotEmpty ? _stack.last.parentId : null;

  @override
  void didUpdateWidget(_CategoriesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.marketplace != widget.marketplace) {
      _stack.clear();
    }
  }

  void _onCategoryTap(ShopCategory cat) {
    if (cat.isParent) {
      setState(() {
        _stack.add((parentId: cat.id, title: cat.name));
      });
    } else {
      // Leaf category — search by categoryId
      widget.onCategorySearch(cat);
    }
  }

  void _goBack() {
    if (_stack.isNotEmpty) {
      setState(() {
        _stack.removeLast();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final params = ShopCategoryParams(
      marketplace: widget.marketplace,
      parentId: _currentParentId,
    );
    final categoriesAsync = ref.watch(shopCategoriesProvider(params));

    return Column(
      children: [
        // Back button + breadcrumb
        if (_stack.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _goBack,
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.chevron_left,
                        size: 18,
                        color: context.brandPrimary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _stack.last.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: context.brandPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // "Show items" button for parent categories
                GestureDetector(
                  onTap: () {
                    // Search items in current parent category
                    final cat = ShopCategory(
                      id: _currentParentId!,
                      name: _stack.last.title,
                      isParent: true,
                    );
                    widget.onCategorySearch(cat);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: context.brandPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.grid_view,
                          size: 14,
                          color: context.brandPrimary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          commerceText(context, 'Товары'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.brandPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

        if (_stack.isNotEmpty) const SizedBox(height: 8),

        // List
        Expanded(
          child: categoriesAsync.when(
            data: (categories) {
              if (categories.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.category_outlined,
                        size: 56,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        commerceText(
                          context,
                          'Введите запрос для поиска товаров',
                        ),
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final cat = categories[index];
                  return _CategoryTile(
                    category: cat,
                    onTap: () => _onCategoryTap(cat),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    commerceText(context, 'Не удалось загрузить категории'),
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(shopCategoriesProvider(params)),
                    child: Text(commerceText(context, 'Повторить')),
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

class _CategoryTile extends StatelessWidget {
  final ShopCategory category;
  final VoidCallback onTap;

  const _CategoryTile({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          category.name,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        trailing: category.isParent
            ? Icon(Icons.chevron_right, color: Colors.grey.shade400)
            : Icon(Icons.search, size: 22, color: Colors.grey.shade400),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onTap: onTap,
      ),
    );
  }
}

class _MarketplaceSearchHint extends StatelessWidget {
  const _MarketplaceSearchHint({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFE1251B).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'JD',
                  style: TextStyle(
                    color: Color(0xFFE1251B),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
