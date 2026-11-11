import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../../helpers/keyboard_acceptance.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import 'package:twoalogisticcabineuser/src/core/ui/sheet_handle.dart';
import 'package:twoalogisticcabineuser/src/features/clients/application/client_codes_controller.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/data/tracks_provider.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/domain/track_item.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/presentation/tracks_screen.dart';

class _NoteApi extends ApiClient {
  final calls = <Map<String, dynamic>>[];
  final replies = <Completer<bool>>[];
  @override
  Future<String?> getToken() async => null;
  @override
  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    expect(path, '/assemblies/43');
    calls.add(Map<String, dynamic>.from(data as Map));
    final response = Completer<bool>();
    replies.add(response);
    final ok = await response.future;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: ok ? 200 : 500,
      data: <String, dynamic>{} as T,
    );
  }
}

Future<void> _open(WidgetTester tester) async {
  final action = find.byKey(const ValueKey('client-track-action-Заметка'));
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pumpAndSettle();
  expect(find.text('Заметка по сборке'), findsOneWidget);
}

Future<_NoteApi> _pump(WidgetTester tester, TargetPlatform platform) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final api = _NoteApi(), now = DateTime(2026, 11, 10);
  const assembly = TrackAssembly(
    id: 43,
    number: 'ASM-NOTE',
    status: 'ready_for_pickup',
    comment: 'Исходная заметка',
    trackCount: 1,
  );
  final track = TrackItem(
    code: 'NOTE-TRACK',
    status: 'В сборке',
    statusCode: 'in_assembly',
    date: now,
    createdAt: now,
    updatedAt: now,
    groupId: '43',
    assembly: assembly,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        activeClientCodeProvider.overrideWithValue('2A-TEST'),
        trackStatusesProvider.overrideWith((_) async => []),
        assemblyStatusesProvider.overrideWith((_) async => []),
      ],
      child: MaterialApp(
        theme: ThemeData(platform: platform, fontFamily: 'Gilroy'),
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => AppKeyboardDismissRegion(child: child!),
        home: Scaffold(
          body: TracksScreen.embedded(tracks: [track], asAssembly: true),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await _open(tester);
  return api;
}

Future<void> _close(WidgetTester tester, String path) async {
  if (path == 'cancel') {
    await tester.tap(find.text('Отмена'));
  } else if (path == 'barrier') {
    await tester.tapAt(const Offset(8, 30));
  } else {
    await tester.drag(
      find.byType(SheetHandle).hitTestable().last,
      const Offset(0, 180),
    );
  }
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    await loadKeyboardAcceptanceFonts();
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final path in ['cancel', 'barrier', 'swipe']) {
      testWidgets('clean assembly note closes by $path ${platform.name}', (
        tester,
      ) async {
        final api = await _pump(tester, platform);
        await _close(tester, path);
        expect(find.text('Заметка по сборке'), findsNothing);
        expect(api.calls, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets(
      'dirty assembly note continues editing or discards ${platform.name}',
      (tester) async {
        final api = await _pump(tester, platform);
        await tester.enterText(find.byType(TextField), 'Новая заметка');
        await tester.pump();
        final originalHeader = tester.getRect(find.text('Заметка по сборке'));
        for (final path in ['cancel', 'barrier', 'swipe']) {
          await _close(tester, path);
          expect(
            find.text('Не сохранять изменения?'),
            findsOneWidget,
            reason: path,
          );
          await tester.tap(find.text('Продолжить редактирование'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            'Новая заметка',
          );
          expect(
            tester.getRect(find.text('Заметка по сборке')),
            originalHeader,
            reason: 'header after $path -> continue editing',
          );
          expect(
            find.text('Отмена').hitTestable(),
            findsOneWidget,
            reason: path,
          );
        }
        await _close(tester, 'cancel');
        await tester.tap(find.text('Не сохранять'));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        await _open(tester);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Исходная заметка',
        );
        expect(api.calls, isEmpty);
        await _close(tester, 'cancel');
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'assembly note failure retains draft and retry commits only success ${platform.name}',
      (tester) async {
        final api = await _pump(tester, platform);
        await tester.enterText(find.byType(TextField), 'Сохранить новый текст');
        await tester.tap(find.text('Сохранить заметку'));
        await tester.pump();
        api.replies.single.complete(false);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Сохранить новый текст',
        );
        await tester.tap(find.text('Сохранить заметку'));
        await tester.pump();
        api.replies.last.complete(true);
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        expect(api.calls, [
          {'comment': 'Сохранить новый текст'},
          {'comment': 'Сохранить новый текст'},
        ]);
        await _open(tester);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Сохранить новый текст',
        );
        await _close(tester, 'cancel');
        await tester.pump(const Duration(seconds: 5));
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets('busy assembly note blocks every close path ${platform.name}', (
      tester,
    ) async {
      final api = await _pump(tester, platform);
      await tester.enterText(find.byType(TextField), 'В процессе сохранения');
      await tester.tap(find.text('Сохранить заметку'));
      await tester.pump();
      await tester.tap(find.text('Отмена'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(8, 30));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SheetHandle).last,
        const Offset(0, 180),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Заметка по сборке'), findsOneWidget);
      expect(find.text('Не сохранять изменения?'), findsNothing);
      expect(api.calls.length, 1);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'В процессе сохранения',
      );
      api.replies.single.complete(true);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    });
  }
}
