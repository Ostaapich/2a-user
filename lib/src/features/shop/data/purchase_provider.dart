import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/purchase_list.dart';

/// Active draft purchase list (cart)
final activePurchaseListProvider = FutureProvider<PurchaseList?>((ref) async {
  final apiClient = ref.read(apiClientProvider);

  try {
    final response = await apiClient.get(
      '/shop/purchase-lists',
      queryParameters: {'status': 'draft'},
    );

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data as Map<String, dynamic>;
      final listsJson = data['lists'] as List<dynamic>? ?? [];
      if (listsJson.isNotEmpty) {
        return PurchaseList.fromJson(listsJson.first as Map<String, dynamic>);
      }
    }
    return null;
  } on DioException catch (e) {
    debugPrint('Error loading active purchase list: $e');
    rethrow;
  }
});

/// All purchase lists for history
final purchaseListsProvider = FutureProvider<List<PurchaseList>>((ref) async {
  final apiClient = ref.read(apiClientProvider);

  try {
    final response = await apiClient.get('/shop/purchase-lists');

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data as Map<String, dynamic>;
      final listsJson = data['lists'] as List<dynamic>? ?? [];
      return listsJson
          .map((json) => PurchaseList.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    return [];
  } on DioException catch (e) {
    debugPrint('Error loading purchase lists: $e');
    rethrow;
  }
});

/// Detail of a specific purchase list
final purchaseListDetailProvider = FutureProvider.family<PurchaseList?, int>((
  ref,
  id,
) async {
  final apiClient = ref.read(apiClientProvider);

  try {
    final response = await apiClient.get('/shop/purchase-lists/$id');

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data as Map<String, dynamic>;
      final listJson = data['list'] as Map<String, dynamic>?;
      if (listJson != null) {
        return PurchaseList.fromJson(listJson);
      }
    }
    return null;
  } on DioException catch (e) {
    debugPrint('Error loading purchase list detail: $e');
    if (e.response?.statusCode == 404) return null;
    rethrow;
  }
});

/// Cart item count (for badge)
final cartItemCountProvider = Provider<int>((ref) {
  final listAsync = ref.watch(activePurchaseListProvider);
  return listAsync.value?.totalItems ?? 0;
});
