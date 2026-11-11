import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../helpers/keyboard_acceptance.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:twoalogisticcabineuser/src/core/ui/blurred_modal_bottom_sheet.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_input_decoration.dart';
import 'package:twoalogisticcabineuser/src/features/garage/domain/garage_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/auth_provider.dart';
import 'package:twoalogisticcabineuser/src/features/self_buyout/data/self_buyout_models.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/garage/application/garage_providers.dart';
import 'package:twoalogisticcabineuser/src/features/more/presentation/more_sheet.dart';
import 'package:twoalogisticcabineuser/src/features/partner_program/data/client_partner_program_provider.dart';
import 'package:twoalogisticcabineuser/src/features/profile/data/profile_provider.dart';
import 'package:twoalogisticcabineuser/src/features/self_buyout/data/self_buyout_service.dart';

class _MenuAuth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    isLoggedIn: true,
    isLoading: false,
    clientId: 41,
    userDomain: 'synthetic.test',
  );
}

class _MenuApi implements ApiClient {
  int tokenReads = 0;
  @override
  String get activeBaseUrl => 'https://synthetic.test/api';
  @override
  Future<String?> getToken() async {
    tokenReads++;
    return 'synthetic-token';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No network expected');
}

const _destinations = <String, List<String>>{
  '/payment-chat': ['Чат по оплатам', 'оплатить', '账单'],
  '/support': ['Чат поддержки', 'менеджеру', '客服'],
  '/self-buyout': ['Самовыкуп', 'самостоятельный выкуп', '自助采购'],
  '/garage': ['Гараж', 'запчасти', '汽配'],
  '/purchase-blanks': ['Выкуп по бланку', 'бланки', '采购单'],
  '/sp-finance': ['Совместные покупки', 'закупки совместные', '团购'],
  '/search-nocode': ['Поиск трека без кода', 'потерянный трек', '未认领'],
  '/tariffs': ['Тарифы', 'тарифах', '运费'],
  '/calculator': ['Калькулятор', 'сборки расчёт', '计算器'],
  '/training': ['Обучение', 'инструкции', '使用说明'],
  '/profile': ['Профиль', 'личные данные', '个人资料'],
  '/referral': ['Реферальная программа', 'пригласить друга', '邀请好友'],
  '/partner-program': ['Партнёрская программа', 'комиссию', '合作伙伴'],
  '/news': ['Новости', 'объявления', '新闻'],
  '/rules': ['Правила', 'оферта', '条款'],
};
Future<GoRouter> _pumpMenu(
  WidgetTester tester,
  TargetPlatform platform,
  double width, {
  bool services = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, width == 320 ? 640 : 844);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: TextButton(
            onPressed: () => showBlurredModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const MoreSheet(screenTranslationEnabled: false),
            ),
            child: const Text('Open menu'),
          ),
        ),
      ),
      for (final route in _destinations.keys)
        GoRoute(
          path: route,
          builder: (context, state) =>
              Scaffold(body: Text('Destination ${state.uri.path}')),
        ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(_MenuApi()),
        authProvider.overrideWith(_MenuAuth.new),
        activeClientCodeProvider.overrideWithValue(null),
        clientProfileProvider.overrideWithValue(const AsyncData(null)),
        selfBuyoutAvailabilityProvider.overrideWithValue(
          AsyncData(
            SelfBuyoutAvailability(
              available: services,
              firstExchangeActive: false,
              showFirstExchangeOnboarding: false,
              requiresAlipayExperienceAnswer: false,
            ),
          ),
        ),
        garageAvailabilityProvider.overrideWithValue(
          AsyncData(
            GarageAvailability(
              available: services,
              reason: null,
              processorAgentId: null,
              vinLookupConfigured: false,
            ),
          ),
        ),
        clientPartnerProgramProvider.overrideWithValue(
          AsyncData(
            services
                ? ClientPartnerProgramData.fromJson({
                    'active': true,
                    'partner': {'code': 'FAKE'},
                  })
                : null,
          ),
        ),
      ],
      child: MaterialApp.router(
        theme: ThemeData(fontFamily: 'Gilroy', platform: platform),
        routerConfig: router,
        builder: (_, child) => AppKeyboardDismissRegion(child: child!),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _finish(WidgetTester tester, GoRouter router) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  router.dispose();
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
  tester.view.resetViewInsets();
}

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final width in [320.0, 390.0]) {
      testWidgets(
        'actual menu each destination has RU ZH aliases and correct navigation ${platform.name} $width',
        (tester) async {
          final router = await _pumpMenu(tester, platform, width);
          for (final entry in _destinations.entries) {
            for (final query in entry.value.skip(1)) {
              router.go('/');
              await tester.pumpAndSettle();
              await tester.tap(find.text('Open menu'));
              await tester.pumpAndSettle();
              final search = find.descendant(
                of: find.byKey(const ValueKey('more-menu-search')),
                matching: find.byType(TextField),
              );
              await tester.enterText(search, query);
              await tester.pumpAndSettle();
              final item = find.text(entry.value.first);
              expect(item, findsOneWidget, reason: '$query => ${entry.key}');
              await tester.ensureVisible(item);
              await tester.tap(item);
              await tester.pumpAndSettle();
              expect(
                router.routerDelegate.currentConfiguration.last.matchedLocation,
                entry.key,
              );
              expect(find.text('Destination ${entry.key}'), findsOneWidget);
            }
          }
          expect(tester.takeException(), isNull);
          await _finish(tester, router);
        },
      );
    }
    testWidgets(
      'hidden services never appear through aliases and IME clear/done preserve search ${platform.name}',
      (tester) async {
        final router = await _pumpMenu(tester, platform, 320, services: false);
        await tester.tap(find.text('Open menu'));
        await tester.pumpAndSettle();
        final search = find.descendant(
          of: find.byKey(const ValueKey('more-menu-search')),
          matching: find.byType(TextField),
        );
        for (final query in [
          'alipay',
          '自助采购',
          '汽配',
          'комиссию',
          '合作伙伴',
          '屏幕翻译',
          'Диагностика сети',
          'Сообщить о проблеме',
          '网络诊断',
          '反馈问题',
        ]) {
          await tester.enterText(search, query);
          await tester.pumpAndSettle();
          for (final title in [
            'Самовыкуп',
            'Гараж',
            'Партнёрская программа',
            'Переводчик',
          ]) {
            expect(find.text(title), findsNothing);
          }
        }
        await tester.enterText(search, 'расчет');
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final editor = find.descendant(
          of: search,
          matching: find.byType(EditableText),
        );
        expectFocusedCaretAboveIme(tester, editor, keyboardTop: 360);
        expect(
          find.ancestor(
            of: search,
            matching: find.byType(AppOutlinedInputFrame),
          ),
          findsOneWidget,
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(tester.widget<EditableText>(editor).focusNode.hasFocus, isFalse);
        expect(tester.widget<TextField>(search).controller!.text, 'расчет');
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Очистить поиск'));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(search).controller!.text, isEmpty);
        expect(find.text('Калькулятор'), findsOneWidget);
        expect(find.text('Профиль'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _finish(tester, router);
      },
    );
  }
}
