import 'package:twoalogisticcabineuser/src/core/ui/app_search_field.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_input_decoration.dart';
import '../../helpers/keyboard_acceptance.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/app/widgets/app_scaffold.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/auth_provider.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/clients/domain/client_codes_state.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/application/notifications_controller.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/domain/notification_item.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/presentation/invoices_screen.dart';

class _Api extends ApiClient {
  final queries = <String?>[];
  @override
  Future<String?> getToken() async => null;
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    if (path == '/invoices') queries.add(queryParameters?['search'] as String?);
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data:
          {
                'data': path == '/invoices'
                    ? [
                        {
                          'id': 'fixture-invoice',
                          'invoiceNumber': queryParameters?['search'] == null
                              ? 'INITIAL-INVOICE'
                              : 'FILTERED-INVOICE',
                        },
                      ]
                    : <dynamic>[],
                'total': path == '/invoices' ? 1 : 0,
                'hasMore': false,
              }
              as T,
    );
  }
}

class _Codes extends ClientCodesController {
  @override
  Future<ClientCodesState> build() async =>
      const ClientCodesState(codes: ['2A-TEST'], activeCode: '2A-TEST');
}

class _Auth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    isLoggedIn: true,
    isLoading: false,
    clientId: 1,
    userDomain: 'fixture.invalid',
  );
}

class _Notifications extends NotificationsController {
  @override
  Future<List<NotificationItem>> build() async => const [];
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    await loadKeyboardAcceptanceFonts();
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final width in [320.0, 390.0]) {
      testWidgets(
        'actual invoice search server query clear once stable focus IME ${platform.name} $width',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, width == 320 ? 640 : 844);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetViewInsets);
          final api = _Api();
          await tester.pumpWidget(
            ProviderScope(
              retry: (_, _) => null,
              overrides: [
                apiClientProvider.overrideWithValue(api),
                authProvider.overrideWith(_Auth.new),
                clientCodesControllerProvider.overrideWith(_Codes.new),
                notificationsControllerProvider.overrideWith(
                  _Notifications.new,
                ),
              ],
              child: MaterialApp(
                theme: ThemeData(platform: platform, fontFamily: 'Gilroy'),
                locale: const Locale('ru'),
                supportedLocales: const [Locale('ru')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                builder: (_, child) => AppKeyboardDismissRegion(child: child!),
                home: const AppScaffold(
                  title: 'Счета',
                  child: InvoicesScreen(),
                ),
              ),
            ),
          );
          await _frames(tester);
          await _frames(tester);
          expect(find.textContaining('INITIAL-INVOICE'), findsWidgets);
          final field = find.descendant(
            of: find.byType(AppSearchField),
            matching: find.byType(TextField),
          );
          expect(field, findsOneWidget);
          expect(
            find.ancestor(
              of: field,
              matching: find.byType(AppOutlinedInputFrame),
            ),
            findsOneWidget,
          );
          await tester.ensureVisible(field);
          await tester.tap(field);
          await tester.enterText(field, 'QUERY-123');
          await _frames(tester);
          final node = tester.widget<TextField>(field).focusNode;
          expect(node!.hasFocus, isTrue);
          expect(api.queries.last, 'QUERY-123');
          expect(find.textContaining('INITIAL-INVOICE'), findsNothing);
          expect(find.textContaining('FILTERED-INVOICE'), findsWidgets);
          tester.view.viewInsets = FakeViewPadding(
            bottom: width == 320 ? 280 : 320,
          );
          await _frames(tester);
          expectFocusedCaretAboveIme(
            tester,
            find.descendant(of: field, matching: find.byType(EditableText)),
          );
          expect(tester.widget<TextField>(field).focusNode, same(node));
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await _frames(tester);
          expect(node.hasFocus, isFalse);
          expect(tester.widget<TextField>(field).controller!.text, 'QUERY-123');
          tester.view.resetViewInsets();
          await _frames(tester);
          final before = api.queries.length;
          await tester.ensureVisible(find.byTooltip('Очистить поиск'));
          await tester.tap(find.byTooltip('Очистить поиск'));
          await _frames(tester);
          expect(tester.widget<TextField>(field).controller!.text, isEmpty);
          expect(
            api.queries.length,
            before + 1,
            reason: 'owned clear must dispatch once',
          );
          expect(api.queries.last, isNull);
          expect(find.textContaining('INITIAL-INVOICE'), findsWidgets);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await _frames(tester);
        },
      );
    }
  }
}
