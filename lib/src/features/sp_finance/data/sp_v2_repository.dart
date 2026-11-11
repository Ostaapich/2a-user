import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paged_list_loader.dart';
import 'sp_v2_models.dart';

MediaType? _mediaTypeForMimeType(String? mimeType) {
  if (mimeType == null || mimeType.trim().isEmpty || !mimeType.contains('/')) {
    return null;
  }
  final parts = mimeType.split('/');
  if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
    return null;
  }
  return MediaType(parts[0], parts[1]);
}

MediaType _mediaTypeForFileName(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return MediaType('image', 'jpeg');
  }
  if (lower.endsWith('.png')) return MediaType('image', 'png');
  if (lower.endsWith('.webp')) return MediaType('image', 'webp');
  if (lower.endsWith('.gif')) return MediaType('image', 'gif');
  if (lower.endsWith('.heic')) return MediaType('image', 'heic');
  if (lower.endsWith('.heif')) return MediaType('image', 'heif');
  return MediaType('image', 'jpeg');
}

class SpV2Repository {
  final ApiClient _apiClient;

  const SpV2Repository(this._apiClient);

  Future<List<SpV2Purchase>> getPurchases({String? query}) async {
    final response = await _apiClient.get(
      '/client/sp-v2/purchases',
      queryParameters: {
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      },
    );
    final data = response.data as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map(SpV2Purchase.fromJson)
        .toList(growable: false);
  }

  Future<SpV2PurchaseDirectoryPage> getPurchasesPage(
    SpV2PurchaseDirectoryQuery query,
  ) async {
    final response = await _apiClient.get(
      '/client/sp-v2/purchases',
      queryParameters: query.toQueryParameters(),
    );
    return SpV2PurchaseDirectoryPage.fromResponse(response.data);
  }

  Future<SpV2Purchase> getPurchase(int id) async {
    final response = await _apiClient.get('/client/sp-v2/purchases/$id');
    return SpV2Purchase.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SpV2Purchase> createPurchase(CreateSpV2PurchaseInput input) async {
    final response = await _apiClient.post(
      '/client/sp-v2/purchases',
      data: input.toJson(),
    );
    return SpV2Purchase.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SpV2Purchase> updatePurchase(
    int id, {
    String? kind,
    String? title,
    String? description,
    String? status,
    String? currency,
    bool? isAcceptingItems,
    double? purchaseRate,
    String? commissionMode,
    SpV2ClientCardSections? clientCardSections,
  }) async {
    final response = await _apiClient.patch(
      '/client/sp-v2/purchases/$id',
      data: {
        if (kind != null) 'kind': kind,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (status != null) 'status': status,
        if (currency != null) 'currency': currency,
        if (isAcceptingItems != null) 'isAcceptingItems': isAcceptingItems,
        if (purchaseRate != null) 'purchaseRate': purchaseRate,
        if (commissionMode != null) 'commissionMode': commissionMode,
        if (clientCardSections != null) ...clientCardSections.toJson(),
      },
    );
    return SpV2Purchase.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SpV2Purchase> updatePurchaseLifecycle(
    int id, {
    required String title,
    String? kind,
    required String status,
    required String currency,
    required bool isAcceptingItems,
    required DateTime startedAt,
    required DateTime? dispatchedFromChinaAt,
    required DateTime? completedAt,
    required SpV2ClientCardSections clientCardSections,
    String? description,
  }) async {
    final response = await _apiClient.patch(
      '/client/sp-v2/purchases/$id',
      data: {
        'title': title,
        if (kind != null) 'kind': kind,
        if (description != null && description.trim().isNotEmpty)
          'description': description,
        'status': status,
        'currency': currency,
        'isAcceptingItems': isAcceptingItems,
        'startedAt': spDateOnly(startedAt),
        'dispatchedFromChinaAt': dispatchedFromChinaAt == null
            ? null
            : spDateOnly(dispatchedFromChinaAt),
        'completedAt': completedAt == null ? null : spDateOnly(completedAt),
        ...clientCardSections.toJson(),
      },
    );
    return SpV2Purchase.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<SpV2Customer>> getCustomers({String? query}) async {
    final data = await loadPagedList(
      query: {if (query != null && query.trim().isNotEmpty) 'q': query.trim()},
      fetchPage: (params) async => (await _apiClient.get(
        '/client/sp-v2/customers',
        queryParameters: params,
      )).data,
    );
    return data
        .whereType<Map<String, dynamic>>()
        .map(SpV2Customer.fromJson)
        .toList(growable: false);
  }

  Future<SpV2Customer> createCustomer({
    required String fullName,
    String? phone,
    String? email,
    String? telegram,
    String? whatsapp,
    String? wechat,
    String? vk,
    String? max,
    String? city,
    String? deliveryAddress,
    String? comment,
  }) async {
    final response = await _apiClient.post(
      '/client/sp-v2/customers',
      data: {
        'fullName': fullName,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        if (telegram != null) 'telegram': telegram,
        if (whatsapp != null) 'whatsapp': whatsapp,
        if (wechat != null) 'wechat': wechat,
        if (vk != null) 'vk': vk,
        if (max != null) 'max': max,
        if (city != null) 'city': city,
        if (deliveryAddress != null) 'deliveryAddress': deliveryAddress,
        if (comment != null) 'comment': comment,
      },
    );
    return SpV2Customer.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SpV2Customer> updateCustomer(
    int id, {
    required String fullName,
    String? phone,
    String? email,
    String? telegram,
    String? whatsapp,
    String? wechat,
    String? vk,
    String? max,
    String? city,
    String? deliveryAddress,
    String? comment,
  }) async {
    final response = await _apiClient.patch(
      '/client/sp-v2/customers/$id',
      data: {
        'fullName': fullName,
        'phone': phone,
        'email': email,
        'telegram': telegram,
        'whatsapp': whatsapp,
        'wechat': wechat,
        'vk': vk,
        'max': max,
        'city': city,
        'deliveryAddress': deliveryAddress,
        'comment': comment,
      },
    );
    return SpV2Customer.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SpV2Expense> createExpense(
    int purchaseId,
    CreateSpV2ExpenseInput input,
  ) async {
    final response = await _apiClient.post(
      '/client/sp-v2/purchases/$purchaseId/expenses',
      data: input.toJson(),
    );
    return SpV2Expense.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SpV2CustomerShipment> upsertShipment(
    int purchaseId, {
    required int customerId,
    String? status,
    String? carrierName,
    String? trackingNumber,
    double? costRub,
    String? comment,
  }) async {
    final response = await _apiClient.post(
      '/client/sp-v2/purchases/$purchaseId/shipments',
      data: {
        'spCustomerId': customerId,
        if (status != null) 'status': status,
        'carrierName': carrierName,
        'trackingNumber': trackingNumber,
        if (costRub != null) 'costRub': costRub,
        'comment': comment,
      },
    );
    return SpV2CustomerShipment.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SpV2Item> createItem(int purchaseId, CreateSpV2ItemInput input) async {
    final response = await _apiClient.post(
      '/client/sp-v2/purchases/$purchaseId/items',
      data: input.toJson(),
    );
    return SpV2Item.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SpV2Item> updateItem(
    int itemId, {
    int? spCustomerId,
    int? spProductId,
    String? title,
    String? sourceUrl,
    String? sellerInfo,
    String? description,
    String? comment,
    int? quantity,
    String? status,
    String? trackNumber,
    double? actualWeightKg,
    double? shippingCostRub,
    double? shippingCostActualRub,
    double? additionalExpensesRub,
    double? totalDueRub,
    double? purchasePrice,
    double? clientPrice,
    String currency = 'CNY',
    List<String> mediaUrls = const [],
  }) async {
    final response = await _apiClient.patch(
      '/client/sp-v2/items/$itemId',
      data: {
        if (spCustomerId != null) 'spCustomerId': spCustomerId,
        if (spProductId != null) 'spProductId': spProductId,
        if (title != null) 'title': title,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
        if (sellerInfo != null) 'sellerInfo': sellerInfo,
        if (description != null) 'description': description,
        if (comment != null) 'comment': comment,
        if (quantity != null) 'quantity': quantity,
        if (status != null) 'status': status,
        if (trackNumber != null) 'trackNumber': trackNumber,
        if (currency == 'RUB') ...{
          if (purchasePrice != null) 'purchasePriceRub': purchasePrice,
          if (clientPrice != null) 'clientPriceRub': clientPrice,
        } else ...{
          if (purchasePrice != null) 'purchasePriceYuan': purchasePrice,
          if (clientPrice != null) 'clientPriceYuan': clientPrice,
        },
        if (actualWeightKg != null) 'actualWeightKg': actualWeightKg,
        if (shippingCostRub != null) 'shippingCostRub': shippingCostRub,
        if (shippingCostActualRub != null)
          'shippingCostActualRub': shippingCostActualRub,
        if (additionalExpensesRub != null)
          'additionalExpensesRub': additionalExpensesRub,
        if (totalDueRub != null) 'totalDueRub': totalDueRub,
        if (mediaUrls.isNotEmpty) 'mediaUrls': mediaUrls,
      },
    );
    return SpV2Item.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SpV2BulkApplyResult> applyBulkItemUpdates(
    int purchaseId, {
    required String operation,
    required List<SpV2BulkItemUpdate> items,
    String? targetStatus,
    int? targetCustomerId,
    int? targetPurchaseId,
    String? archiveReason,
  }) async {
    final response = await _apiClient.post(
      '/client/sp-v2/purchases/$purchaseId/items/bulk',
      data: {
        'operation': operation,
        'items': items.map((item) => item.toJson()).toList(growable: false),
        if (targetStatus != null) 'targetStatus': targetStatus,
        if (targetCustomerId != null) 'targetCustomerId': targetCustomerId,
        if (targetPurchaseId != null) 'targetPurchaseId': targetPurchaseId,
        if (archiveReason != null) 'archiveReason': archiveReason,
      },
    );
    return SpV2BulkApplyResult.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SpV2BulkOptions> getBulkOptions(int purchaseId) async {
    final response = await _apiClient.get(
      '/client/sp-v2/purchases/$purchaseId/items/bulk',
    );
    return SpV2BulkOptions.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SpV2Item> setItemPayment(
    int itemId, {
    required String type,
    required bool paid,
    double? amountRub,
    double? amountYuan,
  }) async {
    final response = await _apiClient.patch(
      '/client/sp-v2/items/$itemId/payment',
      data: {
        'type': type,
        'paid': paid,
        if (amountRub != null) 'amountRub': amountRub,
        if (amountYuan != null) 'amountYuan': amountYuan,
      },
    );
    return SpV2Item.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SpV2Payment> setCustomerPayment(
    int customerId, {
    required int purchaseId,
    required String type,
    required bool paid,
    double? amountRub,
  }) async {
    final response = await _apiClient.patch(
      '/client/sp-v2/customers/$customerId/payment',
      data: {
        'purchaseId': purchaseId,
        'type': type,
        'paid': paid,
        if (amountRub != null) 'amountRub': amountRub,
      },
    );
    return SpV2Payment.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> setCustomerItemsPayment(
    int customerId, {
    required int purchaseId,
    required String type,
    required bool paid,
    required List<({int id, DateTime expectedUpdatedAt, double? amountRub})>
    items,
  }) async {
    await _apiClient.patch(
      '/client/sp-v2/customers/$customerId/payment',
      data: {
        'purchaseId': purchaseId,
        'type': type,
        'paid': paid,
        'items': items
            .map(
              (item) => {
                'id': item.id,
                'expectedUpdatedAt': item.expectedUpdatedAt
                    .toUtc()
                    .toIso8601String(),
                if (item.amountRub != null)
                  'amountRub': double.parse(item.amountRub!.toStringAsFixed(2)),
              },
            )
            .toList(growable: false),
      },
    );
  }

  Future<String?> uploadMedia({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    String type = 'sp-v2',
  }) async {
    final response = await _apiClient.post(
      '/media/upload',
      data: FormData.fromMap({
        'type': type,
        'file': MultipartFile.fromBytes(
          bytes,
          filename: fileName,
          contentType:
              _mediaTypeForMimeType(mimeType) ??
              _mediaTypeForFileName(fileName),
        ),
      }),
    );
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return data['url'] as String?;
    }
    return null;
  }
}
