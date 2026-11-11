import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogistic_shared/twoalogistic_shared.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/core/cache/stale_data_cache.dart';
import 'package:twoalogisticcabineuser/src/core/services/websocket_provider.dart';
import 'package:twoalogisticcabineuser/src/features/photos/data/photos_provider.dart';

class _GalleryApi extends ApiClient {
  final refreshQueries = <Map<String, dynamic>>[];
  bool refreshing = false;
  Completer<Response<dynamic>>? lastChunk;

  Response<T> page<T>(
    int skip,
    int take, {
    String marker = 'original',
    int total = 1015,
  }) => Response<T>(
    statusCode: 200,
    requestOptions: RequestOptions(path: '/photos'),
    data:
        {
              'total': total,
              'data': [
                for (var id = skip; id < skip + take && id < total; id++)
                  {
                    'id': id,
                    'url': '/uploads/$marker-$id.jpg',
                    'createdAt': '2026-11-10T00:00:00Z',
                  },
              ],
            }
            as T,
  );

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    final query = queryParameters!;
    final take = query['take'] as int;
    final skip = query['skip'] as int;
    if (take > 1000) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        response: Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 400,
        ),
      );
    }
    if (query['clientCode'] == 'CLIENT-B') {
      return page(skip, take, marker: 'client-b', total: 12);
    }
    if (refreshing && take > 12 || refreshing && skip >= 1000) {
      refreshQueries.add(Map<String, dynamic>.from(query));
      if (skip == 1000 && lastChunk != null) {
        return await lastChunk!.future as Response<T>;
      }
      return page(skip, take, marker: 'refreshed');
    }
    if (refreshing) {
      return page(skip, take, marker: 'manual-refresh', total: 12);
    }
    return page(skip, take);
  }
}

class _WebSocket extends WebSocketService {
  _WebSocket() : super(serverUrl: 'http://localhost');
  final events = StreamController<DeltaEvent>.broadcast();
  final reconnects = StreamController<void>.broadcast();
  @override
  Stream<DeltaEvent> get deltas => events.stream;
  @override
  Stream<void> get reconnected => reconnects.stream;
  @override
  void dispose() {
    events.close();
    reconnects.close();
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var i = 0; i < 300 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final replacement in ['none', 'manual refresh', 'account switch']) {
    test(
      'large gallery bounded refresh preserves range during $replacement',
      () async {
        final api = _GalleryApi();
        final ws = _WebSocket();
        final container = ProviderContainer(
          overrides: [
            apiClientProvider.overrideWithValue(api),
            staleDataCacheEnabledProvider.overrideWithValue(false),
            webSocketServiceProvider.overrideWithValue(ws),
          ],
        );
        addTearDown(ws.dispose);
        addTearDown(container.dispose);
        final provider = filteredPhotosProvider((
          clientCode: 'CLIENT-A',
          date: '2026-11-10',
          search: 'TRACK',
        ));
        final subscription = container.listen(provider, (_, _) {});
        addTearDown(subscription.close);
        final notifier = container.read(provider);
        await _waitUntil(() => notifier.state.photos.length == 12);
        for (var page = 1; page < 84; page++) {
          await notifier.loadMore();
        }
        expect(notifier.state.photos.length, 1008);
        api.refreshing = true;
        if (replacement != 'none') {
          api.lastChunk = Completer<Response<dynamic>>();
        }
        notifier.setRealtimeRefreshEnabled(true);
        await _waitUntil(() => api.refreshQueries.length == 2);
        if (replacement == 'none') {
          await _waitUntil(
            () => notifier.state.photos.first.url.contains('refreshed'),
          );
          expect(notifier.state.photos.length, 1008);
          expect(
            notifier.state.photos.last.url,
            contains('refreshed-1007.jpg'),
          );
          expect(notifier.state.total, 1015);
          expect(notifier.state.hasMore, isTrue);
        } else if (replacement == 'manual refresh') {
          await notifier.loadInitial();
          api.lastChunk!.complete(api.page<dynamic>(1000, 8, marker: 'stale'));
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(notifier.state.photos.length, 12);
          expect(notifier.state.photos.first.url, contains('manual-refresh'));
        } else {
          container.invalidate(provider);
          final nextProvider = filteredPhotosProvider((
            clientCode: 'CLIENT-B',
            date: '2026-11-10',
            search: 'TRACK',
          ));
          final nextSubscription = container.listen(nextProvider, (_, _) {});
          addTearDown(nextSubscription.close);
          final next = container.read(nextProvider);
          await _waitUntil(() => next.state.photos.length == 12);
          api.lastChunk!.complete(
            api.page<dynamic>(1000, 8, marker: 'old-account'),
          );
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(next.state.photos.first.url, contains('client-b'));
          expect(next.state.photos.length, 12);
        }
        expect(
          api.refreshQueries.map((query) => (query['skip'], query['take'])),
          [(0, 1000), (1000, 8)],
        );
        for (final query in api.refreshQueries) {
          expect(query['clientCode'], 'CLIENT-A');
          expect(query['date'], '2026-11-10');
          expect(query['search'], 'TRACK');
          expect(query['includeVideos'], isTrue);
        }
      },
    );
  }
}
