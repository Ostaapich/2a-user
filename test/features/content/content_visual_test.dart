import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:twoalogisticcabineuser/src/features/news/data/news_provider.dart';
import 'package:twoalogisticcabineuser/src/features/news/domain/news_item.dart';
import 'package:twoalogisticcabineuser/src/features/news/presentation/news_detail_screen.dart';
import 'package:twoalogisticcabineuser/src/features/news/presentation/news_list_screen.dart';
import 'package:twoalogisticcabineuser/src/features/rules/data/rules_provider.dart';
import 'package:twoalogisticcabineuser/src/features/rules/domain/rule_item.dart';
import 'package:twoalogisticcabineuser/src/features/rules/presentation/rule_detail_screen.dart';
import 'package:twoalogisticcabineuser/src/features/rules/presentation/rules_screen.dart';
import 'package:twoalogisticcabineuser/src/features/tariffs/data/tariffs_provider.dart';
import 'package:twoalogisticcabineuser/src/features/tariffs/presentation/tariffs_screen.dart';

const _title =
    'Подробная инструкция по оформлению международной доставки, проверке товаров и получению посылки на складе';
const _content =
    '## Подготовка\n\nПроверьте адрес склада и код клиента перед оформлением заказа.\n\n## Получение\n\n1. Проверьте количество мест.\n2. Сохраните документы.\n\nИнформация должна оставаться доступной полностью.';
final _news = NewsItem(
  slug: '1',
  title: _title,
  excerpt: 'Краткая инструкция по получению и проверке посылок.',
  content: _content,
  publishedAt: DateTime(2026, 11, 9),
);
const _rule = RuleItem(
  slug: '1',
  title: _title,
  excerpt: 'Условия приёмки, хранения и выдачи.',
  content: _content,
  order: 1,
);
void main() {
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader('CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
    await initializeDateFormatting('ru');
    await initializeDateFormatting('zh');
    await (FontLoader('Gilroy')
          ..addFont(rootBundle.load('assets/fonts/gilroy/Gilroy-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/gilroy/Gilroy-Bold.ttf')))
        .load();
  });
  final pages = <String, Widget>{
    'news': const NewsListScreen(),
    'news-detail': const NewsDetailScreen(slug: '1'),
    'rules': const RulesScreen(),
    'rule-detail': const RuleDetailScreen(slug: '1'),
    'tariffs': const TariffsScreen(),
  };
  for (final scenario in [
    (390.0, 1.0, 'ru'),
    (320.0, 1.6, 'ru'),
    (390.0, 1.0, 'zh'),
  ]) {
    final (width, scale, locale) = scenario;
    for (final entry in pages.entries) {
      testWidgets('${entry.key} at ${width.toInt()}px $locale scale=$scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              newsListProvider.overrideWith((_) async => [_news, _news]),
              newsItemProvider('1').overrideWith((_) async => _news),
              rulesListProvider.overrideWith((_) async => [_rule]),
              ruleItemProvider('1').overrideWith((_) async => _rule),
              userTariffsProvider.overrideWith(
                (_) async => const UserTariffsData(
                  deliveryTariffs: [
                    UserDeliveryTariff(
                      id: 1,
                      name: 'Тариф для обычных грузов',
                      baseCost: 2,
                      weightTiers: [
                        UserWeightTier(
                          minWeight: 10,
                          maxWeight: 20,
                          pricePerKg: 2,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            child: MaterialApp(
              locale: Locale(locale),
              supportedLocales: const [Locale('ru'), Locale('zh')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: ThemeData(
                fontFamily: 'Gilroy',
                colorScheme: const ColorScheme.light(
                  primary: Color(0xFFF26F23),
                  secondary: Color(0xFFFFA552),
                ),
              ),
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 1000),
                  textScaler: TextScaler.linear(scale),
                ),
                child: RepaintBoundary(
                  key: boundary,
                  child: Scaffold(body: entry.value),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pump();
        expect(tester.takeException(), isNull);
        if (entry.key.endsWith('detail')) {
          final fullTitle = tester.widget<Text>(find.text(_title).first);
          expect(fullTitle.maxLines, isNull);
          expect(fullTitle.overflow, TextOverflow.visible);
        }
        final output = Platform.environment['REMEDIATION_RENDER_DIR'];
        if (output != null) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory(output).create(recursive: true);
            await File(
              '$output/${entry.key}-${width.toInt()}-$locale-${scale.toStringAsFixed(1)}.png',
            ).writeAsBytes(png!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 5));
      });
    }
  }
}
