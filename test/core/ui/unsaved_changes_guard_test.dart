import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/ui/unsaved_changes_guard.dart';

void main() {
  testWidgets('cancel retains dirty form; explicit discard returns', (
    tester,
  ) async {
    var discarded = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => UnsavedChangesGuard(
                    onDiscard: () => discarded++,
                    hasChanges: true,
                    child: Scaffold(appBar: null, body: Text('Draft remains')),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('Draft remains'));
    Navigator.of(context).maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Не сохранять изменения?'), findsOneWidget);
    await tester.tap(find.text('Продолжить редактирование'));
    await tester.pumpAndSettle();
    expect(find.text('Draft remains'), findsOneWidget);
    expect(discarded, 0);
    Navigator.of(context).maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Не сохранять'));
    await tester.pumpAndSettle();
    expect(discarded, 1);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Draft remains'), findsNothing);
  });
}
