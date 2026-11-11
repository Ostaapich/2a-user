import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:twoalogisticcabineuser/src/features/payments/data/bank_qr_payment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/self_buyout/data/self_buyout_service.dart';
import 'package:twoalogisticcabineuser/src/features/payments/data/invoice_payment_options.dart';
import 'package:twoalogisticcabineuser/src/features/payments/data/payment_operator_status.dart';
import 'package:twoalogisticcabineuser/src/features/payments/presentation/bank_qr_payment_screen.dart';
import 'package:twoalogisticcabineuser/src/features/payments/presentation/payment_receipt_picker.dart';
import '../../helpers/pump_app.dart';

class _LostResponseApi extends ApiClient {
  final keys = <String>[];
  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    keys.add(
      (data as FormData).fields
          .firstWhere((e) => e.key == 'clientRequestKey')
          .value,
    );
    throw DioException(requestOptions: RequestOptions(path: path));
  }
}

class _NeverStartBankQrService extends BankQrPaymentService {
  _NeverStartBankQrService() : super(ApiClient());
  int startCalls = 0;
  @override
  Future<BankQrPaymentResult?> startBankQrPayment(String invoiceId) async {
    startCalls++;
    throw StateError('A receipt-only resume must not create a payment');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'lost response and recreated service reuse durable intent; changed amount starts another',
    () async {
      SharedPreferences.setMockInitialValues({});
      final api = _LostResponseApi();
      Future<void> send(double amount) async {
        await expectLater(
          SelfBuyoutService(api).createRequest(
            clientCodeId: 7,
            amountEnteredIn: 'cny',
            amount: amount,
            warningAccepted: true,
            fileBytes: Uint8List.fromList([1, 2, 3]),
            fileName: 'qr.png',
            fileMime: 'image/png',
          ),
          throwsA(isA<DioException>()),
        );
      }

      await send(100);
      await send(100);
      await send(101);
      expect(api.keys[0], api.keys[1]);
      expect(api.keys[1], isNot(api.keys[2]));
    },
  );
  test('receipt limit rejects oversize before file data is loaded', () {
    expect(
      () => validatePaymentReceiptSize(paymentReceiptMaxBytes),
      returnsNormally,
    );
    expect(
      () => validatePaymentReceiptSize(paymentReceiptMaxBytes + 1),
      throwsA(isA<PaymentReceiptTooLarge>()),
    );
  });
  for (final method in ['bank_qr', 'usdt_trc20']) {
    testWidgets('$method receipt-only resume hides old transfer instructions', (
      tester,
    ) async {
      final service = _NeverStartBankQrService();
      await tester.pumpApp(
        BankQrPaymentSheet(
          invoiceId: '1',
          invoiceNumber: 'INV-1',
          selection: InvoicePaymentSelection(
            method: method,
            paymentId: 7,
            currency: method == 'bank_qr' ? 'RUB' : 'USDT',
            amount: 100,
            receiptOnly: true,
            canChange: true,
            qrPayload: 'ST00012|Sum=10000',
            sumKopecks: 10000,
            qrImageUrl: 'https://example.invalid/old-qr.png',
            walletAddress: 'OLD-WALLET',
          ),
        ),
        overrides: [
          bankQrPaymentServiceProvider.overrideWithValue(service),
          paymentOperatorStatusProvider.overrideWith(
            (ref) => Stream.value(
              const PaymentOperatorStatus(sleeping: true, reachable: true),
            ),
          ),
        ],
      );
      await tester.pumpAndSettle();
      expect(service.startCalls, 0);
      expect(find.text('Приложить чек'), findsOneWidget);
      expect(find.text('Сумма ранее созданной оплаты'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('QR для оплаты'), findsNothing);
      expect(find.text('Сохранить QR-код'), findsNothing);
      expect(find.text('OLD-WALLET'), findsNothing);
      expect(find.text('Я понял'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'existing invoice receipt controls remain available during operator rest',
    (tester) async {
      await tester.pumpApp(
        const BankQrPaymentSheet(
          invoiceId: '1',
          invoiceNumber: 'INV-1',
          selection: InvoicePaymentSelection(
            method: 'bank_qr',
            paymentId: 7,
            currency: 'RUB',
            amount: 1000,
            qrPayload: 'ST00012|Name=Test|Sum=100000',
            sumKopecks: 100000,
          ),
        ),
        overrides: [
          paymentOperatorStatusProvider.overrideWith(
            (ref) => Stream.value(
              const PaymentOperatorStatus(sleeping: true, reachable: true),
            ),
          ),
        ],
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Я понял'));
      await tester.pumpAndSettle();
      expect(find.text('Я оплатил'), findsNothing);
      expect(find.text('Приложить чек'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
