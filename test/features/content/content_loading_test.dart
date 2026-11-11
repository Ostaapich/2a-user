import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/news/data/news_provider.dart';
import 'package:twoalogisticcabineuser/src/features/rules/data/rules_provider.dart';

class _ContentApi extends ApiClient {
  _ContentApi({this.status, this.success = false});
  final int? status;
  final bool success;
  final paths = <String>[];
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    paths.add(path);
    final request = RequestOptions(path: path);
    if (!success) {
      throw DioException(
        requestOptions: request,
        type: status == null
            ? DioExceptionType.connectionError
            : DioExceptionType.badResponse,
        response: status == null
            ? null
            : Response(requestOptions: request, statusCode: status),
      );
    }
    final item = {
      'id': 9876,
      'title': 'Старая публикация',
      'content': 'Полный текст',
    };
    return Response<T>(
      requestOptions: request,
      statusCode: 200,
      data: (path.startsWith('/news/') ? {'data': item} : item) as T,
    );
  }
}

void main() {
  for (final isNews in [true, false]) {
    test(
      '${isNews ? 'news' : 'rules'} list preserves transport failure',
      () async {
        final api = _ContentApi();
        final container = ProviderContainer(
          retry: (_, _) => null,
          overrides: [
            apiClientProvider.overrideWithValue(api),
            clientAgentIdProvider.overrideWithValue(1),
          ],
        );
        addTearDown(container.dispose);
        await expectLater(
          isNews
              ? container.read(newsListProvider.future)
              : container.read(rulesListProvider.future),
          throwsA(isA<DioException>()),
        );
      },
    );
    test(
      '${isNews ? 'news' : 'rules'} old numeric deep link bypasses latest 50',
      () async {
        final api = _ContentApi(success: true);
        final container = ProviderContainer(
          overrides: [apiClientProvider.overrideWithValue(api)],
        );
        addTearDown(container.dispose);
        final item = isNews
            ? await container.read(newsItemProvider('9876').future)
            : await container.read(ruleItemProvider('9876').future);
        expect(item, isNotNull);
        expect(api.paths, [isNews ? '/news/9876' : '/service-rules/9876']);
      },
    );
    for (final status in [404, 503]) {
      test(
        '${isNews ? 'news' : 'rules'} detail distinguishes $status',
        () async {
          final api = _ContentApi(status: status);
          final container = ProviderContainer(
            retry: (_, _) => null,
            overrides: [apiClientProvider.overrideWithValue(api)],
          );
          addTearDown(container.dispose);
          final future = isNews
              ? container.read(newsItemProvider('9876').future)
              : container.read(ruleItemProvider('9876').future);
          if (status == 404) {
            expect(await future, isNull);
          } else {
            await expectLater(future, throwsA(isA<DioException>()));
          }
          expect(api.paths.length, 1);
        },
      );
    }
  }
}
