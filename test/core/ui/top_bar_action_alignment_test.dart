import 'package:flutter/cupertino.dart';
import '../../helpers/keyboard_acceptance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/app/widgets/app_scaffold.dart';
import 'package:twoalogisticcabineuser/src/core/services/push_notification_service.dart';
import 'package:twoalogisticcabineuser/src/core/ui/pixso_top_menu_surface.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/clients/domain/client_codes_state.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/application/notifications_controller.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/domain/notification_item.dart';

class _Codes extends ClientCodesController {
  _Codes(this.hasClient);
  final bool hasClient;
  @override
  Future<ClientCodesState> build() async => ClientCodesState(
    codes: hasClient ? ['TEST'] : [],
    activeCode: hasClient ? 'TEST' : null,
  );
}

class _Notifications extends NotificationsController {
  _Notifications(this.unread);
  final bool unread;
  @override
  Future<List<NotificationItem>> build() async => [
    if (unread)
      NotificationItem(
        id: '1',
        type: NotificationType.chatMessage,
        title: 'Сообщение',
        message: 'Тест',
        createdAt: DateTime(2026),
        isRead: false,
      ),
  ];
}

class _Unread extends UnreadNotificationsCountNotifier {
  _Unread(this.count);
  final int count;
  @override
  int build() => count;
}

Finder _badge(Finder action) => find.descendant(
  of: action,
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Container &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).color == Colors.redAccent,
  ),
);

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final width in [320.0, 390.0]) {
    for (final state in ['unread', 'read', 'no-client']) {
      testWidgets(
        'actual floating topbar centers bell/chat surfaces/icons $width $state',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 844);
          addTearDown(tester.view.reset);
          final unread = state == 'unread';
          final hasClient = state != 'no-client';
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                clientCodesControllerProvider.overrideWith(
                  () => _Codes(hasClient),
                ),
                activeClientCodeProvider.overrideWithValue(
                  hasClient ? 'TEST' : null,
                ),
                notificationsControllerProvider.overrideWith(
                  () => _Notifications(unread),
                ),
                unreadNotificationsCountProvider.overrideWith(
                  () => _Unread(unread ? 3 : 0),
                ),
              ],
              child: MaterialApp(
                theme: ThemeData(fontFamily: 'Gilroy'),
                home: const AppScaffold(
                  title: 'Экран',
                  child: SizedBox.expand(),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.byType(AppFloatingTopBar), findsOneWidget);
          final bell = find.byTooltip('Уведомления');
          final chat = find.byTooltip('Чат поддержки');
          final bellSurface = find.descendant(
            of: bell,
            matching: find.byType(PixsoTopMenuActionSurface),
          );
          final chatSurface = find.descendant(
            of: chat,
            matching: find.byType(PixsoTopMenuActionSurface),
          );
          final bellIcon = find.byIcon(CupertinoIcons.bell);
          final chatIcon = find.byIcon(CupertinoIcons.chat_bubble_2);
          for (final action in [bell, chat]) {
            expect(tester.getSize(action), const Size(44, 44));
          }
          expect(
            tester.getCenter(bellSurface).dy,
            closeTo(tester.getCenter(chatSurface).dy, .01),
          );
          expect(
            tester.getCenter(bellIcon).dy,
            closeTo(tester.getCenter(chatIcon).dy, .01),
          );
          for (final (action, surface, icon) in [
            (bell, bellSurface, bellIcon),
            (chat, chatSurface, chatIcon),
          ]) {
            for (final visual in [surface, icon]) {
              expect(
                tester.getCenter(visual).dx,
                closeTo(tester.getCenter(action).dx, .01),
              );
              expect(
                tester.getCenter(visual).dy,
                closeTo(tester.getCenter(action).dy, .01),
              );
            }
            if (unread) {
              expect(_badge(action), findsOneWidget);
              final badge = tester.getRect(_badge(action));
              final bounds = tester.getRect(action);
              final surfaceBounds = tester.getRect(surface);
              expect(badge.top, greaterThanOrEqualTo(surfaceBounds.top));
              expect(badge.right, lessThanOrEqualTo(surfaceBounds.right));
              expect(bounds.contains(badge.topLeft), isTrue);
              expect(bounds.contains(badge.bottomRight), isTrue);
              final clip = find
                  .ancestor(of: action, matching: find.byType(ClipRRect))
                  .first;
              final clipRect = tester.getRect(clip);
              final clipWidget = tester.widget<ClipRRect>(clip);
              final shape = clipWidget.borderRadius
                  .resolve(TextDirection.ltr)
                  .toRRect(clipRect);
              for (final corner in [
                badge.topLeft,
                badge.topRight,
                badge.bottomLeft,
                badge.bottomRight,
              ]) {
                expect(
                  shape.contains(corner),
                  isTrue,
                  reason: 'badge must remain within rounded pill clipping',
                );
              }
            } else {
              expect(_badge(action), findsNothing);
            }
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
