import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../auth/data/auth_provider.dart';
import '../../news/data/news_provider.dart';
import '../domain/client_terms_snapshot.dart';

class TermsVersionChanged implements Exception {}

class TermsAccountChanged implements Exception {}

class ClientTermsService {
  ClientTermsService(this.api);
  final ApiClient api;
  Future<ClientTermsSnapshot> fetch({
    required int clientId,
    required int agentId,
  }) async {
    final response = await api.get('/client/terms');
    final snapshot = ClientTermsSnapshot.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
    if (snapshot.clientId != clientId || snapshot.agentId != agentId) {
      throw TermsAccountChanged();
    }
    return snapshot;
  }

  Future<void> accept(ClientTermsSnapshot snapshot) async {
    if (!snapshot.available ||
        snapshot.revision == null ||
        snapshot.rules.isEmpty) {
      throw StateError('Terms unavailable');
    }
    try {
      final response = await api.post(
        '/client/terms/accept',
        data: {
          'revision': snapshot.revision,
          'expectedClientId': snapshot.clientId,
          'expectedAgentId': snapshot.agentId,
        },
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['accepted'] != true ||
          data['revision'] != snapshot.revision ||
          data['clientId'] != snapshot.clientId ||
          data['agentId'] != snapshot.agentId ||
          DateTime.tryParse(data['acceptedAt']?.toString() ?? '') == null) {
        throw const FormatException('Unconfirmed terms acceptance');
      }
    } on DioException catch (error) {
      final data = error.response?.data;
      final code = data is Map ? data['code'] : null;
      if (code == 'TERMS_VERSION_CHANGED' || code == 'TERMS_UNAVAILABLE') {
        throw TermsVersionChanged();
      }
      if (code == 'ACCOUNT_CHANGED') throw TermsAccountChanged();
      rethrow;
    }
  }
}

final clientTermsServiceProvider = Provider(
  (ref) => ClientTermsService(ref.read(apiClientProvider)),
);
final clientTermsSnapshotProvider = FutureProvider<ClientTermsSnapshot>((
  ref,
) async {
  final auth = ref.watch(
    authProvider.select((value) => (value.isLoggedIn, value.clientId)),
  );
  final agentId = ref.watch(clientAgentIdProvider);
  if (!auth.$1 || auth.$2 == null || agentId == null) {
    throw TermsAccountChanged();
  }
  final result = await ref
      .read(clientTermsServiceProvider)
      .fetch(clientId: auth.$2!, agentId: agentId);
  if (!ref.mounted) throw TermsAccountChanged();
  final current = ref.read(authProvider);
  if (!current.isLoggedIn ||
      current.clientId != result.clientId ||
      ref.read(clientAgentIdProvider) != result.agentId) {
    throw TermsAccountChanged();
  }
  return result;
});
