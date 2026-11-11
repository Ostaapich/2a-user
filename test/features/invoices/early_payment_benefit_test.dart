import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/auth_provider.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/data/invoices_provider.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/domain/early_payment_benefit.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/domain/invoice_item.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/presentation/invoices_screen.dart';
import 'package:twoalogisticcabineuser/src/features/payments/data/payment_operator_status.dart';
import 'package:twoalogisticcabineuser/src/features/referral/data/referral_provider.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _BenefitTestAuth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    isLoggedIn: true,
    isLoading: false,
    clientId: 42,
    userDomain: 'benefit.test',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('ru');
    await (FontLoader('Gilroy')
          ..addFont(rootBundle.load('assets/fonts/gilroy/Gilroy-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/gilroy/Gilroy-Bold.ttf')))
        .load();
  });

  group('EarlyPaymentBenefit', () {
    test('parses every lifecycle state and exact option values', () {
      final now = DateTime.utc(2026, 9, 16, 10, 1);
      for (final state in const [
        'available',
        'selected',
        'selection_required',
        'applied',
        'expired',
        'cancelled',
        'reversed',
      ]) {
        final benefit = EarlyPaymentBenefit.fromJson({
          'state': state,
          'offeredAt': '2026-09-16T10:00:00.000Z',
          'expiresAt': '2026-09-19T10:00:00.000Z',
          'serverTime': '2026-09-16T10:01:00.000Z',
          'hasTimelyEvidence': true,
          'selectionRequired': state == 'selection_required',
          'selectedType': state == 'available' ? null : 'bonus_kg',
          'options': [
            {
              'type': 'price_lock',
              'enabled': true,
              'available': true,
              'projectedValue': {'unitRate': '4.25', 'unit': 'kg'},
            },
            {
              'type': 'free_insurance',
              'enabled': true,
              'available': true,
              'projectedValue': {
                'insuredValueUsd': 800,
                'waivedInsuranceUsd': 8,
              },
            },
            {
              'type': 'bonus_kg',
              'enabled': true,
              'available': true,
              'projectedValue': {'bonusKg': 2.345},
            },
          ],
        }, now: () => now);

        expect(benefit.state, isNot(EarlyPaymentBenefitState.unknown));
        expect(benefit.hasTimelyEvidence, isTrue);
        expect(benefit.options, hasLength(3));
        expect(benefit.options.first.projectedValue.unitRate, 4.25);
        expect(benefit.options.last.projectedValue.bonusKg, 2.345);
      }
    });

    test('unknown options are ignored without hiding a valid offer', () {
      final benefit = EarlyPaymentBenefit.fromJson({
        'state': 'available',
        'selectionRequired': true,
        'expiresAt': '2026-09-17T00:00:00.000Z',
        'options': [
          {'type': 'future_benefit', 'enabled': true, 'available': true},
          {'type': 'bonus_kg', 'enabled': true, 'available': true},
        ],
      }, now: () => DateTime.utc(2026, 9, 16));

      expect(benefit.options, hasLength(1));
      expect(benefit.canSelect, isTrue);
      expect(benefit.requiresSelectionBeforePayment, isTrue);
    });
  });

  test('selection sends only type and idempotency key', () async {
    final apiClient = _MockApiClient();
    when(
      () => apiClient.post(
        '/client/invoices/invoice-42/early-payment-benefit',
        data: {
          'benefitType': 'free_insurance',
          'idempotencyKey': 'selection-key-42',
        },
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(
          path: '/client/invoices/invoice-42/early-payment-benefit',
        ),
        statusCode: 200,
        data: {
          'earlyPaymentBenefit': {
            'state': 'selected',
            'selectedType': 'free_insurance',
            'selectionRequired': false,
            'options': const [],
          },
        },
      ),
    );

    final result = await selectEarlyPaymentBenefit(
      apiClient,
      invoiceId: 'invoice-42',
      benefitType: EarlyPaymentBenefitType.freeInsurance,
      idempotencyKey: 'selection-key-42',
    );

    expect(result.state, EarlyPaymentBenefitState.selected);
    expect(result.selectedType, EarlyPaymentBenefitType.freeInsurance);
    verify(
      () => apiClient.post(
        '/client/invoices/invoice-42/early-payment-benefit',
        data: {
          'benefitType': 'free_insurance',
          'idempotencyKey': 'selection-key-42',
        },
      ),
    ).called(1);
  });

  test('payment gate disappears when the selection deadline has passed', () {
    final invoice = _invoiceWithBenefit(
      EarlyPaymentBenefit.fromJson({
        'state': 'selection_required',
        'selectionRequired': true,
        'expiresAt': '2026-09-16T00:00:00.000Z',
        'serverTime': '2026-09-16T00:00:00.001Z',
        'hasTimelyEvidence': true,
        'options': [
          {'type': 'bonus_kg', 'enabled': true, 'available': true},
        ],
      }, now: () => DateTime.utc(2026, 9, 16)),
    );

    expect(invoice.earlyPaymentBenefit?.canSelect, isFalse);
    expect(canStartInvoicePayment(invoice), isTrue);
    expect(
      canStartInvoicePayment(
        _invoiceWithBenefit(
          EarlyPaymentBenefit.fromJson({
            'state': 'available',
            'selectionRequired': true,
            'expiresAt': '2026-09-17T00:00:00.000Z',
            'serverTime': '2026-09-16T00:00:00.000Z',
            'options': [
              {'type': 'bonus_kg', 'enabled': true, 'available': true},
            ],
          }, now: () => DateTime.utc(2026, 9, 16)),
        ),
      ),
      isFalse,
    );
  });

  testWidgets('benefit card renders all exact choices and selection action', (
    tester,
  ) async {
    final benefit = EarlyPaymentBenefit.fromJson({
      'state': 'available',
      'selectionRequired': true,
      'expiresAt': '2026-09-19T10:00:00.000Z',
      'options': [
        {
          'type': 'price_lock',
          'enabled': true,
          'available': true,
          'projectedValue': {'unitRate': 4.25, 'unit': 'kg'},
        },
        {
          'type': 'free_insurance',
          'enabled': true,
          'available': true,
          'projectedValue': {'waivedInsuranceUsd': 8},
        },
        {
          'type': 'bonus_kg',
          'enabled': true,
          'available': true,
          'projectedValue': {'bonusKg': 2.345},
        },
      ],
    }, now: () => DateTime.utc(2026, 9, 16, 10));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EarlyPaymentBenefitCard(
              benefit: benefit,
              selecting: false,
              onChoose: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Защита от изменения таможенных пошлин'), findsOneWidget);
    expect(find.text(r'$4.25/кг'), findsOneWidget);
    expect(find.text('Бесплатная страховка'), findsOneWidget);
    expect(find.text(r'Страховка за наш счёт — до $8.00'), findsOneWidget);
    expect(find.text('Бонусные килограммы'), findsOneWidget);
    expect(find.text('+2.345 кг'), findsOneWidget);
    expect(find.text('Выбрать бонус'), findsOneWidget);
  });

  testWidgets('open benefit pill stops offering selection at the deadline', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 9, 16, 10);
    final deadline = now.add(const Duration(milliseconds: 100));
    final benefit = EarlyPaymentBenefit.fromJson({
      'state': 'available',
      'selectionRequired': true,
      'serverTime': now.toIso8601String(),
      'expiresAt': deadline.toIso8601String(),
      'options': [
        {'type': 'bonus_kg', 'enabled': true, 'available': true},
      ],
    }, now: () => now);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EarlyPaymentBenefitPill(benefit: benefit)),
      ),
    );
    expect(find.text('Выберите бонус'), findsOneWidget);

    now = deadline.add(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Выберите бонус'), findsNothing);
    expect(find.text('Бонус истёк'), findsOneWidget);
  });

  testWidgets('open benefit modal closes at server-adjusted deadline', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var now = DateTime.utc(2026, 9, 16, 10);
    final deadline = now.add(const Duration(seconds: 2));
    final benefit = EarlyPaymentBenefit.fromJson({
      'state': 'available',
      'selectionRequired': true,
      'serverTime': now.toIso8601String(),
      'expiresAt': deadline.toIso8601String(),
      'options': [
        {
          'type': 'bonus_kg',
          'enabled': true,
          'available': true,
          'projectedValue': {'bonusKg': 2.5},
        },
      ],
    }, now: () => now);
    final invoice = _invoiceWithBenefit(benefit);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          referralProvider.overrideWith(
            (_) async => const ReferralData(
              referralKgBalance: 0,
              referrals: [],
              transactions: [],
            ),
          ),
          invoiceStatusesProvider.overrideWith((_) async => []),
          invoiceByIdProvider.overrideWith((_, _) async => invoice),
          paymentOperatorStatusProvider.overrideWith(
            (_) => Stream.value(
              PaymentOperatorStatus(sleeping: false, reachable: true),
            ),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ClientInvoiceTile(item: invoice, clientCode: 'TEST'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('INV-42'));
    await tester.pumpAndSettle();
    final chooseButton = find.text('Выбрать бонус');
    await tester.ensureVisible(chooseButton);
    await tester.pumpAndSettle();
    await tester.tap(chooseButton);
    await tester.pumpAndSettle();
    expect(find.text('Один бонус за быструю оплату'), findsOneWidget);

    now = deadline.add(const Duration(milliseconds: 1));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('Один бонус за быструю оплату'), findsNothing);
    expect(find.text('Выбрать бонус'), findsNothing);
    expect(find.text('Срок выбора бонуса истёк.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('selecting a benefit keeps the invoice modal open', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final apiClient = _MockApiClient();
    final benefit = EarlyPaymentBenefit.fromJson({
      'state': 'available',
      'selectionRequired': true,
      'expiresAt': '2026-09-19T10:00:00.000Z',
      'options': [
        {
          'type': 'bonus_kg',
          'enabled': true,
          'available': true,
          'projectedValue': {'bonusKg': 2.5},
        },
      ],
    }, now: () => DateTime.utc(2026, 9, 16, 10));
    final invoice = _invoiceWithBenefit(benefit);
    when(
      () => apiClient.get('/client/invoices/invoice-42/payment-options'),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(
          path: '/client/invoices/invoice-42/payment-options',
        ),
        data: {
          'data': {
            'methods': [
              {'code': 'manager', 'currency': 'RUB', 'available': true},
            ],
            'activeMethod': 'manager',
            'canChange': true,
          },
        },
      ),
    );
    when(
      () => apiClient.post(
        '/client/invoices/invoice-42/early-payment-benefit',
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(
          path: '/client/invoices/invoice-42/early-payment-benefit',
        ),
        statusCode: 200,
        data: {
          'earlyPaymentBenefit': {
            'state': 'selected',
            'selectedType': 'bonus_kg',
            'selectionRequired': false,
            'options': [
              {
                'type': 'bonus_kg',
                'enabled': true,
                'available': true,
                'projectedValue': {'bonusKg': 2.5},
              },
            ],
          },
        },
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
          authProvider.overrideWith(_BenefitTestAuth.new),
          activeClientCodeProvider.overrideWithValue('TEST'),
          referralProvider.overrideWith(
            (_) async => const ReferralData(
              referralKgBalance: 0,
              referrals: [],
              transactions: [],
            ),
          ),
          invoiceStatusesProvider.overrideWith((_) async => []),
          invoiceByIdProvider.overrideWith((_, _) async => invoice),
          paymentOperatorStatusProvider.overrideWith(
            (_) => Stream.value(
              PaymentOperatorStatus(sleeping: false, reachable: true),
            ),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ClientInvoiceTile(item: invoice, clientCode: 'TEST'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('INV-42'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Оплатить'));
    await tester.pumpAndSettle();
    expect(find.text('Один бонус за быструю оплату'), findsOneWidget);
    final bonusChoice = find.text('Бонусные килограммы').last;
    expect(bonusChoice.hitTestable(), findsOneWidget);
    await tester.tap(bonusChoice);
    await tester.pump();
    final confirmBenefit = find.text('Выбрать бонус').last;
    expect(confirmBenefit.hitTestable(), findsOneWidget);
    await tester.tap(confirmBenefit);
    await tester.pumpAndSettle();

    expect(find.text('Один бонус за быструю оплату'), findsNothing);
    expect(find.text('Счёт INV-42'), findsOneWidget);
    expect(find.textContaining('Выбран бонус'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('benefit card renders terminal and review states', (
    tester,
  ) async {
    final expectedCopy = <String, String>{
      'selection_required':
          'Чек загружен вовремя. Выберите бонус — после этого мы продолжим проверку оплаты.',
      'applied': 'Бонус применён и зафиксирован в оплаченной накладной.',
      'expired': 'Срок выбора бонуса истёк.',
      'reversed': 'Бонус отменён после возврата оплаты. История сохранена.',
    };

    for (final entry in expectedCopy.entries) {
      final benefit = EarlyPaymentBenefit.fromJson({
        'state': entry.key,
        'selectionRequired': entry.key == 'selection_required',
        'hasTimelyEvidence': entry.key == 'selection_required',
        'selectedType': entry.key == 'expired' ? null : 'bonus_kg',
        'options': const [],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EarlyPaymentBenefitCard(
              benefit: benefit,
              selecting: false,
              onChoose: null,
            ),
          ),
        ),
      );
      expect(find.text(entry.value), findsOneWidget);
    }
  });
}

InvoiceItem _invoiceWithBenefit(EarlyPaymentBenefit benefit) {
  return InvoiceItem(
    id: 'invoice-42',
    invoiceNumber: 'INV-42',
    status: 'unpaid',
    placesCount: 1,
    density: 0,
    weight: 10,
    volume: 0,
    totalCostRub: 1000,
    earlyPaymentBenefit: benefit,
  );
}
