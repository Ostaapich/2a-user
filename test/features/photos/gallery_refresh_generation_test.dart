import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/photos/data/photos_provider.dart';

class _RaceApi extends ApiClient {
  final more = Completer<Response<dynamic>>();
  final refresh = Completer<Response<dynamic>>();
  final queries = <Map<String, dynamic>>[];
  Response<dynamic> row(int id) => Response(
    requestOptions: RequestOptions(path: '/photos'),
    statusCode: 200,
    data: {
      'total': 2,
      'data': [
        {
          'id': id,
          'url': '/uploads/$id.jpg',
          'createdAt': '2026-11-09T00:00:00Z',
        },
      ],
    },
  );
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    queries.add(Map<String, dynamic>.from(queryParameters!));
    final call = queries.length;
    if (call == 1) return row(1) as Response<T>;
    if (call == 2) return await more.future as Response<T>;
    if (call == 3) return await refresh.future as Response<T>;
    return row(1) as Response<T>;
  }
}

Future<PaginatedPhotosNotifier> _notifier(_RaceApi api) async {
  final c = ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(api)],
  );
  addTearDown(c.dispose);
  final p = filteredPhotosProvider((
    clientCode: 'SYNTHETIC',
    date: '2026-11-09',
    search: 'TRACK',
  ));
  final sub = c.listen(p, (_, _) {});
  addTearDown(sub.close);
  final n = c.read(p);
  for (var i = 0; i < 100 && n.state.photos.isEmpty; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  return n;
}

void main() {
  for (final staleError in [false, true]) {
    test(
      'refresh ignores older page ${staleError ? 'error' : 'success'} completion',
      () async {
        final api = _RaceApi();
        final n = await _notifier(api);
        final more = n.loadMore();
        final refresh = n.loadInitial();
        api.refresh.complete(api.row(1));
        await refresh;
        if (staleError) {
          api.more.completeError(
            DioException(
              requestOptions: RequestOptions(path: '/photos'),
              type: DioExceptionType.connectionError,
            ),
          );
        } else {
          api.more.complete(api.row(2));
        }
        await more;
        expect(n.state.photos.map((p) => p.id), [1]);
        expect(n.state.error, null);
        expect(n.state.isLoading, false);
      },
    );
  }
  test(
    'refresh failure preserves prior page and retry restarts offset0 with original server filters',
    () async {
      final api = _RaceApi();
      final n = await _notifier(api);
      final more = n.loadMore();
      final refresh = n.loadInitial();
      expect(n.state.photos.map((p) => p.id), [1]);
      api.more.complete(api.row(2));
      await more;
      api.refresh.completeError(
        DioException(
          requestOptions: RequestOptions(path: '/photos'),
          type: DioExceptionType.connectionError,
        ),
      );
      await refresh;
      expect(n.state.photos.map((p) => p.id), [1]);
      expect(n.state.error, isNotNull);
      await n.retryFailedLoad();
      expect(n.state.photos.map((p) => p.id), [1]);
      expect(n.state.error, null);
      expect(api.queries.map((q) => q['skip']), [0, 1, 0, 0]);
      for (final q in api.queries) {
        expect(q['clientCode'], 'SYNTHETIC');
        expect(q['date'], '2026-11-09');
        expect(q['search'], 'TRACK');
      }
    },
  );
}
