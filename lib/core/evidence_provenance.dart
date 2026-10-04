// Where a piece of belief evidence was produced (#100, PUNTENFORMULE §2.7).
//
// `supervised` means the answer was graded in the lesson time of the
// student's class, 10 minutes before and after each lesson included (#219,
// `ScheduleSupervisionSource`) — wherever the student sat, so a sick
// student practising at home during the lesson counts too. Everything else
// — the evening, the weekend, a student without a class, a class without
// lessons, a timetable that could not be read — is `home`. There is no
// manual toggle: the timetable decides, per student, per turn.
//
// Turns graded before #219 are all `home` on the record (nothing answered
// `supervised` then), and older `turn_history` docs need no backfill: a
// missing field reads as `home`. Where a count has to be right over the
// whole year, it reads them by the timetable instead: the grade proposal's
// supervised/home tally (`GradeProposalService.compute`) and the
// evaluation tooling's replay (`tooling/evaluation/rules.py`).
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
