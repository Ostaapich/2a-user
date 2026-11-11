import 'package:twoalogisticcabineuser/src/features/auth/data/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/data/invoices_provider.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/domain/invoice_item.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/presentation/invoices_screen.dart';
import 'package:twoalogisticcabineuser/src/features/payments/data/payment_operator_status.dart';
import 'package:twoalogisticcabineuser/src/features/payments/presentation/payment_operator_sleeping_notice.dart';
import 'package:twoalogisticcabineuser/src/features/referral/data/referral_provider.dart';
import 'package:twoalogisticcabineuser/src/features/tariffs/data/tariffs_provider.dart';
import 'package:twoalogisticcabineuser/src/features/tariffs/presentation/tariffs_screen.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_target.dart';

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('ru'),
  supportedLocales: const [Locale('ru')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: Scaffold(body: child),
);

Finder _anchor(String id) => find.byWidgetPredicate(
  (widget) => widget is TrainingTarget && widget.id == id,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('ru');
    await (FontLoader('Gilroy')
          ..addFont(rootBundle.load('assets/fonts/gilroy/Gilroy-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/gilroy/Gilroy-Bold.ttf')))
        .load();
  });

  for (final (bankQr, sleeping) in [
    (false, false),
    (true, false),
    (false, true),
  ]) {
    testWidgets(
      'invoice highlights payment state QR=$bankQr sleeping=$sleeping',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final invoice = InvoiceItem.fromJson({
          'id': 'tour-invoice',
          'invoiceNumber': 'TEST-123',
          'status': 'unpaid',
          'placesCount': 1,
          'totalCostUSD': 124,
          'totalCostRUB': 11829.6,
          'bankQrPaymentAvailable': bankQr,
        });
        final registry = TrainingTargetRegistry();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              trainingTargetRegistryProvider.overrideWithValue(registry),
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
                  PaymentOperatorStatus(sleeping: sleeping, reachable: true),
                ),
              ),
            ],
            child: _app(
              SingleChildScrollView(
                child: ClientInvoiceTile(
                  item: invoice,
                  clientCode: 'TEST',
                  trainingTarget: true,
                ),
              ),
            ),
          ),
        );
        await _frames(tester);
        expect(
          tester.getRect(_anchor('invoice.open')),
          tester.getRect(find.text('TEST-123')),
        );
        expect(tester.getSize(_anchor('invoice.open')).height, lessThan(40));
        expect(registry.contextFor('invoice.pay'), isNull);
        registry.activationFor(
          'invoice.open',
          registry.contextFor('invoice.open')!,
        )!();
        await _frames(tester);
        expect(
          registry.contextFor('invoice.open'),
          isNull,
          reason: 'Root detail sheet hides the list anchor',
        );
        expect(registry.contextFor('invoice.amount'), isNotNull);
        if (sleeping) {
          expect(registry.contextFor('invoice.pay'), isNull);
          final notice = _anchor('invoice.pay.unavailable');
          expect(notice, findsOneWidget);
          expect(
            tester.getRect(notice),
            tester.getRect(find.byType(PaymentOperatorSleepingNotice)),
          );
          expect(registry.contextFor('invoice.pay.unavailable'), isNotNull);
        } else {
          final paymentAnchor = _anchor('invoice.pay');
          expect(paymentAnchor, findsOneWidget);
          expect(
            find.descendant(of: paymentAnchor, matching: find.text('Оплатить')),
            findsOneWidget,
          );
          expect(tester.getSize(paymentAnchor).height, lessThanOrEqualTo(60));
          expect(_anchor('invoice.pay.unavailable'), findsNothing);
        }
        expect(tester.takeException(), isNull);
        // No payment button is pressed: measuring training must not transact.
        await tester.pumpWidget(const SizedBox.shrink());
        await _frames(tester);
      },
    );
  }

  testWidgets('paid invoice dismisses to payable invoice number', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    InvoiceItem fixture(String id, String status) => InvoiceItem.fromJson({
      'id': id,
      'invoiceNumber': id,
      'status': status,
      'placesCount': 1,
      'totalCostUSD': 124,
      'totalCostRUB': 11829.6,
      'bankQrPaymentAvailable': false,
    });
    final paid = fixture('PAID-1', 'paid');
    final unpaid = fixture('UNPAID-2', 'unpaid');
    final registry = TrainingTargetRegistry();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trainingTargetRegistryProvider.overrideWithValue(registry),
          activeClientCodeProvider.overrideWith((_) => 'TEST'),
          authProvider.overrideWith(_InvoiceFixtureAuth.new),
          invoiceDirectoryProvider.overrideWith(
            (_, _) async => InvoiceDirectoryPage(
              items: [paid, unpaid],
              total: 2,
              hasMore: false,
            ),
          ),
          invoiceByIdProvider.overrideWith(
            (_, id) async => id == paid.id ? paid : unpaid,
          ),
          invoiceStatusesProvider.overrideWith((_) async => []),
          referralProvider.overrideWith(
            (_) async => const ReferralData(
              referralKgBalance: 0,
              referrals: [],
              transactions: [],
            ),
          ),
          paymentOperatorStatusProvider.overrideWith(
            (_) => Stream.value(PaymentOperatorStatus.workingFallback),
          ),
        ],
        child: _app(const InvoicesScreen()),
      ),
    );
    await _frames(tester);
    await tester.ensureVisible(_anchor('invoice.open'));
    registry.activationFor(
      'invoice.open',
      registry.contextFor('invoice.open')!,
    )!();
    await _frames(tester);
    expect(registry.contextFor('invoice.pay'), isNull);
    expect(tester.getSize(_anchor('invoice.sheet.dismiss')).width, 42);
    registry.activationFor(
      'invoice.sheet.dismiss',
      registry.contextFor('invoice.sheet.dismiss')!,
    )!();
    await _frames(tester);
    expect(_anchor('invoice.sheet.dismiss'), findsNothing);
    await tester.scrollUntilVisible(
      _anchor('invoice.open-payable'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(
        of: _anchor('invoice.open-payable'),
        matching: find.text('UNPAID-2'),
      ),
      findsOneWidget,
    );
    registry.activationFor(
      'invoice.open-payable',
      registry.contextFor('invoice.open-payable')!,
    )!();
    await _frames(tester);
    expect(registry.contextFor('invoice.pay'), isNotNull);
    expect(
      registry.activationFor(
        'invoice.pay',
        registry.contextFor('invoice.pay')!,
      ),
      isNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('tariffs target is the first tariff name, not the card or page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userTariffsProvider.overrideWith(
            (_) async => const UserTariffsData(
              deliveryTariffs: [
                UserDeliveryTariff(
                  id: 1,
                  name: 'Первый тариф',
                  baseCost: 4,
                  allowedItems: 'Условия тарифа',
                ),
                UserDeliveryTariff(id: 2, name: 'Второй тариф', baseCost: 6),
              ],
            ),
          ),
        ],
        child: _app(const TariffsScreen()),
      ),
    );
    await _frames(tester);
    expect(_anchor('tariffs.name'), findsOneWidget);
    expect(
      tester.getRect(_anchor('tariffs.name')),
      tester.getRect(find.text('Первый тариф')),
    );
    expect(tester.getSize(_anchor('tariffs.name')).height, lessThan(50));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _frames(tester);
  });
}

class _InvoiceFixtureAuth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    isLoggedIn: true,
    clientId: 1,
    userDomain: 'fixture.invalid',
  );
}
