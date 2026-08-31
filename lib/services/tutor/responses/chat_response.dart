// 1) Common interface for every AI message/response payload
import 'package:ai_tutor_python/services/chat/chat_notice.dart';
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
        final completeCode = CompleteCode.fromMap(map);
        // A code-completion exercise with nothing removed is unusable: the
        // student is handed a finished program and asked to fill in the
        // missing part (#78). Reject it here, where every other response the
        // app cannot use is rejected, so the ErrorResponse handler's
        // retry/fallback path recovers instead of the widget rendering it.
        if (!completeCode.hasBlank) {
          return ErrorResponse(
            type: 'error',
            message:
                'complete_code without a blank marker: ${completeCode.code}',
            notice: const ChatNotice(ChatNoticeKind.exerciseWithoutBlank),
          );
        }
        return completeCode;
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
        return ErrorResponse(
          type: 'error',
          message: 'Unknown type: $t',
          notice: ChatNotice(ChatNoticeKind.unknownResponseType, args: [t]),
        );
    }
  }
}
