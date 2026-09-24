import 'dart:convert';

import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';

class QuestionFormatter {
  static String _encodeRequest(
    String requestType, {
    QuestionDifficulty? difficulty,
    Map<String, dynamic>? additionalFields,
  }) {
    final request = <String, dynamic>{"request_type": requestType};
    if (difficulty != null) {
      request["difficulty"] = difficulty.toString().split('.').last;
    }
    if (additionalFields != null) {
      request.addAll(additionalFields);
    }
    return jsonEncode(request);
  }

  /// [subgoalId], when given, is written on every entry: the subgoal the
  /// target LOs belong to (LLM_CONTRACT "Answer grading", #102). Grading
  /// payloads pass it so the grader files its signal under the right
  /// subgoal even when the target is a warm-up review LO from an older one.
  static List<Map<String, dynamic>> encodeLOs(
    List<LearningObjective> los, {
    String? subgoalId,
  }) {
    return los
        .map(
          (lo) => {
            'id': lo.id,
            'statement': lo.statement,
            'kind': lo.kind.name,
            if (subgoalId != null) 'subgoalId': subgoalId,
          },
        )
        .toList(growable: false);
  }

  /// Fields of a question-generation request: the LOs to probe, and the
  /// questions asked most recently this session (#184). Generation goes out
  /// without conversation history, so `recent_questions` — one line each,
  /// oldest first, see `RecentQuestions` — is how the model can avoid
  /// asking the same thing again. Both are omitted when empty.
  static Map<String, dynamic> _questionFields({
    required List<LearningObjective> targetLOs,
    required List<String> recentQuestions,
  }) => {
    if (targetLOs.isNotEmpty) 'target_los': encodeLOs(targetLOs),
    if (recentQuestions.isNotEmpty) 'recent_questions': recentQuestions,
  };

  static String socraticQuestion(
    QuestionDifficulty difficulty, {
    List<LearningObjective> targetLOs = const [],
    List<String> recentQuestions = const [],
  }) => _encodeRequest(
    "socratic_question",
    difficulty: difficulty,
    additionalFields: _questionFields(
      targetLOs: targetLOs,
      recentQuestions: recentQuestions,
    ),
  );

  static String mcQuestion(
    QuestionDifficulty difficulty, {
    List<LearningObjective> targetLOs = const [],
    List<String> recentQuestions = const [],
  }) => _encodeRequest(
    "multiple_choice",
    difficulty: difficulty,
    additionalFields: _questionFields(
      targetLOs: targetLOs,
      recentQuestions: recentQuestions,
    ),
  );

  static String explainCodeQuestion(
    QuestionDifficulty difficulty, {
    List<LearningObjective> targetLOs = const [],
    List<String> recentQuestions = const [],
  }) => _encodeRequest(
    "explain_code",
    difficulty: difficulty,
    additionalFields: _questionFields(
      targetLOs: targetLOs,
      recentQuestions: recentQuestions,
    ),
  );

  static String completeCodeQuestion(
    QuestionDifficulty difficulty, {
    List<LearningObjective> targetLOs = const [],
    List<String> recentQuestions = const [],
  }) => _encodeRequest(
    "complete_code",
    difficulty: difficulty,
    additionalFields: _questionFields(
      targetLOs: targetLOs,
      recentQuestions: recentQuestions,
    ),
  );

  static String writeCodeQuestion(
    QuestionDifficulty difficulty, {
    List<LearningObjective> targetLOs = const [],
    List<String> recentQuestions = const [],
  }) => _encodeRequest(
    "write_code",
    difficulty: difficulty,
    additionalFields: _questionFields(
      targetLOs: targetLOs,
      recentQuestions: recentQuestions,
    ),
  );

  static String requestHint(String currentCode) => _encodeRequest(
    "request_hint",
    additionalFields: {"current_code": currentCode},
  );

  static String studentQuestion(String question, String? code) =>
      _encodeRequest(
        "student_question",
        additionalFields: {"question": question, "code": code ?? ""},
      );

  /// A question about the theory page on screen (#132, LLM_CONTRACT
  /// "Content question"): the question plus the page itself — its title and
  /// its body as plain text (`lessonHtmlToText`), so the model answers from
  /// what the student is looking at.
  static String contentQuestion(
    String question, {
    required String contentTitle,
    required String contentText,
  }) => _encodeRequest(
    "content_question",
    additionalFields: {
      "question": question,
      "content_title": contentTitle,
      "content": contentText,
    },
  );

  static String explainAnswer(
    String answer, {
    List<LearningObjective> targetLOs = const [],
    String? targetSubgoalId,
    List<({String subgoalId, LearningObjective lo})> goalScopeLOs = const [],
  }) => _encodeRequest(
    "explain_answer",
    additionalFields: _gradingFields(
      {"answer": answer},
      targetLOs: targetLOs,
      targetSubgoalId: targetSubgoalId,
      goalScopeLOs: goalScopeLOs,
    ),
  );

  static String socraticFeedback(
    String answer, {
    List<LearningObjective> targetLOs = const [],
    String? targetSubgoalId,
    List<({String subgoalId, LearningObjective lo})> goalScopeLOs = const [],
  }) => _encodeRequest(
    "socratic_feedback",
    additionalFields: _gradingFields(
      {"answer": answer},
      targetLOs: targetLOs,
      targetSubgoalId: targetSubgoalId,
      goalScopeLOs: goalScopeLOs,
    ),
  );

  static String submitCode(
    String code, {
    List<LearningObjective> targetLOs = const [],
    String? targetSubgoalId,
    List<({String subgoalId, LearningObjective lo})> goalScopeLOs = const [],
  }) => _encodeRequest(
    "submit_code",
    additionalFields: _gradingFields(
      {"code": code},
      targetLOs: targetLOs,
      targetSubgoalId: targetSubgoalId,
      goalScopeLOs: goalScopeLOs,
    ),
  );

  static String mcqAnswer(
    String answer, {
    List<LearningObjective> targetLOs = const [],
    String? targetSubgoalId,
    List<({String subgoalId, LearningObjective lo})> goalScopeLOs = const [],
  }) => _encodeRequest(
    "mcq_answer",
    additionalFields: _gradingFields(
      {"answer": answer},
      targetLOs: targetLOs,
      targetSubgoalId: targetSubgoalId,
      goalScopeLOs: goalScopeLOs,
    ),
  );

  /// Grading payload for a chained follow-up answer
  /// (CONDUCTOR_POLICY §6 / LLM_CONTRACT "Grading follow-up answers"). The
  /// grader is told the original follow-up question text plus the student's
  /// answer; the conductor caps signal strength to `weak` and treats the
  /// effective difficulty as `medium` regardless of `targetLOs[*].kind`.
  static String followUpAnswer({
    required String followUpQuestion,
    required String studentAnswer,
    String? rationale,
    int chainDepth = 1,
    List<LearningObjective> targetLOs = const [],
    String? targetSubgoalId,
    List<({String subgoalId, LearningObjective lo})> goalScopeLOs = const [],
  }) => _encodeRequest(
    "follow_up_answer",
    additionalFields: _gradingFields(
      {
        "follow_up_question": followUpQuestion,
        "answer": studentAnswer,
        "chain_depth": chainDepth,
        if (rationale != null && rationale.isNotEmpty)
          "follow_up_rationale": rationale,
      },
      targetLOs: targetLOs,
      targetSubgoalId: targetSubgoalId,
      goalScopeLOs: goalScopeLOs,
    ),
  );

  static String status() => _encodeRequest("status");

  static Map<String, dynamic> _gradingFields(
    Map<String, dynamic> base, {
    required List<LearningObjective> targetLOs,
    required List<({String subgoalId, LearningObjective lo})> goalScopeLOs,
    String? targetSubgoalId,
  }) {
    if (targetLOs.isNotEmpty) {
      base['target_los'] = encodeLOs(targetLOs, subgoalId: targetSubgoalId);
    }
    if (goalScopeLOs.isNotEmpty) {
      base['goal_scope_los'] = goalScopeLOs
          .map(
            (e) => {
              'subgoalId': e.subgoalId,
              'id': e.lo.id,
              'statement': e.lo.statement,
              'kind': e.lo.kind.name,
            },
          )
          .toList(growable: false);
    }
    return base;
  }
}
