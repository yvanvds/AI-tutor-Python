// A grading milestone (#99, PUNTENFORMULE §2.1): the set of learning
// objectives the teacher expects to be known by a report date, with the
// Angoff split into core LOs (set K — gate the 50) and extension LOs
// (set U — buy points above it), and the difficulty level at which the
// core has to be demonstrated.
//
// One doc per milestone in the `milestones` Cosmos container
// (single-partition, `/type = "milestone"`). The LO sets are stored as
// `subgoalIds` plus the *core* keys: every LO of a listed subgoal that is
// not marked core is an extension LO, so a teacher who adds an LO to a
// subgoal mid-period sees it land in U (the harmless side) rather than
// silently gating the 50.

import 'package:ai_tutor_python/core/question_difficulty.dart';

class Milestone {
  const Milestone({
    required this.id,
    required this.title,
    required this.periodStart,
    required this.dueAt,
    required this.expectedDifficulty,
    required this.subgoalIds,
    required this.coreLoKeys,
    this.updatedAt,
  });

  final String id;
  final String title;

  /// Start of the grading period: the growth score (§2.4) reads M_start as
  /// of this instant — from the student's `period_start_snapshots` doc
  /// (#110), or from the stored history for a period that predates it —
  /// and the AI justification summarises status reports written from here
  /// on.
  final DateTime periodStart;

  /// The report moment ("these goals should be known by this date").
  final DateTime dueAt;

  /// The level at which a core LO must have been demonstrated (its
  /// `highestPositiveDifficulty` ratchet, §2.5) to count towards `k`.
  final QuestionDifficulty expectedDifficulty;

  /// Subgoals whose LOs make up the milestone, in curriculum order.
  final List<String> subgoalIds;

  /// `loKey(subgoalId, loId)` of every core LO. LO ids are only unique
  /// within a subgoal, hence the composite key.
  final Set<String> coreLoKeys;

  final DateTime? updatedAt;

  /// The composite key both the milestone and the formula use for one LO.
  static String loKey(String subgoalId, String loId) => '$subgoalId/$loId';

  bool isCore(String subgoalId, String loId) =>
      coreLoKeys.contains(loKey(subgoalId, loId));

  Milestone copyWith({
    String? title,
    DateTime? periodStart,
    DateTime? dueAt,
    QuestionDifficulty? expectedDifficulty,
    List<String>? subgoalIds,
    Set<String>? coreLoKeys,
  }) => Milestone(
    id: id,
    title: title ?? this.title,
    periodStart: periodStart ?? this.periodStart,
    dueAt: dueAt ?? this.dueAt,
    expectedDifficulty: expectedDifficulty ?? this.expectedDifficulty,
    subgoalIds: subgoalIds ?? this.subgoalIds,
    coreLoKeys: coreLoKeys ?? this.coreLoKeys,
    updatedAt: updatedAt,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': 'milestone',
    'title': title,
    'periodStart': periodStart.toUtc().toIso8601String(),
    'dueAt': dueAt.toUtc().toIso8601String(),
    'expectedDifficulty': expectedDifficulty.name,
    'subgoalIds': subgoalIds,
    'coreLoKeys': coreLoKeys.toList()..sort(),
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  };

  factory Milestone.fromCosmos(Map<String, dynamic> doc) {
    DateTime parseDate(Object? raw) => raw is String
        ? (DateTime.tryParse(raw) ?? DateTime.utc(1970))
        : DateTime.utc(1970);
    final diffRaw = doc['expectedDifficulty'];
    final difficulty = QuestionDifficulty.values
        .cast<QuestionDifficulty?>()
        .firstWhere((d) => d!.name == diffRaw, orElse: () => null);
    return Milestone(
      id: doc['id'] as String,
      title: (doc['title'] as String?) ?? '',
      periodStart: parseDate(doc['periodStart']),
      dueAt: parseDate(doc['dueAt']),
      expectedDifficulty: difficulty ?? QuestionDifficulty.medium,
      subgoalIds:
          (doc['subgoalIds'] as List?)?.whereType<String>().toList() ??
          const [],
      coreLoKeys:
          (doc['coreLoKeys'] as List?)?.whereType<String>().toSet() ?? const {},
      updatedAt: doc['updatedAt'] is String
          ? DateTime.tryParse(doc['updatedAt'] as String)
          : null,
    );
  }
}
