import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:twoalogisticcabineuser/src/core/ui/blurred_modal_bottom_sheet.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/presentation/notifications_sheet.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/application/notifications_controller.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/domain/notification_item.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/garage/application/garage_providers.dart';
import 'package:twoalogisticcabineuser/src/features/garage/domain/garage_models.dart';
import 'package:twoalogisticcabineuser/src/features/garage/presentation/garage_screen.dart';
import 'package:twoalogisticcabineuser/src/features/garage/presentation/garage_vehicle_form_screen.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/auth_provider.dart';
import 'package:twoalogisticcabineuser/src/features/calculator/presentation/calculator_screen.dart';
import 'package:twoalogisticcabineuser/src/features/home/presentation/warehouse_address_checker.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_v2_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_v2_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/presentation/sp_v2_purchases_screen.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/presentation/sp_v2_purchase_detail_screen.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_target.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_tour_steps.dart';

class _WarehouseRecognizer implements WarehouseScreenshotTextRecognizer {
  @override
  Future<String> recognize(String path) async => 'TEST 测试仓库 123';
}

Finder anchor(String id) =>
    find.byWidgetPredicate((w) => w is TrainingTarget && w.id == id);
Future<void> frames(WidgetTester tester, [int count = 10]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget app(Widget body) => MaterialApp(
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  supportedLocales: const [Locale('ru'), Locale('zh')],
  locale: const Locale('ru'),
  home: Scaffold(body: body),
);

class _Auth extends AuthNotifier {
  @override
  AuthState build() =>
      const AuthState(isLoggedIn: true, isLoading: false, clientId: 1);
}

class _EmptyGarageVehicles extends GarageVehiclesController {
  int writes = 0;
  @override
  Future<GarageVehiclesState> build() async =>
      GarageVehiclesState(vehicles: []);

  @override
  Future<GarageVehicle> createVehicle(GarageVehicleInput input) async {
    writes++;
    throw StateError('Training must not save a vehicle');
  }
}

class _CalculatorApi extends ApiClient {
  final requests = <String>[];
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    requests.add('GET $path');
    final Object data = switch (path) {
      '/tariffs' => {
        'tariffs': [
          {
            'id': 1,
            'name': 'Тестовый тариф',
            'baseCost': 4,
            'pricingType': 'weight',
            'paidPhotoReport': false,
          },
        ],
      },
      '/packagings' => {
        'packagings': [
          {
            'id': 1,
            'name': 'Тестовая коробка',
            'baseCost': 2,
            'kind': 'primary',
            'isActive': true,
          },
        ],
      },
      '/photo-report-coefficients' => {'coefficients': []},
      _ => throw StateError('Unexpected GET $path'),
    };
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: data as T,
    );
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    requests.add('POST $path');
    if (path != '/client/unloading-quote') {
      throw StateError('Unexpected POST $path');
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data:
          {
                'data': {'clientCostUsd': 3},
              }
              as T,
    );
  }
}

const purchase = SpV2Purchase(
  id: 11,
  title: 'Тестовая закупка',
  status: 'open',
  statusLabel: 'Открыта',
  isAcceptingItems: true,
  currency: 'RUB',
);

class _Purchases extends SpV2PurchasesController {
  @override
  SpV2PurchasesState build() => const SpV2PurchasesState(purchases: [purchase]);
  @override
  Future<void> load({bool silent = false, String? query}) async {}
}

class _Notifications extends NotificationsController {
  @override
  Future<List<NotificationItem>> build() async => [];
  @override
  Future<void> refresh() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('ru');
    await (FontLoader('Gilroy')
          ..addFont(rootBundle.load('assets/fonts/gilroy/Gilroy-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/gilroy/Gilroy-Bold.ttf')))
        .load();
  });
  testWidgets(
    'calculator missing fields lead to actual result without creating business records',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _CalculatorApi();
      final registry = TrainingTargetRegistry();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(api),
            authProvider.overrideWith(_Auth.new),
            trainingTargetRegistryProvider.overrideWithValue(registry),
          ],
          child: app(const CalculatorScreen()),
        ),
      );
      await frames(tester);
      expect(registry.contextFor('calculator.missing.weight'), isNotNull);
      expect(registry.contextFor('calculator.missing.volume'), isNotNull);
      expect(registry.contextFor('calculator.missing.places'), isNull);
      expect(registry.contextFor('calculator.missing.tracks'), isNull);
      expect(registry.contextFor('calculator.missing.packaging'), isNull);
      expect(registry.contextFor('calculator.result'), isNull);
      final weight = find.descendant(
        of: anchor('calculator.weight'),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(weight);
      await tester.enterText(weight, '10');
      await frames(tester);
      expect(registry.contextFor('calculator.missing.weight'), isNull);
      expect(registry.contextFor('calculator.missing.volume'), isNotNull);
      final volume = find.descendant(
        of: anchor('calculator.volume'),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(volume);
      await tester.enterText(volume, '0.1');
      await frames(tester);
      expect(registry.contextFor('calculator.missing.volume'), isNull);
      await tester.ensureVisible(anchor('calculator.result'));
      await frames(tester);
      expect(registry.contextFor('calculator.result'), isNotNull);
      expect(tester.getSize(anchor('calculator.result')).height, lessThan(45));
      Finder field(String id) =>
          find.descendant(of: anchor(id), matching: find.byType(TextField));
      // Fixed-price photo reports are billed as services rather than a
      // percentage of delivery, so the calculator has no photo-count field.
      expect(anchor('calculator.photos'), findsNothing);
      expect(anchor('calculator.missing.photos'), findsNothing);
      expect(anchor('calculator.result'), findsOneWidget);
      final insurance = find.widgetWithText(SwitchListTile, 'Страховка');
      await tester.ensureVisible(insurance);
      await tester.pumpAndSettle();
      await tester.ensureVisible(insurance);
      await tester.tap(insurance);
      await frames(tester);
      expect(anchor('calculator.result'), findsNothing);
      expect(anchor('calculator.missing.insurance'), findsOneWidget);
      await tester.ensureVisible(field('calculator.missing.insurance'));
      await tester.enterText(field('calculator.missing.insurance'), '1500');
      await frames(tester);
      expect(anchor('calculator.missing.insurance'), findsNothing);
      expect(anchor('calculator.result'), findsOneWidget);

      expect(
        api.requests.where((r) => r.startsWith('POST ')),
        everyElement('POST /client/unloading-quote'),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 10));
      await frames(tester);
    },
  );
  testWidgets(
    'warehouse opens actual root checker and restores prerequisite after dismissal',
    (tester) async {
      final registry = TrainingTargetRegistry();
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trainingTargetRegistryProvider.overrideWithValue(registry),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: Scaffold(
              body: Builder(
                builder: (context) => TrainingTarget(
                  id: 'warehouse.check',
                  child: FilledButton(
                    onPressed: () => showWarehouseAddressChecker(
                      context,
                      expected: const WarehouseAddressCheckData(
                        clientCode: 'TEST',
                        address: '测试仓库',
                        phone: '123',
                      ),
                      recognizer: _WarehouseRecognizer(),
                      screenshotPicker: () async => XFile.fromData(
                        base64Decode(
                          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
                        ),
                        name: 'fixture.png',
                      ),
                    ),
                    child: const Text('Проверить заполнение'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(registry.contextFor('warehouse.check'), isNotNull);
      expect(registry.contextFor('warehouse.screenshot'), isNull);
      await tester.tap(anchor('warehouse.check'));
      await frames(tester);
      expect(registry.contextFor('warehouse.check'), isNull);
      expect(registry.contextFor('warehouse.screenshot'), isNotNull);
      final button = find.descendant(
        of: anchor('warehouse.screenshot'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      );
      expect(
        tester.getRect(anchor('warehouse.screenshot')),
        tester.getRect(button),
      );
      navigatorKey.currentState!.pop();
      await frames(tester);
      expect(registry.contextFor('warehouse.check'), isNotNull);
      expect(registry.contextFor('warehouse.screenshot'), isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 10));
      await frames(tester);
    },
  );
  testWidgets(
    'organizer auto actions open actual purchase and participant finance tracks tabs',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final registry = TrainingTargetRegistry();
      final router = GoRouter(
        initialLocation: '/sp-finance',
        routes: [
          GoRoute(
            path: '/sp-finance',
            builder: (_, _) => const Scaffold(body: SpV2PurchasesScreen()),
            routes: [
              GoRoute(
                path: 'purchases/:id',
                builder: (_, _) => const Scaffold(
                  body: SpV2PurchaseDetailScreen(purchaseId: 11),
                ),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trainingTargetRegistryProvider.overrideWithValue(registry),
            spV2PurchasesControllerProvider.overrideWith(_Purchases.new),
            spV2PurchaseDetailProvider.overrideWith((_, _) async => purchase),
            spOrganizerCapabilitiesProvider.overrideWith(
              (_) async => SpOrganizerCapabilities.unavailable,
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            locale: const Locale('ru'),
            supportedLocales: const [Locale('ru')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
          ),
        ),
      );
      await frames(tester);
      await tester.ensureVisible(anchor('organizer.open'));
      registry.activationFor(
        'organizer.open',
        registry.contextFor('organizer.open')!,
      )!();
      await frames(tester);
      expect(
        GoRouterState.of(
          tester.element(find.byType(SpV2PurchaseDetailScreen)),
        ).uri.path,
        '/sp-finance/purchases/11',
      );
      expect(registry.contextFor('organizer.open'), isNull);
      final steps = trainingTourSteps(
        tester.element(find.byType(SpV2PurchaseDetailScreen)),
      );
      for (final id in ['participants', 'finance', 'tracks']) {
        final target = anchor('organizer.tab.$id');
        await tester.ensureVisible(target);
        registry.activationFor(
          'organizer.tab.$id',
          registry.contextFor('organizer.tab.$id')!,
        )!();
        await frames(tester);
        expect(registry.contextFor('organizer.tab.$id'), isNotNull);
        final step = steps.singleWhere(
          (s) => s.targetId == 'organizer.tab.$id',
        );
        expect(
          step.matchesPath(
            GoRouterState.of(
              tester.element(find.byType(SpV2PurchaseDetailScreen)),
            ).uri.path,
          ),
          isTrue,
        );
        expect(tester.getSize(target).height, lessThan(80));
      }
      router.pop();
      await frames(tester);
      expect(registry.contextFor('organizer.open'), isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 10));
      await frames(tester);
    },
  );
  testWidgets(
    'notification auto action dismisses actual modal and restores home target',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final registry = TrainingTargetRegistry();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trainingTargetRegistryProvider.overrideWithValue(registry),
            notificationsControllerProvider.overrideWith(_Notifications.new),
          ],
          child: app(
            Builder(
              builder: (context) => TrainingTarget(
                id: 'warehouse.copy-address',
                child: FilledButton(
                  onPressed: () => showBlurredModalBottomSheet<void>(
                    context: context,
                    useRootNavigator: true,
                    isScrollControlled: true,
                    builder: (_) => SizedBox(
                      height: 600,
                      child: NotificationsSheet(
                        clientCode: 'TEST',
                        onNavigate: (_) {},
                      ),
                    ),
                  ),
                  child: const Text('Open notifications'),
                ),
              ),
            ),
          ),
        ),
      );
      await frames(tester);
      await tester.tap(anchor('warehouse.copy-address'));
      await frames(tester);
      expect(registry.contextFor('warehouse.copy-address'), isNull);
      expect(tester.getSize(anchor('notification.sheet.dismiss')).width, 42);
      registry.activationFor(
        'notification.sheet.dismiss',
        registry.contextFor('notification.sheet.dismiss')!,
      )!();
      await frames(tester);
      expect(anchor('notification.sheet.dismiss'), findsNothing);
      expect(registry.contextFor('warehouse.copy-address'), isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 10));
    },
  );
  testWidgets(
    'garage auto action opens empty real form without creating a vehicle',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final registry = TrainingTargetRegistry();
      final vehicles = _EmptyGarageVehicles();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trainingTargetRegistryProvider.overrideWithValue(registry),
            garageAvailabilityProvider.overrideWith(
              (_) async => const GarageAvailability(
                available: true,
                reason: null,
                processorAgentId: 1,
                vinLookupConfigured: false,
              ),
            ),
            garageVehiclesControllerProvider.overrideWith(() => vehicles),
          ],
          child: app(const GarageScreen()),
        ),
      );
      await frames(tester);
      expect(registry.contextFor('garage.request.create'), isNull);
      await tester.ensureVisible(anchor('garage.vehicle.create'));
      registry.activationFor(
        'garage.vehicle.create',
        registry.contextFor('garage.vehicle.create')!,
      )!();
      await frames(tester);
      expect(find.byType(GarageVehicleFormScreen), findsOneWidget);
      expect(registry.contextFor('garage.vehicle.create'), isNull);
      for (final field in tester.widgetList<TextFormField>(
        find.byType(TextFormField),
      )) {
        expect(field.controller?.text ?? field.initialValue ?? '', isEmpty);
      }
      expect(vehicles.writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 10));
    },
  );
}
