import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/ui/blurred_modal_bottom_sheet.dart';
import 'package:twoalogisticcabineuser/src/core/ui/unsaved_changes_guard.dart';

const _header = ValueKey('sheet-header');
const _list = ValueKey('sheet-list');

Future<ScrollController> _open(
  WidgetTester tester, {
  required ScrollPhysics physics,
  int count = 30,
  bool enableDrag = true,
  bool blocked = false,
  bool draggable = false,
  bool editor = false,
  bool dirty = false,
  Axis scrollDirection = Axis.vertical,
  bool reverse = false,
  bool side = false,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  tester.view.physicalSize = Size(side ? 1200 : 390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = ScrollController();
  addTearDown(controller.dispose);
  Widget content(ScrollController controller) => SizedBox(
    height: 500,
    child: Column(
      children: [
        const SizedBox(
          key: _header,
          height: 50,
          child: Center(child: Text('Header')),
        ),
        Expanded(
          child: editor
              ? const TextField(key: _list, expands: true, maxLines: null)
              : ListView.builder(
                  key: _list,
                  controller: controller,
                  scrollDirection: scrollDirection,
                  reverse: reverse,
                  physics: physics,
                  itemCount: count,
                  itemBuilder: (_, i) =>
                      SizedBox(height: 50, child: Text('Row $i')),
                ),
        ),
      ],
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: TextButton(
              onPressed: () {
                showBlurredModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  enableDrag: enableDrag,
                  builder: (_) => PopScope(
                    canPop: !blocked,
                    child: UnsavedChangesGuard(
                      hasChanges: dirty,
                      isBusy: blocked,
                      child: draggable
                          ? DraggableScrollableSheet(
                              initialChildSize: .65,
                              minChildSize: .4,
                              maxChildSize: .95,
                              expand: false,
                              builder: (_, controller) => content(controller),
                            )
                          : content(controller),
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _pull(WidgetTester tester, {double distance = 170}) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(_list)),
  );
  await gesture.moveBy(const Offset(0, 25));
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.moveBy(Offset(0, distance));
  await tester.pump(const Duration(milliseconds: 150));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final bouncing in [false, true]) {
      final physics = bouncing
          ? const BouncingScrollPhysics()
          : const ClampingScrollPhysics();
      final label = '$platform bouncing=$bouncing';
      testWidgets(
        'kinetics synchronous MOVE packet preserves reverse offset $label',
        (tester) async {
          final controller = await _open(
            tester,
            physics: physics,
            platform: platform,
          );
          final start = tester.getCenter(find.byKey(_list));
          final binding = tester.binding;
          final viewId = tester.view.viewId;
          binding.handlePointerEvent(
            PointerDownEvent(
              pointer: 71,
              viewId: viewId,
              position: start,
              buttons: kPrimaryButton,
            ),
          );
          binding.handlePointerEvent(
            PointerMoveEvent(
              pointer: 71,
              viewId: viewId,
              position: start + const Offset(0, 35),
              delta: const Offset(0, 35),
              timeStamp: const Duration(milliseconds: 10),
              buttons: kPrimaryButton,
            ),
          );
          binding.handlePointerEvent(
            PointerMoveEvent(
              pointer: 71,
              viewId: viewId,
              position: start + const Offset(0, -65),
              delta: const Offset(0, -100),
              timeStamp: const Duration(milliseconds: 20),
              buttons: kPrimaryButton,
            ),
          );
          final reversed = controller.offset;
          expect(reversed, greaterThan(0));
          await tester.pump();
          expect(
            controller.offset,
            reversed,
            reason:
                'queued leading-edge cancel must not erase reverse movement from the same native pointer packet',
          );
          binding.handlePointerEvent(
            PointerUpEvent(
              pointer: 71,
              viewId: viewId,
              position: start + const Offset(0, -65),
              timeStamp: const Duration(milliseconds: 220),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byKey(_header), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
      for (final keyboard in [0.0, 300.0]) {
        testWidgets(
          'kinetics feasible slow distance35 near bottom IME$keyboard $label',
          (tester) async {
            await _open(tester, physics: physics, platform: platform);
            tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
            await tester.pumpAndSettle();
            final bottom = tester.getBottomLeft(find.byKey(_list));
            expect(bottom.dy, lessThanOrEqualTo(844 - keyboard));
            final gesture = await tester.createGesture();
            await gesture.down(
              bottom + const Offset(150, -42),
              timeStamp: Duration.zero,
            );
            await gesture.moveBy(
              const Offset(0, 35),
              timeStamp: const Duration(milliseconds: 100),
            );
            await tester.pump();
            await gesture.up(timeStamp: const Duration(milliseconds: 320));
            await tester.pumpAndSettle();
            expect(find.byKey(_header), findsNothing);
          },
        );
      }
      testWidgets('kinetics short one-move flick35 near bottom closes $label', (
        tester,
      ) async {
        await _open(tester, physics: physics, platform: platform);
        final start =
            tester.getBottomLeft(find.byKey(_list)) + const Offset(150, -42);
        final gesture = await tester.createGesture();
        await gesture.down(start, timeStamp: Duration.zero);
        await gesture.moveBy(
          const Offset(0, 35),
          timeStamp: const Duration(milliseconds: 20),
        );
        await tester.pump();
        await gesture.up(timeStamp: const Duration(milliseconds: 21));
        await tester.pumpAndSettle();
        expect(find.byKey(_header), findsNothing);
      });
      testWidgets(
        'kinetics held short pull springs back without teleport $label',
        (tester) async {
          await _open(tester, physics: physics, platform: platform);
          final header = tester.getTopLeft(find.byKey(_header));
          final gesture = await tester.createGesture();
          await gesture.down(
            tester.getCenter(find.byKey(_list)),
            timeStamp: Duration.zero,
          );
          await gesture.moveBy(
            const Offset(0, 35),
            timeStamp: const Duration(milliseconds: 20),
          );
          await tester.pump();
          final pulled = tester.getTopLeft(find.byKey(_header));
          expect(pulled.dy, greaterThan(header.dy));
          await gesture.up(timeStamp: const Duration(milliseconds: 220));
          await tester.pump();
          expect(find.byKey(_header), findsOneWidget);
          expect(
            tester.getTopLeft(find.byKey(_header)).dy,
            greaterThan(header.dy),
          );
          await tester.pump(const Duration(milliseconds: 40));
          final settling = tester.getTopLeft(find.byKey(_header));
          expect(settling.dy, greaterThan(header.dy));
          expect(settling.dy, lessThan(pulled.dy));
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(find.byKey(_header)), header);
        },
      );
      testWidgets(
        'kinetics reversed handed-off fling retains list inertia $label',
        (tester) async {
          final controller = await _open(
            tester,
            physics: physics,
            platform: platform,
          );
          final gesture = await tester.createGesture();
          await gesture.down(
            tester.getCenter(find.byKey(_list)),
            timeStamp: Duration.zero,
          );
          await gesture.moveBy(
            const Offset(0, 30),
            timeStamp: const Duration(milliseconds: 10),
          );
          await tester.pump();
          await gesture.moveBy(
            const Offset(0, 30),
            timeStamp: const Duration(milliseconds: 20),
          );
          await tester.pump();
          await gesture.moveBy(
            const Offset(0, -100),
            timeStamp: const Duration(milliseconds: 30),
          );
          await tester.pump();
          await gesture.moveBy(
            const Offset(0, -60),
            timeStamp: const Duration(milliseconds: 40),
          );
          await tester.pump();
          await gesture.up(timeStamp: const Duration(milliseconds: 41));
          await tester.pump();
          final released = controller.offset;
          await tester.pump(const Duration(milliseconds: 60));
          expect(controller.offset, greaterThan(released + 5));
          expect(find.byKey(_header), findsOneWidget);
          await tester.pumpAndSettle();
        },
      );
      testWidgets('kinetics fast drag through leading edge closes $label', (
        tester,
      ) async {
        final controller = await _open(
          tester,
          physics: physics,
          platform: platform,
        );
        controller.jumpTo(20);
        await tester.pump();
        final gesture = await tester.createGesture();
        await gesture.down(
          tester.getBottomLeft(find.byKey(_list)) + const Offset(150, -60),
          timeStamp: Duration.zero,
        );
        await gesture.moveBy(
          const Offset(0, 25),
          timeStamp: const Duration(milliseconds: 10),
        );
        await tester.pump();
        await gesture.moveBy(
          const Offset(0, 25),
          timeStamp: const Duration(milliseconds: 20),
        );
        await tester.pump();
        await gesture.up(timeStamp: const Duration(milliseconds: 21));
        await tester.pumpAndSettle();
        expect(find.byKey(_header), findsNothing);
      });
    }
  }
  for (final side in [false, true]) {
    testWidgets('direct header pointer cancel restores sheet side=$side', (
      tester,
    ) async {
      await _open(tester, physics: const ClampingScrollPhysics(), side: side);
      final header = tester.getRect(find.byKey(_header));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_header)),
      );
      await gesture.moveBy(side ? const Offset(25, 0) : const Offset(0, 25));
      await tester.pump();
      await gesture.moveBy(side ? const Offset(130, 0) : const Offset(0, 130));
      await tester.pump();
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_header)), header);
    });
  }
  for (final freshKind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets(
      'second finger cancels direct mobile header translation fresh=$freshKind',
      (tester) async {
        await _open(tester, physics: const ClampingScrollPhysics());
        final header = tester.getRect(find.byKey(_header));
        final first = await tester.startGesture(
          tester.getCenter(find.byKey(_header)),
          pointer: 1,
        );
        await first.moveBy(const Offset(0, 25));
        await tester.pump();
        await first.moveBy(const Offset(0, 130));
        await tester.pump();
        final second = await tester.startGesture(
          tester.getCenter(find.byKey(_header)),
          pointer: 2,
        );
        await tester.pump();
        expect(tester.getRect(find.byKey(_header)), header);
        await second.moveBy(const Offset(0, 130));
        await tester.pump();
        expect(tester.getRect(find.byKey(_header)), header);
        await first.up();
        await second.up();
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byKey(_header)), header);
        // Cancellation lasts only for that sequence; a fresh one-finger gesture
        // must still dismiss normally.
        final fresh = await tester.startGesture(
          tester.getCenter(find.byKey(_header)),
          kind: freshKind,
        );
        await fresh.moveBy(const Offset(0, 25));
        await tester.pump();
        await fresh.moveBy(const Offset(0, 180));
        await tester.pump();
        await fresh.up();
        await tester.pumpAndSettle();
        expect(find.byKey(_header), findsNothing);
      },
    );
  }
  for (final bouncing in [false, true]) {
    final physics = bouncing
        ? const BouncingScrollPhysics()
        : const ClampingScrollPhysics();
    final name = bouncing ? 'bouncing' : 'clamping';
    testWidgets('$name long list leading-edge pull closes whole modal', (
      tester,
    ) async {
      await _open(tester, physics: physics);
      await _pull(tester);
      expect(find.byKey(_header), findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets('$name handed-off movement has exactly one scroll consumer', (
      tester,
    ) async {
      final controller = await _open(tester, physics: physics);
      final start = tester.getTopLeft(find.byKey(_header));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_list)),
      );
      await gesture.moveBy(const Offset(0, 25));
      await tester.pump();
      final claimed = tester.getTopLeft(find.byKey(_header));
      await gesture.moveBy(const Offset(0, 70));
      await tester.pump();
      expect(controller.offset, 0);
      expect(
        tester.getTopLeft(find.byKey(_header)).dy - claimed.dy,
        closeTo(70, 1),
      );
      expect(claimed.dy, greaterThanOrEqualTo(start.dy));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(_header)), start);
    });
    testWidgets('$name header drag still closes modal', (tester) async {
      await _open(tester, physics: physics);
      await tester.drag(find.byKey(_header), const Offset(0, 180));
      await tester.pumpAndSettle();
      expect(find.byKey(_header), findsNothing);
    });
    for (final direction in ['horizontal', 'reversed']) {
      testWidgets('$name $direction list does not hand off scrolling', (
        tester,
      ) async {
        final controller = await _open(
          tester,
          physics: physics,
          scrollDirection: direction == 'horizontal'
              ? Axis.horizontal
              : Axis.vertical,
          reverse: direction == 'reversed',
        );
        final header = tester.getRect(find.byKey(_header));
        if (direction == 'horizontal') {
          await tester.drag(find.byKey(_list), const Offset(-180, 0));
          await tester.pumpAndSettle();
          expect(controller.offset, greaterThan(0));
        } else {
          await _pull(tester);
        }
        expect(tester.getRect(find.byKey(_header)), header);
      });
    }
    testWidgets('$name programmatic edge scroll never moves modal', (
      tester,
    ) async {
      final controller = await _open(tester, physics: physics);
      final header = tester.getRect(find.byKey(_header));
      controller.jumpTo(-100);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_header)), header);
    });
    testWidgets('$name mid-list drag scrolls content without moving modal', (
      tester,
    ) async {
      final controller = await _open(tester, physics: physics);
      controller.jumpTo(600);
      await tester.pump();
      final header = tester.getRect(find.byKey(_header));
      await _pull(tester, distance: 110);
      expect(find.byKey(_header), findsOneWidget);
      expect(tester.getRect(find.byKey(_header)), header);
      expect(controller.offset, lessThan(600));
      expect(controller.offset, greaterThan(0));
    });
    testWidgets('$name same gesture reaches leading edge then closes modal', (
      tester,
    ) async {
      final controller = await _open(tester, physics: physics);
      controller.jumpTo(40);
      await tester.pump();
      await _pull(tester, distance: 220);
      expect(find.byKey(_header), findsNothing);
    });
    for (final count in [0, 2]) {
      for (final always in [false, true]) {
        testWidgets('$name short$count always$always body pull closes modal', (
          tester,
        ) async {
          await _open(
            tester,
            physics: always
                ? physics.applyTo(const AlwaysScrollableScrollPhysics())
                : physics,
            count: count,
          );
          await _pull(tester);
          expect(find.byKey(_header), findsNothing);
        });
      }
    }
    testWidgets('$name blocked form restores whole sheet after pull', (
      tester,
    ) async {
      final controller = await _open(tester, physics: physics, blocked: true);
      final header = tester.getRect(find.byKey(_header));
      await _pull(tester);
      expect(tester.getRect(find.byKey(_header)), header);
      expect(controller.offset, 0);
    });
    testWidgets('$name disabled drag leaves modal and scroll physics intact', (
      tester,
    ) async {
      await _open(tester, physics: physics, enableDrag: false);
      final header = tester.getRect(find.byKey(_header));
      await _pull(tester);
      expect(tester.getRect(find.byKey(_header)), header);
    });
    testWidgets(
      '$name dirty guard keeps draft and geometry then permits discard',
      (tester) async {
        await _open(tester, physics: physics, dirty: true);
        final header = tester.getRect(find.byKey(_header));
        await _pull(tester);
        expect(find.text('Не сохранять изменения?'), findsOneWidget);
        await tester.tap(find.text('Продолжить редактирование'));
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byKey(_header)), header);
        await _pull(tester);
        await tester.tap(find.text('Не сохранять'));
        await tester.pumpAndSettle();
        expect(find.byKey(_header), findsNothing);
      },
    );
    testWidgets('$name multi-touch cancels handoff without closing', (
      tester,
    ) async {
      await _open(tester, physics: physics);
      final header = tester.getRect(find.byKey(_header));
      final first = await tester.startGesture(
        tester.getCenter(find.byKey(_list)),
        pointer: 1,
      );
      await first.moveBy(const Offset(0, 25));
      await tester.pump();
      await first.moveBy(const Offset(0, 130));
      await tester.pump();
      final second = await tester.startGesture(
        tester.getCenter(find.byKey(_list)),
        pointer: 2,
      );
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_header)), header);
    });
    testWidgets(
      '$name reverse handed-off pull scrolls list instead of sticking sheet',
      (tester) async {
        final controller = await _open(tester, physics: physics);
        final header = tester.getRect(find.byKey(_header));
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(_list)),
        );
        await gesture.moveBy(const Offset(0, 25));
        await tester.pump();
        await gesture.moveBy(const Offset(0, 80));
        await tester.pump();
        await gesture.moveBy(const Offset(0, -180));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byKey(_header)), header);
        expect(controller.offset, greaterThan(0));
      },
    );
    testWidgets('$name nested draggable sheet retains native ownership', (
      tester,
    ) async {
      await _open(tester, physics: physics, draggable: true);
      await _pull(tester);
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('$name multiline editor scrolling never hands off', (
      tester,
    ) async {
      await _open(tester, physics: physics, editor: true);
      await tester.enterText(
        find.byType(TextField),
        List.generate(50, (i) => 'line $i').join('\n'),
      );
      await tester.pump();
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      final draft = editable.controller.text;
      final innerScroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(EditableText),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      innerScroll.position.jumpTo(0);
      await tester.pump();
      final header = tester.getRect(find.byKey(_header));
      await _pull(tester);
      expect(tester.getRect(find.byKey(_header)), header);
      expect(editable.controller.text, draft);
      expect(tester.takeException(), isNull);
    });
    testWidgets('$name covered header drag never dismisses unrelated dialog', (
      tester,
    ) async {
      await _open(tester, physics: physics);
      final header = tester.getRect(find.byKey(_header));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_header)),
      );
      await gesture.moveBy(const Offset(0, 25));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 130));
      await tester.pump();
      final context = tester.element(find.byKey(_header));
      showDialog<void>(
        context: context,
        builder: (_) =>
            const AlertDialog(title: Text('Header unrelated dialog')),
      );
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Header unrelated dialog'), findsOneWidget);
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_header)), header);
    });
    testWidgets('$name short slow edge pull restores modal without dismissal', (
      tester,
    ) async {
      await _open(tester, physics: physics);
      final header = tester.getRect(find.byKey(_header));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_list)),
      );
      await gesture.moveBy(const Offset(0, 25));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_header)), header);
    });
    testWidgets(
      '$name covered route does not dismiss unrelated dialog on pointer up',
      (tester) async {
        await _open(tester, physics: physics);
        final header = tester.getRect(find.byKey(_header));
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(_list)),
        );
        await gesture.moveBy(const Offset(0, 25));
        await tester.pump();
        await gesture.moveBy(const Offset(0, 130));
        await tester.pump();
        final context = tester.element(find.byKey(_header));
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(title: Text('Unrelated dialog')),
        );
        await tester.pumpAndSettle();
        await gesture.up();
        await tester.pumpAndSettle();
        expect(find.text('Unrelated dialog'), findsOneWidget);
        Navigator.of(context).pop();
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byKey(_header)), header);
      },
    );
    testWidgets('$name disposed route during handoff has no stale callback', (
      tester,
    ) async {
      await _open(tester, physics: physics);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_list)),
      );
      await gesture.moveBy(const Offset(0, 25));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
    testWidgets('$name pointer cancel restores sheet without close', (
      tester,
    ) async {
      await _open(tester, physics: physics);
      final header = tester.getRect(find.byKey(_header));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_list)),
      );
      await gesture.moveBy(const Offset(0, 25));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 150));
      await tester.pump();
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_header)), header);
    });
  }
}
