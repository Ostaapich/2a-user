import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/data/assemblies_provider.dart';

class _UnavailableReferences extends ApiClient {
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async => throw DioException(
    requestOptions: RequestOptions(path: path),
    type: DioExceptionType.connectionError,
  );
}

void main() {
  for (final tariffs in [true, false]) {
    test(
      '${tariffs ? 'tariffs' : 'packaging'} unavailable is not an empty catalogue',
      () async {
        final container = ProviderContainer(
          retry: (_, _) => null,
          overrides: [
            apiClientProvider.overrideWithValue(_UnavailableReferences()),
          ],
        );
        addTearDown(container.dispose);
        await expectLater(
          tariffs
              ? container.read(tariffsProvider.future)
              : container.read(packagingTypesProvider.future),
          throwsA(isA<DioException>()),
        );
      },
    );
  }
}
