import 'package:twoalogisticcabineuser/src/features/training/presentation/training_target.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/ui/app_colors.dart';
import '../../../../core/ui/app_search_field.dart';
import '../../../../core/utils/locale_text.dart';

class ShopSearchBar extends StatefulWidget {
  final ValueChanged<String> onSearch;
  final String? initialQuery;

  const ShopSearchBar({super.key, required this.onSearch, this.initialQuery});

  @override
  State<ShopSearchBar> createState() => _ShopSearchBarState();
}

class _ShopSearchBarState extends State<ShopSearchBar> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final query = _controller.text.trim();
    if (query.isNotEmpty) {
      FocusScope.of(context).unfocus();
      widget.onSearch(query);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: TrainingTarget(
              id: 'shop.search',
              child: AppSearchField(
                controller: _controller,
                hintText: tr(context, ru: 'Поиск товаров...', zh: '搜索商品……'),
                textInputAction: TextInputAction.search,
                // Marketplace search remains explicit: typing/clearing never
                // starts a request or submits a purchase.
                onChanged: (_) {},
                onSubmitted: (_) => _submit(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              tooltip: tr(context, ru: 'Найти товары', zh: '搜索商品'),
              onPressed: _submit,
              icon: Icon(
                CupertinoIcons.arrow_right_circle_fill,
                size: 26,
                color: context.brandPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
