import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/grader_payload.dart';

class ExplainFeedback implements ChatResponse {
  @override
  final String type;
  final AnswerQuality quality;
  final String prompt;
  final List<LoSignal> loSignals;
  final List<TransferLoRef> transferLOs;
  final FollowUp? followUp;

  ExplainFeedback({
    required this.type,
    required this.quality,
    required this.prompt,
    this.loSignals = const [],
    this.transferLOs = const [],
    this.followUp,
  });

  factory ExplainFeedback.fromMap(Map<String, dynamic> map) {
    return ExplainFeedback(
      type: map['type'] ?? 'explain_feedback',
      quality: _stringToQuality(map['overallQuality'] ?? map['quality']),
      prompt: map['prompt'] ?? '',
      loSignals: parseLoSignals(map['loSignals']),
      transferLOs: parseTransferLOs(map['transferLOs']),
      followUp: FollowUp.tryParse(map['followUp']),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'overallQuality': quality.name,
      'prompt': prompt,
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
