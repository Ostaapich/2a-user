import 'package:twoalogisticcabineuser/src/core/media/authenticated_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_config.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/ui/app_layout.dart';
import '../../../core/ui/blurred_media_backdrop.dart';
import '../../../core/ui/scroll_to_top_button.dart';
import '../../../core/ui/searchable_document.dart';
import '../../../core/ui/tutorial_card.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/utils/locale_text.dart';
import '../data/news_provider.dart';
import 'news_ui.dart';

class NewsDetailScreen extends ConsumerStatefulWidget {
  final String slug;

  const NewsDetailScreen({super.key, required this.slug});

  @override
  ConsumerState<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends ConsumerState<NewsDetailScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncItem = ref.watch(newsItemProvider(widget.slug));
    final topPad = AppLayout.topBarTotalHeight(context);
    final bottomPad = AppLayout.bottomScrollPadding(context);

    Future<void> onRefresh() async {
      ref.invalidate(newsItemProvider(widget.slug));
      await ref.read(newsItemProvider(widget.slug).future);
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
      return [
        NewsPageHeader(
          title: tr(context, ru: 'Новость', zh: '新闻'),
        ),
        const SizedBox(height: 12),
        NewsHeroCard(
          icon: Icons.article_rounded,
          title: tr(context, ru: 'Новость компании', zh: '公司新闻'),
          subtitle: tr(
            context,
            ru: 'Загружаем публикацию и важные детали.',
            zh: '正在加载新闻内容和重要信息。',
          ),
          chips: [
            NewsHeroChip(
              icon: Icons.newspaper_rounded,
              label: tr(context, ru: 'публикация', zh: '新闻'),
            ),
          ],
        ),
        const SizedBox(height: 14),
      ];
    }

    return asyncItem.when(
      loading: () => buildFrame(
        children: [
          ...baseHeader(),
          NewsStateCard(
            icon: Icons.article_rounded,
            title: tr(context, ru: 'Загружаем новость', zh: '正在加载新闻'),
            message: tr(
              context,
              ru: 'Получаем текст публикации.',
              zh: '正在获取文章内容。',
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
      data: (item) {
        if (item == null) {
          return buildFrame(
            children: [
              ...baseHeader(),
              NewsStateCard(
                icon: Icons.article_outlined,
                title: tr(context, ru: 'Статья не найдена', zh: '未找到文章'),
                message: tr(
                  context,
                  ru: 'Новость могла быть удалена или снята с публикации.',
                  zh: '该新闻可能已被删除或取消发布。',
                ),
                isError: true,
              ),
            ],
          );
        }

        final locale = isZh(context) ? 'zh' : 'ru';
        final df = DateFormat('dd MMM yyyy', locale);
        final publishedDate = df.format(item.publishedAt);

        return TutorialScreenWrapper(
          screenKey: 'news_detail',
          steps: const [
            TutorialStep(
              icon: Icons.article_rounded,
              title: 'Статья',
              description:
                  'Здесь отображается полный текст новости с датой публикации и обложкой.',
            ),
            TutorialStep(
              icon: Icons.image_rounded,
              title: 'Фото в статье',
              description:
                  'Нажмите на любое изображение в статье, чтобы открыть его на весь экран и увеличить.',
            ),
          ],
          child: buildFrame(
            children: [
              NewsPageHeader(
                title: tr(context, ru: 'Новость', zh: '新闻'),
              ),
              const SizedBox(height: 12),
              NewsHeroCard(
                icon: Icons.article_rounded,
                title: item.title,
                subtitle: publishedDate,
                titleMaxLines: null,
              ),
              const SizedBox(height: 14),
              if (item.imageUrl != null) ...[
                _ArticleCoverImage(
                  imageUrl: item.imageUrl!,
                  onTap: () => _openImageFullscreen(context, item.imageUrl!),
                ),
                const SizedBox(height: 14),
              ],
              _ArticleContentCard(
                content: item.content,
                onImageTap: (imageUrl) =>
                    _openImageFullscreen(context, imageUrl),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openImageFullscreen(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _FullscreenImageViewer(imageUrl: imageUrl),
      ),
    );
  }
}

class _ArticleCoverImage extends StatelessWidget {
  final String imageUrl;
  final VoidCallback onTap;

  const _ArticleCoverImage({required this.imageUrl, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          height: 220,
          clipBehavior: Clip.antiAlias,
          decoration: NewsUi.cardDecoration(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              AuthenticatedCachedImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(
                  color: const Color(0xFFF5F5F5),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.brandPrimary,
                    ),
                  ),
                ),
                errorWidget: (_, _, _) => const _ArticleImageError(),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.38),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: const Icon(
                    Icons.open_in_full_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArticleImageError extends StatelessWidget {
  const _ArticleImageError();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: Center(
        child: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: context.brandPrimary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            Icons.image_not_supported_rounded,
            color: context.brandPrimary,
            size: 30,
          ),
        ),
      ),
    );
  }
}

class _ArticleContentCard extends StatelessWidget {
  final String content;
  final ValueChanged<String> onImageTap;

  const _ArticleContentCard({required this.content, required this.onImageTap});

  @override
  Widget build(BuildContext context) {
    final hasContent = content.trim().isNotEmpty;

    return Container(
      decoration: NewsUi.cardDecoration(),
      padding: const EdgeInsets.all(16),
      child: hasContent
          ? SearchableDocument(
              contentIdentity: content,
              child: MarkdownBody(
                data: content,
                selectable: true,
                styleSheet: _markdownStyleSheet(context),
                onTapLink: (text, href, title) async {
                  final uri = Uri.tryParse(href ?? '');
                  var opened = false;
                  try {
                    if (uri != null &&
                        const {
                          'https',
                          'http',
                          'mailto',
                          'tel',
                        }.contains(uri.scheme)) {
                      opened = await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  } catch (_) {
                    /* A missing handler is actionable in the reader. */
                  }
                  if (!context.mounted) return;
                  if (!opened) {
                    AppToast.show(
                      context,
                      tr(
                        context,
                        ru: 'Не удалось открыть ссылку. Попробуйте открыть её в браузере.',
                        zh: '无法打开链接，请尝试在浏览器中打开。',
                      ),
                      isError: true,
                    );
                  }
                },
                imageBuilder: (uri, title, alt) {
                  final raw = uri.toString();
                  final imageUrl = _normalizeImageUrl(raw);
                  return _ArticleMarkdownImage(
                    imageUrl: imageUrl,
                    onTap: () => onImageTap(imageUrl),
                  );
                },
              ),
            )
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: NewsUi.softDecoration(),
              child: Text(
                tr(
                  context,
                  ru: 'Текст новости пока не заполнен.',
                  zh: '新闻内容暂未填写。',
                ),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'Gilroy',
                  fontSize: 13.5,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
    );
  }

  String _normalizeImageUrl(String value) {
    final raw = value.trim();
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return ApiConfig.getMediaUrl(raw);
  }

  MarkdownStyleSheet _markdownStyleSheet(BuildContext context) {
    const base = TextStyle(
      color: AppColors.textPrimary,
      fontFamily: 'Gilroy',
      fontSize: 15,
      height: 1.5,
      fontWeight: FontWeight.w600,
    );

    return MarkdownStyleSheet(
      p: base,
      pPadding: const EdgeInsets.only(bottom: 10),
      strong: base.copyWith(fontWeight: FontWeight.w900),
      em: base.copyWith(fontStyle: FontStyle.italic),
      a: base.copyWith(
        color: context.brandPrimary,
        decoration: TextDecoration.underline,
        decorationColor: context.brandPrimary,
      ),
      h1: base.copyWith(
        fontSize: 22,
        height: 1.12,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.25,
      ),
      h1Padding: const EdgeInsets.only(top: 8, bottom: 10),
      h2: base.copyWith(
        fontSize: 20,
        height: 1.15,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.2,
      ),
      h2Padding: const EdgeInsets.only(top: 10, bottom: 8),
      h3: base.copyWith(fontSize: 17, height: 1.2, fontWeight: FontWeight.w900),
      h3Padding: const EdgeInsets.only(top: 8, bottom: 6),
      listBullet: base.copyWith(
        color: context.brandPrimary,
        fontWeight: FontWeight.w900,
      ),
      listIndent: 22,
      blockSpacing: 8,
      blockquote: base.copyWith(color: AppColors.textSecondary),
      blockquotePadding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      blockquoteDecoration: BoxDecoration(
        color: context.brandPrimary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.brandPrimary.withValues(alpha: 0.16)),
      ),
      code: base.copyWith(
        fontFamily: 'monospace',
        fontSize: 13.5,
        color: context.brandPrimary,
        backgroundColor: context.brandPrimary.withValues(alpha: 0.08),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      codeblockDecoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
      ),
    );
  }
}

class _ArticleMarkdownImage extends StatelessWidget {
  final String imageUrl;
  final VoidCallback onTap;

  const _ArticleMarkdownImage({required this.imageUrl, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AuthenticatedCachedImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(
                height: 170,
                color: const Color(0xFFF5F5F5),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.brandPrimary,
                  ),
                ),
              ),
              errorWidget: (_, _, _) => Container(
                height: 170,
                color: const Color(0xFFF8FAFC),
                child: Icon(
                  Icons.broken_image_rounded,
                  color: context.brandPrimary.withValues(alpha: 0.45),
                  size: 38,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FullscreenImageViewer extends StatelessWidget {
  final String imageUrl;

  const _FullscreenImageViewer({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
      body: BlurredMediaBackdrop(
        imageUrl: imageUrl,
        child: PhotoView(
          imageProvider: authenticatedImageProvider(context, imageUrl),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
          backgroundDecoration: const BoxDecoration(color: Colors.transparent),
          loadingBuilder: (context, event) => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
          errorBuilder: (context, error, stackTrace) => const Center(
            child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
          ),
        ),
      ),
    );
  }
}
