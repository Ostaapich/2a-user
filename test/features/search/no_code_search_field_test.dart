import '../../helpers/keyboard_acceptance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_search_field.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_input_decoration.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/search/data/fake_search_repository.dart';
import 'package:twoalogisticcabineuser/src/features/search/presentation/track_search_no_code_screen.dart';

class _Repository implements SearchRepository {
  final queries = <String>[];
  @override
  Future<SearchResultsPage> fetchNoCodeTracks({
    String query = '',
    int skip = 0,
    int take = 20,
  }) async {
    queries.add(query);
    return const SearchResultsPage(items: [], total: 0, hasMore: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected repository operation: ${invocation.memberName}',
  );
}

Finder _input() => find.descendant(
  of: find.byType(AppSearchField),
  matching: find.byType(TextField),
);
Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final width in [320.0, 390.0]) {
      testWidgets(
        'actual NoCode initial query clear validation external focus IME ${platform.name} $width',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, width == 320 ? 640 : 844);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetViewInsets);
          final repository = _Repository();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                searchRepositoryProvider.overrideWithValue(repository),
                activeClientCodeProvider.overrideWithValue('FAKE'),
              ],
              child: MaterialApp(
                locale: const Locale('ru'),
                theme: ThemeData(platform: platform, fontFamily: 'Gilroy'),
                builder: (_, child) => AppKeyboardDismissRegion(child: child!),
                home: const Scaffold(
                  body: TrackSearchNoCodeScreen(initialQuery: '  INIT123  '),
                ),
              ),
            ),
          );
          await _frames(tester);
          expect(repository.queries, ['', 'INIT123']);
          final field = _input();
          final external = tester.widget<TextField>(field).focusNode!;
          expect(tester.widget<TextField>(field).controller!.text, 'INIT123');
          await tester.ensureVisible(field);
          await _frames(tester);
          external.requestFocus();
          await _frames(tester);
          expect(external.hasFocus, isTrue);
          final frame = find.ancestor(
            of: field,
            matching: find.byType(AppOutlinedInputFrame),
          );
          expect(frame, findsOneWidget);
          final painted = find.descendant(
            of: frame,
            matching: find.byType(AnimatedContainer),
          );
          final normal =
              tester.widget<AnimatedContainer>(painted).foregroundDecoration
                  as BoxDecoration;
          expect(
            (normal.border! as Border).top.width,
            1.5,
            reason: 'external focus must reach branded frame',
          );
          await tester.enterText(field, '12');
          await _frames(tester);
          final beforeInvalid = repository.queries.length;
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await _frames(tester);
          expect(
            repository.queries.length,
            beforeInvalid,
            reason: 'min3 validation must not dispatch',
          );
          expect(
            tester.widget<AppSearchField>(find.byType(AppSearchField)).hasError,
            isTrue,
          );
          expect(
            tester.widget<AppOutlinedInputFrame>(frame).borderColor,
            const Color(0xFFE53935),
          );
          external.requestFocus();
          await _frames(tester);
          expect(
            tester.widget<AppOutlinedInputFrame>(frame).focusedBorderColor,
            const Color(0xFFE53935),
          );
          await tester.enterText(field, 'NEXT123');
          await _frames(tester);
          expect(
            tester.widget<AppSearchField>(find.byType(AppSearchField)).hasError,
            isFalse,
          );
          expect(
            repository.queries.length,
            beforeInvalid,
            reason: 'typing must not silently dispatch',
          );
          tester.view.viewInsets = FakeViewPadding(
            bottom: width == 320 ? 280 : 320,
          );
          await _frames(tester);
          final editor = find.descendant(
            of: field,
            matching: find.byType(EditableText),
          );
          expectFocusedCaretAboveIme(tester, editor);
          expect(tester.widget<TextField>(field).focusNode, same(external));
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await _frames(tester);
          expect(repository.queries.last, 'NEXT123');
          expect(repository.queries.length, beforeInvalid + 1);
          expect(external.hasFocus, isFalse);
          tester.view.resetViewInsets();
          await _frames(tester);
          await tester.ensureVisible(find.byTooltip('Очистить поиск'));
          await tester.tap(find.byTooltip('Очистить поиск'));
          await _frames(tester);
          expect(tester.widget<TextField>(field).controller!.text, isEmpty);
          expect(repository.queries.last, '');
          expect(
            repository.queries.length,
            beforeInvalid + 2,
            reason: 'clear must dispatch exactly once',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await _frames(tester);
        },
      );
    }
  }
  testWidgets(
    'borrowed focus node survives helper removal and default remains internal',
    (tester) async {
      final node = FocusNode();
      final controller = TextEditingController();
      Widget app({required bool borrowed}) => MaterialApp(
        home: Scaffold(
          body: AppSearchField(
            controller: controller,
            hintText: 'Search',
            onChanged: (_) {},
            focusNode: borrowed ? node : null,
          ),
        ),
      );
      await tester.pumpWidget(app(borrowed: true));
      await _frames(tester);
      node.requestFocus();
      await _frames(tester);
      expect(node.hasFocus, isTrue);
      expect(tester.widget<TextField>(_input()).focusNode, same(node));
      await tester.pumpWidget(const SizedBox.shrink());
      await _frames(tester);
      await tester.pumpWidget(app(borrowed: true));
      await _frames(tester);
      node.requestFocus();
      await _frames(tester);
      expect(node.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await _frames(tester);
      await tester.pumpWidget(app(borrowed: false));
      await _frames(tester);
      expect(tester.widget<TextField>(_input()).focusNode, isNot(same(node)));
      expect(
        tester.widget<AppSearchField>(find.byType(AppSearchField)).hasError,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await _frames(tester);
      node.dispose();
      controller.dispose();
    },
  );
}
