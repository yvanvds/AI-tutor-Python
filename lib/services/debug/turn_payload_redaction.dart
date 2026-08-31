// Strips the student's belief state out of a turn payload on its way into a
// bug report (#79).
//
// Reports are filed on a **public** repository under the student's own GitHub
// account (#57), so everything in the attached payload is published under
// their real name. The conductor's `conductor.planned` event carries the
// current belief for each candidate learning objective — `mean` and
// `evidence` — and a graded turn carries the same numbers again per LO in
// `persisted.loStatusAfter`, plus the update that was applied. Together that
// is a ranked list of what a named teenager is worst at, readable by their
// classmates.
//
// The project owner's call: those estimates are not relevant to diagnosing a
// bug, so they do not belong in the issue. Nothing here changes what the
// conductor *records* — Options → Developer tools → Recent turns still shows
// the full numbers, on the teacher's own machine, where they are useful. This
// runs on the report side only, which is also why [redactBeliefData] copies
// rather than edits: a `TurnEvent`'s `data` map is handed out by reference,
// so redacting in place would blank the live debug view as a side effect.
//
// Shaped like `redactUserPaths` (#74): applied structurally to the whole
// payload rather than to two named keys at one call site, so a belief-bearing
// field added later — at any depth, inside any list — is caught without
// anyone remembering to come back here. What is kept is the structural
// material a report is diagnosed from: `targetLO`, `questionType`,
// `difficulty`, `chosenReason`, the candidate LO *ids*, the parsed response,
// timings and events. #78 was diagnosed from exactly that.

/// Stands in for a redacted value. Deliberately not a deleted key: a reader
/// should see that something was withheld rather than wonder whether the app
/// failed to record it.
const String kRedactedBelief = '<redacted>';

/// Keys whose value says how good the student is, rather than what the app
/// did. Every one of them is a number or flag derived from the Beta belief
/// the conductor keeps per learning objective:
///
///   * `mean`, `evidence` — the belief itself (`CandidateLoStat`,
///     `TurnLoStatus`);
///   * `mastered`, `stuck` — the same belief as a verdict on the student;
///   * `alphaDelta`, `betaDelta` — the update this turn applied to it;
///   * `subgoalProgressAfter` — how far through the subgoal they are.
///
/// Add a key here when a new field carries belief data; nothing else needs to
/// change.
const Set<String> kBeliefKeys = {
  'mean',
  'evidence',
  'mastered',
  'stuck',
  'alphaDelta',
  'betaDelta',
  'subgoalProgressAfter',
};

/// Returns a copy of [payload] with every [kBeliefKeys] value, at any depth,
/// replaced by [kRedactedBelief]. [payload] itself is never modified.
Map<String, dynamic> redactBeliefData(Map<String, dynamic> payload) =>
    _redactMap(payload);

Map<String, dynamic> _redactMap(Map<dynamic, dynamic> map) {
  final out = <String, dynamic>{};
  map.forEach((key, value) {
    final name = key.toString();
    out[name] = kBeliefKeys.contains(name)
        ? kRedactedBelief
        : _redactValue(value);
  });
  return out;
}

Object? _redactValue(Object? value) {
  if (value is Map) return _redactMap(value);
  if (value is List) {
    return value.map(_redactValue).toList(growable: false);
  }
  return value;
}
