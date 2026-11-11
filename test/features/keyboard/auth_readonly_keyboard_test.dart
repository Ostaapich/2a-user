import '../../helpers/keyboard_acceptance.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/core/services/agent_domain_resolver.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/auth_provider.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/client_partner_invite_provider.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/partner_link_provider.dart';
import 'package:twoalogisticcabineuser/src/features/auth/presentation/login_screen.dart';
import 'package:twoalogisticcabineuser/src/features/auth/presentation/register_screen.dart';
import 'package:twoalogisticcabineuser/src/features/auth/presentation/forgot_password_screen.dart';

class _Auth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(isLoading: false);
}

class _Partner extends PartnerLinkNotifier {
  @override
  PartnerLinkState build() =>
      const PartnerLinkState(phase: PartnerLinkPhase.idle);
}

class _Invite extends ClientPartnerInviteNotifier {
  @override
  ClientPartnerInviteState build() =>
      const ClientPartnerInviteState(phase: ClientPartnerInvitePhase.idle);
}

// Scripted transport only. No superclass transport or real provider is reached.
// Fake proof responses only expose later existing UI steps; account operations
// and call launch controls must never be used by these keyboard fixtures.
class _Api implements ApiClient {
  final posts = <String>[];
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    if (path != '/public/tariffs') throw StateError('Unexpected read: $path');
    return Response<T>(
      data: <String, dynamic>{'tariffs': []} as T,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    posts.add(path);
    final body = switch (path) {
      '/register/phone-verification/request' => {
        'verificationToken': 'fixture-pending',
        'callPhone': '+78000000000',
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 5))
            .toIso8601String(),
      },
      '/register/phone-verification/verify' => {
        'confirmed': true,
        'phoneVerificationToken': 'fixture-confirmed',
      },
      '/password-reset/request' => {
        'checkId': 'fixture-check',
        'callPhone': '+78000000000',
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 5))
            .toIso8601String(),
      },
      '/password-reset/verify' => {
        'confirmed': true,
        'resetToken': 'fixture-reset',
      },
      _ => throw StateError(
        'Forbidden account submit or unmocked request: $path',
      ),
    };
    return Response<T>(
      data: body as T,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unmocked API operation: ${invocation.memberName}');
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

Future<void> _open(WidgetTester tester, Widget screen, _Api api) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        authProvider.overrideWith(_Auth.new),
        partnerLinkProvider.overrideWith(_Partner.new),
        clientPartnerInviteProvider.overrideWith(_Invite.new),
        currentAgentDomainProvider.overrideWithValue(null),
      ],
      child: MaterialApp(
        builder: (_, child) => AppKeyboardDismissRegion(child: child!),
        theme: ThemeData(fontFamily: 'Gilroy'),
        home: screen,
      ),
    ),
  );
  await _frames(tester);
}

Future<int> _allEditors(WidgetTester tester) async {
  final controllers = find
      .byType(EditableText)
      .evaluate()
      .map((e) => (e.widget as EditableText).controller)
      .toSet()
      .toList();
  expect(controllers, isNotEmpty);
  for (final controller in controllers) {
    final field = find.byWidgetPredicate(
      (w) => w is EditableText && identical(w.controller, controller),
    );
    await tester.ensureVisible(field);
    await _frames(tester);
    await tester.tap(field);
    final widget = tester.widget<EditableText>(field);
    debugPrint(
      'Auth editor: ${widget.keyboardType}, obscured=${widget.obscureText}',
    );
    final value = widget.obscureText
        ? 'FixturePassword1'
        : widget.keyboardType == TextInputType.phone
        ? '9991234567'
        : widget.keyboardType == TextInputType.emailAddress
        ? 'fixture@example.test'
        : widget.keyboardType == TextInputType.url
        ? 'fixture.test'
        : 'Fixture Client';
    await tester.enterText(field, value);
    await _frames(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await _frames(tester);
    expectFocusedCaretAboveIme(tester, field, keyboardTop: 360);
    final draft = controller.text;
    expect(draft, isNotEmpty);
    // Never invoke Done: Login's existing Done callback submits credentials.
    FocusManager.instance.primaryFocus?.unfocus();
    tester.view.resetViewInsets();
    await _frames(tester);
    expect(controller.text, draft);
  }
  return controllers.length;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await _frames(tester);
  await tester.tap(finder);
  await _frames(tester);
}

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final page in ['login', 'register', 'recovery']) {
      testWidgets('read-only $page all existing input steps ${platform.name}', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetViewInsets();
        });
        final api = _Api();
        await _open(tester, switch (page) {
          'login' => const LoginScreen(),
          'register' => const RegisterScreen(),
          _ => const ForgotPasswordScreen(),
        }, api);
        if (page == 'login') {
          expect(find.byType(EditableText), findsNothing);
          await _tap(tester, find.byKey(const ValueKey('password-reveal')));
          expect(await _allEditors(tester), 3);
          expect(api.posts, isEmpty);
        } else if (page == 'register') {
          expect(await _allEditors(tester), 3);
          await _tap(tester, find.text('Подтвердить телефон звонком'));
          await _tap(tester, find.text('Проверить'));
          await _tap(tester, find.text('Продолжить'));
          expect(await _allEditors(tester), 2);
          await _tap(tester, find.text('Продолжить'));
          expect(await _allEditors(tester), 2);
          expect(api.posts, [
            '/register/phone-verification/request',
            '/register/phone-verification/verify',
          ]);
        } else {
          expect(await _allEditors(tester), 2);
          await _tap(tester, find.text('Продолжить'));
          await tester.pump(const Duration(seconds: 3));
          await _frames(tester);
          expect(await _allEditors(tester), 2);
          expect(api.posts, [
            '/password-reset/request',
            '/password-reset/verify',
          ]);
        }
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 10));
      });
    }
  }
}
