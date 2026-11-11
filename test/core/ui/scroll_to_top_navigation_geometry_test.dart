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
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:twoalogisticcabineuser/src/core/ui/scroll_to_top_button.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/auth_provider.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/clients/domain/client_codes_state.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/application/notifications_controller.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/domain/notification_item.dart';
import 'package:twoalogisticcabineuser/src/features/photos/data/photos_provider.dart';
import 'package:twoalogisticcabineuser/src/features/photos/presentation/photos_screen.dart';
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

class _Api implements ApiClient {
  @override
  Future<String?> getToken() async => null;
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    final videos = path == '/photos'
        ? List.generate(
            12,
            (i) => {
              'id': 'video:$i',
              'url': '/fixture-$i.mp4',
              'mimeType': 'video/mp4',
              'createdAt': '2026-11-09T10:00:00Z',
              'trackNumber': 'FIXTURE-$i',
            },
          )
        : [];
    return Response<T>(
      data:
          <String, dynamic>{
                'data': videos,
                'total': videos.length,
                'hasMore': false,
              }
              as T,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unmocked geometry API operation');
}

class _Page extends StatelessWidget {
  const _Page(this.controller, {this.safeArea = false, this.bottomOffset});
  final ScrollController controller;
  final bool safeArea;
  final double? bottomOffset;
  @override
  Widget build(BuildContext context) {
    final child = Stack(
      children: [
        ListView.builder(
          controller: controller,
          itemCount: 100,
          itemBuilder: (_, i) => SizedBox(height: 80, child: Text('Row $i')),
        ),
        ScrollToTopButton(controller: controller, bottomOffset: bottomOffset),
      ],
    );
    return safeArea ? SafeArea(top: false, child: child) : child;
  }
}

Future<void> _frames(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
  await t.pump();
}

Future<ScrollController> _open(
  WidgetTester t,
  double width, {
  bool photos = false,
  bool root = false,
  bool safeArea = false,
  double? bottomOffset,
}) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = Size(width, 900);
  t.view.devicePixelRatio = 1;
  t.view.padding = const FakeViewPadding(top: 59, bottom: 34);
  t.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
  addTearDown(t.view.reset);
  final controller = ScrollController();
  addTearDown(controller.dispose);
  final initial = photos ? 1 : 3;
  final router = GoRouter(
    initialLocation: root ? '/root' : '/page$initial',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(navigationShell: shell),
        branches: List.generate(
          6,
          (index) => StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/page$index',
                builder: (_, _) {
                  if (index != initial) {
                    return Center(child: Text('Branch $index'));
                  }
                  return photos
                      ? const PhotosScreen()
                      : _Page(
                          controller,
                          safeArea: safeArea,
                          bottomOffset: bottomOffset,
                        );
                },
              ),
            ],
          ),
        ),
      ),
      GoRoute(
        path: '/root',
        builder: (_, _) => AppScaffold(
          title: 'Root',
          child: _Page(controller, bottomOffset: bottomOffset),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await t.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        apiClientProvider.overrideWithValue(_Api()),
        authProvider.overrideWith(_Auth.new),
        clientCodesControllerProvider.overrideWith(_Codes.new),
        notificationsControllerProvider.overrideWith(_Notifications.new),
        photosRealtimeBridgeProvider.overrideWith((ref) {}),
      ],
      child: MaterialApp.router(
        theme: ThemeData(fontFamily: 'Gilroy'),
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (_, child) => AppKeyboardDismissRegion(child: child!),
        routerConfig: router,
      ),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await t.pump(const Duration(milliseconds: 50));
  }
  final scrolling = photos
      ? t.widget<CustomScrollView>(find.byType(CustomScrollView)).controller!
      : controller;
  expect(scrolling.position.maxScrollExtent, greaterThan(300));
  scrolling.jumpTo(450);
  await _frames(t);
  return scrolling;
}

Finder _button() => find.descendant(
  of: find.byType(ScrollToTopButton),
  matching: find.byType(GestureDetector),
);
Finder _nav() => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_BottomNavSurface',
);
void _clearance(WidgetTester t, String name, double width) {
  final nav = t.getRect(_nav());
  final button = t.getRect(_button());
  final gap = nav.top - button.bottom;
  debugPrint(
    'SCROLL_BUTTON_GEOMETRY ${jsonEncode({'page': name, 'width': width, 'navTop': nav.top, 'buttonBottom': button.bottom, 'gap': gap})}',
  );
  expect(gap, closeTo(24, 0.1));
  expect(button.overlaps(nav), false);
}

Future<void> _finish(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump(const Duration(seconds: 10));
}

void main() {
  setUpAll(() async {
    await loadKeyboardAcceptanceFonts();
    await initializeDateFormatting('ru');
  });
  for (final width in [320.0, 390.0]) {
    for (final photos in [false, true]) {
      testWidgets(
        'scroll button clears actual ${photos ? 'Photos' : 'default page'} shell nav at $width',
        (t) async {
          final controller = await _open(t, width, photos: photos);
          _clearance(t, photos ? 'Photos' : 'default', width);
          await t.tap(_button());
          await _frames(t);
          expect(controller.offset, closeTo(0, 0.1));
          await t.tap(find.text('Треки').last);
          await _frames(t);
          expect(find.text('Branch 2'), findsOneWidget);
          expect(t.takeException(), isNull);
          await _finish(t);
        },
      );
    }
    testWidgets(
      'root scroll button reserves safe bottom once without phantom nav $width',
      (t) async {
        await _open(t, width, root: true);
        expect(_nav(), findsNothing);
        expect(900 - 34 - t.getRect(_button()).bottom, closeTo(24, 0.1));
        await _finish(t);
      },
    );
    testWidgets(
      'descendant SafeArea does not double count bottom inset $width',
      (t) async {
        await _open(t, width, safeArea: true);
        _clearance(t, 'nestedSafeArea', width);
        await _finish(t);
      },
    );
    testWidgets(
      'IME hides scroll button after Scaffold consumes inset; hidden nav reserves safe only $width',
      (t) async {
        await _open(t, width);
        t.view.viewInsets = const FakeViewPadding(bottom: 320);
        await _frames(t);
        final buttonContext = t.element(find.byType(ScrollToTopButton));
        expect(MediaQuery.viewInsetsOf(buttonContext).bottom, 0);
        expect(
          t
              .widget<IgnorePointer>(
                find.descendant(
                  of: find.byType(ScrollToTopButton),
                  matching: find.byType(IgnorePointer),
                ),
              )
              .ignoring,
          true,
        );
        expect(_nav(), findsNothing);
        t.view.resetViewInsets();
        await _frames(t);
        final container = ProviderScope.containerOf(
          t.element(find.byType(AppShell)),
        );
        container.read(bottomNavVisibleProvider.notifier).hide();
        await _frames(t);
        expect(900 - 34 - t.getRect(_button()).bottom, closeTo(24, 0.1));
        await _finish(t);
      },
    );
    testWidgets('explicit bottomOffset remains absolute inside shell $width', (
      t,
    ) async {
      await _open(t, width, bottomOffset: 180);
      expect(900 - t.getRect(_button()).bottom, closeTo(180, 0.1));
      await _finish(t);
    });
  }
  testWidgets('sidebar has no phantom bottom navigation reservation', (
    t,
  ) async {
    final controller = await _open(t, 1200);
    expect(_nav(), findsNothing);
    expect(900 - 34 - t.getRect(_button()).bottom, closeTo(24, 0.1));
    await t.tap(_button());
    await _frames(t);
    expect(controller.offset, closeTo(0, 0.1));
    await _finish(t);
  });
}
