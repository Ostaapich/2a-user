import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../core/logging/client_log_service.dart';
import '../core/ui/app_layout.dart';
import '../core/utils/locale_text.dart';
import '../features/auth/data/auth_provider.dart';
import '../features/auth/data/auth_input_safety.dart';
import '../features/auth/data/auth_form_exit_guards.dart';
import '../features/auth/data/registration_draft.dart';
import '../features/auth/data/partner_link_provider.dart';
import '../features/auth/presentation/client_partner_invite_screen.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/partner_link_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/garage/presentation/garage_order_detail_screen.dart';
import '../features/garage/presentation/garage_request_detail_screen.dart';
import '../features/garage/presentation/garage_request_form_screen.dart';
import '../features/garage/presentation/garage_screen.dart';
import '../features/garage/presentation/garage_vehicle_form_screen.dart';
import '../features/invoices/presentation/invoices_screen.dart';
import '../features/news/presentation/news_detail_screen.dart';
import '../features/news/presentation/news_list_screen.dart';
import '../features/payment_chat/presentation/payment_chat_screen.dart';
import '../features/photos/presentation/photos_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/rules/presentation/rule_detail_screen.dart';
import '../features/rules/presentation/rules_screen.dart';
import '../features/search/presentation/track_search_no_code_screen.dart';
import '../features/shell/presentation/app_shell.dart';
import '../features/calculator/presentation/calculator_screen.dart';
import '../features/shop/domain/marketplace.dart';
import '../features/shop/presentation/marketplace_access_gate.dart';
import '../features/shop/presentation/purchase_list_detail_screen.dart';
import '../features/shop/presentation/purchase_list_screen.dart';
import '../features/shop/presentation/purchase_lists_screen.dart';
import '../features/shop/presentation/shop_item_detail_screen.dart';
import '../features/shop/presentation/shop_screen.dart';
import '../features/sp_finance/presentation/sp_assembly_detail_screen.dart';
import '../features/sp_finance/presentation/sp_track_edit_screen.dart';
import '../features/sp_finance/presentation/sp_organizer_analytics_screen.dart';
import '../features/sp_finance/presentation/sp_organizer_customer_detail_screen.dart';
import '../features/sp_finance/presentation/sp_organizer_customers_screen.dart';
import '../features/sp_finance/presentation/sp_organizer_product_detail_screen.dart';
import '../features/sp_finance/presentation/sp_organizer_products_screen.dart';
import '../features/sp_finance/presentation/sp_organizer_shell.dart';
import '../features/sp_finance/presentation/sp_v2_purchase_detail_screen.dart';
import '../features/sp_finance/presentation/sp_v2_purchases_screen.dart';
import '../features/splash/presentation/splash_screen.dart';
import '../features/referral/presentation/referral_screen.dart';
import '../features/partner_program/presentation/partner_program_screen.dart';
import '../features/tariffs/presentation/tariffs_screen.dart';
import '../features/purchase_blanks/presentation/purchase_blank_detail_screen.dart';
import '../features/purchase_blanks/presentation/purchase_blanks_screen.dart';
import '../features/self_buyout/presentation/self_buyout_screen.dart';
import '../features/support/presentation/support_chat_screen.dart';
import '../features/tracks/presentation/tracks_screen.dart';
import '../features/training/presentation/training_entry_screen.dart';
import '../features/training/presentation/training_modal_ownership.dart';
import '../features/training/presentation/assembly_practice_screen.dart';
import '../features/training/presentation/training_target.dart';
import 'widgets/app_scaffold.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

int? _parsePositiveRouteId(String? value) {
  if (value == null || !RegExp(r'^[1-9]\d*$').hasMatch(value)) return null;
  return int.tryParse(value);
}

final routerProvider = Provider<GoRouter>((ref) {
  final pendingDestination = PendingAuthDestination();
  // НЕ используем ref.watch здесь — иначе GoRouter пересоздаётся при каждом
  // изменении authState (включая фоновое обновление clientData), что сбрасывает
  // navigation stack в initialLocation '/'. Вместо этого читаем authState прямо
  // внутри redirect через ref.read — он вызывается refreshListenable'ом.
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    observers: [
      SentryNavigatorObserver(),
      ClientLogNavigatorObserver(),
      ref.read(trainingModalOwnershipProvider),
    ],
    refreshListenable: _AuthRefreshNotifier(ref),
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final isLoading = authState.isLoading;
      final isLoggedIn = authState.isLoggedIn;
      final registrationDraft = ref.read(registrationDraftStoreProvider);
      registrationDraft.authenticated = isLoggedIn;
      if (isLoggedIn) registrationDraft.clear();
      final isSplashRoute = state.matchedLocation == '/splash';
      final isPartnerLinkRoute = state.matchedLocation.startsWith(
        '/partner-connect/',
      );
      final isClientPartnerInviteRoute = state.matchedLocation.startsWith(
        '/client-partner/invite/',
      );
      final routePartnerToken = isPartnerLinkRoute
          ? state.pathParameters['token']
          : null;
      final partnerLinkState = ref.read(partnerLinkProvider);
      if (routePartnerToken != null &&
          partnerLinkState.shouldCaptureRouteToken(routePartnerToken)) {
        unawaited(
          Future<void>.microtask(
            () => ref
                .read(partnerLinkProvider.notifier)
                .captureToken(routePartnerToken),
          ),
        );
      }
      final pendingPartnerToken = partnerLinkState.pendingTokenForRoute(
        routePartnerToken,
      );
      final isAuthRoute =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation == '/forgot-password';

      // Still loading auth state - show splash.
      // Исключение: если пользователь уже на экране входа/регистрации — остаёмся там.
      // Иначе нажатие "Войти" перебрасывает на сплэш на время API-запроса.
      if (isLoading) {
        if (isAuthRoute || isClientPartnerInviteRoute) return null;
        if (!isPartnerLinkRoute) pendingDestination.remember(state.uri);
        return isSplashRoute ? null : '/splash';
      }

      // Done loading, redirect from splash to appropriate screen
      if (isSplashRoute) {
        if (!isLoggedIn) return '/login';
        return pendingPartnerToken != null
            ? '/partner-connect/$pendingPartnerToken'
            : pendingDestination.take() ?? '/';
      }

      // Not logged in and not on auth route - redirect to login
      if (!isLoggedIn && !isAuthRoute && !isClientPartnerInviteRoute) {
        if (!isPartnerLinkRoute) pendingDestination.remember(state.uri);
        return '/login';
      }

      // Logged in but on auth route - redirect to home
      if (isLoggedIn && isAuthRoute) {
        return pendingPartnerToken != null
            ? '/partner-connect/$pendingPartnerToken'
            : pendingDestination.take() ?? '/';
      }

      // Токен мог быть восстановлен после cold start уже на домашнем роуте.
      // Завершаем привязку до загрузки бизнес-экранов.
      if (isLoggedIn && pendingPartnerToken != null && !isPartnerLinkRoute) {
        return '/partner-connect/$pendingPartnerToken';
      }

      return null;
    },
    routes: [
      // Splash screen
      GoRoute(
        name: 'splash',
        path: '/splash',
        pageBuilder: (context, state) => NoTransitionPage<void>(
          key: state.pageKey,
          child: const SplashScreen(),
        ),
      ),

      // Auth routes
      GoRoute(
        name: 'login',
        path: '/login',
        pageBuilder: (context, state) => NoTransitionPage<void>(
          key: state.pageKey,
          child: const LoginScreen(),
        ),
      ),
      GoRoute(
        name: 'register',
        path: '/register',
        onExit: (context, state) async =>
            ref.read(authProvider).isLoggedIn ||
            await (ref.read(authFormExitGuardsProvider).registration?.call() ??
                Future.value(true)),
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        name: 'forgot-password',
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        name: 'partner-connect',
        path: '/partner-connect/:token',
        builder: (context, state) =>
            PartnerLinkScreen(token: state.pathParameters['token'] ?? ''),
      ),
      GoRoute(
        name: 'client-partner-invite',
        path: '/client-partner/invite/:token',
        builder: (context, state) {
          final token = state.pathParameters['token'] ?? '';
          return ClientPartnerInviteScreen(key: ValueKey(token), token: token);
        },
      ),

      StatefulShellRoute.indexedStack(
        // Auth can round-trip through splash before an outgoing transition
        // finishes. Never keep two pages with the same navigation shell key.
        pageBuilder: (context, state, navigationShell) =>
            NoTransitionPage<void>(
              key: state.pageKey,
              child: AppShell(navigationShell: navigationShell),
            ),
        branches: [
          StatefulShellBranch(
            observers: [ClientLogNavigatorObserver()],
            routes: [
              GoRoute(
                name: 'home',
                path: '/',
                builder: (context, state) =>
                    const TrainingTarget(id: 'route.home', child: HomeScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            observers: [ClientLogNavigatorObserver()],
            routes: [
              GoRoute(
                name: 'photos',
                path: '/photos',
                builder: (context, state) => const TrainingTarget(
                  id: 'route.photos',
                  child: PhotosScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            observers: [ClientLogNavigatorObserver()],
            routes: [
              GoRoute(
                name: 'tracks',
                path: '/tracks',
                builder: (context, state) {
                  final query = state.uri.queryParameters;
                  return TrainingTarget(
                    id: 'route.tracks',
                    child: TracksScreen(
                      initialViewMode: query['view'] == 'groups'
                          ? ViewMode.groups
                          : null,
                      initialTrackId: int.tryParse(query['trackId'] ?? ''),
                      initialTrackCode: query['trackCode'],
                      initialAssemblyId: int.tryParse(
                        query['assemblyId'] ?? '',
                      ),
                      initialClientCode: query['clientCode'],
                    ),
                  );
                },
              ),
            ],
          ),
          StatefulShellBranch(
            observers: [ClientLogNavigatorObserver()],
            routes: [
              GoRoute(
                name: 'invoices',
                path: '/invoices',
                builder: (context, state) => TrainingTarget(
                  id: 'route.invoices',
                  child: InvoicesScreen(
                    initialInvoiceId: state.uri.queryParameters['invoiceId'],
                    initialClientCode: state.uri.queryParameters['clientCode'],
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            observers: [ClientLogNavigatorObserver()],
            routes: [
              GoRoute(
                name: 'support',
                path: '/support',
                builder: (context, state) {
                  final initialMessage = state.extra as String?;
                  return TrainingTarget(
                    id: 'route.support',
                    child: SupportChatScreen(initialMessage: initialMessage),
                  );
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: '/more', redirect: (context, state) => '/'),
      GoRoute(
        name: 'training',
        path: '/training',
        redirect: (context, state) =>
            state.uri.queryParameters['practice'] == 'true'
            ? '/training/assembly'
            : null,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => AppScaffold(
          title: tr(context, ru: 'Обучение', zh: '学习'),
          child: TrainingEntryScreen(
            initialLessonId: state.uri.queryParameters['lesson'],
            initialPractice: state.uri.queryParameters['practice'] == 'true',
          ),
        ),
      ),
      GoRoute(
        path: '/training/assembly',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => AppScaffold(
          title: tr(context, ru: 'Треки · Учебный пример', zh: '运单 · 练习示例'),
          child: const AssemblyPracticeScreen(),
        ),
      ),
      GoRoute(
        name: 'calculator',
        path: '/calculator',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _adaptivePage(
          context,
          state,
          const AppScaffold(
            title: 'Калькулятор доставки',
            child: TrainingTarget(
              id: 'route.calculator',
              child: CalculatorScreen(),
            ),
          ),
        ),
      ),
      GoRoute(
        name: 'search-nocode',
        path: '/search-nocode',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _adaptivePage(
          context,
          state,
          AppScaffold(
            title: 'Поиск по трек-номеру',
            child: TrainingTarget(
              id: 'route.search-nocode',
              child: TrackSearchNoCodeScreen(
                initialQuery: state.uri.queryParameters['query'],
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        name: 'payment-chat',
        path: '/payment-chat',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) {
          String? initialMessage;
          String? invoiceId;
          String? invoiceNumber;
          double? amount;
          double? totalCostCny;
          double? totalCostRub;
          double? clientRubRate;
          double? clientYuanRate;

          if (state.extra is Map<String, dynamic>) {
            final extra = state.extra as Map<String, dynamic>;
            initialMessage = extra['message'] as String?;
            invoiceId = extra['invoiceId'] as String?;
            invoiceNumber = extra['invoiceNumber'] as String?;
            amount = extra['amount'] as double?;
            totalCostCny = extra['totalCostCny'] as double?;
            totalCostRub = extra['totalCostRub'] as double?;
            clientRubRate = extra['clientRubRate'] as double?;
            clientYuanRate = extra['clientYuanRate'] as double?;
          } else if (state.extra is String) {
            initialMessage = state.extra as String?;
          }

          return _adaptivePage(
            context,
            state,
            AppScaffold(
              title: 'Чат по оплате',
              child: TrainingTarget(
                id: 'route.payment-chat',
                child: PaymentChatScreen(
                  initialMessage: initialMessage,
                  invoiceId: invoiceId,
                  invoiceNumber: invoiceNumber,
                  amount: amount,
                  totalCostCny: totalCostCny,
                  totalCostRub: totalCostRub,
                  clientRubRate: clientRubRate,
                  clientYuanRate: clientYuanRate,
                ),
              ),
            ),
          );
        },
      ),
      GoRoute(
        name: 'news',
        path: '/news',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _adaptivePage(
          context,
          state,
          const AppScaffold(
            title: 'Новости',
            child: TrainingTarget(id: 'route.news', child: NewsListScreen()),
          ),
        ),
        routes: [
          GoRoute(
            name: 'news-detail',
            path: ':slug',
            parentNavigatorKey: _rootNavigatorKey,
            pageBuilder: (context, state) {
              final slug = state.pathParameters['slug'] ?? '';
              return _adaptivePage(
                context,
                state,
                AppScaffold(
                  title: 'Статья',
                  child: NewsDetailScreen(slug: slug),
                ),
              );
            },
          ),
        ],
      ),
      GoRoute(
        name: 'profile',
        path: '/profile',
        onExit: (context, state) async =>
            !ref.read(authProvider).isLoggedIn ||
            await (ref.read(authFormExitGuardsProvider).profile?.call() ??
                Future.value(true)),
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _adaptivePage(
          context,
          state,
          const AppScaffold(
            title: 'Профиль',
            child: TrainingTarget(id: 'route.profile', child: ProfileScreen()),
          ),
        ),
      ),
      GoRoute(
        name: 'rules',
        path: '/rules',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _adaptivePage(
          context,
          state,
          const AppScaffold(
            title: 'Правила',
            child: TrainingTarget(id: 'route.rules', child: RulesScreen()),
          ),
        ),
        routes: [
          GoRoute(
            name: 'rule-detail',
            path: ':slug',
            parentNavigatorKey: _rootNavigatorKey,
            pageBuilder: (context, state) {
              final slug = state.pathParameters['slug'] ?? '';
              return _adaptivePage(
                context,
                state,
                AppScaffold(
                  title: 'Правило',
                  child: RuleDetailScreen(slug: slug),
                ),
              );
            },
          ),
        ],
      ),
      GoRoute(
        name: 'referral',
        path: '/referral',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _adaptivePage(
          context,
          state,
          const AppScaffold(
            title: 'Реферальная программа',
            child: TrainingTarget(
              id: 'route.referral',
              child: ReferralScreen(),
            ),
          ),
        ),
      ),
      GoRoute(
        name: 'partner-program',
        path: '/partner-program',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _adaptivePage(
          context,
          state,
          const AppScaffold(
            title: 'Партнёрская программа',
            child: TrainingTarget(
              id: 'route.partner-program',
              child: PartnerProgramScreen(),
            ),
          ),
        ),
      ),
      GoRoute(
        name: 'tariffs',
        path: '/tariffs',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _adaptivePage(
          context,
          state,
          const AppScaffold(
            title: 'Тарифы',
            child: TrainingTarget(id: 'route.tariffs', child: TariffsScreen()),
          ),
        ),
      ),
      GoRoute(
        name: 'shop',
        path: '/shop',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _adaptivePage(
          context,
          state,
          const AppScaffold(
            title: 'Маркетплейсы',
            child: MarketplaceAccessGate(
              child: TrainingTarget(id: 'route.shop', child: ShopScreen()),
            ),
          ),
        ),
        routes: [
          GoRoute(
            name: 'shop-item',
            path: 'item/:itemId',
            parentNavigatorKey: _rootNavigatorKey,
            pageBuilder: (context, state) {
              final marketplace =
                  Marketplace.fromApiKey(
                    state.uri.queryParameters['provider'] ?? '',
                  ) ??
                  Marketplace.alibaba1688;
              return _adaptivePage(
                context,
                state,
                AppScaffold(
                  title: 'Товар ${marketplace.displayName}',
                  child: MarketplaceAccessGate(
                    platformCode: marketplace.apiKey,
                    child: ShopItemDetailScreen(
                      itemId: state.pathParameters['itemId'] ?? '',
                      marketplace: marketplace,
                    ),
                  ),
                ),
              );
            },
          ),
          GoRoute(
            name: 'shop-cart',
            path: 'cart',
            parentNavigatorKey: _rootNavigatorKey,
            pageBuilder: (context, state) => _adaptivePage(
              context,
              state,
              const AppScaffold(
                title: 'Список выкупа',
                child: MarketplaceAccessGate(
                  requirePurchaseList: true,
                  child: PurchaseListScreen(),
                ),
              ),
            ),
          ),
          GoRoute(
            name: 'shop-purchases',
            path: 'purchases',
            parentNavigatorKey: _rootNavigatorKey,
            pageBuilder: (context, state) => _adaptivePage(
              context,
              state,
              const AppScaffold(
                title: 'История заявок',
                child: PurchaseListsScreen(),
              ),
            ),
          ),
          GoRoute(
            name: 'shop-purchase-detail',
            path: 'purchases/:id',
            parentNavigatorKey: _rootNavigatorKey,
            pageBuilder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              if (id == null) {
                return _adaptivePage(
                  context,
                  state,
                  const _InvalidLinkScreen(
                    reason: 'Некорректный ID заявки на выкуп',
                  ),
                );
              }
              return _adaptivePage(
                context,
                state,
                AppScaffold(
                  title: 'Заявка на выкуп',
                  child: PurchaseListDetailScreen(listId: id),
                ),
              );
            },
          ),
        ],
      ),
      // SP Finance workspace: the four organizer directories are persistent
      // tabs. Branch switching keeps each tab's scroll/filter state and does
      // not animate as a new page, while the existing URLs remain deep-linkable.
      StatefulShellRoute.indexedStack(
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state, navigationShell) => _adaptivePage(
          context,
          state,
          AppScaffold(
            title: tr(context, ru: 'Совместные покупки', zh: '共同采购'),
            child: SpOrganizerShell(navigationShell: navigationShell),
          ),
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                name: 'sp-finance',
                path: '/sp-finance',
                builder: (context, state) => const TrainingTarget(
                  id: 'route.sp-finance',
                  child: SpV2PurchasesScreen(embedded: true),
                ),
                routes: [
                  GoRoute(
                    name: 'sp-v2-purchase-detail',
                    path: 'purchases/:id',
                    parentNavigatorKey: _rootNavigatorKey,
                    pageBuilder: (context, state) {
                      final id = _parsePositiveRouteId(
                        state.pathParameters['id'],
                      );
                      if (id == null) {
                        return _adaptivePage(
                          context,
                          state,
                          _InvalidLinkScreen(
                            reason: tr(
                              context,
                              ru: 'Некорректный ID совместной покупки',
                              zh: '共同采购ID无效',
                            ),
                          ),
                        );
                      }
                      return _adaptivePage(
                        context,
                        state,
                        AppScaffold(
                          title: tr(
                            context,
                            ru: 'Совместная покупка',
                            zh: '共同采购',
                          ),
                          child: SpV2PurchaseDetailScreen(purchaseId: id),
                        ),
                      );
                    },
                  ),
                  GoRoute(
                    name: 'sp-assembly-detail',
                    path: 'assemblies/:id',
                    parentNavigatorKey: _rootNavigatorKey,
                    pageBuilder: (context, state) {
                      final id = _parsePositiveRouteId(
                        state.pathParameters['id'],
                      );
                      if (id == null) {
                        return _adaptivePage(
                          context,
                          state,
                          _InvalidLinkScreen(
                            reason: tr(
                              context,
                              ru: 'Некорректный ID сборки',
                              zh: '集货单ID无效',
                            ),
                          ),
                        );
                      }
                      return _adaptivePage(
                        context,
                        state,
                        AppScaffold(
                          title: tr(context, ru: 'Детали сборки', zh: '集货单详情'),
                          child: SpAssemblyDetailScreen(assemblyId: id),
                        ),
                      );
                    },
                  ),
                  GoRoute(
                    name: 'sp-track-edit',
                    path: 'tracks/:id',
                    parentNavigatorKey: _rootNavigatorKey,
                    pageBuilder: (context, state) {
                      final id = _parsePositiveRouteId(
                        state.pathParameters['id'],
                      );
                      if (id == null) {
                        return _adaptivePage(
                          context,
                          state,
                          _InvalidLinkScreen(
                            reason: tr(
                              context,
                              ru: 'Некорректный ID трека',
                              zh: '物流单号ID无效',
                            ),
                          ),
                        );
                      }
                      final extra = state.extra as Map<String, dynamic>?;
                      final extraAssemblyId = extra?['assemblyId'];
                      final queryAssemblyId = _parsePositiveRouteId(
                        state.uri.queryParameters['assemblyId'],
                      );
                      final assemblyId =
                          (extraAssemblyId is int && extraAssemblyId > 0)
                          ? extraAssemblyId
                          : queryAssemblyId;
                      if (assemblyId == null) {
                        return _adaptivePage(
                          context,
                          state,
                          _InvalidLinkScreen(
                            reason: tr(
                              context,
                              ru:
                                  'Не указана сборка для трека. '
                                  'Откройте трек из карточки сборки.',
                              zh: '未指定物流单所属集货单。请从集货单详情打开物流单。',
                            ),
                          ),
                        );
                      }
                      return _adaptivePage(
                        context,
                        state,
                        AppScaffold(
                          title: tr(
                            context,
                            ru: 'Редактирование трека',
                            zh: '编辑物流单',
                          ),
                          child: SpTrackEditScreen(
                            trackId: id,
                            assemblyId: assemblyId,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                name: 'sp-organizer-customers',
                path: '/sp-finance/customers',
                builder: (context, state) =>
                    const SpOrganizerCustomersScreen(embedded: true),
                routes: [
                  GoRoute(
                    name: 'sp-organizer-customer-detail',
                    path: ':id',
                    parentNavigatorKey: _rootNavigatorKey,
                    pageBuilder: (context, state) {
                      final id = _parsePositiveRouteId(
                        state.pathParameters['id'],
                      );
                      if (id == null) {
                        return _adaptivePage(
                          context,
                          state,
                          _InvalidLinkScreen(
                            reason: tr(
                              context,
                              ru: 'Некорректный ID клиента СП',
                              zh: '共同采购客户ID无效',
                            ),
                          ),
                        );
                      }
                      return _adaptivePage(
                        context,
                        state,
                        AppScaffold(
                          title: tr(
                            context,
                            ru: 'Карточка клиента',
                            zh: '客户详情',
                          ),
                          child: SpOrganizerCustomerDetailScreen(
                            customerId: id,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                name: 'sp-organizer-products',
                path: '/sp-finance/products',
                builder: (context, state) =>
                    const SpOrganizerProductsScreen(embedded: true),
                routes: [
                  GoRoute(
                    name: 'sp-organizer-product-detail',
                    path: ':id',
                    parentNavigatorKey: _rootNavigatorKey,
                    pageBuilder: (context, state) {
                      final id = _parsePositiveRouteId(
                        state.pathParameters['id'],
                      );
                      if (id == null) {
                        return _adaptivePage(
                          context,
                          state,
                          _InvalidLinkScreen(
                            reason: tr(
                              context,
                              ru: 'Некорректный ID товара СП',
                              zh: '共同采购商品ID无效',
                            ),
                          ),
                        );
                      }
                      return _adaptivePage(
                        context,
                        state,
                        AppScaffold(
                          title: tr(context, ru: 'Карточка товара', zh: '商品详情'),
                          child: SpOrganizerProductDetailScreen(productId: id),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                name: 'sp-organizer-analytics',
                path: '/sp-finance/analytics',
                builder: (context, state) =>
                    const SpOrganizerAnalyticsScreen(embedded: true),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        name: 'garage',
        path: '/garage',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _adaptivePage(
          context,
          state,
          const AppScaffold(
            title: 'Гараж',
            child: TrainingTarget(id: 'route.garage', child: GarageScreen()),
          ),
        ),
        routes: [
          GoRoute(
            name: 'garage-vehicle-create',
            path: 'vehicles/new',
            parentNavigatorKey: _rootNavigatorKey,
            pageBuilder: (context, state) => _adaptivePage(
              context,
              state,
              const AppScaffold(
                title: 'Новый автомобиль',
                child: GarageVehicleFormScreen(),
              ),
            ),
          ),
          GoRoute(
            name: 'garage-vehicle-edit',
            path: 'vehicles/:id/edit',
            parentNavigatorKey: _rootNavigatorKey,
            pageBuilder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              if (id == null) {
                return _adaptivePage(
                  context,
                  state,
                  const _InvalidLinkScreen(
                    reason: 'Некорректный ID автомобиля',
                  ),
                );
              }
              return _adaptivePage(
                context,
                state,
                AppScaffold(
                  title: 'Автомобиль',
                  child: GarageVehicleFormScreen(vehicleId: id),
                ),
              );
            },
          ),
          GoRoute(
            name: 'garage-request-create',
            path: 'requests/new',
            parentNavigatorKey: _rootNavigatorKey,
            pageBuilder: (context, state) => _adaptivePage(
              context,
              state,
              AppScaffold(
                title: 'Новая заявка',
                child: GarageRequestFormScreen(
                  initialVehicleId: int.tryParse(
                    state.uri.queryParameters['vehicleId'] ?? '',
                  ),
                ),
              ),
            ),
          ),
          GoRoute(
            name: 'garage-request-edit',
            path: 'requests/:id/edit',
            parentNavigatorKey: _rootNavigatorKey,
            pageBuilder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              if (id == null) {
                return _adaptivePage(
                  context,
                  state,
                  const _InvalidLinkScreen(reason: 'Некорректный ID заявки'),
                );
              }
              return _adaptivePage(
                context,
                state,
                AppScaffold(
                  title: 'Редактирование заявки',
                  child: GarageRequestFormScreen(requestId: id),
                ),
              );
            },
          ),
          GoRoute(
            name: 'garage-request-detail',
            path: 'requests/:id',
            parentNavigatorKey: _rootNavigatorKey,
            pageBuilder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              if (id == null) {
                return _adaptivePage(
                  context,
                  state,
                  const _InvalidLinkScreen(reason: 'Некорректный ID заявки'),
                );
              }
              return _adaptivePage(
                context,
                state,
                AppScaffold(
                  title: 'Заявка Гаража',
                  child: GarageRequestDetailScreen(requestId: id),
                ),
              );
            },
          ),
          GoRoute(
            name: 'garage-order-detail',
            path: 'orders/:id',
            parentNavigatorKey: _rootNavigatorKey,
            pageBuilder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              if (id == null) {
                return _adaptivePage(
                  context,
                  state,
                  const _InvalidLinkScreen(reason: 'Некорректный ID заказа'),
                );
              }
              return _adaptivePage(
                context,
                state,
                AppScaffold(
                  title: 'Заказ Гаража',
                  child: GarageOrderDetailScreen(orderId: id),
                ),
              );
            },
          ),
        ],
      ),
      // Purchase Blanks routes
      GoRoute(
        name: 'self-buyout',
        path: '/self-buyout',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _adaptivePage(
          context,
          state,
          const AppScaffold(
            title: 'Самовыкуп',
            child: TrainingTarget(
              id: 'route.self-buyout',
              child: SelfBuyoutScreen(),
            ),
          ),
        ),
      ),
      GoRoute(
        name: 'purchase-blanks',
        path: '/purchase-blanks',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _adaptivePage(
          context,
          state,
          const AppScaffold(
            title: 'Выкуп по бланку',
            child: TrainingTarget(
              id: 'route.purchase-blanks',
              child: PurchaseBlanksScreen(),
            ),
          ),
        ),
        routes: [
          GoRoute(
            name: 'purchase-blank-detail',
            path: ':id',
            parentNavigatorKey: _rootNavigatorKey,
            pageBuilder: (context, state) {
              final id = _parsePositiveRouteId(state.pathParameters['id']);
              if (id == null) {
                return _adaptivePage(
                  context,
                  state,
                  _InvalidLinkScreen(
                    reason: tr(
                      context,
                      ru: 'Некорректный ID бланка выкупа',
                      zh: '采购单ID无效',
                    ),
                  ),
                );
              }
              return _adaptivePage(
                context,
                state,
                AppScaffold(
                  title: 'Бланк #$id',
                  child: PurchaseBlankDetailScreen(blankId: id),
                ),
              );
            },
          ),
        ],
      ),
    ],
  );
});

Page<void> _adaptivePage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  if (AppLayout.useSideNavigation(context)) {
    return NoTransitionPage<void>(key: state.pageKey, child: child);
  }

  return MaterialPage<void>(key: state.pageKey, child: child);
}

/// Notifier that triggers router refresh when auth state changes
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(this._ref) {
    _ref.listen(authProvider, (_, _) {
      notifyListeners();
    });
    _ref.listen(partnerLinkProvider, (_, _) {
      notifyListeners();
    });
  }

  final Ref _ref;
}

/// PU-S6/H4: показывается когда роут не смог распарсить параметры
/// (некорректный ID, отсутствует обязательный query). Не падаем ассертом,
/// показываем дружелюбный экран с кнопкой возврата.
class _InvalidLinkScreen extends StatelessWidget {
  const _InvalidLinkScreen({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Ссылка недействительна',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.link_off_rounded, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                reason,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/');
                  }
                },
                child: const Text('Назад'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
