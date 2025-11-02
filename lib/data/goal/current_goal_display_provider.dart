// Small “view model” for the AppBar center area
import 'package:ai_tutor_python/data/goal/goal_providers.dart';
import 'package:ai_tutor_python/data/progress/progress_providers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final currentGoalDisplayProvider =
    Provider<({String? rootTitle, String? childTitle, double? progress})>((
      ref,
    ) {
      final rootId = ref.watch(selectedRootGoalProviderNotifier);
      final childId = ref.watch(selectedChildGoalProviderNotifier);

      final rootTitle = rootId == null
          ? null
          : ref
                .watch(goalByIdProvider(rootId))
                .maybeWhen(data: (g) => g?.title, orElse: () => null);

      final childTitle = childId == null
          ? null
          : ref
                .watch(goalByIdProvider(childId))
                .maybeWhen(data: (g) => g?.title, orElse: () => null);

      double? p;
      if (childId != null) {
        p = ref
            .watch(progressByGoalProvider(childId))
            .maybeWhen(data: (pr) => pr?.progress ?? 0.0, orElse: () => null);
      }

      return (rootTitle: rootTitle, childTitle: childTitle, progress: p);
    });
