import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../garage/application/garage_providers.dart';
import '../../partner_program/data/client_partner_program_provider.dart';
import '../../self_buyout/data/self_buyout_service.dart';
import '../../shop/data/shop_availability_provider.dart';
import '../application/training_tour_provider.dart';
import '../application/assembly_training_provider.dart';
import 'assembly_practice_steps.dart';
import 'training_target.dart';
import 'training_modal_ownership.dart';
import 'training_tour_overlay.dart';
import 'training_tour_steps.dart';

String _currentPath(GoRouter router) =>
    router.routerDelegate.currentConfiguration.isEmpty
    ? router.routeInformationProvider.value.uri.path
    : router.state.uri.path;

TrainingServiceAccess trainingAccess<T>(
  AsyncValue<T> value,
  bool Function(T) allowed,
) {
  if (value.isLoading) return TrainingServiceAccess.checking;
  if (value.hasError) return TrainingServiceAccess.failed;
  final data = value.asData;
  if (data == null) return TrainingServiceAccess.checking;
  return allowed(data.value)
      ? TrainingServiceAccess.available
      : TrainingServiceAccess.unavailable;
}

class TrainingTourHost extends ConsumerWidget {
  final GoRouter router;
  final Widget child;

  const TrainingTourHost({
    super.key,
    required this.router,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The Router subtree stays in the same slot throughout start/stop/auth changes.
    // Only a separate overlay is mounted, preserving forms and navigation state.
    return _AfterFrameListenableBuilder(
      listenable: router.routerDelegate,
      builder: (context, _) => Consumer(
        builder: (context, ref, _) {
          final controller = ref.watch(
            _currentPath(router) == assemblyPracticeRoute
                ? assemblyPracticeControllerProvider
                : trainingTourControllerProvider,
          );
          return Stack(
            children: [
              child,
              if (controller != null)
                Positioned.fill(
                  child: ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) {
                      if (!controller.active) return const SizedBox.shrink();
                      final steps = [
                        ...trainingTourSteps(context),
                        ...assemblyPracticeSteps(context),
                      ];
                      final matches = steps.where(
                        (step) => step.id == controller.currentId,
                      );
                      if (matches.isEmpty) return const SizedBox.shrink();
                      // This host is above the Navigator in MaterialApp.builder.
                      // Coach tooltips need their own Overlay ancestor there.
                      return Overlay.wrap(
                        child: _ActiveTrainingTour(
                          key: ValueKey(controller.scopeKey),
                          router: router,
                          step: matches.first,
                          child: const SizedBox.expand(),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ActiveTrainingTour extends ConsumerWidget {
  final GoRouter router;
  final TrainingTourStep step;
  final Widget child;

  const _ActiveTrainingTour({
    super.key,
    required this.router,
    required this.step,
    required this.child,
  });

  TrainingServiceAccess _access(WidgetRef ref) => switch (step.capability) {
    'self_buyout' => trainingAccess(
      ref.watch(selfBuyoutAvailabilityProvider),
      (data) =>
          data.available ||
          const {'rate_stale', 'no_rate', 'rate_invalid'}.contains(data.reason),
    ),
    'garage' => trainingAccess(
      ref.watch(garageAvailabilityProvider),
      (data) => data.available,
    ),
    'shop' => trainingAccess(
      ref.watch(shopAvailabilityProvider),
      (data) => data.hasBrowsablePlatform,
    ),
    'partner_program' => trainingAccess(
      ref.watch(clientPartnerProgramProvider),
      (data) => data != null,
    ),
    null => TrainingServiceAccess.available,
    _ => TrainingServiceAccess.unavailable,
  };

  void _retry(WidgetRef ref) {
    switch (step.capability) {
      case 'self_buyout':
        ref.invalidate(selfBuyoutAvailabilityProvider);
      case 'garage':
        ref.invalidate(garageAvailabilityProvider);
      case 'shop':
        ref.invalidate(shopAvailabilityProvider);
      case 'partner_program':
        ref.invalidate(clientPartnerProgramProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(
      step.lessonId == assemblyPracticeLessonId
          ? assemblyPracticeControllerProvider
          : trainingTourControllerProvider,
    );
    if (controller == null) return child;
    final access = _access(ref);
    final registry = ref.watch(trainingTargetRegistryProvider);
    final practice = step.lessonId == assemblyPracticeLessonId;
    final session = practice
        ? ref.watch(assemblyTrainingSessionProvider)
        : null;
    return _AfterFrameListenableBuilder(
      listenable: Listenable.merge([
        router.routerDelegate,
        if (session != null) session,
      ]),
      builder: (context, _) => TrainingTourOverlay(
        controller: controller,
        registry: registry,
        modalOwnership: ref.read(trainingModalOwnershipProvider),
        step: step,
        guidedPractice: practice,
        advanceRequested:
            practice && step.lessonStep == 6 && session!.assemblyCreated,
        access: access,
        currentPath: _currentPath(router),
        navigate: router.go,
        onExit: () {
          controller.stop();
          router.go(practice ? '/training?lesson=assembly' : '/training');
        },
        onPractice: () {
          controller.stop();
          router.go(assemblyPracticeRoute);
        },
        onRetryAccess: () => _retry(ref),
        child: child,
      ),
    );
  }
}

// Router notifications may occur while MaterialApp is building its Navigator.
// Observe imperative pushes as well as go(), but update the coach after layout.
class _AfterFrameListenableBuilder extends StatefulWidget {
  final Listenable listenable;
  final TransitionBuilder builder;

  const _AfterFrameListenableBuilder({
    required this.listenable,
    required this.builder,
  });

  @override
  State<_AfterFrameListenableBuilder> createState() =>
      _AfterFrameListenableBuilderState();
}

class _AfterFrameListenableBuilderState
    extends State<_AfterFrameListenableBuilder> {
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(_AfterFrameListenableBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
  }

  void _changed() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, null);
}
