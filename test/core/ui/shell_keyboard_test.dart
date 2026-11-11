import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:twoalogisticcabineuser/src/app/widgets/app_scaffold.dart';
import 'package:twoalogisticcabineuser/src/features/shell/presentation/app_shell.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/clients/domain/client_codes_state.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/application/notifications_controller.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/domain/notification_item.dart';

class _Codes extends ClientCodesController {
  @override
  Future<ClientCodesState> build() async =>
      const ClientCodesState(codes: ['TEST'], activeCode: 'TEST');
}

class _Notifications extends NotificationsController {
  @override
  Future<List<NotificationItem>> build() async => const [];
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final standalone in [true, false]) {
      testWidgets(
        'actual ${standalone ? 'AppScaffold' : 'AppShell'} keyboard restores bounds $platform',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          const contentKey = ValueKey('body-boundary');
          const content = SizedBox.expand(
            key: contentKey,
            child: SingleChildScrollView(child: TextField()),
          );
          final router = GoRouter(
            routes: [
              StatefulShellRoute.indexedStack(
                builder: (_, state, shell) => AppShell(navigationShell: shell),
                branches: [
                  for (final path in [
                    '/',
                    '/photos',
                    '/tracks',
                    '/invoices',
                    '/support',
                  ])
                    StatefulShellBranch(
                      routes: [
                        GoRoute(path: path, builder: (_, state) => content),
                      ],
                    ),
                ],
              ),
            ],
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                clientCodesControllerProvider.overrideWith(_Codes.new),
                notificationsControllerProvider.overrideWith(
                  _Notifications.new,
                ),
              ],
              child: standalone
                  ? MaterialApp(
                      theme: ThemeData(platform: platform),
                      builder: (_, child) =>
                          AppKeyboardDismissRegion(child: child!),
                      home: const AppScaffold(title: 'Form', child: content),
                    )
                  : MaterialApp.router(
                      theme: ThemeData(platform: platform),
                      routerConfig: router,
                      builder: (_, child) =>
                          AppKeyboardDismissRegion(child: child!),
                    ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          final normalBottom = tester
              .getBottomRight(find.byKey(contentKey).first)
              .dy;
          if (!standalone) expect(find.text('Главная'), findsOneWidget);
          tester.view.viewInsets = const FakeViewPadding(bottom: 320);
          await tester.pumpAndSettle();
          expect(
            tester.getBottomRight(find.byKey(contentKey).first).dy,
            closeTo(524, 1),
          );
          if (!standalone) expect(find.text('Главная'), findsNothing);
          tester.view.viewInsets = const FakeViewPadding();
          await tester.pumpAndSettle();
          expect(
            tester.getBottomRight(find.byKey(contentKey).first).dy,
            normalBottom,
          );
          if (!standalone) expect(find.text('Главная'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
