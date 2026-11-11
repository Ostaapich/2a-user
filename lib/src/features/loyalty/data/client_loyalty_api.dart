import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../domain/client_loyalty.dart';

class LoyaltyRequestException implements Exception {
  final String code;
  const LoyaltyRequestException(this.code);
}

class ClientLoyaltyApi {
  final ApiClient api;
  static final _initializations = <String, Future<Map<String, dynamic>>>{};
  static const _definitiveRejections = {
    'insufficient_loyalty_points',
    'loyalty_disabled',
    'reward_disabled',
    'invalid_track',
    'invalid_reward',
    'invalid_wish',
    'invalid_request_id',
    'PHOTO_REPORT_NOT_ALLOWED_FOR_STATUS',
    'duplicate_photo_request',
    'reward_refunded',
  };

  ClientLoyaltyApi(this.api);

  Future<ClientLoyalty?> load() async {
    try {
      final response = await api.get('/client/loyalty');
      final raw = response.data;
      return ClientLoyalty.tryParse(
        raw is Map && raw['data'] is Map ? raw['data'] : raw,
      );
    } on DioException catch (error) {
      if (const [404, 501].contains(error.response?.statusCode)) return null;
      rethrow;
    }
  }

  Future<void> redeem({
    required int agentId,
    required int clientId,
    required int trackId,
    required String rewardType,
    required String wish,
    required bool Function() isCurrentIdentity,
  }) async {
    if (agentId <= 0 ||
        clientId <= 0 ||
        trackId <= 0 ||
        !const ['photo', 'video'].contains(rewardType) ||
        wish.trim().isEmpty) {
      throw const LoyaltyRequestException('loyalty_invalid_request');
    }
    final key =
        'client_loyalty_request_v1:$agentId:$clientId:$trackId:$rewardType';
    final initialization = _initializations.putIfAbsent(key, () async {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(key);
      if (saved != null) {
        try {
          final value = Map<String, dynamic>.from(jsonDecode(saved) as Map);
          if (value['requestId'] is String && value['wish'] is String) {
            return value;
          }
        } catch (_) {
          // A corrupt pending key cannot safely be replaced after an unknown POST.
        }
        throw const LoyaltyRequestException('loyalty_pending_request_invalid');
      }
      final value = {'requestId': const Uuid().v4(), 'wish': wish.trim()};
      if (!await prefs.setString(key, jsonEncode(value))) {
        throw const LoyaltyRequestException('loyalty_request_not_saved');
      }
      return value;
    });
    Map<String, dynamic> pending;
    try {
      pending = await initialization;
    } catch (_) {
      if (identical(_initializations[key], initialization)) {
        _initializations.remove(key);
      }
      rethrow;
    }
    if (pending['wish'] != wish.trim()) {
      throw const LoyaltyRequestException('loyalty_pending_request_changed');
    }
    if (!isCurrentIdentity()) {
      throw const LoyaltyRequestException('loyalty_identity_changed');
    }
    late final Response<dynamic> response;
    try {
      response = await api.postOnce(
        '/client/loyalty/redemptions',
        data: {
          'trackId': trackId,
          'rewardType': rewardType,
          'wish': pending['wish'],
          'requestId': pending['requestId'],
        },
      );
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      final body = error.response?.data;
      if (status != null &&
          status >= 400 &&
          status < 500 &&
          status != 401 &&
          body is Map &&
          _definitiveRejections.contains(body['code'])) {
        // The server confirms no live redemption remains. A later explicit
        // request may change its wish and obtain a new durable UUID.
        await _clearPending(key, pending['requestId'], initialization);
      }
      rethrow;
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw const LoyaltyRequestException('loyalty_request_failed');
    }
    final body = response.data;
    final id = body is Map ? int.tryParse('${body['id']}') : null;
    if (id == null || id <= 0) {
      throw const LoyaltyRequestException('loyalty_request_failed');
    }
    // ACK is authoritative even if the local cleanup fails. Reusing the same key
    // after restart returns the server's idempotent result, never a second charge.
    await _clearPending(key, pending['requestId'], initialization);
  }

  static Future<void> _clearPending(
    String key,
    dynamic requestId,
    Future<Map<String, dynamic>> initialization,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getString(key);
      if (current != null && jsonDecode(current)['requestId'] == requestId) {
        await prefs.remove(key);
      }
    } catch (_) {
      // Cleanup never changes an acknowledged server outcome. A retained key
      // will safely replay the same idempotent result after restart.
    }
    if (identical(_initializations[key], initialization)) {
      _initializations.remove(key);
    }
  }

  Future<void> claimGift(String tier) async {
    if (!ClientLoyalty.tiers.skip(1).contains(tier)) {
      throw const LoyaltyRequestException('loyalty_invalid_tier');
    }
    await api.postOnce('/client/loyalty/gifts/claim', data: {'tier': tier});
  }
}
