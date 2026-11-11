import 'package:twoalogisticcabineuser/src/features/screen_translation/presentation/screen_translation_section.dart';
import 'package:flutter/material.dart';
import 'package:twoalogisticcabineuser/src/features/shop/data/shop_availability_provider.dart';
import 'package:twoalogisticcabineuser/src/features/shell/presentation/desktop_side_nav.dart';
import 'package:twoalogisticcabineuser/src/features/clients/domain/client_codes_state.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/application/notifications_controller.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/domain/notification_item.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_target.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_colors.dart';
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

class _MenuCodes extends ClientCodesController {
  @override
  Future<ClientCodesState> build() async =>
      const ClientCodesState(codes: [], activeCode: null);
}

class _MenuNotifications extends NotificationsController {
  @override
  Future<List<NotificationItem>> build() async => const [];
}

void main() {
  testWidgets('search finds grouped service and preserves its navigation', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) =>
                    const MoreSheet(screenTranslationEnabled: false),
              ),
              child: const Text('Open menu'),
            ),
          ),
        ),
        GoRoute(
          path: '/calculator',
          builder: (context, state) =>
              const Scaffold(body: Text('Calculator opened')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(_MenuApi()),
          authProvider.overrideWith(_MenuAuth.new),
          activeClientCodeProvider.overrideWithValue(null),
          clientProfileProvider.overrideWithValue(const AsyncData(null)),
          selfBuyoutAvailabilityProvider.overrideWithValue(
            const AsyncLoading(),
          ),
          garageAvailabilityProvider.overrideWithValue(const AsyncLoading()),
          clientPartnerProgramProvider.overrideWithValue(const AsyncData(null)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('Open menu'));
    await tester.pumpAndSettle();
    for (final title in [
      'Обучение',
      'Профиль',
      'Реферальная программа',
      'Выкуп по бланку',
      'Совместные покупки',
      'Поиск трека без кода',
      'Новости',
      'Правила',
      'Тарифы',
      'Калькулятор',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Диагностика сети'), findsNothing);
    expect(find.text('Сообщить о проблеме'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('more-menu-search')),
      'расчет',
    );
    await tester.pumpAndSettle();
    expect(find.text('Калькулятор'), findsOneWidget);
    expect(find.text('Профиль'), findsNothing);
    expect(find.text('Чат поддержки'), findsNothing);
    await tester.ensureVisible(find.text('Калькулятор'));
    await tester.tap(find.text('Калькулятор'));
    await tester.pumpAndSettle();
    expect(find.text('Calculator opened'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      '/calculator',
    );
  });

  testWidgets(
    'desktop menu removes report and diagnostics but preserves support and update',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(
              body: Row(
                children: [
                  SizedBox(width: 280, child: DesktopSideNav()),
                  Expanded(child: SizedBox()),
                ],
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(_MenuApi()),
            authProvider.overrideWith(_MenuAuth.new),
            clientCodesControllerProvider.overrideWith(_MenuCodes.new),
            shopAvailabilityProvider.overrideWithValue(const AsyncLoading()),
            notificationsControllerProvider.overrideWith(
              _MenuNotifications.new,
            ),
            activeClientCodeProvider.overrideWithValue(null),
            selfBuyoutAvailabilityProvider.overrideWithValue(
              const AsyncLoading(),
            ),
            garageAvailabilityProvider.overrideWithValue(const AsyncLoading()),
            clientPartnerProgramProvider.overrideWithValue(
              const AsyncData(null),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      for (final title in [
        'Диагностика',
        'Диагностика сети',
        'Проблема',
        'Сообщить о проблеме',
      ]) {
        expect(find.text(title), findsNothing);
      }
      expect(
        find.byWidgetPredicate(
          (widget) => widget is TrainingTarget && widget.id == 'menu.report',
        ),
        findsNothing,
      );
      expect(find.text('Поддержка'), findsOneWidget);
      expect(find.text('Обновление'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      router.dispose();
    },
  );

  group('shouldShowManualUpdateMenu', () {
    test('shows update check for direct Android builds', () {
      expect(
        shouldShowManualUpdateMenu(
          isAndroid: true,
          isRustoreDistribution: false,
        ),
        isTrue,
      );
    });

    test('hides update check for RuStore Android builds', () {
      expect(
        shouldShowManualUpdateMenu(
          isAndroid: true,
          isRustoreDistribution: true,
        ),
        isFalse,
      );
    });

    test('hides update check outside Android', () {
      expect(
        shouldShowManualUpdateMenu(
          isAndroid: false,
          isRustoreDistribution: false,
        ),
        isFalse,
      );
    });
  });

  testWidgets(
    'iOS 26 hides translator; iOS 27 shows it beside self-buyout and keeps session owner mounted',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const channel = MethodChannel('com.twoalogistic.user/screen_translation');
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      var iosVersion = '26.9';
      final api = _MenuApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            screenTranslationIOSVersionProvider.overrideWith(
              (ref) async => iosVersion,
            ),
            apiClientProvider.overrideWithValue(api),
            authProvider.overrideWith(_MenuAuth.new),
            activeClientCodeProvider.overrideWithValue(null),
            clientProfileProvider.overrideWithValue(const AsyncData(null)),
            selfBuyoutAvailabilityProvider.overrideWithValue(
              const AsyncData(
                SelfBuyoutAvailability(
                  available: true,
                  firstExchangeActive: false,
                  showFirstExchangeOnboarding: false,
                  requiresAlipayExperienceAnswer: false,
                ),
              ),
            ),
            garageAvailabilityProvider.overrideWithValue(const AsyncLoading()),
            clientPartnerProgramProvider.overrideWithValue(
              const AsyncData(null),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: MoreSheet(screenTranslationEnabled: true)),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Переводчик'), findsNothing);
      expect(api.tokenReads, 0);
      expect(calls, isEmpty);
      iosVersion = '27.0';
      ProviderScope.containerOf(
        tester.element(find.byType(MoreSheet)),
      ).invalidate(screenTranslationIOSVersionProvider);
      await tester.pump();
      await tester.pump();
      final selfBuyout = tester.getCenter(find.text('Самовыкуп'));
      final translator = tester.getCenter(find.text('Переводчик'));
      expect(translator.dx, greaterThan(selfBuyout.dx));
      expect(translator.dy, closeTo(selfBuyout.dy, 0.1));
      expect(api.tokenReads, 0);
      expect(calls, isEmpty);
      await tester.tap(find.text('Переводчик'));
      await tester.pump();
      expect(find.byType(MoreSheet), findsOneWidget);
      expect(api.tokenReads, 1);
      expect(calls.map((call) => call.method), ['present']);
      expect(calls.single.arguments, {
        'endpoint': 'https://synthetic.test/api/screen-translate/v1',
        'accessToken': 'synthetic-token',
        'appearance': {
          'primary': Theme.of(
            tester.element(find.byType(MoreSheet)),
          ).colorScheme.primary.toARGB32(),
          'secondary': Theme.of(
            tester.element(find.byType(MoreSheet)),
          ).colorScheme.secondary.toARGB32(),
          'gradientStart': tester
              .element(find.byType(MoreSheet))
              .brandGradient
              .colors
              .first
              .toARGB32(),
          'language': 'en',
        },
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(calls.map((call) => call.method), ['present', 'stop']);
      await tester.pump(const Duration(seconds: 10));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'Android hides translator even when enabled without auth API or channel access',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const channel = MethodChannel('com.twoalogistic.user/screen_translation');
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWith(
              (ref) =>
                  throw StateError('Disabled translator must not read API'),
            ),
            authProvider.overrideWith(
              () => throw StateError('Disabled translator must not read auth'),
            ),
            activeClientCodeProvider.overrideWithValue(null),
            clientProfileProvider.overrideWithValue(const AsyncData(null)),
            selfBuyoutAvailabilityProvider.overrideWithValue(
              const AsyncLoading(),
            ),
            garageAvailabilityProvider.overrideWithValue(const AsyncLoading()),
            clientPartnerProgramProvider.overrideWithValue(
              const AsyncData(null),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: MoreSheet(screenTranslationEnabled: true)),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Переводчик'), findsNothing);
      expect(find.byIcon(Icons.translate_rounded), findsNothing);
      expect(find.text('Калькулятор'), findsOneWidget);
      expect(calls, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(calls, isEmpty);
      await tester.pump(const Duration(seconds: 10));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('shows the calculator entry in More', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeClientCodeProvider.overrideWithValue(null),
          clientProfileProvider.overrideWithValue(const AsyncData(null)),
          selfBuyoutAvailabilityProvider.overrideWithValue(
            const AsyncLoading(),
          ),
          garageAvailabilityProvider.overrideWithValue(const AsyncLoading()),
          clientPartnerProgramProvider.overrideWithValue(const AsyncData(null)),
        ],
        child: const MaterialApp(home: Scaffold(body: MoreSheet())),
      ),
    );

    expect(find.text('Калькулятор'), findsOneWidget);
    expect(find.text('Предварительный расчёт сборки'), findsOneWidget);
    expect(find.byIcon(Icons.calculate_rounded), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });
}
