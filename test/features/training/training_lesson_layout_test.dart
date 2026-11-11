import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/app/theme/app_theme.dart';
import 'package:twoalogisticcabineuser/src/app/widgets/app_scaffold.dart';
import 'package:twoalogisticcabineuser/src/core/persistence/shared_preferences_provider.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_colors.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_layout.dart';
import 'package:twoalogisticcabineuser/src/features/auth/data/auth_provider.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/clients/domain/client_codes_state.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/application/notifications_controller.dart';
import 'package:twoalogisticcabineuser/src/features/notifications/domain/notification_item.dart';
import 'package:twoalogisticcabineuser/src/features/training/data/training_progress.dart';
import 'package:twoalogisticcabineuser/src/features/training/presentation/training_entry_screen.dart';

class _Auth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    isLoggedIn: true,
    isLoading: false,
    clientId: 17,
    userDomain: 'test',
  );
}

class _Codes extends ClientCodesController {
  @override
  Future<ClientCodesState> build() async =>
      const ClientCodesState(codes: ['2A-TEST'], activeCode: '2A-TEST');
}

class _Notifications extends NotificationsController {
  @override
  Future<List<NotificationItem>> build() async => [];
}

void main() {
  testWidgets(
    'completed lesson uses app shell inset and a single practice action',
    (tester) async {
      final originalShadows = debugDisableShadows;
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = originalShadows);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await TrainingProgressStore(prefs, accountKey: 'test:17').save(
        const TrainingProgress().visit(
          'assembly',
          5,
          status: TrainingLessonStatus.practiced,
        ),
      );
      await (FontLoader(
            'Gilroy',
          )..addFont(rootBundle.load('assets/fonts/gilroy/Gilroy-Regular.ttf')))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          ))
          .load();
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = FakeViewPadding(top: 59, bottom: 34);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      var practiceLaunches = 0;
      final router = GoRouter(
        initialLocation: '/training',
        routes: [
          GoRoute(
            path: '/training',
            builder: (_, _) => const AppScaffold(
              title: 'Обучение',
              child: TrainingEntryScreen(initialLessonId: 'assembly'),
            ),
          ),
          GoRoute(
            path: '/training/assembly',
            builder: (_, _) {
              practiceLaunches++;
              return const Scaffold(body: Text('Practice'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            authProvider.overrideWith(_Auth.new),
            clientCodesControllerProvider.overrideWith(_Codes.new),
            notificationsControllerProvider.overrideWith(_Notifications.new),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            theme: AppTheme.lightWithColors(
              BrandColors.fromHex('#F4773C', '#FF955F'),
            ),
            locale: const Locale('ru'),
            supportedLocales: const [Locale('ru'), Locale('zh')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (_, child) =>
                RepaintBoundary(key: boundary, child: child!),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('training-show-in-app')), findsNothing);
      expect(find.byKey(const Key('training-practice')), findsOneWidget);
      final context = tester.element(find.byType(TrainingEntryScreen));
      expect(
        MediaQuery.paddingOf(context).top,
        0,
        reason: 'AppScaffold has already consumed the safe top inset',
      );
      final firstAction = find.byKey(const Key('training-catalog'));
      expect(
        tester.getTopLeft(firstAction).dy,
        closeTo(
          MediaQuery.paddingOf(tester.element(find.byType(AppScaffold))).top +
              AppLayout.topBarTotalHeight(context) +
              16,
          1,
        ),
      );
      final output = Platform.environment['TRAINING_RENDER_DIR'];
      if (output != null) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File(
            '$output/completed-assembly-lesson.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.byKey(const Key('training-practice')));
      await tester.pumpAndSettle();
      expect(practiceLaunches, 1);
      expect(find.text('Practice'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDisableShadows = originalShadows;
    },
  );
}
