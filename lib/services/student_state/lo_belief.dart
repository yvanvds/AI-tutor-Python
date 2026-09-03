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
  /// Backwards compatibility: docs written before the field existed read
  /// the old binary flag's documented meaning — "ever demonstrated at
  /// non-easy" — as [QuestionDifficulty.medium] when
  /// [lastPositiveAtCalibratedAt] is set, and `null` otherwise.
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
  /// an LO once mastered by direct probing can be refreshed sideways.
  /// Docs written before the field existed are read by the conductor as
  /// "mastered as of the last direct write" (`belief_math.everMastered`)
  /// and get the stamp on their next write; nothing is backfilled.
  final DateTime? firstMasteredAt;

  /// Set when an incidental cross-subgoal negative (CONDUCTOR_POLICY §2.4,
  /// #108) leaves a once-mastered LO below the mastery rule — later work
  /// revealed a regression on it (#112). While set, the LO is due for a
  /// warm-up review (§1.5) regardless of how recently it was written: the
  /// negative itself bumps `lastUpdatedAt`, which would otherwise push
  /// the review `warmUpStaleAfter` out. Cleared by the next direct probe
  /// of the LO (the review, or a probe while its subgoal is active) and by
  /// any write that brings the stored belief back to mastery (a transfer
  /// credit, a positive incidental). Missing on older docs: not regressed.
  final DateTime? regressedAt;

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
  });

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
  };

  factory LoBelief.fromCosmos(Map<String, dynamic> doc) {
    final updatedRaw = doc['lastUpdatedAt'];
    final positiveRaw = doc['lastPositiveAtCalibratedAt'];
    final lastPositiveAtCalibratedAt = positiveRaw is String
        ? DateTime.tryParse(positiveRaw)
        : null;
    final highestRaw = doc['highestPositiveDifficulty'];
    // An unrecognised level is treated like a missing one.
    final highestPositiveDifficulty =
        QuestionDifficulty.values.cast<QuestionDifficulty?>().firstWhere(
          (d) => d!.name == highestRaw,
          orElse: () => null,
        ) ??
        _legacyHighest(lastPositiveAtCalibratedAt);
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
    );
  }
}

/// What a doc without `highestPositiveDifficulty` says about the level: the
/// old flag's documented reading ("ever demonstrated at non-easy") maps to
/// `medium`; no flag means no positive on record.
QuestionDifficulty? _legacyHighest(DateTime? lastPositiveAtCalibratedAt) =>
    lastPositiveAtCalibratedAt == null ? null : QuestionDifficulty.medium;
