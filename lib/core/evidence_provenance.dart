// Where a piece of belief evidence was produced (#100, PUNTENFORMULE §2.7).
//
// `supervised` means the student was in an active, alert-free Anchor
// classroom session at the moment the answer was graded; everything else —
// home work, a sick student during the lesson, a session with an escape
// alert on record for this student — is `home`. There is no manual toggle:
// the session registration decides, per student, per turn.
//
// Until Anchor ships every turn is `home`, so the weighting in
// `belief_math.signalDeltas` is a no-op and older `turn_history` docs need
// no backfill: a missing field reads as `home`.
enum EvidenceProvenance {
  home,
  supervised;

  /// Parses a persisted name; anything unknown (including `null`) is `home`,
  /// so a doc written before the field existed keeps its uniform weight.
  static EvidenceProvenance parse(Object? raw) {
    if (raw is String) {
      for (final p in EvidenceProvenance.values) {
        if (p.name == raw) return p;
      }
    }
    return EvidenceProvenance.home;
  }
}
