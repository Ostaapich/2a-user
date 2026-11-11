import 'package:twoalogisticcabineuser/src/core/ui/app_search_field.dart';
import 'package:twoalogisticcabineuser/src/features/shop/presentation/widgets/shop_search_bar.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/domain/track_item.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/domain/invoice_item.dart';
import 'package:flutter/material.dart';
import '../../helpers/keyboard_acceptance.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/data/tracks_provider.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/data/invoices_provider.dart';
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

class _Codes extends ClientCodesController {
  @override
  Future<ClientCodesState> build() async =>
      const ClientCodesState(codes: ['TEST'], activeCode: 'TEST');
}

class _Payment extends PaymentChatController {
  final sent = <String>[];
  @override
  Future<bool> sendMessage(
    String content, {
    Map<String, dynamic>? metadata,
    List<int>? attachmentIds,
  }) async {
    sent.add(content);
    return true;
  }

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

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Finder _search() => find.descendant(
  of: find.byType(AppSearchField),
  matching: find.byType(TextField),
);
void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final width in [320.0, 390.0]) {
      testWidgets(
        'shop explicit search clear arrow and IME ${platform.name} $width',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, width == 320 ? 640 : 844);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetViewInsets);
          final submissions = <String>[];
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: ThemeData(platform: platform, fontFamily: 'Gilroy'),
                builder: (_, child) => AppKeyboardDismissRegion(child: child!),
                home: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.only(top: 80),
                    child: ShopSearchBar(
                      initialQuery: ' initial ',
                      onSearch: submissions.add,
                    ),
                  ),
                ),
              ),
            ),
          );
          await _frames(tester);
          expect(submissions, isEmpty);
          expect(
            tester.widget<TextField>(_search()).controller!.text,
            ' initial ',
          );
          final submit = find.byTooltip('Найти товары');
          expect(tester.getSize(submit).height, greaterThanOrEqualTo(44));
          expect(submit.hitTestable(), findsOneWidget);
          await tester.tap(_search());
          await tester.enterText(_search(), ' новые товары ');
          await _frames(tester);
          expect(submissions, isEmpty);
          tester.view.viewInsets = FakeViewPadding(
            bottom: width == 320 ? 280 : 320,
          );
          await _frames(tester);
          expectFocusedCaretAboveIme(
            tester,
            find.descendant(of: _search(), matching: find.byType(EditableText)),
          );
          expect(submit.hitTestable(), findsOneWidget);
          await tester.tap(submit);
          await _frames(tester);
          expect(submissions, ['новые товары']);
          tester.view.resetViewInsets();
          await _frames(tester);
          await tester.tap(find.byTooltip('Очистить поиск'));
          await _frames(tester);
          expect(tester.widget<TextField>(_search()).controller!.text, isEmpty);
          expect(submissions, ['новые товары']);
          await tester.tap(submit);
          await _frames(tester);
          expect(submissions, ['новые товары']);
          await tester.tap(_search());
          await tester.enterText(_search(), ' keyboard ');
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await _frames(tester);
          expect(submissions, ['новые товары', 'keyboard']);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await _frames(tester);
        },
      );
      testWidgets(
        'actual chat picker local filter clear tabs selection IME ${platform.name} $width',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, width == 320 ? 640 : 844);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetViewInsets);
          SharedPreferences.setMockInitialValues({
            'tutorial_payment_chat': true,
          });
          final prefs = await SharedPreferences.getInstance();
          final controller = _Payment();
          final now = DateTime(2026, 11, 10);
          final tracks = [
            for (final code in ['MATCH-TRACK', 'OTHER-TRACK'])
              TrackItem(
                id: code.startsWith('MATCH') ? 1 : 2,
                code: code,
                status: 'На складе',
                date: now,
                createdAt: now,
                updatedAt: now,
              ),
          ];
          final invoices = [
            for (final number in ['MATCH-INVOICE', 'OTHER-INVOICE'])
              InvoiceItem(
                id: number,
                invoiceNumber: number,
                status: 'pending',
                placesCount: 1,
                density: 1,
                weight: 1,
                volume: 1,
                totalCostRub: 100,
              ),
          ];
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                sharedPreferencesProvider.overrideWithValue(prefs),
                clientCodesControllerProvider.overrideWith(_Codes.new),
                tracksSimpleListProvider.overrideWith(
                  (ref, code) async => tracks,
                ),
                invoicesListProvider.overrideWith(
                  (ref, code) async => invoices,
                ),
                paymentChatControllerProvider.overrideWith(() => controller),
                chatPresenceServiceProvider.overrideWithValue(_Presence()),
                pushNotificationServiceProvider.overrideWithValue(_Push()),
                notificationsControllerProvider.overrideWith(
                  _Notifications.new,
                ),
              ],
              child: MaterialApp(
                theme: ThemeData(platform: platform, fontFamily: 'Gilroy'),
                builder: (_, child) => AppKeyboardDismissRegion(child: child!),
                home: const PaymentChatScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.longPress(find.byTooltip('Прикрепить'));
          await tester.pumpAndSettle();
          expect(find.text('MATCH-TRACK'), findsOneWidget);
          expect(find.text('OTHER-TRACK'), findsOneWidget);
          await tester.tap(_search());
          await tester.enterText(_search(), 'MATCH');
          await _frames(tester);
          expect(find.text('MATCH-TRACK'), findsOneWidget);
          expect(find.text('OTHER-TRACK'), findsNothing);
          expect(controller.sent, isEmpty);
          tester.view.viewInsets = FakeViewPadding(
            bottom: width == 320 ? 280 : 320,
          );
          await _frames(tester);
          expectFocusedCaretAboveIme(
            tester,
            find.descendant(of: _search(), matching: find.byType(EditableText)),
          );
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await _frames(tester);
          tester.view.resetViewInsets();
          await _frames(tester);
          await tester.tap(find.text('Счета'));
          await tester.pumpAndSettle();
          expect(find.text('MATCH-INVOICE'), findsOneWidget);
          expect(find.text('OTHER-INVOICE'), findsNothing);
          expect(controller.sent, isEmpty);
          await tester.tap(find.byTooltip('Очистить поиск'));
          await _frames(tester);
          expect(find.text('MATCH-INVOICE'), findsOneWidget);
          expect(find.text('OTHER-INVOICE'), findsOneWidget);
          expect(controller.sent, isEmpty);
          expect(find.text('MATCH-INVOICE').hitTestable(), findsOneWidget);
          await tester.tap(find.text('MATCH-INVOICE'));
          await tester.pumpAndSettle();
          expect(find.byType(AppSearchField), findsNothing);
          expect(controller.sent, hasLength(1));
          expect(controller.sent.single, contains('MATCH-INVOICE'));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
