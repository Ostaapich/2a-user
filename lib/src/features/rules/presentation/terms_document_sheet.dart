import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/network/api_config.dart';
import '../../../core/ui/app_cached_media_image.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/ui/searchable_document.dart';
import '../../../core/utils/locale_text.dart';
import '../domain/client_terms_snapshot.dart';

/// Reads the exact bundle associated with the acceptance button's revision.
/// Opening the reader never fetches a newer or unrelated rules list.
class TermsDocumentSheet extends StatelessWidget {
  const TermsDocumentSheet({super.key, required this.snapshot});
  final ClientTermsSnapshot snapshot;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        ListTile(
          title: Text(
            tr(
              context,
              ru: 'Правила: ${snapshot.identity.displayVersion}',
              zh: '规则版本：${snapshot.identity.displayVersion}',
            ),
          ),
          trailing: IconButton(
            tooltip: tr(context, ru: 'Закрыть правила', zh: '关闭规则'),
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SearchableDocument(
              contentIdentity: snapshot.revision!,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final rule in snapshot.rules) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        rule.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    MarkdownBody(
                      data: rule.content,
                      selectable: true,
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
                          /* Preserve the reader on unavailable external handler. */
                        }
                        if (!context.mounted) return;
                        if (!opened) {
                          AppToast.show(
                            context,
                            tr(
                              context,
                              ru: 'Не удалось открыть ссылку',
                              zh: '无法打开链接',
                            ),
                            isError: true,
                          );
                        }
                      },
                      imageBuilder: (uri, title, alt) {
                        final raw = uri.toString();
                        final url =
                            raw.startsWith('https://') ||
                                raw.startsWith('http://')
                            ? raw
                            : ApiConfig.getMediaUrl(raw);
                        return AppCachedMediaImage(
                          url: url,
                          fit: BoxFit.contain,
                        );
                      },
                    ),
                    const Divider(height: 32),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
