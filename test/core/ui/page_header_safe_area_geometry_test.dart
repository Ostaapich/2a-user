import '../../helpers/keyboard_acceptance.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/app/widgets/app_scaffold.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/core/ui/pixso_top_menu_surface.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/auth_provider.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/passkey_auth_service.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/clients/domain/client_codes_state.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/application/notifications_controller.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/domain/notification_item.dart';
import 'package:twoalogisticcabineuser/src/features/photos/data/photos_provider.dart';
import 'package:twoalogisticcabineuser/src/features/photos/presentation/photos_screen.dart';
import 'package:twoalogisticcabineuser/src/features/profile/data/profile_provider.dart';
import 'package:twoalogisticcabineuser/src/features/profile/presentation/profile_screen.dart';
import 'package:twoalogisticcabineuser/src/features/shell/presentation/app_shell.dart';

class _Auth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    isLoggedIn: true,
    isLoading: false,
    clientId: 17,
    userDomain: 'fixture.invalid',
  );
}

class _Codes extends ClientCodesController {
  @override
  Future<ClientCodesState> build() async =>
      const ClientCodesState(codes: ['A-001'], activeCode: 'A-001');
}

class _Notifications extends NotificationsController {
  @override
  Future<List<NotificationItem>> build() async => [];
}

class _Passkey implements PasskeyAuthService {
  @override
  Future<bool> isAvailable() async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unmocked passkey operation');
}

class _Api implements ApiClient {
  @override
  Future<String?> getToken() async => null;
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async => Response<T>(
    data:
        <String, dynamic>{
              'data': [],
              'photos': [],
              'total': 0,
              'hasMore': false,
            }
            as T,
    statusCode: 200,
    requestOptions: RequestOptions(path: path),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unmocked geometry-fixture operation');
}

void main() {
  setUpAll(() async {
    await loadKeyboardAcceptanceFonts();
    await initializeDateFormatting('ru');
  });
  for (final width in [320.0, 390.0]) {
    for (final page in ['photos-shell', 'profile-root']) {
      testWidgets('$page consumes safeTop59 once at $width', (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
        addTearDown(tester.view.reset);
        final router = GoRouter(
          initialLocation: page == 'photos-shell' ? '/photos' : '/profile',
          routes: [
            StatefulShellRoute.indexedStack(
              builder: (context, state, shell) =>
                  AppShell(navigationShell: shell),
              branches: [
                StatefulShellBranch(
                  routes: [
                    GoRoute(path: '/', builder: (_, _) => const SizedBox()),
                  ],
                ),
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: '/photos',
                      builder: (_, _) => const PhotosScreen(),
                    ),
                  ],
                ),
              ],
            ),
            GoRoute(
              path: '/profile',
              builder: (_, _) =>
                  const AppScaffold(title: 'Профиль', child: ProfileScreen()),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            retry: (_, _) => null,
            overrides: [
              apiClientProvider.overrideWithValue(_Api()),
              authProvider.overrideWith(_Auth.new),
              clientCodesControllerProvider.overrideWith(_Codes.new),
              notificationsControllerProvider.overrideWith(_Notifications.new),
              photosRealtimeBridgeProvider.overrideWith((ref) {}),
              passkeyAuthServiceProvider.overrideWithValue(_Passkey()),
              clientProfileProvider.overrideWith(
                (ref) async => ClientProfile(
                  id: 17,
                  fullName: 'Fixture Client',
                  email: 'fixture@example.test',
                  balance: 0,
                  isActive: true,
                  codes: const [],
                  createdAt: DateTime(2026),
                ),
              ),
            ],
            child: MaterialApp.router(
              theme: ThemeData(fontFamily: 'Gilroy'),
              locale: const Locale('ru'),
              supportedLocales: const [Locale('ru')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              routerConfig: router,
            ),
          ),
        );
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final menu = tester.getRect(find.byType(PixsoTopMenuSurface).first);
        final header = tester.getRect(
          find.byWidgetPredicate(
            (widget) =>
                widget.runtimeType.toString() ==
                (page == 'photos-shell'
                    ? '_PhotosHeaderSection'
                    : '_ProfilePageHeader'),
          ),
        );
        final gap = header.top - menu.bottom;
        debugPrint(
          'HEADER_GEOMETRY ${jsonEncode({'page': page, 'width': width, 'safeTop': 59, 'menuTop': menu.top, 'menuBottom': menu.bottom, 'headerTop': header.top, 'gap': gap})}',
        );
        // Keep the content separate from the floating controls, without a second
        // status-bar allowance below them.
        expect(
          gap,
          greaterThanOrEqualTo(0),
          reason: 'header must not overlap floating menu',
        );
        expect(
          gap,
          lessThanOrEqualTo(16),
          reason: 'safe inset must not be charged twice below menu',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 10));
      });
    }
  }
}
