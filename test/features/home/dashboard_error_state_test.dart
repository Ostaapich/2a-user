import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/core/cache/stale_data_cache.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/core/persistence/shared_preferences_provider.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/data/tracks_provider.dart';
import 'package:twoalogisticcabineuser/src/features/assemblies/data/assemblies_provider.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/data/invoices_provider.dart';
import 'package:twoalogisticcabineuser/src/features/home/presentation/home_screen.dart';
import 'package:twoalogisticcabineuser/src/features/home/data/current_cny_rate_provider.dart';
import 'package:twoalogisticcabineuser/src/features/home/data/home_counts_provider.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/auth_provider.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/profile/data/profile_provider.dart';
import 'package:twoalogisticcabineuser/src/features/photos/data/photos_provider.dart';
import 'package:twoalogisticcabineuser/src/features/referral/data/referral_provider.dart';

class _UnavailableApi extends ApiClient {
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    throw DioException(
      requestOptions: RequestOptions(path: path),
      type: DioExceptionType.connectionError,
    );
  }
}

class _LoggedIn extends AuthNotifier {
  @override
  AuthState build() => const AuthState(isLoggedIn: true, isLoading: false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'dashboard retries failed data without refetching successful cards',
    (tester) async {
      SharedPreferences.setMockInitialValues({'terms_accepted': true});
      final prefs = await SharedPreferences.getInstance();
      var trackCalls = 0;
      var assemblyCalls = 0;
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authProvider.overrideWith(_LoggedIn.new),
          activeClientCodeProvider.overrideWithValue('TEST'),
          clientProfileProvider.overrideWith((ref) async => null),
          homeTracksCountProvider('TEST').overrideWith((ref) async {
            if (++trackCalls == 1) throw StateError('offline');
            return 7;
          }),
          homePendingTracksCountProvider('TEST').overrideWith((ref) async => 0),
          homeAssembliesCountProvider('TEST').overrideWith((ref) async {
            assemblyCalls++;
            return 37;
          }),
          invoicesCountProvider('TEST').overrideWith((ref) async => 8),
          tracksWeeklyCountProvider('TEST').overrideWith((ref) async => 1),
          assembliesWeeklyCountProvider('TEST').overrideWith((ref) async => 2),
          invoicesWeeklyCountProvider('TEST').overrideWith((ref) async => 3),
          tracksDigestProvider('TEST').overrideWith((ref) async => []),
          assembliesDigestProvider('TEST').overrideWith((ref) async => []),
          invoicesDigestProvider('TEST').overrideWith((ref) async => []),
          photosRecentProvider.overrideWith((ref, arg) async => []),
          currentCnyRateProvider.overrideWith((ref) async => null),
          referralProvider.overrideWith(
            (ref) async => throw StateError('unused'),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: HomeScreen())),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('dashboard-load-error')),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Повторить'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dashboard-load-error')), findsNothing);
      expect(container.read(homeTracksCountProvider('TEST')).requireValue, 7);
      expect(assemblyCalls, 1);
      expect(trackCalls, 2);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'unavailable uncached dashboard remains error instead of false zero/empty',
    () async {
      SharedPreferences.setMockInitialValues({});
      await StaleDataCache.clearAll();
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [apiClientProvider.overrideWithValue(_UnavailableApi())],
      );
      addTearDown(container.dispose);
      final providers = [
        tracksDigestProvider('TEST'),
        homeTracksCountProvider('TEST'),
        homePendingTracksCountProvider('TEST'),
        tracksWeeklyCountProvider('TEST'),
        assembliesDigestProvider('TEST'),
        homeAssembliesCountProvider('TEST'),
        assembliesWeeklyCountProvider('TEST'),
        invoicesDigestProvider('TEST'),
        invoicesCountProvider('TEST'),
        invoicesWeeklyCountProvider('TEST'),
      ];
      for (final provider in providers) {
        await expectLater(
          container.read(provider.future),
          throwsA(isA<DioException>()),
        );
        expect(container.read(provider).hasError, isTrue);
      }
    },
  );
}
