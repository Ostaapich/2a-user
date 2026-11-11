import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/services/demo_mode_provider.dart';
import 'package:twoalogisticcabineuser/src/core/ui/tutorial_card.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_lessons.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_target.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_tour_steps.dart';

void main() {
  Widget surface(TrainingTargetRegistry registry, Widget child) =>
      ProviderScope(
        overrides: [trainingTargetRegistryProvider.overrideWithValue(registry)],
        child: MaterialApp(home: Scaffold(body: child)),
      );

  testWidgets('root dialog obscures nested navigator anchors until dismissed', (
    tester,
  ) async {
    final registry = TrainingTargetRegistry();
    late BuildContext nestedContext;
    await tester.pumpWidget(
      surface(
        registry,
        Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (context) {
              nestedContext = context;
              return const Scaffold(
                body: TrainingTarget(
                  id: 'nested.screen',
                  child: Text('Nested page'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final originalContext = registry.contextFor('nested.screen');
    expect(originalContext, isNotNull);

    final dialog = showDialog<void>(
      context: nestedContext,
      useRootNavigator: true,
      builder: (_) => const AlertDialog(
        content: TrainingTarget(id: 'modal.content', child: Text('Root modal')),
      ),
    );
    await tester.pumpAndSettle();
    expect(originalContext!.mounted, isTrue);
    expect(registry.contextFor('nested.screen'), isNull);
    expect(registry.contextFor('modal.content'), isNotNull);

    Navigator.of(nestedContext, rootNavigator: true).pop();
    await tester.pumpAndSettle();
    await dialog;
    expect(registry.contextFor('nested.screen'), same(originalContext));
    expect(registry.contextFor('modal.content'), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'duplicate id resolves visible branch even if offstage registers last',
    (tester) async {
      final registry = TrainingTargetRegistry();
      await tester.pumpWidget(
        surface(
          registry,
          const Column(
            children: [
              TrainingTarget(id: 'shared', child: Text('Visible branch')),
              Offstage(
                offstage: true,
                child: TrainingTarget(
                  id: 'shared',
                  child: Text('Hidden branch'),
                ),
              ),
            ],
          ),
        ),
      );
      final context = registry.contextFor('shared');
      expect(context, isNotNull);
      expect(
        find.descendant(
          of: find.byWidget(context!.widget),
          matching: find.text('Visible branch'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byWidget(context.widget),
          matching: find.text('Hidden branch', skipOffstage: false),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'detached bindings unregister even if their key stays mounted elsewhere',
    (tester) async {
      final registry = TrainingTargetRegistry();
      final targetKey = GlobalKey();
      await tester.pumpWidget(
        surface(
          registry,
          Column(
            children: [
              TrainingTargetBindings(
                targets: {'target': targetKey},
                child: const SizedBox(),
              ),
              SizedBox(key: targetKey, width: 40, height: 40),
            ],
          ),
        ),
      );
      expect(registry.contextFor('target'), same(targetKey.currentContext));
      await tester.pumpWidget(
        surface(
          registry,
          Column(
            children: [
              const SizedBox(),
              SizedBox(key: targetKey, width: 40, height: 40),
            ],
          ),
        ),
      );
      expect(targetKey.currentContext, isNotNull);
      expect(registry.contextFor('target'), isNull);
    },
  );

  testWidgets('updating binding id removes old registration', (tester) async {
    final registry = TrainingTargetRegistry();
    final targetKey = GlobalKey();
    Widget binding(String id) => TrainingTargetBindings(
      targets: {id: targetKey},
      child: SizedBox(key: targetKey, width: 40, height: 40),
    );
    await tester.pumpWidget(surface(registry, binding('old')));
    await tester.pumpWidget(surface(registry, binding('new')));
    expect(registry.contextFor('old'), isNull);
    expect(registry.contextFor('new'), same(targetKey.currentContext));
    await tester.pumpWidget(const SizedBox());
    expect(registry.contextFor('new'), isNull);
  });

  testWidgets(
    'legacy wrapper registers normal UI without activating demo overlay',
    (tester) async {
      final registry = TrainingTargetRegistry();
      final targetKey = GlobalKey();
      await tester.pumpWidget(
        surface(
          registry,
          TutorialScreenWrapper(
            screenKey: 'test',
            steps: [
              TutorialStep(
                title: 'Overlay title',
                description: 'Overlay description',
                icon: Icons.info,
                targetKey: targetKey,
              ),
            ],
            child: SizedBox(
              key: targetKey,
              child: const Text('Real interface'),
            ),
          ),
        ),
      );
      await tester.pump();
      final context = tester.element(find.byType(TutorialScreenWrapper));
      expect(
        ProviderScope.containerOf(context).read(demoModeProvider),
        isFalse,
      );
      expect(
        registry.contextFor('legacy.test.0'),
        same(targetKey.currentContext),
      );
      expect(find.text('Real interface'), findsOneWidget);
      expect(find.text('Overlay title'), findsNothing);
      expect(find.text('Завершить обучение'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'localized tour covers 55 unique steps and 19 registered routes',
    (tester) async {
      const routes = {
        '/',
        '/tracks',
        '/invoices',
        '/photos',
        '/support',
        '/profile',
        '/calculator',
        '/search-nocode',
        '/payment-chat',
        '/news',
        '/rules',
        '/referral',
        '/partner-program',
        '/tariffs',
        '/shop',
        '/sp-finance',
        '/garage',
        '/self-buyout',
        '/purchase-blanks',
      };
      const capabilities = {
        '/self-buyout': 'self_buyout',
        '/garage': 'garage',
        '/shop': 'shop',
        '/partner-program': 'partner_program',
      };
      final routerSource = File('lib/src/app/router.dart').readAsStringSync();
      final registered = RegExp(
        r"path:\s*'([^']+)'",
      ).allMatches(routerSource).map((match) => match.group(1)).toSet();
      expect(registered, containsAll(routes));
      List<TrainingTourStep>? russian;
      for (final language in ['ru', 'zh']) {
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: const [Locale('ru'), Locale('zh')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const Scaffold(body: SizedBox()),
          ),
        );
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(Scaffold));
        final tour = trainingTourSteps(context);
        final lessons = trainingLessons(context);
        expect(tour, hasLength(55));
        expect(tour.any((step) => step.targetId == 'menu.report'), isFalse);
        expect(tour.map((step) => step.id).toSet(), hasLength(55));
        expect(tour.map((step) => step.route).toSet(), routes);
        expect(tour.map((step) => step.lessonId).toSet(), hasLength(12));
        for (final step in tour) {
          expect(step.targetId.startsWith('route.'), isFalse);
          expect(step.targetId.startsWith('legacy.'), isFalse);
          expect(step.targetId.endsWith('.card'), isFalse);
          final source = lessons
              .singleWhere((lesson) => lesson.id == step.lessonId)
              .steps[step.lessonStep];
          expect(step.title, source.title);
          expect(step.body, source.body);
          expect(step.action, source.action);
          expect(step.targetId, isNotEmpty);
          expect(
            step.capability,
            step.lessonId == 'self_buyout'
                ? 'self_buyout'
                : capabilities[step.route],
          );
        }
        expect(
          tour
              .where((step) => step.lessonId == 'assembly')
              .map((step) => step.route)
              .toSet(),
          {'/tracks'},
        );
        if (russian == null) {
          russian = tour;
        } else {
          expect(tour.map((step) => step.id), russian.map((step) => step.id));
          expect(tour.first.title, isNot(russian.first.title));
        }
      }
    },
  );
}
