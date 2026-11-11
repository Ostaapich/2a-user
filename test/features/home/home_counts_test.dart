import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/home/data/home_counts_provider.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/data/invoices_provider.dart';

class _CountsApi extends ApiClient {
  final queries = <String, Map<String, dynamic>>{};
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    queries[path] = queryParameters!;
    return Response<T>(
      data:
          {
                'data': <dynamic>[],
                'total': 1234,
                'pagination': {'total': 5678},
              }
              as T,
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('home counts use server totals and exact status filters', () async {
    SharedPreferences.setMockInitialValues({});
    final api = _CountsApi();
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    expect(await container.read(homeTracksCountProvider('TEST').future), 1234);
    expect(
      await container.read(homeAssembliesCountProvider('TEST').future),
      5678,
    );
    expect(await container.read(invoicesCountProvider('TEST').future), 1234);
    expect(api.queries['/tracks'], {
      'clientCode': 'TEST',
      'take': 1,
      'statuses': 'in_warehouse',
    });
    expect(
      await container.read(homePendingTracksCountProvider('TEST').future),
      1234,
    );
    expect(api.queries['/tracks'], {
      'clientCode': 'TEST',
      'take': 1,
      'statuses': 'pending',
    });
    expect(api.queries['/assemblies'], {
      'clientCode': 'TEST',
      'take': 1,
      'statuses': 'new,in_warehouse,in_assembly,shipped',
    });
    expect(api.queries['/invoices'], {
      'clientCode': 'TEST',
      'take': 1,
      'status': 'unpaid',
    });
  });
}
