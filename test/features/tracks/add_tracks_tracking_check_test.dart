import '../../helpers/keyboard_draft_acceptance.dart';
import '../../helpers/keyboard_acceptance.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/core/persistence/shared_preferences_provider.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/auth_provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/features/add_tracks/data/add_tracks_repository.dart';
import 'package:twoalogisticcabineuser/src/features/add_tracks/data/track_tracking_check_repository.dart';
import 'package:twoalogisticcabineuser/src/features/add_tracks/domain/add_tracks_result.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/presentation/add_tracks_dialog.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('Gilroy')
          ..addFont(rootBundle.load('assets/fonts/gilroy/Gilroy-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/gilroy/Gilroy-Bold.ttf'))
          ..addFont(rootBundle.load('assets/fonts/gilroy/Gilroy-Black.ttf')))
        .load();
  });
  testWidgets(
    'отслеживаемые треки добавляются сразу, остальные можно исправить',
    (tester) async {
      final checkRepository = _FakeCheckRepository([
        const TrackTrackingCheckResult(
          configured: true,
          checkAvailable: true,
          items: [
            TrackTrackingCheckItem(
              code: 'TRACKABLE',
              status: TrackTrackingStatus.trackable,
            ),
            TrackTrackingCheckItem(
              code: 'NOTYET',
              status: TrackTrackingStatus.unconfirmed,
              reason: TrackTrackingReason.noTrackingData,
            ),
          ],
        ),
        const TrackTrackingCheckResult(
          configured: true,
          checkAvailable: true,
          items: [
            TrackTrackingCheckItem(
              code: 'FIXED',
              status: TrackTrackingStatus.trackable,
            ),
          ],
        ),
      ]);
      final addRepository = _FakeAddRepository();
      await _pumpLauncher(
        tester,
        checkRepository: checkRepository,
        addRepository: addRepository,
      );

      await tester.tap(find.text('Добавить треки'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'TRACKABLE\nNOTYET');
      await tester.tap(find.text('Проверить и добавить'));
      await tester.pumpAndSettle();

      expect(addRepository.calls, [
        ['TRACKABLE'],
      ]);
      expect(find.text('Проверьте эти трек-номера'), findsOneWidget);
      expect(find.text('История доставки пока не найдена'), findsOneWidget);
      expect(find.text('Уже добавлено автоматически: 1'), findsOneWidget);

      final reviewField = find.descendant(
        of: find.byKey(const ValueKey('unconfirmed-track-0')),
        matching: find.byType(TextField),
      );
      await tester.enterText(reviewField, 'FIXED');
      await tester.tap(find.text('Проверить исправления'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(checkRepository.calls, [
        ['TRACKABLE', 'NOTYET'],
        ['FIXED'],
      ]);
      expect(addRepository.calls, [
        ['TRACKABLE'],
        ['FIXED'],
      ]);
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets('не найденный у перевозчика номер можно подтвердить', (
    tester,
  ) async {
    final checkRepository = _FakeCheckRepository([
      const TrackTrackingCheckResult(
        configured: true,
        checkAvailable: true,
        items: [
          TrackTrackingCheckItem(
            code: 'NEWTRACK',
            status: TrackTrackingStatus.unconfirmed,
            reason: TrackTrackingReason.carrierNotRecognized,
          ),
        ],
      ),
    ]);
    final addRepository = _FakeAddRepository();
    await _pumpLauncher(
      tester,
      checkRepository: checkRepository,
      addRepository: addRepository,
    );

    await tester.tap(find.text('Добавить треки'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'NEWTRACK');
    await tester.tap(find.text('Проверить и добавить'));
    await tester.pumpAndSettle();

    expect(find.text('Служба доставки не определена'), findsOneWidget);
    final confirmButton = find.text('Всё указано верно — добавить');
    await tester.ensureVisible(confirmButton);
    await tester.pumpAndSettle();
    await tester.tap(confirmButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(addRepository.calls, [
      ['NEWTRACK'],
    ]);
    await tester.pump(const Duration(seconds: 2));
  });
  testWidgets(
    'track draft survives interrupted screen and stays scoped to account',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      Future<void> launch({int clientId = 7}) => _pumpLauncher(
        tester,
        checkRepository: _FakeCheckRepository([]),
        addRepository: _FakeAddRepository(),
        preferences: prefs,
        clientId: clientId,
      );
      await launch();
      await tester.tap(find.text('Добавить треки'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'DRAFT-123');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await launch(clientId: 8);
      await tester.tap(find.text('Добавить треки'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await launch();
      await tester.tap(find.text('Добавить треки'));
      await tester.pumpAndSettle();
      expect(find.text('DRAFT-123'), findsOneWidget);
      await tester.tap(find.byTooltip('Закрыть'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Не сохранять'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Добавить треки'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('actual add tracks IME focus and close ${platform.name}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      await _pumpLauncher(
        tester,
        platform: platform,
        checkRepository: _FakeCheckRepository([]),
        addRepository: _FakeAddRepository(),
      );
      await tester.tap(find.text('Добавить треки'));
      await tester.pumpAndSettle();
      final field = find.byType(TextField).first;
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pump();
      final editable = find.descendant(
        of: field,
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();
      expectFocusedCaretAboveIme(tester, editable);
      expect(MediaQuery.viewInsetsOf(tester.element(field)).bottom, 0);
      final close = find.byTooltip('Закрыть');
      await tester.ensureVisible(close);
      await tester.pump();
      expect(close.hitTestable(), findsOneWidget);
      expect(tester.getRect(close).top, greaterThanOrEqualTo(50));
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'unconfirmed correction retains typed code above IME ${platform.name}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetViewInsets);
        final check = _FakeCheckRepository([
          const TrackTrackingCheckResult(
            configured: true,
            checkAvailable: true,
            items: [
              TrackTrackingCheckItem(
                code: 'NOTYET',
                status: TrackTrackingStatus.unconfirmed,
                reason: TrackTrackingReason.noTrackingData,
              ),
            ],
          ),
        ]);
        final add = _FakeAddRepository();
        await _pumpLauncher(
          tester,
          platform: platform,
          checkRepository: check,
          addRepository: add,
        );
        await tester.tap(find.text('Добавить треки'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'NOTYET');
        await tester.tap(find.text('Проверить и добавить'));
        await tester.pumpAndSettle();
        final correction = find.descendant(
          of: find.byKey(const ValueKey('unconfirmed-track-0')),
          matching: find.byType(EditableText),
        );
        expect(correction, findsOneWidget);
        await typeDraftThroughIme(
          tester,
          tester.widget<EditableText>(correction).controller,
          'FIXED-123',
        );
        expect(
          add.calls,
          isEmpty,
          reason: 'typing correction must not submit anything',
        );
        expect(check.calls, [
          ['NOTYET'],
        ]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}

class _DraftAuth extends AuthNotifier {
  _DraftAuth(this.clientId);
  final int clientId;
  @override
  AuthState build() => AuthState(
    isLoggedIn: true,
    isLoading: false,
    clientId: clientId,
    userDomain: 'test.invalid',
  );
}

Future<void> _pumpLauncher(
  WidgetTester tester, {
  required TrackTrackingCheckRepository checkRepository,
  required AddTracksRepository addRepository,
  SharedPreferences? preferences,
  int clientId = 7,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  if (preferences == null) SharedPreferences.setMockInitialValues({});
  final prefs = preferences ?? await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeClientCodeProvider.overrideWithValue('A-001'),
        authProvider.overrideWith(() => _DraftAuth(clientId)),
        sharedPreferencesProvider.overrideWithValue(prefs),
        trackTrackingCheckRepositoryProvider.overrideWithValue(checkRepository),
        addTracksRepositoryProvider.overrideWithValue(addRepository),
      ],
      child: MaterialApp(
        theme: ThemeData(fontFamily: 'Gilroy', platform: platform),
        builder: (context, child) => AppKeyboardDismissRegion(child: child!),
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('zh')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => showAddTracksDialog(context, ref),
              child: const Text('Добавить треки'),
            ),
          ),
        ),
      ),
    ),
  );
}

class _FakeCheckRepository implements TrackTrackingCheckRepository {
  final List<TrackTrackingCheckResult> responses;
  final List<List<String>> calls = [];

  _FakeCheckRepository(this.responses);

  @override
  Future<TrackTrackingCheckResult> check({
    required String clientCode,
    required List<String> trackCodes,
  }) async {
    calls.add(List.of(trackCodes));
    return responses.removeAt(0);
  }
}

class _FakeAddRepository implements AddTracksRepository {
  final List<List<String>> calls = [];

  @override
  Future<AddTracksResult> addTracks({
    required String clientCode,
    required List<String> trackCodes,
  }) async {
    calls.add(List.of(trackCodes));
    return AddTracksResult(added: trackCodes.length, skipped: const []);
  }
}
