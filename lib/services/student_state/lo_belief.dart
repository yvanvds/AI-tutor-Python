// One row of the `lo_beliefs` Cosmos container. Per `docs/STUDENT_MODEL.md`
// "Schema sketch", partition `/uid`, doc id `${uid}_${subgoalId}_${loId}`.

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

  /// Count of consecutive negative signals on this LO whose answer was at
  /// the student's calibration *at the time of the answer*. Resets to 0 on
  /// any positive signal at any difficulty (CONDUCTOR_POLICY §2.3 notch-drop
  /// rule). Defaults to 0 on read when the field is missing on disk —
  /// existing belief docs without it are fine.
  final int recentNegativesAtCalibrated;

  const LoBelief({
    required this.subgoalId,
    required this.loId,
    required this.alpha,
    required this.beta,
    required this.lastUpdatedAt,
    this.lastQuestionType,
    this.lastPositiveAtCalibratedAt,
    this.recentNegativesAtCalibrated = 0,
  });

  LoBelief copyWith({
    double? alpha,
    double? beta,
    DateTime? lastUpdatedAt,
    String? lastQuestionType,
    DateTime? lastPositiveAtCalibratedAt,
    int? recentNegativesAtCalibrated,
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
      recentNegativesAtCalibrated:
          recentNegativesAtCalibrated ?? this.recentNegativesAtCalibrated,
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
    'recentNegativesAtCalibrated': recentNegativesAtCalibrated,
  };

  factory LoBelief.fromCosmos(Map<String, dynamic> doc) {
    final updatedRaw = doc['lastUpdatedAt'];
    final positiveRaw = doc['lastPositiveAtCalibratedAt'];
    return LoBelief(
      subgoalId: (doc['subgoalId'] as String?) ?? '',
      loId: (doc['loId'] as String?) ?? '',
      alpha: (doc['alpha'] as num?)?.toDouble() ?? 1.0,
      beta: (doc['beta'] as num?)?.toDouble() ?? 1.0,
      lastUpdatedAt: updatedRaw is String
          ? (DateTime.tryParse(updatedRaw) ?? DateTime.utc(1970))
          : DateTime.utc(1970),
      lastQuestionType: doc['lastQuestionType'] as String?,
      lastPositiveAtCalibratedAt: positiveRaw is String
          ? DateTime.tryParse(positiveRaw)
          : null,
      recentNegativesAtCalibrated:
          (doc['recentNegativesAtCalibrated'] as num?)?.toInt() ?? 0,
    );
  }
}
