import 'dart:convert';

import 'package:ai_tutor_python/core/question_difficulty.dart';

class QuestionFormatter {
  static String socraticQuestion(QuestionDifficulty difficulty) {
    final request = {
      "request_type": "socratic_question",
      "difficulty": difficulty.toString().split('.').last,
    };

    return jsonEncode(request);
  }

  static String mcQuestion(QuestionDifficulty difficulty) {
    final request = {
      "request_type": "multiple_choice",
      "difficulty": difficulty.toString().split('.').last,
    };

    return jsonEncode(request);
  }

  static String explainCodeQuestion(QuestionDifficulty difficulty) {
    final request = {
      "request_type": "explain_code",
      "difficulty": difficulty.toString().split('.').last,
    };

    return jsonEncode(request);
  }

  static String completeCodeQuestion(QuestionDifficulty difficulty) {
    final request = {
      "request_type": "complete_code",
      "difficulty": difficulty.toString().split('.').last,
    };

    return jsonEncode(request);
  }

  static String writeCodeQuestion(QuestionDifficulty difficulty) {
    final request = {
      "request_type": "write_code",
      "difficulty": difficulty.toString().split('.').last,
    };

    return jsonEncode(request);
  }

  static String requestHint(String currentCode) {
    final request = {
      "request_Type": "request_hint",
      "current_code": currentCode,
    };

    return jsonEncode(request);
  }

  static String studentQuestion(String question, String? code) {
    final request = {
      "request_type": "student_question",
      "question": question,
      "code": code ?? "",
    };

    return jsonEncode(request);
  }

  static String explainAnswer(String answer) {
    final request = {"request_type": "explain_answer", "answer": answer};

    return jsonEncode(request);
  }

  static String socraticFeedback(String answer) {
    final request = {"request_type": "socratic_feedback", "answer": answer};

    return jsonEncode(request);
  }

  static String submitCode(String code) {
    final request = {"request_type": "submit_code", "code": code};

    return jsonEncode(request);
  }

  static String mcqAnswer(String answer) {
    final request = {"request_type": "mcq_answer", "answer": answer};

    return jsonEncode(request);
  }

  static String status() {
    final request = {"request_type": "status"};

    return jsonEncode(request);
  }
}
