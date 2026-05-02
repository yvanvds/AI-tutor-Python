import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/progress/concept_attribution.dart';

/// One row of the `progress` Cosmos container. Each doc carries its own
/// `uid` and `goalId`, with composite id `${uid}_${goalId}` and the user's
/// uid as the partition key.
class Progress {
  static const int recentAnswersWindow = 5;
  static const int recentConceptAttributionsWindow = 20;

  final String goalID;
  final double progress;
  final DateTime? updatedAt;

  /// Last calibrated difficulty for this (uid, goalId). Defaults to `easy`
  /// for legacy docs that predate this field.
  final QuestionDifficulty difficulty;

  /// Rolling answer-quality window for this (uid, goalId), oldest-first.
  /// Trimmed to the last [recentAnswersWindow] entries on write.
  final List<AnswerQuality> recentAnswers;

  /// When the conductor last wrote this doc. Set automatically by [toMap]
  /// on every upsert; the constructor parameter is for tests/in-memory use.
  final DateTime? lastSessionAt;

  /// AI-emitted suspected-concept attributions for recent feedback turns,
  /// oldest-first. Trimmed to the last [recentConceptAttributionsWindow]
  /// entries on write. Pure data collection — no behaviour reads this yet.
  final List<ConceptAttribution> recentConceptAttributions;

  Progress({
    required this.goalID,
    required this.progress,
    this.updatedAt,
    this.difficulty = QuestionDifficulty.easy,
    this.recentAnswers = const [],
    this.lastSessionAt,
    this.recentConceptAttributions = const [],
  });

  /// Build a Cosmos doc map. The container partition key is `/uid`, so
  /// every doc must carry the owner's uid; the composite id keeps doc-id
  /// uniqueness across users in a single container.
  Map<String, dynamic> toMap({required String uid}) {
    final now = DateTime.now().toUtc().toIso8601String();
    final trimmed = recentAnswers.length <= recentAnswersWindow
        ? recentAnswers
        : recentAnswers.sublist(
            recentAnswers.length - recentAnswersWindow,
          );
    final trimmedAttrs = recentConceptAttributions.length <=
            recentConceptAttributionsWindow
        ? recentConceptAttributions
        : recentConceptAttributions.sublist(
            recentConceptAttributions.length -
                recentConceptAttributionsWindow,
          );
    return {
      'id': '${uid}_$goalID',
      'uid': uid,
      'goalId': goalID,
      'progress': progress,
      'updatedAt': now,
      'difficulty': difficulty.name,
      'recentAnswers': trimmed.map((q) => q.name).toList(),
      'lastSessionAt': now,
      'recentConceptAttributions':
          trimmedAttrs.map((a) => a.toJson()).toList(),
    };
  }

  factory Progress.fromCosmos(Map<String, dynamic> doc) {
    final updatedRaw = doc['updatedAt'];
    final lastSessionRaw = doc['lastSessionAt'];
    return Progress(
      goalID: (doc['goalId'] as String?) ?? '',
      progress: (doc['progress'] as num?)?.toDouble() ?? 0.0,
      updatedAt: updatedRaw is String ? DateTime.tryParse(updatedRaw) : null,
      difficulty: _parseDifficulty(doc['difficulty']),
      recentAnswers: _parseAnswers(doc['recentAnswers']),
      lastSessionAt:
          lastSessionRaw is String ? DateTime.tryParse(lastSessionRaw) : null,
      recentConceptAttributions:
          _parseAttributions(doc['recentConceptAttributions']),
    );
  }

  static QuestionDifficulty _parseDifficulty(Object? raw) {
    if (raw is! String) return QuestionDifficulty.easy;
    for (final d in QuestionDifficulty.values) {
      if (d.name == raw) return d;
    }
    return QuestionDifficulty.easy;
  }

  static List<AnswerQuality> _parseAnswers(Object? raw) {
    if (raw is! List) return const [];
    final out = <AnswerQuality>[];
    for (final entry in raw) {
      if (entry is! String) continue;
      for (final q in AnswerQuality.values) {
        if (q.name == entry) {
          out.add(q);
          break;
        }
      }
    }
    return out;
  }

  static List<ConceptAttribution> _parseAttributions(Object? raw) {
    if (raw is! List) return const [];
    final out = <ConceptAttribution>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      out.add(ConceptAttribution.fromJson(entry.cast<String, dynamic>()));
    }
    return out;
  }
}
