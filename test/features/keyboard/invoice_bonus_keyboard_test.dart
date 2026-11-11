import '../../helpers/keyboard_acceptance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/data/invoices_provider.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/domain/invoice_item.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/presentation/invoices_screen.dart';
import 'package:twoalogisticcabineuser/src/features/payments/data/payment_operator_status.dart';
import 'package:twoalogisticcabineuser/src/features/referral/data/referral_provider.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    await loadKeyboardAcceptanceFonts();
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'invoice bonus numeric field focus and dismiss ${platform.name}',
      (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = const Size(390, 844);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetViewInsets);
        const item = InvoiceItem(
          id: 'bonus-keyboard',
          invoiceNumber: 'INV-KEYBOARD',
          status: 'unpaid',
          placesCount: 1,
          density: 0,
          weight: 10,
          volume: 0,
          totalCostRub: 1000,
          totalCostUsd: 100,
          clientPricePerKg: 10,
        );
        await t.pumpWidget(
          ProviderScope(
            overrides: [
              referralProvider.overrideWith(
                (_) async => const ReferralData(
                  referralKgBalance: 10,
                  referrals: [],
                  transactions: [],
                ),
              ),
              invoiceStatusesProvider.overrideWith((_) async => []),
              invoiceByIdProvider.overrideWith((_, _) async => item),
              paymentOperatorStatusProvider.overrideWith(
                (_) => Stream.value(
                  PaymentOperatorStatus(sleeping: false, reachable: true),
                ),
              ),
            ],
            child: MaterialApp(
              theme: ThemeData(fontFamily: 'Gilroy', platform: platform),
              locale: const Locale('ru'),
              supportedLocales: const [Locale('ru')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              builder: (context, child) =>
                  AppKeyboardDismissRegion(child: child!),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ClientInvoiceTile(item: item, clientCode: 'TEST'),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.text('INV-KEYBOARD'));
        await t.pumpAndSettle();
        expect(await exerciseCurrentRouteEditors(t), 1);
        expect(
          t.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        final route = ModalRoute.of(t.element(find.byType(TextField)));
        expect(route?.isCurrent, isTrue);
        Navigator.of(t.element(find.byType(TextField))).pop();
        await t.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }
}
