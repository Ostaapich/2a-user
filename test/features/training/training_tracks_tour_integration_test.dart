import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_toast.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/presentation/widgets/track_sheet_surface.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/data/assemblies_provider.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/presentation/tracks_screen.dart';
import 'package:twoalogisticcabineuser/src/features/training/data/assembly_training_session.dart';
import 'package:twoalogisticcabineuser/src/features/training/data/training_tour_controller.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_target.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_tour_overlay.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_tour_steps.dart';

class _Harness {
  late AssemblyTrainingSession session;
  late TrainingTourController controller;
  final registry = TrainingTargetRegistry();

  Future<void> pump(
    WidgetTester tester,
    List<String> ids, {
    bool created = false,
    String locale = 'ru',
  }) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() => initializeDateFormatting('ru'));
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    session = AssemblyTrainingSession(registry: registry);
    controller = TrainingTourController(prefs, scopeKey: 'integration');
    if (created) {
      final result = await tester.runAsync(
        () => session.container
            .read(assembliesApiServiceProvider)
            .createAssembly(
              clientId: assemblyTrainingClientId,
              clientCodeId: assemblyTrainingClientCodeId,
              tariffId: assemblyTrainingTariffId,
              packagingTypeIds: [assemblyTrainingPackagingId],
              placePreference: 'single_if_possible',
              goodsDescription: 'TRAINING',
              trackIds: assemblyTrainingTrackIds.take(2).toList(),
            ),
      );
      expect(result!.isSuccess, isTrue);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: session.container,
        child: MaterialApp(
          locale: Locale(locale),
          supportedLocales: const [Locale('ru'), Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const Scaffold(body: TracksScreen()),
          builder: (context, child) => Stack(
            children: [
              child!,
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) =>
                      !controller.active || controller.currentId == null
                      ? const SizedBox.shrink()
                      : Overlay.wrap(
                          child: TrainingTourOverlay(
                            controller: controller,
                            registry: registry,
                            step: trainingTourSteps(
                              context,
                            ).firstWhere((s) => s.id == controller.currentId),
                            access: TrainingServiceAccess.available,
                            currentPath: '/tracks',
                            navigate: (path) => expect(path, '/tracks'),
                            onExit: controller.stop,
                            onPractice: () {},
                            onRetryAccess: () {},
                            child: const SizedBox.expand(),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tick(tester);
    controller.start(ids, resume: false);
    await tick(tester);
  }

  Future<void> tick(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  Finder target(String id) {
    final context = registry.contextFor(id);
    expect(
      context,
      isNotNull,
      reason: 'Expected $id at ${controller.currentId}',
    );
    return find.byWidget(context!.widget);
  }

  Future<void> tap(WidgetTester tester, String id) async {
    await tester.ensureVisible(target(id));
    await tester.pumpAndSettle();
    await tester.tap(target(id));
    await tick(tester);
  }

  Future<void> waitForTarget(WidgetTester tester, String id) async {
    for (var attempt = 0; attempt < 12; attempt++) {
      if (registry.contextFor(id) != null) {
        await tick(tester);
        return;
      }
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }
    expect(registry.contextFor(id), isNotNull, reason: 'Auto-open $id');
  }

  Future<void> waitForSelectedTab(WidgetTester tester, String id) async {
    await waitForTarget(tester, id);
    for (var attempt = 0; attempt < 12; attempt++) {
      final context = registry.contextFor(id)!;
      if (registry.activationFor(id, context) == null) return;
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }
    expect(registry.activationFor(id, registry.contextFor(id)!), isNull);
  }

  void expectSpotlight(WidgetTester tester, String id) {
    final spotlight = find.byKey(const Key('tour-spotlight'));
    final paint = tester.widget<CustomPaint>(spotlight);
    final actual = ((paint.painter as dynamic).target as Rect).shift(
      tester.getTopLeft(spotlight),
    );
    final expected = tester
        .getRect(target(id))
        .intersect(tester.getRect(spotlight))
        .deflate(2);
    for (final pair in [
      (actual.left, expected.left),
      (actual.top, expected.top),
      (actual.right, expected.right),
      (actual.bottom, expected.bottom),
    ]) {
      expect(
        pair.$1,
        closeTo(pair.$2, 0.01),
        reason: 'Spotlight must enclose $id at ${controller.currentId}',
      );
    }
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 700));
    controller.dispose();
    session.dispose();
  }
}

void main() {
  for (final locale in ['ru', 'zh']) {
    testWidgets('real assembly wizard localized at320px $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = _Harness();
      await h.pump(tester, ['assembly:0'], locale: locale);
      h.controller.stop();
      await h.tick(tester);
      for (final code in assemblyTrainingTrackCodes.take(2)) {
        final checkbox = find.descendant(
          of: find.byKey(ValueKey('client-track-card-$code')),
          matching: find.byKey(const ValueKey('client-track-selection')),
        );
        await tester.ensureVisible(checkbox);
        await tester.tap(checkbox);
        await h.tick(tester);
      }
      await h.tap(tester, 'assembly.submit');
      expect(
        find.text(locale == 'ru' ? '1. Тариф и страховка' : '1. 运价与保险'),
        findsOneWidget,
      );
      expect(find.text(locale == 'ru' ? 'Далее' : '下一步'), findsOneWidget);
      final requiredDescription = h.registry.contextFor(
        'assembly.required.goods-description',
      );
      if (requiredDescription != null) {
        final field = find.descendant(
          of: find.byWidget(requiredDescription.widget),
          matching: find.byType(TextField),
        );
        await tester.ensureVisible(field);
        await tester.enterText(field, 'TRAINING GOODS');
        tester.testTextInput.hide();
        await h.tick(tester);
      }
      await tester.tap(find.text(locale == 'ru' ? 'Далее' : '下一步'));
      await h.tick(tester);
      expect(
        find.text(locale == 'ru' ? '2. Описание товаров' : '2. 商品描述'),
        findsOneWidget,
      );
      expect(
        find.text(locale == 'ru' ? 'Есть хрупкие товары' : '包含易碎品'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(h.session.submittedPayload, isNull);
      await h.finish(tester);
    });
  }

  testWidgets(
    'failed assembly note save keeps form and never publishes optimistic cache',
    (tester) async {
      final h = _Harness();
      await h.pump(tester, ['assembly:0'], created: true);
      h.controller.stop();
      await h.tick(tester);
      final switcher = h.registry.contextFor('tracks.view.switch-to-groups');
      if (switcher != null) {
        h.registry.activationFor('tracks.view.switch-to-groups', switcher)!();
        await h.tick(tester);
      }
      await h.waitForTarget(tester, 'assembly.open');
      await h.tap(tester, 'assembly.open');
      final edit = find.text('Добавить комментарий');
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await h.tick(tester);
      Finder noteSurface() => find
          .ancestor(
            of: find.text('Заметка по сборке'),
            matching: find.byWidgetPredicate(
              (widget) => widget is TrackSheetSurface,
            ),
          )
          .first;
      Finder noteField() =>
          find.descendant(of: noteSurface(), matching: find.byType(TextField));
      await tester.enterText(noteField(), 'UNSAVED NOTE');
      tester.testTextInput.hide();
      await h.tick(tester);
      await tester.tap(find.text('Сохранить заметку'));
      await h.tick(tester);
      expect(find.text('Заметка по сборке'), findsOneWidget);
      expect(
        tester.widget<TextField>(noteField()).controller!.text,
        'UNSAVED NOTE',
      );
      expect(
        h.session.rejectedRequests,
        contains('PATCH /assemblies/$assemblyTrainingAssemblyId'),
      );
      AppToast.hide();
      await tester.tap(
        find.descendant(of: noteSurface(), matching: find.text('Отмена')),
      );
      await h.tick(tester);
      expect(find.text('Не сохранять изменения?'), findsOneWidget);
      expect(
        tester.widget<TextField>(noteField()).controller!.text,
        'UNSAVED NOTE',
      );
      await tester.tap(find.text('Не сохранять'));
      await h.tick(tester);
      await tester.tap(find.text('Добавить комментарий'));
      await h.tick(tester);
      expect(
        tester.widget<TextField>(noteField()).controller!.text,
        isNot('UNSAVED NOTE'),
      );
      await h.finish(tester);
    },
  );

  testWidgets(
    'failed quick delivery save keeps selected method and form available',
    (tester) async {
      final h = _Harness();
      await h.pump(tester, ['assembly:0'], created: true);
      h.controller.stop();
      await h.tick(tester);
      final switcher = h.registry.contextFor('tracks.view.switch-to-groups');
      if (switcher != null) {
        h.registry.activationFor('tracks.view.switch-to-groups', switcher)!();
        await h.tick(tester);
      }
      final delivery = find.byKey(
        const ValueKey('client-track-action-Доставка'),
      );
      await tester.ensureVisible(delivery);
      await tester.tap(delivery);
      await h.tick(tester);
      await tester.tap(find.text('Самовывоз').last);
      await h.tick(tester);
      await tester.tap(find.text('Сохранить'));
      await h.tick(tester);
      expect(find.text('Способ получения'), findsOneWidget);
      expect(find.text('Самовывоз'), findsNWidgets(2));
      expect(
        h.session.rejectedRequests,
        contains('PATCH /assemblies/$assemblyTrainingAssemblyId'),
      );
      expect(tester.takeException(), isNull);
      AppToast.hide();
      await h.finish(tester);
    },
  );

  testWidgets('tour highlights then automatically opens the real add form', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(tester, ['tracks:0']);
    h.expectSpotlight(tester, 'tracks.add');
    expect(h.registry.contextFor('tracks.add.form'), isNull);
    await h.waitForTarget(tester, 'tracks.add.form');
    h.expectSpotlight(tester, 'tracks.add.form');
    expect(h.session.submittedPayload, isNull);
    expect(h.session.rejectedRequests, isEmpty);
    expect(tester.takeException(), isNull);
    await h.finish(tester);
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets('ordinary return-to-transfer guide closes form at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = _Harness();
      await h.pump(tester, ['track_actions:3', 'track_actions:4']);
      await h.tap(tester, 'track.return');
      expect(find.text('Возврат товара'), findsOneWidget);
      expect(h.registry.contextFor('track.transfer'), isNull);
      h.controller.next();
      await h.tick(tester);
      expect(find.byKey(const Key('tour-spotlight')), findsOneWidget);
      h.expectSpotlight(tester, 'track.sheet.dismiss-handle');
      await h.waitForTarget(tester, 'track.transfer');
      expect(find.text('Возврат товара'), findsNothing);
      expect(h.registry.contextFor('track.transfer'), isNotNull);
      h.expectSpotlight(tester, 'track.transfer');
      expect(h.session.submittedPayload, isNull);
      expect(h.session.rejectedRequests, isEmpty);
      expect(tester.takeException(), isNull);
      await h.finish(tester);
    });
  }

  testWidgets(
    'delivery guide finds groups then moves between real detail tabs',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = _Harness();
      await h.pump(tester, [
        'delivery:0',
        'delivery:1',
        'delivery:2',
        'delivery:3',
        'delivery:4',
      ], created: true);
      expect(h.registry.contextFor('assembly.open'), isNull);
      expect(h.registry.contextFor('tracks.view.switch-to-groups'), isNotNull);
      final originalPayload = h.session.submittedPayload;
      await h.waitForSelectedTab(tester, 'assembly.tab.tracks');
      h.controller.next();
      await h.tick(tester);
      await h.waitForSelectedTab(tester, 'assembly.tab.places');
      expect(find.text('Места сборки ещё не добавлены'), findsOneWidget);
      h.controller.next();
      await h.tick(tester);
      await h.waitForSelectedTab(tester, 'assembly.tab.delivery');
      h.controller.next();
      await h.tick(tester);
      await h.waitForSelectedTab(tester, 'assembly.tab.main');
      expect(h.registry.contextFor('assembly.status.details'), isNotNull);
      h.controller.next();
      await h.tick(tester);
      await h.waitForSelectedTab(tester, 'assembly.tab.video');
      expect(h.session.submittedPayload, same(originalPayload));
      expect(h.session.rejectedRequests, [
        'GET /client/assemblies/$assemblyTrainingAssemblyId/scan-sessions',
      ]);
      expect(tester.takeException(), isNull);
      await h.finish(tester);
    },
  );

  testWidgets(
    'ordinary wizard exposes required fields and preserves back navigation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = _Harness();
      await h.pump(tester, [
        'assembly:0',
        'assembly:1',
        'assembly:2',
        'assembly:3',
        'assembly:4',
      ]);
      expect(
        h.registry.activationFor(
          'tracks.selection',
          h.registry.contextFor('tracks.selection')!,
        ),
        isNull,
        reason: 'The tour must never choose real tracks for the client',
      );
      for (final code in assemblyTrainingTrackCodes.take(2)) {
        final checkbox = find.descendant(
          of: find.byKey(ValueKey('client-track-card-$code')),
          matching: find.byKey(const ValueKey('client-track-selection')),
        );
        await tester.ensureVisible(checkbox);
        await tester.tap(checkbox);
        await h.tick(tester);
      }
      h.controller.next();
      await h.tick(tester);
      await h.tap(tester, 'assembly.submit');
      h.controller.next();
      await h.tick(tester);
      expect(h.registry.contextFor('assembly.tariff'), isNotNull);
      await tester.tap(find.byKey(const Key('tour-collapse')));
      await h.tick(tester);
      await h.tap(tester, 'assembly.insurance');
      expect(
        h.registry.contextFor('assembly.required.insurance-amount'),
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('tour-collapse')));
      h.controller.next();
      await h.tick(tester);
      expect(h.registry.contextFor('assembly.wizard.ready.0'), isNull);
      h.expectSpotlight(tester, 'assembly.required.goods-description');
      final description = find.descendant(
        of: h.target('assembly.required.goods-description'),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(description);
      await tester.enterText(description, 'TRAINING');
      tester.testTextInput.hide();
      await h.tick(tester);
      expect(
        h.registry.contextFor('assembly.required.goods-description'),
        isNull,
      );
      h.expectSpotlight(tester, 'assembly.required.insurance-amount');
      final insuranceAmount = find.descendant(
        of: h.target('assembly.required.insurance-amount'),
        matching: find.byType(TextField),
      );
      await tester.enterText(insuranceAmount, '100');
      tester.testTextInput.hide();
      await h.tick(tester);
      expect(
        h.registry.contextFor('assembly.required.insurance-amount'),
        isNull,
      );
      await h.waitForTarget(tester, 'assembly.required.places');
      expect(h.registry.contextFor('assembly.wizard.ready.1'), isNull);
      h.expectSpotlight(tester, 'assembly.required.places');
      await h.tap(tester, 'assembly.required.places');
      expect(h.registry.contextFor('assembly.required.places'), isNull);
      await h.waitForTarget(tester, 'assembly.required.packaging');
      expect(h.registry.contextFor('assembly.required.packaging'), isNotNull);
      h.expectSpotlight(tester, 'assembly.required.packaging');
      h.controller.previous();
      await h.tick(tester);
      await h.waitForTarget(tester, 'assembly.tariff');
      expect(h.registry.contextFor('assembly.tariff'), isNotNull);
      h.controller.next();
      await h.tick(tester);
      await h.waitForTarget(tester, 'assembly.required.packaging');
      await h.tap(tester, 'assembly.required.packaging');
      expect(h.registry.contextFor('assembly.required.packaging'), isNull);
      h.controller.next();
      await h.tick(tester);
      await h.waitForTarget(tester, 'assembly.review');
      expect(h.registry.contextFor('assembly.review'), isNotNull);
      expect(
        h.registry.activationFor(
          'assembly.wizard.ready.3',
          h.registry.contextFor('assembly.wizard.ready.3')!,
        ),
        isNull,
        reason: 'Final submission must always remain a manual decision',
      );
      h.controller.previous();
      await h.tick(tester);
      await h.waitForTarget(tester, 'assembly.packaging');
      expect(h.registry.contextFor('assembly.packaging'), isNotNull);
      expect(h.session.assemblyCreated, isFalse);
      expect(h.session.rejectedRequests, isEmpty);
      expect(tester.takeException(), isNull);
      await h.finish(tester);
    },
  );

  testWidgets('empty groups keep only useful switch-back preparation', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(tester, ['tracks:1']);
    await h.tap(tester, 'tracks.view.switch-to-groups');
    expect(h.registry.contextFor('track.status'), isNull);
    expect(h.registry.contextFor('tracks.view.switch-to-groups'), isNull);
    expect(h.registry.contextFor('tracks.view.switch-to-singles'), isNotNull);
    h.expectSpotlight(tester, 'tracks.view.switch-to-singles');
    await h.waitForTarget(tester, 'track.status');
    expect(h.registry.contextFor('track.status'), isNotNull);
    expect(h.registry.contextFor('tracks.view.switch-to-singles'), isNull);
    await h.finish(tester);
  });
}
