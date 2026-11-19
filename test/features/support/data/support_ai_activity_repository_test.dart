import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/support/data/chat_provider.dart';

class _Api extends Mock implements ApiClient {}

void main() {
  test(
    'activity is read from the dedicated endpoint without selecting another client',
    () async {
      final api = _Api();
      when(
        () => api.get(
          '/client/chat/activity',
          queryParameters: {'conversationId': 7},
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/client/chat/activity'),
          statusCode: 200,
          data: {
            'conversationId': 7,
            'isTyping': true,
            'messageId': 10,
            'expiresAt': DateTime.now()
                .add(const Duration(seconds: 45))
                .toIso8601String(),
          },
        ),
      );
      final result = await ChatRepository(
        api,
      ).fetchAiActivity(conversationId: 7);
      expect(result?.messageId, 10);
      verify(
        () => api.get(
          '/client/chat/activity',
          queryParameters: {'conversationId': 7},
        ),
      ).called(1);
    },
  );
  test(
    'an older backend, malformed body and transient error simply disable the indicator',
    () async {
      for (final status in [404, 500, 200]) {
        final api = _Api();
        when(
          () => api.get(
            '/client/chat/activity',
            queryParameters: {'conversationId': 7},
          ),
        ).thenAnswer(
          (_) async => Response(
            requestOptions: RequestOptions(path: '/client/chat/activity'),
            statusCode: status,
            data: {'conversation': null},
          ),
        );
        expect(
          await ChatRepository(api).fetchAiActivity(conversationId: 7),
          isNull,
        );
      }
      final api = _Api();
      when(
        () => api.get(
          '/client/chat/activity',
          queryParameters: {'conversationId': 7},
        ),
      ).thenThrow(Exception('offline'));
      expect(
        await ChatRepository(api).fetchAiActivity(conversationId: 7),
        isNull,
      );
    },
  );
}
