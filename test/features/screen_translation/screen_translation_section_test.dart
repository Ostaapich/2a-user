import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/app/theme/app_theme.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_colors.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/auth_provider.dart';
import 'package:twoalogisticcabineuser/src/features/screen_translation/presentation/screen_translation_section.dart';

const _signedIn = AuthState(
  isLoggedIn: true,
  isLoading: false,
  clientId: 41,
  userDomain: 'synthetic-tenant.test',
);

class _Auth extends AuthNotifier {
  @override
  AuthState build() => _signedIn;

  void change(AuthState value) => state = value;
}

class _Api implements ApiClient {
  int tokenReads = 0;
  String base = 'https://synthetic-api.test/api/';
  Future<String?> Function() token = () async => 'synthetic-access-token';

  @override
  String get activeBaseUrl => base;

  @override
  Future<String?> getToken() {
    tokenReads++;
    return token();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected API use');
}

void iosTest(String name, WidgetTesterCallback callback) {
  testWidgets(
    name,
    callback,
    skip: kIsWeb,
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.twoalogistic.user/screen_translation');
  final calls = <MethodCall>[];
  Object? nativeResult;

  setUp(() {
    calls.clear();
    nativeResult = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return nativeResult;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<ProviderContainer> pump(
    WidgetTester tester,
    _Api api, {
    bool enabled = true,
    bool forbidProviders = false,
    String? iosVersion = '27.0',
    bool versionError = false,
    Locale locale = const Locale('ru'),
    ThemeData? theme,
  }) async {
    late BuildContext scopeContext;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          screenTranslationIOSVersionProvider.overrideWith((ref) async {
            if (versionError) throw StateError('Version unavailable');
            return iosVersion;
          }),
          apiClientProvider.overrideWith((ref) {
            if (forbidProviders) {
              throw StateError('API must stay uninitialized');
            }
            return api;
          }),
          authProvider.overrideWith(() {
            if (forbidProviders) {
              throw StateError('Auth must stay uninitialized');
            }
            return _Auth();
          }),
        ],
        child: MaterialApp(
          locale: locale,
          theme: theme,
          supportedLocales: const [Locale('ru'), Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                scopeContext = context;
                return ScreenTranslationSection(enabled: enabled);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(scopeContext);
  }

  Future<void> start(WidgetTester tester) async {
    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();
  }

  testWidgets('web initializes no providers even when enabled', (tester) async {
    final api = _Api();
    await pump(tester, api, forbidProviders: true);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(api.tokenReads, 0);
    expect(calls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(calls, isEmpty);
  }, skip: !kIsWeb);

  iosTest('flag off initializes no providers and sends no channel calls', (
    tester,
  ) async {
    final api = _Api();
    await pump(tester, api, enabled: false, forbidProviders: true);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(api.tokenReads, 0);
    expect(calls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(calls, isEmpty);
  });

  for (final version in ['26.9', '18.7', '', 'unknown', null]) {
    iosTest('unsupported iOS $version hides entry without auth or API', (
      tester,
    ) async {
      final api = _Api();
      await pump(tester, api, iosVersion: version, forbidProviders: true);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(api.tokenReads, 0);
      expect(calls, isEmpty);
    });
  }

  iosTest('version lookup failure hides entry without auth or API', (
    tester,
  ) async {
    await pump(tester, _Api(), versionError: true, forbidProviders: true);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(calls, isEmpty);
  });

  iosTest('iOS 28 remains supported', (tester) async {
    await pump(tester, _Api(), iosVersion: '28.0');
    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(calls, isEmpty);
  });

  iosTest('non-iOS initializes no providers and sends no channel calls', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final api = _Api();
    await pump(tester, api, forbidProviders: true);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(api.tokenReads, 0);
    expect(calls, isEmpty);
  });

  iosTest(
    'iOS presentation sends exact endpoint token and current appearance',
    (tester) async {
      final api = _Api();
      await pump(tester, api);
      expect(api.tokenReads, 0);
      expect(calls, isEmpty);
      await start(tester);
      expect(api.tokenReads, 1);
      expect(calls.single.method, 'present');
      expect(calls.single.arguments, {
        'endpoint': 'https://synthetic-api.test/api/screen-translate/v1',
        'accessToken': 'synthetic-access-token',
        'appearance': {
          'primary': Theme.of(
            tester.element(find.byType(ScreenTranslationSection)),
          ).colorScheme.primary.toARGB32(),
          'secondary': Theme.of(
            tester.element(find.byType(ScreenTranslationSection)),
          ).colorScheme.secondary.toARGB32(),
          'gradientStart': tester
              .element(find.byType(ScreenTranslationSection))
              .brandGradient
              .colors
              .first
              .toARGB32(),
          'language': 'ru',
        },
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(calls.map((call) => call.method), ['present', 'stop']);
    },
  );

  iosTest('Chinese text is localized and unopened logout has no stop', (
    tester,
  ) async {
    final container = await pump(tester, _Api(), locale: const Locale('zh'));
    expect(find.text('屏幕翻译'), findsNWidgets(2));
    (container.read(authProvider.notifier) as _Auth).change(
      const AuthState(isLoading: false),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(calls, isEmpty);
  });

  for (final entry in {
    'logout': const AuthState(isLoading: false),
    'client': const AuthState(
      isLoggedIn: true,
      clientId: 42,
      userDomain: 'synthetic-tenant.test',
    ),
    'domain': const AuthState(
      isLoggedIn: true,
      clientId: 41,
      userDomain: 'other-synthetic-tenant.test',
    ),
  }.entries) {
    iosTest('${entry.key} invalidates pending token before native call', (
      tester,
    ) async {
      final token = Completer<String?>();
      final api = _Api()..token = () => token.future;
      final container = await pump(tester, api);
      await start(tester);
      (container.read(authProvider.notifier) as _Auth).change(entry.value);
      token.complete('synthetic-access-token');
      await tester.pump();
      expect(calls, isEmpty);
    });

    iosTest('${entry.key} stops an owned session once', (tester) async {
      final container = await pump(tester, _Api());
      await start(tester);
      (container.read(authProvider.notifier) as _Auth).change(entry.value);
      await tester.pump();
      expect(calls.map((call) => call.method), ['present', 'stop']);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(calls.length, 2);
    });
  }

  iosTest('identity away and back still invalidates pending credentials', (
    tester,
  ) async {
    final token = Completer<String?>();
    final api = _Api()..token = () => token.future;
    final container = await pump(tester, api);
    await start(tester);
    final auth = container.read(authProvider.notifier) as _Auth;
    auth.change(const AuthState(isLoading: false));
    auth.change(_signedIn);
    token.complete('synthetic-access-token');
    await tester.pump();
    expect(calls, isEmpty);
  });

  iosTest('unrelated auth update does not stop a session', (tester) async {
    final container = await pump(tester, _Api());
    await start(tester);
    (container.read(authProvider.notifier) as _Auth).change(
      _signedIn.copyWith(clientName: 'Synthetic name'),
    );
    await tester.pump();
    expect(calls.map((call) => call.method), ['present']);
  });

  iosTest('dispose while loading token never opens native UI', (tester) async {
    final token = Completer<String?>();
    final api = _Api()..token = () => token.future;
    await pump(tester, api);
    await start(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    token.complete('synthetic-access-token');
    await tester.pump();
    expect(calls, isEmpty);
  });

  iosTest('missing token asks for login without native traffic', (
    tester,
  ) async {
    await pump(tester, _Api()..token = () async => null);
    await start(tester);
    expect(find.text('Войдите в аккаунт заново.'), findsOneWidget);
    expect(calls, isEmpty);
  });

  iosTest('insecure endpoint never reads credentials', (tester) async {
    final api = _Api()..base = 'http://synthetic-api.test/api';
    await pump(tester, api);
    await start(tester);
    expect(api.tokenReads, 0);
    expect(calls, isEmpty);
  });

  iosTest('native unsupported uses generic content-free message', (
    tester,
  ) async {
    nativeResult = false;
    await pump(tester, _Api());
    await start(tester);
    expect(
      find.text('Перевод экрана сейчас недоступен. Попробуйте позже.'),
      findsOneWidget,
    );
    expect(calls.map((call) => call.method), ['present', 'stop']);
  });

  iosTest(
    'presentation forwards actual brand theme colors and Chinese language',
    (tester) async {
      const brand = BrandColors(
        primary: Color(0xFF123456),
        primaryDark: Color(0xFF102030),
        primaryLight: Color(0xFFABCDEF),
      );
      await pump(
        tester,
        _Api(),
        locale: const Locale('zh'),
        theme: AppTheme.lightWithColors(brand),
      );
      await start(tester);
      final arguments = calls.single.arguments as Map;
      expect(arguments['appearance'], {
        'primary': 0xFF123456,
        'secondary': 0xFFABCDEF,
        'gradientStart': tester
            .element(find.byType(ScreenTranslationSection))
            .brandGradient
            .colors
            .first
            .toARGB32(),
        'language': 'zh',
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  iosTest('logout during native presentation stops before future resolves', (
    tester,
  ) async {
    final presented = Completer<Object?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'present') return presented.future;
          return null;
        });
    final container = await pump(tester, _Api());
    await start(tester);
    (container.read(authProvider.notifier) as _Auth).change(
      const AuthState(isLoading: false),
    );
    await tester.pump();
    expect(calls.map((call) => call.method), ['present', 'stop']);
    presented.complete(true);
    await tester.pump();
    expect(calls.length, 2);
  });

  iosTest('native errors never expose exception content', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'present') {
            throw PlatformException(
              code: 'unsupported',
              message: 'private-data',
            );
          }
          return null;
        });
    await pump(tester, _Api());
    await start(tester);
    await tester.pump();
    expect(find.textContaining('private-data'), findsNothing);
    expect(
      find.text('Перевод экрана сейчас недоступен. Попробуйте позже.'),
      findsOneWidget,
    );
    expect(calls.map((call) => call.method), ['present', 'stop']);
  });

  iosTest('API base change during token await prevents presentation', (
    tester,
  ) async {
    final token = Completer<String?>();
    final api = _Api()..token = () => token.future;
    await pump(tester, api);
    await start(tester);
    api.base = 'https://other-synthetic-api.test/api';
    token.complete('synthetic-access-token');
    await tester.pump();
    expect(calls, isEmpty);
  });
}
