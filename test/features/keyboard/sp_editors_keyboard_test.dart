import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_v2_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_v2_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/presentation/sp_v2_purchase_detail_screen.dart';
import 'keyboard_form_probe.dart';
import '../../helpers/keyboard_acceptance.dart';

const _customer = SpV2Customer(id: 3, fullName: 'Участник теста');
const _purchase = SpV2Purchase(
  id: 7,
  title: 'Тестовая закупка',
  status: 'open',
  statusLabel: 'Открыта',
  isAcceptingItems: true,
  purchaseRate: 12,
  items: [
    SpV2Item(
      id: 17,
      title: 'Тестовый товар',
      status: 'requested',
      statusLabel: 'Запрошен',
      quantity: 1,
      purchasePriceYuan: 10,
      customer: _customer,
    ),
  ],
);
const _capabilities = SpOrganizerCapabilities(
  contractVersion: 1,
  organizerV2: true,
  purchaseKinds: true,
  participants: false,
  products: false,
  calculationProfiles: false,
  fulfillmentOverview: false,
  selfBuyoutLinks: false,
  selfBuyout: SpOrganizerActionCapability.unavailable,
  garageImport: false,
  trackLinks: false,
  assemblyLinks: false,
  invoiceLinks: false,
  analytics: false,
);

Future<void> _host(WidgetTester tester, TargetPlatform platform) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 640);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        spV2PurchaseDetailProvider.overrideWith((ref, id) async => _purchase),
        spV2CustomersProvider.overrideWith((ref) async => [_customer]),
        spOrganizerCapabilitiesProvider.overrideWith(
          (ref) async => _capabilities,
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(platform: platform),
        builder: (_, child) => AppKeyboardDismissRegion(child: child!),
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: const Scaffold(body: SpV2PurchaseDetailScreen(purchaseId: 7)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text('Тестовая закупка'), findsOneWidget);
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  final routeScroll = find
      .byElementPredicate(
        (element) =>
            element.widget is Scrollable &&
            ModalRoute.of(element)?.isCurrent == true &&
            (element.widget as Scrollable).axisDirection == AxisDirection.down,
      )
      .first;
  tester.state<ScrollableState>(routeScroll).position.jumpTo(0);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.scrollUntilVisible(
    target,
    160,
    scrollable: find
        .byElementPredicate(
          (element) =>
              element.widget is Scrollable &&
              ModalRoute.of(element)?.isCurrent == true &&
              (element.widget as Scrollable).axisDirection ==
                  AxisDirection.down,
        )
        .first,
    maxScrolls: 40,
  );
  await tester.ensureVisible(target);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      '$platform SP edit purchase all fields with 320px available height',
      (tester) async {
        await _host(tester, platform);
        await _tap(tester, find.byTooltip('Изменить закупку'));
        expect(await probeCurrentFormEditors(tester, minimumFields: 2), 2);
      },
    );
    testWidgets('$platform SP add item fields with 320px available height', (
      tester,
    ) async {
      await _host(tester, platform);
      await _tap(tester, find.widgetWithText(FilledButton, 'Добавить товар'));
      for (final title in [
        'Контакты участника',
        'Параметры и комментарий',
        'Доставка',
      ]) {
        await _tap(tester, find.text(title));
      }
      expect(await probeCurrentFormEditors(tester, minimumFields: 14), 14);
    });
    testWidgets('$platform SP edit item every enabled field320height', (
      tester,
    ) async {
      await _host(tester, platform);
      await _tap(tester, find.text('Тестовый товар'));
      final count = await probeCurrentFormEditors(tester, minimumFields: 11);
      debugPrint('SP_EDIT_ITEM_FIELDS=$count');
    });
    testWidgets('$platform SP bulk price percent/fixed fields320height', (
      tester,
    ) async {
      await _host(tester, platform);
      await _tap(tester, find.text('Массовые действия'));
      await _tap(tester, find.text('Рассчитать цены клиента'));
      for (final option in ['Добавить процент', 'Добавить фиксированно']) {
        await _tap(tester, find.text(option));
        expect(await probeCurrentFormEditors(tester), 1);
      }
    });
    testWidgets('$platform SP bulk delivery both fields320height', (
      tester,
    ) async {
      await _host(tester, platform);
      await _tap(tester, find.text('Массовые действия'));
      await _tap(tester, find.text('Рассчитать доставку'));
      expect(await probeCurrentFormEditors(tester, minimumFields: 2), 2);
    });
    testWidgets('$platform SP shipment all fields320height', (tester) async {
      await _host(tester, platform);
      await _tap(tester, find.text('Участники'));
      await _tap(tester, find.text('Участник теста').first);
      await _tap(tester, find.text('Отправка клиенту'));
      expect(await probeCurrentFormEditors(tester, minimumFields: 4), 4);
    });
    testWidgets('$platform SP edit item manual total branch320height', (
      tester,
    ) async {
      await _host(tester, platform);
      await _tap(tester, find.text('Тестовый товар'));
      await _tap(tester, find.text('Скорректировать'));
      expect(await probeCurrentFormEditors(tester, minimumFields: 13), 13);
    });
    testWidgets('$platform SP existing customer picker search320height', (
      tester,
    ) async {
      await _host(tester, platform);
      await _tap(tester, find.byKey(const ValueKey('sp-add-item-tab-action')));
      await _tap(
        tester,
        find.byKey(const ValueKey('add-item-existing-customer-mode')),
      );
      expect(await probeCurrentFormEditors(tester), 1);
    });
    testWidgets('$platform SP customer all contact fields320height', (
      tester,
    ) async {
      await _host(tester, platform);
      await _tap(tester, find.text('Участники'));
      await _tap(tester, find.text('Участник теста').first);
      await _tap(tester, find.text('Изменить').last);
      expect(await probeCurrentFormEditors(tester, minimumFields: 11), 11);
    });
    testWidgets('$platform SP rate field with 320px available height', (
      tester,
    ) async {
      await _host(tester, platform);
      await _tap(tester, find.text('Настройки'));
      await _tap(tester, find.text('Изменить').last);
      expect(await probeCurrentFormEditors(tester), 1);
    });
    testWidgets('$platform SP expense all fields with 320px available height', (
      tester,
    ) async {
      await _host(tester, platform);
      await _tap(tester, find.text('Финансы'));
      await _tap(tester, find.text('Добавить'));
      expect(await probeCurrentFormEditors(tester, minimumFields: 3), 3);
    });
  }
}
