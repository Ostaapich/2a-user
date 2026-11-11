import '../../features/home/data/home_counts_provider.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/invoices/data/invoices_provider.dart';
import '../../features/garage/application/garage_providers.dart';
import '../../features/home/data/current_cny_rate_provider.dart';
import '../../features/self_buyout/data/self_buyout_service.dart';
import '../../features/news/data/news_provider.dart';
import '../../features/notifications/application/notifications_controller.dart';
import '../../features/partner_program/data/client_partner_program_provider.dart';
import '../../features/photos/data/photos_provider.dart';
import '../../features/profile/data/profile_provider.dart';
import '../../features/rules/data/rules_provider.dart';
import '../../features/shell/application/shell_branch_provider.dart';
import '../../features/tariffs/data/tariffs_provider.dart';
import '../../features/assemblies/data/assemblies_provider.dart'
    as user_assemblies;
import '../../features/clients/application/client_codes_controller.dart';
import '../../features/sp_finance/data/sp_provider.dart';
import '../../features/tracks/data/assemblies_provider.dart';
import '../../features/tracks/data/tracks_provider.dart';
import '../logging/client_log_service.dart';
import 'websocket_provider.dart';

/// Провайдер для автоматической синхронизации данных через WebSocket дельты.
///
/// Слушает delta events и инвалидирует соответствующие FutureProvider'ы,
/// чтобы экраны автоматически обновлялись при изменении данных на сервере.
///
/// Замена для AutoRefreshMixin (60-секундный polling).
final deltaSyncProvider = Provider<void>((ref) {
  final wsService = ref.read(webSocketServiceProvider);

  // Debounce: собираем типы дельт за 500ms и обрабатываем разом
  final pendingTypes = <String>{};
  Timer? debounceTimer;
  Timer? reconnectRefreshTimer;

  void scheduleFlush(String type) {
    pendingTypes.add(type);
    debounceTimer?.cancel();
    debounceTimer = Timer(const Duration(milliseconds: 500), () {
      final types = pendingTypes.toList(growable: false)..sort();
      ClientLogService.instance.add(
        type: 'data_delta_flush',
        level: 'info',
        message: 'Получены обновления данных',
        data: {'types': types},
      );
      for (final t in pendingTypes) {
        _handleDeltaType(ref, t);
      }
      pendingTypes.clear();
    });
  }

  // Listen to delta events (room-based, preferred)
  final deltaSub = wsService.deltas.listen((delta) {
    if (kDebugMode) {
      debugPrint(
        '[DeltaSync] Delta: ${delta.type} ${delta.action} ${delta.id}',
      );
    }
    scheduleFlush(delta.type);
  });

  // Listen to delta_batch events (mass operations)
  final deltaBatchSub = wsService.deltaBatches.listen((batch) {
    if (kDebugMode) {
      debugPrint(
        '[DeltaSync] DeltaBatch: ${batch.type} ${batch.items.length} items',
      );
    }
    scheduleFlush(batch.type);
  });

  // Listen to data_changed events (broadcast, fallback)
  final dataChangedSub = wsService.dataChanged.listen((data) {
    final type = data['type'] as String?;
    if (type != null) {
      if (kDebugMode) {
        debugPrint('[DeltaSync] DataChanged: $type');
      }
      scheduleFlush(type);
    }
  });

  // При reconnect — инвалидируем все
  final reconnectSub = wsService.reconnected.listen((_) {
    if (kDebugMode) {
      debugPrint('[DeltaSync] WS reconnected — invalidating all providers');
    }
    ClientLogService.instance.add(
      type: 'websocket_reconnected',
      level: 'warning',
      message: 'WebSocket переподключился, планируем обновление данных',
    );
    reconnectRefreshTimer?.cancel();
    reconnectRefreshTimer = Timer(const Duration(seconds: 2), () {
      ClientLogService.instance.add(
        type: 'websocket_reconnected_refresh',
        level: 'warning',
        message: 'Обновляем данные после переподключения WebSocket',
      );
      _invalidateAll(ref);
    });
  });

  ref.onDispose(() {
    deltaSub.cancel();
    deltaBatchSub.cancel();
    dataChangedSub.cancel();
    reconnectSub.cancel();
    debounceTimer?.cancel();
    reconnectRefreshTimer?.cancel();
  });
});

void _handleDeltaType(Ref ref, String type) {
  ClientLogService.instance.add(
    type: 'data_invalidate',
    level: 'info',
    message: 'Обновляем провайдеры после дельты $type',
    data: {'deltaType': type},
  );

  switch (type) {
    case 'tracks':
      // PaginatedTracksNotifier использует custom listener pattern,
      // для FutureProvider'ов — invalidate
      ref.invalidate(tracksDigestProvider);
      ref.invalidate(tracksCountProvider);
      ref.invalidate(homeTracksCountProvider);
      ref.invalidate(tracksWithoutAssemblyCountProvider);
      return;

    case 'assemblies':
    case 'warehouse_assemblies':
      ref.invalidate(assembliesListProvider);
      ref.invalidate(assembliesDigestProvider);
      ref.invalidate(assembliesCountProvider);
      ref.invalidate(homeAssembliesCountProvider);
      ref.invalidate(user_assemblies.assembliesListProvider);
      ref.invalidate(user_assemblies.assembliesCountProvider);
      // SP finance assemblies (NotifierProvider — throttle WS refreshes)
      ref.read(spAssembliesControllerProvider.notifier).refreshFromDelta();
      return;

    case 'invoices':
      if (_isShellBranchActive(ref, ShellBranchIndex.invoices)) {
        ref.invalidate(invoicesListProvider);
        ref.invalidate(invoiceDirectoryPageProvider);
        ref.invalidate(invoiceDirectoryProvider);
      }
      ref.invalidate(invoicesDigestProvider);
      ref.invalidate(invoicesCountProvider);
      // Инвалидируем детальные провайдеры (family) — нужно для мгновенного
      // обновления открытого инвойса, например, на экране оплаты.
      ref.invalidate(invoiceByIdProvider);
      return;

    case 'self_buyout':
      // F2-1: заявка самовыкупа изменилась (статус/чек/подтверждение) —
      // обновляем список и доступность.
      ref.invalidate(selfBuyoutRequestsProvider);
      ref.invalidate(selfBuyoutAvailabilityProvider);
      return;

    case 'garage_requests':
    case 'garage_request_messages':
      ref.invalidate(garageRequestsProvider);
      ref.invalidate(garageRequestProvider);
      return;

    case 'garage_orders':
      ref.invalidate(garageOrdersProvider);
      ref.invalidate(garageOrderProvider);
      ref.invalidate(garageInvoiceProvider);
      ref.invalidate(garageRequestsProvider);
      ref.invalidate(garageRequestProvider);
      return;

    case 'currency_rates':
      ref.invalidate(currentCnyRateProvider);
      ref.invalidate(garageRequestsProvider);
      ref.invalidate(garageRequestProvider);
      ref.invalidate(garageOrdersProvider);
      ref.invalidate(garageOrderProvider);
      ref.invalidate(garageInvoiceProvider);
      ref.invalidate(selfBuyoutAvailabilityProvider);
      return;

    case 'news':
      ref.invalidate(newsListProvider);
      return;

    case 'tariffs':
      ref.invalidate(userTariffsProvider);
      return;

    case 'service_rules':
      ref.invalidate(rulesListProvider);
      return;

    case 'photo_requests':
      ref.invalidate(photosTotalCountProvider);
      ref.invalidate(photosRecentProvider);
      ref.invalidate(photosDaysProvider);
      ref.invalidate(photosByDateProvider);
      ref.invalidate(photosSearchProvider);
      // Фотозапросы вложены в треки — обновляем digest
      ref.invalidate(tracksDigestProvider);
      return;

    case 'questions':
      // Вопросы вложены в треки — обновляем digest
      ref.invalidate(tracksDigestProvider);
      return;

    case 'notifications':
      ref.read(notificationsControllerProvider.notifier).refreshDebounced();
      // T-Bank settlement currently emits only a notifications delta. Refresh
      // every client payment target family so an already-open Invoice/Garage
      // detail re-reads paymentSummary and terminal status immediately.
      invalidatePaymentTargetProviders(ref);
      return;
  }
}

@visibleForTesting
void invalidatePaymentTargetProviders(dynamic ref) {
  ref.invalidate(invoicesListProvider);
  ref.invalidate(invoiceDirectoryPageProvider);
  ref.invalidate(invoiceDirectoryProvider);
  ref.invalidate(invoicesDigestProvider);
  ref.invalidate(invoicesCountProvider);
  ref.invalidate(invoiceByIdProvider);
  ref.invalidate(garageRequestsProvider);
  ref.invalidate(garageRequestProvider);
  ref.invalidate(garageOrdersProvider);
  ref.invalidate(garageOrderProvider);
  ref.invalidate(garageInvoiceProvider);
}

/// Принудительное обновление клиентских данных после восстановления сети.
///
/// Вызывается из App при возврате из background/sleep и из WS reconnect-flow.
/// Держим это в одном месте, чтобы не расходились списки провайдеров.
void invalidateClientDataProviders(WidgetRef ref) => _invalidateAllFor(ref);

/// Лёгкое обновление после resume: сначала профиль/коды/уведомления, без
/// одновременного старта всех списков и дайджестов.
void invalidateClientCoreProviders(WidgetRef ref) {
  ref.invalidate(clientProfileProvider);
  ref.invalidate(clientStatsProvider);
  ref.invalidate(clientCodesControllerProvider);
  ref.invalidate(currentCnyRateProvider);
  ref.invalidate(clientPartnerProgramProvider);
  ref.read(notificationsControllerProvider.notifier).refreshDebounced();
}

void _invalidateAll(Ref ref) => _invalidateAllFor(ref);

void _invalidateAllFor(dynamic ref) {
  ref.invalidate(clientProfileProvider);
  ref.invalidate(clientStatsProvider);
  ref.invalidate(clientCodesControllerProvider);
  ref.invalidate(currentCnyRateProvider);
  ref.invalidate(clientPartnerProgramProvider);
  ref.invalidate(tracksDigestProvider);
  ref.invalidate(tracksCountProvider);
  ref.invalidate(homeTracksCountProvider);
  ref.invalidate(tracksWithoutAssemblyCountProvider);
  ref.invalidate(assembliesListProvider);
  ref.invalidate(assembliesDigestProvider);
  ref.invalidate(assembliesCountProvider);
  ref.invalidate(homeAssembliesCountProvider);
  ref.invalidate(user_assemblies.assembliesListProvider);
  ref.invalidate(user_assemblies.assembliesCountProvider);
  ref.read(spAssembliesControllerProvider.notifier).refreshFromDelta();
  if (_isShellBranchActive(ref, ShellBranchIndex.invoices)) {
    ref.invalidate(invoicesListProvider);
    ref.invalidate(invoiceDirectoryPageProvider);
    ref.invalidate(invoiceDirectoryProvider);
  }
  ref.invalidate(invoicesDigestProvider);
  ref.invalidate(invoicesCountProvider);
  ref.invalidate(garageAvailabilityProvider);
  ref.invalidate(garageRequestsProvider);
  ref.invalidate(garageRequestProvider);
  ref.invalidate(garageOrdersProvider);
  ref.invalidate(garageOrderProvider);
  ref.invalidate(garageInvoiceProvider);
  ref.invalidate(newsListProvider);
  ref.invalidate(userTariffsProvider);
  ref.invalidate(rulesListProvider);
  ref.invalidate(photosTotalCountProvider);
  ref.invalidate(photosRecentProvider);
  ref.invalidate(photosDaysProvider);
  ref.invalidate(photosByDateProvider);
  ref.invalidate(photosSearchProvider);
}

bool _isShellBranchActive(dynamic ref, int branchIndex) {
  try {
    return ref.read(activeShellBranchIndexProvider) == branchIndex;
  } catch (_) {
    // На случай ранних bootstrap/test-контекстов без shell provider:
    // лучше обновить данные, чем случайно оставить активный экран stale.
    return true;
  }
}
