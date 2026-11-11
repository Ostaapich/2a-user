import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_organizer_calculation_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/presentation/sp_organizer_calculation_profile_sheet.dart';
import '../../helpers/keyboard_acceptance.dart';
import 'keyboard_form_probe.dart';

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final mode in ['percent', 'fixed']) {
      testWidgets(
        '$platform SP calculation self/client $mode all fields320height',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 640);
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: ThemeData(platform: platform),
                builder: (_, child) => AppKeyboardDismissRegion(child: child!),
                locale: const Locale('ru'),
                supportedLocales: const [Locale('ru')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                ],
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => showSpOrganizerCalculationProfileSheet(
                        context: context,
                        purchaseId: 7,
                        selfProfile: SpOrganizerCalculationProfile(
                          source: 'profile',
                          scope: 'self',
                          currency: 'CNY',
                          insuranceMode: mode,
                        ),
                        clientProfile: SpOrganizerCalculationProfile(
                          source: 'profile',
                          scope: 'client',
                          currency: 'CNY',
                          insuranceMode: mode,
                          commissionMode: mode,
                        ),
                      ),
                      child: const Text('Открыть расчёт'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(find.text('Открыть расчёт'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(await probeCurrentFormEditors(tester, minimumFields: 9), 9);
          final outer = tester.state<ScrollableState>(
            find
                .byElementPredicate(
                  (element) =>
                      element.widget is Scrollable &&
                      ModalRoute.of(element)?.isCurrent == true &&
                      (element.widget as Scrollable).axisDirection ==
                          AxisDirection.down,
                )
                .first,
          );
          outer.position.jumpTo(0);
          await tester.pump(const Duration(milliseconds: 400));
          await tester.ensureVisible(find.text('Для клиента'));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(find.text('Для клиента'));
          await tester.pump(const Duration(milliseconds: 400));
          expect(await probeCurrentFormEditors(tester, minimumFields: 9), 9);
        },
      );
    }
  }
}
