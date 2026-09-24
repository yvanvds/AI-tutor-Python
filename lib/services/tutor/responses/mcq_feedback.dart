import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/grader_payload.dart';

class McqFeedback implements ChatResponse {
  @override
  final String type;
  final AnswerQuality quality;
  final String prompt;
  final List<LoSignal> loSignals;
  final List<TransferLoRef> transferLOs;
  final FollowUp? followUp;

  /// META's `keyDisputed` (#198, LLM_CONTRACT "The answer key"): the grader
  /// of a pick that was told the answer key (`correct_option`) found the
  /// key itself wrong — whichever option the student picked, also when
  /// grade and key agree that the pick is wrong. Only `true` counts.
  ///
  /// A message to the app, not part of the conversation: [toJson] leaves it
  /// out, so it is not on the exercise's history a later call reads, and
  /// nothing the student sees carries it.
  final bool keyDisputed;

  McqFeedback({
    required this.type,
    required this.quality,
    required this.prompt,
    this.loSignals = const [],
    this.transferLOs = const [],
    this.followUp,
    this.keyDisputed = false,
  });

  factory McqFeedback.fromMap(Map<String, dynamic> map) {
    return McqFeedback(
      type: map['type'] ?? 'mcq_feedback',
      quality: _stringToQuality(map['overallQuality'] ?? map['quality']),
      prompt: map['prompt'] ?? '',
      loSignals: parseLoSignals(map['loSignals']),
      transferLOs: parseTransferLOs(map['transferLOs']),
      followUp: FollowUp.tryParse(map['followUp']),
      keyDisputed: map['keyDisputed'] == true,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'overallQuality': quality.name,
    'prompt': prompt,
    'loSignals': loSignals.map((s) => s.toJson()).toList(),
    if (transferLOs.isNotEmpty)
      'transferLOs': transferLOs.map((t) => t.toJson()).toList(),
    if (followUp != null) 'followUp': followUp!.toJson(),
  };

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
