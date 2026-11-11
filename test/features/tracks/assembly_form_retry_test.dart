import '../../helpers/keyboard_acceptance.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/core/cache/stale_data_cache.dart';
import 'package:twoalogisticcabineuser/src/core/persistence/shared_preferences_provider.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/auth_provider.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/presentation/tracks_screen.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/presentation/widgets/client_track_compact_card.dart';
import 'package:twoalogisticcabineuser/src/features/training/data/assembly_training_session.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_target.dart';

class _FailFirstAssemblyApi extends ApiClient {
  _FailFirstAssemblyApi(this.delegate);
  final ApiClient delegate;
  final attempts = <Map<String, dynamic>>[];
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) =>
      delegate.get<T>(path, queryParameters: queryParameters, options: options);
  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    if (path == '/assemblies') {
      attempts.add(Map<String, dynamic>.from(data as Map));
      if (attempts.length == 1) {
        throw DioException(
          requestOptions: RequestOptions(path: path),
          type: DioExceptionType.connectionError,
        );
      }
    }
    return delegate.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }
}

class _Auth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    isLoggedIn: true,
    isLoading: false,
    clientId: assemblyTrainingClientId,
    userDomain: 'training.invalid',
  );
}

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'failed assembly request preserves live form and retries same intention ${platform.name}',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        await initializeDateFormatting('ru');
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetViewInsets);
        final registry = TrainingTargetRegistry();
        final sandbox = AssemblyTrainingSession(registry: registry);
        addTearDown(sandbox.dispose);
        final api = _FailFirstAssemblyApi(
          sandbox.container.read(apiClientProvider),
        );
        final container = ProviderContainer(
          overrides: [
            apiClientProvider.overrideWithValue(api),
            authProvider.overrideWith(_Auth.new),
            activeClientCodeProvider.overrideWithValue(
              assemblyTrainingClientCode,
            ),
            activeClientCodeIdProvider.overrideWithValue(
              assemblyTrainingClientCodeId,
            ),
            staleDataCacheEnabledProvider.overrideWithValue(false),
            sharedPreferencesProvider.overrideWithValue(prefs),
            trainingTargetRegistryProvider.overrideWithValue(registry),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(fontFamily: 'Gilroy', platform: platform),
              builder: (context, child) =>
                  AppKeyboardDismissRegion(child: child!),
              home: const Scaffold(body: TracksScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> tapTarget(String id) async {
          var targetContext = registry.contextFor(id);
          if (targetContext == null) {
            final target = find.byWidgetPredicate(
              (widget) => widget is TrainingTarget && widget.id == id,
            );
            final surface = find
                .byWidgetPredicate(
                  (widget) =>
                      widget.runtimeType.toString() == '_TrackSheetSurface',
                )
                .last;
            await tester.scrollUntilVisible(
              target,
              180,
              scrollable: find
                  .descendant(of: surface, matching: find.byType(Scrollable))
                  .first,
            );
            await tester.pumpAndSettle();
            targetContext = registry.contextFor(id);
          }
          expect(targetContext, isNotNull, reason: id);
          final finder = find.byWidget(targetContext!.widget);
          await tester.ensureVisible(finder);
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        for (final code in assemblyTrainingTrackCodes.take(2)) {
          final card = find.byWidgetPredicate(
            (widget) =>
                widget is ClientTrackCompactCard && widget.trackNumber == code,
          );
          final checkbox = find.descendant(
            of: card,
            matching: find.byKey(const ValueKey('client-track-selection')),
          );
          await tester.ensureVisible(checkbox);
          await tester.tap(checkbox);
          await tester.pumpAndSettle();
        }
        await tapTarget('assembly.submit');
        expect(
          await exerciseCurrentRouteEditors(tester),
          greaterThanOrEqualTo(1),
        );
        final description = find.descendant(
          of: find.byWidget(
            registry.contextFor('assembly.goods-description')!.widget,
          ),
          matching: find.byType(TextField),
        );
        await tester.ensureVisible(description);
        await tester.enterText(description, 'Сохранённое описание');
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
        await tapTarget('assembly.insurance');
        expect(await exerciseCurrentRouteEditors(tester), 2);
        await tapTarget('assembly.insurance');
        await tapTarget('assembly.wizard.next.0');
        await tapTarget('assembly.places.single_if_possible');
        await tapTarget('assembly.wizard.next.1');
        await tapTarget('assembly.packaging');
        await tapTarget('assembly.wizard.next.2');
        await tapTarget('assembly.review');
        expect(sandbox.assemblyCreated, false);
        expect(find.text('4. Подтверждение'), findsOneWidget);
        expect(find.text('Сохранённое описание'), findsOneWidget);
        await tapTarget('assembly.review');
        expect(sandbox.assemblyCreated, true);
        expect(api.attempts.length, 2);
        expect(api.attempts.first, api.attempts.last);
        expect(find.text('4. Подтверждение'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 4));
      },
    );
  }
}
