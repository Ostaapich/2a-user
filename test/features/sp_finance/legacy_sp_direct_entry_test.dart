import 'package:flutter/material.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_keyboard_dismiss.dart';
import '../keyboard/keyboard_form_probe.dart';
import '../../helpers/keyboard_acceptance.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_models.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/data/sp_provider.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/presentation/sp_assembly_detail_screen.dart';
import 'package:twoalogisticcabineuser/src/features/sp_finance/presentation/sp_track_edit_screen.dart';

class _ReloadController extends SpAssembliesController {
  int loads = 0;
  @override
  SpAssembliesState build() => const SpAssembliesState();
  @override
  Future<void> loadAssemblies({bool silent = false}) async {
    loads++;
    state = const SpAssembliesState(isLoading: true);
    await Future<void>.delayed(Duration.zero);
    state = SpAssembliesState(
      assemblies: [
        SpAssembly.fromJson({
          'id': 7,
          'name': 'Recovered assembly',
          'status': 'in_warehouse',
          'createdAt': '2026-11-09T00:00:00Z',
          'stats': <String, dynamic>{'tracksTotal': 1, 'tracksWithSP': 1},
          'tracks': [
            {
              'id': 3,
              'trackNumber': 'RESTORED-TRACK',
              'spParticipantName': 'Recovered participant',
            },
          ],
        }),
      ],
    );
  }
}

void main() {
  setUpAll(loadKeyboardAcceptanceFonts);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform legacy SP track every field320height', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 640);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            spAssembliesControllerProvider.overrideWith(_ReloadController.new),
          ],
          child: MaterialApp(
            theme: ThemeData(platform: platform),
            builder: (_, child) => AppKeyboardDismissRegion(child: child!),
            home: const Scaffold(
              body: SpTrackEditScreen(trackId: 3, assemblyId: 7),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(await probeCurrentFormEditors(tester, minimumFields: 8), 8);
    });
  }

  for (final track in [false, true]) {
    testWidgets(
      'legacy ${track ? 'track' : 'assembly'} direct entry loads missing provider data',
      (tester) async {
        final controller = _ReloadController();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              spAssembliesControllerProvider.overrideWith(() => controller),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: track
                    ? const SpTrackEditScreen(trackId: 3, assemblyId: 7)
                    : const SpAssemblyDetailScreen(assemblyId: 7),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump();
        expect(controller.loads, 1);
        expect(
          find.textContaining(track ? 'RESTORED-TRACK' : 'Recovered assembly'),
          findsWidgets,
        );
        expect(find.text('Сборка не найдена'), findsNothing);
      },
    );
  }
}
