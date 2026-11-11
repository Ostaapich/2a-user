import '../../../core/services/analytics_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/error_utils.dart';
import '../domain/add_tracks_result.dart';

abstract class AddTracksRepository {
  Future<AddTracksResult> addTracks({
    required String clientCode,
    required List<String> trackCodes,
  });
}

final addTracksRepositoryProvider = Provider<AddTracksRepository>((ref) {
  return RealAddTracksRepository(ref);
});

class RealAddTracksRepository implements AddTracksRepository {
  final Ref _ref;

  RealAddTracksRepository(this._ref);

  ApiClient get _api => _ref.read(apiClientProvider);

  @override
  Future<AddTracksResult> addTracks({
    required String clientCode,
    required List<String> trackCodes,
  }) async {
    return AnalyticsService.traceOperation(
      WorkflowAction.trackAdd,
      () async {
        try {
          final response = await _api.post(
            '/client/tracks',
            data: {'clientCode': clientCode, 'trackNumbers': trackCodes},
          );

          if (response.statusCode == 200 || response.statusCode == 201) {
            final data = response.data as Map<String, dynamic>;
            final added = data['added'] as int? ?? 0;
            final skippedList = data['skipped'] as List<dynamic>? ?? [];

            final skipped = skippedList.map((s) {
              if (s is Map<String, dynamic>) {
                return SkippedTrack(
                  code: s['code'] as String? ?? '',
                  reason: s['reason'] as String? ?? 'Неизвестная причина',
                );
              }
              return SkippedTrack(
                code: s.toString(),
                reason: 'Уже существует в базе',
              );
            }).toList();

            return AddTracksResult(added: added, skipped: skipped);
          }

          throw Exception(
            'Ошибка при добавлении треков: ${response.statusCode}',
          );
        } on DioException catch (e) {
          debugPrint('Error adding tracks: $e');

          // Специфичные ошибки для добавления треков
          if (e.response?.statusCode == 401) {
            throw Exception('Необходимо авторизоваться');
          }
          if (e.response?.statusCode == 403) {
            throw Exception('Нет доступа для добавления треков');
          }
          if (e.response?.statusCode == 404) {
            throw Exception('Код клиента не найден');
          }

          // Проверяем кастомное сообщение от сервера
          final serverErrorMessage = e.response?.data?['error'] as String?;
          if (serverErrorMessage != null && serverErrorMessage.isNotEmpty) {
            throw Exception(serverErrorMessage);
          }

          // Используем ErrorUtils для остальных ошибок
          final errorInfo = ErrorUtils.getErrorInfo(e);
          throw Exception(errorInfo.message);
        } catch (e, stackTrace) {
          debugPrint('Unexpected error adding tracks: $e');
          debugPrint('Stack trace: $stackTrace');
          throw Exception(
            'Произошла непредвиденная ошибка. Попробуйте ещё раз',
          );
        }
      },
      outcome: (result) =>
          result.added > 0 ? WorkflowStage.succeeded : WorkflowStage.noChange,
    );
  }
}
