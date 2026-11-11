import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/photos/data/photos_provider.dart';

class _GalleryApi extends ApiClient {
  final queries = <Map<String, dynamic>>[];
  bool failNext = true;
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    final query = Map<String, dynamic>.from(queryParameters!);
    queries.add(query);
    final request = RequestOptions(path: path);
    if (query['skip'] != 0 && failNext) {
      throw DioException(
        requestOptions: request,
        type: DioExceptionType.connectionError,
      );
    }
    return Response<T>(
      requestOptions: request,
      statusCode: 200,
      data:
          {
                'total': 2,
                'data': [
                  {
                    'id': query['skip'] == 0 ? 1 : 2,
                    'url': '/uploads/test.jpg',
                    'createdAt': '2026-11-09T00:00:00Z',
                  },
                ],
              }
              as T,
    );
  }
}

void main() {
  test(
    'gallery applies server filters to every page and retries same failed offset',
    () async {
      final api = _GalleryApi();
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final provider = filteredPhotosProvider((
        clientCode: '2A-TEST',
        date: '2026-11-09',
        search: 'TRACK-9876',
      ));
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final notifier = container.read(provider);
      for (var i = 0; i < 100 && notifier.state.photos.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(notifier.state.photos.map((p) => p.id), [1]);
      await notifier.loadMore();
      expect(notifier.state.error, isNotNull);
      expect(notifier.state.photos.length, 1);
      api.failNext = false;
      await notifier.loadMore();
      expect(notifier.state.error, isNull);
      expect(notifier.state.photos.map((p) => p.id), [1, 2]);
      expect(notifier.state.hasMore, isFalse);
      expect(api.queries.map((q) => q['skip']), [0, 1, 1]);
      for (final query in api.queries) {
        expect(query['search'], 'TRACK-9876');
        expect(query['date'], '2026-11-09');
        expect(query['clientCode'], '2A-TEST');
      }
    },
  );
}
