import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/payments/data/bank_qr_payment.dart';
import 'package:twoalogisticcabineuser/src/features/payments/data/invoice_payment_options.dart';
import 'package:twoalogisticcabineuser/src/features/payments/data/payment_operator_status.dart';
import 'package:twoalogisticcabineuser/src/features/payments/presentation/bank_qr_payment_screen.dart';

import '../../helpers/pump_app.dart';
import 'package:twoalogisticcabineuser/src/features/payments/presentation/usdt_payment_screen.dart';

class _Picker extends FilePicker {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult([
    PlatformFile(
      name: 'proof.pdf',
      size: 4,
      bytes: Uint8List.fromList([37, 80, 68, 70]),
    ),
  ]);
}

class _MediaApi extends ApiClient {
  @override
  Future<Response<T>> getWithProgress<T>(
    String path, {
    Options? options,
    required ProgressCallback onReceiveProgress,
  }) => get<T>(path, options: options);

  @override
  Future<String?> getToken() async => null;
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async => Response<T>(
    requestOptions: RequestOptions(path: path),
    statusCode: 200,
    data:
        base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=',
            )
            as T,
  );
}

class _Receipts extends BankQrPaymentService {
  _Receipts() : super(_MediaApi());
  int starts = 0;
  int? receivedPaymentId;
  String? receivedName;
  @override
  Future<BankQrPaymentResult?> startBankQrPayment(String invoiceId) async {
    starts++;
    throw StateError('foreign must never start RUB');
  }

  @override
  Future<PaymentReceiptUploadResult?> uploadBankQrReceipt({
    required int paymentId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    receivedPaymentId = paymentId;
    receivedName = fileName;
    return PaymentReceiptUploadResult(
      receiptId: 1,
      paymentId: paymentId,
      invoiceStatus: 'payment_review',
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  String method,
  _Receipts receipts, {
  VoidCallback? onChange,
}) async {
  await tester.pumpApp(
    Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            builder: (_) => BankQrPaymentSheet(
              invoiceId: '12',
              invoiceNumber: 'INV-12',
              selection: InvoicePaymentSelection(
                method: method,
                paymentId: 77,
                currency: method == 'alipay' ? 'CNY' : 'USDT',
                amount: 123.45,
                qrImageUrl: '/uploads/qr.png',
                walletAddress: method == 'alipay'
                    ? null
                    : 'TExampleWalletAddress',
                network: method == 'alipay' ? null : 'TRC20',
                canChange: true,
              ),
              onChangeMethod: onChange,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
    overrides: [
      apiClientProvider.overrideWithValue(_MediaApi()),
      bankQrPaymentServiceProvider.overrideWithValue(receipts),
      paymentOperatorStatusProvider.overrideWith(
        (ref) => Stream.value(
          const PaymentOperatorStatus(sleeping: false, reachable: true),
        ),
      ),
    ],
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  // Image decoding uses the real async queue. Resolve it before waiting for
  // animations: the QR preloader intentionally animates until the first frame.
  expect(find.text('Загрузка QR-кода…'), findsOneWidget);
  final qr = find.byType(Image).first;
  await tester.runAsync(
    () => precacheImage(tester.widget<Image>(qr).image, tester.element(qr)),
  );
  await tester.pumpAndSettle();
  expect(find.text('Загрузка QR-кода…'), findsNothing);
}

void main() {
  testWidgets(
    'legacy USDT invoice screen directs to invoice without creating old payment',
    (tester) async {
      await tester.pumpApp(const UsdtPaymentScreen(amount: 100, invoiceId: 12));
      await tester.pumpAndSettle();
      expect(
        find.text('Выберите способ оплаты в карточке счёта'),
        findsOneWidget,
      );
      expect(find.text('Открыть счёт'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final method in ['usdt_trc20', 'alipay']) {
    testWidgets(
      '$method shows foreign amount and sends receipt against chosen attempt',
      (tester) async {
        FilePicker.platform = _Picker();
        final receipts = _Receipts();
        await _pump(tester, method, receipts);
        expect(receipts.starts, 0);
        expect(
          find.text(method == 'alipay' ? '123.45 CNY' : '123.450000 USDT'),
          findsOneWidget,
        );
        expect(find.text('Я понял'), findsNothing);
        if (method == 'usdt_trc20') {
          expect(find.text('TExampleWalletAddress'), findsOneWidget);
        }
        final confirm = find.ancestor(
          of: find.text('Приложить чек'),
          matching: find.byType(InkWell),
        );
        expect(tester.widget<InkWell>(confirm).onTap, isNotNull);
        final attach = find.text('Приложить чек');
        await tester.ensureVisible(attach);
        await tester.pumpAndSettle();
        await tester.tap(attach);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Файлы').hitTestable(), findsOneWidget);
        expect(receipts.receivedPaymentId, isNull);
        await tester.tap(find.text('Файлы'));
        await tester.pumpAndSettle();
        expect(receipts.receivedPaymentId, 77);
        expect(receipts.receivedName, 'proof.pdf');
        expect(find.text('Чек отправлен на проверку'), findsOneWidget);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      },
    );
    testWidgets('$method can switch before receipt on 280px screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(280, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var changed = false;
      await _pump(tester, method, _Receipts(), onChange: () => changed = true);
      final change = find.text('Изменить способ оплаты');
      await tester.ensureVisible(change);
      await tester.pumpAndSettle();
      await tester.tap(change);
      expect(changed, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
