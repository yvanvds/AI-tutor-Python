// Progress reset flows for the Options panel (issue #25).
//
// `resetAll` is the former debug-dialog "wipe": every progress /
// progress_history / lo_beliefs / turn_history doc of the signed-in user
// goes, and the account calibration returns to medium.
//
// `resetGoal` is the granular variant. For a subgoal it removes that
// subgoal's progress cache, history samples, LO beliefs and turn records,
// then recomputes the parent root's cached progress the same way the
// conductor does (mean over the children, missing = 0). For a root goal it
// does this for every child and drops the root's own cache.
//
// Both take the content of the oefeningen along (#232): the `turn_content`
// docs next to the turn records they delete — the question, the answer and
// the feedback. Last, and best-effort: by then the rest of the reset is
// done, and a missing container or a failed delete does not fail it. The
// question bank (`questions`) is never touched: it is kept for next year,
// also the questions this student was the first to get.

import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:ai_tutor_python/services/student_state/lo_beliefs_service.dart';
import 'package:ai_tutor_python/services/student_state/student_calibration.dart';
import 'package:ai_tutor_python/services/student_state/turn_content_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProgressReset {
  ProgressReset({
    required this._goals,
    required this._progress,
    required this._loBeliefs,
    required this._turnHistory,
    required this._turnContent,
    required this._setCalibration,
  });

  final GoalsService _goals;
  final ProgressService _progress;
  final LoBeliefsService _loBeliefs;
  final TurnHistoryService _turnHistory;
  final TurnContentService _turnContent;
  final Future<void> Function(StudentCalibration) _setCalibration;

  Future<void> resetAll() async {
    await _progress.deleteAllForCurrentUser();
    await _loBeliefs.deleteAllForCurrentUser();
    await _turnHistory.deleteAllForCurrentUser();
    await _setCalibration(StudentCalibration.fresh());
    await _turnContent.deleteAllForCurrentUser();
  }

  /// Resets [goal]. Returns the number of subgoals whose state was cleared.
  Future<int> resetGoal(Goal goal) async {
    if (goal.parentId == null) {
      final children = await _goals.getChildrenOnce(goal.id);
      for (final child in children) {
        await _clearSubgoal(child.id);
      }
      await _progress.deleteForGoal(goal.id);
      for (final child in children) {
        await _turnContent.deleteAllForSubgoal(child.id);
      }
      return children.length;
    }

    await _clearSubgoal(goal.id);
    await _recomputeRoot(goal.parentId!);
    await _turnContent.deleteAllForSubgoal(goal.id);
    return 1;
  }

  Future<void> _clearSubgoal(String subgoalId) async {
    await _progress.deleteForGoal(subgoalId);
    await _loBeliefs.deleteAllForSubgoal(subgoalId);
    await _turnHistory.deleteAllForSubgoal(subgoalId);
  }

  Future<void> _recomputeRoot(String rootId) async {
    final children = await _goals.getChildrenOnce(rootId);
    if (children.isEmpty) {
      await _progress.deleteForGoal(rootId);
      return;
    }
    var sum = 0.0;
    for (final child in children) {
      final p = await _progress.getByGoalId(child.id);
      sum += p?.progress ?? 0.0;
    }
    await _progress.upsert(
      Progress(goalID: rootId, progress: sum / children.length),
      recordHistory: false,
    );
  }
}

final progressResetProvider = Provider<ProgressReset>((ref) {
  return ProgressReset(
    goals: ref.watch(goalsServiceProvider),
    progress: ref.watch(progressServiceProvider),
    loBeliefs: ref.watch(loBeliefsServiceProvider),
    turnHistory: ref.watch(turnHistoryServiceProvider),
    turnContent: ref.watch(turnContentServiceProvider),
    setCalibration: (c) =>
        ref.read(accountServiceProvider.notifier).setCalibration(c),
  );
});
