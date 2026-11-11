import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_target.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/core/persistence/shared_preferences_provider.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/auth_provider.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/home/data/current_cny_rate_provider.dart';
import 'package:twoalogisticcabineuser/src/features/home/data/home_counts_provider.dart';
import 'package:twoalogisticcabineuser/src/features/home/presentation/home_payment_attention.dart';
import 'package:twoalogisticcabineuser/src/features/home/presentation/home_screen.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/data/invoices_provider.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/domain/invoice_item.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/presentation/invoices_screen.dart';
import 'package:twoalogisticcabineuser/src/features/payments/data/payment_operator_status.dart';
import 'package:twoalogisticcabineuser/src/features/payments/data/invoice_payment_options.dart';
import 'package:twoalogisticcabineuser/src/features/payments/data/bank_qr_payment.dart';
import 'package:twoalogisticcabineuser/src/features/payments/presentation/invoice_payment_method_sheet.dart';
import 'package:twoalogisticcabineuser/src/features/payments/presentation/bank_qr_payment_screen.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/presentation/widgets/track_sheet_surface.dart';
import 'package:twoalogisticcabineuser/src/features/photos/data/photos_provider.dart';
import 'package:twoalogisticcabineuser/src/features/profile/data/profile_provider.dart';
import 'package:twoalogisticcabineuser/src/features/referral/data/referral_provider.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/data/tracks_provider.dart';
import 'package:twoalogisticcabineuser/src/features/assemblies/data/assemblies_provider.dart';
import '../../helpers/keyboard_acceptance.dart';

Map<String, dynamic> _row(int id) => {
  'id': '$id',
  'invoiceNumber': 'INV-$id',
  'status': 'unpaid',
  'statusName': 'Требует оплаты',
  'placesCount': 1,
  'totalCostUSD': 10.25,
  'totalCostRUB': 925.50,
};

class _Api extends ApiClient {
  final queries = <Map<String, dynamic>>[];
  bool empty = false;
  int rows = 1;
  bool hasMore = false;
  int failFirst = 0;
  int failNextPage = 0;
  Completer<Response<dynamic>>? pending;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    if (path.contains('fixture-qr')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data:
            base64Decode(
                  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
                )
                as T,
      );
    }
    if (path != '/invoices') {
      throw StateError('Unexpected request $path');
    }
    final query = Map<String, dynamic>.from(queryParameters!);
    queries.add(query);
    if (pending != null) {
      return await pending!.future as Response<T>;
    }
    if (failFirst > 0) {
      failFirst--;
      throw StateError('offline');
    }
    final skip = query['skip'] as int;
    if (skip > 0 && failNextPage > 0) {
      failNextPage--;
      throw StateError('next page offline');
    }
    final body = {
      'data': empty
          ? []
          : List.generate(
              rows,
              (index) => _row(skip == 0 ? index + 1 : rows + index + 1),
            ),
      'total': empty
          ? 0
          : hasMore
          ? 2
          : rows,
      'hasMore': hasMore && skip == 0,
    };
    return Response<T>(
      data: body as T,
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
    );
  }

  @override
  Future<Response<T>> getWithProgress<T>(
    String path, {
    Options? options,
    required ProgressCallback onReceiveProgress,
  }) => get<T>(path, options: options);
  @override
  Future<String?> getToken() async => null;
}

class _PaymentApi extends ApiClient {
  int fetches = 0;
  int selections = 0;
  int bankStarts = 0;
  bool prepared = false;
  bool unavailable = false;
  bool resumeContract = true;
  bool? resumeDecision;
  bool omitActivePayment = false;
  String preparedMethod = 'bank_qr';
  String? lockedReason;
  Map<String, dynamic> get selection => <String, dynamic>{
    'method': preparedMethod,
    'paymentId': 77,
    'currency': preparedMethod == 'alipay'
        ? 'CNY'
        : preparedMethod == 'usdt_trc20'
        ? 'USDT'
        : 'RUB',
    if (preparedMethod != 'bank_qr') 'qrImageUrl': '/uploads/fixture-qr.png',
    if (preparedMethod == 'usdt_trc20') 'walletAddress': 'TFixtureWallet',
    if (preparedMethod == 'usdt_trc20') 'network': 'TRC20',
    'amount': '925.50',
    'sumKopecks': 92550,
    'qrPayload': 'ST00012|Name=Fixture|Sum=92550',
    'purpose': 'INV-1',
    'canChange': true,
  };
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    fetches++;
    return Response(
      requestOptions: RequestOptions(path: path),
      data:
          {
                'data': {
                  'methods': [
                    {
                      'code': 'bank_qr',
                      'currency': 'RUB',
                      'available': !unavailable,
                    },
                    for (final method in ['usdt_trc20', 'alipay'])
                      {
                        'code': method,
                        'currency': method == 'alipay' ? 'CNY' : 'USDT',
                        'available': !unavailable,
                      },
                    {'code': 'manager', 'currency': 'RUB', 'available': true},
                  ],
                  'activeMethod': prepared ? preparedMethod : 'manager',
                  'canChange': lockedReason == null,
                  'lockedReason': lockedReason,
                  'activePayment': prepared && !omitActivePayment
                      ? selection
                      : null,
                  if (resumeContract)
                    'canResumeActivePayment':
                        resumeDecision ??
                        (prepared && lockedReason == null && !unavailable),
                },
              }
              as T,
    );
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    if (path == '/client/invoices/1/bank-qr/start') {
      bankStarts++;
      expect(data, const <String, dynamic>{});
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data:
            {
                  'paymentId': 77,
                  'invoiceId': 1,
                  'invoiceNumber': 'INV-1',
                  'amountRub': 925.50,
                  'sumKopecks': 92550,
                  'purpose': 'INV-1',
                  'qrPayload': 'ST00012|Name=Fixture|Sum=92550',
                  'status': 'pending',
                  'reused': true,
                }
                as T,
      );
    }
    selections++;
    expect(path, '/client/invoices/1/payment-method');
    expect(data, {'method': 'bank_qr'});
    prepared = true;
    return Response(
      requestOptions: RequestOptions(path: path),
      data: {'data': selection} as T,
    );
  }
}

class _NeverStartPayment extends BankQrPaymentService {
  _NeverStartPayment(super.api);
  int starts = 0;
  @override
  Future<BankQrPaymentResult?> startBankQrPayment(String invoiceId) async {
    starts++;
    throw StateError('Existing prepared invoice must not create new payment');
  }
}

class _LoggedIn extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    isLoggedIn: true,
    isLoading: false,
    clientId: 1,
    userDomain: 'test.example',
  );
  void switchClient() => state = const AuthState(
    isLoggedIn: true,
    isLoading: false,
    clientId: 2,
    userDomain: 'other.example.test',
  );
}

class _Code extends Notifier<String?> {
  @override
  String? build() => 'TEST';
  void select(String? value) => state = value;
}

final _code = NotifierProvider<_Code, String?>(_Code.new);

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<({GoRouter router, ProviderContainer container})> _host(
  WidgetTester tester,
  _Api api, {
  double width = 390,
  bool realHome = false,
  bool realInvoices = false,
  _PaymentApi? paymentApi,
  BankQrPaymentService? bankPayments,
  ClientProfile? profile,
  TargetPlatform? platform,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'terms_accepted': true,
    'tutorial_home': true,
    'tutorial_invoices': true,
    'payment.qr.rules.v1.invoice:1:77': true,
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      apiClientProvider.overrideWithValue(api),
      if (paymentApi != null)
        invoicePaymentOptionsServiceProvider.overrideWithValue(
          InvoicePaymentOptionsService(paymentApi),
        ),
      if (bankPayments != null)
        bankQrPaymentServiceProvider.overrideWithValue(bankPayments),
      authProvider.overrideWith(_LoggedIn.new),
      activeClientCodeProvider.overrideWith((ref) => ref.watch(_code)),
      clientProfileProvider.overrideWith((ref) async => profile),
      homeTracksCountProvider.overrideWith((ref, code) async => 0),
      homePendingTracksCountProvider.overrideWith((ref, code) async => 0),
      homeAssembliesCountProvider.overrideWith((ref, code) async => 0),
      invoicesCountProvider.overrideWith((ref, code) async => 7),
      tracksWeeklyCountProvider.overrideWith((ref, code) async => 0),
      tracksDigestProvider.overrideWith((ref, code) async => []),
      assembliesDigestProvider.overrideWith((ref, code) async => []),
      invoicesDigestProvider.overrideWith((ref, code) async => []),
      photosRecentProvider.overrideWith((ref, arg) async => []),
      currentCnyRateProvider.overrideWith((ref) async => null),
      referralProvider.overrideWith(
        (ref) async => const ReferralData(
          referralKgBalance: 0,
          referrals: [],
          transactions: [],
        ),
      ),
      invoiceStatusesProvider.overrideWith((ref) async => []),
      invoiceByIdProvider.overrideWith(
        (ref, id) async => InvoiceItem.fromJson(_row(int.parse(id))),
      ),
      paymentOperatorStatusProvider.overrideWith(
        (ref) => Stream.value(
          PaymentOperatorStatus(sleeping: false, reachable: true),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: realInvoices
              ? const InvoicesScreen(initialInvoiceId: '1')
              : realHome
              ? const HomeScreen()
              : const Padding(
                  padding: EdgeInsets.all(16),
                  child: HomePaymentAttentionCard(clientCode: 'TEST', count: 7),
                ),
        ),
      ),
      GoRoute(
        path: '/invoices',
        builder: (_, _) => const Scaffold(body: Text('INVOICE_ROUTE')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: ThemeData(fontFamily: 'Gilroy', platform: platform),
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
      ),
    ),
  );
  await _frames(tester);
  return (router: router, container: container);
}

Future<void> _open(WidgetTester tester) async {
  final card = find.byKey(const ValueKey('home-payment-attention'));
  await tester.ensureVisible(card);
  await tester.tap(card);
  await _frames(tester);
}

void main() {
  setUpAll(() async {
    await loadKeyboardAcceptanceFonts();
    await initializeDateFormatting('ru');
  });
  for (final entry in ['home', 'invoices']) {
    testWidgets(
      'actual $entry invoice prepared QR closes and resumes without selecting again',
      (tester) async {
        final paymentApi = _PaymentApi();
        final bank = _NeverStartPayment(paymentApi);
        final host = await _host(
          tester,
          _Api(),
          realHome: entry == 'home',
          realInvoices: entry == 'invoices',
          paymentApi: paymentApi,
          bankPayments: bank,
        );
        if (entry == 'home') {
          await _open(tester);
          await tester.tap(find.text('INV-1'));
          await _frames(tester);
        } else {
          await _frames(tester);
        }
        final pay = find.byWidgetPredicate(
          (widget) => widget is TrainingTarget && widget.id == 'invoice.pay',
        );
        expect(pay, findsOneWidget);
        await tester.tap(pay);
        await _frames(tester);
        expect(find.byType(InvoicePaymentMethodSheet), findsOneWidget);
        await tester.tap(find.text('Оплатить в рублях'));
        await _frames(tester);
        await tester.tap(
          find.descendant(
            of: find.byType(InvoicePaymentMethodSheet),
            matching: find.byType(TrackSheetPrimaryButton),
          ),
        );
        await _frames(tester);
        expect(find.byType(BankQrPaymentSheet), findsOneWidget);
        expect(paymentApi.selections, 1);
        expect(bank.starts, 0);
        Navigator.of(
          tester.element(find.byType(BankQrPaymentSheet)),
        ).pop(false);
        await _frames(tester);
        // Model a same-client code refresh between closing and reopening.
        host.container.read(_code.notifier).select(null);
        await _frames(tester);
        host.container.read(_code.notifier).select('TEST');
        await _frames(tester);
        await tester.tap(pay);
        await _frames(tester);
        expect(find.byType(InvoicePaymentMethodSheet), findsNothing);
        expect(find.byType(BankQrPaymentSheet), findsOneWidget);
        expect(find.text('Приложить чек'), findsOneWidget);
        expect(paymentApi.selections, 1);
        expect(bank.starts, 0);
        final change = find.text('Изменить способ оплаты');
        await tester.ensureVisible(change);
        await tester.tap(change);
        await _frames(tester);
        expect(find.byType(BankQrPaymentSheet), findsNothing);
        expect(find.byType(InvoicePaymentMethodSheet), findsOneWidget);
        final tile = tester.widget<TrackSheetOptionTile>(
          find.byType(TrackSheetOptionTile).first,
        );
        expect(tile.selected, isTrue);
        expect(paymentApi.selections, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'explicit resume denial keeps saved method preselected without opening QR',
    (tester) async {
      final api = _PaymentApi()
        ..prepared = true
        ..resumeDecision = false;
      final bank = _NeverStartPayment(api);
      await _host(
        tester,
        _Api(),
        realHome: true,
        paymentApi: api,
        bankPayments: bank,
      );
      await _open(tester);
      await tester.tap(find.text('INV-1'));
      await _frames(tester);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is TrainingTarget && widget.id == 'invoice.pay',
        ),
      );
      await _frames(tester);
      expect(find.byType(BankQrPaymentSheet), findsNothing);
      expect(find.byType(InvoicePaymentMethodSheet), findsOneWidget);
      expect(
        tester
            .widget<TrackSheetOptionTile>(
              find.byType(TrackSheetOptionTile).first,
            )
            .selected,
        isTrue,
      );
      expect(api.selections, 0);
      expect(bank.starts, 0);
    },
  );
  for (final method in ['bank_qr', 'usdt_trc20', 'alipay']) {
    testWidgets('legacy $method direct window without choosing again', (
      tester,
    ) async {
      final api = _PaymentApi()
        ..prepared = true
        ..resumeContract = false
        ..preparedMethod = method
        ..omitActivePayment = (method == 'bank_qr');
      final bank = BankQrPaymentService(api);
      await _host(
        tester,
        _Api(),
        realHome: true,
        paymentApi: api,
        bankPayments: bank,
      );
      await _open(tester);
      await tester.tap(find.text('INV-1'));
      await _frames(tester);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is TrainingTarget && widget.id == 'invoice.pay',
        ),
      );
      await _frames(tester);
      expect(find.byType(InvoicePaymentMethodSheet), findsNothing);
      expect(find.byType(BankQrPaymentSheet), findsOneWidget);
      expect(
        tester
            .widget<BankQrPaymentSheet>(find.byType(BankQrPaymentSheet))
            .selection
            ?.method,
        method,
      );
      expect(api.selections, 0);
      expect(api.bankStarts, method == 'bank_qr' ? 1 : 0);
      expect(find.text('Приложить чек'), findsOneWidget);
      final change = find.text('Изменить способ оплаты');
      await tester.ensureVisible(change);
      await tester.tap(change);
      await _frames(tester);
      expect(find.byType(InvoicePaymentMethodSheet), findsOneWidget);
      expect(api.selections, 0);
      expect(tester.takeException(), isNull);
    });
  }
  for (final blocked in ['explicit false', 'locked', 'unavailable']) {
    testWidgets('legacy compatibility respects $blocked', (tester) async {
      final api = _PaymentApi()
        ..prepared = true
        ..resumeContract = (blocked == 'explicit false')
        ..resumeDecision = false
        ..omitActivePayment = true;
      if (blocked == 'locked') api.lockedReason = 'payment_in_review';
      if (blocked == 'unavailable') api.unavailable = true;
      await _host(
        tester,
        _Api(),
        realHome: true,
        paymentApi: api,
        bankPayments: BankQrPaymentService(api),
      );
      await _open(tester);
      await tester.tap(find.text('INV-1'));
      await _frames(tester);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is TrainingTarget && widget.id == 'invoice.pay',
        ),
      );
      await _frames(tester);
      expect(find.byType(BankQrPaymentSheet), findsNothing);
      expect(find.byType(InvoicePaymentMethodSheet), findsOneWidget);
      expect(api.selections, 0);
      expect(api.bankStarts, 0);
    });
  }
  test(
    'resume decision distinguishes absent legacy capability from explicit false',
    () {
      final legacy = InvoicePaymentOptions.fromJson({
        'canChange': true,
        'methods': [],
      });
      final denied = InvoicePaymentOptions.fromJson({
        'canChange': true,
        'methods': [],
        'canResumeActivePayment': false,
      });
      expect(legacy.hasResumeDecision, isFalse);
      expect(denied.hasResumeDecision, isTrue);
      expect(denied.canResumeActivePayment, isFalse);
    },
  );
  for (final invoiceCount in [1, 20]) {
    for (final held in [false, true]) {
      testWidgets(
        'iPhone actual payment modal $invoiceCount invoices near-bottom ${held ? 'held20px spring return' : 'fast35px flick dismiss'}',
        (tester) async {
          await _host(
            tester,
            _Api()..rows = invoiceCount,
            platform: TargetPlatform.iOS,
          );
          tester.view.padding = const FakeViewPadding(bottom: 34);
          tester.view.viewPadding = const FakeViewPadding(bottom: 34);
          await _open(tester);
          final sheet = find.byKey(
            const ValueKey('home-payment-invoices-sheet'),
          );
          final header = find.byKey(
            const ValueKey('home-payment-invoices-header'),
          );
          final list = find.byKey(const ValueKey('home-payment-invoice-list'));
          final scroll = tester.state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)).first,
          );
          expect(
            scroll.position.pixels,
            closeTo(scroll.position.minScrollExtent, .01),
          );
          if (invoiceCount > 1) {
            expect(scroll.position.maxScrollExtent, greaterThan(0));
          }
          final pullDistance = held ? 20.0 : 35.0;
          final initialTop = tester.getTopLeft(header).dy;
          final viewport = tester.getRect(list);
          final start = Offset(viewport.center.dx, viewport.bottom - 42);
          expect(start.dy + pullDistance, lessThan(viewport.bottom));
          final gesture = await tester.createGesture();
          await gesture.down(start, timeStamp: Duration.zero);
          await gesture.moveBy(
            Offset(0, pullDistance),
            timeStamp: const Duration(milliseconds: 25),
          );
          await tester.pump();
          if (held) {
            final pulledTop = tester.getTopLeft(header).dy;
            expect(pulledTop, greaterThan(initialTop));
            await tester.pump(const Duration(milliseconds: 375));
            await gesture.up(timeStamp: const Duration(milliseconds: 400));
            await tester.pump();
            expect(sheet, findsOneWidget);
            expect(
              tester.getTopLeft(header).dy,
              greaterThan(initialTop),
              reason: 'held pull returns by spring rather than teleporting',
            );
            await tester.pump(const Duration(milliseconds: 40));
            final settling = tester.getTopLeft(header).dy;
            expect(settling, greaterThan(initialTop));
            expect(settling, lessThan(pulledTop));
            await tester.pumpAndSettle();
            expect(tester.getTopLeft(header).dy, closeTo(initialTop, .1));
          } else {
            await gesture.up(timeStamp: const Duration(milliseconds: 30));
            await tester.pumpAndSettle();
            expect(sheet, findsNothing);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final width in [320.0, 390.0]) {
    testWidgets(
      'actual Home payment card opens list then existing invoice detail without route change $width',
      (tester) async {
        final api = _Api();
        final host = await _host(tester, api, width: width, realHome: true);
        expect(find.text('Требуют оплаты: 7'), findsOneWidget);
        await _open(tester);
        expect(
          find.byKey(const ValueKey('home-payment-invoices-sheet')),
          findsOneWidget,
        );
        expect(find.text('Всего: 1'), findsOneWidget);
        final header = find.byKey(
          const ValueKey('home-payment-invoices-header'),
        );
        expect(
          (tester.widget<Container>(header).decoration as BoxDecoration)
              .gradient,
          isA<LinearGradient>(),
        );
        expect(
          tester.widget<Text>(find.text('Счета к оплате')).style?.color,
          Colors.white,
        );
        expect(tester.getSize(find.byTooltip('Закрыть')), const Size(44, 44));

        expect(find.byType(ClientInvoiceTile), findsOneWidget);
        expect(api.queries.single, {
          'clientCode': 'TEST',
          'skip': 0,
          'take': 50,
          'status': 'unpaid',
        });
        await tester.tap(find.text('INV-1'));
        await _frames(tester);
        expect(find.text('Счёт INV-1'), findsOneWidget);
        expect(find.text('Разбивка суммы и данные для оплаты'), findsOneWidget);
        expect(host.router.routeInformationProvider.value.uri.path, '/');
        expect(find.text('INVOICE_ROUTE'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [320.0, 390.0]) {
    testWidgets(
      'actual Home warehouse address/phone share row and preserve copy values $width',
      (tester) async {
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final profile = ClientProfile(
          id: 1,
          fullName: 'Тестовый клиент',
          email: 'fixture@example.test',
          balance: 0,
          isActive: true,
          codes: const [ClientCodeInfo(id: 1, code: 'TEST')],
          createdAt: DateTime(2026),
          agent: const AgentInfo(
            id: 1,
            name: '2A Test',
            warehouseAddress: ' 浙江义乌测试仓(不要隐藏代码 OLD) ',
            warehousePhone: ' +86 123456789 ',
          ),
        );
        final host = await _host(
          tester,
          _Api(),
          width: width,
          realHome: true,
          profile: profile,
        );
        final address = find.text('Адрес склада');
        final phone = find.text('Телефон склада');
        await tester.scrollUntilVisible(
          address,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await _frames(tester);
        final registry = host.container.read(trainingTargetRegistryProvider);
        final checkerTarget = registry.contextFor('warehouse.check');
        expect(checkerTarget, isNotNull);
        expect(
          registry.activationFor('warehouse.check', checkerTarget!),
          isNull,
          reason: 'A passive tour must not invoke the native image picker',
        );
        for (final label in [address, phone]) {
          final paragraph = tester.renderObject<RenderParagraph>(label);
          debugPrint(
            'warehouse label width=$width allocated=${paragraph.size.width} intrinsic=${paragraph.getMaxIntrinsicWidth(double.infinity)}',
          );
        }
        expect(
          tester.renderObject<RenderParagraph>(address).didExceedMaxLines,
          isFalse,
        );
        expect(
          tester.renderObject<RenderParagraph>(phone).didExceedMaxLines,
          isFalse,
        );
        final addressButton = find
            .ancestor(of: address, matching: find.byType(InkWell))
            .first;
        final phoneButton = find
            .ancestor(of: phone, matching: find.byType(InkWell))
            .first;
        expect(
          tester.getCenter(addressButton).dy,
          closeTo(tester.getCenter(phoneButton).dy, .01),
        );
        expect(tester.getSize(addressButton).height, 44);
        expect(tester.getSize(phoneButton).height, 44);
        expect(
          tester.getSize(addressButton).width,
          closeTo(tester.getSize(phoneButton).width, .01),
        );
        await tester.tap(addressButton);
        await _frames(tester);
        expect(copied, '浙江义乌测试仓(不要隐藏代码 TEST)');
        expect(find.text('Адрес склада скопирован'), findsOneWidget);
        await tester.tap(find.text('Понятно'));
        await _frames(tester);
        await tester.ensureVisible(phoneButton);
        await tester.tap(phoneButton);
        await _frames(tester);
        expect(copied, '+86 123456789');
        expect(find.text('Телефон склада скопирован'), findsOneWidget);
        expect(find.text('Адрес склада скопирован'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 4));
      },
    );
  }
  testWidgets(
    'server pagination retains earlier invoices and retries a failed next page',
    (tester) async {
      final api = _Api()
        ..hasMore = true
        ..failNextPage = 1;
      await _host(tester, api);
      await _open(tester);
      final more = find.byKey(const ValueKey('home-payment-invoices-more'));
      await tester.ensureVisible(more);
      await tester.tap(more);
      await _frames(tester);
      expect(find.text('INV-1'), findsOneWidget);
      expect(
        find.text('Не удалось загрузить следующую страницу'),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('home-payment-invoices-retry')),
      );
      await _frames(tester);
      expect(
        find.text('Не удалось загрузить следующую страницу'),
        findsNothing,
      );
      final second = find.text('INV-2');
      await tester.scrollUntilVisible(
        second,
        160,
        scrollable: find.byType(Scrollable).last,
      );
      expect(second, findsOneWidget);
      expect(api.queries.where((query) => query['skip'] == 50).length, 2);
      expect(api.queries.every((query) => query['status'] == 'unpaid'), isTrue);
      expect(
        find.byKey(const ValueKey('home-payment-invoices-more')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('initial invoice error has explicit retry', (tester) async {
    final api = _Api()..failFirst = 1;
    await _host(tester, api);
    await _open(tester);
    expect(find.text('Не удалось загрузить счета'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-payment-invoices-retry')));
    await _frames(tester);
    expect(find.text('INV-1'), findsOneWidget);
    expect(api.queries.length, 2);
  });
  testWidgets(
    'fresh server empty state replaces a cached positive home count',
    (tester) async {
      await _host(tester, _Api()..empty = true);
      await _open(tester);
      expect(find.text('Всего: 0'), findsOneWidget);
      expect(find.text('Нет счетов, требующих оплаты'), findsOneWidget);
      expect(find.byType(ClientInvoiceTile), findsNothing);
    },
  );
  testWidgets('changing active client code removes the old invoice list', (
    tester,
  ) async {
    final api = _Api();
    final host = await _host(tester, api);
    await _open(tester);
    expect(find.text('INV-1'), findsOneWidget);
    host.container.read(_code.notifier).select('OTHER');
    await _frames(tester);
    expect(find.byType(ClientInvoiceTile), findsNothing);
    expect(find.textContaining('Выбранный клиент изменился'), findsOneWidget);
    expect(api.queries.length, 1);
  });
  testWidgets(
    'same code with another authenticated client clears cached invoice rows',
    (tester) async {
      final api = _Api();
      final host = await _host(tester, api);
      await _open(tester);
      expect(find.text('INV-1'), findsOneWidget);
      (host.container.read(authProvider.notifier) as _LoggedIn).switchClient();
      await _frames(tester);
      expect(find.byType(ClientInvoiceTile), findsNothing);
      expect(find.textContaining('Выбранный клиент изменился'), findsOneWidget);
    },
  );
  testWidgets('loading invoice list can be dismissed', (tester) async {
    final api = _Api()..pending = Completer<Response<dynamic>>();
    await _host(tester, api);
    await _open(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byTooltip('Закрыть'));
    await _frames(tester);
    expect(
      find.byKey(const ValueKey('home-payment-invoices-sheet')),
      findsNothing,
    );
    api.pending!.complete(
      Response(
        data: {'data': [], 'total': 0, 'hasMore': false},
        requestOptions: RequestOptions(path: '/invoices'),
        statusCode: 200,
      ),
    );
    await _frames(tester);
    expect(tester.takeException(), isNull);
  });
}
