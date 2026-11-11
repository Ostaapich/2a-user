import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/features/home/presentation/home_stats_grid.dart';

void main() {
  for (final width in [280.0, 320.0, 360.0, 390.0, 430.0, 768.0, 1200.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('stats fit width $width at text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var tapped = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 1200),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: HomeStatsGrid(
                    tracksValue: '12 345',
                    pendingTracksValue: '12 336',
                    warehouseTracksValue: '9',
                    assembliesValue: '37',
                    invoicesValue: '8',
                    bonusKgValue: '16.95',
                    onTracksTap: () => tapped = true,
                    onAssembliesTap: () {},
                    onInvoicesTap: () {},
                    onBonusKgTap: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('В ожидании: 12 336'), findsOneWidget);
        expect(find.text('На складе: 9'), findsOneWidget);
        final track = tester.getTopLeft(find.text('Треки'));
        final assembly = tester.getTopLeft(find.text('Сборки'));
        final invoice = tester.getTopLeft(find.text('Счета'));
        final bonus = tester.getTopLeft(find.text('Бонусные кг'));
        expect(track.dy, assembly.dy);
        expect(invoice.dy, greaterThan(track.dy));
        expect(bonus.dy, invoice.dy);
        expect(find.textContaining('за неделю'), findsNothing);
        await tester.tap(find.text('Треки'));
        expect(tapped, isTrue);
      });
    }
  }
}
