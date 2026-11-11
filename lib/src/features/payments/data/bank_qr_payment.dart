import '../../../core/services/analytics_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';

import '../../../core/network/api_client.dart';

/// Bank QR (рубли) Sprint 4 — результат старта QR-оплаты.
class BankQrPaymentResult {
  final int paymentId;
  final int invoiceId;
  final String invoiceNumber;
  final double amountRub;
  final int sumKopecks;
  final String purpose;
  final String qrPayload;
  final String status;
  final bool reused;

  const BankQrPaymentResult({
    required this.paymentId,
    required this.invoiceId,
    required this.invoiceNumber,
    required this.amountRub,
    required this.sumKopecks,
    required this.purpose,
    required this.qrPayload,
    required this.status,
    this.reused = false,
  });

  factory BankQrPaymentResult.fromJson(Map<String, dynamic> json) {
    return BankQrPaymentResult(
      paymentId: (json['paymentId'] as num).toInt(),
      invoiceId: (json['invoiceId'] as num).toInt(),
      invoiceNumber: json['invoiceNumber']?.toString() ?? '',
      amountRub: (json['amountRub'] as num?)?.toDouble() ?? 0,
      sumKopecks: (json['sumKopecks'] as num?)?.toInt() ?? 0,
      purpose: json['purpose']?.toString() ?? '',
      qrPayload: json['qrPayload']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      reused: json['reused'] == true,
    );
  }
}

/// Результат загрузки чека.
class PaymentReceiptUploadResult {
  final int receiptId;
  final int paymentId;
  final String invoiceStatus;

  const PaymentReceiptUploadResult({
    required this.receiptId,
    required this.paymentId,
    required this.invoiceStatus,
  });

  factory PaymentReceiptUploadResult.fromJson(Map<String, dynamic> json) {
    return PaymentReceiptUploadResult(
      receiptId: (json['receiptId'] as num).toInt(),
      paymentId: (json['paymentId'] as num).toInt(),
      invoiceStatus: json['invoiceStatus']?.toString() ?? 'payment_review',
    );
  }
}

class BankQrPaymentService {
  final ApiClient _apiClient;
  BankQrPaymentService(this._apiClient);

  /// Старт оплаты в рублях по QR. Идемпотентно на бэке.
  Future<BankQrPaymentResult?> startBankQrPayment(String invoiceId) async {
    return AnalyticsService.traceOperation(
      WorkflowAction.paymentQrStart,
      () async {
        try {
          final response = await _apiClient.post(
            '/client/invoices/$invoiceId/bank-qr/start',
            data: const <String, dynamic>{},
          );
          if (response.statusCode == 200 && response.data != null) {
            return BankQrPaymentResult.fromJson(
              response.data as Map<String, dynamic>,
            );
          }
          return null;
        } on DioException catch (e) {
          debugPrint('startBankQrPayment error: $e');
          rethrow;
        }
      },
      outcome: (result) =>
          result != null ? WorkflowStage.succeeded : WorkflowStage.failed,
    );
  }

  /// Загрузка чека (изображение/PDF). Переводит счёт в payment_review.
  Future<PaymentReceiptUploadResult?> uploadBankQrReceipt({
    required int paymentId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    return AnalyticsService.traceOperation(
      WorkflowAction.paymentReceipt,
      () async {
        try {
          final parts = mimeType.split('/');
          final type = parts.isNotEmpty ? parts[0] : 'application';
          final subtype = parts.length > 1 ? parts[1] : 'octet-stream';
          final formData = FormData.fromMap({
            'file': MultipartFile.fromBytes(
              bytes,
              filename: fileName,
              contentType: MediaType(type, subtype),
            ),
          });
          final response = await _apiClient.post(
            '/client/payments/$paymentId/receipt',
            data: formData,
            options: Options(headers: {'Content-Type': 'multipart/form-data'}),
          );
          if (response.statusCode == 200 && response.data != null) {
            return PaymentReceiptUploadResult.fromJson(
              response.data as Map<String, dynamic>,
            );
          }
          return null;
        } on DioException catch (e) {
          debugPrint('uploadBankQrReceipt error: $e');
          rethrow;
        }
      },
      outcome: (result) =>
          result != null ? WorkflowStage.succeeded : WorkflowStage.failed,
    );
  }
}

final bankQrPaymentServiceProvider = Provider<BankQrPaymentService>((ref) {
  final apiClient = ref.read(apiClientProvider);
  return BankQrPaymentService(apiClient);
});
