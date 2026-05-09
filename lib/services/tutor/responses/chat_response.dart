// 1) Common interface for every AI message/response payload
import 'package:ai_tutor_python/services/tutor/responses/answer.dart';
import 'package:ai_tutor_python/services/tutor/responses/code_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/complete_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/error_summary.dart';
import 'package:ai_tutor_python/services/tutor/responses/explain_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/explain_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/hint.dart';
import 'package:ai_tutor_python/services/tutor/responses/mcq_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_question.dart';
import 'package:ai_tutor_python/services/tutor/responses/status_summary.dart';
import 'package:ai_tutor_python/services/tutor/responses/write_code.dart';

abstract class ChatResponse {
  String get type;
  Map<String, dynamic> toJson();
}

// 2) Central factory to decode any payload by its "type"
class ChatResponseFactory {
  static ChatResponse fromMap(Map<String, dynamic> map) {
    final t = (map['type'] as String?)?.toLowerCase();
    if (t == null) {
      throw const FormatException('Missing "type" in payload.');
    }
    switch (t) {
      // Question types
      case 'socratic_question':
        return SocraticQuestion.fromMap(map);
      case 'multiple_choice':
        return MultipleChoice.fromMap(map);
      case 'explain_code':
        return ExplainCode.fromMap(map);
      case 'complete_code':
        return CompleteCode.fromMap(map);
      case 'write_code':
        return WriteCode.fromMap(map);

      // Feedback / system types
      case 'answer':
        return Answer.fromMap(map);
      case 'hint':
        return Hint.fromMap(map);
      case 'code_feedback':
        return CodeFeedback.fromMap(map);
      case 'mcq_feedback':
        return McqFeedback.fromMap(map);
      case 'explain_feedback':
        return ExplainFeedback.fromMap(map);
      case 'socratic_feedback':
        return SocraticFeedback.fromMap(map);
      case 'status_summary':
        return StatusSummary.fromMap(map);
      case 'error':
        return ErrorResponse.fromMap(map);

      default:
        return ErrorResponse(type: "error", message: 'Unknown type: $t');
    }
  }
}
