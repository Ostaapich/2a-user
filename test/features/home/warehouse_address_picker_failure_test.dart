import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:twoalogisticcabineuser/src/features/home/presentation/warehouse_address_checker.dart';

class _Recognizer implements WarehouseScreenshotTextRecognizer {
  int calls = 0;
  bool failOnce = false;
  @override
  Future<String> recognize(String path) async {
    calls++;
    if (failOnce) {
      failOnce = false;
      throw StateError('ocr');
    }
    return 'TEST Warehouse 12345678901';
  }
}

XFile _screenshot() => XFile.fromData(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  ),
  name: 'fixture.png',
);

Future<void> _launcher(
  WidgetTester tester,
  Future<XFile?> Function() picker,
  WarehouseScreenshotTextRecognizer recognizer,
) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showWarehouseAddressChecker(
                  context,
                  expected: const WarehouseAddressCheckData(
                    clientCode: 'TEST',
                    address: 'Warehouse',
                    phone: '12345678901',
                  ),
                  recognizer: recognizer,
                  screenshotPicker: picker,
                ),
                child: const Text('Проверить заполнение'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(
  WidgetTester tester,
  Future<XFile?> Function() picker,
) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: WarehouseAddressCheckerSheet(
            expected: const WarehouseAddressCheckData(
              clientCode: 'TEST',
              address: 'Warehouse',
              phone: '12345',
            ),
            recognizer: _Recognizer(),
            screenshotPicker: picker,
          ),
        ),
      ),
    ),
  );
}

void main() {
  tearDown(AppToast.hide);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      '$platform direct launch picks once before any checker modal and cancellation returns Home',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        var calls = 0;
        final pending = Completer<XFile?>();
        await _launcher(tester, () {
          calls++;
          return pending.future;
        }, _Recognizer());
        final action = find.text('Проверить заполнение');
        await tester.tap(action);
        await tester.tap(action);
        await tester.pump();
        expect(calls, 1);
        expect(find.byType(WarehouseAddressCheckerSheet), findsNothing);
        expect(find.text('Выбрать скриншот'), findsNothing);
        pending.complete(null);
        await _frames(tester);
        expect(find.byType(WarehouseAddressCheckerSheet), findsNothing);
        expect(action, findsOneWidget);
        await tester.tap(action);
        await _frames(tester);
        expect(calls, 2);
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      },
    );
    testWidgets(
      '$platform selected screenshot opens existing checker and checks automatically without a second picker',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        var calls = 0;
        final recognizer = _Recognizer();
        final pending = Completer<XFile?>();
        await _launcher(tester, () {
          calls++;
          return pending.future;
        }, recognizer);
        await tester.tap(find.text('Проверить заполнение'));
        await tester.pump();
        expect(find.byType(WarehouseAddressCheckerSheet), findsNothing);
        pending.complete(_screenshot());
        await _frames(tester);
        expect(find.byType(WarehouseAddressCheckerSheet), findsOneWidget);
        expect(recognizer.calls, 1);
        expect(calls, 1);
        expect(find.textContaining('Всё заполнено правильно'), findsOneWidget);
        expect(find.text('Проверить другой скриншот'), findsOneWidget);
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      },
    );
    testWidgets(
      '$platform direct picker permission error returns Home and permits retry',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        var calls = 0;
        await _launcher(tester, () async {
          calls++;
          if (calls == 1) throw PlatformException(code: 'photo_access_denied');
          return null;
        }, _Recognizer());
        await tester.tap(find.text('Проверить заполнение'));
        await _frames(tester);
        expect(find.byType(WarehouseAddressCheckerSheet), findsNothing);
        expect(find.textContaining('Нет доступа к фото'), findsOneWidget);
        await tester.tap(find.text('Проверить заполнение'));
        await _frames(tester);
        expect(calls, 2);
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 4));
      },
    );
    testWidgets(
      '$platform automatic OCR failure keeps existing retry workflow',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        var calls = 0;
        final recognizer = _Recognizer()..failOnce = true;
        await _launcher(tester, () async {
          calls++;
          return _screenshot();
        }, recognizer);
        await tester.tap(find.text('Проверить заполнение'));
        await _frames(tester);
        expect(calls, 1);
        expect(
          find.textContaining('Не удалось проверить скриншот'),
          findsOneWidget,
        );
        final retry = find.byType(FilledButton).last;
        await tester.ensureVisible(retry);
        await tester.tap(retry);
        await _frames(tester);
        expect(calls, 2);
        expect(recognizer.calls, 2);
        expect(find.textContaining('Всё заполнено правильно'), findsOneWidget);
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
  testWidgets(
    'unmounted Home does not open checker when native picker completes',
    (tester) async {
      final pending = Completer<XFile?>();
      await _launcher(tester, () => pending.future, _Recognizer());
      await tester.tap(find.text('Проверить заполнение'));
      await tester.pumpWidget(const SizedBox());
      pending.complete(_screenshot());
      await _frames(tester);
      expect(find.byType(WarehouseAddressCheckerSheet), findsNothing);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );
  testWidgets(
    'Linux unsupported guard opens explanation before invoking picker',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var calls = 0;
      await _launcher(tester, () async {
        calls++;
        return _screenshot();
      }, const NativeWarehouseScreenshotTextRecognizer());
      await tester.tap(find.text('Проверить заполнение'));
      await _frames(tester);
      expect(calls, 0);
      expect(
        find.textContaining('Распознавание скриншота доступно'),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'native screenshot picker serializes same-frame taps and unlocks on cancel',
    (tester) async {
      final pending = Completer<XFile?>();
      var calls = 0;
      await _pump(tester, () {
        calls++;
        return pending.future;
      });
      final button = find.byType(FilledButton).first;
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.tap(button);
      await tester.pump();
      expect(calls, 1);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      pending.complete(null);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );
  testWidgets(
    'native permission denial stays actionable and retry remains available',
    (tester) async {
      var calls = 0;
      await _pump(tester, () async {
        if (++calls == 1) {
          throw PlatformException(
            code: 'photo_access_denied',
            message: 'Denied',
          );
        }
        return null;
      });
      final button = find.byType(FilledButton).first;
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.textContaining('Нет доступа к фото'), findsOneWidget);
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
