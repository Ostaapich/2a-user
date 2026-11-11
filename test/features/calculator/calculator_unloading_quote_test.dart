import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../helpers/keyboard_acceptance.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/auth_provider.dart';
import 'package:twoalogisticcabineuser/src/features/calculator/presentation/calculator_screen.dart';

class _Auth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(isLoading: false, clientId: 17);
}

class _Api implements ApiClient {
  _Api({this.density = false, this.packagingCost = 0});
  final double packagingCost;
  final bool density;
  final requests = <Map<String, dynamic>>[];

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    final data = switch (path) {
      '/tariffs' => {
        'tariffs': [
          density
              ? {
                  'id': 1,
                  'name': 'Спец тариф',
                  'baseCost': 3,
                  'paidPhotoReport': false,
                  'pricingType': 'density',
                  'densityTiers': [
                    {'minDensity': 0, 'clientPricePerM3': 300},
                  ],
                  'packagingSurcharges': [
                    {'packagingTypeId': 10, 'amount': 0.1, 'isActive': true},
                  ],
                }
              : {
                  'id': 1,
                  'name': 'Весовой',
                  'baseCost': 4,
                  'paidPhotoReport': false,
                },
        ],
      },
      '/photo-report-coefficients' => {'coefficients': <dynamic>[]},
      '/packagings' => {
        'packagings': [
          {'id': 10, 'name': 'Коробка', 'baseCost': packagingCost},
        ],
      },
      _ => throw StateError('Unexpected GET $path'),
    };
    return Response<T>(
      data: data as T,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    expect(path, '/client/unloading-quote');
    requests.add(Map<String, dynamic>.from(data as Map));
    return Response<T>(
      data:
          {
                'data': {'clientCostUsd': 9.23},
              }
              as T,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Finder _field(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
  matching: find.byType(TextFormField),
);

Future<void> _settleQuote(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  testWidgets(
    'unloading quote uses weight and places before volume is entered',
    (tester) async {
      final api = _Api();
      await tester.binding.setSurfaceSize(const Size(1200, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(api),
            authProvider.overrideWith(_Auth.new),
          ],
          child: const MaterialApp(home: Scaffold(body: CalculatorScreen())),
        ),
      );
      await _settleQuote(tester);
      await tester.enterText(_field('Вес, кг'), '8,5');
      await _settleQuote(tester);
      expect(api.requests.last, {
        'weightKg': 8.5,
        'volumeM3': 0.0,
        'placesCount': 1,
        'packagingTypeIds': [10],
      });

      await tester.enterText(_field('Мест'), '3');
      await _settleQuote(tester);
      expect(api.requests.last['placesCount'], 3);
      await tester.enterText(_field('Вес, кг'), '10.5');
      await _settleQuote(tester);
      expect(api.requests.last['weightKg'], 10.5);

      await tester.enterText(_field('Объём, м³'), '0.2');
      await tester.enterText(_field('Треков всего'), '1');
      await _settleQuote(tester);
      expect(api.requests.last['volumeM3'], 0.2);
      expect(find.text('Снятие упаковки'), findsNothing);
      expect(find.text('Снять коробку'), findsNothing);
      expect(find.text('Снять упаковку с сумки'), findsNothing);
      expect(find.text('Снять всю упаковку'), findsNothing);
      expect(find.text('\$9.23'), findsOneWidget);
      expect(find.text('по объёму, минимум \$5'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 10));
    },
  );
  testWidgets(
    'advanced mixed places drive quote and packaging cost and retain both modes',
    (tester) async {
      final api = _Api(packagingCost: 7);
      await tester.binding.setSurfaceSize(const Size(1200, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(api),
            authProvider.overrideWith(_Auth.new),
          ],
          child: const MaterialApp(home: Scaffold(body: CalculatorScreen())),
        ),
      );
      await _settleQuote(tester);
      await tester.enterText(_field('Вес, кг'), '3');
      await tester.enterText(_field('Объём, м³'), '0.05');
      await _settleQuote(tester);
      final toggle = find.byKey(const ValueKey('calculator.advanced-mode'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await _settleQuote(tester);
      Future<void> fill(int id, List<String> values) async {
        final names = ['length', 'width', 'height', 'weight'];
        for (var i = 0; i < names.length; i++) {
          final field = find.byKey(ValueKey('cargo-place-$id-${names[i]}'));
          await tester.ensureVisible(field);
          await tester.enterText(field, values[i]);
        }
        await _settleQuote(tester);
      }

      await fill(0, ['100', '50', '20', '8,5']);
      expect(api.requests.last['placesCount'], 1);
      final add = find.byKey(const ValueKey('cargo-place-add'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await _settleQuote(tester);
      final previousCount = api.requests.length;
      expect(find.text('Заполните параметры'), findsOneWidget);
      await fill(1, ['40', '30', '20', '1.5']);
      expect(api.requests.length, greaterThan(previousCount));
      expect(api.requests.last['weightKg'], 10);
      expect(api.requests.last['volumeM3'], closeTo(.124, 1e-10));
      expect(api.requests.last['placesCount'], 2);
      expect(find.text('\$14.00'), findsOneWidget);
      expect(find.text('\$63.23'), findsOneWidget);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await _settleQuote(tester);
      expect(api.requests.last['weightKg'], 3);
      expect(api.requests.last['volumeM3'], .05);
      expect(api.requests.last['placesCount'], 1);
      await tester.tap(toggle);
      await _settleQuote(tester);
      expect(api.requests.last['placesCount'], 2);
      expect(api.requests.last['weightKg'], 10);
      expect(find.text('\$14.00'), findsOneWidget);
      final remove = find.byKey(const ValueKey('cargo-place-remove-1'));
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await _settleQuote(tester);
      expect(api.requests.last['placesCount'], 1);
      expect(api.requests.last['weightKg'], 8.5);
      expect(find.text('\$7.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 10));
    },
  );
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final width in [320.0, 390.0]) {
      testWidgets(
        'advanced actual calculator caret above keyboard ${platform.name} $width',
        (tester) async {
          tester.view.physicalSize = Size(width, width == 320 ? 640 : 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewInsets);
          final api = _Api();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                apiClientProvider.overrideWithValue(api),
                authProvider.overrideWith(_Auth.new),
              ],
              child: MaterialApp(
                theme: ThemeData(platform: platform),
                builder: (_, child) => AppKeyboardDismissRegion(child: child!),
                home: const Scaffold(body: CalculatorScreen()),
              ),
            ),
          );
          await _settleQuote(tester);
          final toggle = find.byKey(const ValueKey('calculator.advanced-mode'));
          await tester.ensureVisible(toggle);
          await _settleQuote(tester);
          expect(toggle.hitTestable(), findsOneWidget);
          await tester.tap(toggle);
          await _settleQuote(tester);
          final add = find.byKey(const ValueKey('cargo-place-add'));
          await tester.ensureVisible(add);
          await _settleQuote(tester);
          expect(add.hitTestable(), findsOneWidget);
          await tester.tap(add);
          await _settleQuote(tester);
          for (final part in ['length', 'width', 'height', 'weight']) {
            final field = find.byKey(ValueKey('cargo-place-1-$part'));
            await tester.ensureVisible(field);
            await _settleQuote(tester);
            await tester.tap(field);
            await tester.enterText(field, '12,5');
            tester.view.viewInsets = const FakeViewPadding(bottom: 280);
            await _settleQuote(tester);
            final editable = find.descendant(
              of: field,
              matching: find.byType(EditableText),
            );
            expectFocusedCaretAboveIme(tester, editable);
            await tester.testTextInput.receiveAction(TextInputAction.done);
            await tester.pump();
            expect(
              tester.widget<EditableText>(editable).focusNode.hasFocus,
              isFalse,
            );
            expect(
              tester.widget<EditableText>(editable).controller.text,
              '12,5',
            );
            tester.view.resetViewInsets();
            await _settleQuote(tester);
          }
          expect(
            api.requests,
            isEmpty,
            reason: 'Incomplete first place cannot quote partial totals',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 10));
        },
      );
    }
  }
  testWidgets(
    'density surcharge shows kg addon while volume rate stays separate',
    (tester) async {
      final api = _Api(density: true);
      await tester.binding.setSurfaceSize(const Size(1200, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(api),
            authProvider.overrideWith(_Auth.new),
          ],
          child: const MaterialApp(home: Scaffold(body: CalculatorScreen())),
        ),
      );
      await _settleQuote(tester);
      await tester.enterText(_field('Вес, кг'), '20');
      await tester.enterText(_field('Объём, м³'), '0.2');
      await _settleQuote(tester);
      expect(find.text('Надбавка за упаковку к доставке'), findsOneWidget);
      expect(find.text('\$2.00'), findsOneWidget);
      expect(find.text('\$62.00'), findsOneWidget);
      expect(find.text('\$300.00/м³'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 10));
    },
  );
}
