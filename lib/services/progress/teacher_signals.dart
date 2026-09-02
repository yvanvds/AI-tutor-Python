// Pure helpers consumed by the teacher accounts overview and the per-student
// detail drawer. Kept out of widgets so the inline-table column logic and the
// drawer summary can share the same definitions and so the rules are easy to
// tune from one place.
//
// Under the LO-belief redesign, per-(student, subgoal) `recentAnswers` and
// concept-attribution lists are gone — answer history lives on the account
// doc's `calibration` substructure (cross-LO) and per-LO beliefs (per LO).
// The struggling/concept-attribution surfaces from the previous model are
// not part of this step's scope (CONDUCTOR_POLICY 8.2 strong-signal events
// land later); the active/idle state below is what remains.

import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';

/// Coarse activity bucket the teacher table colours each student with.
enum StudentStatus { active, idle }

/// "Recent" cutoff for the active/idle decision. Mirrors the 7-day window
/// the spec calls out so widgets don't redefine it locally.
const Duration kRecentActivityWindow = Duration(days: 7);

/// Picks the most-recently-active progress doc from a per-student list. Used
/// for both "current goal" and the active/idle status anchor.
Progress? mostRecentlyActive(List<Progress> docs) {
  Progress? best;
  DateTime? bestAt;
  for (final p in docs) {
    final ts = p.lastSessionAt ?? p.updatedAt;
    if (ts == null) continue;
    if (bestAt == null || ts.isAfter(bestAt)) {
      best = p;
      bestAt = ts;
    }
  }
  // Fall back to the first doc when none have a timestamp at all so the
  // caller still has *something* to render rather than an em-dash for a
  // student who clearly has progress data.
  return best ?? (docs.isEmpty ? null : docs.first);
}

/// Composite status for the inline accounts table dot.
StudentStatus computeStudentStatus({
  required List<Progress> progress,
  DateTime? now,
}) {
  if (progress.isEmpty) return StudentStatus.idle;
  final reference = mostRecentlyActive(progress);
  if (reference == null) return StudentStatus.idle;
  final ts = reference.lastSessionAt ?? reference.updatedAt;
  if (ts == null) return StudentStatus.idle;
  final clock = now ?? DateTime.now().toUtc();
  if (clock.toUtc().difference(ts.toUtc()) > kRecentActivityWindow) {
    return StudentStatus.idle;
  }
  return StudentStatus.active;
}

/// Root goal id owning the student's most-recently-active progress record,
/// resolved by walking [parentByChild] upward (a record on a root — the
/// derived root cache doc — resolves to that root itself). Null when the
/// student has no progress or the active record's goal is unknown — the same
/// cases in which the "Current goal" column shows an em-dash.
String? activeRootId({
  required List<Progress> progress,
  required Map<String, String?> parentByChild,
}) {
  final active = mostRecentlyActive(progress);
  if (active == null) return null;
  if (!parentByChild.containsKey(active.goalID)) return null;
  var current = active.goalID;
  // Guard against a parent cycle in hand-authored goal data.
  final seen = <String>{current};
  var parent = parentByChild[current];
  while (parent != null) {
    if (!seen.add(parent)) return null;
    current = parent;
    parent = parentByChild[current];
  }
  return current;
}

/// Overall progress of the student's *active* root goal — the root that owns
/// the most-recently-active progress record, i.e. the same root the
/// "Current goal" column names (#89).
///
/// Averages over **all** non-optional subgoals defined under that root, with
/// subgoals the student has not started counting as 0 — so finishing 1 of N
/// shows ~1/N, not 100%. Optional subgoals stay excluded from both sides of
/// the average. Returns 0.0 when the student has no resolvable active root
/// or the root has no non-optional subgoals.
double activeRootProgress({
  required List<Progress> progress,
  required Map<String, Goal> goalById,
  required Map<String, String?> parentByChild,
}) {
  final rootId = activeRootId(progress: progress, parentByChild: parentByChild);
  if (rootId == null) return 0.0;
  final subgoals = goalById.values
      .where((g) => g.parentId == rootId && !g.optional)
      .toList();
  if (subgoals.isEmpty) return 0.0;
  final progressByGoal = {for (final p in progress) p.goalID: p.progress};
  double total = 0;
  for (final g in subgoals) {
    total += (progressByGoal[g.id] ?? 0.0).clamp(0.0, 1.0);
  }
  return total / subgoals.length;
}

/// Average progress across [docs], skipping any goal whose id is in
/// [excludeIds]. Returns 0.0 for an empty input.
double averageProgress(
  List<Progress> docs, {
  Set<String> excludeIds = const {},
}) {
  if (docs.isEmpty) return 0.0;
  double total = 0;
  int count = 0;
  for (final p in docs) {
    if (excludeIds.contains(p.goalID)) continue;
    total += p.progress;
    count++;
  }
  if (count == 0) return 0.0;
  return total / count;
}
