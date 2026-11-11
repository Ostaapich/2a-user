import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:twoalogisticcabineuser/src/app/widgets/app_scaffold.dart';
import 'package:twoalogisticcabineuser/src/core/branding/company_branding_provider.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/clients/domain/client_codes_state.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/application/notifications_controller.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/domain/notification_item.dart';
import 'package:twoalogisticcabineuser/src/features/profile/data/profile_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_v2_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_v2_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/presentation/sp_v2_purchase_detail_screen.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_target.dart';

class _Codes extends ClientCodesController {
  @override
  Future<ClientCodesState> build() async =>
      const ClientCodesState(codes: ['2A-TEST'], activeCode: '2A-TEST');
}

class _Notifications extends NotificationsController {
  @override
  Future<List<NotificationItem>> build() async => const [];
}

const _capabilities = SpOrganizerCapabilities(
  contractVersion: 1,
  organizerV2: true,
  purchaseKinds: true,
  participants: false,
  products: false,
  calculationProfiles: false,
  fulfillmentOverview: false,
  selfBuyoutLinks: false,
  selfBuyout: SpOrganizerActionCapability.unavailable,
  garageImport: true,
  trackLinks: true,
  trackImport: true,
  purchaseBlankImport: true,
  previousPurchaseImport: true,
  assemblyLinks: false,
  invoiceLinks: false,
  analytics: false,
  purchaseExport: true,
  bulkOperations: true,
);
String _itemTitle(int i, String locale) => locale == 'ru'
    ? 'Позиция ${i.toString().padLeft(3, '0')} — кроссовки'
    : '商品 ${i.toString().padLeft(3, '0')} — 运动鞋';
SpV2Purchase _fixture(int count, String locale) => SpV2Purchase(
  id: 17,
  title: locale == 'ru' ? 'Закупка ноября' : '十一月采购',
  description: locale == 'ru'
      ? 'Поставка одежды и обуви для участников закупки.'
      : '为参与者采购服装和鞋类。',
  status: 'open',
  statusLabel: locale == 'ru' ? 'Принимает товары' : '接收商品',
  isAcceptingItems: true,
  purchaseRate: 11.5,
  createdAt: DateTime.utc(2026, 11, 1),
  startedAt: DateTime.utc(2026, 11, 2),
  stats: SpV2PurchaseStats(
    customersCount: 1,
    itemsCount: count,
    totalDueRub: count * 390,
    totalProfitRub: count * 92,
  ),
  items: List.generate(
    count,
    (i) => SpV2Item(
      id: i + 1,
      title: _itemTitle(i + 1, locale),
      status: 'approved',
      statusLabel: locale == 'ru' ? 'Подтверждён' : '已确认',
      quantity: 2,
      purchasePriceYuan: 10,
      clientPriceYuan: 14,
      shippingCostRub: 60,
      shippingCostActualRub: 50,
      additionalExpensesRub: 8,
      totalDueRub: 390,
      updatedAt: DateTime.utc(2026, 11, 9),
      customer: SpV2Customer(
        id: 31,
        fullName: locale == 'ru' ? 'Участник закупки' : '采购参与者',
      ),
    ),
  ),
);
Future<void> _capture(WidgetTester t, GlobalKey key, String name) async {
  final directory = Platform.environment['ROOT06_RENDER_DIR'];
  if (directory == null) return;
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    await (FontLoader('Gilroy')
          ..addFont(rootBundle.load('assets/fonts/gilroy/Gilroy-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/gilroy/Gilroy-Bold.ttf'))
          ..addFont(rootBundle.load('assets/fonts/gilroy/Gilroy-Black.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
    final font = File(
      Platform.environment['ROOT06_CJK_FONT'] ??
          '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
    );
    if (await font.exists()) {
      final bytes = await font.readAsBytes();
      await (FontLoader(
        'Root06CJK',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    } else if (Platform.environment['ROOT06_RENDER_DIR'] != null) {
      throw StateError(
        'Real CJK font is required for captured acceptance evidence',
      );
    }
    await initializeDateFormatting('ru');
    await initializeDateFormatting('zh');
  });
  for (final count in [1, 20, 100]) {
    for (final width in [320.0, 390.0]) {
      for (final locale in ['ru', 'zh']) {
        for (final scale in [1.0, 1.6]) {
          final name =
              'sp-$count-${width.toInt()}-$locale-${scale.toStringAsFixed(1)}';
          testWidgets('working purchase $name', (t) async {
            final baseline = Platform.environment['ROOT06_BASELINE'] == '1';
            await t.binding.setSurfaceSize(Size(width, 844));
            addTearDown(() => t.binding.setSurfaceSize(null));
            final errors = <String>[];
            final old = FlutterError.onError;
            FlutterError.onError = (d) {
              errors.add(d.exceptionAsString());
              if (!baseline) old?.call(d);
            };
            addTearDown(() => FlutterError.onError = old);
            final fixture = _fixture(count, locale);
            final boundary = GlobalKey();
            await t.pumpWidget(
              RepaintBoundary(
                key: boundary,
                child: ProviderScope(
                  retry: (_, _) => null,
                  overrides: [
                    companyNameProvider.overrideWithValue('2A Logistic'),
                    clientProfileProvider.overrideWithValue(
                      const AsyncData(null),
                    ),
                    clientCodesControllerProvider.overrideWith(_Codes.new),
                    notificationsControllerProvider.overrideWith(
                      _Notifications.new,
                    ),
                    spV2PurchaseDetailProvider(
                      17,
                    ).overrideWith((ref) async => fixture),
                    spOrganizerCapabilitiesProvider.overrideWith(
                      (ref) async => _capabilities,
                    ),
                    spV2CustomersProvider.overrideWith(
                      (ref) async => [fixture.items.first.customer!],
                    ),
                  ],
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    locale: Locale(locale),
                    supportedLocales: const [Locale('ru'), Locale('zh')],
                    localizationsDelegates:
                        GlobalMaterialLocalizations.delegates,
                    theme: ThemeData(
                      fontFamily: 'Gilroy',
                      fontFamilyFallback: const ['Root06CJK'],
                      filledButtonTheme: FilledButtonThemeData(
                        style: ButtonStyle(
                          textStyle: WidgetStatePropertyAll(
                            TextStyle(fontFamilyFallback: const ['Root06CJK']),
                          ),
                        ),
                      ),
                      colorScheme: const ColorScheme.light(
                        primary: Color(0xFFF26F23),
                        secondary: Color(0xFFFFA552),
                      ),
                    ),
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        size: Size(width, 844),
                        textScaler: TextScaler.linear(scale),
                      ),
                      child: child!,
                    ),
                    home: const AppScaffold(
                      title: '2A',
                      child: SpV2PurchaseDetailScreen(purchaseId: 17),
                    ),
                  ),
                ),
              ),
            );
            await t.pump();
            await t.pump(const Duration(milliseconds: 700));
            await t.pump();
            final actualMedia = MediaQuery.of(
              t.element(find.byType(SpV2PurchaseDetailScreen)),
            );
            expect(actualMedia.size, Size(width, 844));
            final first = find.text(_itemTitle(1, locale));
            final initialY = first.evaluate().isEmpty
                ? null
                : t.getRect(first.first).top;
            final firstInitiallyVisible =
                initialY != null && initialY < (scale > 1 ? 680 : 600);
            await _capture(t, boundary, '$name-top');
            final scrollable = find
                .descendant(
                  of: find.byType(SpV2PurchaseDetailScreen),
                  matching: find.byType(Scrollable),
                )
                .first;
            if (first.evaluate().isEmpty) {
              await t.scrollUntilVisible(
                first,
                350,
                scrollable: scrollable,
                maxScrolls: 20,
              );
              await t.pump();
            }
            final scroll = t.state<ScrollableState>(scrollable).position;
            final absoluteFirstY = scroll.pixels + t.getRect(first.first).top;
            await Scrollable.ensureVisible(
              t.element(first.first),
              alignment: .4,
            );
            await t.pump();
            await t.pump(const Duration(milliseconds: 300));
            expect(first.hitTestable(), findsOneWidget);
            final last = find.text(_itemTitle(count, locale));
            await Scrollable.ensureVisible(
              t.element(last.first),
              alignment: .4,
            );
            await t.pump();
            await t.pump(const Duration(milliseconds: 300));
            expect(last.hitTestable(), findsOneWidget);
            await _capture(t, boundary, '$name-last');
            if (!baseline) {
              // Exercise the real horizontal navigation and preserve every action.
              scroll.jumpTo(0);
              await t.pump();
              for (final tab in [
                'items',
                'participants',
                'finance',
                'tracks',
                'settings',
              ]) {
                final target = find.byWidgetPredicate(
                  (w) => w is TrainingTarget && w.id == 'organizer.tab.$tab',
                );
                await Scrollable.ensureVisible(
                  t.element(target),
                  alignment: .3,
                );
                await t.pump();
                expect(target.hitTestable(), findsOneWidget, reason: tab);
                expect(
                  t
                      .widget<InkWell>(
                        find
                            .descendant(
                              of: target,
                              matching: find.byType(InkWell),
                            )
                            .first,
                      )
                      .onTap,
                  isNotNull,
                );
              }
              final settings = find.byWidgetPredicate(
                (w) => w is TrainingTarget && w.id == 'organizer.tab.settings',
              );
              await t.tap(settings);
              await t.pump();
              await t.pump(const Duration(milliseconds: 300));
              expect(find.byKey(const ValueKey('settings')), findsOneWidget);
              final items = find.byWidgetPredicate(
                (w) => w is TrainingTarget && w.id == 'organizer.tab.items',
              );
              await Scrollable.ensureVisible(t.element(items), alignment: .3);
              await t.pump();
              await t.tap(items);
              await t.pump();
              await t.pump(const Duration(milliseconds: 300));
              expect(
                find.byWidgetPredicate(
                  (w) => w.runtimeType.toString() == '_ItemCard',
                ),
                findsNWidgets(count),
              );
              scroll.jumpTo(0);
              await t.pump();
              final management = find.text(
                locale == 'ru' ? 'Управление СП' : '采购管理',
              );
              await t.tap(management);
              await t.pump();
              await t.pump(const Duration(milliseconds: 300));
              final accept = find.text(
                locale == 'ru' ? 'Закрыть приём' : '停止接收',
              );
              await Scrollable.ensureVisible(t.element(accept), alignment: .4);
              await t.pump();
              expect(accept.hitTestable(), findsOneWidget);
              expect(find.text(fixture.description!), findsOneWidget);
              await _capture(t, boundary, '$name-management');
              await Scrollable.ensureVisible(
                t.element(management),
                alignment: .3,
              );
              await t.pump();
              await t.tap(management);
              await t.pump();
              await t.pump(const Duration(milliseconds: 300));
              final bulk = find.text(
                locale == 'ru' ? 'Массовые действия' : '批量操作',
              );
              await Scrollable.ensureVisible(t.element(bulk), alignment: .3);
              await t.pump();
              await t.tap(bulk);
              await t.pump();
              await t.pump(const Duration(milliseconds: 300));
              for (final type in [
                '_BulkManageActionCard',
                '_BulkPriceActionCard',
                '_BulkDeliveryActionCard',
              ]) {
                final card = find.byWidgetPredicate(
                  (w) => w.runtimeType.toString() == type,
                );
                await Scrollable.ensureVisible(t.element(card), alignment: .4);
                await t.pump();
                final action = find
                    .descendant(of: card, matching: find.byType(InkWell))
                    .first;
                expect(action.hitTestable(), findsOneWidget);
                expect(t.widget<InkWell>(action).onTap, isNotNull);
              }
              await _capture(t, boundary, '$name-bulk');
            }
            final verifyEdit =
                !baseline &&
                count == 1 &&
                width == 390 &&
                scale == 1.0 &&
                locale == 'ru';
            if (verifyEdit) {
              await Scrollable.ensureVisible(
                t.element(first.first),
                alignment: .4,
              );
              await t.pump();
              await t.tap(first.first);
              await t.pump();
              await t.pump(const Duration(milliseconds: 500));
              final editors = t
                  .widgetList<TextField>(find.byType(TextField))
                  .toList();
              await _capture(t, boundary, '$name-edit-top');
              expect(
                editors.any(
                  (e) => e.controller?.text == fixture.items.first.title,
                ),
                true,
              );
              expect(editors.any((e) => e.controller?.text == '2'), true);
              final clientPrice = find.byWidgetPredicate(
                (w) => w is TextField && w.controller?.text == '14.00',
              );
              await t.scrollUntilVisible(
                clientPrice,
                200,
                scrollable: find
                    .descendant(
                      of: find.byWidgetPredicate(
                        (w) => w.runtimeType.toString() == '_EditItemSheet',
                      ),
                      matching: find.byType(Scrollable),
                    )
                    .first,
              );
              await t.pump();
              await Scrollable.ensureVisible(
                t.element(clientPrice),
                alignment: .4,
              );
              await t.pump();
              expect(clientPrice.hitTestable(), findsOneWidget);
              expect(
                t.widget<TextField>(clientPrice).controller?.text,
                '14.00',
              );
              await _capture(t, boundary, '$name-edit');
              await Navigator.of(
                t.element(find.byType(TextField).first),
              ).maybePop();
              await t.pump();
              await t.pump(const Duration(milliseconds: 400));
              expect(find.byType(TextField), findsNothing);
            }
            final add = find.byKey(const ValueKey('sp-add-item-tab-action'));
            await Scrollable.ensureVisible(t.element(add), alignment: .4);
            await t.pump();
            for (final tab in [
              'items',
              'participants',
              'finance',
              'tracks',
              'settings',
            ]) {
              expect(
                find.byWidgetPredicate(
                  (w) => w is TrainingTarget && w.id == 'organizer.tab.$tab',
                ),
                findsOneWidget,
              );
            }
            await t.tap(add);
            await t.pump();
            await t.pump(const Duration(milliseconds: 600));
            final field = find.byKey(
              const ValueKey('add-item-customer-section'),
            );
            expect(field, findsOneWidget);
            final input = find.byWidgetPredicate(
              (w) =>
                  w is TextField &&
                  w.decoration?.labelText ==
                      (locale == 'ru' ? 'Имя участника *' : '参与者姓名 *'),
            );
            final inputY = t.getRect(input).top;
            expect(input.hitTestable(), findsOneWidget);
            await _capture(t, boundary, '$name-add');
            expect(
              find.byKey(const ValueKey('track-import-entry')),
              findsNothing,
            );
            if (!baseline) {
              final imports = find.text(
                locale == 'ru' ? 'Импорт товара' : '导入商品',
              );
              await t.tap(imports);
              await t.pump();
              await t.pump(const Duration(milliseconds: 300));
              for (final key in [
                'track-import-entry',
                'previous-purchase-import-entry',
                'purchase-blank-import-entry',
                'garage-import-entry',
              ]) {
                final action = find.byKey(ValueKey(key));
                await Scrollable.ensureVisible(
                  t.element(action),
                  alignment: .3,
                );
                await t.pump();
                expect(action.hitTestable(), findsOneWidget);
                expect(t.widget<InkWell>(action).onTap, isNotNull);
              }
              await _capture(t, boundary, '$name-imports');
            }
            final directory = Platform.environment['ROOT06_RENDER_DIR'];
            if (directory != null) {
              await t.runAsync(
                () => File('$directory/$name.json').writeAsString(
                  jsonEncode({
                    'count': count,
                    'width': width,
                    'height': 844,
                    'mediaQuerySize': [
                      actualMedia.size.width,
                      actualMedia.size.height,
                    ],
                    'locale': locale,
                    'textScale': scale,
                    'firstInitiallyVisible': firstInitiallyVisible,
                    'initialFirstY': initialY,
                    'absoluteFirstY': absoluteFirstY,
                    'addParticipantY': inputY,
                    'lastReachable': true,
                    'allFiveTabsPreserved': true,
                    'allFiveTabsReachable': !baseline,
                    'bulkActionsReachable': baseline ? null : 3,
                    'importActionsReachable': baseline ? null : 4,
                    'managementAndDescriptionReachable': !baseline,
                    'firstInputHitTestable': true,
                    'settingsSelectionAndReturnItems': !baseline,
                    'editDraftVerified': verifyEdit,
                    'errors': errors,
                    'fixtureTotalDueRub': fixture.stats.totalDueRub,
                    'itemTotalDueRub': fixture.items.first.totalDueRub,
                    'fontFamilies': [
                      'Gilroy',
                      'Root06CJK',
                      'MaterialIcons',
                      'packages/cupertino_icons/CupertinoIcons',
                    ],
                  }),
                ),
              );
            }
            FlutterError.onError = old;
            if (!baseline) {
              expect(
                firstInitiallyVisible,
                true,
                reason:
                    'First product must be visible before scrolling: $initialY',
              );
              expect(
                inputY,
                lessThan(700),
                reason:
                    'Participant form should precede expanded import options',
              );
              expect(errors, isEmpty);
            }
            await t.pumpWidget(const SizedBox.shrink());
            await t.pump(const Duration(seconds: 1));
          });
        }
      }
    }
  }
}
