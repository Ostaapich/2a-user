import 'package:twoalogisticcabineuser/src/core/media/authenticated_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../data/rules_provider.dart';
import 'rules_ui.dart';

class RuleDetailScreen extends ConsumerStatefulWidget {
  final String slug;
  const RuleDetailScreen({super.key, required this.slug});

  @override
  ConsumerState<RuleDetailScreen> createState() => _RuleDetailScreenState();
}

class _RuleDetailScreenState extends ConsumerState<RuleDetailScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncItem = ref.watch(ruleItemProvider(widget.slug));
    final topPad = AppLayout.topBarTotalHeight(context);
    final bottomPad = AppLayout.bottomScrollPadding(context);

    Future<void> onRefresh() async {
      ref.invalidate(ruleItemProvider(widget.slug));
      await ref.read(ruleItemProvider(widget.slug).future);
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
        RulesPageHeader(
          title: tr(context, ru: 'Правило', zh: '规则'),
          fallbackRoute: '/rules',
        ),
        const SizedBox(height: 12),
        RulesHeroCard(
          icon: Icons.rule_rounded,
          title: tr(context, ru: 'Правила оказания услуг', zh: '服务规则'),
          subtitle: tr(
            context,
            ru: 'Получаем актуальный текст условия.',
            zh: '正在获取最新规则内容。',
          ),
        ),
        const SizedBox(height: 14),
      ];
    }

    return asyncItem.when(
      loading: () => buildFrame(
        children: [
          ...baseHeader(),
          RulesStateCard(
            icon: Icons.rule_rounded,
            title: tr(context, ru: 'Загружаем правило', zh: '正在加载规则'),
            message: tr(
              context,
              ru: 'Получаем актуальный текст правила.',
              zh: '正在获取规则内容。',
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
            RulesStateCard(
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
              RulesStateCard(
                icon: Icons.article_outlined,
                title: tr(context, ru: 'Правило не найдено', zh: '未找到规则'),
                message: tr(
                  context,
                  ru: 'Правило могло быть удалено или снято с публикации.',
                  zh: '该规则可能已被删除或取消发布。',
                ),
                isError: true,
              ),
            ],
          );
        }

        final orderLabel = item.order > 0
            ? tr(context, ru: 'Пункт ${item.order}', zh: '第 ${item.order} 条')
            : tr(context, ru: 'Актуальное правило', zh: '最新规则');

        return TutorialScreenWrapper(
          screenKey: 'rule_detail',
          steps: const [
            TutorialStep(
              icon: Icons.rule_rounded,
              title: 'Текст правила',
              description:
                  'Здесь отображается полное содержание правила. Прокрутите вниз, чтобы прочитать его целиком.',
            ),
            TutorialStep(
              icon: Icons.image_rounded,
              title: 'Изображения',
              description:
                  'Нажмите на любое изображение в правиле, чтобы открыть его на весь экран и увеличить.',
            ),
          ],
          child: buildFrame(
            children: [
              RulesPageHeader(
                title: tr(context, ru: 'Правило', zh: '规则'),
                fallbackRoute: '/rules',
              ),
              const SizedBox(height: 12),
              RulesHeroCard(
                icon: Icons.rule_rounded,
                title: item.title,
                subtitle: orderLabel,
                titleMaxLines: null,
              ),
              const SizedBox(height: 14),
              _RuleContentCard(
                content: item.content,
                onImageTap: (imageUrl) =>
                    _openImageFullscreen(context, _normalizeImageUrl(imageUrl)),
              ),
            ],
          ),
        );
      },
    );
  }

  String _normalizeImageUrl(String value) {
    final raw = value.trim();
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return ApiConfig.getMediaUrl(raw);
  }

  void _openImageFullscreen(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _FullscreenImageViewer(imageUrl: imageUrl),
      ),
    );
  }
}

class _RuleContentCard extends StatelessWidget {
  final String content;
  final ValueChanged<String> onImageTap;

  const _RuleContentCard({required this.content, required this.onImageTap});

  @override
  Widget build(BuildContext context) {
    final hasContent = content.trim().isNotEmpty;

    return Container(
      decoration: RulesUi.cardDecoration(),
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
                  final imageUrl =
                      raw.startsWith('http://') || raw.startsWith('https://')
                      ? raw
                      : ApiConfig.getMediaUrl(raw);
                  return _RuleMarkdownImage(
                    imageUrl: imageUrl,
                    onTap: () => onImageTap(imageUrl),
                  );
                },
              ),
            )
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: RulesUi.softDecoration(),
              child: Text(
                tr(
                  context,
                  ru: 'Текст правила пока не заполнен.',
                  zh: '规则内容暂未填写。',
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

class _RuleMarkdownImage extends StatelessWidget {
  final String imageUrl;
  final VoidCallback onTap;

  const _RuleMarkdownImage({required this.imageUrl, required this.onTap});

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
