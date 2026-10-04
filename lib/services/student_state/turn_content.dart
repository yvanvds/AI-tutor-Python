// What the student saw, answered and was told on one graded turn (#228,
// CONDUCTOR_POLICY §8.1): the `turn_content` doc next to the turn's
// `turn_history` doc, with the same id.
//
// `turn_history` says *that* an oefening went wrong and how the rules
// reacted; this says *why*: the question as it was on screen, the answer,
// the feedback, the grader's signals before the scope check and why each
// dropped one did not count, and where the student was. Kept until the end
// of the school year (`ttl`, see `KeepUntil`), then Cosmos removes it.
//
// Deliberately not in it: the full prompts (the instructions are in
// `instructions`) and the model's raw output.

import 'package:ai_tutor_python/services/student_state/turn_record.dart';

/// The question the graded answer was to, as the student saw it. For a
/// follow-up, the follow-up question.
class TurnContentQuestion {
  const TurnContentQuestion({
    required this.text,
    this.code,
    this.options,
    this.correctOption,
    this.questionId,
  });

  /// The question's text (the reply's `<TEXT>`), or the follow-up question.
  final String text;

  /// The code shown with it: the skeleton of a complete-code question, the
  /// code to explain, or the code of a multiple-choice question.
  final String? code;

  /// A multiple-choice question's options, in the order on screen.
  final List<String>? options;

  /// A multiple-choice question's answer key, as option text.
  final String? correctOption;

  /// The question's bank id (#185), as on the turn record.
  final String? questionId;

  Map<String, dynamic> toJson() => {
    'text': text,
    if (code != null && code!.isNotEmpty) 'code': code,
    if (options != null) 'options': options,
    if (correctOption != null) 'correctOption': correctOption,
    if (questionId != null) 'questionId': questionId,
  };
}

/// What the student handed in: code, a picked option, or text.
class TurnContentAnswer {
  const TurnContentAnswer({this.code, this.picked, this.text});

  /// The code submitted from the editor.
  final String? code;

  /// The option picked on a multiple-choice question.
  final String? picked;

  /// An explanation, an answer to a socratic or follow-up question, or text
  /// typed in the chat about a multiple-choice question.
  final String? text;

  Map<String, dynamic> toJson() => {
    if (code != null) 'code': code,
    if (picked != null) 'picked': picked,
    if (text != null) 'text': text,
  };
}

/// One grader signal that did not count, with why: a
/// `SignalDropReason` name (`outOfScope`, `targetOutOfScope`, `unknownLo`,
/// `laterSubgoal`, `outsideActiveRoot`, `incidentalNegative`,
/// `incidentalNeutral`).
class TurnDroppedSignal {
  const TurnDroppedSignal({
    required this.subgoalId,
    required this.loId,
    required this.signal,
    required this.strength,
    required this.reason,
  });

  final String subgoalId;
  final String loId;
  final String signal;
  final String strength;
  final String reason;

  Map<String, dynamic> toJson() => {
    'subgoalId': subgoalId,
    'loId': loId,
    'signal': signal,
    'strength': strength,
    'reason': reason,
  };
}

/// Where the student was when the answer was graded: the active goal and
/// subgoal, the selection and preferences behind them, and how the session
/// began (`startup`, `continueLearningPath`, `workOnGoal`, `restart`).
class TurnContentContext {
  const TurnContentContext({
    this.activeRootId,
    this.activeSubgoalId,
    this.selectedRootId,
    this.selectedChildId,
    this.preferredRootId,
    this.preferredChildId,
    required this.sessionStart,
  });

  final String? activeRootId;
  final String? activeSubgoalId;
  final String? selectedRootId;
  final String? selectedChildId;
  final String? preferredRootId;
  final String? preferredChildId;
  final String sessionStart;

  Map<String, dynamic> toJson() => {
    'activeRootId': activeRootId,
    'activeSubgoalId': activeSubgoalId,
    'selectedRootId': selectedRootId,
    'selectedChildId': selectedChildId,
    'preferredRootId': preferredRootId,
    'preferredChildId': preferredChildId,
    'sessionStart': sessionStart,
  };
}

class TurnContent {
  const TurnContent({
    required this.id,
    required this.turnAt,
    required this.subgoalId,
    required this.questionType,
    required this.isFollowUp,
    required this.question,
    required this.answer,
    required this.feedback,
    required this.rawSignals,
    required this.droppedSignals,
    required this.context,
    required this.hintCount,
    this.clientVersion,
  });

  /// The id of the turn's `turn_history` doc.
  final String id;
  final DateTime turnAt;

  /// As on the turn record: the subgoal of the asked LO.
  final String subgoalId;

  /// The `ChatRequestType` of the question, as on the turn record.
  final String questionType;
  final bool isFollowUp;

  /// `null` when the question is not known — the app was restarted between
  /// question and answer.
  final TurnContentQuestion? question;
  final TurnContentAnswer? answer;

  /// The text the student got back (the grade's `<TEXT>`).
  final String feedback;

  /// The grader's own signals, before the scope check. On a pick graded by
  /// the answer key (#186) the key's signal is what was checked; the turn
  /// record says `gradedByKey`.
  final List<TurnLoSignal> rawSignals;

  /// Every signal that did not count, with why.
  final List<TurnDroppedSignal> droppedSignals;
  final TurnContentContext context;

  /// Hints asked since the question went up (or the last graded answer).
  final int hintCount;
  final String? clientVersion;

  /// The doc as written: [keepUntil] is when it expires, [ttl] the seconds
  /// from this write until then (Cosmos counts from `_ts`).
  Map<String, dynamic> toMap({
    required String uid,
    required DateTime keepUntil,
    required int ttl,
  }) => {
    'id': id,
    'uid': uid,
    'type': 'turn_content',
    'turnAt': turnAt.toUtc().toIso8601String(),
    'subgoalId': subgoalId,
    'questionType': questionType,
    'isFollowUp': isFollowUp,
    'question': question?.toJson(),
    'answer': answer?.toJson(),
    'feedback': feedback,
    'rawSignals': rawSignals.map((s) => s.toJson()).toList(),
    'droppedSignals': droppedSignals.map((s) => s.toJson()).toList(),
    'context': context.toJson(),
    'hintCount': hintCount,
    if (clientVersion != null) 'clientVersion': clientVersion,
    'keepUntil': keepUntil.toUtc().toIso8601String(),
    'ttl': ttl,
  };
}
