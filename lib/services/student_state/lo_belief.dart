// One row of the `lo_beliefs` Cosmos container. Per `docs/STUDENT_MODEL.md`
// "Schema sketch", partition `/uid`, doc id `${uid}_${subgoalId}_${loId}`.

import 'package:ai_tutor_python/core/question_difficulty.dart';

class LoBelief {
  final String subgoalId;
  final String loId;
  final double alpha;
  final double beta;
  final DateTime lastUpdatedAt;

  /// Last `ChatRequestType.name` that probed this LO. `null` until first
  /// probe. Used by conductor §2.2 type rotation.
  final String? lastQuestionType;

  /// Set when a positive signal arrives at the student's calibration *at the
  /// time of the answer*, or higher. Required for mastery condition 3
  /// (CONDUCTOR_POLICY 4.1/4.3). Once set, never reset by calibration shifts —
  /// a one-way ratchet for "ever demonstrated at non-easy."
  final DateTime? lastPositiveAtCalibratedAt;

  /// The highest difficulty at which a positive signal was ever earned on
  /// this LO (#103, PUNTENFORMULE §2.5). A one-way ratchet per level: a
  /// later positive at a lower difficulty never lowers it, and calibration
  /// shifts never reset it. `null` until the first positive. Distinct from
  /// [lastPositiveAtCalibratedAt], which is relative to the calibration in
  /// force at the time; this one is absolute, which is what the grade
  /// formula needs as its difficulty differentiator above the 50-line.
  ///
  /// Backwards compatibility: a doc without the field reads as `null` and
  /// stays that way — the model never invents a level (#164). Before, a
  /// doc written before the field existed was read as
  /// [QuestionDifficulty.medium] whenever [lastPositiveAtCalibratedAt] was
  /// set (the old flag's documented "ever demonstrated at non-easy"), and
  /// the next write stored that guess as if it had been measured; a
  /// student who had really demonstrated the LO at hard lost that for
  /// good, since the tutor does not re-probe a mastered LO. The one place
  /// that needs the *meaning* of such a doc — the grade formula's core
  /// gate — applies PUNTENFORMULE §2.5's old-data reading itself, at grade
  /// time (`LoGradeInput.fromBelief`), and nothing is written back.
  final QuestionDifficulty? highestPositiveDifficulty;

  /// Count of consecutive negative signals on this LO whose answer was at
  /// the student's calibration *at the time of the answer*. Resets to 0 on
  /// any positive signal at any difficulty (CONDUCTOR_POLICY §2.3 notch-drop
  /// rule). Defaults to 0 on read when the field is missing on disk —
  /// existing belief docs without it are fine.
  final int recentNegativesAtCalibrated;

  /// When this LO first met all three mastery conditions (CONDUCTOR_POLICY
  /// §4.1) — a one-way stamp, `null` until then, never cleared by decay or
  /// later negatives. It is the gate for transfer credit (#101, §3.7): only
  /// an LO once mastered by direct probing can be refreshed sideways. And
  /// it is what the grade formula reads as "mastered" (#168, PUNTENFORMULE
  /// §2.2): the belief steers the teaching, the stamp steers the grade.
  /// Docs written before the field existed are read by the conductor as
  /// "mastered as of the last direct write" (`belief_math.everMastered`)
  /// and get the stamp on their next write; the grade applies no such
  /// fallback — a doc without the stamp is not mastered — and the app
  /// backfills nothing: older docs get their stamp once, outside the app,
  /// from `turn_history`.
  final DateTime? firstMasteredAt;

  /// Set when an incidental cross-subgoal negative (CONDUCTOR_POLICY §2.4,
  /// #108) lands on a once-mastered LO: later work *suggested* a gap in it
  /// (#112). Since #167 that negative is not written to the belief — it is
  /// the least reliable verdict the system has, and it lands on LOs the
  /// tutor no longer probes directly, so a debit would never be re-tested
  /// — and this flag is all it leaves behind: while set, the LO is due for
  /// a warm-up review (§1.5) regardless of how recently it was written,
  /// and that direct probe is the measurement that counts. Cleared only by
  /// the next direct probe of the LO (the review, or a probe while its
  /// subgoal is active); a transfer credit or positive incidental leaves it
  /// as it was. Missing on older docs: not flagged.
  final DateTime? regressedAt;

  /// When a *direct* probe last landed on this LO (#187): a question that
  /// targeted it, or a signal on it while its own subgoal was active — the
  /// writes that may move the ratchets. Not a follow-up, not a signal from
  /// a later subgoal (§2.4), not a transfer credit: those move
  /// [lastUpdatedAt] and leave this alone. It is the clock of the recheck
  /// slot (CONDUCTOR_POLICY §2.6), which [lastUpdatedAt] cannot be: an LO
  /// that later work keeps touching from the side would look freshly
  /// asked while nobody asked it. Missing on docs written before #187 —
  /// read through [lastDirectProbeAt].
  final DateTime? lastProbedAt;

  const LoBelief({
    required this.subgoalId,
    required this.loId,
    required this.alpha,
    required this.beta,
    required this.lastUpdatedAt,
    this.lastQuestionType,
    this.lastPositiveAtCalibratedAt,
    this.highestPositiveDifficulty,
    this.recentNegativesAtCalibrated = 0,
    this.firstMasteredAt,
    this.regressedAt,
    this.lastProbedAt,
  });

  /// When a direct probe last landed, as far as this doc can tell:
  /// [lastProbedAt]; on a doc from before #187 that was ever the target of
  /// a question ([lastQuestionType] set), [lastUpdatedAt] — never earlier
  /// than the real last probe, so an old doc is at worst due a little
  /// later, never early. `null` for an LO never asked directly.
  DateTime? get lastDirectProbeAt =>
      lastProbedAt ?? (lastQuestionType != null ? lastUpdatedAt : null);

  /// [regressedAt] is the one field that legitimately goes back to `null`
  /// (a review clears it), hence the explicit [clearRegressedAt].
  LoBelief copyWith({
    double? alpha,
    double? beta,
    DateTime? lastUpdatedAt,
    String? lastQuestionType,
    DateTime? lastPositiveAtCalibratedAt,
    QuestionDifficulty? highestPositiveDifficulty,
    int? recentNegativesAtCalibrated,
    DateTime? firstMasteredAt,
    DateTime? regressedAt,
    bool clearRegressedAt = false,
    DateTime? lastProbedAt,
  }) {
    return LoBelief(
      subgoalId: subgoalId,
      loId: loId,
      alpha: alpha ?? this.alpha,
      beta: beta ?? this.beta,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      lastQuestionType: lastQuestionType ?? this.lastQuestionType,
      lastPositiveAtCalibratedAt:
          lastPositiveAtCalibratedAt ?? this.lastPositiveAtCalibratedAt,
      highestPositiveDifficulty:
          highestPositiveDifficulty ?? this.highestPositiveDifficulty,
      recentNegativesAtCalibrated:
          recentNegativesAtCalibrated ?? this.recentNegativesAtCalibrated,
      firstMasteredAt: firstMasteredAt ?? this.firstMasteredAt,
      regressedAt: clearRegressedAt ? null : (regressedAt ?? this.regressedAt),
      lastProbedAt: lastProbedAt ?? this.lastProbedAt,
    );
  }

  static String docIdFor({
    required String uid,
    required String subgoalId,
    required String loId,
  }) => '${uid}_${subgoalId}_$loId';

  Map<String, dynamic> toMap({required String uid}) => {
    'id': docIdFor(uid: uid, subgoalId: subgoalId, loId: loId),
    'type': 'lo_belief',
    'uid': uid,
    'subgoalId': subgoalId,
    'loId': loId,
    'alpha': alpha,
    'beta': beta,
    'lastUpdatedAt': lastUpdatedAt.toUtc().toIso8601String(),
    if (lastQuestionType != null) 'lastQuestionType': lastQuestionType,
    if (lastPositiveAtCalibratedAt != null)
      'lastPositiveAtCalibratedAt': lastPositiveAtCalibratedAt!
          .toUtc()
          .toIso8601String(),
    if (highestPositiveDifficulty != null)
      'highestPositiveDifficulty': highestPositiveDifficulty!.name,
    'recentNegativesAtCalibrated': recentNegativesAtCalibrated,
    if (firstMasteredAt != null)
      'firstMasteredAt': firstMasteredAt!.toUtc().toIso8601String(),
    if (regressedAt != null)
      'regressedAt': regressedAt!.toUtc().toIso8601String(),
    if (lastProbedAt != null)
      'lastProbedAt': lastProbedAt!.toUtc().toIso8601String(),
  };

  factory LoBelief.fromCosmos(Map<String, dynamic> doc) {
    final updatedRaw = doc['lastUpdatedAt'];
    final positiveRaw = doc['lastPositiveAtCalibratedAt'];
    final lastPositiveAtCalibratedAt = positiveRaw is String
        ? DateTime.tryParse(positiveRaw)
        : null;
    final highestRaw = doc['highestPositiveDifficulty'];
    // An unrecognised level is treated like a missing one, and a missing
    // one is *missing*: not derived from the old flag (#164).
    final highestPositiveDifficulty = QuestionDifficulty.values
        .cast<QuestionDifficulty?>()
        .firstWhere((d) => d!.name == highestRaw, orElse: () => null);
    return LoBelief(
      subgoalId: (doc['subgoalId'] as String?) ?? '',
      loId: (doc['loId'] as String?) ?? '',
      alpha: (doc['alpha'] as num?)?.toDouble() ?? 1.0,
      beta: (doc['beta'] as num?)?.toDouble() ?? 1.0,
      lastUpdatedAt: updatedRaw is String
          ? (DateTime.tryParse(updatedRaw) ?? DateTime.utc(1970))
          : DateTime.utc(1970),
      lastQuestionType: doc['lastQuestionType'] as String?,
      lastPositiveAtCalibratedAt: lastPositiveAtCalibratedAt,
      highestPositiveDifficulty: highestPositiveDifficulty,
      recentNegativesAtCalibrated:
          (doc['recentNegativesAtCalibrated'] as num?)?.toInt() ?? 0,
      firstMasteredAt: doc['firstMasteredAt'] is String
          ? DateTime.tryParse(doc['firstMasteredAt'] as String)
          : null,
      regressedAt: doc['regressedAt'] is String
          ? DateTime.tryParse(doc['regressedAt'] as String)
          : null,
      lastProbedAt: doc['lastProbedAt'] is String
          ? DateTime.tryParse(doc['lastProbedAt'] as String)
          : null,
    );
  }
}
