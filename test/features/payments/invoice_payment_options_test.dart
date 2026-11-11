import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/auth_provider.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/payments/data/invoice_payment_method_drafts.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/domain/invoice_item.dart';
import 'package:twoalogisticcabineuser/src/features/invoices/presentation/invoices_screen.dart';
import 'package:twoalogisticcabineuser/src/features/payments/data/invoice_payment_options.dart';
import 'package:twoalogisticcabineuser/src/features/payments/presentation/invoice_payment_method_sheet.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/presentation/widgets/track_sheet_surface.dart';

class _Auth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    isLoggedIn: true,
    isLoading: false,
    clientId: 1,
    userDomain: 'agent.test',
  );
  void switchOwner({
    int id = 2,
    String? domain = 'agent.test',
    bool loggedIn = true,
  }) => state = AuthState(
    isLoggedIn: loggedIn,
    isLoading: false,
    clientId: id,
    userDomain: domain,
  );
}

class _Code extends Notifier<String?> {
  @override
  String? build() => 'TEST';
  void select(String? value) => state = value;
}

final _code = NotifierProvider<_Code, String?>(_Code.new);

class _Api extends ApiClient {
  String? lastPath;
  dynamic lastData;
  bool locked = false;
  int selections = 0;
  int fetches = 0;
  bool failSelection = false;
  String? unavailable;
  String? activeMethod;
  Completer<Response<dynamic>>? pendingSelection;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    lastPath = path;
    fetches++;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data:
          {
                'data': {
                  'methods': [
                    for (final method in [
                      'bank_qr',
                      'usdt_trc20',
                      'alipay',
                      'manager',
                    ])
                      {
                        'code': method,
                        'currency': method == 'alipay' ? 'CNY' : 'RUB',
                        'available': method != unavailable,
                      },
                  ],
                  'activeMethod': locked ? 'alipay' : activeMethod,
                  'canChange': !locked,
                  'lockedReason': locked ? 'payment_review' : null,
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
    selections++;
    lastPath = path;
    lastData = data;
    if (pendingSelection != null) {
      return await pendingSelection!.future as Response<T>;
    }
    if (failSelection) {
      locked = true;
      throw StateError('locked concurrently');
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data:
          {
                'data': {
                  'method': data['method'],
                  'paymentId': 77,
                  'currency': 'USDT',
                  'amount': '123.45',
                  'qrImageUrl': '/uploads/qr.png',
                  'walletAddress': 'TWallet',
                  'network': 'TRC20',
                  'canChange': true,
                },
              }
              as T,
    );
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _Api api, {
  Locale locale = const Locale('ru'),
  String invoiceId = '12',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_Auth.new),
        activeClientCodeProvider.overrideWith((ref) => ref.watch(_code)),
        invoicePaymentOptionsServiceProvider.overrideWithValue(
          InvoicePaymentOptionsService(api),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('ru'), Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<InvoicePaymentSelection>(
                context: context,
                isScrollControlled: true,
                builder: (_) => InvoicePaymentMethodSheet(invoiceId: invoiceId),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.text('open')));
}

Future<void> _pay(WidgetTester tester) async {
  await tester.tap(find.byType(TrackSheetPrimaryButton));
  await tester.pumpAndSettle();
}

void main() {
  Map<String, dynamic> resumePayload({
    bool? receiptOnly,
    bool available = false,
    bool canResume = false,
    bool canChange = true,
    String? lockedReason,
    String activeMethod = 'usdt_trc20',
    bool pending = true,
  }) => {
    'methods': [
      {'code': 'usdt_trc20', 'currency': 'USDT', 'available': available},
      {'code': 'alipay', 'currency': 'CNY', 'available': true},
    ],
    'activeMethod': activeMethod,
    'canChange': canChange,
    'canResumeActivePayment': canResume,
    'lockedReason': lockedReason,
    'activePayment': {
      'method': 'usdt_trc20',
      'paymentId': 9,
      'currency': 'USDT',
      'amount': '100.00',
      'canChange': pending,
      'qrImageUrl': '/uploads/old-qr.png',
      'walletAddress': 'OLD-WALLET',
      if (receiptOnly != null) 'receiptOnly': receiptOnly,
    },
  };

  test(
    'legacy unavailable manual payment resumes only for receipt submission',
    () {
      final legacy = InvoicePaymentOptions.fromJson(resumePayload());
      expect(legacy.resumablePayment()?.paymentId, 9);
      expect(legacy.resumablePayment()?.receiptOnly, true);
      expect(legacy.resumablePayment(draftMethod: 'alipay'), isNull);
    },
  );
  test(
    'new server receipt-only permit is honored without enabling a new payment',
    () {
      final current = InvoicePaymentOptions.fromJson(
        resumePayload(receiptOnly: true, canResume: true),
      );
      expect(current.resumablePayment()?.receiptOnly, true);
      expect(current.methods.first.available, false);
    },
  );
  test(
    'explicit new refusal and lock/status/method mismatches never resume',
    () {
      for (final payload in [
        resumePayload(receiptOnly: false),
        resumePayload(receiptOnly: true, canResume: false),
        resumePayload(canChange: false),
        resumePayload(lockedReason: 'payment_in_review'),
        resumePayload(activeMethod: 'alipay'),
        resumePayload(pending: false),
      ]) {
        expect(
          InvoicePaymentOptions.fromJson(payload).resumablePayment(),
          isNull,
        );
      }
    },
  );

  test(
    'foreign invoice method persists and review/paid cannot reopen payment',
    () {
      for (final method in ['usdt_trc20', 'alipay']) {
        for (final status in [
          'unpaid',
          'processing',
          'payment_review',
          'paid',
          'cancelled',
        ]) {
          final item = InvoiceItem.fromJson({
            'id': 12,
            'invoiceNumber': 'INV-12',
            'status': status,
            'paymentMethod': method,
            'paymentProvider': 'manual',
          });
          expect(item.paymentMethod, method);
          expect(item.paymentProvider, 'manual');
          expect(
            canOpenInvoicePayment(item),
            status == 'unpaid' || status == 'processing',
          );
        }
      }
    },
  );

  test('service preserves invoice scope and foreign decimal amount', () async {
    final api = _Api();
    final service = InvoicePaymentOptionsService(api);
    final options = await service.fetch('12');
    expect(api.lastPath, '/client/invoices/12/payment-options');
    expect(options.methods.length, 4);
    final selection = await service.select('12', 'usdt_trc20');
    expect(api.lastPath, '/client/invoices/12/payment-method');
    expect(api.lastData, {'method': 'usdt_trc20'});
    expect(selection.amount, 123.45);
    expect(selection.paymentId, 77);
    expect(selection.currency, 'USDT');
  });

  test('foreign payment rejects missing credentials and invalid amount', () {
    for (final value in [null, 'NaN', '0', '-1']) {
      expect(
        () => InvoicePaymentSelection.fromJson({
          'method': 'usdt_trc20',
          'amount': value,
        }),
        throwsFormatException,
      );
    }
  });

  testWidgets('review locks all choices without selection requests', (
    tester,
  ) async {
    final api = _Api()..locked = true;
    await _pump(tester, api);
    expect(find.byType(TrackSheetOptionTile), findsNothing);
    expect(find.textContaining('Пока чек на проверке'), findsOneWidget);
    expect(api.selections, 0);
    expect(find.textContaining('Отозвать'), findsNothing);
  });

  testWidgets('four choices submit selected code and no legacy creation', (
    tester,
  ) async {
    final api = _Api();
    await _pump(tester, api);
    expect(find.byType(TrackSheetSurface), findsOneWidget);
    expect(find.byType(TrackSheetPrimaryButton), findsOneWidget);
    expect(find.byType(TrackSheetOptionTile), findsNWidgets(4));
    await tester.tap(find.text('Оплатить USDT · TRC20'));
    await tester.pumpAndSettle();
    expect(api.selections, 0);
    expect(
      tester
          .widget<TrackSheetOptionTile>(find.byType(TrackSheetOptionTile).at(1))
          .selected,
      isTrue,
    );
    await _pay(tester);
    expect(api.lastPath, '/client/invoices/12/payment-method');
    expect(api.lastData, {'method': 'usdt_trc20'});
    expect(api.selections, 1);
  });

  testWidgets('concurrent review refreshes lock after failed switch', (
    tester,
  ) async {
    final api = _Api()..failSelection = true;
    await _pump(tester, api);
    await tester.tap(find.text('Оплатить USDT · TRC20'));
    await tester.pumpAndSettle();
    await _pay(tester);
    expect(find.byType(TrackSheetOptionTile), findsNothing);
    expect(find.textContaining('Пока чек на проверке'), findsOneWidget);
    expect(api.selections, 1);
  });

  testWidgets('choice survives close and reopen without creating a payment', (
    tester,
  ) async {
    final api = _Api();
    await _pump(tester, api);
    expect(
      tester
          .widget<TrackSheetPrimaryButton>(find.byType(TrackSheetPrimaryButton))
          .onTap,
      isNull,
    );
    await tester.tap(find.text('Оплатить USDT · TRC20'));
    await tester.pumpAndSettle();
    expect(api.selections, 0);
    Navigator.of(tester.element(find.byType(InvoicePaymentMethodSheet))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final tile = tester.widget<TrackSheetOptionTile>(
      find.byType(TrackSheetOptionTile).at(1),
    );
    expect(tile.selected, isTrue);
    expect(tile.radioIndicator, isTrue);
    expect(api.selections, 0);
    await _pay(tester);
    expect(api.selections, 1);
  });

  for (final change in ['client', 'agent', 'code', 'logout']) {
    testWidgets('draft does not cross $change and stale sheet cannot pay', (
      tester,
    ) async {
      final api = _Api();
      final container = await _pump(tester, api);
      await tester.tap(find.text('Оплатить USDT · TRC20'));
      await tester.pumpAndSettle();
      final oldDrafts = container.read(invoicePaymentMethodDraftsProvider);
      switch (change) {
        case 'client':
          (container.read(authProvider.notifier) as _Auth).switchOwner();
        case 'agent':
          (container.read(authProvider.notifier) as _Auth).switchOwner(
            id: 1,
            domain: 'other.test',
          );
        case 'code':
          container.read(_code.notifier).select('OTHER');
        case 'logout':
          (container.read(authProvider.notifier) as _Auth).switchOwner(
            id: 1,
            loggedIn: false,
          );
      }
      await tester.pumpAndSettle();
      final newDrafts = container.read(invoicePaymentMethodDraftsProvider);
      expect(identical(oldDrafts, newDrafts), isFalse);
      expect(newDrafts.selected('12'), isNull);
      expect(find.textContaining('Выбранный клиент изменился'), findsOneWidget);
      expect(
        tester
            .widget<TrackSheetPrimaryButton>(
              find.byType(TrackSheetPrimaryButton),
            )
            .onTap,
        isNull,
      );
      expect(api.selections, 0);
    });
  }

  testWidgets('unavailable saved choice is discarded on reopen', (
    tester,
  ) async {
    final api = _Api();
    await _pump(tester, api);
    await tester.tap(find.text('Оплатить USDT · TRC20'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(InvoicePaymentMethodSheet))).pop();
    await tester.pumpAndSettle();
    api.unavailable = 'usdt_trc20';
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TrackSheetOptionTile>(find.byType(TrackSheetOptionTile).at(1))
          .selected,
      isFalse,
    );
    expect(
      tester
          .widget<TrackSheetPrimaryButton>(find.byType(TrackSheetPrimaryButton))
          .onTap,
      isNull,
    );
    expect(api.selections, 0);
  });

  testWidgets('foreign card label states rubles and starts only on Pay', (
    tester,
  ) async {
    final api = _Api();
    await _pump(tester, api);
    final title = find.text('Оплатить рублями картой нероссийского банка');
    expect(title, findsOneWidget);
    await tester.ensureVisible(title);
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(api.selections, 0);
    await _pay(tester);
    expect(api.lastData, {'method': 'manager'});
    expect(api.selections, 1);
    expect(find.byType(InvoicePaymentMethodSheet), findsNothing);
  });

  testWidgets(
    'same owner code refresh disables payment while unknown and restores exact draft',
    (tester) async {
      final api = _Api();
      final container = await _pump(tester, api);
      await tester.tap(find.text('Оплатить USDT · TRC20'));
      await tester.pumpAndSettle();
      Navigator.of(
        tester.element(find.byType(InvoicePaymentMethodSheet)),
      ).pop();
      await tester.pumpAndSettle();
      container.read(_code.notifier).select(null);
      await tester.pump();
      expect(
        container.read(invoicePaymentMethodDraftsProvider).enabled,
        isFalse,
      );
      expect(
        container.read(invoicePaymentMethodDraftsProvider).selected('12'),
        isNull,
      );
      container.read(_code.notifier).select('TEST');
      await tester.pump();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TrackSheetOptionTile>(
              find.byType(TrackSheetOptionTile).at(1),
            )
            .selected,
        isTrue,
      );
      expect(api.selections, 0);
    },
  );

  for (final loggedIn in [true, false]) {
    testWidgets(
      'nullable restored domain ${loggedIn ? 'allows valid authenticated Pay' : 'does not enable logged-out Pay'}',
      (tester) async {
        final api = _Api();
        final container = await _pump(tester, api);
        Navigator.of(
          tester.element(find.byType(InvoicePaymentMethodSheet)),
        ).pop();
        await tester.pumpAndSettle();
        (container.read(authProvider.notifier) as _Auth).switchOwner(
          id: 1,
          domain: null,
          loggedIn: loggedIn,
        );
        await tester.pump();
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        final tile = tester.widget<TrackSheetOptionTile>(
          find.byType(TrackSheetOptionTile).at(1),
        );
        if (loggedIn) {
          expect(tile.onTap, isNotNull);
          await tester.tap(find.text('Оплатить USDT · TRC20'));
          await tester.pumpAndSettle();
          expect(api.selections, 0);
          await _pay(tester);
          expect(api.selections, 1);
          expect(api.lastData, {'method': 'usdt_trc20'});
          expect(find.byType(InvoicePaymentMethodSheet), findsNothing);
        } else {
          expect(tile.onTap, isNull);
          expect(
            tester
                .widget<TrackSheetPrimaryButton>(
                  find.byType(TrackSheetPrimaryButton),
                )
                .onTap,
            isNull,
          );
          expect(api.selections, 0);
        }
      },
    );
  }

  testWidgets('latest valid draft wins over an older server method on reopen', (
    tester,
  ) async {
    final api = _Api()..activeMethod = 'alipay';
    await _pump(tester, api);
    expect(
      tester
          .widget<TrackSheetOptionTile>(find.byType(TrackSheetOptionTile).at(2))
          .selected,
      isTrue,
    );
    await tester.tap(find.text('Оплатить USDT · TRC20'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(InvoicePaymentMethodSheet))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TrackSheetOptionTile>(find.byType(TrackSheetOptionTile).at(1))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<TrackSheetOptionTile>(find.byType(TrackSheetOptionTile).at(2))
          .selected,
      isFalse,
    );
    expect(api.selections, 0);
  });

  for (final failed in [false, true]) {
    testWidgets(
      'account change ignores pending payment ${failed ? 'failure' : 'success'} without refetching',
      (tester) async {
        final api = _Api()..pendingSelection = Completer<Response<dynamic>>();
        final container = await _pump(tester, api);
        await tester.tap(find.text('Оплатить USDT · TRC20'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(TrackSheetPrimaryButton));
        await tester.pump();
        expect(api.selections, 1);
        (container.read(authProvider.notifier) as _Auth).switchOwner();
        await tester.pump();
        if (failed) {
          api.pendingSelection!.completeError(StateError('offline'));
        } else {
          api.pendingSelection!.complete(
            Response(
              requestOptions: RequestOptions(path: '/fake'),
              data: {
                'data': {'method': 'manager', 'canChange': true},
              },
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(find.byType(InvoicePaymentMethodSheet), findsOneWidget);
        expect(
          find.textContaining('Выбранный клиент изменился'),
          findsOneWidget,
        );
        expect(api.fetches, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('invoice drafts remain isolated and bounded without payment data', () {
    final drafts = InvoicePaymentMethodDrafts(enabled: true);
    drafts.select('12', 'alipay');
    expect(drafts.selected('13'), isNull);
    for (var i = 0; i < 129; i++) {
      drafts.select('invoice-$i', 'bank_qr');
    }
    expect(drafts.selected('12'), isNull);
    expect(drafts.selected('invoice-128'), 'bank_qr');
  });

  for (final locale in [const Locale('ru'), const Locale('zh')]) {
    for (final width in [280.0, 320.0, 390.0, 600.0]) {
      testWidgets('choices fit $width ${locale.languageCode} with large text', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pump(tester, _Api(), locale: locale);
        await tester.ensureVisible(find.byType(TrackSheetOptionTile).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final close = find.byType(TrackSheetPrimaryButton);
        expect(tester.getBottomRight(close).dy, lessThanOrEqualTo(640));
        expect(tester.getTopLeft(close).dy, greaterThan(0));
      });
    }
  }
}
