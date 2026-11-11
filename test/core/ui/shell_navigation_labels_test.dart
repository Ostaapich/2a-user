import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
  for (final width in [320.0, 390.0]) {
    testWidgets('mobile navigation labels and header 44dp targets fit $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = GoRouter(
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, shell) =>
                AppShell(navigationShell: shell),
            branches: [
              for (final route in [
                '/',
                '/photos',
                '/tracks',
                '/invoices',
                '/support',
              ])
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: route,
                      builder: (context, state) =>
                          const Center(child: Text('Business page')),
                    ),
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
            notificationsControllerProvider.overrideWith(_Notifications.new),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      for (final label in [
        'Главная',
        'Фото',
        'Треки',
        'Счета',
        'Помощь',
        'Ещё',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      for (final tooltip in ['Уведомления', 'Чат поддержки']) {
        final size = tester.getSize(find.byTooltip(tooltip).first);
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
      expect(find.byTooltip('Главная'), findsOneWidget); // bottom shortcut only
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Счета'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/invoices');
    });
  }
}
