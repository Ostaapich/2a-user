import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/features/training/data/training_tour_controller.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_target.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_modal_ownership.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_tour_overlay.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_tour_steps.dart';

const _steps = [
  TrainingTourStep(
    lessonId: 'tracks',
    lessonStep: 0,
    title: 'Трек на складе',
    body: 'Посмотрите на карточку посылки.',
    action: 'Откройте подробности, когда захотите.',
    route: '/tracks',
    targetId: 'track',
    preparations: [
      TrainingTourPreparation(
        targetId: 'open-track',
        instruction: 'Сначала откройте форму трека.',
      ),
    ],
    allowedRoutePrefixes: ['/tracks/details/'],
  ),
  TrainingTourStep(
    lessonId: 'self_buyout',
    lessonStep: 0,
    title: 'Самовыкуп',
    body: 'Услуга доступна по настройкам компании.',
    action: 'Проверьте доступность.',
    route: '/self-buyout',
    targetId: 'buyout',
    capability: 'self_buyout',
  ),
];

class _Harness extends StatefulWidget {
  final TrainingTourController controller;
  final TrainingTargetRegistry registry;
  final TrainingModalOwnership? ownership;
  final TrainingServiceAccess access;
  final bool showTarget;
  final bool showPreparation;
  final double targetOffset;
  final bool automatic;
  final bool guidedPractice;
  final VoidCallback? onSafeOpen;
  final ValueChanged<String> onNavigate;
  final VoidCallback onBusinessAction;

  const _Harness({
    required this.controller,
    required this.registry,
    this.ownership,
    required this.access,
    required this.showTarget,
    this.showPreparation = false,
    this.targetOffset = 0,
    this.automatic = false,
    this.guidedPractice = false,
    this.onSafeOpen,
    required this.onNavigate,
    required this.onBusinessAction,
  });

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  String path = '/';
  bool opened = false;

  void _open() {
    widget.onSafeOpen?.call();
    setState(() => opened = true);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final child = Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 80),
            child: widget.showTarget || opened
                ? Transform.translate(
                    offset: Offset(widget.targetOffset, 0),
                    child: TrainingTarget(
                      id: 'track',
                      child: FilledButton(
                        key: const Key('business-action'),
                        onPressed: widget.onBusinessAction,
                        child: const Text('Настоящее действие'),
                      ),
                    ),
                  )
                : widget.showPreparation
                ? TrainingTarget(
                    id: 'open-track',
                    onActivate: widget.automatic ? _open : null,
                    child: OutlinedButton(
                      key: const Key('open-track'),
                      onPressed: _open,
                      child: const Text('Открыть форму'),
                    ),
                  )
                : const Text('Загрузка…'),
          ),
        ),
      );
      if (!widget.controller.active) return child;
      return TrainingTourOverlay(
        controller: widget.controller,
        guidedPractice: widget.guidedPractice,
        registry: widget.registry,
        modalOwnership: widget.ownership,
        step: _steps[widget.controller.index],
        access: widget.access,
        currentPath: path,
        navigate: (route) {
          widget.onNavigate(route);
          setState(() => path = route);
        },
        onExit: widget.controller.stop,
        onPractice: widget.controller.stop,
        onRetryAccess: () {},
        child: child,
      );
    },
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<TrainingTourController> createController() async {
    final controller = TrainingTourController(
      await SharedPreferences.getInstance(),
      scopeKey: 'test',
    );
    addTearDown(controller.dispose);
    controller.start(_steps.map((step) => step.id).toList());
    return controller;
  }

  Future<void> host(
    WidgetTester tester,
    TrainingTourController controller,
    TrainingTargetRegistry registry, {
    TrainingServiceAccess access = TrainingServiceAccess.available,
    bool target = true,
    bool preparation = false,
    double targetOffset = 0,
    bool automatic = false,
    bool guidedPractice = false,
    VoidCallback? safeOpen,
    TrainingModalOwnership? ownership,
    GlobalKey<NavigatorState>? navigatorKey,
    String locale = 'ru',
    ValueChanged<String>? navigate,
    VoidCallback? businessAction,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [trainingTargetRegistryProvider.overrideWithValue(registry)],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [if (ownership != null) ownership],
          locale: Locale(locale),
          supportedLocales: const [Locale('ru'), Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: _Harness(
            controller: controller,
            registry: registry,
            ownership: ownership,
            access: access,
            showTarget: target,
            showPreparation: preparation,
            targetOffset: targetOffset,
            automatic: automatic,
            guidedPractice: guidedPractice,
            onSafeOpen: safeOpen,
            onNavigate: navigate ?? (_) {},
            onBusinessAction: businessAction ?? () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'tour cleanup respects unsaved-form PopScope even for an owned popup',
    (tester) async {
      final controller = await createController();
      final ownership = TrainingModalOwnership();
      final nav = GlobalKey<NavigatorState>();
      await host(
        tester,
        controller,
        TrainingTargetRegistry(),
        ownership: ownership,
        navigatorKey: nav,
      );
      ownership.runOwned(() {
        showDialog<void>(
          context: nav.currentContext!,
          builder: (_) => const PopScope(
            canPop: false,
            child: AlertDialog(content: Text('Unsaved user edits')),
          ),
        );
      });
      await tester.pumpAndSettle();
      expect(await ownership.closeOwned(), isFalse);
      expect(find.text('Unsaved user edits'), findsOneWidget);
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'tour dismisses its own previous popup on step change and keeps user windows',
    (tester) async {
      final controller = await createController();
      final registry = TrainingTargetRegistry();
      final ownership = TrainingModalOwnership();
      final nav = GlobalKey<NavigatorState>();
      await host(
        tester,
        controller,
        registry,
        target: false,
        preparation: true,
        automatic: true,
        ownership: ownership,
        navigatorKey: nav,
        safeOpen: () {
          showDialog<void>(
            context: nav.currentContext!,
            builder: (_) =>
                const AlertDialog(content: Text('Tour address dialog')),
          );
        },
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Tour address dialog'), findsOneWidget);
      expect(
        ownership.hasOwnedActive,
        isTrue,
        reason: 'auto-open should be owned',
      );
      controller.next();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Tour address dialog'), findsNothing);
      showDialog<void>(
        context: nav.currentContext!,
        builder: (_) => const AlertDialog(content: Text('User form')),
      );
      await tester.pumpAndSettle();
      await ownership.closeOwned();
      await tester.pumpAndSettle();
      expect(find.text('User form'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'highlights before safe auto opening and never presses business action',
    (tester) async {
      final controller = await createController();
      var opens = 0;
      var writes = 0;
      await host(
        tester,
        controller,
        TrainingTargetRegistry(),
        target: false,
        preparation: true,
        automatic: true,
        safeOpen: () => opens++,
        businessAction: () => writes++,
      );
      expect(find.byKey(const Key('tour-spotlight')), findsOneWidget);
      expect(find.byKey(const Key('open-track')), findsOneWidget);
      expect(opens, 0);
      expect(find.textContaining('Сейчас нажмём выделенный'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      expect(opens, 1);
      expect(find.byKey(const Key('business-action')), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(opens, 1);
      expect(writes, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final interruption in ['exit', 'skip', 'collapse', 'unmount']) {
    testWidgets('cancels pending auto opening on $interruption', (
      tester,
    ) async {
      final controller = await createController();
      var opens = 0;
      await host(
        tester,
        controller,
        TrainingTargetRegistry(),
        target: false,
        preparation: true,
        automatic: true,
        safeOpen: () => opens++,
      );
      switch (interruption) {
        case 'exit':
          controller.stop();
        case 'skip':
          controller.next(skip: true);
        case 'collapse':
          await tap(tester, 'tour-collapse');
        case 'unmount':
          await tester.pumpWidget(const SizedBox.shrink());
      }
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(opens, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('manual click wins pending auto activation without double open', (
    tester,
  ) async {
    final controller = await createController();
    var opens = 0;
    await host(
      tester,
      controller,
      TrainingTargetRegistry(),
      target: false,
      preparation: true,
      automatic: true,
      safeOpen: () => opens++,
    );
    await tap(tester, 'open-track');
    await tester.pump(const Duration(seconds: 3));
    expect(opens, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'guided practice waits for the trainee even when a safe hook exists',
    (tester) async {
      final controller = await createController();
      var opens = 0;
      await host(
        tester,
        controller,
        TrainingTargetRegistry(),
        target: false,
        preparation: true,
        automatic: true,
        guidedPractice: true,
        safeOpen: () => opens++,
      );
      await tester.pump(const Duration(seconds: 3));
      expect(opens, 0);
      expect(find.byKey(const Key('open-track')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('guides manual preparation then switches to the exact action', (
    tester,
  ) async {
    final controller = await createController();
    final registry = TrainingTargetRegistry();
    var businessActions = 0;
    await host(
      tester,
      controller,
      registry,
      target: false,
      preparation: true,
      businessAction: () => businessActions++,
    );
    expect(find.text('Сначала откройте форму трека.'), findsOneWidget);
    expect(find.text(_steps.first.body), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('tour-next'))).onPressed,
      isNull,
    );
    await tap(tester, 'tour-next');
    expect(controller.currentId, 'tracks:0');
    expect(controller.viewed, isEmpty);
    expect(find.byKey(const Key('tour-spotlight')), findsOneWidget);
    expect(find.byKey(const Key('business-action')), findsNothing);
    await tap(tester, 'open-track');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Сначала откройте форму трека.'), findsNothing);
    expect(find.text(_steps.first.action), findsOneWidget);
    expect(find.text(_steps.first.body), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('tour-next'))).onPressed,
      isNotNull,
    );
    expect(find.byKey(const Key('tour-spotlight')), findsOneWidget);
    expect(businessActions, 0);
    await tap(tester, 'business-action');
    expect(businessActions, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('nested detail routes belong only to their explicitly allowed step', () {
    expect(_steps.first.matchesPath('/tracks'), isTrue);
    expect(_steps.first.matchesPath('/tracks/details/12'), isTrue);
    expect(_steps.first.matchesPath('/tracks-other'), isFalse);
    expect(_steps.last.matchesPath('/self-buyout/other'), isFalse);
  });

  testWidgets('navigates, highlights, and does not trigger business actions', (
    tester,
  ) async {
    final controller = await createController();
    final registry = TrainingTargetRegistry();
    final routes = <String>[];
    var actions = 0;
    await host(
      tester,
      controller,
      registry,
      navigate: routes.add,
      businessAction: () => actions++,
    );
    expect(routes, ['/tracks']);
    expect(find.byKey(const Key('tour-spotlight')), findsOneWidget);
    expect(actions, 0);
    await tap(tester, 'business-action');
    expect(
      actions,
      1,
      reason: 'spotlight must pass input through to the real UI',
    );
    await tap(tester, 'tour-next');
    expect(routes, ['/tracks', '/self-buyout']);
    expect(actions, 1);
    await tap(tester, 'tour-exit');
    expect(find.byKey(const Key('training-coach-card')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unavailable service never navigates and remains skippable', (
    tester,
  ) async {
    final controller = await createController();
    controller.next();
    final routes = <String>[];
    await host(
      tester,
      controller,
      TrainingTargetRegistry(),
      access: TrainingServiceAccess.unavailable,
      navigate: routes.add,
    );
    expect(routes, isEmpty);
    expect(find.textContaining('недоступен вашему кабинету'), findsOneWidget);
    await tap(tester, 'tour-skip');
    expect(controller.complete, isTrue);
    expect(controller.viewed, isNot(contains('self_buyout:0')));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'missing target times out honestly then highlights a late target',
    (tester) async {
      final controller = await createController();
      final registry = TrainingTargetRegistry();
      await host(tester, controller, registry, target: false);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const Key('tour-spotlight')), findsNothing);
      expect(
        find.textContaining('Нужный элемент пока не показан'),
        findsOneWidget,
      );
      await host(tester, controller, registry, target: true);
      expect(find.byKey(const Key('tour-spotlight')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('offscreen target times out and recovers when visible', (
    tester,
  ) async {
    final controller = await createController();
    final registry = TrainingTargetRegistry();
    await host(tester, controller, registry, targetOffset: 2000);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const Key('tour-spotlight')), findsNothing);
    expect(
      find.textContaining('Нужный элемент пока не показан'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tour-reveal')), findsOneWidget);
    await host(tester, controller, registry);
    expect(find.byKey(const Key('tour-spotlight')), findsOneWidget);
    expect(find.byKey(const Key('tour-notice')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'checking does not navigate until service availability resolves',
    (tester) async {
      final controller = await createController();
      controller.next();
      final registry = TrainingTargetRegistry();
      final routes = <String>[];
      await host(
        tester,
        controller,
        registry,
        access: TrainingServiceAccess.checking,
        navigate: routes.add,
      );
      expect(routes, isEmpty);
      await host(tester, controller, registry, navigate: routes.add);
      expect(routes, ['/self-buyout']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final locale in ['ru', 'zh']) {
    testWidgets('coach fits narrow landscape and large text $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 390);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final controller = await createController();
      await host(tester, controller, TrainingTargetRegistry(), locale: locale);
      expect(tester.takeException(), isNull);
      await tap(tester, 'tour-collapse');
      expect(tester.takeException(), isNull);
      await tap(tester, 'tour-exit');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
