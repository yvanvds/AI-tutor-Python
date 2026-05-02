// Pure helpers consumed by the teacher accounts overview and the per-student
// detail drawer. Kept out of widgets so the inline-table column logic and the
// drawer summary can share the same definitions and so the rules are easy to
// tune from one place.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/services/progress/concept_attribution.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';

/// Coarse activity bucket the teacher table colours each student with.
enum StudentStatus { struggling, active, idle }

/// "Recent" cutoff for the active/idle decision. Mirrors the 7-day window
/// the spec calls out so widgets don't redefine it locally.
const Duration kRecentActivityWindow = Duration(days: 7);

/// Minimum number of recent answers required before we'll call a student
/// struggling. With < 3 entries the signal is too noisy.
const int kStrugglingMinSamples = 3;

/// Weighted-wrong threshold: ≥ 0.5 over the recent window flips the dot red.
const double kStrugglingThreshold = 0.5;

/// `true` when the student's most recent rolling-window answers indicate they
/// are struggling on this subgoal. Weights wrong=1.0, partial=0.5, correct=0.0
/// and requires at least [kStrugglingMinSamples] samples to fire.
bool isStruggling(List<AnswerQuality> recentAnswers) {
  if (recentAnswers.length < kStrugglingMinSamples) return false;
  double total = 0;
  for (final q in recentAnswers) {
    switch (q) {
      case AnswerQuality.wrong:
        total += 1.0;
      case AnswerQuality.partial:
        total += 0.5;
      case AnswerQuality.correct:
      // 0
    }
  }
  return (total / recentAnswers.length) >= kStrugglingThreshold;
}

/// Picks the most-recently-active progress doc from a per-student list. Used
/// for both "current goal" and the struggling/concept-attribution lookup —
/// they're always anchored on the same subgoal.
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
  if (isStruggling(reference.recentAnswers)) return StudentStatus.struggling;
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

/// Counts how often each concept tag shows up in the supplied attributions
/// list. Returned entries are sorted descending by count, then by concept
/// name for stable rendering.
List<MapEntry<String, int>> rankConceptAttributions(
  List<ConceptAttribution> attributions,
) {
  final counts = <String, int>{};
  for (final a in attributions) {
    counts[a.concept] = (counts[a.concept] ?? 0) + 1;
  }
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      if (byCount != 0) return byCount;
      return a.key.compareTo(b.key);
    });
  return entries;
}
