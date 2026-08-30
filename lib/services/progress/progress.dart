/// One row of the `progress` Cosmos container. Each doc carries its own
/// `uid` and `goalId`, with composite id `${uid}_${goalId}` and the user's
/// uid as the partition key.
///
/// Under the LO-belief redesign, `progress` is a derived cache of subgoal
/// completion (0.0–1.0) aggregated from per-LO beliefs. The previous
/// `recentAnswers`, `difficulty`, `recentConceptAttributions` fields are
/// gone — answer history lives in `account.calibration` and per-LO beliefs;
/// concept attributions are subsumed by per-LO signals (see STUDENT_MODEL).
class Progress {
  final String goalID;
  final double progress;
  final DateTime? updatedAt;

  /// When the conductor last wrote this doc. Set automatically by [toMap]
  /// on every upsert; the constructor parameter is for tests/in-memory use.
  final DateTime? lastSessionAt;

  Progress({
    required this.goalID,
    required this.progress,
    this.updatedAt,
    this.lastSessionAt,
  });

  /// Build a Cosmos doc map. The container partition key is `/uid`, so
  /// every doc must carry the owner's uid; the composite id keeps doc-id
  /// uniqueness across users in a single container.
  Map<String, dynamic> toMap({required String uid}) {
    final now = DateTime.now().toUtc().toIso8601String();
    return {
      'id': '${uid}_$goalID',
      'uid': uid,
      'goalId': goalID,
      'progress': progress,
      'updatedAt': now,
      'lastSessionAt': now,
    };
  }

  factory Progress.fromCosmos(Map<String, dynamic> doc) {
    final updatedRaw = doc['updatedAt'];
    final lastSessionRaw = doc['lastSessionAt'];
    return Progress(
      goalID: (doc['goalId'] as String?) ?? '',
      progress: (doc['progress'] as num?)?.toDouble() ?? 0.0,
      updatedAt: updatedRaw is String ? DateTime.tryParse(updatedRaw) : null,
      lastSessionAt: lastSessionRaw is String
          ? DateTime.tryParse(lastSessionRaw)
          : null,
    );
  }
}
