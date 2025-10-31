import 'dart:convert';

class QuestionFormatter {
  static String generateExcercise(double progress) {
    final request = {"request_type": "generate_exercise", "progress": progress};

    return jsonEncode(request);
  }

  static String requestHint(String currentCode, double progress) {
    final request = {
      "request_Type": "request_hint",
      "current_code": currentCode,
      "progress": progress,
    };

    return jsonEncode(request);
  }

  static String studentQuestion(
    String question,
    double progress,
    String? code,
  ) {
    final request = {
      "request_type": "student_question",
      "question": question,
      "code": code ?? "",
      "progress": progress,
    };

    return jsonEncode(request);
  }

  static String explainAnswer(String answer, double progress, String? code) {
    final request = {
      "request_type": "explain_answer",
      "answer": answer,
      "progress": progress,
    };

    return jsonEncode(request);
  }

  static String socraticFeedback(String answer, double progress) {
    final request = {
      "request_type": "socratic_feedback",
      "answer": answer,
      "progress": progress,
    };

    return jsonEncode(request);
  }

  static String submitCode(String code, double progress) {
    final request = {
      "request_type": "submit_code",
      "code": code,
      "progress": progress,
    };

    return jsonEncode(request);
  }

  static String mcqAnswer(String answer, double progress) {
    final request = {
      "request_type": "mcq_answer",
      "answer": answer,
      "progress": progress,
    };

    return jsonEncode(request);
  }

  static String status() {
    final request = {"request_type": "status"};

    return jsonEncode(request);
  }
}
