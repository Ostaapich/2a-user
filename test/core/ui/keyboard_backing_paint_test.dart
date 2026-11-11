import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/app/theme/app_theme.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_colors.dart';
import 'package:twoalogisticcabineuser/src/core/ui/blurred_modal_bottom_sheet.dart';

void main() {
  testWidgets(
    'transparent app screens keep opaque backing below keyboard viewport',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: ColoredBox(
            color: Colors.black,
            child: MaterialApp(
              theme: AppTheme.light(),
              builder: (_, child) => AppKeyboardDismissRegion(child: child!),
              home: const Scaffold(
                resizeToAvoidBottomInset: true,
                body: ColoredBox(color: Colors.white, child: SizedBox.expand()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final b =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final pixel = await tester.runAsync(() async {
        final image = await b.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final index = (600 * 390 + 2) * 4;
        final color = Color.fromARGB(
          data!.getUint8(index + 3),
          data.getUint8(index),
          data.getUint8(index + 1),
          data.getUint8(index + 2),
        );
        image.dispose();
        return color;
      });
      expect(
        pixel,
        AppColors.brandBg,
        reason:
            'rounded OS keyboard corners expose app backing, never black native clear',
      );
    },
  );
  testWidgets(
    'modal paints its surface behind rounded keyboard corners only below IME',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (_, child) => AppKeyboardDismissRegion(child: child!),
            home: Builder(
              builder: (context) => Scaffold(
                body: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: TextButton(
                      onPressed: () => showBlurredModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const SizedBox(
                          height: 200,
                          child: ColoredBox(color: Colors.white),
                        ),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final pixel = await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final i = (530 * 390 + 2) * 4;
        final c = Color.fromARGB(
          data!.getUint8(i + 3),
          data.getUint8(i),
          data.getUint8(i + 1),
          data.getUint8(i + 2),
        );
        image.dispose();
        return c;
      });
      expect(
        pixel,
        Colors.white,
        reason:
            'keyboard corner reveals the same modal surface, not barrier or clear backing',
      );
    },
  );
}
