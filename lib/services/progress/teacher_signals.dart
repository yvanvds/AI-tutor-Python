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
