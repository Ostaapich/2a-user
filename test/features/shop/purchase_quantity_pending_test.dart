import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/shop/data/purchase_provider.dart';
import 'package:twoalogisticcabineuser/src/features/shop/domain/purchase_list.dart';
import 'package:twoalogisticcabineuser/src/features/shop/presentation/purchase_list_screen.dart';

class _PendingApi extends ApiClient {
  final pending = Completer<Response<dynamic>>();
  int calls = 0;
  @override
  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    calls++;
    return await pending.future as Response<T>;
  }
}

void main() {
  testWidgets(
    'quantity cannot race and submission waits for confirmed quantity',
    (tester) async {
      final api = _PendingApi();
      final cart = PurchaseList(
        id: 7,
        status: 'draft',
        createdAt: DateTime(2026),
        totalItems: 1,
        items: const [
          PurchaseItem(
            id: 3,
            externalItemId: 'abc',
            provider: '1688',
            title: 'Cart item',
            quantity: 2,
            price: 10,
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(api),
            activePurchaseListProvider.overrideWith((ref) async => cart),
          ],
          child: const MaterialApp(home: Scaffold(body: PurchaseListScreen())),
        ),
      );
      await tester.pumpAndSettle();
      final plus = find.byIcon(Icons.add);
      expect(plus, findsOneWidget);
      await tester.tap(plus);
      await tester.pump();
      await tester.tap(plus);
      await tester.pump();
      expect(api.calls, 1);
      final submit = find.widgetWithText(FilledButton, 'Отправить менеджеру');
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      api.pending.complete(
        Response(
          requestOptions: RequestOptions(path: ''),
          data: <String, dynamic>{},
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    },
  );
}
