import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_v2_repository.dart';

class _Api extends ApiClient {
  final calls = <(String, dynamic)>[];
  @override
  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    calls.add((path, data));
    return Response<T>(requestOptions: RequestOptions(path: path));
  }
}

void main() {
  test(
    'customer payment submits one complete versioned batch and preserves unknown amount',
    () async {
      final api = _Api();
      final repository = SpV2Repository(api);
      final version = DateTime.utc(2026, 11, 9);
      await repository.setCustomerItemsPayment(
        4,
        purchaseId: 7,
        type: 'goods_payment',
        paid: true,
        items: [
          (id: 1, expectedUpdatedAt: version, amountRub: 10.235),
          (id: 2, expectedUpdatedAt: version, amountRub: null),
        ],
      );
      expect(api.calls.length, 1);
      expect(api.calls.single.$1, '/client/sp-v2/customers/4/payment');
      final body = api.calls.single.$2 as Map;
      expect(body['paid'], true);
      expect(body['purchaseId'], 7);
      final items = body['items'] as List;
      expect(items.length, 2);
      expect(items.first['expectedUpdatedAt'], version.toIso8601String());
      expect(items.first['amountRub'], 10.23);
      expect(items.last.containsKey('amountRub'), false);
    },
  );
}
