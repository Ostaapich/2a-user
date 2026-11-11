import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/features/training/data/training_progress.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_lessons.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_screen.dart';

Future<TrainingProgressStore> pumpTraining(
  WidgetTester tester, {
  String locale = 'ru',
  TrainingProgressStore? progressStore,
  VoidCallback? onStartPractice,
  String? initialLessonId,
  bool initialPractice = false,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final store =
      progressStore ?? TrainingProgressStore(prefs, accountKey: 'test');
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      supportedLocales: const [Locale('ru'), Locale('zh')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(
        body: TrainingScreen(
          store: store,
          onStartPractice: onStartPractice,
          initialLessonId: initialLessonId,
          initialPractice: initialPractice,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'practice delegates to the app flow without completing or replacing reading',
    (tester) async {
      var launches = 0;
      final store = await pumpTraining(
        tester,
        initialLessonId: 'assembly',
        onStartPractice: () => launches++,
      );
      await tapKey(tester, 'training-practice');
      expect(launches, 1);
      expect(find.byKey(const Key('training-next')), findsOneWidget);
      expect(find.byKey(const Key('training-assembly-exercise')), findsNothing);
      expect(
        store.read().statuses['assembly'],
        isNot(TrainingLessonStatus.practiced),
      );
    },
  );

  testWidgets('standalone reading hides practice without an app launcher', (
    tester,
  ) async {
    await pumpTraining(
      tester,
      initialLessonId: 'assembly',
      initialPractice: true,
    );
    expect(find.byKey(const Key('training-practice')), findsNothing);
    expect(find.byKey(const Key('training-assembly-exercise')), findsNothing);
    expect(find.byKey(const Key('training-next')), findsOneWidget);
  });

  testWidgets('catalog has 12 complete topics in both languages', (
    tester,
  ) async {
    for (final locale in ['ru', 'zh']) {
      await pumpTraining(tester, locale: locale);
      final context = tester.element(find.byType(TrainingScreen));
      final lessons = trainingLessons(context);
      expect(lessons.length, 12);
      expect(lessons.map((e) => e.id).toSet().length, 12);
      for (final lesson in lessons) {
        expect(lesson.title, isNotEmpty);
        expect(lesson.steps.length, greaterThanOrEqualTo(3));
        for (final step in lesson.steps) {
          expect(step.title, isNotEmpty);
          expect(step.body, isNotEmpty);
          expect(step.action, isNotEmpty);
        }
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'continue resumes reading, skip opens next topic without completing',
    (tester) async {
      final store = await pumpTraining(tester);
      await tapKey(tester, 'training-continue');
      await tapKey(tester, 'training-next');
      expect(store.read().steps['cabinet'], 1);
      await tapKey(tester, 'training-catalog');
      await tapKey(tester, 'training-continue');
      expect(find.textContaining('Шаг 2 из'), findsOneWidget);
      await tapKey(tester, 'training-skip');
      expect(store.read().statuses['cabinet'], TrainingLessonStatus.skipped);
      expect(store.read().lastLessonId, 'warehouse');
      expect(
        store.read().statuses['warehouse'],
        TrainingLessonStatus.inProgress,
      );
    },
  );

  testWidgets('assembly reading completion is separate from exercise success', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final store = TrainingProgressStore(prefs, accountKey: 'test');
    await store.save(const TrainingProgress().visit('assembly', 0));
    var launches = 0;
    await pumpTraining(tester, onStartPractice: () => launches++);
    await tapKey(tester, 'training-continue');
    while (find.byKey(const Key('training-next')).evaluate().isNotEmpty) {
      await tapKey(tester, 'training-next');
    }
    await tapKey(tester, 'training-mark-read');
    expect(store.read().statuses['assembly'], TrainingLessonStatus.read);
    await tapKey(tester, 'training-practice');
    expect(launches, 1);
    expect(find.byKey(const Key('training-assembly-exercise')), findsNothing);
    expect(store.read().statuses['assembly'], TrainingLessonStatus.read);
    await tapKey(tester, 'training-catalog');
    expect(store.read().statuses['assembly'], TrainingLessonStatus.read);
  });

  testWidgets(
    'failed persistence still opens and advances reading, then retries',
    (tester) async {
      final store = _FailingProgressStore(
        await SharedPreferences.getInstance(),
      );
      await pumpTraining(tester, progressStore: store);
      await tapKey(tester, 'training-continue');
      expect(find.byKey(const Key('training-next')), findsOneWidget);
      await tapKey(tester, 'training-next');
      expect(
        find.textContaining('Прогресс пока сохранён только'),
        findsOneWidget,
      );
      expect(store.read().steps['cabinet'], isNull);
      store.fail = false;
      await tapKey(tester, 'training-retry-save');
      expect(store.read().steps['cabinet'], 1);
      expect(find.byKey(const Key('training-retry-save')), findsNothing);
    },
  );

  testWidgets(
    'Chinese catalog and lesson fit a narrow viewport with large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 740));
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(() {
        tester.binding.setSurfaceSize(null);
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await pumpTraining(tester, locale: 'zh');
      expect(tester.takeException(), isNull);
      await tapKey(tester, 'training-continue');
      expect(tester.takeException(), isNull);
      await tapKey(tester, 'training-next');
      expect(tester.takeException(), isNull);
    },
  );
}

class _FailingProgressStore extends TrainingProgressStore {
  _FailingProgressStore(super.preferences) : super(accountKey: 'failing');
  bool fail = true;
  @override
  Future<bool> save(TrainingProgress progress) async =>
      fail ? false : super.save(progress);
}
