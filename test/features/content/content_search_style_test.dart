import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/core/persistence/shared_preferences_provider.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_input_decoration.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_layout.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_search_field.dart';
import 'package:twoalogisticcabineuser/src/features/news/data/news_provider.dart';
import 'package:twoalogisticcabineuser/src/features/news/domain/news_item.dart';
import 'package:twoalogisticcabineuser/src/features/news/presentation/news_detail_screen.dart';
import 'package:twoalogisticcabineuser/src/features/rules/data/rules_provider.dart';
import 'package:twoalogisticcabineuser/src/features/rules/domain/rule_item.dart';
import 'package:twoalogisticcabineuser/src/features/rules/presentation/rule_detail_screen.dart';
import 'package:twoalogisticcabineuser/src/features/rules/presentation/rules_screen.dart';
import '../../helpers/keyboard_acceptance.dart';

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 100));
}

const _content = 'Склад принимает груз.\n\nУсловия склада обновлены.';
const _rules = [
  RuleItem(
    slug: 'storage',
    title: 'Хранение',
    excerpt: 'Условия',
    content: _content,
    order: 1,
  ),
  RuleItem(
    slug: 'delivery',
    title: 'Доставка',
    excerpt: 'Отправка',
    content: 'Отправление по России',
    order: 2,
  ),
];

Future<void> _host(
  WidgetTester tester,
  String screen,
  TargetPlatform platform,
  double width,
) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'tutorial_rules': true,
    'tutorial_rule_detail': true,
    'tutorial_news_detail': true,
  });
  final prefs = await SharedPreferences.getInstance();
  final page = switch (screen) {
    'rules' => const RulesScreen(),
    'rule' => const RuleDetailScreen(slug: 'storage'),
    _ => const NewsDetailScreen(slug: 'news'),
  };
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        rulesListProvider.overrideWith((ref) async => _rules),
        ruleItemProvider('storage').overrideWith((ref) async => _rules.first),
        newsItemProvider('news').overrideWith(
          (ref) async => NewsItem(
            slug: 'news',
            title: 'Обновление',
            excerpt: 'Условия',
            content: _content,
            publishedAt: DateTime(2026, 11, 10),
          ),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(platform: platform, fontFamily: 'Gilroy'),
        home: Scaffold(body: page),
      ),
    ),
  );
  await _frames(tester);
}

void main() {
  setUpAll(() async {
    await loadKeyboardAcceptanceFonts();
    await initializeDateFormatting('ru');
  });
  for (final screen in ['rules', 'rule', 'news']) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      for (final width in [320.0, 390.0]) {
        testWidgets(
          '$screen unified search $platform $width preserves query results clear and IME',
          (tester) async {
            await _host(tester, screen, platform, width);
            final search = find.byType(AppSearchField);
            await tester.ensureVisible(search);
            await _frames(tester);
            final frame = find.descendant(
              of: search,
              matching: find.byType(AppOutlinedInputFrame),
            );
            expect(
              tester.getSize(frame).height,
              closeTo(48 * AppLayout.compactScale(tester.element(frame)), .01),
            );
            final style = tester.widget<AppOutlinedInputFrame>(frame);
            expect(style.radius, 16);
            expect(style.fillColor, const Color(0xFFF8FAFC));
            final field = find.descendant(
              of: search,
              matching: find.byType(TextField),
            );
            expect(
              tester.widget<TextField>(field).decoration!.prefixIcon,
              isNotNull,
            );
            await tester.tap(field);
            await tester.enterText(field, '  СКЛАД  ');
            tester.view.viewInsets = const FakeViewPadding(bottom: 320);
            await _frames(tester);
            final editable = find.descendant(
              of: search,
              matching: find.byType(EditableText),
            );
            expectFocusedCaretAboveIme(tester, editable);
            expect(
              tester.widget<TextField>(field).decoration!.prefixIcon,
              isNull,
            );
            if (screen == 'rules') {
              expect(find.text('Хранение'), findsOneWidget);
              expect(find.text('Доставка'), findsNothing);
            } else {
              expect(find.text('Фрагмент 1 из 2'), findsOneWidget);
            }
            await tester.tap(find.byTooltip('Очистить поиск'));
            await _frames(tester);
            expect(tester.widget<TextField>(field).controller!.text, isEmpty);
            expect(find.byTooltip('Очистить поиск'), findsNothing);
            if (screen == 'rules') {
              expect(find.text('Доставка'), findsOneWidget);
            } else {
              expect(find.textContaining('Фрагмент '), findsNothing);
            }
            await tester.enterText(field, 'несуществующее');
            await _frames(tester);
            if (screen != 'rules') {
              expect(find.text('Совпадений нет'), findsOneWidget);
            }
            await tester.testTextInput.receiveAction(
              tester.widget<TextField>(field).textInputAction!,
            );
            await _frames(tester);
            expect(
              tester.widget<EditableText>(editable).focusNode.hasFocus,
              isFalse,
            );
            expect(
              tester.widget<TextField>(field).decoration!.prefixIcon,
              isNotNull,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  testWidgets('custom clear owns one callback without an extra query change', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'draft');
    addTearDown(controller.dispose);
    var cleared = 0;
    var changed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSearchField(
            controller: controller,
            hintText: 'Поиск',
            onChanged: (_) => changed++,
            onClear: () => cleared++,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Очистить поиск'));
    await _frames(tester);
    expect(controller.text, isEmpty);
    expect(cleared, 1);
    expect(changed, 0);
  });
  testWidgets(
    'search submit dismisses native keyboard and delivers custom callback',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var submitted = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppSearchField(
              controller: controller,
              hintText: 'Поиск',
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (_) {},
              onSubmitted: (_) {
                submitted = true;
              },
            ),
          ),
        ),
      );
      await _frames(tester);
      await tester.enterText(find.byType(TextField), 'запрос');
      tester.testTextInput.log.clear();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await _frames(tester);
      expect(submitted, isTrue);
      expect(
        tester.testTextInput.log.any((call) => call.method == 'TextInput.hide'),
        isTrue,
      );
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isFalse,
      );
    },
  );
}
