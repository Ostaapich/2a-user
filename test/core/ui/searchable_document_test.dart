import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:twoalogisticcabineuser/src/core/ui/searchable_document.dart';
import 'package:twoalogisticcabineuser/src/core/utils/delta_converter.dart';

void main() {
  testWidgets('search controls wrap on320px with200percent text in RU/ZH', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 740));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    for (final locale in ['ru', 'zh']) {
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          supportedLocales: const [Locale('ru'), Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SearchableDocument(
                  contentIdentity: 'Условия 内容',
                  child: MarkdownBody(data: 'Условия 内容', selectable: true),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '内容');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'search navigates real rendered fragments without losing Delta headings or lists',
    (tester) async {
      final original = DeltaConverter.toMarkdown(
        jsonEncode([
          {'insert': 'Условия хранения'},
          {
            'insert': '\n',
            'attributes': {'header': 2},
          },
          {'insert': 'Клиент указывает получателя.'},
          {
            'insert': '\n',
            'attributes': {'list': 'ordered'},
          },
          {'insert': '${List.filled(90, 'Описание груза. ').join()}\n\n'},
          {'insert': 'Получатель получает уведомление.\n'},
        ]),
      );
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: scroll,
              children: [
                SearchableDocument(
                  contentIdentity: original,
                  child: MarkdownBody(data: original, selectable: true),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'получател');
      await tester.pumpAndSettle();
      expect(find.text('Фрагмент 1 из 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Следующий фрагмент'));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(100));
      expect(
        tester.widget<MarkdownBody>(find.byType(MarkdownBody)).data,
        original,
      );
      expect(original, contains('## Условия хранения'));
      expect(original, contains('1. Клиент'));
    },
  );

  testWidgets(
    'plain text search reports no results and clears without invented headings',
    (tester) async {
      const content =
          'Фотоотчёт: важная информация\n\nДля корректного выполнения фотоотчёта просим чётко прописывать пожелания.';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SearchableDocument(
                contentIdentity: content,
                child: MarkdownBody(data: content, selectable: true),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'неизвестное слово');
      await tester.pumpAndSettle();
      expect(find.text('Совпадений нет'), findsOneWidget);
      await tester.tap(find.byTooltip('Очистить поиск'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MarkdownBody>(find.byType(MarkdownBody)).data,
        content,
      );
      expect(find.text('Совпадений нет'), findsNothing);
    },
  );
}
