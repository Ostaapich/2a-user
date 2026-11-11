import 'package:twoalogisticcabineuser/src/core/media/authenticated_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../training/presentation/training_target.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/ui/app_layout.dart';
import '../../../core/ui/scroll_to_top_button.dart';
import '../../../core/ui/tutorial_card.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/utils/locale_text.dart';
import '../data/news_provider.dart';
import '../domain/news_item.dart';
import 'news_ui.dart';

class NewsListScreen extends ConsumerStatefulWidget {
  const NewsListScreen({super.key});

  @override
  ConsumerState<NewsListScreen> createState() => _NewsListScreenState();
}

class _NewsListScreenState extends ConsumerState<NewsListScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _newsListKey = GlobalKey();
  final GlobalKey _firstNewsKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final asyncItems = ref.watch(newsListProvider);
    final topPad = AppLayout.topBarTotalHeight(context);
    final bottomPad = AppLayout.bottomScrollPadding(context);
    final horizontalPad = AppLayout.horizontalMargin(context);

    Future<void> onRefresh() async {
      ref.invalidate(newsListProvider);
      await ref.read(newsListProvider.future);
    }

    Widget buildFrame({required List<Widget> children}) {
      return Stack(
        children: [
          RefreshIndicator(
            onRefresh: onRefresh,
            color: context.brandPrimary,
            child: ListView(
              controller: _scrollController,
              key: _newsListKey,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                horizontalPad,
                topPad * 0.7 + 16,
                horizontalPad,
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
      return [
        NewsPageHeader(
          title: tr(context, ru: 'Новости', zh: '新闻'),
        ),
        const SizedBox(height: 12),
        NewsHeroCard(
          icon: Icons.newspaper_rounded,
          title: tr(context, ru: 'Новости компании', zh: '公司新闻'),
          subtitle: tr(
            context,
            ru: 'Важные объявления, изменения в работе склада, тарифы и полезные материалы.',
            zh: '重要公告、仓库工作变化、价格和实用信息。',
          ),
        ),
        const SizedBox(height: 14),
      ];
    }

    return asyncItems.when(
      loading: () => buildFrame(
        children: [
          ...baseHeader(),
          NewsStateCard(
            icon: Icons.newspaper_rounded,
            title: tr(context, ru: 'Загружаем новости', zh: '正在加载新闻'),
            message: tr(
              context,
              ru: 'Получаем последние публикации компании.',
              zh: '正在获取公司的最新发布。',
            ),
            isLoading: true,
          ),
        ],
      ),
      error: (e, _) {
        final errorInfo = ErrorUtils.getErrorInfo(e);
        return buildFrame(
          children: [
            ...baseHeader(),
            NewsStateCard(
              icon: errorInfo.icon,
              title: errorInfo.title,
              message: errorInfo.message,
              isError: true,
            ),
          ],
        );
      },
      data: (items) {
        if (items.isEmpty) {
          return buildFrame(
            children: [
              ...baseHeader(),
              NewsStateCard(
                icon: Icons.newspaper_outlined,
                title: tr(context, ru: 'Пока нет новостей', zh: '暂无新闻'),
                message: tr(
                  context,
                  ru: 'Здесь появятся новости, акции и важные объявления.',
                  zh: '这里将显示新闻、活动和重要公告。',
                ),
              ),
            ],
          );
        }

        return TutorialScreenWrapper(
          screenKey: 'news_list',
          steps: [
            TutorialStep(
              icon: Icons.newspaper_rounded,
              title: 'Новости компании',
              description:
                  'Здесь публикуются важные новости: изменения тарифов, акции, объявления об изменениях в работе.',
              targetKey: _newsListKey,
            ),
            TutorialStep(
              icon: Icons.open_in_new_rounded,
              title: 'Читать подробнее',
              description:
                  'Нажмите на карточку новости, чтобы прочитать полный текст. Важные новости лучше не пропускать.',
              targetKey: _firstNewsKey,
            ),
          ],
          child: buildFrame(
            children: [
              ...baseHeader(),
              _NewsSectionHeader(count: items.length),
              const SizedBox(height: 10),
              _NewsCardsGrid(items: items, firstItemKey: _firstNewsKey),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

class _NewsCardsGrid extends StatelessWidget {
  final List<NewsItem> items;
  final GlobalKey firstItemKey;

  const _NewsCardsGrid({required this.items, required this.firstItemKey});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 520
            ? 2
            : 1;
        final spacing = columns >= 3 ? 14.0 : 12.0;
        final tileWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (var i = 0; i < items.length; i++)
              SizedBox(
                width: tileWidth,
                child: i == 0
                    ? KeyedSubtree(
                        key: firstItemKey,
                        child: _NewsCard(item: items[i], trainingTarget: true),
                      )
                    : _NewsCard(item: items[i]),
              ),
          ],
        );
      },
    );
  }
}

class _NewsSectionHeader extends StatelessWidget {
  final int count;

  const _NewsSectionHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: context.brandPrimary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(
            Icons.feed_rounded,
            color: context.brandPrimary,
            size: 22,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            tr(context, ru: 'Последние новости', zh: '最新新闻'),
            style: NewsUi.sectionTitleStyle,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: context.brandPrimary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: context.brandPrimary,
              fontFamily: 'Gilroy',
              fontSize: 12,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _NewsCard extends StatelessWidget {
  final NewsItem item;

  const _NewsCard({required this.item, this.trainingTarget = false});
  final bool trainingTarget;

  @override
  Widget build(BuildContext context) {
    final locale = isZh(context) ? 'zh' : 'ru';
    final df = DateFormat('dd MMM yyyy', locale);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => context.push('/news/${item.slug}'),
        child: Container(
          decoration: NewsUi.cardDecoration(),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (item.imageUrl?.isNotEmpty == true)
                _NewsCoverImage(imageUrl: item.imageUrl!),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NewsDatePill(label: df.format(item.publishedAt)),
                    const SizedBox(height: 12),
                    TrainingTarget(
                      id: trainingTarget
                          ? 'news.open'
                          : 'news.open.${item.slug}',
                      child: Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontFamily: 'Gilroy',
                          fontWeight: FontWeight.w900,
                          fontSize: 19,
                          height: 1.08,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (item.excerpt.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        item.excerpt,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontFamily: 'Gilroy',
                          fontSize: 13.5,
                          height: 18 / 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: context.brandPrimary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: context.brandPrimary.withValues(alpha: 0.10),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tr(context, ru: 'Читать далее', zh: '阅读更多'),
                            style: TextStyle(
                              color: context.brandPrimary,
                              fontFamily: 'Gilroy',
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              height: 1,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 17,
                            color: context.brandPrimary,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewsCoverImage extends StatelessWidget {
  final String imageUrl;

  const _NewsCoverImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return AuthenticatedCachedImage(
      imageUrl: imageUrl,
      height: 158,
      fit: BoxFit.cover,
      placeholder: (_, _) => Container(
        height: 158,
        color: const Color(0xFFF5F5F5),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.brandPrimary,
          ),
        ),
      ),
      errorWidget: (_, _, _) => const _NewsPlaceholderCover(),
    );
  }
}

class _NewsPlaceholderCover extends StatelessWidget {
  const _NewsPlaceholderCover();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 146,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(gradient: context.brandGradient),
          ),
          const Positioned.fill(child: NewsHeaderGlowBackdrop()),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                child: const Icon(
                  Icons.newspaper_rounded,
                  color: Colors.white,
                  size: 29,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
