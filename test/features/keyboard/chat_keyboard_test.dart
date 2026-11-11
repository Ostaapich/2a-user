import 'package:flutter/material.dart';
import '../../helpers/keyboard_acceptance.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/data/tracks_provider.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/data/invoices_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:twoalogisticcabineuser/src/app/widgets/app_scaffold.dart';
import 'package:twoalogisticcabineuser/src/features/shell/presentation/app_shell.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/clients/domain/client_codes_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/core/persistence/shared_preferences_provider.dart';
import 'package:twoalogisticcabineuser/src/core/services/chat_presence_service.dart';
import 'package:twoalogisticcabineuser/src/core/services/push_notification_service.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/application/notifications_controller.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/domain/notification_item.dart';
import 'package:twoalogisticcabineuser/src/features/payment_chat/data/payment_chat_provider.dart';
import 'package:twoalogisticcabineuser/src/features/payment_chat/presentation/payment_chat_screen.dart';
import 'package:twoalogisticcabineuser/src/features/support/data/chat_provider.dart';
import 'package:twoalogisticcabineuser/src/features/support/presentation/support_chat_screen.dart';

class _Codes extends ClientCodesController {
  @override
  Future<ClientCodesState> build() async =>
      const ClientCodesState(codes: ['TEST'], activeCode: 'TEST');
}

class _Support extends ChatController {
  @override
  ChatState build() => const ChatState();
  @override
  Future<void> loadConversation() async {}
  @override
  void setRealtimeActive(bool active) {}
}

class _Payment extends PaymentChatController {
  @override
  PaymentChatState build() => const PaymentChatState();
  @override
  Future<void> loadConversation() async {}
  @override
  void setRealtimeActive(bool active) {}
}

class _Push implements PushNotificationService {
  @override
  Future<void> initialize({void Function(String? route)? onTap}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Presence extends ChatPresenceService {
  _Presence() : super(ApiClient());
  @override
  Future<void> openChat(ChatType type, {int? conversationId}) async {}
  @override
  Future<void> closeChat(ChatType type) async {}
}

class _Notifications extends NotificationsController {
  @override
  Future<List<NotificationItem>> build() async => [];
  @override
  Future<void> markTypesRead(Set<NotificationType> types) async {}
}

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final payment in [false, true]) {
      for (final shellResize in [false, true]) {
        testWidgets(
          '$platform ${payment ? 'payment' : 'support'} ${shellResize ? 'consumed shell' : 'standalone'} keyboard',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = const Size(390, 844);
            tester.view.viewPadding = const FakeViewPadding(bottom: 34);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetViewInsets);
            addTearDown(tester.view.resetViewPadding);
            SharedPreferences.setMockInitialValues({
              'tutorial_support': true,
              'tutorial_payment_chat': true,
            });
            final prefs = await SharedPreferences.getInstance();
            final router = GoRouter(
              initialLocation: '/support',
              routes: [
                StatefulShellRoute.indexedStack(
                  builder: (_, state, shell) =>
                      AppShell(navigationShell: shell),
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
                          GoRoute(
                            path: path,
                            builder: (_, state) => path == '/support'
                                ? const SupportChatScreen()
                                : const SizedBox(),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            );
            addTearDown(router.dispose);
            final application = shellResize && !payment
                ? MaterialApp.router(
                    theme: ThemeData(platform: platform),
                    routerConfig: router,
                    builder: (_, child) =>
                        AppKeyboardDismissRegion(child: child!),
                  )
                : MaterialApp(
                    theme: ThemeData(platform: platform),
                    builder: (_, child) =>
                        AppKeyboardDismissRegion(child: child!),
                    home: shellResize
                        ? const AppScaffold(
                            title: 'Чат по оплате',
                            child: PaymentChatScreen(),
                          )
                        : (payment
                              ? const PaymentChatScreen()
                              : const SupportChatScreen()),
                  );
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  sharedPreferencesProvider.overrideWithValue(prefs),
                  clientCodesControllerProvider.overrideWith(_Codes.new),
                  tracksSimpleListProvider.overrideWith(
                    (ref, code) async => [],
                  ),
                  invoicesListProvider.overrideWith((ref, code) async => []),
                  chatControllerProvider.overrideWith(_Support.new),
                  paymentChatControllerProvider.overrideWith(_Payment.new),
                  chatPresenceServiceProvider.overrideWithValue(_Presence()),
                  pushNotificationServiceProvider.overrideWithValue(_Push()),
                  notificationsControllerProvider.overrideWith(
                    _Notifications.new,
                  ),
                ],
                child: application,
              ),
            );
            await tester.pumpAndSettle();
            final editor = find.byType(TextField).first;
            await tester.tap(editor);
            await tester.pump();
            tester.view.viewInsets = const FakeViewPadding(bottom: 300);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expectFocusedCaretAboveIme(
              tester,
              find.byType(EditableText).first,
              keyboardTop:
                  tester.view.physicalSize.height /
                      tester.view.devicePixelRatio -
                  tester.view.viewInsets.bottom / tester.view.devicePixelRatio,
            );
            final inputBottom = tester.getBottomLeft(editor).dy;
            expect(inputBottom, lessThan(544));
            expect(
              inputBottom,
              greaterThan(490),
              reason:
                  'composer should sit near IME without stale home/nav padding',
            );
            final animation = find
                .ancestor(of: editor, matching: find.byType(AnimatedPadding))
                .first;
            expect(
              tester
                  .widget<AnimatedPadding>(animation)
                  .padding
                  .resolve(TextDirection.ltr)
                  .bottom,
              shellResize ? 10 : 310,
            );
            await tester.tapAt(const Offset(195, 250));
            await tester.pump();
            expect(
              tester
                  .widget<EditableText>(find.byType(EditableText).first)
                  .focusNode
                  .hasFocus,
              isFalse,
            );
            if (payment && shellResize) {
              tester.view.viewInsets = const FakeViewPadding();
              await tester.pumpAndSettle();
              await tester.longPress(find.byTooltip('Прикрепить'));
              await tester.pumpAndSettle();
              final search = find.widgetWithText(
                TextField,
                'Поиск по номеру...',
              );
              await tester.tap(search);
              await tester.pump();
              tester.view.viewInsets = const FakeViewPadding(bottom: 300);
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              expect(tester.getRect(search).bottom, lessThanOrEqualTo(544));
              expectFocusedCaretAboveIme(
                tester,
                find.byType(EditableText).last,
                keyboardTop:
                    tester.view.physicalSize.height /
                        tester.view.devicePixelRatio -
                    tester.view.viewInsets.bottom /
                        tester.view.devicePixelRatio,
              );
              await tester.tap(find.text('Быстрая отправка'));
              await tester.pump();
              expect(
                tester
                    .widget<EditableText>(find.byType(EditableText).last)
                    .focusNode
                    .hasFocus,
                isFalse,
              );
            }
            await tester.pumpWidget(const SizedBox());
            await tester.pumpAndSettle();
          },
        );
      }
    }
  }
}
