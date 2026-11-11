import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/data/auth_provider.dart';
import '../domain/news_item.dart';

/// Провайдер для получения agentId из данных клиента
final clientAgentIdProvider = Provider<int?>((ref) {
  final authState = ref.watch(authProvider);
  final clientData = authState.clientData;
  if (clientData == null) return null;

  final agent = clientData['agent'] as Map<String, dynamic>?;
  return agent?['id'] as int?;
});

/// Провайдер для получения списка новостей
final newsListProvider = FutureProvider<List<NewsItem>>((ref) async {
  final apiClient = ref.read(apiClientProvider);
  final agentId = ref.watch(clientAgentIdProvider);

  if (agentId == null) {
    debugPrint('News: agentId is null, returning empty list');
    return [];
  }

  try {
    final response = await apiClient.get(
      '/news',
      queryParameters: {
        'agentId': agentId,
        'status': 'published', // Показываем только опубликованные
        'take': 50,
      },
    );

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data as Map<String, dynamic>;
      final newsJson = data['data'] as List<dynamic>? ?? [];

      return newsJson
          .map((json) => NewsItem.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    return [];
  } on DioException catch (e) {
    debugPrint('Error loading news: $e');
    rethrow;
  }
});

/// Провайдер для получения одной новости по ID/slug.
///
/// PU-M9: сначала пробуем прямой fetch GET `/news/:id`. Раньше всегда
/// тянули весь список и искали в нём — для новости вне последних 50
/// (или по deep link/push до загрузки списка) detail screen открывался
/// пустым. Если прямой fetch упал — fallback на поиск в списке (старое
/// поведение), чтобы не ломать UX в офлайне.
final newsItemProvider = FutureProvider.family<NewsItem?, String>((
  ref,
  idOrSlug,
) async {
  final apiClient = ref.read(apiClientProvider);

  // 1) Прямой fetch по id.
  final id = int.tryParse(idOrSlug);
  if (id != null) {
    try {
      final response = await apiClient.get('/news/$id');
      if (response.statusCode == 200 && response.data != null) {
        final body = response.data as Map<String, dynamic>;
        final raw = body['data'] as Map<String, dynamic>?;
        if (raw != null) {
          return NewsItem.fromJson(raw);
        }
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  // 2) Fallback: ищем в уже загруженном списке.
  final newsList = await ref.watch(newsListProvider.future);
  return newsList.cast<NewsItem?>().firstWhere(
    (n) => n?.slug == idOrSlug,
    orElse: () => null,
  );
});
