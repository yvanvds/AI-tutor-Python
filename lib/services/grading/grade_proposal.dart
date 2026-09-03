// One row of the `grade_proposals` Cosmos container (#99): the computed
// proposal for one student on one milestone, the AI-written justification
// once the teacher asked for it, and the teacher's adjustment + sign-off.
// Doc id `${uid}_${milestoneId}`, partition key `/uid`.
//
// A signed-off doc is frozen: PUNTENFORMULE §5 says a grade that reached a
// report card is never recomputed, so `GradeProposalService.compute` hands
// the stored doc back untouched once `signedOffAt` is set.

import 'package:ai_tutor_python/core/cosmos_doc_id.dart';

class GradeProposal {
  const GradeProposal({
    required this.uid,
    required this.milestoneId,
    required this.formulaVersion,
    required this.computedAt,
    required this.k,
    required this.u,
    required this.d,
    required this.mEnd,
    required this.mStart,
    required this.g,
    required this.proposal,
    required this.coreTotal,
    required this.coreCounted,
    required this.extensionTotal,
    required this.extensionMastered,
    required this.masteredTotal,
    required this.hardCount,
    required this.staleLoCount,
    required this.neverProbedCount,
    required this.supervisedTurns,
    required this.homeTurns,
    this.justification,
    this.justificationAt,
    this.adjustedGrade,
    this.adjustmentNote = '',
    this.signedOffAt,
  });

  final String uid;
  final String milestoneId;

  /// `GradingConstants.formulaVersion` at compute time.
  final String formulaVersion;
  final DateTime computedAt;

  // §2.2–§2.6
  final double k;
  final double u;
  final double d;
  final double mEnd;
  final double mStart;
  final double g;

  /// The deterministic proposal `P`, rounded to a whole point.
  final int proposal;

  // Counts behind the fractions, for display and for the justification.
  final int coreTotal;
  final int coreCounted;
  final int extensionTotal;
  final int extensionMastered;
  final int masteredTotal;
  final int hardCount;

  // Reliability signals (§3.2): staleness and provenance, never posterior
  // width — a narrow belief is what fast mastery looks like.
  /// Milestone LOs whose belief was last written longer ago than the
  /// warm-up threshold (`PolicyConstants.warmUpStaleAfter`) before the
  /// report moment, or never at all.
  final int staleLoCount;

  /// Milestone LOs with no belief doc at all.
  final int neverProbedCount;

  /// Graded turns inside the grading window, by provenance.
  final int supervisedTurns;
  final int homeTurns;

  final String? justification;
  final DateTime? justificationAt;

  /// What goes on the report card once signed: the teacher's number, which
  /// defaults to [proposal].
  final int? adjustedGrade;
  final String adjustmentNote;
  final DateTime? signedOffAt;

  bool get isSignedOff => signedOffAt != null;

  /// The number that ends up on the report card.
  int get finalGrade => adjustedGrade ?? proposal;

  GradeProposal copyWith({
    String? justification,
    DateTime? justificationAt,
    int? adjustedGrade,
    String? adjustmentNote,
    DateTime? signedOffAt,
  }) => GradeProposal(
    uid: uid,
    milestoneId: milestoneId,
    formulaVersion: formulaVersion,
    computedAt: computedAt,
    k: k,
    u: u,
    d: d,
    mEnd: mEnd,
    mStart: mStart,
    g: g,
    proposal: proposal,
    coreTotal: coreTotal,
    coreCounted: coreCounted,
    extensionTotal: extensionTotal,
    extensionMastered: extensionMastered,
    masteredTotal: masteredTotal,
    hardCount: hardCount,
    staleLoCount: staleLoCount,
    neverProbedCount: neverProbedCount,
    supervisedTurns: supervisedTurns,
    homeTurns: homeTurns,
    justification: justification ?? this.justification,
    justificationAt: justificationAt ?? this.justificationAt,
    adjustedGrade: adjustedGrade ?? this.adjustedGrade,
    adjustmentNote: adjustmentNote ?? this.adjustmentNote,
    signedOffAt: signedOffAt ?? this.signedOffAt,
  );

  Map<String, dynamic> toMap() => {
    'id': CosmosDocId.gradeProposal(uid, milestoneId),
    'type': 'grade_proposal',
    'uid': uid,
    'milestoneId': milestoneId,
    'formulaVersion': formulaVersion,
    'computedAt': computedAt.toUtc().toIso8601String(),
    'k': k,
    'u': u,
    'd': d,
    'mEnd': mEnd,
    'mStart': mStart,
    'g': g,
    'proposal': proposal,
    'coreTotal': coreTotal,
    'coreCounted': coreCounted,
    'extensionTotal': extensionTotal,
    'extensionMastered': extensionMastered,
    'masteredTotal': masteredTotal,
    'hardCount': hardCount,
    'staleLoCount': staleLoCount,
    'neverProbedCount': neverProbedCount,
    'supervisedTurns': supervisedTurns,
    'homeTurns': homeTurns,
    if (justification != null) 'justification': justification,
    if (justificationAt != null)
      'justificationAt': justificationAt!.toUtc().toIso8601String(),
    if (adjustedGrade != null) 'adjustedGrade': adjustedGrade,
    if (adjustmentNote.isNotEmpty) 'adjustmentNote': adjustmentNote,
    if (signedOffAt != null)
      'signedOffAt': signedOffAt!.toUtc().toIso8601String(),
  };

  factory GradeProposal.fromCosmos(Map<String, dynamic> doc) {
    double num_(String key) => (doc[key] as num?)?.toDouble() ?? 0.0;
    int int_(String key) => (doc[key] as num?)?.toInt() ?? 0;
    DateTime? date(String key) =>
        doc[key] is String ? DateTime.tryParse(doc[key] as String) : null;
    return GradeProposal(
      uid: (doc['uid'] as String?) ?? '',
      milestoneId: (doc['milestoneId'] as String?) ?? '',
      formulaVersion: (doc['formulaVersion'] as String?) ?? '',
      computedAt: date('computedAt') ?? DateTime.utc(1970),
      k: num_('k'),
      u: num_('u'),
      d: num_('d'),
      mEnd: num_('mEnd'),
      mStart: num_('mStart'),
      g: num_('g'),
      proposal: int_('proposal'),
      coreTotal: int_('coreTotal'),
      coreCounted: int_('coreCounted'),
      extensionTotal: int_('extensionTotal'),
      extensionMastered: int_('extensionMastered'),
      masteredTotal: int_('masteredTotal'),
      hardCount: int_('hardCount'),
      staleLoCount: int_('staleLoCount'),
      neverProbedCount: int_('neverProbedCount'),
      supervisedTurns: int_('supervisedTurns'),
      homeTurns: int_('homeTurns'),
      justification: doc['justification'] as String?,
      justificationAt: date('justificationAt'),
      adjustedGrade: (doc['adjustedGrade'] as num?)?.toInt(),
      adjustmentNote: (doc['adjustmentNote'] as String?) ?? '',
      signedOffAt: date('signedOffAt'),
    );
  }
}
