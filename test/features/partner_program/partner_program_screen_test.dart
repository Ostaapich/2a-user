import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_target.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/features/partner_program/data/client_partner_program_provider.dart';
import 'package:twoalogisticcabineuser/src/features/partner_program/presentation/partner_program_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'tutorial_partner_program': true});
  });

  test('разбирает статистику и выплаты без потери валюты', () {
    final program = ClientPartnerProgramData.fromJson(_programJson);

    expect(program.registeredCount, 9);
    expect(program.awaitingWeightKg, 45.75);
    expect(program.paidWeightKg, 18.25);
    expect(program.availableUsd, 12.5);
    expect(program.payableUsd, 17.5);
    expect(program.paidUsd, 20);
    expect(program.payouts.single.paidAmountUsd, 20);
  });

  test('считает доступную выплату как available плюс reserved без payable', () {
    final json = Map<String, dynamic>.from(_programJson);
    json['totals'] = Map<String, dynamic>.from(
      _programJson['totals'] as Map<String, dynamic>,
    )..remove('payableUsd');

    final program = ClientPartnerProgramData.fromJson(json);

    expect(program.availableUsd, 12.5);
    expect(program.reservedUsd, 5);
    expect(program.payableUsd, 17.5);
  });

  testWidgets('показывает отдельную партнёрскую страницу на ширине 320 px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpProgram(tester, ClientPartnerProgramData.fromJson(_programJson));

    expect(find.text('Партнёрская программа'), findsOneWidget);
    expect(find.text('Ваш партнёрский кабинет'), findsNothing);
    expect(find.textContaining('Код партнёра'), findsNothing);
    expect(find.text('Активна'), findsNothing);
    expect(find.text('Партнёрский префикс'), findsOneWidget);
    expect(find.text('Доступно к выплате'), findsOneWidget);
    expect(find.text('PA'), findsWidgets);
    expect(find.textContaining('За всё время'), findsNothing);
    expect(find.text('9 клиентов'), findsNothing);
    expect(find.text(r'$17.50'), findsWidgets);
    expect(find.text('Ссылка приглашения'), findsOneWidget);
    expect(
      find.text('https://api.test/client-partner/invite/token'),
      findsNothing,
    );
    expect(find.textContaining('ABCDEFGH'), findsNothing);
    expect(find.text('Копировать ссылку'), findsOneWidget);
    final inviteTarget = find.byWidgetPredicate(
      (widget) => widget is TrainingTarget && widget.id == 'partner.invite',
    );
    expect(inviteTarget, findsOneWidget);
    final copyButton = find.descendant(
      of: inviteTarget,
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    expect(copyButton, findsOneWidget);
    expect(tester.getRect(inviteTarget), tester.getRect(copyButton));
    expect(tester.getSize(inviteTarget).height, lessThanOrEqualTo(60));
    expect(find.text('Поделиться'), findsNothing);
    expect(find.byIcon(Icons.ios_share_rounded), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Зарегистрировано'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Зарегистрировано'), findsOneWidget);
    expect(find.text('Ожидают отправки'), findsOneWidget);
    expect(find.text('45.750 кг'), findsOneWidget);
    expect(find.text('Оплачено'), findsOneWidget);
    expect(find.text('18.250 кг'), findsOneWidget);
    expect(find.text('Выплачено'), findsWidgets);
    expect(find.text('Ставка'), findsOneWidget);
    expect(find.text('0.2500 USD/кг'), findsOneWidget);
    expect(find.text('Условия начисления'), findsNothing);
    expect(find.text('Оплатили счета'), findsNothing);
    expect(find.text('Конверсия'), findsNothing);
    expect(find.text('Ожидает выплаты'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('локализует страницу для китайского интерфейса', (tester) async {
    await _pumpProgram(
      tester,
      ClientPartnerProgramData.fromJson(_programJson),
      locale: const Locale('zh'),
    );

    expect(find.text('合作伙伴计划'), findsOneWidget);
    expect(find.text('您的合作伙伴中心'), findsNothing);
    expect(find.text('合作伙伴前缀'), findsOneWidget);
    expect(find.text('可提现金额'), findsOneWidget);
    expect(find.text('PA'), findsWidgets);
    expect(find.text('邀请链接'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('已注册'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('已注册'), findsOneWidget);
    expect(find.text('待发货重量'), findsOneWidget);
    expect(find.text('45.750 公斤'), findsOneWidget);
    expect(find.text('已付款重量'), findsOneWidget);
    expect(find.text('18.250 公斤'), findsOneWidget);
    expect(find.text('已支付'), findsWidgets);
    expect(find.text('费率'), findsOneWidget);
    expect(find.text('佣金规则'), findsNothing);
  });

  testWidgets('показывает нейтральное состояние обычному клиенту', (
    tester,
  ) async {
    await _pumpProgram(tester, null);

    expect(find.text('Партнёрская программа не подключена'), findsOneWidget);
  });
}

Future<void> _pumpProgram(
  WidgetTester tester,
  ClientPartnerProgramData? data, {
  Locale locale = const Locale('ru'),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clientPartnerProgramProvider.overrideWith((ref) async => data),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('ru'), Locale('zh')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: PartnerProgramScreen()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpAndSettle();
}

final _programJson = <String, dynamic>{
  'active': true,
  'partner': {'id': 1, 'code': 'CP-10', 'name': 'Partner'},
  'invite': {
    'url': 'https://api.test/client-partner/invite/token',
    'shortCode': 'ABCDEFGH',
  },
  'prefix': {'id': 2, 'prefix': 'PA'},
  'rule': {'id': 3, 'rateUsdPerKg': '0.2500'},
  'stats': {
    'registeredCount': 9,
    'awaitingWeightKg': '45.750',
    'paidWeightKg': '18.250',
    'paidClientsCount': 4,
    'conversionPercent': '44.44',
  },
  'totals': {
    'availableUsd': '12.50',
    'reservedUsd': '5.00',
    'payableUsd': '17.50',
    'paidUsd': '20.00',
    'lifetimeEarnedUsd': '37.50',
  },
  'settlements': [
    {
      'id': 7,
      'status': 'paid',
      'periodFrom': '2026-08-01T00:00:00.000Z',
      'periodTo': '2026-09-01T00:00:00.000Z',
      'payableAmountUsd': '20.00',
      'paidAmountUsd': '20.00',
      'paidAt': '2026-09-03T00:00:00.000Z',
    },
  ],
};
