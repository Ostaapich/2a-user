import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/data/invoices_provider.dart';
import 'package:twoalogisticcabineuser/src/features/self_buyout/data/self_buyout_service.dart';

class _Api extends ApiClient {
  int calls = 0;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    calls++;
    if (path.contains('availability') || calls > 1) {
      throw DioException(requestOptions: RequestOptions(path: path));
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data:
          {
                'data': [
                  {'id': 1, 'invoiceNumber': 'INV-1'},
                ],
                'hasMore': true,
              }
              as T,
    );
  }
}

class _DirectoryApi extends ApiClient {
  Map<String, dynamic>? query;
  bool broken = false;
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    query = queryParameters;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data:
          {
                'data': broken
                    ? []
                    : [
                        {'id': 151, 'invoiceNumber': 'OLD-151'},
                      ],
                'total': 180,
                'hasMore': true,
              }
              as T,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'history beyond 100 uses server search and status with bounded page offset',
    () async {
      final api = _DirectoryApi();
      final page = await fetchInvoiceDirectoryPage(api, (
        clientCode: '2A-01',
        search: '  old tariff  ',
        status: 'unpaid',
        page: 4,
      ));
      expect(api.query, {
        'clientCode': '2A-01',
        'skip': 150,
        'take': 50,
        'search': 'old tariff',
        'status': 'unpaid',
      });
      expect(page.items.single.id, '151');
      expect(page.total, 180);
      expect(page.hasMore, isTrue);
      api.broken = true;
      await expectLater(
        fetchInvoiceDirectoryPage(api, (
          clientCode: '2A-01',
          search: '',
          status: null,
          page: 1,
        )),
        throwsFormatException,
      );
    },
  );
  test(
    'export never returns a successful partial file after a page fails',
    () async {
      await expectLater(
        fetchAllInvoicesForExport(_Api(), '2A-01', batchSize: 1),
        throwsA(isA<Exception>()),
      );
    },
  );

  test('export reaching its limit cannot masquerade as complete', () async {
    await expectLater(
      fetchAllInvoicesForExport(_Api(), '2A-01', batchSize: 1, safetyLimit: 1),
      throwsA(isA<Exception>()),
    );
  });

  test(
    'availability network failure remains an error, not a policy denial',
    () async {
      await expectLater(
        SelfBuyoutService(_Api()).getAvailability(),
        throwsA(isA<DioException>()),
      );
    },
  );
}
