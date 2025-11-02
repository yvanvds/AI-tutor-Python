import 'dart:convert';

import 'package:ai_tutor_python/core/question_difficulty.dart';

class QuestionFormatter {
  static String _encodeRequest(String requestType, {QuestionDifficulty? difficulty, Map<String, dynamic>? additionalFields}) {
    final request = <String, dynamic>{"request_type": requestType};
    if (difficulty != null) {
      request["difficulty"] = difficulty.toString().split('.').last;
    }
    if (additionalFields != null) {
      request.addAll(additionalFields);
    }
    return jsonEncode(request);
  }

  static String socraticQuestion(QuestionDifficulty difficulty) =>
      _encodeRequest("socratic_question", difficulty: difficulty);

  static String mcQuestion(QuestionDifficulty difficulty) =>
      _encodeRequest("multiple_choice", difficulty: difficulty);

  static String explainCodeQuestion(QuestionDifficulty difficulty) =>
      _encodeRequest("explain_code", difficulty: difficulty);

  static String completeCodeQuestion(QuestionDifficulty difficulty) =>
      _encodeRequest("complete_code", difficulty: difficulty);

  static String writeCodeQuestion(QuestionDifficulty difficulty) =>
      _encodeRequest("write_code", difficulty: difficulty);

  static String requestHint(String currentCode) =>
      _encodeRequest("request_hint", additionalFields: {"current_code": currentCode});

  static String studentQuestion(String question, String? code) =>
      _encodeRequest("student_question", additionalFields: {
        "question": question,
        "code": code ?? "",
      });

  static String explainAnswer(String answer) =>
      _encodeRequest("explain_answer", additionalFields: {"answer": answer});

  static String socraticFeedback(String answer) =>
      _encodeRequest("socratic_feedback", additionalFields: {"answer": answer});

  static String submitCode(String code) =>
      _encodeRequest("submit_code", additionalFields: {"code": code});

  static String mcqAnswer(String answer) =>
      _encodeRequest("mcq_answer", additionalFields: {"answer": answer});

  static String status() => _encodeRequest("status");
}
