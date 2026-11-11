import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/core/persistence/shared_preferences_provider.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:twoalogisticcabineuser/src/core/ui/blurred_modal_bottom_sheet.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/self_buyout/data/self_buyout_models.dart';
import 'package:twoalogisticcabineuser/src/features/self_buyout/presentation/self_buyout_create_sheet.dart';
import 'package:twoalogisticcabineuser/src/features/self_buyout/presentation/self_buyout_verification_sheet.dart';
import 'package:twoalogisticcabineuser/src/features/shop/data/purchase_provider.dart';
import 'package:twoalogisticcabineuser/src/features/shop/data/shop_availability_provider.dart';
import 'package:twoalogisticcabineuser/src/features/shop/data/shop_provider.dart';
import 'package:twoalogisticcabineuser/src/features/shop/presentation/shop_screen.dart';
import 'package:twoalogisticcabineuser/src/features/shop/presentation/purchase_list_screen.dart';
import 'package:twoalogisticcabineuser/src/features/shop/domain/purchase_list.dart';
import 'keyboard_form_probe.dart';
import '../../helpers/keyboard_acceptance.dart';
import 'package:twoalogisticcabineuser/src/features/purchase_blanks/presentation/widgets/blank_item_form.dart';

Future<void> _host(
  WidgetTester tester,
  TargetPlatform platform,
  Widget child,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 700);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewInsets);
  SharedPreferences.setMockInitialValues({
    'tutorial_marketplaces': true,
    'tutorial_purchase_list': true,
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        activeClientCodeProvider.overrideWithValue('A-001'),
        activeClientCodeIdProvider.overrideWithValue(1),
        cartItemCountProvider.overrideWithValue(0),
        activePurchaseListProvider.overrideWith(
          (ref) async => PurchaseList(
            id: 1,
            status: 'draft',
            createdAt: DateTime(2026),
            items: const [
              PurchaseItem(
                id: 1,
                externalItemId: 'fixture',
                provider: '1688',
                title: 'Тестовый товар',
                quantity: 1,
                price: 12,
              ),
            ],
          ),
        ),
        shopAvailabilityProvider.overrideWith(
          (ref) async => MarketplaceAvailability.unavailable,
        ),
        shopCategoriesProvider.overrideWith((ref, arg) async => []),
        shopSearchProvider.overrideWith(
          (ref, arg) async => const ShopSearchResult(),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(platform: platform, fontFamily: 'Gilroy'),
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => AppKeyboardDismissRegion(child: child!),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform purchase list note above IME', (tester) async {
      await _host(tester, platform, const PurchaseListScreen());
      expect(await probeCurrentFormEditors(tester), 1);
    });
    testWidgets(
      '$platform correction route has no text inputs and keeps submit above IME',
      (tester) async {
        await _host(
          tester,
          platform,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showBlurredModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const SelfBuyoutCreateSheet.correctRequisites(
                  correctionRequest: SelfBuyoutRequest(
                    id: 1,
                    requestNumber: 'SB-1',
                    status: 'cancelled',
                    clientCodeId: 1,
                    requestedCnyAmount: 100,
                    paymentRubAmount: 1250,
                    clientCnyRubRate: 12.5,
                    amountEnteredIn: 'cny',
                  ),
                ),
              ),
              child: const Text('correction'),
            ),
          ),
        );
        await tester.tap(find.text('correction'));
        await tester.pumpAndSettle();
        expect(find.byType(EditableText), findsNothing);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final submit = find.text('Отправить на рассмотрение');
        expect(tester.getRect(submit).bottom, lessThanOrEqualTo(400));
      },
    );

    testWidgets(
      '$platform verification every contact field remains above IME',
      (tester) async {
        await _host(
          tester,
          platform,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showBlurredModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const SelfBuyoutVerificationSheet(
                  verification: SelfBuyoutVerification(
                    required: true,
                    status: 'required',
                    canSubmit: true,
                  ),
                ),
              ),
              child: const Text('verify'),
            ),
          ),
        );
        await tester.tap(find.text('verify'));
        await tester.pumpAndSettle();
        expect(
          await probeCurrentFormEditors(
            tester,
            minimumFields: 3,
            keyboardInset: 300,
          ),
          3,
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        final fields = find.byType(EditableText);
        expect(fields, findsNWidgets(3));
        for (var i = 0; i < fields.evaluate().length; i++) {
          await tester.ensureVisible(fields.at(i));
          await tester.pumpAndSettle();
          await tester.tap(fields.at(i));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final current = fields.at(i);
          final editor = tester.widget(current) is EditableText
              ? current
              : find.descendant(
                  of: current,
                  matching: find.byType(EditableText),
                );
          expectFocusedCaretAboveIme(tester, editor, keyboardTop: 400);
          expect(
            MediaQuery.viewInsetsOf(tester.element(fields.at(i))).bottom,
            0,
          );
        }
        await tester.tapAt(const Offset(5, 250));
        await tester.pump();
        expect(
          tester.widget<EditableText>(fields.last).focusNode.hasFocus,
          isFalse,
        );
      },
    );

    testWidgets(
      '$platform inline blank lower field remains visible and outside touch dismisses',
      (tester) async {
        await _host(
          tester,
          platform,
          SingleChildScrollView(
            child: BlankItemForm(
              onSave:
                  ({
                    required productName,
                    required productUrl,
                    characteristics,
                    required quantity,
                    required unitPrice,
                    newPhotos,
                    newPhotoNames,
                  }) async {},
            ),
          ),
        );
        expect(
          await probeCurrentFormEditors(
            tester,
            minimumFields: 5,
            keyboardInset: 300,
          ),
          5,
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        final fields = find.byType(TextFormField);
        for (var i = 0; i < fields.evaluate().length; i++) {
          final field = fields.at(i);
          await tester.ensureVisible(field);
          await tester.pumpAndSettle();
          await tester.tap(field);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expectFocusedCaretAboveIme(
            tester,
            find.descendant(of: field, matching: find.byType(EditableText)),
            keyboardTop: 400,
          );
        }
        await tester.tapAt(const Offset(5, 10));
        await tester.pump();
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText).last)
              .focusNode
              .hasFocus,
          isFalse,
        );
      },
    );

    testWidgets(
      '$platform shop price remains scrollable above compact keyboard',
      (tester) async {
        await _host(tester, platform, const ShopScreen());
        expect(await probeCurrentFormEditors(tester), 1);
        await tester.enterText(find.byType(TextField).first, 'shoe');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.tune));
        await tester.pumpAndSettle();
        expect(
          await probeCurrentFormEditors(
            tester,
            minimumFields: 2,
            keyboardInset: 480,
          ),
          2,
        );
        final fields = find.byType(TextField);
        await tester.tap(fields.at(1));
        await tester.pump();
        tester.view.viewInsets = const FakeViewPadding(bottom: 480);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final index in [1, 2]) {
          await tester.ensureVisible(fields.at(index));
          await tester.pumpAndSettle();
          await tester.tap(fields.at(index));
          await tester.pumpAndSettle();
          expect(
            tester.getBottomLeft(fields.at(index)).dy,
            lessThanOrEqualTo(220),
          );
        }
        final apply = find.widgetWithText(FilledButton, 'Применить');
        await tester.ensureVisible(apply);
        await tester.pumpAndSettle();
        expect(tester.getBottomLeft(apply).dy, lessThanOrEqualTo(220));
        await tester.tap(apply);
        await tester.pumpAndSettle();
        expect(find.text('Фильтр по цене (¥)'), findsNothing);
      },
    );

    testWidgets(
      '$platform self-buyout modal consumes IME once and dismisses focus',
      (tester) async {
        await _host(
          tester,
          platform,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showBlurredModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const SelfBuyoutCreateSheet(
                  availability: SelfBuyoutAvailability(
                    available: true,
                    clientCnyRubRate: 12.5,
                    minCny: 100,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(
          await probeCurrentFormEditors(
            tester,
            minimumFields: 2,
            keyboardInset: 300,
          ),
          2,
        );
        final field = find.byType(TextField).first;
        await tester.ensureVisible(field);
        await tester.tap(field);
        await tester.pump();
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final fields = find.byType(TextField);
        for (var i = 0; i < fields.evaluate().length; i++) {
          await tester.ensureVisible(fields.at(i));
          await tester.pumpAndSettle();
          await tester.tap(fields.at(i));
          await tester.pumpAndSettle();
          expect(
            MediaQuery.viewInsetsOf(tester.element(fields.at(i))).bottom,
            0,
          );
          final current = fields.at(i);
          final editor = tester.widget(current) is EditableText
              ? current
              : find.descendant(
                  of: current,
                  matching: find.byType(EditableText),
                );
          expectFocusedCaretAboveIme(tester, editor, keyboardTop: 400);
        }
        expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);
        // Touch a non-editor area inside the modal (not its dismissal barrier).
        await tester.tap(find.text('Новая заявка').first, warnIfMissed: false);
        await tester.pump();
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText).last)
              .focusNode
              .hasFocus,
          isFalse,
        );
      },
    );
  }
}
