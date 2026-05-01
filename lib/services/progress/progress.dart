/// One row of the `progress` Cosmos container. Each doc carries its own
/// `uid` and `goalId`, with composite id `${uid}_${goalId}` and the user's
/// uid as the partition key.
class Progress {
  final String goalID;
  final double progress;
  final DateTime? updatedAt;

  Progress({required this.goalID, required this.progress, this.updatedAt});

  /// Build a Cosmos doc map. The container partition key is `/uid`, so
  /// every doc must carry the owner's uid; the composite id keeps doc-id
  /// uniqueness across users in a single container.
  Map<String, dynamic> toMap({required String uid}) => {
    'id': '${uid}_$goalID',
    'uid': uid,
    'goalId': goalID,
    'progress': progress,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  };

  factory Progress.fromCosmos(Map<String, dynamic> doc) {
    final raw = doc['updatedAt'];
    return Progress(
      goalID: (doc['goalId'] as String?) ?? '',
      progress: (doc['progress'] as num?)?.toDouble() ?? 0.0,
      updatedAt: raw is String ? DateTime.tryParse(raw) : null,
    );
  }
}
