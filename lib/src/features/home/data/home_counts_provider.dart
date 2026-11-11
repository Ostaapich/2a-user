import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/stale_data_cache.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/demo_mode_provider.dart';

// Home filters are separate from client switcher totals. The API counts all
// matching records, independently of the single record requested for the page.
final homeTracksCountProvider = FutureProvider.family<int, String>((
  ref,
  code,
) async {
  if (ref.watch(demoModeProvider)) return 0;
  final query = {'clientCode': code, 'take': 1, 'statuses': 'in_warehouse'};
  final data = await StaleDataCache.getJson(
    ref: ref,
    cacheKey: StaleDataCache.buildKey('home_tracks_count', query),
    label: 'количество треков на складе',
    request: () =>
        ref.read(apiClientProvider).get('/tracks', queryParameters: query),
  );
  return data['total'] as int? ?? 0;
});

// Count pending tracks on the server, never from the loaded digest page.
final homePendingTracksCountProvider = FutureProvider.family<int, String>((
  ref,
  code,
) async {
  if (ref.watch(demoModeProvider)) return 0;
  final query = {'clientCode': code, 'take': 1, 'statuses': 'pending'};
  final data = await StaleDataCache.getJson(
    ref: ref,
    cacheKey: StaleDataCache.buildKey('home_pending_tracks_count', query),
    label: 'количество треков в ожидании',
    request: () =>
        ref.read(apiClientProvider).get('/tracks', queryParameters: query),
  );
  return data['total'] as int? ?? 0;
});

final homeAssembliesCountProvider = FutureProvider.family<int, String>((
  ref,
  code,
) async {
  if (ref.watch(demoModeProvider)) return 0;
  final query = {
    'clientCode': code,
    'take': 1,
    'statuses': 'new,in_warehouse,in_assembly,shipped',
  };
  final data = await StaleDataCache.getJson(
    ref: ref,
    cacheKey: StaleDataCache.buildKey('home_assemblies_count', query),
    label: 'количество активных сборок',
    request: () =>
        ref.read(apiClientProvider).get('/assemblies', queryParameters: query),
  );
  return (data['pagination'] as Map<String, dynamic>?)?['total'] as int? ?? 0;
});
