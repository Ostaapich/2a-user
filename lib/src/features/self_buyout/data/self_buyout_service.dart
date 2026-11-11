import '../../../core/services/analytics_service.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paged_list_loader.dart';
import 'self_buyout_models.dart';

class SelfBuyoutService {
  final ApiClient _apiClient;
  SelfBuyoutService(this._apiClient);

  Future<SelfBuyoutAvailability> getAvailability() async {
    try {
      final res = await _apiClient.get('/client/self-buyout/availability');
      if (res.statusCode == 200 && res.data is Map) {
        return SelfBuyoutAvailability.fromJson(
          res.data as Map<String, dynamic>,
        );
      }
      throw const FormatException('Invalid self-buyout availability response');
    } on DioException catch (e) {
      debugPrint('getAvailability error: $e');
      rethrow;
    }
  }

  Future<List<SelfBuyoutRequest>> getRequests() async {
    final list = await loadPagedList(
      listKey: 'requests',
      fetchPage: (query) async => (await _apiClient.get(
        '/client/self-buyout/requests',
        queryParameters: query,
      )).data,
    );
    return list
        .whereType<Map<String, dynamic>>()
        .map(SelfBuyoutRequest.fromJson)
        .toList();
  }

  Future<SelfBuyoutVerification> submitVerification({
    required String fullName,
    required String phone,
    required String telegram,
  }) async {
    final res = await _apiClient.post(
      '/client/self-buyout/verification',
      data: {
        'fullName': fullName.trim(),
        'phone': phone.trim(),
        'telegram': telegram.trim(),
      },
    );
    return SelfBuyoutVerification.fromJson(
      res.data?['verification'] as Map<String, dynamic>?,
    );
  }

  Future<SelfBuyoutDetail> getDetail(int requestId) async {
    final res = await _apiClient.get('/client/self-buyout/requests/$requestId');
    return SelfBuyoutDetail.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Uint8List> getTransferProofBytes(String gatedUrl) async {
    final res = await _apiClient.get<List<int>>(
      _apiPath(gatedUrl),
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = res.data;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Transfer proof response is empty');
    }
    return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  }

  String _apiPath(String url) {
    final uri = Uri.tryParse(url);
    final path = uri?.path ?? url;
    if (path.startsWith('/api/')) return path.substring(4);
    if (path.startsWith('api/')) return '/${path.substring(4)}';
    return path.startsWith('/') ? path : '/$path';
  }

  /// Создать заявку с обязательным изображением QR/реквизитов.
  Future<SelfBuyoutRequest> createRequest({
    required int clientCodeId,
    required String amountEnteredIn, // cny | rub
    required double amount,
    required bool warningAccepted,
    bool? alipayTopUpExperienced,
    required Uint8List fileBytes,
    required String fileName,
    required String fileMime,
  }) async {
    return AnalyticsService.traceOperation(
      WorkflowAction.selfBuyoutCreate,
      () async {
        // Persist the intention before sending money instructions. A lost response or
        // reopening the form retries the same key; changing any field starts a new intention.
        final fingerprint = sha256
            .convert(
              utf8.encode(
                jsonEncode([
                  clientCodeId,
                  amountEnteredIn,
                  amount,
                  warningAccepted,
                  alipayTopUpExperienced,
                  fileMime,
                  sha256.convert(fileBytes).toString(),
                ]),
              ),
            )
            .toString();
        final preferences = await SharedPreferences.getInstance();
        final preferenceKey = 'self_buyout.pending.v1.$fingerprint';
        final requestKey =
            preferences.getString(preferenceKey) ?? const Uuid().v4();
        await preferences.setString(preferenceKey, requestKey);
        final map = <String, dynamic>{
          'clientRequestKey': requestKey,
          'clientCodeId': clientCodeId.toString(),
          'amountEnteredIn': amountEnteredIn,
          'amount': amount.toString(),
          'warningAccepted': warningAccepted.toString(),
          if (alipayTopUpExperienced != null)
            'alipayTopUpExperienced': alipayTopUpExperienced.toString(),
        };
        final parts = fileMime.split('/');
        map['transferQr'] = MultipartFile.fromBytes(
          fileBytes,
          filename: fileName,
          contentType: MediaType(
            parts.isNotEmpty ? parts[0] : 'image',
            parts.length > 1 ? parts[1] : 'jpeg',
          ),
        );
        final formData = FormData.fromMap(map);
        final res = await _apiClient.post(
          '/client/self-buyout/requests',
          data: formData,
          options: Options(headers: {'Content-Type': 'multipart/form-data'}),
        );
        final created = SelfBuyoutRequest.fromJson(
          res.data['request'] as Map<String, dynamic>,
        );
        await preferences.remove(preferenceKey);
        return created;
      },
    );
  }

  Future<SelfBuyoutRequest> correctTransferRequisites({
    required int requestId,
    required Uint8List fileBytes,
    required String fileName,
    required String fileMime,
  }) async {
    final parts = fileMime.split('/');
    final map = <String, dynamic>{
      'transferQr': MultipartFile.fromBytes(
        fileBytes,
        filename: fileName,
        contentType: MediaType(
          parts.isNotEmpty ? parts[0] : 'image',
          parts.length > 1 ? parts[1] : 'jpeg',
        ),
      ),
    };
    final res = await _apiClient.patch(
      '/client/self-buyout/requests/$requestId/transfer-requisites',
      data: FormData.fromMap(map),
      options: Options(headers: {'Content-Type': 'multipart/form-data'}),
    );
    return SelfBuyoutRequest.fromJson(
      res.data['request'] as Map<String, dynamic>,
    );
  }

  /// Старт QR-оплаты по заявке. Идемпотентно на бэке.
  Future<SelfBuyoutPaymentInfo?> startBankQr(int requestId) async {
    return AnalyticsService.traceOperation(
      WorkflowAction.paymentQrStart,
      () async {
        final res = await _apiClient.post(
          '/client/self-buyout/requests/$requestId/bank-qr/start',
          data: const <String, dynamic>{},
        );
        if (res.statusCode == 200 && res.data is Map) {
          return SelfBuyoutPaymentInfo.fromStartJson(
            res.data as Map<String, dynamic>,
          );
        }
        return null;
      },
      outcome: (result) =>
          result != null ? WorkflowStage.succeeded : WorkflowStage.failed,
    );
  }

  Future<bool> uploadReceipt({
    required int paymentId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    return AnalyticsService.traceOperation(
      WorkflowAction.paymentReceipt,
      () async {
        final parts = mimeType.split('/');
        final formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(
            bytes,
            filename: fileName,
            contentType: MediaType(
              parts.isNotEmpty ? parts[0] : 'application',
              parts.length > 1 ? parts[1] : 'octet-stream',
            ),
          ),
        });
        final res = await _apiClient.post(
          '/client/self-buyout/payments/$paymentId/receipt',
          data: formData,
          options: Options(headers: {'Content-Type': 'multipart/form-data'}),
        );
        return res.statusCode == 200;
      },
      outcome: (result) =>
          result ? WorkflowStage.succeeded : WorkflowStage.failed,
    );
  }

  Future<bool> cancel(int requestId) async {
    final res = await _apiClient.post(
      '/client/self-buyout/requests/$requestId/cancel',
      data: const <String, dynamic>{},
    );
    return res.statusCode == 200;
  }
}

final selfBuyoutServiceProvider = Provider<SelfBuyoutService>((ref) {
  return SelfBuyoutService(ref.read(apiClientProvider));
});

/// Доступность самовыкупа (для меню и экрана).
final selfBuyoutAvailabilityProvider = FutureProvider<SelfBuyoutAvailability>((
  ref,
) async {
  return ref.read(selfBuyoutServiceProvider).getAvailability();
});

/// Список заявок клиента.
final selfBuyoutRequestsProvider =
    FutureProvider.autoDispose<List<SelfBuyoutRequest>>((ref) async {
      return ref.read(selfBuyoutServiceProvider).getRequests();
    });
