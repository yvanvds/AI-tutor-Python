import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/cosmos_doc_id.dart';

/// One snapshot of a (uid, goalId) progress value at a point in time. Stored
/// in the `progress_history` Cosmos container with `/uid` as partition key.
/// Time series feed for the teacher detail panel; written best-effort by
/// `ProgressService.upsert` whenever the persisted progress actually changes.
class ProgressSample {
  final String goalID;
  final double progress;

  /// Quality of the answer that triggered this sample. Optional — not
  /// every progress change comes from a feedback turn (e.g. teacher
  /// resets, future admin tools).
  final AnswerQuality? quality;

  final DateTime at;

  ProgressSample({
    required this.goalID,
    required this.progress,
    required this.at,
    this.quality,
  });

  /// Build a Cosmos doc map. The container partition key is `/uid`.
  Map<String, dynamic> toMap({required String uid}) {
    return {
      'id': CosmosDocId.progressHistory(at),
      'uid': uid,
      'goalId': goalID,
      'progress': progress,
      if (quality != null) 'quality': quality!.name,
      'at': at.toUtc().toIso8601String(),
    };
  }

  factory ProgressSample.fromCosmos(Map<String, dynamic> doc) {
    final atRaw = doc['at'];
    return ProgressSample(
      goalID: (doc['goalId'] as String?) ?? '',
      progress: (doc['progress'] as num?)?.toDouble() ?? 0.0,
      quality: _parseQuality(doc['quality']),
      at: atRaw is String
          ? (DateTime.tryParse(atRaw) ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  static AnswerQuality? _parseQuality(Object? raw) {
    if (raw is! String) return null;
    for (final q in AnswerQuality.values) {
      if (q.name == raw) return q;
    }
    return null;
  }
}
