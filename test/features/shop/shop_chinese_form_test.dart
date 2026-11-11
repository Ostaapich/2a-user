import 'package:flutter/material.dart';
import 'package:twoalogisticcabineuser/src/core/branding/company_branding_provider.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/auth_provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/ui/tutorial_card.dart';
import 'package:twoalogisticcabineuser/src/features/shop/data/purchase_provider.dart';
import 'package:twoalogisticcabineuser/src/features/shop/data/shop_availability_provider.dart';
import 'package:twoalogisticcabineuser/src/features/shop/data/shop_provider.dart';
import 'package:twoalogisticcabineuser/src/features/shop/presentation/shop_screen.dart';

class _ShopAuth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(isLoggedIn: false, isLoading: false);
}

void main() {
  testWidgets(
    'Chinese shop tutorial and filters retain API sort and price parameters',
    (tester) async {
      ShopSearchParams? latest;
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            companyNameProvider.overrideWithValue('Partner Cargo'),
            authProvider.overrideWith(_ShopAuth.new),
            shopAvailabilityProvider.overrideWith(
              (ref) async => const MarketplaceAvailability(
                available: true,
                reason: null,
                platforms: [
                  MarketplacePlatformAvailability(
                    code: '1688',
                    nameRu: '1688',
                    nameZh: '1688',
                    available: true,
                    reason: null,
                    capabilities: MarketplaceCapabilities(
                      catalog: true,
                      purchaseList: true,
                      orderHistory: true,
                    ),
                  ),
                ],
              ),
            ),
            activePurchaseListProvider.overrideWith((ref) async => null),
            shopCategoriesProvider.overrideWith((ref, platform) async => []),
            shopSearchProvider.overrideWith((ref, params) async {
              latest = params;
              return const ShopSearchResult();
            }),
          ],
          child: const MaterialApp(
            locale: Locale('zh'),
            supportedLocales: [Locale('ru'), Locale('zh')],
            localizationsDelegates: [
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: Scaffold(body: ShopScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('搜索商品……'), findsOneWidget);
      final tutorial = tester.widget<TutorialScreenWrapper>(
        find.byType(TutorialScreenWrapper),
      );
      for (final step in tutorial.steps) {
        expect(RegExp('[А-Яа-я]').hasMatch(step.title), false);
        expect(RegExp('[А-Яа-я]').hasMatch(step.description), false);
      }
      await tester.enterText(find.byType(TextField).first, 'shoes');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('默认排序'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      expect(find.text('价格筛选（¥）'), findsOneWidget);
      expect(find.text('最低价'), findsOneWidget);
      expect(find.text('最高价'), findsOneWidget);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(1), '10');
      await tester.enterText(fields.at(2), '20');
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(latest?.query, 'shoes');
      expect(latest?.orderBy, 'Default');
      expect(latest?.minPrice, 10);
      expect(latest?.maxPrice, 20);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('价格升序').last);
      await tester.pumpAndSettle();
      expect(latest?.orderBy, 'Price:Asc');
      expect(tester.takeException(), isNull);
    },
  );
}
