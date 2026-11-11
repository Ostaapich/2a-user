import 'package:flutter/material.dart';

import '../utils/locale_text.dart';
import 'app_search_field.dart';

/// Searches the rendered document, preserving the Markdown subtree unchanged.
/// Results refer to text fragments, rather than inventing document sections.
class SearchableDocument extends StatefulWidget {
  const SearchableDocument({
    super.key,
    required this.contentIdentity,
    required this.child,
  });

  final String contentIdentity;
  final Widget child;

  @override
  State<SearchableDocument> createState() => _SearchableDocumentState();
}

class _SearchableDocumentState extends State<SearchableDocument> {
  final _controller = TextEditingController();
  final _documentKey = GlobalKey();
  List<BuildContext> _matches = [];
  int _selected = 0;
  String _query = '';

  @override
  void didUpdateWidget(SearchableDocument oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentIdentity != widget.contentIdentity) {
      _find(_controller.text);
    }
  }

  void _find(String value) {
    final query = value.trim().toLowerCase();
    setState(() {
      _query = query;
      _selected = 0;
      _matches = [];
    });
    if (query.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || query != _query) return;
      final matches = <BuildContext>[];
      void visit(Element element) {
        final widget = element.widget;
        String? text;
        if (widget is SelectableText) {
          text = widget.data ?? widget.textSpan?.toPlainText();
        } else if (widget is RichText) {
          text = widget.text.toPlainText();
        } else if (widget is Text) {
          text = widget.data ?? widget.textSpan?.toPlainText();
        }
        if (text != null) {
          if (text.toLowerCase().contains(query)) matches.add(element);
          // SelectableText/Text build RichText descendants. Count each block once.
          return;
        }
        element.visitChildElements(visit);
      }

      (_documentKey.currentContext as Element?)?.visitChildElements(visit);
      if (!mounted || query != _query) return;
      setState(() => _matches = matches);
    });
  }

  Future<void> _goTo(int index) async {
    if (_matches.isEmpty) return;
    final selected = (index + _matches.length) % _matches.length;
    final target = _matches[selected];
    if (!target.mounted) {
      _find(_controller.text);
      return;
    }
    setState(() => _selected = selected);
    FocusScope.of(context).unfocus();
    await Scrollable.ensureVisible(
      target,
      alignment: .15,
      duration: const Duration(milliseconds: 250),
    );
    if (!mounted) return;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppSearchField(
        controller: _controller,
        hintText: tr(context, ru: 'Поиск по тексту', zh: '搜索文档内容'),
        onChanged: _find,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _goTo(_selected),
      ),
      if (_query.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                _matches.isEmpty
                    ? tr(context, ru: 'Совпадений нет', zh: '未找到匹配内容')
                    : tr(
                        context,
                        ru: 'Фрагмент ${_selected + 1} из ${_matches.length}',
                        zh: '第 ${_selected + 1} / ${_matches.length} 段',
                      ),
              ),
              IconButton(
                tooltip: tr(context, ru: 'Предыдущий фрагмент', zh: '上一段'),
                onPressed: _matches.isEmpty ? null : () => _goTo(_selected - 1),
                icon: const Icon(Icons.arrow_upward),
              ),
              IconButton(
                tooltip: tr(context, ru: 'Следующий фрагмент', zh: '下一段'),
                onPressed: _matches.isEmpty ? null : () => _goTo(_selected + 1),
                icon: const Icon(Icons.arrow_downward),
              ),
            ],
          ),
        ),
      const SizedBox(height: 16),
      KeyedSubtree(key: _documentKey, child: widget.child),
    ],
  );
}
