import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/ui/tutorial_card.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/partner_link_provider.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/passkey_auth_service.dart';
import 'package:twoalogisticcabineuser/src/features/auth/presentation/login_screen.dart';
import 'package:twoalogisticcabineuser/src/features/tariffs/data/tariffs_provider.dart';
import 'package:twoalogisticcabineuser/src/features/tariffs/presentation/tariffs_screen.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_target.dart';

class _IdlePartner extends PartnerLinkNotifier {
  @override
  PartnerLinkState build() =>
      const PartnerLinkState(phase: PartnerLinkPhase.idle);
}

class _NoPasskeys implements PasskeyAuthService {
  @override
  Future<bool> isAvailable() async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No authentication expected');
}

final _mixed = UserDeliveryTariff.fromJson({
  'id': 1,
  'name': 'Тариф по плотности',
  'pricingType': 'density',
  'baseCost': 0.01,
  'weightTiers': [
    {'minWeight': 999, 'pricePerKg': 0.001},
  ],
  'densityTiers': [
    {
      'minDensity': 0,
      'maxDensity': 100,
      'clientPricePerKg': 1,
      'clientPricePerM3': 80,
    },
    {'minDensity': 100, 'maxDensity': 200, 'clientPricePerKg': 4},
    {'minDensity': 200, 'clientPricePerKg': 3},
  ],
});

const _weight = UserDeliveryTariff(
  id: 2,
  name: 'Весовой тариф',
  baseCost: 2,
  weightTiers: [UserWeightTier(minWeight: 10, maxWeight: 20, pricePerKg: 3)],
);

Future<void> _pump(
  WidgetTester tester,
  UserDeliveryTariff tariff, {
  bool public = false,
  String locale = 'ru',
  double width = 390,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userTariffsProvider.overrideWith(
          (_) async => UserTariffsData(deliveryTariffs: [tariff]),
        ),
        publicDefaultTariffsProvider.overrideWith((_) async => [tariff]),
        partnerLinkProvider.overrideWith(_IdlePartner.new),
        passkeyAuthServiceProvider.overrideWithValue(_NoPasskeys()),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        supportedLocales: const [Locale('ru'), Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: public ? const LoginScreen() : const TariffsScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
  if (!public) {
    final expand = find.text(locale == 'zh' ? '区间及费率' : 'Диапазоны и ставки');
    if (expand.evaluate().isNotEmpty) {
      await tester.ensureVisible(expand);
      await tester.tap(expand);
      await tester.pump(const Duration(milliseconds: 400));
    }
  }
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // Login's existing delayed animation/passkey checks must finish after dispose.
  await tester.pump(const Duration(seconds: 10));
}

void main() {
  testWidgets('complete-product tariff never claims that data is optional', (
    tester,
  ) async {
    await _pump(
      tester,
      UserDeliveryTariff.fromJson({
        'id': 1,
        'name': 'Фото обязательно',
        'baseCost': 2,
        'requiresProductInfo': false,
        'requiresCompleteProductInfo': true,
      }),
    );
    expect(find.text('Нужны данные о товаре'), findsOneWidget);
    expect(find.text('Без данных о товаре'), findsNothing);
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });

  setUpAll(() async {
    await (FontLoader('Gilroy')
          ..addFont(rootBundle.load('assets/fonts/gilroy/Gilroy-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/gilroy/Gilroy-Bold.ttf')))
        .load();
  });

  testWidgets(
    'mixed density rows and badge show each unit without legacy weight prices',
    (tester) async {
      await _pump(tester, _mixed);
      expect(find.text('Диапазоны плотности'), findsOneWidget);
      expect(find.text('0 – 100 кг/м³'), findsOneWidget);
      expect(find.text('от 200 кг/м³'), findsOneWidget);
      expect(find.text('\$80 / м³'), findsOneWidget);
      expect(find.text('\$3 / кг'), findsOneWidget);
      expect(find.text('от \$3'), findsOneWidget);
      expect(find.text('от \$80'), findsOneWidget);
      expect(find.text('за кг'), findsOneWidget);
      expect(find.text('за м³'), findsOneWidget);
      expect(find.text('Весовые диапазоны'), findsNothing);
      expect(find.text('\$0.01'), findsNothing);
      expect(find.text('от 999 кг'), findsNothing);
      final tutorial = tester.widget<TutorialScreenWrapper>(
        find.byType(TutorialScreenWrapper),
      );
      expect(tutorial.steps[0].description, contains('1 м³'));
      expect(tutorial.steps[1].description, contains('вес ÷ объём'));
      expect(tutorial.steps[1].description, isNot(contains('Чем тяжелее')));
      final name = find.byWidgetPredicate(
        (w) => w is TrainingTarget && w.id == 'tariffs.name',
      );
      expect(name, findsOneWidget);
      expect(tester.getRect(name), tester.getRect(find.text(_mixed.name)));
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    },
  );

  testWidgets(
    'zero prices, a closed zero bound and absent price are distinct',
    (tester) async {
      final tariff = UserDeliveryTariff.fromJson({
        'pricingType': 'density',
        'name': 'Нулевые ставки',
        'baseCost': 55,
        'densityTiers': [
          {'minDensity': 0, 'maxDensity': 0, 'clientPricePerKg': 0},
          {
            'minDensity': 100,
            'maxDensity': 200,
            'clientPricePerKg': 5,
            'clientPricePerM3': 0,
          },
          {'minDensity': 200},
        ],
      });
      await _pump(tester, tariff);
      expect(find.text('0 – 0 кг/м³'), findsOneWidget);
      expect(find.text('\$0 / кг'), findsOneWidget);
      expect(find.text('\$0 / м³'), findsOneWidget);
      expect(find.text('от \$0'), findsNWidgets(2));
      expect(find.text('Цена не указана'), findsOneWidget);
      expect(find.text('\$55'), findsNothing);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    },
  );

  testWidgets(
    'density without configured rates does not present baseCost as per kg',
    (tester) async {
      await _pump(
        tester,
        const UserDeliveryTariff(
          id: 1,
          name: 'Без ставок',
          baseCost: 55,
          pricingType: 'density',
        ),
      );
      expect(find.text('Цена не указана'), findsOneWidget);
      expect(find.text('Диапазоны не настроены'), findsOneWidget);
      expect(find.text('за кг'), findsNothing);
      expect(find.text('\$55'), findsNothing);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    },
  );

  testWidgets(
    'weight card keeps baseCost minimum, rows, and original weight tutorial',
    (tester) async {
      await _pump(tester, _weight);
      expect(find.text('от \$2'), findsOneWidget);
      expect(find.text('10 – 20 кг'), findsOneWidget);
      expect(find.text('\$3 / кг'), findsOneWidget);
      expect(find.text('Весовые диапазоны'), findsOneWidget);
      expect(find.text('Диапазоны плотности'), findsNothing);
      final tutorial = tester.widget<TutorialScreenWrapper>(
        find.byType(TutorialScreenWrapper),
      );
      expect(tutorial.steps[1].description, contains('Чем тяжелее партия'));
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    },
  );

  for (final locale in ['ru', 'zh']) {
    testWidgets('mixed density fits a 320px viewport in $locale', (
      tester,
    ) async {
      await _pump(tester, _mixed, locale: locale, width: 320);
      final ru = locale == 'ru';
      expect(find.text(ru ? 'Диапазоны плотности' : '密度区间'), findsOneWidget);
      expect(find.text(ru ? '0 – 100 кг/м³' : '0 – 100 kg/m³'), findsOneWidget);
      expect(find.text(ru ? '\$80 / м³' : '\$80 / m³'), findsOneWidget);
      expect(find.text(ru ? 'за м³' : '每立方米'), findsOneWidget);
      expect(find.text(ru ? 'за кг' : '每千克'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });
  }

  for (final locale in ['ru', 'zh']) {
    for (final density in [false, true]) {
      testWidgets(
        'branded tariff ranges reuse app surface and typography320 $locale density=$density',
        (tester) async {
          await _pump(
            tester,
            density ? _mixed : _weight,
            locale: locale,
            width: 320,
          );
          final tile = find.byType(ExpansionTile);
          expect(tile, findsOneWidget);
          final title = tester.widget<Text>(
            find.descendant(of: tile, matching: find.byType(Text)).first,
          );
          expect(title.style?.fontFamily, 'Gilroy');
          expect(title.style?.fontWeight, FontWeight.w900);
          final surface =
              tester
                      .widget<Container>(
                        find
                            .ancestor(
                              of: tile,
                              matching: find.byType(Container),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration;
          expect(surface.color, const Color(0xFFF8FAFC));
          expect(surface.borderRadius, BorderRadius.circular(18));
          final rangeLabel = density
              ? (locale == 'ru' ? '0 – 100 кг/м³' : '0 – 100 kg/m³')
              : (locale == 'ru' ? '10 – 20 кг' : '10 – 20 kg');
          final label = find.text(rangeLabel);
          expect(label, findsOneWidget);
          await tester.ensureVisible(label);
          await tester.pump();
          expect(tester.getSize(label).width, greaterThan(0));
          final toggle = find.text(
            locale == 'ru' ? 'Диапазоны и ставки' : '区间及费率',
          );
          await tester.ensureVisible(toggle);
          await tester.tap(toggle);
          await tester.pump(const Duration(milliseconds: 400));
          expect(label, findsNothing);
          await tester.tap(toggle);
          await tester.pump(const Duration(milliseconds: 400));
          expect(label, findsOneWidget);
          expect(tester.takeException(), isNull);
          await _dispose(tester);
        },
      );
    }
  }

  for (final locale in ['ru', 'zh']) {
    testWidgets('consolidated base-only price clearly says from $locale', (
      tester,
    ) async {
      await _pump(
        tester,
        const UserDeliveryTariff(id: 7, name: 'Сборный груз', baseCost: 2.5),
        locale: locale,
        width: 320,
      );
      expect(find.text(locale == 'ru' ? 'от \$2.5' : '\$2.5起'), findsOneWidget);
      expect(find.text('\$2.5'), findsNothing);
      expect(find.byType(ExpansionTile), findsNothing);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });
  }

  testWidgets('public Chinese preview retains a zero m3 price and its unit', (
    tester,
  ) async {
    await _pump(
      tester,
      const UserDeliveryTariff(
        id: 1,
        name: '免费运价',
        baseCost: 55,
        pricingType: 'density',
        densityTiers: [
          UserDensityTier(
            minDensity: 0,
            clientPricePerKg: 5,
            clientPricePerM3: 0,
          ),
        ],
      ),
      public: true,
      locale: 'zh',
      width: 320,
    );
    expect(find.text('\$0/m³起'), findsOneWidget);
    expect(find.text('\$5/kg起'), findsNothing);
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });

  testWidgets(
    'public preview keeps mixed units separately on a narrow screen',
    (tester) async {
      await _pump(tester, _mixed, public: true, width: 320);
      final prices = find.text('от \$3/кг\nот \$80/м³');
      expect(prices, findsOneWidget);
      await tester.ensureVisible(prices);
      await tester.pump();
      expect(tester.getSize(prices).width, lessThan(150));
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    },
  );

  testWidgets(
    'public preview never labels pure m3 or missing density prices as per kg',
    (tester) async {
      final volumetric = UserDeliveryTariff(
        id: 1,
        name: 'Объём',
        baseCost: 55,
        pricingType: 'density',
        densityTiers: const [
          UserDensityTier(minDensity: 0, clientPricePerM3: 80),
        ],
      );
      await _pump(tester, volumetric, public: true);
      expect(find.text('от \$80/м³'), findsOneWidget);
      expect(find.text('от \$55/кг'), findsNothing);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
      await _pump(
        tester,
        const UserDeliveryTariff(
          id: 3,
          name: 'Не настроен',
          baseCost: 55,
          pricingType: 'density',
        ),
        public: true,
      );
      expect(find.text('Цена не указана'), findsOneWidget);
      expect(find.text('от \$55/кг'), findsNothing);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    },
  );

  testWidgets('public weight preview retains its tiers-first minimum', (
    tester,
  ) async {
    await _pump(tester, _weight, public: true);
    expect(find.text('от \$3/кг'), findsOneWidget);
    expect(find.text('от \$2/кг'), findsNothing);
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });
}
