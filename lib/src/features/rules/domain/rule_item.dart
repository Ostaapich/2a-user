import '../../../core/utils/delta_converter.dart';

class RuleItem {
  final String slug;
  final String title;
  final String excerpt;

  /// Markdown content for rich text rendering (converted from Delta if needed)
  final String content;
  final int order;
  final DateTime? updatedAt;

  const RuleItem({
    required this.slug,
    required this.title,
    required this.excerpt,
    required this.content,
    required this.order,
    this.updatedAt,
  });

  factory RuleItem.fromJson(Map<String, dynamic> json) {
    final rawContent = json['content'] as String? ?? '';

    // Конвертируем Delta JSON в Markdown если нужно
    final content = DeltaConverter.toMarkdown(rawContent);

    return RuleItem(
      slug: json['id'].toString(),
      title: json['title'] as String? ?? '',
      excerpt: _extractExcerpt(content),
      content: content,
      order: json['sortOrder'] as int? ?? 0,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }

  /// Извлекает первые ~150 символов для превью
  static String _extractExcerpt(String content) {
    // Убираем markdown разметку для чистого текста
    final cleaned = content
        .replaceAll(RegExp(r'#{1,6}\s*'), '') // заголовки
        .replaceAll(RegExp(r'\*{1,2}'), '') // bold/italic
        .replaceAll(RegExp(r'`{1,3}'), '') // code
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1') // links
        .replaceAll(RegExp(r'>\s*'), '') // blockquotes
        .replaceAll(RegExp(r'[-*]\s+'), '') // lists
        .replaceAll(RegExp(r'\n+'), ' ') // newlines
        .trim();

    if (cleaned.length <= 150) return cleaned;
    return '${cleaned.substring(0, 147)}...';
  }
}
