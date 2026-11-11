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
import 'package:twoalogisticcabineuser/src/features/photos/data/photos_provider.dart';
import 'package:twoalogisticcabineuser/src/features/photos/presentation/photos_screen.dart';
import 'package:twoalogisticcabineuser/src/features/search/presentation/track_search_no_code_screen.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/presentation/tracks_screen.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/presentation/invoices_screen.dart';

class _Api extends ApiClient {
  int invoiceSearchCalls = 0;
  @override
  Future<String?> getToken() async => null;
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    if (path == '/invoices' && queryParameters?['search'] != null) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (invoiceSearchCalls++ == 0) {
        throw DioException(
          requestOptions: RequestOptions(path: path),
          type: DioExceptionType.connectionError,
        );
      }
    }
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
                              ? 'OLD-QUERY-INVOICE'
                              : 'NEW-QUERY-INVOICE',
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

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    await loadKeyboardAcceptanceFonts();
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final page in ['tracks', 'photos', 'invoices', 'search']) {
      testWidgets('$page focus and IME visibility on ${platform.name}', (
        t,
      ) async {
        SharedPreferences.setMockInitialValues({});
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = const Size(390, 844);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetViewInsets);
        final child = switch (page) {
          'tracks' => const TracksScreen(),
          'photos' => const PhotosScreen(),
          'invoices' => const InvoicesScreen(),
          _ => const TrackSearchNoCodeScreen(),
        };
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
            child: MaterialApp(
              theme: ThemeData(fontFamily: 'Gilroy', platform: platform),
              builder: (context, child) =>
                  AppKeyboardDismissRegion(child: child!),
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              supportedLocales: const [Locale('ru'), Locale('en')],
              locale: const Locale('ru'),
              home: AppScaffold(title: page, child: child),
            ),
          ),
        );
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        if (page == 'invoices') {
          expect(find.textContaining('OLD-QUERY-INVOICE'), findsWidgets);
        }
        final field = find.byType(TextField).first;
        await t.ensureVisible(field);
        await t.pump();
        await t.tap(field);
        await t.enterText(field, 'TRACK-123');
        final editable = find.descendant(
          of: field,
          matching: find.byType(EditableText),
        );
        expect(t.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
        t.view.viewInsets = const FakeViewPadding(bottom: 320);
        await t.pump();
        await t.pump(const Duration(milliseconds: 350));
        final rect = t.getRect(editable);
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(524));
        expect(field.hitTestable(), findsOneWidget);
        if (page == 'invoices') {
          final originalFocus = t.widget<EditableText>(editable).focusNode;
          expect(find.textContaining('OLD-QUERY-INVOICE'), findsNothing);
          await t.pump(const Duration(seconds: 2));
          await t.pump();
          expect(
            t.widget<EditableText>(editable).focusNode,
            same(originalFocus),
          );
          expect(originalFocus.hasFocus, isTrue);
          final retry = find.text('Не удалось загрузить счета. Повторить');
          for (var i = 0; i < 5 && retry.evaluate().isEmpty; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          expect(
            retry,
            findsOneWidget,
            reason: find
                .byType(Text)
                .evaluate()
                .map((e) => (e.widget as Text).data)
                .toList()
                .toString(),
          );
          await t.ensureVisible(retry);
          await t.pump();
          await t.tap(retry);
          await t.pump();
          expect(originalFocus.hasFocus, isTrue);
          expect(t.widget<TextField>(field).controller!.text, 'TRACK-123');
          await t.pump(const Duration(seconds: 2));
          await t.pump();
          expect(originalFocus.hasFocus, isTrue);
          expect(
            t.widget<EditableText>(editable).focusNode,
            same(originalFocus),
          );
          expect(retry, findsNothing);
          expect(find.textContaining('OLD-QUERY-INVOICE'), findsNothing);
          await t.ensureVisible(field);
          await t.pump();
        }
        await t.tapAt(const Offset(4, 510));
        await t.pump();
        expect(t.widget<EditableText>(editable).focusNode.hasFocus, isFalse);
        await t.tap(field);
        await t.pump();
        expect(t.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
        await t.testTextInput.receiveAction(
          t.widget<EditableText>(editable).textInputAction ??
              TextInputAction.done,
        );
        await t.pump();
        expect(t.widget<EditableText>(editable).focusNode.hasFocus, isFalse);
        t.view.viewInsets = FakeViewPadding.zero;
        await t.pump(const Duration(milliseconds: 350));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(seconds: 10));
      });
    }
  }
}
