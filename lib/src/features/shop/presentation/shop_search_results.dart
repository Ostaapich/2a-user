import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/app_layout.dart';
import '../data/shop_provider.dart';
import '../domain/marketplace.dart';
import '../domain/shop_item.dart';
import 'widgets/shop_item_card.dart';

class ShopSearchResults extends ConsumerStatefulWidget {
  final ShopSearchParams params;

  const ShopSearchResults({super.key, required this.params});

  @override
  ConsumerState<ShopSearchResults> createState() => _ShopSearchResultsState();
}

class _ShopSearchResultsState extends ConsumerState<ShopSearchResults> {
  final List<ShopItem> _allItems = [];
  int _currentPage = 0;
  int _total = 0;
  String? _nextCursor;
  String? _currentCursor;
  bool _isLoadingMore = false;

  /// The base params (without page) — used to detect when search changes
  ShopSearchParams get _baseParams =>
      widget.params.copyWithReset(page: 0, resetCursor: true);

  ShopSearchParams? _lastBaseParams;

  @override
  void initState() {
    super.initState();
    _lastBaseParams = _baseParams;
  }

  @override
  void didUpdateWidget(ShopSearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If base search params changed (query, marketplace, filters, sort) — reset
    if (_lastBaseParams != _baseParams) {
      _lastBaseParams = _baseParams;
      _allItems.clear();
      _currentPage = 0;
      _total = 0;
      _nextCursor = null;
      _currentCursor = null;
      _isLoadingMore = false;
    }
  }

  void _onPageLoaded(ShopSearchResult result, int page) {
    if (!mounted) return;
    // Avoid duplicates: only add if this page's items aren't already in the list
    final expectedStart = page * (widget.params.pageSize);
    if (_allItems.length <= expectedStart) {
      _allItems.addAll(result.items);
    }
    _total = result.total;
    _nextCursor = result.nextCursor;
    _currentPage = page;
    _isLoadingMore = false;
  }

  void _loadNextPage() {
    if (_isLoadingMore) return;
    if (_allItems.length >= _total) return;
    setState(() {
      _isLoadingMore = true;
      _currentCursor = _nextCursor;
      _currentPage++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Always watch the current page
    final params = widget.params.copyWith(
      page: _currentPage,
      cursor: _currentCursor,
    );
    final searchAsync = ref.watch(shopSearchProvider(params));

    return searchAsync.when(
      data: (result) {
        _onPageLoaded(result, _currentPage);

        if (_allItems.isEmpty) {
          return Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text(
                    'Ничего не найдено',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Попробуйте изменить запрос',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),
          );
        }

        final hasMore =
            _allItems.length < _total &&
            (widget.params.marketplace != Marketplace.jd ||
                _nextCursor?.isNotEmpty == true);

        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollEndNotification &&
                notification.metrics.extentAfter < 300 &&
                hasMore &&
                !_isLoadingMore) {
              _loadNextPage();
            }
            return false;
          },
          child: _buildGrid(context, hasMore: hasMore),
        );
      },
      loading: () {
        if (_allItems.isNotEmpty) {
          // Already have items, show them + loading at bottom
          final hasMore =
              _allItems.length < _total &&
              (widget.params.marketplace != Marketplace.jd ||
                  _nextCursor?.isNotEmpty == true);
          return NotificationListener<ScrollNotification>(
            onNotification: (notification) => false,
            child: _buildGrid(context, hasMore: hasMore),
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
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
              onPressed: () {
                ref.invalidate(shopSearchProvider(params));
              },
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context, {required bool hasMore}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final crossAxisCount = width >= 960
            ? 4
            : width >= 700
            ? 3
            : 2;
        final spacing = width >= 700 ? 14.0 : 12.0;

        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            AppLayout.bottomScrollPadding(context) + 20,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: width >= 700 ? 0.58 : 0.54,
          ),
          itemCount: _allItems.length + (hasMore ? crossAxisCount : 0),
          itemBuilder: (context, index) {
            if (index >= _allItems.length) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            final item = _allItems[index];
            return ShopItemCard(
              item: item,
              trainingTarget: index == 0,
              onTap: () {
                context.push(
                  Uri(
                    path: '/shop/item/${item.id}',
                    queryParameters: {'provider': item.provider},
                  ).toString(),
                );
              },
            );
          },
        );
      },
    );
  }
}
