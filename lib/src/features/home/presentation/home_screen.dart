import 'package:twoalogisticcabineuser/src/core/media/authenticated_media.dart';
import 'home_payment_attention.dart';

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/branding/company_branding_provider.dart';
import '../../../core/cache/stale_data_cache.dart';
import '../../../core/network/api_config.dart';
import '../../../core/ui/app_cached_media_image.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/ui/app_layout.dart';
import '../../../core/ui/empty_state.dart';
import '../../../core/utils/clipboard_helper.dart';
import '../../../core/utils/locale_text.dart';
import '../../assemblies/data/assemblies_provider.dart';
import '../../assemblies/domain/assembly_item.dart';
import '../../auth/data/auth_provider.dart';
import '../../rules/data/client_terms_provider.dart';
import '../../rules/domain/client_terms_snapshot.dart';
import '../../rules/presentation/terms_document_sheet.dart';
import '../../rules/domain/terms_identity.dart';
import '../../shell/application/shell_branch_provider.dart';
import '../../news/data/news_provider.dart';
import '../../clients/application/client_codes_controller.dart';
import '../../clients/presentation/client_switcher_sheet.dart';
import '../../../core/ui/blurred_modal_bottom_sheet.dart';
import '../../invoices/data/invoices_provider.dart';
import '../../invoices/domain/invoice_item.dart';
import '../../invoices/presentation/invoices_screen.dart';
import '../../photos/data/photos_provider.dart';
import '../../photos/domain/photo_item.dart';
import '../../photos/presentation/photo_viewer_screen.dart';
import '../../profile/data/profile_provider.dart';
import '../../referral/data/referral_provider.dart';
import '../../tracks/data/tracks_provider.dart';
import '../../training/presentation/training_target.dart';
import '../../training/presentation/training_home_invitation.dart';
import '../../tracks/domain/track_item.dart';
import '../../tracks/presentation/add_tracks_dialog.dart';
import '../../tracks/presentation/tracks_screen.dart';
import '../../../core/ui/tutorial_card.dart';
import '../data/current_cny_rate_provider.dart';
import 'home_cny_rate_card.dart';
import 'home_stats_grid.dart';
import '../data/home_counts_provider.dart';
import 'home_agent_contacts_card.dart';
import 'warehouse_address_checker.dart';
import 'warehouse_address_copy_banner.dart';

void _showStyledSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  AppToast.show(context, message, isError: isError);
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // Флаг для показа диалога принятия правил
  bool _termsCheckRunning = false;
  bool _termsCheckScheduled = false;
  bool _termsCheckQueued = false;
  bool _termsRetryAvailable = false;

  final GlobalKey _quickCardsKey = GlobalKey();
  final GlobalKey _digestKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _checkAndShowTermsDialog(refreshRules: true);
  }

  bool get _canPresentTerms {
    if (ref.read(activeShellBranchIndexProvider) != ShellBranchIndex.home) {
      return false;
    }
    var current = ModalRoute.of(context)?.isCurrent ?? true;
    context.visitAncestorElements((element) {
      if (element.widget is Navigator) {
        final outerRoute = ModalRoute.of(element);
        if (outerRoute != null && !outerRoute.isCurrent) current = false;
      }
      return current;
    });
    return current;
  }

  /// Rechecks when identity/agent become ready, when home becomes active, and
  /// on explicit retry/refresh. Never interrupt an already open customer form.
  void _checkAndShowTermsDialog({bool refreshRules = false}) {
    if (_termsCheckRunning) {
      _termsCheckQueued = true;
      return;
    }
    if (_termsCheckScheduled) return;
    _termsCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _termsCheckScheduled = false;
      if (!mounted || _termsCheckRunning) return;
      final auth = ref.read(authProvider);
      final agentId = ref.read(clientAgentIdProvider);
      if (!auth.isLoggedIn ||
          auth.isLoading ||
          auth.clientId == null ||
          agentId == null) {
        return;
      }
      if (ref.read(activeShellBranchIndexProvider) != ShellBranchIndex.home) {
        return;
      }
      if (!_canPresentTerms) {
        setState(() => _termsRetryAvailable = true);
        return;
      }
      _termsCheckRunning = true;
      try {
        if (refreshRules) ref.invalidate(clientTermsSnapshotProvider);
        final snapshot = await ref.read(clientTermsSnapshotProvider.future);
        if (!mounted) return;
        final current = ref.read(authProvider);
        if (!current.isLoggedIn ||
            current.clientId != auth.clientId ||
            ref.read(clientAgentIdProvider) != agentId) {
          return;
        }
        if (!snapshot.available || snapshot.rules.isEmpty) {
          setState(() => _termsRetryAvailable = true);
          return;
        }
        if (snapshot.clientId != auth.clientId || snapshot.agentId != agentId) {
          setState(() => _termsRetryAvailable = true);
          return;
        }
        if (snapshot.accepted) {
          setState(() => _termsRetryAvailable = false);
          return;
        }
        if (!_canPresentTerms) {
          setState(() => _termsRetryAvailable = true);
          return;
        }
        setState(() => _termsRetryAvailable = false);
        final refresh = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _TermsAcceptanceDialog(snapshot: snapshot),
        );
        if (!mounted) return;
        if (refresh == true) {
          ref.invalidate(clientTermsSnapshotProvider);
          _termsCheckQueued = true;
        }
      } catch (_) {
        if (mounted) setState(() => _termsRetryAvailable = true);
      } finally {
        _termsCheckRunning = false;
        if (mounted && _termsCheckQueued) {
          _termsCheckQueued = false;
          _checkAndShowTermsDialog();
        }
      }
    });
  }

  Widget _termsRetryCard() => Padding(
    padding: const EdgeInsets.all(12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr(
                context,
                ru: 'Правила требуют проверки. Если загрузка не удалась, проверьте соединение и повторите.',
                zh: '需要核对服务规则。如果加载失败，请检查网络后重试。',
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _checkAndShowTermsDialog(refreshRules: true),
              icon: const Icon(Icons.refresh),
              label: Text(
                tr(context, ru: 'Повторить проверку правил', zh: '重新核对规则'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _withTermsRetry(Widget child) => !_termsRetryAvailable
      ? child
      : Column(
          children: [
            _termsRetryCard(),
            Expanded(child: child),
          ],
        );

  void _openNoCodeSearch() {
    context.push('/search-nocode');
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      authProvider.select(
        (value) => (value.isLoggedIn, value.isLoading, value.clientId),
      ),
      (_, _) => _checkAndShowTermsDialog(),
    );
    ref.listen(clientAgentIdProvider, (_, _) => _checkAndShowTermsDialog());
    ref.listen(activeShellBranchIndexProvider, (_, next) {
      if (next == ShellBranchIndex.home) {
        _checkAndShowTermsDialog(refreshRules: true);
      }
    });
    final clientCode = ref.watch(activeClientCodeProvider);
    final authState = ref.watch(authProvider);
    final clientProfile = ref.watch(clientProfileProvider);
    // Используем имя из профиля (актуальное с сервера), иначе из кэша авторизации
    final clientName =
        clientProfile.asData?.value?.fullName ??
        authState.clientName ??
        'Клиент';
    final shouldLoadDashboardData =
        authState.isLoggedIn && !authState.isLoading;

    if (clientCode == null) {
      final codes = ref.watch(clientCodesControllerProvider);
      if (codes.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return _withTermsRetry(
        EmptyState(
          icon: codes.hasError
              ? Icons.sync_problem_rounded
              : Icons.badge_outlined,
          title: tr(
            context,
            ru: codes.hasError
                ? 'Не удалось загрузить коды клиента'
                : 'Выберите или добавьте код клиента',
            zh: codes.hasError ? '无法加载客户代码' : '选择或添加客户代码',
          ),
          message: tr(
            context,
            ru: codes.hasError
                ? 'Проверьте соединение и повторите загрузку.'
                : 'Код объединяет ваши посылки, фотоотчёты и счета.',
            zh: codes.hasError ? '请检查网络连接后重试。' : '客户代码关联您的包裹、照片和账单。',
          ),
          actionLabel: tr(
            context,
            ru: codes.hasError ? 'Повторить' : 'Открыть коды клиента',
            zh: codes.hasError ? '重试' : '打开客户代码',
          ),
          onAction: codes.hasError
              ? () => ref.invalidate(clientCodesControllerProvider)
              : () => showBlurredModalBottomSheet<void>(
                  context: context,
                  useRootNavigator: true,
                  isScrollControlled: true,
                  builder: (_) => const ClientSwitcherSheet(),
                ),
        ),
      );
    }

    final AsyncValue<List<TrackItem>> tracksDigestAsync =
        shouldLoadDashboardData
        ? ref.watch(tracksDigestProvider(clientCode))
        : const AsyncValue.loading();
    final AsyncValue<List<AssemblyItem>> assembliesDigestAsync =
        shouldLoadDashboardData
        ? ref.watch(assembliesDigestProvider(clientCode))
        : const AsyncValue.loading();
    final AsyncValue<List<InvoiceItem>> invoicesDigestAsync =
        shouldLoadDashboardData
        ? ref.watch(invoicesDigestProvider(clientCode))
        : const AsyncValue.loading();
    final AsyncValue<List<PhotoItem>> recentPhotosAsync =
        shouldLoadDashboardData
        ? ref.watch(photosRecentProvider((clientCode: clientCode, limit: 12)))
        : const AsyncValue.loading();

    final AsyncValue<int> tracksCountAsync = shouldLoadDashboardData
        ? ref.watch(homeTracksCountProvider(clientCode))
        : const AsyncValue.loading();
    final AsyncValue<int> pendingTracksCountAsync = shouldLoadDashboardData
        ? ref.watch(homePendingTracksCountProvider(clientCode))
        : const AsyncValue.loading();
    final AsyncValue<int> assembliesCountAsync = shouldLoadDashboardData
        ? ref.watch(homeAssembliesCountProvider(clientCode))
        : const AsyncValue.loading();
    final AsyncValue<int> invoicesCountAsync = shouldLoadDashboardData
        ? ref.watch(invoicesCountProvider(clientCode))
        : const AsyncValue.loading();
    final AsyncValue<ReferralData> referralAsync = shouldLoadDashboardData
        ? ref.watch(referralProvider)
        : const AsyncValue.loading();
    final AsyncValue<CurrentCnyRate?> currentCnyRateAsync =
        shouldLoadDashboardData
        ? ref.watch(currentCnyRateProvider)
        : const AsyncValue.loading();
    final staleNotice = ref.watch(staleDataNoticeProvider);
    final retryFailed = <VoidCallback>[
      if (tracksDigestAsync.hasError)
        () => ref.invalidate(tracksDigestProvider(clientCode)),
      if (assembliesDigestAsync.hasError)
        () => ref.invalidate(assembliesDigestProvider(clientCode)),
      if (invoicesDigestAsync.hasError)
        () => ref.invalidate(invoicesDigestProvider(clientCode)),
      if (tracksCountAsync.hasError)
        () => ref.invalidate(homeTracksCountProvider(clientCode)),
      if (pendingTracksCountAsync.hasError)
        () => ref.invalidate(homePendingTracksCountProvider(clientCode)),
      if (assembliesCountAsync.hasError)
        () => ref.invalidate(homeAssembliesCountProvider(clientCode)),
      if (invoicesCountAsync.hasError)
        () => ref.invalidate(invoicesCountProvider(clientCode)),
    ];

    final warehouseTracksCount = tracksCountAsync.asData?.value;
    final pendingTracksCount = pendingTracksCountAsync.asData?.value;
    final tracksCount =
        warehouseTracksCount != null && pendingTracksCount != null
        ? warehouseTracksCount + pendingTracksCount
        : null;
    final assembliesCount = assembliesCountAsync.asData?.value;
    final invoicesCount = invoicesCountAsync.asData?.value;
    final referralData = referralAsync.asData?.value;
    final bonusKgBalance = referralData?.referralKgBalance;
    final agent = clientProfile.asData?.value?.agent;

    final topPad = AppLayout.topBarTotalHeight(context);
    final bottomContentGap = AppLayout.bottomScrollPadding(context) + 16;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final useWideHomeLayout = screenWidth >= 900;
    final horizontalPadding = useWideHomeLayout
        ? AppLayout.horizontalMargin(context)
        : 16.0;

    Future<void> onRefresh() async {
      debugPrint('[Home] pull-to-refresh triggered');
      _checkAndShowTermsDialog(refreshRules: true);
      ref.read(staleDataNoticeProvider.notifier).clear();
      ref.invalidate(clientProfileProvider);
      unawaited(
        ref.read(clientProfileProvider.future).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          debugPrint('[Home] profile refresh failed: $error');
          return null;
        }),
      );
      if (!mounted) return;
      ref.invalidate(tracksDigestProvider(clientCode));
      ref.invalidate(assembliesDigestProvider(clientCode));
      ref.invalidate(invoicesDigestProvider(clientCode));
      ref.invalidate(photosRecentProvider((clientCode: clientCode, limit: 12)));
      ref.invalidate(homeTracksCountProvider(clientCode));
      ref.invalidate(homePendingTracksCountProvider(clientCode));
      ref.invalidate(homeAssembliesCountProvider(clientCode));
      ref.invalidate(invoicesCountProvider(clientCode));
      ref.invalidate(referralProvider);
      ref.invalidate(currentCnyRateProvider);
      try {
        await Future.wait([
          ref.read(tracksDigestProvider(clientCode).future),
          ref.read(assembliesDigestProvider(clientCode).future),
          ref.read(invoicesDigestProvider(clientCode).future),
          ref.read(
            photosRecentProvider((clientCode: clientCode, limit: 12)).future,
          ),
          ref.read(homeTracksCountProvider(clientCode).future),
          ref.read(homePendingTracksCountProvider(clientCode).future),
          ref.read(homeAssembliesCountProvider(clientCode).future),
          ref.read(invoicesCountProvider(clientCode).future),
          ref.read(referralProvider.future),
          ref.read(currentCnyRateProvider.future),
        ]);
      } catch (error) {
        // Each failed provider renders its own error; successful cards remain.
        debugPrint('[Home] partial refresh failed: $error');
      }
    }

    return TutorialScreenWrapper(
      screenKey: 'home',
      steps: [
        TutorialStep(
          icon: Icons.dashboard_rounded,
          title: 'Главная страница',
          description:
              'Здесь собрана ключевая информация: счётчики треков, сборок, счетов и фотоотчётов. Нажмите на любую карточку — перейдёте в нужный раздел.',
          targetKey: _quickCardsKey,
        ),
        TutorialStep(
          icon: Icons.local_shipping_rounded,
          title: 'Последние посылки',
          description:
              'Блок показывает последние треки с текущим статусом. Цветной значок — этап доставки. Нажмите на трек, чтобы увидеть детали.',
          targetKey: _digestKey,
        ),
        TutorialStep(
          icon: Icons.receipt_long_rounded,
          title: 'Счета',
          description:
              'Последние счета на оплату. «Требует оплаты» — посылка ждёт оплаты перед отправкой. «Оплачен» — уже в пути.',
          targetKey: _digestKey,
        ),
        TutorialStep(
          icon: Icons.photo_rounded,
          title: 'Фотоотчёты',
          description:
              'Последние фотографии ваших посылок со склада. Нажмите на фото, чтобы открыть в полном размере.',
          targetKey: _digestKey,
        ),
      ],
      child: RefreshIndicator(
        onRefresh: onRefresh,
        color: context.brandPrimary,
        child: ListView(
          clipBehavior: Clip.none,
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            topPad * 0.7 + 16,
            horizontalPadding,
            0,
          ),
          children: [
            if (_termsRetryAvailable) _termsRetryCard(),
            _HomeReveal(
              order: 0,
              child: useWideHomeLayout
                  ? _WideHeroActionRow(
                      greeting: _GreetingBlock(
                        fullName: clientName,
                        onTap: () => context.push('/profile'),
                      ),
                      action: _AddTracksStatCard(
                        onTap: () => showAddTracksDialog(context, ref),
                      ),
                    )
                  : _GreetingBlock(
                      fullName: clientName,
                      onTap: () => context.push('/profile'),
                    ),
            ),
            const SizedBox(height: 15),
            if ((invoicesCount ?? 0) > 0) ...[
              HomePaymentAttentionCard(
                clientCode: clientCode,
                count: invoicesCount!,
              ),
              const SizedBox(height: 12),
            ],
            const TrainingHomeInvitation(),
            if (useWideHomeLayout) ...[
              _HomeReveal(
                order: 1,
                child: HomeCnyRateCard(
                  rate: currentCnyRateAsync,
                  onRetry: () => ref.invalidate(currentCnyRateProvider),
                ),
              ),
              const SizedBox(height: 15),
            ],
            if (staleNotice != null) ...[
              _HomeReveal(
                order: 1,
                child: _StaleDataBanner(
                  message: staleNotice.message,
                  onRefresh: () => unawaited(onRefresh()),
                  onDismiss: () =>
                      ref.read(staleDataNoticeProvider.notifier).clear(),
                ),
              ),
              const SizedBox(height: 15),
            ],
            if (retryFailed.isNotEmpty) ...[
              MaterialBanner(
                key: const ValueKey('dashboard-load-error'),
                leading: const Icon(Icons.sync_problem_rounded),
                content: Text(
                  tr(
                    context,
                    ru: 'Часть данных не удалось загрузить. Доступные данные показаны ниже.',
                    zh: '部分数据加载失败。已加载的数据仍显示在下方。',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      for (final retry in retryFailed) {
                        retry();
                      }
                    },
                    child: Text(tr(context, ru: 'Повторить', zh: '重试')),
                  ),
                ],
              ),
              const SizedBox(height: 15),
            ],
            _HomeReveal(
              order: 2,
              child: KeyedSubtree(
                key: _quickCardsKey,
                child: _StatsBlock(
                  showAddTracks: !useWideHomeLayout,
                  currentCnyRate: useWideHomeLayout
                      ? null
                      : currentCnyRateAsync,
                  bonusKgValue: _formatKg(bonusKgBalance),
                  tracksValue: _formatCount(tracksCount),
                  pendingTracksValue: _formatCount(pendingTracksCount),
                  warehouseTracksValue: _formatCount(warehouseTracksCount),
                  assembliesValue: _formatCount(assembliesCount),
                  invoicesValue: _formatCount(invoicesCount),
                  onTracksTap: () => context.go('/tracks'),
                  onAssembliesTap: () => context.go('/tracks'),
                  onBonusKgTap: () => context.push('/referral'),
                  onInvoicesTap: () => context.go('/invoices'),
                  onAddTracksTap: () => showAddTracksDialog(context, ref),
                  onCnyRateRetry: () => ref.invalidate(currentCnyRateProvider),
                ),
              ),
            ),
            const SizedBox(height: 15),
            if (agent?.hasHomeBanner == true) ...[
              _HomeReveal(order: 3, child: _PromoSlider(agent: agent!)),
              const SizedBox(height: 15),
            ],
            if (agent?.hasWarehouseContacts == true) ...[
              _HomeReveal(
                order: 4,
                child: useWideHomeLayout
                    ? _WarehouseSearchRow(
                        warehouse: TrainingTarget(
                          id: 'warehouse.address',
                          child: _WarehouseDataBlock(
                            agent: agent!,
                            clientCode: clientCode,
                          ),
                        ),
                        search: _NoCodeSearchCard(onOpen: _openNoCodeSearch),
                      )
                    : TrainingTarget(
                        id: 'warehouse.address',
                        child: _WarehouseDataBlock(
                          agent: agent!,
                          clientCode: clientCode,
                        ),
                      ),
              ),
              const SizedBox(height: 15),
            ],
            if (agent?.hasCompanyContacts == true) ...[
              _HomeReveal(
                order: 5,
                child: HomeAgentContactsCard(agent: agent!),
              ),
              const SizedBox(height: 15),
            ],
            if (agent?.hasWarehouseContacts != true || !useWideHomeLayout) ...[
              _HomeReveal(
                order: 6,
                child: _NoCodeSearchCard(onOpen: _openNoCodeSearch),
              ),
              const SizedBox(height: 15),
            ],
            _HomeReveal(
              order: 7,
              child: KeyedSubtree(
                key: _digestKey,
                child: _DigestBlock(
                  clientCode: clientCode,
                  tracksAsync: tracksDigestAsync,
                  assembliesAsync: assembliesDigestAsync,
                  invoicesAsync: invoicesDigestAsync,
                  photosAsync: recentPhotosAsync,
                  onPhotoTap: (photo) {
                    Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute<void>(
                        fullscreenDialog: true,
                        builder: (_) => PhotoViewerScreen(item: photo),
                      ),
                    );
                  },
                ),
              ),
            ),
            SizedBox(height: bottomContentGap),
          ],
        ),
      ),
    );
  }
}

String _formatCount(int? value) {
  if (value == null) return '–';
  return NumberFormat.decimalPattern('ru_RU').format(value);
}

String _formatKg(double? value) {
  if (value == null) return '–';
  final fixed = value.toStringAsFixed(2);
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}

// На старых Android/Android Go постоянные декоративные анимации слишком дорогие:
// в profile на M2006C3LG они давали непрерывный raster и десятки saveLayer в секунду.
// Оставляем внешний вид статичным, но не гоняем ticker на главной странице.
bool get _useStaticHomeMotion =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

double _compactHomeScale(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width <= 360) return 0.86;
  if (width <= 390) return 0.92;
  return 1.0;
}

// Главная уже была вручную уплотнена под 360dp. После глобального compact
// text scale компенсируем только fontSize, чтобы визуально не сжать её дважды.
double _compactHomeFontScale(BuildContext context) {
  final globalTextScale = AppLayout.compactTextScale(context);
  if (globalTextScale == 0) return _compactHomeScale(context);
  return _compactHomeScale(context) / globalTextScale;
}

class _HomeReveal extends StatefulWidget {
  final int order;
  final Widget child;

  const _HomeReveal({required this.order, required this.child});

  @override
  State<_HomeReveal> createState() => _HomeRevealState();
}

class _HomeRevealState extends State<_HomeReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(curve);
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.045),
      end: Offset.zero,
    ).animate(curve);

    if (_useStaticHomeMotion) {
      _controller.value = 1;
    } else {
      Future<void>.delayed(Duration(milliseconds: 55 * widget.order), () {
        if (!mounted) return;
        _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

class _StaleDataBanner extends StatelessWidget {
  const _StaleDataBanner({
    required this.message,
    required this.onRefresh,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onRefresh;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    const warning = Color(0xFFF59E0B);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: warning.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.sync_problem_rounded, color: warning, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Данные могут быть не свежими',
                    style: TextStyle(
                      color: Color(0xFF7C2D12),
                      fontFamily: 'Gilroy',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    style: const TextStyle(
                      color: Color(0xFF9A3412),
                      fontFamily: 'Gilroy',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onRefresh,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF9A3412),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text(
                      'Обновить',
                      style: TextStyle(
                        fontFamily: 'Gilroy',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: const Icon(
                Icons.close_rounded,
                color: Color(0xFF9A3412),
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GreetingBlock extends StatelessWidget {
  final String fullName;
  final VoidCallback onTap;

  const _GreetingBlock({required this.fullName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final greeting = _greetingFor(DateTime.now());
    final scale = _compactHomeScale(context);
    final textScale = _compactHomeFontScale(context);
    final radius = BorderRadius.circular(24 * scale);
    final nameFontSize = 28 * textScale;
    final nameLineHeight = 34 * textScale;
    final headerIconSize = 46 * scale;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        label: 'Открыть профиль',
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            splashColor: Colors.white.withValues(alpha: 0.08),
            highlightColor: Colors.white.withValues(alpha: 0.04),
            child: Ink(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    context.brandPrimary.withValues(alpha: 0.98),
                    context.brandSecondary.withValues(alpha: 0.9),
                  ],
                ),
                borderRadius: radius,
                boxShadow: [
                  BoxShadow(
                    color: context.brandPrimary.withValues(alpha: 0.22),
                    offset: const Offset(0, 14),
                    blurRadius: 32,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: Stack(
                  children: [
                    const Positioned.fill(child: _HeaderGlowBackdrop()),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        16 * scale,
                        15 * scale,
                        16 * scale,
                        13 * scale,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      greeting,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.86,
                                        ),
                                        fontFamily: 'Gilroy',
                                        fontSize: 15 * textScale,
                                        fontWeight: FontWeight.w600,
                                        height: 1.2,
                                      ),
                                    ),
                                    SizedBox(height: 6 * scale),
                                    SizedBox(
                                      height: nameLineHeight,
                                      child: _OverflowMarqueeText(
                                        text: fullName,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontFamily: 'Gilroy',
                                          fontSize: nameFontSize,
                                          fontWeight: FontWeight.w900,
                                          height: nameLineHeight / nameFontSize,
                                          letterSpacing: -0.4 * textScale,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: 12 * scale),
                              _PulsingHeaderIcon(size: headerIconSize),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _greetingFor(DateTime now) {
    final h = now.hour;
    if (h >= 5 && h < 12) return 'Доброе утро';
    if (h >= 12 && h < 17) return 'Добрый день';
    if (h >= 17 && h < 23) return 'Добрый вечер';
    return 'Доброй ночи';
  }
}

class _HeaderGlowBackdrop extends StatefulWidget {
  const _HeaderGlowBackdrop();

  @override
  State<_HeaderGlowBackdrop> createState() => _HeaderGlowBackdropState();
}

class _HeaderGlowBackdropState extends State<_HeaderGlowBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5600),
    );
    if (_useStaticHomeMotion) {
      _controller.value = 0.5;
    } else {
      _controller.repeat(reverse: true);
      _settleAfter(const Duration(seconds: 9));
    }
  }

  void _settleAfter(Duration activeFor) {
    Future<void>.delayed(activeFor, () {
      if (!mounted || !_controller.isAnimating) return;
      _controller.animateTo(
        0.5,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final wave = Curves.easeInOutCubic.transform(_controller.value);
            final shift = (wave * 2) - 1;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  right: -62,
                  top: -58,
                  child: Transform.translate(
                    offset: Offset(-10 * shift, 6 * shift),
                    child: _HeaderGlowCircle(
                      size: 154,
                      color: Colors.white.withValues(alpha: 0.13),
                    ),
                  ),
                ),
                Positioned(
                  right: 22,
                  bottom: -68,
                  child: Transform.translate(
                    offset: Offset(9 * shift, -7 * shift),
                    child: _HeaderGlowCircle(
                      size: 152,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                Positioned(
                  right: -14,
                  bottom: 16,
                  child: Transform.translate(
                    offset: Offset(5 * shift, -4 * shift),
                    child: _HeaderGlowCircle(
                      size: 82,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeaderGlowCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _HeaderGlowCircle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _PulsingHeaderIcon extends StatefulWidget {
  final double size;

  const _PulsingHeaderIcon({this.size = 46});

  @override
  State<_PulsingHeaderIcon> createState() => _PulsingHeaderIconState();
}

class _PulsingHeaderIconState extends State<_PulsingHeaderIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (_useStaticHomeMotion) {
      _controller.value = 0.5;
    } else {
      _controller.repeat(reverse: true);
      _settleAfter(const Duration(seconds: 7));
    }
    _scale = Tween<double>(
      begin: 0.96,
      end: 1.04,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  void _settleAfter(Duration activeFor) {
    Future<void>.delayed(activeFor, () {
      if (!mounted || !_controller.isAnimating) return;
      _controller.animateTo(
        0.5,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(widget.size * 0.35),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: Icon(
          Icons.local_shipping_rounded,
          color: Colors.white,
          size: widget.size * 0.54,
        ),
      ),
    );
  }
}

class _OverflowMarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _OverflowMarqueeText({required this.text, required this.style});

  @override
  State<_OverflowMarqueeText> createState() => _OverflowMarqueeTextState();
}

class _OverflowMarqueeTextState extends State<_OverflowMarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _lastOverflow = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant _OverflowMarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _lastOverflow = 0;
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncAnimation(double overflow) {
    if (overflow <= 0 || _useStaticHomeMotion) {
      if (_controller.isAnimating || _controller.value != 0) {
        _controller.stop();
        _controller.value = 0;
      }
      return;
    }

    if ((_lastOverflow - overflow).abs() < 0.5 && _controller.isAnimating) {
      return;
    }

    _lastOverflow = overflow;
    final durationMs = (2800 + overflow * 18).clamp(3200, 8000).round();
    _controller.duration = Duration(milliseconds: durationMs);
    _controller.repeat(reverse: true);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final direction = Directionality.of(context);
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: direction,
        )..layout();
        final textWidth = painter.width;
        final overflow = textWidth - constraints.maxWidth;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncAnimation(overflow);
        });

        if (overflow <= 0 || _useStaticHomeMotion) {
          return Text(
            widget.text,
            maxLines: 1,
            overflow: _useStaticHomeMotion
                ? TextOverflow.ellipsis
                : TextOverflow.visible,
            softWrap: false,
            style: widget.style,
          );
        }

        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final eased = Curves.easeInOut.transform(_controller.value);
              return Transform.translate(
                offset: Offset(-overflow * eased, 0),
                child: child,
              );
            },
            child: SizedBox(
              width: textWidth,
              child: Text(
                widget.text,
                maxLines: 1,
                overflow: TextOverflow.visible,
                softWrap: false,
                style: widget.style,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PromoSlider extends StatelessWidget {
  const _PromoSlider({required this.agent});

  final AgentInfo agent;

  static const _textColor = Color(0xFF2F2F2F);
  static const _designWidth = 400.0;
  static const _designHeight = 149.0;
  static const _textBlockWidth = 230.0;

  @override
  Widget build(BuildContext context) {
    final imageUrl = _textOrNull(agent.homeBannerImageUrl);
    final resolvedImageUrl = imageUrl == null
        ? null
        : ApiConfig.getMediaUrl(imageUrl);
    final eyebrow = _textOrNull(agent.homeBannerEyebrow);
    final title = _textOrNull(agent.homeBannerTitle);
    final description = _textOrNull(agent.homeBannerDescription);

    if (imageUrl == null &&
        eyebrow == null &&
        title == null &&
        description == null) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final rawScale = width / _designWidth;
        final useCompactDesktopBanner = AppLayout.useSideNavigation(context);
        final scale = useCompactDesktopBanner
            ? rawScale.clamp(1.0, 1.35).toDouble()
            : rawScale;
        final bannerHeight =
            _designHeight *
            (useCompactDesktopBanner ? rawScale * 0.5 : rawScale);
        final radius = BorderRadius.circular(10 * scale);
        final maxTextWidth = (_textBlockWidth * scale)
            .clamp(0.0, width)
            .toDouble();
        final minTextWidth = maxTextWidth <= 0
            ? 0.0
            : (180.0 * scale).clamp(0.0, maxTextWidth).toDouble();
        final desiredTextWidth = width * 0.45;
        final textWidth = maxTextWidth <= minTextWidth
            ? maxTextWidth
            : desiredTextWidth.clamp(minTextWidth, maxTextWidth).toDouble();

        return SizedBox(
          width: width,
          height: bannerHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: const Color(0x1A000000),
                  offset: Offset(3 * scale, 4 * scale),
                  blurRadius: 25 * scale,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: imageUrl == null
                        ? const ColoredBox(color: Color(0xCCFFFFFF))
                        : RepaintBoundary(
                            child: AuthenticatedImage.network(
                              resolvedImageUrl!,
                              fit: BoxFit.cover,
                              alignment: Alignment.centerLeft,
                              gaplessPlayback: true,
                              filterQuality: FilterQuality.low,
                              errorBuilder: (_, error, _) {
                                if (kDebugMode) {
                                  debugPrint(
                                    '[Home] Banner image failed: '
                                    '$resolvedImageUrl $error',
                                  );
                                }
                                return const ColoredBox(
                                  color: Color(0xCCFFFFFF),
                                );
                              },
                            ),
                          ),
                  ),
                  SizedBox(
                    height: bannerHeight,
                    width: width,
                    child: Padding(
                      padding: EdgeInsets.all(10 * scale),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (eyebrow != null)
                            SizedBox(
                              width: textWidth,
                              child: Text(
                                eyebrow,
                                style: TextStyle(
                                  color: _textColor,
                                  fontFamily: 'Gilroy',
                                  fontWeight: FontWeight.w300,
                                  fontSize: 13.6 * scale,
                                  height: 16 / 13.6,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                          if (eyebrow != null && title != null)
                            SizedBox(height: 10 * scale),
                          if (title != null)
                            SizedBox(
                              width: textWidth,
                              child: Text(
                                title,
                                style: TextStyle(
                                  color: _textColor,
                                  fontFamily: 'Gilroy',
                                  fontWeight: FontWeight.w500,
                                  fontSize: 18.6 * scale,
                                  height: 23 / 18.6,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                          if ((eyebrow != null || title != null) &&
                              description != null)
                            SizedBox(height: 10 * scale),
                          if (description != null)
                            SizedBox(
                              width: textWidth,
                              child: Text(
                                description,
                                style: TextStyle(
                                  color: _textColor,
                                  fontFamily: 'Gilroy',
                                  fontWeight: FontWeight.w400,
                                  fontSize: 13.6 * scale,
                                  height: 16 / 13.6,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String? _textOrNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class _WideHeroActionRow extends StatelessWidget {
  final Widget greeting;
  final Widget action;

  const _WideHeroActionRow({required this.greeting, required this.action});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 136,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 7, child: greeting),
          const SizedBox(width: 14),
          Expanded(flex: 5, child: action),
        ],
      ),
    );
  }
}

class _StatsBlock extends StatelessWidget {
  final bool showAddTracks;
  final AsyncValue<CurrentCnyRate?>? currentCnyRate;
  final String bonusKgValue;
  final String tracksValue;
  final String pendingTracksValue;
  final String warehouseTracksValue;
  final String assembliesValue;
  final String invoicesValue;
  final VoidCallback onTracksTap;
  final VoidCallback onAssembliesTap;
  final VoidCallback onBonusKgTap;
  final VoidCallback onInvoicesTap;
  final VoidCallback onAddTracksTap;
  final VoidCallback onCnyRateRetry;

  const _StatsBlock({
    this.showAddTracks = true,
    this.currentCnyRate,
    required this.bonusKgValue,
    required this.tracksValue,
    required this.pendingTracksValue,
    required this.warehouseTracksValue,
    required this.assembliesValue,
    required this.invoicesValue,
    required this.onTracksTap,
    required this.onAssembliesTap,
    required this.onBonusKgTap,
    required this.onInvoicesTap,
    required this.onAddTracksTap,
    required this.onCnyRateRetry,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showAddTracks) ...[
        _AddTracksStatCard(onTap: onAddTracksTap),
        const SizedBox(height: 8),
      ],
      if (currentCnyRate != null) ...[
        HomeCnyRateCard(rate: currentCnyRate!, onRetry: onCnyRateRetry),
        const SizedBox(height: 8),
      ],
      HomeStatsGrid(
        tracksValue: tracksValue,
        pendingTracksValue: pendingTracksValue,
        warehouseTracksValue: warehouseTracksValue,
        assembliesValue: assembliesValue,
        invoicesValue: invoicesValue,
        bonusKgValue: bonusKgValue,
        onTracksTap: onTracksTap,
        onAssembliesTap: onAssembliesTap,
        onInvoicesTap: onInvoicesTap,
        onBonusKgTap: onBonusKgTap,
      ),
    ],
  );
}

class _AddTracksStatCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AddTracksStatCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scale = _compactHomeScale(context);
    final textScale = _compactHomeFontScale(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: 78 * scale),
          padding: EdgeInsets.fromLTRB(
            14 * scale,
            14 * scale,
            14 * scale,
            14 * scale,
          ),
          decoration: BoxDecoration(
            gradient: context.brandGradient,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: context.brandPrimary.withValues(alpha: 0.24),
                offset: const Offset(0, 12),
                blurRadius: 28,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48 * scale,
                height: 48 * scale,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16 * scale),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                child: Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: 30 * scale,
                ),
              ),
              SizedBox(width: 12 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Добавить треки',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'Gilroy',
                        fontWeight: FontWeight.w900,
                        fontSize: 18 * textScale,
                        height: 1.1,
                      ),
                    ),
                    SizedBox(height: 4 * scale),
                    Text(
                      'Вставьте номера — мы начнём отслеживание',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xE6FFFFFF),
                        fontFamily: 'Gilroy',
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5 * textScale,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 10 * scale),
              _NudgingArrowIcon(size: 24 * scale),
            ],
          ),
        ),
      ),
    );
  }
}

class _NudgingArrowIcon extends StatefulWidget {
  final double size;

  const _NudgingArrowIcon({this.size = 24});

  @override
  State<_NudgingArrowIcon> createState() => _NudgingArrowIconState();
}

class _NudgingArrowIconState extends State<_NudgingArrowIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
    if (_useStaticHomeMotion) {
      _controller.value = 0;
    } else {
      _controller.repeat(reverse: true);
      _settleAfter(const Duration(seconds: 6));
    }
    _offset = Tween<double>(begin: 0, end: 5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
  }

  void _settleAfter(Duration activeFor) {
    Future<void>.delayed(activeFor, () {
      if (!mounted || !_controller.isAnimating) return;
      _controller.animateTo(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offset,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_offset.value, 0),
          child: child,
        );
      },
      child: Icon(
        Icons.arrow_forward_rounded,
        color: Colors.white,
        size: widget.size,
      ),
    );
  }
}

class _WarehouseSearchRow extends StatelessWidget {
  final Widget warehouse;
  final Widget search;

  const _WarehouseSearchRow({required this.warehouse, required this.search});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final warehousePaneWidth = (constraints.maxWidth - 14) * 0.6;
        // _WarehouseDataBlock decides whether to stack controls by its inner
        // LayoutBuilder width. Account for the card padding here; otherwise
        // iPad side-nav can get a compact 142px row while warehouse controls
        // are already vertical and need the taller row.
        final warehouseControlsWidth = warehousePaneWidth - 28;
        final needsStackedWarehouseControls = warehouseControlsWidth < 620;
        final rowHeight = needsStackedWarehouseControls
            ? 260.0
            : constraints.maxWidth >= 1050
            ? 142.0
            : 188.0;

        return SizedBox(
          height: rowHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 6, child: warehouse),
              const SizedBox(width: 14),
              Expanded(flex: 4, child: search),
            ],
          ),
        );
      },
    );
  }
}

class _WarehouseDataBlock extends StatefulWidget {
  final String clientCode;
  final AgentInfo agent;

  const _WarehouseDataBlock({required this.clientCode, required this.agent});

  @override
  State<_WarehouseDataBlock> createState() => _WarehouseDataBlockState();
}

class _WarehouseDataBlockState extends State<_WarehouseDataBlock> {
  Timer? _highlightTimer;
  bool _highlightChecker = false;

  @override
  void dispose() {
    _highlightTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final address = _warehouseAddressForClient(widget.agent.warehouseAddress);
    final phone = widget.agent.warehousePhone?.trim() ?? '';
    void openAddressChecker() => showWarehouseAddressChecker(
      context,
      expected: WarehouseAddressCheckData(
        clientCode: widget.clientCode,
        address: address,
        phone: phone,
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            offset: const Offset(0, 10),
            blurRadius: 26,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: context.brandPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.warehouse_rounded,
                  color: context.brandPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Склад и маркировка',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Gilroy',
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        height: 1.15,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Скопируйте данные для отправки товара',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontFamily: 'Gilroy',
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final controls = <Widget>[
                _WarehouseCodeTile(clientCode: widget.clientCode),
                if (address.isNotEmpty)
                  TrainingTarget(
                    id: 'warehouse.copy-address',
                    child: _WarehouseCopyButton(
                      label: 'Адрес склада',
                      icon: CupertinoIcons.doc_on_doc,
                      value: address,
                      showMarketplaceNotice: true,
                      onMarketplaceNoticeClosed: _highlightCheckerButton,
                    ),
                  ),
                if (phone.isNotEmpty)
                  TrainingTarget(
                    id: 'warehouse.copy-phone',
                    child: _WarehouseCopyButton(
                      label: 'Телефон склада',
                      icon: CupertinoIcons.phone,
                      value: phone,
                    ),
                  ),
              ];
              final useSingleRow = constraints.maxWidth >= 620;

              if (!useSingleRow || controls.length == 1) {
                return Column(
                  children: [
                    controls.first,
                    if (controls.length > 1) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (var i = 1; i < controls.length; i++) ...[
                            if (i > 1) const SizedBox(width: 8),
                            Expanded(child: controls[i]),
                          ],
                        ],
                      ),
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  for (var i = 0; i < controls.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(flex: i == 0 ? 5 : 4, child: controls[i]),
                  ],
                ],
              );
            },
          ),
          if (address.isNotEmpty) ...[
            const SizedBox(height: 8),
            TrainingTarget(
              id: 'warehouse.check',
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOut,
                padding: EdgeInsets.all(_highlightChecker ? 4 : 0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(19),
                  color: _highlightChecker
                      ? context.brandPrimary.withValues(alpha: 0.14)
                      : Colors.transparent,
                  boxShadow: _highlightChecker
                      ? [
                          BoxShadow(
                            color: context.brandPrimary.withValues(alpha: 0.3),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ]
                      : const [],
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: openAddressChecker,
                    icon: const Icon(Icons.fact_check_outlined, size: 19),
                    label: const Text('Проверить заполнение'),
                    style: FilledButton.styleFrom(
                      backgroundColor: context.brandPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      elevation: 0,
                      textStyle: const TextStyle(
                        fontFamily: 'Gilroy',
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _warehouseAddressForClient(String? rawAddress) {
    final base = (rawAddress ?? '')
        .replaceFirst(RegExp(r'\s*\(不要隐藏代码\s*[^)]*\)\s*$'), '')
        .trim();
    if (base.isEmpty) return '';
    return '$base(不要隐藏代码 ${widget.clientCode})';
  }

  void _highlightCheckerButton() {
    if (!mounted) return;
    _highlightTimer?.cancel();
    setState(() => _highlightChecker = true);
    _highlightTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _highlightChecker = false);
    });
  }
}

class _WarehouseCodeTile extends StatelessWidget {
  final String clientCode;

  const _WarehouseCodeTile({required this.clientCode});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
      ),
      child: Row(
        children: [
          Icon(Icons.qr_code_2_rounded, color: context.brandPrimary, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Код клиента: '),
                  TextSpan(
                    text: clientCode,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontFamily: 'Gilroy',
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarehouseCopyButton extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final bool showMarketplaceNotice;
  final VoidCallback? onMarketplaceNoticeClosed;

  const _WarehouseCopyButton({
    required this.label,
    required this.icon,
    required this.value,
    this.showMarketplaceNotice = false,
    this.onMarketplaceNoticeClosed,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 360;
    return Material(
      color: context.brandPrimary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => _copyValue(context),
        child: Container(
          height: 44,
          padding: EdgeInsets.symmetric(horizontal: compact ? 3 : 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: context.brandPrimary.withValues(alpha: 0.12),
            ),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: context.brandPrimary, size: compact ? 16 : 17),
              SizedBox(width: compact ? 4 : 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.brandPrimary,
                    fontFamily: 'Gilroy',
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 12 : 13.5,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyValue(BuildContext context) async {
    final copied = await AppClipboard.copyText(value);
    if (!context.mounted) return;
    if (!copied) {
      _showStyledSnackBar(context, 'Не удалось скопировать', isError: true);
      return;
    }
    HapticFeedback.selectionClick();
    if (showMarketplaceNotice) {
      await showWarehouseAddressCopyBanner(context);
      if (!context.mounted) return;
      onMarketplaceNoticeClosed?.call();
      return;
    }
    _showStyledSnackBar(context, '$label скопирован');
  }
}

class _NoCodeSearchCard extends StatelessWidget {
  final VoidCallback onOpen;

  const _NoCodeSearchCard({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, 8),
            blurRadius: 22,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: context.brandPrimary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.manage_search_rounded,
                  color: context.brandPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Товары без кода клиента',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Gilroy',
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Эти товары не обязательно ваши, поэтому проверяйте логистику в вашем приложении',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontFamily: 'Gilroy',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: onOpen,
              style: FilledButton.styleFrom(
                backgroundColor: context.brandPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Перейти',
                style: TextStyle(
                  fontFamily: 'Gilroy',
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _DigestTab {
  tracks('Треки', Icons.local_shipping_rounded),
  assemblies('Сборки', Icons.inventory_2_rounded),
  invoices('Счета', Icons.receipt_long_rounded),
  photos('Фото', Icons.photo_library_rounded);

  final String label;
  final IconData icon;

  const _DigestTab(this.label, this.icon);
}

class _DigestBlock extends StatefulWidget {
  final String clientCode;
  final AsyncValue<List<TrackItem>> tracksAsync;
  final AsyncValue<List<AssemblyItem>> assembliesAsync;
  final AsyncValue<List<InvoiceItem>> invoicesAsync;
  final AsyncValue<List<PhotoItem>> photosAsync;
  final ValueChanged<PhotoItem> onPhotoTap;

  const _DigestBlock({
    required this.clientCode,
    required this.tracksAsync,
    required this.assembliesAsync,
    required this.invoicesAsync,
    required this.photosAsync,
    required this.onPhotoTap,
  });

  @override
  State<_DigestBlock> createState() => _DigestBlockState();
}

class _DigestBlockState extends State<_DigestBlock> {
  _DigestTab _selected = _DigestTab.tracks;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            offset: const Offset(0, 10),
            blurRadius: 26,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Последние обновления',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Gilroy',
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Треки, сборки, счета и фото в одном месте',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontFamily: 'Gilroy',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          _DigestTabBar(
            selected: _selected,
            onChanged: (tab) => setState(() => _selected = tab),
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: KeyedSubtree(
              key: ValueKey(_selected),
              child: switch (_selected) {
                _DigestTab.tracks => _TrackDigestList(
                  clientCode: widget.clientCode,
                  itemsAsync: widget.tracksAsync,
                ),
                _DigestTab.assemblies => _AssemblyDigestList(
                  clientCode: widget.clientCode,
                  itemsAsync: widget.assembliesAsync,
                ),
                _DigestTab.invoices => _InvoiceDigestList(
                  clientCode: widget.clientCode,
                  itemsAsync: widget.invoicesAsync,
                ),
                _DigestTab.photos => _PhotoDigestGrid(
                  itemsAsync: widget.photosAsync,
                  onTap: widget.onPhotoTap,
                ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DigestTabBar extends StatelessWidget {
  final _DigestTab selected;
  final ValueChanged<_DigestTab> onChanged;

  const _DigestTabBar({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (var i = 0; i < _DigestTab.values.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _DigestTabButton(
              tab: _DigestTab.values[i],
              selected: selected == _DigestTab.values[i],
              onTap: () => onChanged(_DigestTab.values[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _DigestTabButton extends StatelessWidget {
  final _DigestTab tab;
  final bool selected;
  final VoidCallback onTap;

  const _DigestTabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : AppColors.textPrimary;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? context.brandPrimary : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? context.brandPrimary
                  : Colors.black.withValues(alpha: 0.04),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(tab.icon, size: 16, color: foreground),
              const SizedBox(width: 6),
              Text(
                tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontFamily: 'Gilroy',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackDigestList extends ConsumerWidget {
  final String clientCode;
  final AsyncValue<List<TrackItem>> itemsAsync;

  const _TrackDigestList({required this.clientCode, required this.itemsAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return itemsAsync.when(
      loading: () => const _DigestStateCard(child: CircularProgressIndicator()),
      error: (e, _) => _DigestStateCard(
        child: Text(
          tr(context, ru: 'Не удалось загрузить треки', zh: '无法加载运单'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.red),
        ),
      ),
      data: (items) {
        final top = items.take(10).toList(growable: false);
        if (top.isEmpty) {
          return const _DigestStateCard(child: Text('Пока нет треков.'));
        }

        return _DigestListColumn(
          children: [
            for (final track in top)
              TracksScreen.embedded(
                tracks: [track],
                onEmbeddedChanged: () =>
                    ref.invalidate(tracksDigestProvider(clientCode)),
              ),
          ],
        );
      },
    );
  }
}

class _AssemblyDigestList extends StatelessWidget {
  final String clientCode;
  final AsyncValue<List<AssemblyItem>> itemsAsync;

  const _AssemblyDigestList({
    required this.clientCode,
    required this.itemsAsync,
  });

  @override
  Widget build(BuildContext context) {
    return itemsAsync.when(
      loading: () => const _DigestStateCard(child: CircularProgressIndicator()),
      error: (e, _) => _DigestStateCard(
        child: Text(
          tr(context, ru: 'Не удалось загрузить сборки', zh: '无法加载集运包裹'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.red),
        ),
      ),
      data: (items) {
        final top = items.take(10).toList(growable: false);
        if (top.isEmpty) {
          return const _DigestStateCard(child: Text('Пока нет сборок.'));
        }

        return _DigestListColumn(
          children: [
            for (final assembly in top)
              _AssemblyDigestEntry(clientCode: clientCode, assembly: assembly),
          ],
        );
      },
    );
  }
}

class _AssemblyDigestEntry extends ConsumerWidget {
  final String clientCode;
  final AssemblyItem assembly;

  const _AssemblyDigestEntry({
    required this.clientCode,
    required this.assembly,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(
      tracksListProvider(
        TracksListParams(
          clientCode: clientCode,
          assemblyId: assembly.id.toString(),
          take: 200,
        ),
      ),
    );

    return tracksAsync.when(
      loading: () => const _DigestStateCard(child: CircularProgressIndicator()),
      error: (error, _) => _DigestStateCard(
        child: Text(
          'Не удалось загрузить сборку: $error',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.red),
        ),
      ),
      data: (tracks) => tracks.isEmpty
          ? const _DigestStateCard(child: Text('В сборке пока нет треков.'))
          : TracksScreen.embedded(
              tracks: tracks,
              asAssembly: true,
              onEmbeddedChanged: () {
                ref.invalidate(assembliesDigestProvider(clientCode));
                ref.invalidate(
                  tracksListProvider(
                    TracksListParams(
                      clientCode: clientCode,
                      assemblyId: assembly.id.toString(),
                      take: 200,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _InvoiceDigestList extends StatelessWidget {
  final String clientCode;
  final AsyncValue<List<InvoiceItem>> itemsAsync;

  const _InvoiceDigestList({
    required this.clientCode,
    required this.itemsAsync,
  });

  @override
  Widget build(BuildContext context) {
    return itemsAsync.when(
      loading: () => const _DigestStateCard(child: CircularProgressIndicator()),
      error: (e, _) => _DigestStateCard(
        child: Text(
          tr(context, ru: 'Не удалось загрузить счета', zh: '无法加载账单'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.red),
        ),
      ),
      data: (items) {
        final top = items.take(10).toList(growable: false);
        if (top.isEmpty) {
          return const _DigestStateCard(child: Text('Пока нет счетов.'));
        }

        return _DigestListColumn(
          children: [
            for (final invoice in top)
              ClientInvoiceTile(item: invoice, clientCode: clientCode),
          ],
        );
      },
    );
  }
}

class _PhotoDigestGrid extends StatelessWidget {
  final AsyncValue<List<PhotoItem>> itemsAsync;
  final ValueChanged<PhotoItem> onTap;

  const _PhotoDigestGrid({required this.itemsAsync, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return itemsAsync.when(
      loading: () => const _DigestStateCard(child: CircularProgressIndicator()),
      error: (e, _) => _DigestStateCard(
        child: Text(
          'Не удалось загрузить фото: $e',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.red),
        ),
      ),
      data: (items) {
        final top = items.take(12).toList(growable: false);
        if (top.isEmpty) {
          return const _DigestStateCard(child: Text('Пока нет фотоотчётов.'));
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900 ? 5 : 3;
            final spacing = 8.0;
            final tileSize =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final item in top)
                  SizedBox(
                    width: tileSize,
                    height: tileSize,
                    child: _PhotoThumb(item: item, onOpen: () => onTap(item)),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _DigestListColumn extends StatelessWidget {
  final List<Widget> children;

  const _DigestListColumn({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          const spacing = 8.0;
          final tileWidth = (constraints.maxWidth - spacing) / 2;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final child in children)
                SizedBox(width: tileWidth, child: child),
            ],
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 5),
              children[i],
            ],
          ],
        );
      },
    );
  }
}

class _DigestStateCard extends StatelessWidget {
  final Widget child;

  const _DigestStateCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 92),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  final PhotoItem item;
  final VoidCallback onOpen;

  const _PhotoThumb({required this.item, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary предотвращает перерисовку при скролле
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onOpen,
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (item.isVideo)
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.black.withValues(alpha: 0.45),
                              Colors.black.withValues(alpha: 0.15),
                            ],
                          ),
                        ),
                      )
                    else
                      AppCachedMediaImage(
                        url: item.url,
                        thumbnailSize: 360,
                        maxHeightDiskCache: 400,
                        maxWidthDiskCache: 400,
                        memCacheHeight: 200,
                        memCacheWidth: 200,
                        imageBuilder: (_, imageProvider) => DecoratedBox(
                          decoration: BoxDecoration(
                            image: DecorationImage(
                              image: imageProvider,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        placeholder: (_, _) => Container(
                          color: Colors.black.withValues(alpha: 0.06),
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (_, _, _) => AppCachedMediaImage(
                          url: item.url,
                          variant: AppMediaImageVariant.full,
                          fit: BoxFit.cover,
                          maxHeightDiskCache: 400,
                          maxWidthDiskCache: 400,
                          memCacheHeight: 200,
                          memCacheWidth: 200,
                          placeholder: (_, _) => Container(
                            color: Colors.black.withValues(alpha: 0.06),
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          errorWidget: (_, _, _) => Container(
                            color: Colors.black.withValues(alpha: 0.06),
                            child: const Center(
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                      ),
                    if (item.isVideo)
                      const Center(
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Диалог принятия правил оказания услуг при первом входе
class _TermsAcceptanceDialog extends ConsumerStatefulWidget {
  const _TermsAcceptanceDialog({required this.snapshot});
  final ClientTermsSnapshot snapshot;
  @override
  ConsumerState<_TermsAcceptanceDialog> createState() =>
      _TermsAcceptanceDialogState();
}

class _TermsAcceptanceDialogState
    extends ConsumerState<_TermsAcceptanceDialog> {
  bool _submitting = false;
  bool _versionChanged = false;
  String? _error;
  TermsIdentity get identity => widget.snapshot.identity;
  @override
  Widget build(BuildContext context) {
    final companyName = ref.watch(companyNameProvider);

    return PopScope(
      canPop: false, // Запрещаем закрытие диалога свайпом или кнопкой "назад"
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero, // Убираем отступы по бокам
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: 24,
          ), // Добавляем margin вместо insetPadding
          constraints: const BoxConstraints(maxWidth: 500),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Заголовок с иконкой
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.brandPrimary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          Icons.description_rounded,
                          size: 48,
                          color: context.brandPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Добро пожаловать!',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1A1A1A),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                // Контент (скроллируемый)
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Прежде чем продолжить',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A1A),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Для использования приложения необходимо ознакомиться и принять правила оказания услуг компании $companyName.',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade700,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          tr(
                            context,
                            ru: 'Версия правил: ${identity.displayVersion}',
                            zh: '规则版本：${identity.displayVersion}',
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (identity.updatedAt != null)
                          Text(
                            tr(
                              context,
                              ru: 'Обновлены ${DateFormat("dd.MM.yyyy").format(identity.updatedAt!.toLocal())}',
                              zh: '更新日期 ${DateFormat("yyyy.MM.dd").format(identity.updatedAt!.toLocal())}',
                            ),
                            textAlign: TextAlign.center,
                          ),
                        const SizedBox(height: 24),

                        // Блок с основными пунктами
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.grey.shade200,
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildInfoItem(
                                icon: Icons.check_circle_outline_rounded,
                                text: 'Условия оказания услуг',
                                color: context.brandPrimary,
                              ),
                              const SizedBox(height: 12),
                              _buildInfoItem(
                                icon: Icons.verified_user_outlined,
                                text: 'Права и обязанности клиентов',
                                color: context.brandPrimary,
                              ),
                              const SizedBox(height: 12),
                              _buildInfoItem(
                                icon: Icons.inventory_2_outlined,
                                text: 'Правила упаковки и маркировки',
                                color: context.brandPrimary,
                              ),
                              const SizedBox(height: 12),
                              _buildInfoItem(
                                icon: Icons.policy_outlined,
                                text: 'Порядок работы и процедуры',
                                color: context.brandPrimary,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Кнопка "Ознакомиться с правилами"
                        OutlinedButton.icon(
                          onPressed: _submitting
                              ? null
                              : () async {
                                  // Открываем правила поверх диалога
                                  await showBlurredModalBottomSheet<void>(
                                    context: context,
                                    useRootNavigator: true,
                                    isScrollControlled: true,
                                    builder: (_) => TermsDocumentSheet(
                                      snapshot: widget.snapshot,
                                    ),
                                  );
                                  // После возврата пользователь снова видит диалог
                                },
                          icon: const Icon(Icons.article_outlined, size: 20),
                          label: const Text('Ознакомиться с правилами'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.brandPrimary,
                            side: BorderSide(
                              color: context.brandPrimary,
                              width: 2,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        // Кнопка "Соглашаюсь"
                        FilledButton.icon(
                          onPressed: _submitting
                              ? null
                              : () async {
                                  if (_versionChanged) {
                                    Navigator.of(context).pop(true);
                                    return;
                                  }
                                  final auth = ref.read(authProvider);
                                  if (auth.clientId != identity.clientId ||
                                      ref.read(clientAgentIdProvider) !=
                                          identity.agentId) {
                                    Navigator.of(context).pop(true);
                                    return;
                                  }
                                  setState(() {
                                    _submitting = true;
                                    _error = null;
                                  });
                                  try {
                                    await ref
                                        .read(clientTermsServiceProvider)
                                        .accept(widget.snapshot);
                                    if (!context.mounted) return;
                                    final current = ref.read(authProvider);
                                    ref.invalidate(clientTermsSnapshotProvider);
                                    if (current.clientId != identity.clientId ||
                                        ref.read(clientAgentIdProvider) !=
                                            identity.agentId) {
                                      Navigator.of(context).pop(true);
                                      return;
                                    }
                                    Navigator.of(context).pop(false);
                                  } on TermsVersionChanged {
                                    if (!context.mounted) return;
                                    setState(() {
                                      _versionChanged = true;
                                      _error = tr(
                                        context,
                                        ru: 'Правила обновились. Загрузите и прочитайте актуальную версию.',
                                        zh: '规则已更新，请加载并阅读最新版本。',
                                      );
                                    });
                                  } on TermsAccountChanged {
                                    if (context.mounted) {
                                      Navigator.of(context).pop(true);
                                    }
                                  } catch (_) {
                                    if (!context.mounted) return;
                                    setState(
                                      () => _error = tr(
                                        context,
                                        ru: 'Не удалось сохранить принятие правил на сервере. Проверьте соединение и повторите.',
                                        zh: '无法将规则确认保存到服务器，请检查网络后重试。',
                                      ),
                                    );
                                  } finally {
                                    if (mounted) {
                                      setState(() => _submitting = false);
                                    }
                                  }
                                },
                          icon: const Icon(Icons.done_rounded, size: 22),
                          label: Text(
                            tr(
                              context,
                              ru: _submitting
                                  ? 'Сохраняем…'
                                  : _versionChanged
                                  ? 'Обновить правила'
                                  : 'Соглашаюсь',
                              zh: _submitting
                                  ? '正在保存…'
                                  : _versionChanged
                                  ? '更新规则'
                                  : '我同意',
                            ),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: context.brandPrimary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 18,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 4,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Мелкий текст
                        Text(
                          'Нажимая кнопку "Соглашаюсь", вы подтверждаете, что ознакомились с правилами оказания услуг и обязуетесь их соблюдать.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
        ),
      ],
    );
  }
}
