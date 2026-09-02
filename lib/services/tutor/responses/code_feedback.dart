import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/grader_payload.dart';

/*
{
  "type": "code_feedback",
  "summary": "brief explanation of correctness or errors",
  "suggestion": "concise next step for improvement",
  "overallQuality": "wrong | partial | correct",
  "loSignals": [...],
  "transferLOs": [{ "subgoalId": "...", "loId": "..." }],   // optional (#101)
  "followUp": { "question": "...", "rationale": "..." }   // optional
}
*/

class CodeFeedback implements ChatResponse {
  @override
  final String type;
  final String prompt;
  final String suggestion;
  final AnswerQuality quality;
  final List<LoSignal> loSignals;
  final List<TransferLoRef> transferLOs;
  final FollowUp? followUp;

  CodeFeedback({
    required this.type,
    required this.prompt,
    required this.suggestion,
    required this.quality,
    this.loSignals = const [],
    this.transferLOs = const [],
    this.followUp,
  });

  factory CodeFeedback.fromMap(Map<String, dynamic> map) {
    return CodeFeedback(
      type: map['type'] ?? 'code_feedback',
      prompt: map['prompt'] ?? '',
      suggestion: map['suggestion'] ?? '',
      quality: _stringToQuality(map['overallQuality'] ?? map['quality']),
      loSignals: parseLoSignals(map['loSignals']),
      transferLOs: parseTransferLOs(map['transferLOs']),
      followUp: FollowUp.tryParse(map['followUp']),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'prompt': prompt,
      'suggestion': suggestion,
      'overallQuality': quality.name,
      'loSignals': loSignals.map((s) => s.toJson()).toList(),
      if (transferLOs.isNotEmpty)
        'transferLOs': transferLOs.map((t) => t.toJson()).toList(),
      if (followUp != null) 'followUp': followUp!.toJson(),
    };
  }

  static AnswerQuality _stringToQuality(Object? value) {
    if (value is! String) return AnswerQuality.wrong;
    switch (value.toLowerCase()) {
      case 'wrong':
        return AnswerQuality.wrong;
      case 'partial':
        return AnswerQuality.partial;
      case 'correct':
        return AnswerQuality.correct;
      default:
        return AnswerQuality.wrong;
    }
  }
}
