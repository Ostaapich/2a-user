import '../../helpers/keyboard_acceptance.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter/material.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/presentation/notifications_sheet.dart';
import '../../helpers/pump_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/services/push_notification_service.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/application/notifications_controller.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/data/notifications_repository.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/domain/notification_item.dart';

class _Repo implements NotificationsRepository {
  _Repo({this.total = 90, this.unread = 90});
  final int total;
  final int unread;
  bool loadedRead = false;
  int markAllCalls = 0;
  final pages = <int>[];
  @override
  Future<NotificationsPage> fetchPage({
    required String clientCode,
    int page = 1,
    int limit = 50,
  }) async {
    pages.add(page);
    return NotificationsPage(
      items: [
        NotificationItem(
          id: '$page',
          type: NotificationType.news,
          title: 'News',
          message: 'Body',
          createdAt: DateTime.utc(2026),
          isRead: loadedRead,
        ),
      ],
      total: total,
      unreadCount: unread,
      page: page,
      limit: limit,
    );
  }

  @override
  Future<List<NotificationItem>> fetchNotifications({
    required String clientCode,
  }) async => (await fetchPage(clientCode: clientCode)).items;
  @override
  Future<void> markAllAsRead() async {
    markAllCalls++;
  }

  @override
  Future<void> markAsRead(List<int> ids) async {}
  @override
  Future<void> markTypesAsRead(List<String> types) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('ru');
    await loadKeyboardAcceptanceFonts();
  });
  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets('notification header has clear mark-all action at $width px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _Repo(total: 750, unread: 343);
      await tester.pumpApp(
        Scaffold(
          body: NotificationsSheet(clientCode: '2A-01', onNavigate: (_) {}),
        ),
        overrides: [
          activeClientCodeProvider.overrideWith((ref) => '2A-01'),
          notificationsRepositoryProvider.overrideWithValue(repo),
        ],
      );
      await tester.pumpAndSettle();
      expect(find.text('Прочитать всё'), findsOneWidget);
      final heading = find.text('Уведомления');
      final subtitle = find.text('343 новых из 750');
      expect(subtitle, findsOneWidget);
      final action = find.byTooltip('Прочитать всё');
      final headingGroup = find
          .ancestor(of: heading, matching: find.byType(Column))
          .first;
      final groupRect = tester.getRect(headingGroup);
      final actionRect = tester.getRect(action);
      expect(actionRect.center.dy, closeTo(groupRect.center.dy, .1));
      expect(actionRect.left, greaterThanOrEqualTo(groupRect.right));
      expect(actionRect.height, greaterThanOrEqualTo(44));
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(repo.markAllCalls, 1);
      expect(find.text('Все уведомления прочитаны'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test('history loads older rows and polling keeps all loaded pages', () async {
    final repo = _Repo();
    final container = ProviderContainer(
      overrides: [
        activeClientCodeProvider.overrideWith((ref) => '2A-01'),
        notificationsRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(notificationsControllerProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(notificationsControllerProvider.future);
    final controller = container.read(notificationsControllerProvider.notifier);
    await controller.loadMore();
    expect(
      container.read(notificationsControllerProvider).value!.map((n) => n.id),
      ['1', '2'],
    );
    await controller.markRead('2');
    expect(container.read(unreadNotificationsCountProvider), 89);
    await controller.refresh();
    expect(container.read(notificationsControllerProvider).value!.length, 2);
    expect(repo.pages, [1, 2, 1, 2]);
  });
  for (final loadedRead in [false, true]) {
    test(
      loadedRead
          ? 'mark all includes unread notifications beyond the loaded page'
          : 'reading one item decrements the server-wide count only once',
      () async {
        final repo = _Repo()..loadedRead = loadedRead;
        final container = ProviderContainer(
          overrides: [
            activeClientCodeProvider.overrideWith((ref) => '2A-01'),
            notificationsRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);
        final sub = container.listen(
          notificationsControllerProvider,
          (_, _) {},
        );
        addTearDown(sub.close);
        await container.read(notificationsControllerProvider.future);
        final notifier = container.read(
          notificationsControllerProvider.notifier,
        );
        if (loadedRead) {
          await notifier.markAllRead();
          expect(repo.markAllCalls, 1);
        } else {
          await notifier.markRead('1');
          expect(container.read(unreadNotificationsCountProvider), 89);
          await notifier.markRead('1');
          expect(container.read(unreadNotificationsCountProvider), 89);
        }
      },
    );
  }
}
