import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../helpers/keyboard_acceptance.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/core/persistence/shared_preferences_provider.dart';
import 'package:twoalogisticcabineuser/src/features/training/data/assembly_training_session.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_target.dart';
import 'package:twoalogisticcabineuser/src/features/home/presentation/home_screen.dart';
import 'package:twoalogisticcabineuser/src/features/home/data/home_counts_provider.dart';
import 'package:twoalogisticcabineuser/src/features/home/data/current_cny_rate_provider.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/data/tracks_provider.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/domain/track_item.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/presentation/tracks_screen.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/presentation/widgets/client_track_compact_card.dart';
import 'package:twoalogisticcabineuser/src/features/assemblies/data/assemblies_provider.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/data/invoices_provider.dart';
import 'package:twoalogisticcabineuser/src/features/photos/data/photos_provider.dart';
import 'package:twoalogisticcabineuser/src/features/profile/data/profile_provider.dart';
import 'package:twoalogisticcabineuser/src/features/referral/data/referral_provider.dart';

class _ReturnlessTracks extends TracksApiService {
  _ReturnlessTracks(super.ref);
  @override
  Future<TrackReturnInfo?> getTrackReturn(int trackId) async => null;
}

Future<TrainingTargetRegistry> _pump(
  WidgetTester t,
  String mode,
  double width,
) async {
  SharedPreferences.setMockInitialValues({'terms_accepted': true});
  final prefs = await SharedPreferences.getInstance();
  final registry = TrainingTargetRegistry(),
      session = AssemblyTrainingSession(registry: registry);
  addTearDown(session.dispose);
  final response = await t.runAsync(
    () => session.container
        .read(apiClientProvider)
        .get(
          '/tracks',
          queryParameters: {'clientCode': assemblyTrainingClientCode},
        ),
  );
  final rows = (response!.data['data'] as List)
      .map((row) => TrackItem.fromJson(Map<String, dynamic>.from(row as Map)))
      .toList();
  final child = ProviderContainer(
    parent: session.container,
    overrides: [
      tracksApiServiceProvider.overrideWith(_ReturnlessTracks.new),
      sharedPreferencesProvider.overrideWithValue(prefs),
      clientProfileProvider.overrideWith((_) async => null),
      tracksDigestProvider(
        assemblyTrainingClientCode,
      ).overrideWith((_) async => rows),
      assembliesDigestProvider(
        assemblyTrainingClientCode,
      ).overrideWith((_) async => []),
      invoicesDigestProvider(
        assemblyTrainingClientCode,
      ).overrideWith((_) async => []),
      homeTracksCountProvider(
        assemblyTrainingClientCode,
      ).overrideWith((_) async => 2),
      homePendingTracksCountProvider(
        assemblyTrainingClientCode,
      ).overrideWith((_) async => 1),
      homeAssembliesCountProvider(
        assemblyTrainingClientCode,
      ).overrideWith((_) async => 0),
      invoicesCountProvider(
        assemblyTrainingClientCode,
      ).overrideWith((_) async => 0),
      photosRecentProvider.overrideWith((_, arg) async => []),
      currentCnyRateProvider.overrideWith((_) async => null),
      referralProvider.overrideWith(
        (_) async => const ReferralData(
          referralKgBalance: 0,
          referrals: [],
          transactions: [],
        ),
      ),
    ],
  );
  addTearDown(child.dispose);
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(width, 1100);
  addTearDown(t.view.resetDevicePixelRatio);
  addTearDown(t.view.resetPhysicalSize);
  Widget body = switch (mode) {
    'home' => const HomeScreen(),
    'tracks' => const TracksScreen(),
    'orphan' => SingleChildScrollView(
      child: TracksScreen.embedded(tracks: [rows.first, rows.last]),
    ),
    _ => SingleChildScrollView(
      child: TracksScreen.embedded(tracks: [rows.last]),
    ),
  };
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: child,
      child: MaterialApp(
        theme: ThemeData(fontFamily: 'Gilroy'),
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: body),
      ),
    ),
  );
  await t.pumpAndSettle();
  return registry;
}

Finder _card(String code) => find.ancestor(
  of: find.byKey(ValueKey('client-track-card-$code')),
  matching: find.byType(ClientTrackCompactCard),
);
Future<void> _reveal(WidgetTester t, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
  } else {
    await t.ensureVisible(finder);
  }
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    await loadKeyboardAcceptanceFonts();
  });
  for (final width in [320.0, 390.0]) {
    for (final mode in ['embedded', 'tracks', 'home']) {
      testWidgets('no duplicate lower actions $mode width$width', (t) async {
        await _pump(t, mode, width);
        final card = _card(assemblyTrainingTrackCodes.last);
        await _reveal(t, card);
        final widget = t.widget<ClientTrackCompactCard>(card);
        expect(
          widget.actions.map((action) => action.label),
          everyElement(
            isNot(isIn(['О товаре', 'Вопрос', 'Вопросы', 'Фотоотчёт'])),
          ),
        );
        expect(
          widget.indicators.map((indicator) => indicator.title),
          containsAll(['Товар', 'Фото', 'Вопросы']),
        );
        expect(
          widget.actions.map((action) => action.label),
          containsAll(['Перенести', 'Заметка']),
        );
        if (mode != 'embedded') {
          final warehouse = _card(assemblyTrainingTrackCodes.first);
          await _reveal(t, warehouse);
          expect(
            t
                .widget<ClientTrackCompactCard>(warehouse)
                .actions
                .map((action) => action.label),
            containsAll(['Перенести', 'Заметка', 'Возврат']),
          );
        }
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(seconds: 12));
      });
    }
  }
  for (final tab in [0, 2, 3]) {
    testWidgets('upper indicator$tab preserves its workflow', (t) async {
      await _pump(t, 'embedded', 390);
      final card = _card(assemblyTrainingTrackCodes.last);
      await _reveal(t, card);
      final upper = find.descendant(
        of: card,
        matching: find.byKey(ValueKey('client-track-indicator-$tab')),
      );
      await t.tap(upper);
      await t.pumpAndSettle();
      if (tab == 0) {
        final edit = find.text('Заполнить информацию');
        await _reveal(t, edit);
        await t.tap(edit);
        await t.pumpAndSettle();
        expect(find.byType(TextField), findsNWidgets(2));
      } else if (tab == 2) {
        final choose = find.text('Выбрать фотоотчёт');
        await _reveal(t, choose);
        expect(choose.hitTestable(), findsOneWidget);
        final button = find
            .ancestor(of: choose, matching: find.byType(InkWell))
            .first;
        expect(t.widget<InkWell>(button).onTap, isNotNull);
      } else {
        final create = find.text('Создать новый вопрос');
        await _reveal(t, create);
        await t.tap(create);
        await t.pumpAndSettle();
        expect(
          find.text(
            'Не знаю что это за трек номер, могли бы проверить и код клиента и трек номер',
          ),
          findsOneWidget,
        );
        expect(find.text('Отправить'), findsOneWidget);
      }
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 12));
    });
  }
  testWidgets(
    'orphan grouped fallback retains unique actions without upper duplicates',
    (t) async {
      await _pump(t, 'orphan', 390);
      expect(
        find.byKey(const ValueKey('client-track-indicator-0')),
        findsNothing,
      );
      final legacy = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_ActionChipButton',
      );
      for (final label in ['О товаре', 'Вопрос', 'Фотоотчёт']) {
        expect(
          find.descendant(of: legacy, matching: find.text(label)),
          findsWidgets,
        );
      }
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 12));
    },
  );
  testWidgets('question training anchor moves to upper indicator', (t) async {
    final registry = await _pump(t, 'tracks', 390);
    final target = registry.contextFor('track.question');
    expect(target, isNotNull);
    final anchor = find.byWidget(target!.widget);
    expect(
      find.descendant(
        of: anchor,
        matching: find.byKey(const ValueKey('client-track-indicator-3')),
      ),
      findsOneWidget,
    );
    await _reveal(t, anchor);
    await t.tap(anchor);
    await t.pumpAndSettle();
    expect(find.text('Создать новый вопрос'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 12));
  });
}
