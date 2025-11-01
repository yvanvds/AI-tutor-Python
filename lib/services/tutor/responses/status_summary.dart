import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';

class StatusSummary implements ChatResponse {
  final String type;
  final String summary;
  final int hintsUsed;
  final List<String> commonIssues;
  final String lastExerciseType;

  StatusSummary({
    required this.type,
    required this.summary,
    required this.hintsUsed,
    required this.commonIssues,
    required this.lastExerciseType,
  });

  factory StatusSummary.fromMap(Map<String, dynamic> map) {
    final stats = map['stats'] ?? {};
    return StatusSummary(
      type: map['type'] ?? 'status_summary',
      summary: map['summary'] ?? '',
      hintsUsed: stats['hints_used'] ?? 0,
      commonIssues:
          (stats['common_issues'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      lastExerciseType: stats['last_exercise_type'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'summary': summary,
    'stats': {
      'hints_used': hintsUsed,
      'common_issues': commonIssues,
      'last_exercise_type': lastExerciseType,
    },
  };
}
