import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/app/widgets/app_scaffold.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:twoalogisticcabineuser/src/core/ui/blurred_modal_bottom_sheet.dart';
import 'package:twoalogisticcabineuser/src/core/ui/searchable_document.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/clients/domain/client_codes_state.dart';
import 'package:twoalogisticcabineuser/src/features/more/presentation/more_sheet.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/application/notifications_controller.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/domain/notification_item.dart';
import 'package:twoalogisticcabineuser/src/features/rules/data/rules_provider.dart';
import 'package:twoalogisticcabineuser/src/features/rules/domain/rule_item.dart';
import 'package:twoalogisticcabineuser/src/features/rules/presentation/rules_screen.dart';
import '../../helpers/keyboard_acceptance.dart';

class _Codes extends ClientCodesController {
  @override
  Future<ClientCodesState> build() async =>
      const ClientCodesState(codes: ['TEST'], activeCode: 'TEST');
}

class _Notifications extends NotificationsController {
  @override
  Future<List<NotificationItem>> build() async => const [];
}

class _Api extends ApiClient {
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async => Response<T>(
    requestOptions: RequestOptions(path: path),
    statusCode: 200,
    data: <String, dynamic>{'data': <dynamic>[], 'available': false} as T,
  );
}

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final page in ['rules', 'document', 'more']) {
      testWidgets(
        '$page actual input automatic keyboard visibility $platform',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 844);
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            ProviderScope(
              retry: (_, _) => null,
              overrides: [
                apiClientProvider.overrideWithValue(_Api()),
                clientCodesControllerProvider.overrideWith(_Codes.new),
                notificationsControllerProvider.overrideWith(
                  _Notifications.new,
                ),
                rulesListProvider.overrideWith(
                  (_) async => const [
                    RuleItem(
                      slug: 'test',
                      title: 'Fixture',
                      content: 'Fixture text',
                      excerpt: 'Fixture',
                      order: 1,
                    ),
                  ],
                ),
              ],
              child: MaterialApp(
                theme: ThemeData(platform: platform, fontFamily: 'Gilroy'),
                builder: (_, child) => AppKeyboardDismissRegion(child: child!),
                home: Builder(
                  builder: (context) => AppScaffold(
                    title: 'Fixture',
                    child: page == 'rules'
                        ? const RulesScreen()
                        : page == 'document'
                        ? const SingleChildScrollView(
                            padding: EdgeInsets.only(top: 120),
                            child: SearchableDocument(
                              contentIdentity: 'Fixture',
                              child: Text('Fixture text'),
                            ),
                          )
                        : Center(
                            child: TextButton(
                              onPressed: () =>
                                  showBlurredModalBottomSheet<void>(
                                    context: context,
                                    isScrollControlled: true,
                                    builder: (_) => const MoreSheet(),
                                  ),
                              child: const Text('open more'),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          if (page == 'more') {
            await tester.tap(find.text('open more'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
          }
          expect(await exerciseCurrentRouteEditors(tester), 1);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 10));
        },
      );
    }
  }
}
