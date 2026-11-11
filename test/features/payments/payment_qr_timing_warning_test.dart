import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/features/payments/presentation/payment_qr_timing_warning.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/presentation/widgets/track_sheet_surface.dart';
import 'package:twoalogisticcabineuser/src/core/ui/sheet_handle.dart';

void main() {
  testWidgets(
    'acknowledgement belongs to payment attempt and persists on reopen',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      var payment = 'invoice:1:10';
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showPaymentQrTimingWarning(
                  context,
                  paymentAttemptKey: payment,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Я понял'), findsOneWidget);
      await tester.tap(find.text('Я понял'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(TrackSheetSurface), findsNothing);
      payment = 'invoice:1:11';
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Я понял'), findsOneWidget);
      await tester.tap(find.text('Я понял'));
      await tester.pumpAndSettle();
    },
  );
  for (final width in [320.0, 390.0]) {
    testWidgets(
      'branded payment terms $width require explicit acknowledgement',
      (tester) async {
        tester.view.physicalSize = Size(width, 568);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
        addTearDown(tester.view.reset);
        const brand = Color(0xFF1677FF);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: brand,
              ).copyWith(primary: brand),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showPaymentQrTimingWarning(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final surface = tester.widget<TrackSheetSurface>(
          find.byType(TrackSheetSurface),
        );
        expect(surface.title, 'Условия оплаты');
        expect(surface.icon, Icons.receipt_long_rounded);
        expect(surface.showHandle, false);
        expect(find.byType(SheetHandle), findsNothing);
        expect(
          tester
              .element(find.text('Условия оплаты'))
              .findAncestorWidgetOfExactType<Theme>()
              ?.data
              .colorScheme
              .primary,
          brand,
        );
        expect(
          tester.getRect(find.text('Я понял')).bottom,
          lessThanOrEqualTo(568 - 34),
        );
        expect(
          find.textContaining('автоматически отправлен на проверку'),
          findsOneWidget,
        );
        expect(find.textContaining('нажмите «Я оплатил»'), findsNothing);
        await tester.tapAt(const Offset(2, 2));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Условия оплаты'), findsOneWidget);
        await tester.drag(find.text('Условия оплаты'), const Offset(0, 160));
        await tester.pumpAndSettle();
        expect(find.text('Условия оплаты'), findsOneWidget);
        await tester.tap(find.text('Я понял'));
        await tester.pumpAndSettle();
        expect(find.text('Условия оплаты'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('programmatic close does not record an acknowledgement', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showPaymentQrTimingWarning(
                context,
                paymentAttemptKey: 'cancelled',
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('payment.qr.rules.v1.cancelled'), isNot(true));
  });
  testWidgets('recipient restriction is prominent red and above QR content', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              PaymentRecipientWarning(),
              SizedBox(key: ValueKey('payment-qr'), height: 220, width: 220),
            ],
          ),
        ),
      ),
    );
    final label = find.text('НЕ ОПЛАЧИВАТЬ С ИП/ООО');
    expect(label, findsOneWidget);
    final text = tester.widget<Text>(label);
    expect(text.style?.color, const Color(0xFFB91C1C));
    expect(text.style?.fontWeight, FontWeight.w900);
    expect(
      tester.getBottomLeft(label).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('payment-qr'))).dy),
    );
  });
  testWidgets('inline payment conditions use branded expandable card', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PaymentQrTimingNotice())),
    );
    final title = find.text('Условия оплаты и зачисления');
    expect(tester.widget<Text>(title).style?.fontWeight, FontWeight.w800);
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('автоматически отправлен на проверку'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
