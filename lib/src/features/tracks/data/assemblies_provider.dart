import '../../../core/services/analytics_service.dart';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/services/demo_mode_provider.dart';

const trackWarehouseArrivalCooldownCode = 'TRACK_WAREHOUSE_ARRIVAL_COOLDOWN';
const packagingRemovalTargetsUnsupportedCode =
    'PACKAGING_REMOVAL_TARGETS_UNSUPPORTED';

class AssemblyCreateResult {
  const AssemblyCreateResult._({
    this.assembly,
    this.assemblies = const [],
    this.errorCode,
    this.message,
  });

  final List<Assembly> assemblies;

  final Assembly? assembly;
  final String? errorCode;
  final String? message;

  bool get isSuccess => assembly != null;

  factory AssemblyCreateResult.success(
    Assembly assembly, {
    List<Assembly>? assemblies,
  }) => AssemblyCreateResult._(
    assembly: assembly,
    assemblies: List.unmodifiable(assemblies ?? [assembly]),
  );

  factory AssemblyCreateResult.failure({String? errorCode, String? message}) =>
      AssemblyCreateResult._(errorCode: errorCode, message: message);

  factory AssemblyCreateResult.fromErrorData(dynamic data) {
    if (data is! Map) return AssemblyCreateResult.failure();
    final error = data['error']?.toString().trim();
    final code = data['code']?.toString().trim();
    final structuredMessage = data['message']?.toString().trim();
    final message = structuredMessage?.isNotEmpty == true
        ? structuredMessage
        : (error?.isNotEmpty == true ? error : null);
    return AssemblyCreateResult.failure(
      errorCode: code?.isNotEmpty == true ? code : null,
      message: message,
    );
  }
}

/// Модель сборки
class Assembly {
  final int id;
  final String number;
  final String? name;
  final String status;
  final String statusName;
  final String? statusColor;
  final String? clientCode;
  final String? clientName;
  final bool hasInsurance;
  final double? insuranceAmount;
  final String? tariffName;
  final double tariffCost;
  final List<String> packagingNames;
  final double packagingCost; // Сумма стоимости упаковок
  final int trackCount;
  final List<AssemblyTrack> tracks;
  final String? scalePhotoUrl;
  final String? comment;
  final String? goodsDescription;
  final String?
  deliveryMethod; // Способ доставки: self_pickup или transport_company
  final String? recipientName; // Имя получателя (для ТК)
  final String? recipientPhone; // Телефон получателя (для ТК)
  final String? recipientCity; // Город получателя (для ТК)
  final String? transportCompanyName; // Название транспортной компании
  final bool hasFragileGoods;
  final String placePreference;
  final String packagingRemoval;
  final String? packagingRemovalTarget;
  final bool supportsPackagingRemovalTargets;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Assembly({
    required this.id,
    required this.number,
    this.name,
    required this.status,
    required this.statusName,
    this.statusColor,
    this.clientCode,
    this.clientName,
    this.hasInsurance = false,
    this.insuranceAmount,
    this.tariffName,
    this.tariffCost = 0,
    this.packagingNames = const [],
    this.packagingCost = 0,
    this.trackCount = 0,
    this.tracks = const [],
    this.scalePhotoUrl,
    this.comment,
    this.goodsDescription,
    this.deliveryMethod,
    this.recipientName,
    this.recipientPhone,
    this.recipientCity,
    this.transportCompanyName,
    this.hasFragileGoods = false,
    this.placePreference = 'unspecified',
    this.packagingRemoval = 'none',
    this.packagingRemovalTarget,
    this.supportsPackagingRemovalTargets = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Assembly.fromJson(Map<String, dynamic> json) {
    // Парсим треки
    final tracksList = json['tracks'] as List<dynamic>? ?? [];
    final tracks = tracksList
        .map((t) => AssemblyTrack.fromJson(t as Map<String, dynamic>))
        .toList();

    // Парсим имена упаковки
    final packagingNames =
        (json['packagingNames'] as List<dynamic>?)
            ?.map((p) => p.toString())
            .toList() ??
        [];

    return Assembly(
      id: int.tryParse(json['id'].toString()) ?? 0,
      number: json['number'] as String? ?? '',
      name: json['name'] as String?,
      status: json['status'] as String? ?? '',
      statusName:
          json['statusName'] as String? ?? json['status'] as String? ?? '',
      statusColor: json['statusColor'] as String?,
      clientCode: json['clientCode'] as String?,
      clientName: json['clientName'] as String?,
      hasInsurance: json['hasInsurance'] as bool? ?? false,
      insuranceAmount: json['insuranceAmount'] != null
          ? double.tryParse(json['insuranceAmount'].toString())
          : null,
      tariffName: json['tariffName'] as String?,
      tariffCost: json['tariffCost'] != null
          ? double.tryParse(json['tariffCost'].toString()) ?? 0
          : 0,
      packagingNames: packagingNames,
      packagingCost: json['packagingCost'] != null
          ? double.tryParse(json['packagingCost'].toString()) ?? 0
          : 0,
      trackCount: json['trackCount'] as int? ?? tracks.length,
      tracks: tracks,
      scalePhotoUrl: json['scalePhotoUrl'] as String?,
      comment: json['comment'] as String?,
      goodsDescription: json['goodsDescription'] as String?,
      deliveryMethod: json['deliveryMethod'] as String?,
      recipientName: json['recipientName'] as String?,
      recipientPhone: json['recipientPhone'] as String?,
      recipientCity: json['recipientCity'] as String?,
      transportCompanyName: json['transportCompanyName'] as String?,
      hasFragileGoods:
          json['hasFragileGoods'] == true || json['hasFragileGoods'] == 'true',
      placePreference: json['placePreference']?.toString() ?? 'unspecified',
      packagingRemoval: json['packagingRemoval']?.toString() ?? 'none',
      packagingRemovalTarget: json['packagingRemovalTarget']?.toString(),
      supportsPackagingRemovalTargets:
          json['supportsPackagingRemovalTargets'] == true,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// Модель трека в сборке
class AssemblyTrack {
  final int id;
  final String trackNumber;
  final String? productName;
  final int quantity;
  final String? imageUrl;

  const AssemblyTrack({
    required this.id,
    required this.trackNumber,
    this.productName,
    this.quantity = 1,
    this.imageUrl,
  });

  factory AssemblyTrack.fromJson(Map<String, dynamic> json) {
    return AssemblyTrack(
      id: int.tryParse(json['id'].toString()) ?? 0,
      trackNumber: json['trackNumber'] as String? ?? '',
      productName: json['productName'] as String?,
      quantity: json['quantity'] as int? ?? 1,
      imageUrl: json['imageUrl'] as String?,
    );
  }
}

/// Провайдер для получения списка сборок по коду клиента
final assembliesListProvider = FutureProvider.family<List<Assembly>, String>((
  ref,
  clientCode,
) async {
  if (ref.watch(demoModeProvider)) return [];
  final apiClient = ref.read(apiClientProvider);

  try {
    final response = await apiClient.get(
      '/assemblies',
      queryParameters: {'clientCode': clientCode, 'take': 100},
    );

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data as Map<String, dynamic>;
      final assembliesJson = data['assemblies'] as List<dynamic>? ?? [];

      return assembliesJson
          .map((json) => Assembly.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    return [];
  } on DioException catch (e) {
    debugPrint('Error loading assemblies: $e');
    return [];
  }
});

/// Провайдер для дайджеста сборок - последние 5 сборок
final assembliesDigestProvider = FutureProvider.family<List<Assembly>, String>((
  ref,
  clientCode,
) async {
  if (ref.watch(demoModeProvider)) return [];
  final apiClient = ref.read(apiClientProvider);

  try {
    final response = await apiClient.get(
      '/assemblies',
      queryParameters: {'clientCode': clientCode, 'take': 5},
    );

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data as Map<String, dynamic>;
      final assembliesJson = data['assemblies'] as List<dynamic>? ?? [];

      return assembliesJson
          .map((json) => Assembly.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    return [];
  } on DioException catch (e) {
    debugPrint('Error loading assemblies digest: $e');
    return [];
  }
});

/// Провайдер для общего количества сборок
final assembliesCountProvider = FutureProvider.family<int, String>((
  ref,
  clientCode,
) async {
  if (ref.watch(demoModeProvider)) return 0;
  final apiClient = ref.read(apiClientProvider);

  try {
    final response = await apiClient.get(
      '/assemblies',
      queryParameters: {'clientCode': clientCode, 'take': 1},
    );

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data as Map<String, dynamic>;
      final pagination = data['pagination'] as Map<String, dynamic>?;
      return pagination?['total'] as int? ?? 0;
    }
    return 0;
  } on DioException catch (e) {
    debugPrint('Error loading assemblies count: $e');
    return 0;
  }
});

// ==================== API Mutations ====================

/// Сервис для API операций со сборками
class AssembliesApiService {
  final Ref _ref;

  AssembliesApiService(this._ref);

  final Map<String, String> _pendingAssemblyRequests = {};

  ApiClient get _apiClient => _ref.read(apiClientProvider);

  /// Создать сборку (статус = new)
  Future<AssemblyCreateResult> createAssembly({
    required int clientId,
    int? clientCodeId,
    String? clientCode,
    String? name,
    int? tariffId,
    List<int>? packagingTypeIds,
    bool hasFragileGoods = false,
    String placePreference = 'unspecified',
    String packagingRemoval = 'none',
    String? packagingRemovalTarget,
    bool supportsPackagingRemovalTargets = false,
    bool hasInsurance = false,
    double? insuranceAmount,
    String? goodsDescription,
    List<int>? trackIds,
    bool cancelPendingQuestions = false,
  }) async {
    return AnalyticsService.traceOperation(
      WorkflowAction.assemblyCreate,
      () async {
        try {
          final payload = <String, dynamic>{
            'clientId': clientId,
            if (clientCodeId != null)
              'clientCodeId': clientCodeId
            else if (clientCode != null)
              'clientCode': clientCode,
            if (name != null) 'name': name,
            if (tariffId != null) 'tariffId': tariffId,
            if (packagingTypeIds != null && packagingTypeIds.isNotEmpty)
              'packagingTypeIds': packagingTypeIds,
            'hasFragileGoods': hasFragileGoods,
            'placePreference': placePreference,
            'packagingRemoval': 'none',
            if (supportsPackagingRemovalTargets) 'packagingRemovalTarget': null,
            'hasInsurance': hasInsurance,
            if (insuranceAmount != null) 'insuranceAmount': insuranceAmount,
            if (goodsDescription != null && goodsDescription.trim().isNotEmpty)
              'goodsDescription': goodsDescription.trim(),
            if (trackIds != null && trackIds.isNotEmpty) 'trackIds': trackIds,
            if (cancelPendingQuestions) 'cancelPendingQuestions': true,
          };
          // Selection order can change after refreshing the list; it does not
          // change the batch and must retain the same retry key.
          final fingerprint = jsonEncode({
            ...payload,
            if (trackIds != null && trackIds.isNotEmpty)
              'trackIds': [...trackIds]..sort(),
            if (packagingTypeIds != null && packagingTypeIds.isNotEmpty)
              'packagingTypeIds': [...packagingTypeIds]..sort(),
          });
          final requestKey = _pendingAssemblyRequests.putIfAbsent(
            fingerprint,
            () => const Uuid().v4(),
          );
          final response = await _apiClient.post(
            '/assemblies',
            data: {
              ...payload,
              'assemblyBatchProtocol': 1,
              'assemblyRequestId': requestKey,
            },
          );

          if (response.statusCode == 200 || response.statusCode == 201) {
            final data = response.data as Map<String, dynamic>;
            final children = data['assemblies'] is List
                ? (data['assemblies'] as List)
                      .map(
                        (item) => Assembly.fromJson(
                          Map<String, dynamic>.from(item as Map),
                        ),
                      )
                      .toList()
                : [Assembly.fromJson(data)];
            if (children.isEmpty) return AssemblyCreateResult.failure();
            _pendingAssemblyRequests.remove(fingerprint);
            return AssemblyCreateResult.success(
              children.first,
              assemblies: children,
            );
          }
          return AssemblyCreateResult.failure();
        } on DioException catch (e) {
          debugPrint('Error creating assembly: $e');
          return AssemblyCreateResult.fromErrorData(e.response?.data);
        }
      },
      outcome: (result) =>
          result.isSuccess ? WorkflowStage.succeeded : WorkflowStage.failed,
    );
  }

  /// Добавить треки в сборку
  Future<bool> addTracksToAssembly({
    required int assemblyId,
    required List<int> trackIds,
  }) async {
    try {
      final response = await _apiClient.post(
        '/assemblies/$assemblyId/tracks',
        data: {'trackIds': trackIds},
      );
      return response.statusCode == 200;
    } on DioException catch (e) {
      debugPrint('Error adding tracks to assembly: $e');
      return false;
    }
  }

  /// Удалить треки из сборки
  Future<bool> removeTracksFromAssembly({
    required int assemblyId,
    required List<int> trackIds,
  }) async {
    try {
      final response = await _apiClient.delete(
        '/assemblies/$assemblyId/tracks',
        data: {'trackIds': trackIds},
      );
      return response.statusCode == 200;
    } on DioException catch (e) {
      debugPrint('Error removing tracks from assembly: $e');
      return false;
    }
  }

  /// Добавить комментарий к сборке
  Future<bool> addAssemblyComment({
    required int assemblyId,
    required String comment,
  }) async {
    try {
      final response = await _apiClient.patch(
        '/assemblies/$assemblyId',
        data: {'comment': comment},
      );
      return response.statusCode == 200;
    } on DioException catch (e) {
      debugPrint('Error adding assembly comment: $e');
      return false;
    }
  }

  /// Обновить страховку сборки
  Future<bool> updateAssemblyInsurance({
    required int assemblyId,
    required bool hasInsurance,
    double? insuranceAmount,
  }) async {
    try {
      final response = await _apiClient.patch(
        '/assemblies/$assemblyId',
        data: {
          'hasInsurance': hasInsurance,
          if (insuranceAmount != null) 'insuranceAmount': insuranceAmount,
        },
      );
      return response.statusCode == 200;
    } on DioException catch (e) {
      debugPrint('Error updating assembly insurance: $e');
      return false;
    }
  }

  /// Обновить способ доставки сборки
  Future<bool> updateAssemblyDelivery({
    required int assemblyId,
    required String deliveryMethod,
    String? recipientName,
    String? recipientPhone,
    String? recipientCity,
    String? transportCompanyName,
  }) async {
    try {
      final response = await _apiClient.patch(
        '/assemblies/$assemblyId',
        data: {
          'deliveryMethod': deliveryMethod,
          if (recipientName != null) 'recipientName': recipientName,
          if (recipientPhone != null) 'recipientPhone': recipientPhone,
          if (recipientCity != null) 'recipientCity': recipientCity,
          if (transportCompanyName != null)
            'transportCompanyName': transportCompanyName,
        },
      );
      return response.statusCode == 200;
    } on DioException catch (e) {
      debugPrint('Error updating assembly delivery: $e');
      return false;
    }
  }

  /// Подтвердить фактическое получение сборки клиентом.
  Future<bool> confirmAssemblyReceipt(int assemblyId) async {
    try {
      final response = await _apiClient.post(
        '/client/assemblies/$assemblyId/confirm-receipt',
      );
      return response.statusCode == 200;
    } on DioException catch (e) {
      debugPrint('Error confirming assembly receipt: $e');
      debugPrint('Response data: ${e.response?.data}');
      return false;
    }
  }
}

/// Провайдер для API сервиса сборок
final assembliesApiServiceProvider = Provider<AssembliesApiService>((ref) {
  return AssembliesApiService(ref);
});

/// Модель типа упаковки

/// Модель типа упаковки
class PackagingType {
  final int id;
  final String name;
  final String? nameRu;
  final String? nameZh;
  final String kind;
  final bool suitableForFragileGoods;
  final String unitLabel;
  final double unitStep;
  final double baseCost;

  const PackagingType({
    required this.id,
    required this.name,
    this.nameRu,
    this.nameZh,
    this.kind = 'primary',
    this.suitableForFragileGoods = false,
    this.unitLabel = 'шт.',
    this.unitStep = 1,
    this.baseCost = 0,
  });

  factory PackagingType.fromJson(Map<String, dynamic> json) {
    return PackagingType(
      id: int.tryParse(json['id'].toString()) ?? 0,
      name: json['name'] as String? ?? json['nameRu'] as String? ?? '',
      nameRu: json['nameRu'] as String?,
      nameZh: json['nameZh'] as String?,
      kind: json['kind'] as String? ?? 'primary',
      suitableForFragileGoods:
          json['suitableForFragileGoods'] as bool? ?? false,
      unitLabel: json['unitLabel']?.toString() ?? 'шт.',
      unitStep: json['unitStep'] != null
          ? double.tryParse(json['unitStep'].toString()) ?? 1
          : 1,
      baseCost: json['baseCost'] != null
          ? double.tryParse(json['baseCost'].toString()) ?? 0
          : 0,
    );
  }

  bool get isPrimary => kind != 'addon';
  bool get isAddon => kind == 'addon';
  String get displayName => nameRu ?? name;
  String localizedName(bool chinese) =>
      chinese && nameZh?.trim().isNotEmpty == true ? nameZh! : displayName;
}

/// Провайдер для тарифов (с поддержкой clientId)
final tariffsProvider = FutureProvider<List<Tariff>>((ref) async {
  final apiClient = ref.read(apiClientProvider);

  try {
    final response = await apiClient.get(
      '/tariffs',
      queryParameters: {'activeOnly': 'true'},
    );

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data as Map<String, dynamic>;
      final tariffList =
          data['tariffs'] as List<dynamic>? ??
          data['data'] as List<dynamic>? ??
          [];

      return tariffList
          .map((json) => Tariff.fromJson(json as Map<String, dynamic>))
          .where((t) => t.isActive)
          .toList();
    }
    return [];
  } on DioException catch (e) {
    debugPrint('Error loading tariffs: $e');
    rethrow;
  }
});

/// Провайдер для типов упаковки
final packagingTypesProvider = FutureProvider<List<PackagingType>>((ref) async {
  final apiClient = ref.read(apiClientProvider);

  try {
    final response = await apiClient.get('/packagings');

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data as Map<String, dynamic>;
      final packagingList =
          data['packagings'] as List<dynamic>? ??
          data['data'] as List<dynamic>? ??
          [];

      return packagingList
          .map((json) => PackagingType.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    return [];
  } on DioException catch (e) {
    debugPrint('Error loading packaging types: $e');
    rethrow;
  }
});

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

/// Модель тарифа
class Tariff {
  final int id;
  final String name;
  final String? nameZh;
  final double baseCost;
  final double? packagingRemovalTransportPrice;
  final double? packagingRemovalAllPrice;
  final bool supportsPackagingRemovalTargets;
  final bool isActive;
  final bool isCurrentlyActive;
  final DateTime? validFrom;
  final DateTime? validTo;
  final bool requiresProductInfo;
  final bool requiresCompleteProductInfo;

  const Tariff({
    required this.id,
    required this.name,
    this.nameZh,
    required this.baseCost,
    this.packagingRemovalTransportPrice,
    this.packagingRemovalAllPrice,
    this.supportsPackagingRemovalTargets = false,
    this.isActive = true,
    this.isCurrentlyActive = true,
    this.validFrom,
    this.validTo,
    this.requiresProductInfo = false,
    this.requiresCompleteProductInfo = false,
  });

  String localizedName(bool chinese) =>
      chinese && nameZh?.trim().isNotEmpty == true ? nameZh! : name;

  factory Tariff.fromJson(Map<String, dynamic> json) {
    return Tariff(
      id: int.tryParse(json['id'].toString()) ?? 0,
      name: json['name'] as String? ?? '',
      nameZh: json['nameZh'] as String?,
      baseCost: json['baseCost'] != null
          ? double.tryParse(json['baseCost'].toString()) ?? 0
          : 0,
      packagingRemovalTransportPrice:
          json['packagingRemovalTransportPrice'] != null
          ? double.tryParse(json['packagingRemovalTransportPrice'].toString())
          : null,
      packagingRemovalAllPrice: json['packagingRemovalAllPrice'] != null
          ? double.tryParse(json['packagingRemovalAllPrice'].toString())
          : null,
      supportsPackagingRemovalTargets:
          json['supportsPackagingRemovalTargets'] == true,
      isActive: json['isActive'] as bool? ?? true,
      isCurrentlyActive:
          json['isCurrentlyActive'] as bool? ??
          json['isActive'] as bool? ??
          true,
      validFrom: _parseDate(json['validFrom']),
      validTo: _parseDate(json['validTo']),
      requiresProductInfo: json['requiresProductInfo'] as bool? ?? false,
      requiresCompleteProductInfo: json['requiresCompleteProductInfo'] == true,
    );
  }
}
