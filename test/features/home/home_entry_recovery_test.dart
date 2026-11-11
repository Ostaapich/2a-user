import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/auth_provider.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/clients/domain/client_codes_state.dart';
import 'package:twoalogisticcabineuser/src/features/home/presentation/home_screen.dart';
import 'package:twoalogisticcabineuser/src/features/home/presentation/warehouse_address_checker.dart';
import 'package:twoalogisticcabineuser/src/features/profile/data/profile_provider.dart';

class _Auth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(isLoading: false);
}

class _Codes extends ClientCodesController {
  _Codes(this.mode, this.onLoad);
  final String mode;
  final VoidCallback onLoad;
  @override
  Future<ClientCodesState> build() async {
    onLoad();
    if (mode == 'loading') return Completer<ClientCodesState>().future;
    if (mode == 'error') throw StateError('offline');
    return const ClientCodesState(codes: [], activeCode: null);
  }
}

void main() {
  for (final mode in ['loading', 'error', 'empty']) {
    testWidgets('home handles client-code $mode with direct recovery', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            authProvider.overrideWith(_Auth.new),
            activeClientCodeProvider.overrideWithValue(null),
            clientCodesControllerProvider.overrideWith(
              () => _Codes(mode, () => calls++),
            ),
            clientProfileProvider.overrideWith((_) async => null),
          ],
          child: const MaterialApp(home: Scaffold(body: HomeScreen())),
        ),
      );
      await tester.pump();
      if (mode == 'loading') {
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      } else if (mode == 'error') {
        expect(find.text('Не удалось загрузить коды клиента'), findsOneWidget);
        await tester.tap(find.text('Повторить'));
        await tester.pump();
        expect(calls, 2);
      } else {
        await tester.tap(find.text('Открыть коды клиента'));
        await tester.pumpAndSettle();
        expect(find.text('Коды клиента пока не найдены'), findsOneWidget);
        expect(
          find.text('После привязки кода он появится в этом списке.'),
          findsOneWidget,
        );
        expect(find.text('Привязать код по PIN'), findsNothing);
        expect(find.text('PIN'), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
    });
  }
  testWidgets(
    'unsupported OCR explains restriction before any image selection',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: WarehouseAddressCheckerSheet(
                expected: WarehouseAddressCheckData(
                  clientCode: 'TEST',
                  address: 'Warehouse address',
                  phone: '1234567',
                ),
                recognizer: NativeWarehouseScreenshotTextRecognizer(),
              ),
            ),
          ),
        ),
      );
      expect(
        find.textContaining('Распознавание скриншота доступно'),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
        isNull,
      );
      expect(find.textContaining('Warehouse address'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
