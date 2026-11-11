import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/features/auth/presentation/auth_visuals.dart';

const _items = [
  AuthTrustItem(icon: Icons.photo_camera_rounded, label: 'Фотоотчёты'),
  AuthTrustItem(icon: Icons.location_on_rounded, label: 'Отслеживание'),
  AuthTrustItem(
    icon: Icons.account_balance_wallet_rounded,
    label: 'Alipay / WeChat Pay',
  ),
  AuthTrustItem(icon: Icons.shopping_bag_rounded, label: 'Выкуп'),
];

void main() {
  for (final scale in [1.0, 1.6]) {
    testWidgets(
      'all four login service badges fit 320px with text scale $scale',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const Scaffold(
              body: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: AuthTrustChips(items: _items),
                ),
              ),
            ),
          ),
        );
        for (final item in _items) {
          final label = find.text(item.label);
          expect(label, findsOneWidget);
          final bounds = tester.getRect(label);
          expect(bounds.left, greaterThanOrEqualTo(24));
          expect(bounds.right, lessThanOrEqualTo(296));
          final text = tester.widget<Text>(label);
          expect(
            text.maxLines,
            isNull,
            reason: 'Service names must wrap completely, not be truncated',
          );
          expect(text.overflow, isNull);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
