import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/stale_data_cache.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/demo_mode_provider.dart';
import '../domain/invoice_item.dart';
import '../domain/early_payment_benefit.dart';

/// Модель статуса счёта
class InvoiceStatus {
  final String id;
  final String code;
  final String nameRu;
  final String? color;
  final int sortOrder;

  const InvoiceStatus({
    required this.id,
    required this.code,
    required this.nameRu,
    this.color,
    this.sortOrder = 0,
  });

  factory InvoiceStatus.fromJson(Map<String, dynamic> json) {
    return InvoiceStatus(
      id: json['id']?.toString() ?? '',
      code: json['code'] as String? ?? '',
      nameRu: json['nameRu'] as String? ?? json['code'] as String? ?? '',
      color: json['color'] as String?,
      sortOrder: json['sortOrder'] as int? ?? 0,
    );
  }
}

/// Провайдер для статусов счетов из БД
final invoiceStatusesProvider = FutureProvider<List<InvoiceStatus>>((
  ref,
) async {
  if (ref.watch(demoModeProvider)) return [];
  final apiClient = ref.read(apiClientProvider);

  try {
    const queryParams = {'type': 'invoice'};
    final data = await StaleDataCache.getJson(
      ref: ref,
      cacheKey: StaleDataCache.buildKey('invoice_statuses', queryParams),
      label: 'статусы счетов',
      request: () => apiClient.get('/statuses', queryParameters: queryParams),
    );

    // API возвращает 'data', а не 'statuses'
    final statusesJson = data['data'] as List<dynamic>? ?? [];

    final statuses = statusesJson
        .map((json) => InvoiceStatus.fromJson(json as Map<String, dynamic>))
        .toList();

    debugPrint('Parsed invoice statuses: ${statuses.length}');
    return statuses;
  } catch (e) {
    debugPrint('Error loading invoice statuses: $e');
    return [];
  }
});

/// Фиксирует нажатие клиентом кнопки "Оплатить".
///
/// Backend переводит счёт из `unpaid`/`pending` в `processing`, чтобы кнопка
/// оплаты сразу исчезала и бухгалтер видел следующий ожидаемый статус.
Future<void> requestInvoicePayment(
  ApiClient apiClient,
  String invoiceId,
) async {
  await apiClient.post('/client/invoices/$invoiceId/request-payment');
}

/// Выбирает одно из предложенных сервером преимуществ ранней оплаты.
///
/// Клиент передаёт только тип и ключ идемпотентности. Все суммы, доступность и
/// срок предложения остаются серверными данными.
Future<EarlyPaymentBenefit> selectEarlyPaymentBenefit(
  ApiClient apiClient, {
  required String invoiceId,
  required EarlyPaymentBenefitType benefitType,
  required String idempotencyKey,
}) async {
  final response = await apiClient.post(
    '/client/invoices/$invoiceId/early-payment-benefit',
    data: {
      'benefitType': benefitType.serverValue,
      'idempotencyKey': idempotencyKey,
    },
  );
  final responseData = response.data;
  if (responseData is! Map) {
    throw const FormatException('Invalid early-payment benefit response');
  }
  final nestedData = responseData['data'];
  final benefitJson =
      responseData['earlyPaymentBenefit'] ??
      (nestedData is Map ? nestedData['earlyPaymentBenefit'] : null);
  if (benefitJson is! Map) {
    throw const FormatException('Missing early-payment benefit response');
  }
  return EarlyPaymentBenefit.fromJson(Map<String, dynamic>.from(benefitJson));
}

/// Провайдер для получения списка счетов
final invoicesListProvider = FutureProvider.family<List<InvoiceItem>, String>((
  ref,
  clientCode,
) async {
  if (ref.watch(demoModeProvider)) return const <InvoiceItem>[];
  final apiClient = ref.read(apiClientProvider);

  try {
    final queryParams = {'clientCode': clientCode, 'take': 100};
    final data = await StaleDataCache.getJson(
      ref: ref,
      cacheKey: StaleDataCache.buildKey('invoices_list', queryParams),
      label: 'счета',
      request: () => apiClient.get('/invoices', queryParameters: queryParams),
    );

    final invoicesJson = data['data'] as List<dynamic>? ?? [];

    return invoicesJson
        .map((json) => InvoiceItem.fromJson(json as Map<String, dynamic>))
        .toList();
  } catch (e) {
    debugPrint('Error loading invoices: $e');
    rethrow;
  }
});

typedef InvoiceDirectoryQuery = ({
  String clientCode,
  String search,
  String? status,
  int pages,
});
typedef InvoicePageQuery = ({
  String clientCode,
  String search,
  String? status,
  int page,
});

class InvoiceDirectoryPage {
  final List<InvoiceItem> items;
  final int total;
  final bool hasMore;
  const InvoiceDirectoryPage({
    required this.items,
    required this.total,
    required this.hasMore,
  });
}

Future<InvoiceDirectoryPage> fetchInvoiceDirectoryPage(
  ApiClient api,
  InvoicePageQuery query,
) async {
  const size = 50;
  final response = await api.get(
    '/invoices',
    queryParameters: {
      'clientCode': query.clientCode,
      'skip': (query.page - 1) * size,
      'take': size,
      if (query.search.trim().isNotEmpty) 'search': query.search.trim(),
      if (query.status != null) 'status': query.status,
    },
  );
  if (response.statusCode != 200 || response.data is! Map) {
    throw const FormatException('Invalid invoice directory response');
  }
  final body = response.data as Map;
  if (body['data'] is! List) {
    throw const FormatException('Missing invoice page');
  }
  final items = (body['data'] as List)
      .map(
        (value) =>
            InvoiceItem.fromJson(Map<String, dynamic>.from(value as Map)),
      )
      .toList(growable: false);
  final total = (body['total'] as num?)?.toInt() ?? items.length;
  final hasMore = body['hasMore'] == true;
  if (hasMore && items.isEmpty) {
    throw const FormatException('Invoice pagination did not advance');
  }
  return InvoiceDirectoryPage(items: items, total: total, hasMore: hasMore);
}

final invoiceDirectoryPageProvider = FutureProvider.autoDispose
    .family<InvoiceDirectoryPage, InvoicePageQuery>((ref, query) async {
      if (ref.watch(demoModeProvider)) {
        return const InvoiceDirectoryPage(items: [], total: 0, hasMore: false);
      }
      return fetchInvoiceDirectoryPage(ref.read(apiClientProvider), query);
    });

/// Each page has its own provider: adding a page retains the earlier pages,
/// while search and status are always applied by the server across all history.
final invoiceDirectoryProvider = FutureProvider.autoDispose
    .family<InvoiceDirectoryPage, InvoiceDirectoryQuery>((ref, query) async {
      final items = <String, InvoiceItem>{};
      var result = const InvoiceDirectoryPage(
        items: [],
        total: 0,
        hasMore: false,
      );
      for (var page = 1; page <= query.pages; page++) {
        result = await ref.watch(
          invoiceDirectoryPageProvider((
            clientCode: query.clientCode,
            search: query.search,
            status: query.status,
            page: page,
          )).future,
        );
        for (final item in result.items) {
          items[item.id] = item;
        }
        if (!result.hasMore) break;
      }
      return InvoiceDirectoryPage(
        items: items.values.toList(growable: false),
        total: result.total,
        hasMore: result.hasMore,
      );
    });

/// Провайдер для дайджеста счетов (последние 10, сортировка по updatedAt)
final invoicesDigestProvider = FutureProvider.family<List<InvoiceItem>, String>(
  (ref, clientCode) async {
    if (ref.watch(demoModeProvider)) return const <InvoiceItem>[];
    final apiClient = ref.read(apiClientProvider);

    try {
      final queryParams = {
        'clientCode': clientCode,
        'take': 10,
        'sortBy': 'updatedAt',
      };
      final data = await StaleDataCache.getJson(
        ref: ref,
        cacheKey: StaleDataCache.buildKey('invoices_digest', queryParams),
        label: 'последние счета',
        request: () => apiClient.get('/invoices', queryParameters: queryParams),
      );

      final invoicesJson = data['data'] as List<dynamic>? ?? [];

      return invoicesJson
          .map((json) => InvoiceItem.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error loading invoices digest: $e');
      rethrow;
    }
  },
);

/// PU-H9: вытащить ВСЕ счета клиента батчами для экспорта.
///
/// `invoicesListProvider` берёт только первые 100, поэтому при
/// >100 счетах Excel-экспорт был неполным. Здесь делаем batch fetch по
/// `skip`/`take` до `hasMore == false`. Не Provider — обычная функция,
/// чтобы не дребезжать кешем (вызывается одноразово при кнопке).
///
/// Принимает `ApiClient` напрямую (а не `Ref`), чтобы вызывать одинаково
/// и из ConsumerWidget (`ref.read(apiClientProvider)`), и из обычного
/// контроллера, и из теста с моком.
Future<List<InvoiceItem>> fetchAllInvoicesForExport(
  ApiClient apiClient,
  String clientCode, {
  int batchSize = 200,
  int safetyLimit = 50000, // ~250 батчей × 200 — крайний предохранитель
}) async {
  final all = <InvoiceItem>[];
  var skip = 0;

  while (true) {
    if (all.length >= safetyLimit) {
      debugPrint(
        'fetchAllInvoicesForExport: hit safetyLimit=$safetyLimit, stop',
      );
      throw const FormatException(
        'Invoice export safety limit reached before completion',
      );
    }
    try {
      final response = await apiClient.get(
        '/invoices',
        queryParameters: {
          'clientCode': clientCode,
          'skip': skip,
          'take': batchSize,
        },
      );
      if (response.statusCode != 200 || response.data is! Map) {
        throw const FormatException('Incomplete invoice export response');
      }

      final data = response.data as Map<String, dynamic>;
      if (data['data'] is! List) {
        throw const FormatException('Missing invoice export page');
      }
      final invoicesJson = data['data'] as List<dynamic>;
      final batch = invoicesJson
          .map((json) => InvoiceItem.fromJson(json as Map<String, dynamic>))
          .toList();
      all.addAll(batch);

      final hasMore = data['hasMore'] as bool? ?? (batch.length == batchSize);
      if (!hasMore) break;
      if (batch.isEmpty) {
        throw const FormatException('Invoice export did not advance');
      }
      skip += batchSize;
    } on DioException catch (e) {
      debugPrint('fetchAllInvoicesForExport error: $e');
      rethrow;
    }
  }
  return all;
}

/// Провайдер количества счетов для карточки на главном экране.
/// Считаются только неоплаченные счета (status=unpaid).
final invoicesCountProvider = FutureProvider.family<int, String>((
  ref,
  clientCode,
) async {
  if (ref.watch(demoModeProvider)) return 0;
  final apiClient = ref.read(apiClientProvider);

  try {
    final queryParams = {
      'clientCode': clientCode,
      'take': 1,
      'status': 'unpaid',
    };
    final data = await StaleDataCache.getJson(
      ref: ref,
      cacheKey: StaleDataCache.buildKey('invoices_count', queryParams),
      label: 'количество счетов',
      request: () => apiClient.get('/invoices', queryParameters: queryParams),
    );

    return data['total'] as int? ?? 0;
  } catch (e) {
    debugPrint('Error loading invoices count: $e');
    rethrow;
  }
});

/// Количество счетов, созданных за последние 7 дней.
final invoicesWeeklyCountProvider = FutureProvider.family<int, String>((
  ref,
  clientCode,
) async {
  final weekStart = DateTime.now().subtract(const Duration(days: 7));
  if (ref.watch(demoModeProvider)) return 0;
  final apiClient = ref.read(apiClientProvider);

  try {
    final queryParams = {
      'clientCode': clientCode,
      'take': 1,
      'dateFrom': weekStart.toUtc().toIso8601String(),
      'sortBy': 'createdAt',
    };
    final data = await StaleDataCache.getJson(
      ref: ref,
      cacheKey: StaleDataCache.buildKey('invoices_weekly_count', {
        'clientCode': clientCode,
        'dateFromDay': weekStart.toUtc().toIso8601String().substring(0, 10),
      }),
      label: 'счета за неделю',
      request: () => apiClient.get('/invoices', queryParameters: queryParams),
    );

    return data['total'] as int? ?? 0;
  } catch (e) {
    debugPrint('Error loading weekly invoices count: $e');
    rethrow;
  }
});

/// Провайдер для получения одного счёта по ID (для актуальных данных в чате)
final invoiceByIdProvider = FutureProvider.family<InvoiceItem?, String>((
  ref,
  id,
) async {
  if (ref.watch(demoModeProvider)) return null;
  final apiClient = ref.read(apiClientProvider);

  try {
    final response = await apiClient.get('/invoices/$id');

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data as Map<String, dynamic>;
      final invoiceJson = data['data'] as Map<String, dynamic>?;
      if (invoiceJson == null) return null;
      return InvoiceItem.fromJson(invoiceJson);
    }
    return null;
  } on DioException catch (e) {
    debugPrint('Error loading invoice by id: $e');
    return null;
  }
});

/// Payment TG username — cached after first load
String? _paymentTgUsername;

/// Provider that loads and caches payment TG config
final paymentTgUsernameProvider = FutureProvider<String?>((ref) async {
  if (_paymentTgUsername != null) return _paymentTgUsername;
  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/client/payment-tg-config');
    final data = res.data['data'] as Map<String, dynamic>?;
    if (data != null && data['enabled'] == true) {
      _paymentTgUsername = data['businessUsername'] as String?;
    }
  } catch (_) {}
  return _paymentTgUsername;
});
