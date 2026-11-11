import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/data/invoices_provider.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/domain/invoice_item.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/presentation/invoices_screen.dart';
import 'package:twoalogisticcabineuser/src/features/payments/data/payment_operator_status.dart';
import 'package:twoalogisticcabineuser/src/features/referral/data/referral_provider.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    await (FontLoader('Gilroy')
          ..addFont(rootBundle.load('assets/fonts/gilroy/Gilroy-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/gilroy/Gilroy-Bold.ttf')))
        .load();
  });

  for (final (usd, cny, rub, usdText, cnyText, rubText) in [
    (88.15, 632.30, 8155.63, '\$88,15', '¥632,30', '8\u00a0155,63 ₽'),
    (88.0, 632.0, 8156.0, '\$88,00', '¥632,00', '8\u00a0156,00 ₽'),
  ]) {
    testWidgets('invoice list and detail retain cents for $usd USD', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final invoice = InvoiceItem.fromJson({
        'id': 'precision-test',
        'invoiceNumber': 'INV-PRECISION',
        'status': 'paid',
        'placesCount': 1,
        'totalCostUSD': usd,
        'totalCostCNY': cny,
        'totalCostRUB': rub,
      });
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
      expect(find.text(usdText), findsOneWidget);

      await tester.tap(find.text('INV-PRECISION'));
      await tester.pumpAndSettle();
      expect(find.text(usdText), findsWidgets);
      expect(find.text(cnyText), findsOneWidget);
      expect(find.text(rubText), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
