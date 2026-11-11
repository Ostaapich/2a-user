import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:twoalogisticcabineuser/src/features/payments/presentation/payment_qr_timing_warning.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/core/ui/blurred_modal_bottom_sheet.dart';
import 'package:twoalogisticcabineuser/src/features/payments/data/bank_qr_payment.dart';
import 'package:twoalogisticcabineuser/src/features/payments/data/payment_operator_status.dart';
import 'package:twoalogisticcabineuser/src/features/payments/presentation/bank_qr_payment_screen.dart';
import 'package:twoalogisticcabineuser/src/features/self_buyout/data/self_buyout_service.dart';
import 'package:twoalogisticcabineuser/src/features/self_buyout/data/self_buyout_models.dart';
import 'package:twoalogisticcabineuser/src/features/self_buyout/presentation/self_buyout_qr_sheet.dart';
import 'package:twoalogisticcabineuser/src/features/garage/application/garage_providers.dart';
import 'package:twoalogisticcabineuser/src/features/garage/data/garage_repository.dart';
import 'package:twoalogisticcabineuser/src/features/garage/domain/garage_models.dart';
import 'package:twoalogisticcabineuser/src/features/garage/presentation/garage_payment_sheet.dart';
import '../../helpers/pump_app.dart';

class _Picker extends FilePicker {
  int calls = 0;
  bool cancel = false;
  Completer<FilePickerResult?>? pending;
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
  }) async {
    calls++;
    if (pending != null) return pending!.future;
    if (cancel) return null;
    return FilePickerResult([
      PlatformFile(
        name: 'receipt.pdf',
        size: 4,
        bytes: Uint8List.fromList([37, 80, 68, 70]),
      ),
    ]);
  }
}

class _Upload {
  int calls = 0;
  bool fail = false;
  int errorCode = 500;
  Completer<void>? pending;
  final List<List<int>> payloads = [];
  Future<void> send(Uint8List bytes) async {
    calls++;
    payloads.add(bytes.toList());
    if (pending != null) await pending!.future;
    if (fail) {
      throw DioException(
        requestOptions: RequestOptions(path: '/fixture/receipt'),
        response: Response(
          requestOptions: RequestOptions(path: '/fixture/receipt'),
          statusCode: errorCode,
        ),
      );
    }
  }
}

class _Bank extends BankQrPaymentService {
  _Bank(this.upload) : super(ApiClient());
  final _Upload upload;
  @override
  Future<BankQrPaymentResult?> startBankQrPayment(String invoiceId) async =>
      const BankQrPaymentResult(
        paymentId: 101,
        invoiceId: 1,
        invoiceNumber: 'INV-1',
        amountRub: 100,
        sumKopecks: 10000,
        purpose: 'Test',
        qrPayload: 'ST00012|Name=Test|Sum=10000',
        status: 'pending',
      );
  @override
  Future<PaymentReceiptUploadResult?> uploadBankQrReceipt({
    required int paymentId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    await upload.send(bytes);
    return const PaymentReceiptUploadResult(
      receiptId: 1,
      paymentId: 101,
      invoiceStatus: 'payment_review',
    );
  }
}

class _Self extends SelfBuyoutService {
  _Self(this.upload) : super(ApiClient());
  final _Upload upload;
  @override
  Future<SelfBuyoutPaymentInfo?> startBankQr(int requestId) async =>
      const SelfBuyoutPaymentInfo(
        paymentId: 202,
        status: 'pending',
        amountRub: 100,
        sumKopecks: 10000,
        purpose: 'Test',
        qrPayload: 'ST00012|Name=Test|Sum=10000',
      );
  @override
  Future<bool> uploadReceipt({
    required int paymentId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    await upload.send(bytes);
    return true;
  }
}

class _Garage implements GarageRepository {
  _Garage(this.upload);
  final _Upload upload;
  @override
  Future<GarageBankQrPayment> startBankQrPayment(
    int orderId, {
    required String idempotencyKey,
  }) async => const GarageBankQrPayment(
    paymentId: 303,
    garageInvoiceId: 1,
    invoiceNumber: 'GI-1',
    amountRub: 100,
    sumKopecks: 10000,
    purpose: 'Test',
    qrPayload: 'ST00012|Name=Test|Sum=10000',
    status: 'pending',
    reused: false,
  );
  @override
  Future<GarageReceiptUploadResult> uploadPaymentReceipt({
    required int paymentId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    await upload.send(bytes);
    return const GarageReceiptUploadResult(
      receiptId: 1,
      paymentId: 303,
      invoiceStatus: 'payment_review',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unmocked receipt fixture operation');
}

Future<void> _open(
  WidgetTester tester,
  String kind,
  _Upload upload,
  ValueNotifier<bool?> result,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpApp(
    Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result.value = await showBlurredModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              builder: (_) => switch (kind) {
                'invoice' => const BankQrPaymentSheet(
                  invoiceId: '1',
                  invoiceNumber: 'INV-1',
                ),
                'self' => const SelfBuyoutQrSheet(
                  requestId: 1,
                  requestNumber: 'SB-1',
                  cnyAmount: 100,
                ),
                _ => const GaragePaymentSheet(orderId: 1, orderNumber: 'GO-1'),
              },
            );
          },
          child: const Text('Open'),
        ),
      ),
    ),
    overrides: [
      bankQrPaymentServiceProvider.overrideWithValue(_Bank(upload)),
      selfBuyoutServiceProvider.overrideWithValue(_Self(upload)),
      garageRepositoryProvider.overrideWithValue(_Garage(upload)),
      paymentOperatorStatusProvider.overrideWith(
        (ref) => Stream.value(
          const PaymentOperatorStatus(sleeping: false, reachable: true),
        ),
      ),
    ],
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  if (find.text('Я понял').evaluate().isNotEmpty) {
    await tester.tap(find.text('Я понял'));
    await tester.pumpAndSettle();
  }
}

Future<void> _attach(WidgetTester tester) async {
  final button = find.text('Приложить чек');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text('Файлы').hitTestable(), findsOneWidget);
  await tester.tap(find.text('Файлы'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  for (final kind in ['invoice', 'self', 'garage']) {
    testWidgets('$kind attaches then automatically submits once for review', (
      tester,
    ) async {
      final picker = _Picker();
      FilePicker.platform = picker;
      final upload = _Upload();
      final result = ValueNotifier<bool?>(null);
      addTearDown(result.dispose);
      await _open(tester, kind, upload, result);
      expect(find.byType(PaymentRecipientWarning), findsOneWidget);
      expect(
        tester.getBottomRight(find.byType(PaymentRecipientWarning)).dy,
        lessThan(tester.getTopLeft(find.byType(QrImageView)).dy),
      );
      expect(find.text('Я оплатил'), findsNothing);
      expect(find.text('Я оплатил — отправить чек'), findsNothing);
      await _attach(tester);
      await tester.pumpAndSettle();
      expect(picker.calls, 1);
      expect(upload.calls, 1);
      expect(result.value, true);
      await tester.pump(const Duration(seconds: 4));
    });
    testWidgets('$kind picker cancel never reports payment', (tester) async {
      FilePicker.platform = _Picker()..cancel = true;
      final upload = _Upload();
      final result = ValueNotifier<bool?>(null);
      addTearDown(result.dispose);
      await _open(tester, kind, upload, result);
      await _attach(tester);
      await tester.pumpAndSettle();
      expect(upload.calls, 0);
      expect(result.value, isNull);
      expect(find.text('Приложить чек'), findsOneWidget);
    });
    for (final status in [500, 409]) {
      testWidgets(
        '$kind failed$status retains selected receipt and retries without picker',
        (tester) async {
          final picker = _Picker();
          FilePicker.platform = picker;
          final upload = _Upload()
            ..fail = true
            ..errorCode = status;
          final result = ValueNotifier<bool?>(null);
          addTearDown(result.dispose);
          await _open(tester, kind, upload, result);
          await _attach(tester);
          await tester.pumpAndSettle();
          expect(result.value, isNull);
          expect(upload.calls, 1);
          expect(find.text('receipt.pdf'), findsOneWidget);
          upload.fail = false;
          final retry = find.text('Повторить отправку');
          await tester.ensureVisible(retry);
          await tester.tap(retry);
          await tester.pumpAndSettle();
          expect(upload.calls, 2);
          expect(picker.calls, 1);
          expect(upload.payloads[0], upload.payloads[1]);
          expect(result.value, true);
          await tester.pump(const Duration(seconds: 4));
        },
      );
    }
    testWidgets(
      '$kind pending upload cannot submit twice or show success early',
      (tester) async {
        FilePicker.platform = _Picker();
        final upload = _Upload()..pending = Completer<void>();
        final result = ValueNotifier<bool?>(null);
        addTearDown(result.dispose);
        await _open(tester, kind, upload, result);
        await _attach(tester);
        expect(upload.calls, 1);
        expect(result.value, isNull);
        final primary = find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString().endsWith('PrimaryButton'),
        );
        await tester.ensureVisible(primary);
        await tester.pump(const Duration(milliseconds: 100));
        expect(primary.hitTestable(), findsOneWidget);
        await tester.tap(primary);
        await tester.pump(const Duration(milliseconds: 300));
        expect(upload.calls, 1);
        expect(result.value, isNull);
        upload.pending!.complete();
        await tester.pumpAndSettle();
        expect(result.value, true);
        expect(upload.calls, 1);
        await tester.pump(const Duration(seconds: 4));
      },
    );
  }
}
