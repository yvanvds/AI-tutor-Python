import 'package:ai_tutor_python/data/account/account_providers.dart';
import 'package:ai_tutor_python/data/goal/goal.dart';
import 'package:ai_tutor_python/data/goal/goal_providers.dart';
import 'package:ai_tutor_python/data/progress/progress_providers.dart';
import 'package:ai_tutor_python/services/chat_service.dart';
import 'package:collection/collection.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final tutorServiceProvider = Provider<TutorService>((ref) {
  final service = TutorService(ref: ref);
  ref.onDispose(service.dispose);
  return service;
});

class TutorService {
  final Ref ref;
  TutorService({required this.ref});

  Goal? _currentRootGoal = null;
  Goal? _currentChildGoal = null;

  // ---- Public API -----------------------------------------------------------

  Future<void> initializeSession() async {
    final chat = ref.read(chatServiceProvider);

    chat.clear();
    // Resolve name & target using stable snapshots
    final userName = await _getUserFirstName();
    final hasTarget = await setTargetGoal(); // selects providers inside

    if (!hasTarget) {
      chat.addSystemMessage(
        "There are no goals available to work on. Have fun!",
      );
      return;
    }

    chat.addSystemMessage(
      "Hello $userName, your current goal is '${_currentChildGoal?.title}' (under root '${_currentRootGoal?.title}'). Let's get started!",
    );
  }

  /// Computes and selects the next target goal/subgoal.
  /// Returns true if a selection was made, false otherwise.
  Future<bool> setTargetGoal() async {
    // Clear previous selection
    ref.read(selectedRootGoalProviderNotifier.notifier).select(null);
    ref.read(selectedChildGoalProviderNotifier.notifier).select(null);

    // Take stable snapshots
    final roots = await ref.read(rootGoalsProviderFuture.future); // List<Goal>
    final progressList = await ref.read(
      progressListProviderFuture.future,
    ); // List<Progress>

    double progressFor(Goal g) {
      final p = progressList.firstWhereOrNull((x) => x.goalID == g.id);
      return p?.progress ?? 0.0;
    }

    for (final root in roots) {
      if (progressFor(root) < 1.0) {
        // Load children for this root on demand (family provider)
        final subgoals = await ref.read(
          childGoalsByParentProviderFuture(root.id).future,
        );

        // Pick first incomplete subgoal (if any)
        final targetChild = subgoals.firstWhereOrNull(
          (g) => progressFor(g) < 1.0,
        );

        if (targetChild != null) {
          ref.read(selectedRootGoalProviderNotifier.notifier).select(root.id);
          ref
              .read(selectedChildGoalProviderNotifier.notifier)
              .select(targetChild.id);
          _currentRootGoal = root;
          _currentChildGoal = targetChild;
          return true;
        }
        // else: all children complete -> try next root
      }
    }

    // Nothing to select
    return false;
  }

  void dispose() {}

  // ---- Private helpers ------------------------------------------------------

  Future<String> _getUserFirstName() async {
    final acc = await ref.read(myAccountProviderFuture.future);
    return acc?.firstName ?? 'Student';
  }
}
