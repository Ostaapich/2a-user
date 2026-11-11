import 'package:twoalogisticcabineuser/src/features/garage/presentation/garage_conversation_card.dart';
import '../../helpers/keyboard_acceptance.dart';
import 'package:twoalogisticcabineuser/src/features/profile/presentation/profile_screen.dart';
import 'package:twoalogisticcabineuser/src/core/ui/blurred_modal_bottom_sheet.dart';
import 'package:twoalogisticcabineuser/src/features/profile/presentation/verified_phone_change_sheet.dart';
import 'package:twoalogisticcabineuser/src/features/profile/presentation/problem_report_sheet.dart';
import 'package:twoalogisticcabineuser/src/features/profile/data/profile_provider.dart';
import 'package:twoalogisticcabineuser/src/features/profile/data/problem_report_repository.dart';
import 'package:dio/dio.dart';
import 'package:twoalogisticcabineuser/src/features/clients/domain/client_codes_state.dart';
import 'package:flutter/foundation.dart';
import 'package:twoalogisticcabineuser/src/features/garage/application/garage_providers.dart';
import 'package:twoalogisticcabineuser/src/features/garage/data/garage_repository.dart';
import 'package:twoalogisticcabineuser/src/features/garage/domain/garage_models.dart';
import 'package:twoalogisticcabineuser/src/features/garage/presentation/garage_request_form_screen.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/referral/data/referral_provider.dart';
import 'package:twoalogisticcabineuser/src/features/referral/presentation/referral_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/auth_provider.dart';
import 'package:twoalogisticcabineuser/src/features/calculator/presentation/calculator_screen.dart';
import 'package:twoalogisticcabineuser/src/features/garage/presentation/garage_vehicle_form_screen.dart';

final _profile = ClientProfile(
  id: 17,
  fullName: 'Test Client',
  email: 'test@example.test',
  balance: 0,
  isActive: true,
  codes: const [],
  createdAt: DateTime(2026),
);

class _Codes extends ClientCodesController {
  @override
  Future<ClientCodesState> build() async =>
      const ClientCodesState(codes: [], activeCode: null);
}

class _Garage implements GarageRepository {
  @override
  Future<GarageMessagePage> getRequestMessages(
    int requestId, {
    int? cursor,
    int take = 100,
  }) async => GarageMessagePage(
    messages: [],
    nextCursor: null,
    unreadCount: 0,
    lastReadMessageId: null,
  );
  @override
  Future<List<GarageVehicle>> getVehicles() async => [
    GarageVehicle.fromJson({
      'id': 7,
      'vin': 'JTDKN3DU0D1234567',
      'make': 'Toyota',
      'model': 'Prius',
      'year': 2015,
    }),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(isLoading: false, clientId: 17);
}

class _Api implements ApiClient {
  int mutations = 0;
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    final body = switch (path) {
      '/tariffs' => {
        'tariffs': [
          {
            'id': 7,
            'name': 'Test tariff',
            'baseCost': 2,
            'pricingType': 'weight',
          },
        ],
      },
      '/photo-report-coefficients' => {'coefficients': []},
      '/packagings' => {'packagings': []},
      _ => <String, dynamic>{},
    };
    return Response<T>(
      data: body as T,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    if (path.contains('quote')) {
      return Response<T>(
        data: <String, dynamic>{'available': false} as T,
        statusCode: 200,
        requestOptions: RequestOptions(path: path),
      );
    }
    mutations++;
    throw StateError('Keyboard must not submit');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

Future<void> _pump(WidgetTester tester, Widget child, _Api api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        authProvider.overrideWith(_Auth.new),
        clientProfileProvider.overrideWith((ref) async => _profile),
        activeClientCodeProvider.overrideWithValue('A-001'),
        clientCodesControllerProvider.overrideWith(_Codes.new),
        garageRepositoryProvider.overrideWithValue(_Garage()),
        referralProvider.overrideWith(
          (ref) async => const ReferralData(
            referralKgBalance: 0,
            referrals: [],
            transactions: [],
          ),
        ),
      ],
      child: MaterialApp(
        builder: (_, child) => AppKeyboardDismissRegion(child: child!),
        home: Scaffold(body: child),
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(Scaffold).first),
  );
  await container.read(clientCodesControllerProvider.future);
  await container.read(garageVehiclesControllerProvider.future);
  await container.read(referralProvider.future);
  await _settle(tester);
}

Finder _label(String label) => find.ancestor(
  of: find.byWidgetPredicate(
    (widget) =>
        widget is InputDecorator && widget.decoration.labelText == label,
  ),
  matching: find.byType(TextFormField),
);

// Exercise the real fields without pressing business-submit controls. Each
// controller retains its draft after the keyboard is dismissed.
Future<void> _exerciseFields(WidgetTester tester, List<String> labels) async {
  for (final label in labels) {
    debugPrint("Keyboard field: $label");
    final field = _label(label);
    // Label is the real InputDecorator label, not a duplicate display text.
    await tester.scrollUntilVisible(
      field,
      180,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.ensureVisible(field);
    await _settle(tester);
    await tester.tap(field);
    final editableFinder = find.descendant(
      of: field,
      matching: find.byType(EditableText),
    );
    final editable = tester.widget<EditableText>(editableFinder);
    await tester.enterText(
      field,
      editable.keyboardType == TextInputType.number
          ? '2020'
          : label == 'VIN'
          ? 'JTDKN3DU0D1234567'
          : 'draft',
    );
    await _settle(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await _settle(tester);

    expectFocusedCaretAboveIme(
      tester,
      editableFinder,
      keyboardTop: tester.view.physicalSize.height - 280,
    );
    final value = editable.controller.text;
    expect(value, isNotEmpty, reason: label);
    FocusManager.instance.primaryFocus?.unfocus();
    tester.view.resetViewInsets();
    await _settle(tester);
    expect(editable.controller.text, value, reason: label);
  }
}

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'profile all five edit/password fields retain drafts ${platform.name}',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetViewInsets();
        });
        final api = _Api();
        await _pump(tester, const ProfileScreen(), api);
        final edit = find.text('Изменить');
        await tester.scrollUntilVisible(
          edit,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(edit);
        await _settle(tester);
        for (final label in [
          'ФИО',
          'Email',
          'Текущий пароль',
          'Новый пароль',
          'Подтвердите новый пароль',
        ]) {
          if (label == 'Текущий пароль') {
            final change = find.text('Сменить пароль');
            await tester.scrollUntilVisible(
              change,
              180,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.tap(change);
            await _settle(tester);
          }
          final field = find.widgetWithText(TextField, label);
          await tester.scrollUntilVisible(
            field,
            180,
            scrollable: find.byType(Scrollable).first,
            maxScrolls: 30,
          );
          await tester.ensureVisible(field);
          await _settle(tester);
          await tester.enterText(
            field,
            label == 'Email' ? 'draft@example.test' : 'draft-value',
          );
          await _settle(tester);
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await _settle(tester);
          final editable = find.descendant(
            of: field,
            matching: find.byType(EditableText),
          );
          expectFocusedCaretAboveIme(tester, editable, keyboardTop: 360);
          final state = tester.widget<EditableText>(editable);
          final value = state.controller.text;
          FocusManager.instance.primaryFocus?.unfocus();
          tester.view.resetViewInsets();
          await _settle(tester);
          expect(state.controller.text, value);
          expect(api.mutations, 0);
        }
        debugDefaultTargetPlatformOverride = null;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 10));
      },
    );
    testWidgets(
      'garage conversation multiline draft above IME ${platform.name}',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetViewInsets();
        });
        final api = _Api();
        await _pump(
          tester,
          SingleChildScrollView(
            child: GarageConversationCard(
              request: GarageRequest.fromJson({
                'id': 11,
                'requestNumber': 'GAR-11',
                'vehicleId': 7,
                'status': 'new',
                'items': [],
              }),
            ),
          ),
          api,
        );
        final field = find.byType(EditableText);
        await tester.ensureVisible(field);
        await _settle(tester);
        await tester.enterText(field, 'Draft\nsecond line');
        await _settle(tester);
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await _settle(tester);
        expectFocusedCaretAboveIme(tester, field, keyboardTop: 360);
        expect(
          tester.widget<EditableText>(field).textInputAction,
          TextInputAction.newline,
        );
        expect(api.mutations, 0);
        debugDefaultTargetPlatformOverride = null;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 10));
      },
    );
    for (final sheet in ['phone', 'problem']) {
      testWidgets(
        'profile $sheet real modal editable above IME ${platform.name}',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(() {
            debugDefaultTargetPlatformOverride = null;
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
            tester.view.resetViewInsets();
          });
          final api = _Api();
          await _pump(
            tester,
            Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () {
                    if (sheet == 'phone') {
                      showBlurredModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (_) => const VerifiedPhoneChangeSheet(),
                      );
                    } else {
                      showProblemReportSheet(
                        context: context,
                        profile: _profile,
                        repository: ProblemReportRepository(api),
                      );
                    }
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
            api,
          );
          await tester.tap(find.text('Open'));
          await _settle(tester);
          final all = find.byType(EditableText);
          final editable = all.first;
          await tester.enterText(
            editable,
            sheet == 'phone' ? '9991234567' : 'Description\nsecond line',
          );
          await _settle(tester);
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await _settle(tester);

          expectFocusedCaretAboveIme(tester, editable, keyboardTop: 360);
          final state = tester.widget<EditableText>(editable);
          final draft = state.controller.text;
          expect(draft, isNotEmpty);
          FocusManager.instance.primaryFocus?.unfocus();
          await _settle(tester);
          expect(state.controller.text, draft);
          expect(api.mutations, 0);
          expect(tester.takeException(), isNull);
          debugDefaultTargetPlatformOverride = null;
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 10));
        },
      );
    }

    for (final form in ['vehicle', 'request', 'referral']) {
      testWidgets('all $form fields retain draft above IME ${platform.name}', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetViewInsets();
        });
        final api = _Api();
        await _pump(tester, switch (form) {
          'vehicle' => const GarageVehicleFormScreen(),
          'request' => const GarageRequestFormScreen(initialVehicleId: 7),
          _ => const ReferralScreen(),
        }, api);
        if (form == 'vehicle') {
          await _exerciseFields(tester, [
            'VIN',
            'Название в Гараже',
            'Марка *',
            'Модель *',
            'Год выпуска *',
            'Поколение / комплектация',
            'Код двигателя',
            'Комментарий',
          ]);
        } else if (form == 'request') {
          await _exerciseFields(tester, [
            'Общий комментарий',
            'Название детали *',
            'Артикул *',
            'Аналогичный товар в России',
            'Количество *',
            'Сторона / расположение',
            'Позиция / место установки',
            'Комментарий',
          ]);
        } else {
          final field = find.byType(TextField);
          await tester.scrollUntilVisible(
            field,
            180,
            scrollable: find.byType(Scrollable).first,
            maxScrolls: 30,
          );
          await tester.ensureVisible(field);
          await _settle(tester);
          await tester.enterText(field, 'REF123');
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await _settle(tester);
          expect(tester.widget<TextField>(field).controller!.text, 'REF123');
          expect(
            tester
                .widget<EditableText>(find.byType(EditableText))
                .focusNode
                .hasFocus,
            false,
          );
        }
        expect(api.mutations, 0);
        debugDefaultTargetPlatformOverride = null;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 10));
      });
    }
    for (final size in [const Size(320, 640), const Size(390, 844)]) {
      testWidgets(
        'vehicle Next and drag dismiss preserve draft ${platform.name} $size',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(() {
            debugDefaultTargetPlatformOverride = null;
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
            tester.view.resetViewInsets();
          });
          final api = _Api();
          await _pump(tester, const GarageVehicleFormScreen(), api);
          final first = find.byType(TextFormField).first;
          expect(
            tester
                .widget<EditableText>(
                  find.descendant(
                    of: first,
                    matching: find.byType(EditableText),
                  ),
                )
                .textInputAction,
            TextInputAction.next,
          );
          await tester.ensureVisible(first);
          await tester.tap(first);
          await tester.enterText(first, 'JTDKN3DU0D1234567');
          await tester.testTextInput.receiveAction(TextInputAction.next);
          await _settle(tester);
          expect(
            tester
                .widget<EditableText>(find.byType(EditableText).at(1))
                .focusNode
                .hasFocus,
            true,
          );
          await _settle(tester);
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await _settle(tester);
          expect(
            tester.getRect(find.byType(EditableText).at(1)).bottom,
            lessThanOrEqualTo(size.height - 280 + 1),
          );
          await tester.drag(find.byType(ListView).first, const Offset(0, -100));
          await _settle(tester);
          expect(
            tester
                .widget<EditableText>(find.byType(EditableText).at(1))
                .focusNode
                .hasFocus,
            false,
          );
          expect(
            tester.widget<TextFormField>(first).controller!.text,
            'JTDKN3DU0D1234567',
          );
          expect(api.mutations, 0);
          debugDefaultTargetPlatformOverride = null;
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 10));
        },
      );
    }
    testWidgets('calculator numeric Done only dismisses ${platform.name}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
      });
      final api = _Api();
      await _pump(tester, const CalculatorScreen(), api);
      final first = find.byType(TextFormField).first;
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: first, matching: find.byType(EditableText)),
            )
            .textInputAction,
        TextInputAction.done,
      );
      await tester.ensureVisible(first);
      await _settle(tester);
      await tester.tap(first);
      await tester.enterText(first, '12');
      await _settle(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await _settle(tester);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .focusNode
            .hasFocus,
        false,
      );
      expect(tester.widget<TextFormField>(first).controller!.text, '12');
      tester.view.resetViewInsets();
      await _settle(tester);
      for (final label in [
        'Вес, кг',
        'Мест',
        'Объём, м³',
        'Треков всего',
        'Стоимость товаров, CNY',
      ]) {
        if (label == 'Стоимость товаров, CNY') {
          final insurance = find.text('Страховка');
          await tester.scrollUntilVisible(
            insurance,
            180,
            scrollable: find.byType(Scrollable).first,
            maxScrolls: 30,
          );
          await tester.tap(insurance);
          await _settle(tester);
        }
        final caption = find.text(label);
        await tester.scrollUntilVisible(
          caption,
          180,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 30,
        );
        final field = find.descendant(
          of: find.ancestor(of: caption, matching: find.byType(Column)).first,
          matching: find.byType(EditableText),
        );
        await tester.ensureVisible(field);
        await _settle(tester);
        await tester.enterText(field, '12');
        await _settle(tester);
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await _settle(tester);
        expectFocusedCaretAboveIme(tester, field, keyboardTop: 360);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await _settle(tester);
        expect(tester.widget<EditableText>(field).controller.text, '12');
        tester.view.resetViewInsets();
        await _settle(tester);
      }
      expect(api.mutations, 0);
      debugDefaultTargetPlatformOverride = null;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 10));
    });
  }
}
