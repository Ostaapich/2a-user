import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/shop/data/purchase_provider.dart';

class _UnavailableShopApi extends ApiClient {
  _UnavailableShopApi({this.status});
  final int? status;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    throw DioException(
      requestOptions: RequestOptions(path: path),
      type: status == null
          ? DioExceptionType.connectionError
          : DioExceptionType.badResponse,
      response: status == null
          ? null
          : Response(
              requestOptions: RequestOptions(path: path),
              statusCode: status,
            ),
    );
  }
}

void main() {
  for (final target in ['cart', 'history', 'detail']) {
    test(
      '$target network failure remains an error rather than empty data',
      () async {
        final container = ProviderContainer(
          retry: (_, _) => null,
          overrides: [
            apiClientProvider.overrideWithValue(_UnavailableShopApi()),
          ],
        );
        addTearDown(container.dispose);
        final future = switch (target) {
          'cart' => container.read(activePurchaseListProvider.future),
          'history' => container.read(purchaseListsProvider.future),
          _ => container.read(purchaseListDetailProvider(7).future),
        };
        await expectLater(future, throwsA(isA<DioException>()));
      },
    );
  }

  test('an actual missing order remains a not-found result', () async {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        apiClientProvider.overrideWithValue(_UnavailableShopApi(status: 404)),
      ],
    );
    addTearDown(container.dispose);
    expect(await container.read(purchaseListDetailProvider(7).future), isNull);
  });
}
