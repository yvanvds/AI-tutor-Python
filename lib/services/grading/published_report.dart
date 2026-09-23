// One row of the `reports` Cosmos container (#150): the published report —
// the frozen, student-facing copy of a signed-off `GradeProposal`.
// Doc id `${uid}_${milestoneId}`, partition key `/uid`.
//
// Note the framing: the proposal is already on the server the moment it is
// computed, so what approval adds is *publication*, not storage. A separate
// container rather than a `publishedAt` flag on the proposal, because the
// teacher's working doc stays the teacher's, a later recompute can never
// mutate what a student already read, and the student query is trivially
// scoped to their own partition. Be honest about what that is: with
// master-key auth it is a clean boundary, not a privacy one.
//
// What it carries is only what the student sees, and the omissions are the
// point (see [PublishedReport.of]).

import 'package:ai_tutor_python/core/cosmos_doc_id.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';

import 'grade_proposal.dart';
import 'milestone.dart';

class PublishedReport {
  const PublishedReport({
    required this.uid,
    required this.milestoneId,
    required this.milestoneTitle,
    required this.dueAt,
    required this.grade,
    required this.justification,
    required this.note,
    required this.computedAt,
    required this.publishedAt,
    required this.updatedAt,
    required this.formulaVersion,
    required this.mEnd,
    required this.k,
    required this.u,
    required this.d,
    required this.coreCounted,
    required this.coreTotal,
    required this.extensionMastered,
    required this.extensionTotal,
    required this.expectedDifficulty,
  });

  final String uid;
  final String milestoneId;

  /// Copied, not referenced: a milestone the teacher renames or deletes
  /// later must not change what a student already read.
  final String milestoneTitle;
  final DateTime dueAt;

  /// The grade that went on the report card — the teacher's
  /// `adjustedGrade`, falling back to the computed proposal.
  final int grade;

  /// The justification as published. Empty only when the teacher signed a
  /// report off without one.
  final String justification;

  /// The teacher's `adjustmentNote`; empty when there is none.
  final String note;

  /// When the formula measured. The report is honest about this because the
  /// teacher runs the batch at a moment of their choosing (#148), so a
  /// classmate who worked another week and scored higher is never a
  /// mystery.
  final DateTime computedAt;

  /// When this report was first released to its student.
  final DateTime publishedAt;

  /// When this copy was last written. A post-sign-off rewrite of the prose
  /// (#149) is a republish: the doc is overwritten and this moves, with no
  /// revision history — the current text is what the report says.
  final DateTime updatedAt;

  final String formulaVersion;

  // The breakdown the student may recompute (PUNTENFORMULE §2.2–§2.6).
  // Reports published before v1.0.16 (#191) also carry `mStart` and `g`;
  // P = M since, and the student page no longer shows them.
  final double mEnd;
  final double k;
  final double u;
  final double d;
  final int coreCounted;
  final int coreTotal;
  final int extensionMastered;
  final int extensionTotal;

  /// The level the core had to be demonstrated at (§2.5) — without it the
  /// `k` a student recomputes cannot be checked against the one here.
  final QuestionDifficulty expectedDifficulty;

  /// Whether this copy has been rewritten since it was released.
  bool get isRepublished => updatedAt.isAfter(publishedAt);

  /// The published copy of [proposal] as of [updatedAt].
  ///
  /// Deliberately **not** copied from the proposal:
  ///   - `supervisedTurns` / `homeTurns` — a turn tally reads as a
  ///     surveillance count on a student's own page, and PUNTENFORMULE §2.7
  ///     already discloses the principle that where the work happened
  ///     weighs differently;
  ///   - `staleLoCount` / `neverProbedCount` — teacher diagnostics about
  ///     how much the system knows, which land on a student as an
  ///     accusation about how much they did.
  ///
  /// Neither is an input to the number a student recomputes, so leaving
  /// them out costs the report nothing it promises.
  factory PublishedReport.of({
    required GradeProposal proposal,
    required Milestone milestone,
    required DateTime publishedAt,
    required DateTime updatedAt,
  }) => PublishedReport(
    uid: proposal.uid,
    milestoneId: milestone.id,
    milestoneTitle: milestone.title,
    dueAt: milestone.dueAt,
    grade: proposal.finalGrade,
    justification: proposal.justification ?? '',
    note: proposal.adjustmentNote,
    computedAt: proposal.computedAt,
    publishedAt: publishedAt,
    updatedAt: updatedAt,
    formulaVersion: proposal.formulaVersion,
    mEnd: proposal.mEnd,
    k: proposal.k,
    u: proposal.u,
    d: proposal.d,
    coreCounted: proposal.coreCounted,
    coreTotal: proposal.coreTotal,
    extensionMastered: proposal.extensionMastered,
    extensionTotal: proposal.extensionTotal,
    expectedDifficulty: milestone.expectedDifficulty,
  );

  /// Whether [other] would publish the exact same thing to the student.
  ///
  /// Everything but [updatedAt], which records *when* the copy was written
  /// rather than what it says: pressing "release" again for a class whose
  /// reports are already out must not stamp a new revision on every one of
  /// them.
  bool sameContentAs(PublishedReport other) =>
      uid == other.uid &&
      milestoneId == other.milestoneId &&
      milestoneTitle == other.milestoneTitle &&
      dueAt == other.dueAt &&
      grade == other.grade &&
      justification == other.justification &&
      note == other.note &&
      computedAt == other.computedAt &&
      publishedAt == other.publishedAt &&
      formulaVersion == other.formulaVersion &&
      mEnd == other.mEnd &&
      k == other.k &&
      u == other.u &&
      d == other.d &&
      coreCounted == other.coreCounted &&
      coreTotal == other.coreTotal &&
      extensionMastered == other.extensionMastered &&
      extensionTotal == other.extensionTotal &&
      expectedDifficulty == other.expectedDifficulty;

  Map<String, dynamic> toMap() => {
    'id': CosmosDocId.publishedReport(uid, milestoneId),
    'type': 'report',
    'uid': uid,
    'milestoneId': milestoneId,
    'milestoneTitle': milestoneTitle,
    'dueAt': dueAt.toUtc().toIso8601String(),
    'grade': grade,
    'justification': justification,
    'note': note,
    'computedAt': computedAt.toUtc().toIso8601String(),
    'publishedAt': publishedAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'formulaVersion': formulaVersion,
    'mEnd': mEnd,
    'k': k,
    'u': u,
    'd': d,
    'coreCounted': coreCounted,
    'coreTotal': coreTotal,
    'extensionMastered': extensionMastered,
    'extensionTotal': extensionTotal,
    'expectedDifficulty': expectedDifficulty.name,
  };

  factory PublishedReport.fromCosmos(Map<String, dynamic> doc) {
    double num_(String key) => (doc[key] as num?)?.toDouble() ?? 0.0;
    int int_(String key) => (doc[key] as num?)?.toInt() ?? 0;
    DateTime date(String key) =>
        (doc[key] is String ? DateTime.tryParse(doc[key] as String) : null) ??
        DateTime.utc(1970);
    final published = date('publishedAt');
    return PublishedReport(
      uid: (doc['uid'] as String?) ?? '',
      milestoneId: (doc['milestoneId'] as String?) ?? '',
      milestoneTitle: (doc['milestoneTitle'] as String?) ?? '',
      dueAt: date('dueAt'),
      grade: int_('grade'),
      justification: (doc['justification'] as String?) ?? '',
      note: (doc['note'] as String?) ?? '',
      computedAt: date('computedAt'),
      publishedAt: published,
      // A doc written before a republish was ever needed reads as "never
      // revised" rather than as revised at the epoch.
      updatedAt: doc['updatedAt'] is String
          ? (DateTime.tryParse(doc['updatedAt'] as String) ?? published)
          : published,
      formulaVersion: (doc['formulaVersion'] as String?) ?? '',
      mEnd: num_('mEnd'),
      k: num_('k'),
      u: num_('u'),
      d: num_('d'),
      coreCounted: int_('coreCounted'),
      coreTotal: int_('coreTotal'),
      extensionMastered: int_('extensionMastered'),
      extensionTotal: int_('extensionTotal'),
      expectedDifficulty:
          QuestionDifficulty.values.cast<QuestionDifficulty?>().firstWhere(
            (v) => v!.name == doc['expectedDifficulty'],
            orElse: () => null,
          ) ??
          QuestionDifficulty.medium,
    );
  }
}
