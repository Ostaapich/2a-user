import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/data/auth_provider.dart';
import '../domain/client_loyalty.dart';
import 'client_loyalty_api.dart';

final clientLoyaltyApiProvider = Provider<ClientLoyaltyApi>(
  (ref) => ClientLoyaltyApi(ref.read(apiClientProvider)),
);

final clientLoyaltyProvider = FutureProvider.autoDispose<ClientLoyalty?>((
  ref,
) async {
  final identity = ref.watch(
    authProvider.select(
      (state) => (
        state.isLoggedIn,
        state.clientId,
        state.userDomain,
        state.clientData?['agentId'],
      ),
    ),
  );
  if (!identity.$1 || identity.$2 == null) return null;
  return ref.read(clientLoyaltyApiProvider).load();
});
