import 'dart:math';

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:ai_tutor_python/services/tutor/responses/answer.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/code_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/complete_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/error_summary.dart';
import 'package:ai_tutor_python/services/tutor/responses/explain_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/explain_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/grader_payload.dart';
import 'package:ai_tutor_python/services/tutor/responses/hint.dart';
import 'package:ai_tutor_python/services/tutor/responses/mcq_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_question.dart';
import 'package:ai_tutor_python/services/tutor/responses/status_summary.dart';
import 'package:ai_tutor_python/services/tutor/responses/write_code.dart';

/// Outcome of integrating a graded answer into the conductor (CONDUCTOR_POLICY
/// §6.5 post-answer flow). Distinct from the `bool` of "did the subgoal
/// advance" because there's now a third path — the conductor presented a
/// chained follow-up and is waiting on the next student answer.
enum IntegrateOutcome {
  /// The subgoal mastered and we advanced to the next one. The handler
  /// should not also call `requestExercise`.
  advanced,

  /// A follow-up question was presented in chat. The handler should NOT
  /// call `requestExercise`; the next student message will route to a
  /// follow-up grading call.
  followUpPresented,

  /// Belief / calibration updated; nothing presented. The handler should
  /// continue to `requestExercise` as usual.
  continuing,
}

class TutorContext {
  TutorContext({
    required this.conductor,
    required this.startNewCode,
    required this.addTutorMessage,
    required this.addSystemNotice,
    required this.writeCodeTemplate,
    required this.setExerciseType,
    required this.setFollowUp,
    required this.requestExercise,
    required this.maybeRetry,
    required this.playQuestion,
    required this.setActiveMcq,
    required this.applyMcqFeedback,
    required this.updateReportForGoal,
    required this.updateReportForCurrentGoal,
    required this.recordParsedResponse,
    required this.integrateGradedAnswer,
    required this.getCurrentExerciseType,
    this.statusReportGoalIdOverride,
  });

  final Conductor conductor;
  final void Function(String code) startNewCode;
  final void Function(String message) addTutorMessage;

  /// System pill, localized by the chat widget (#23).
  final void Function(ChatNotice notice) addSystemNotice;

  /// Editor contents a write-code exercise starts with (a comment in the
  /// UI language).
  final String Function() writeCodeTemplate;
  final void Function(String type) setExerciseType;
  final void Function({String? message, String? code}) setFollowUp;
  final Future<void> Function() requestExercise;
  final Future<void> Function() maybeRetry;
  final void Function() playQuestion;

  /// Open a fresh MCQ in the practice view.
  final void Function({
    required String prompt,
    required String code,
    required List<String> options,
  }) setActiveMcq;

  /// Land tutor feedback onto the in-flight MCQ so the practice view can
  /// reveal correct/wrong styling and the "Volgende" button.
  final void Function({
    required String prompt,
    required AnswerQuality quality,
  }) applyMcqFeedback;

  final Future<void> Function(String goalId, String report) updateReportForGoal;
  final Future<void> Function(String report) updateReportForCurrentGoal;
  final void Function(ChatResponse response) recordParsedResponse;

  /// Builds the `GradedAnswer`, runs validation/fallback, calls the
  /// conductor's `integrateAnswer`, optionally presents a follow-up, and
  /// returns the outcome. TutorService owns the implementation since it has
  /// access to the in-flight `QuestionPlan` and current goal scope.
  final Future<IntegrateOutcome> Function({
    required AnswerQuality overallQuality,
    required List<LoSignal> loSignals,
    required FollowUp? followUp,
  }) integrateGradedAnswer;

  /// Goal id the StatusSummaryHandler should write against. Set by
  /// TutorService when firing a post-mastery status query so the report
  /// lands on the just-mastered subgoal rather than the now-current one.
  final String? statusReportGoalIdOverride;

  /// Current exercise type as tracked by TutorService (e.g. `complete_code`,
  /// `write_code`, `multiple_choice`). Used by AnswerHandler to detect when a
  /// chat reply lands while a code-editor exercise is still open, so the
  /// student can be reminded to submit through the editor.
  final String Function() getCurrentExerciseType;
}

abstract class ResponseHandler<R extends ChatResponse> {
  const ResponseHandler();
  Future<void> handle(R response, TutorContext ctx);
}

class CompleteCodeHandler extends ResponseHandler<CompleteCode> {
  const CompleteCodeHandler();
  @override
  Future<void> handle(CompleteCode r, TutorContext ctx) async {
    ctx.setExerciseType(r.type);
    ctx.startNewCode(r.code);
    ctx.addTutorMessage(r.prompt);
    ctx.playQuestion();
  }
}

class ExplainCodeHandler extends ResponseHandler<ExplainCode> {
  const ExplainCodeHandler();
  @override
  Future<void> handle(ExplainCode r, TutorContext ctx) async {
    ctx.setExerciseType(r.type);
    ctx.startNewCode(r.code);
    ctx.addTutorMessage(r.prompt);
    ctx.playQuestion();
  }
}

class WriteCodeHandler extends ResponseHandler<WriteCode> {
  const WriteCodeHandler();
  @override
  Future<void> handle(WriteCode r, TutorContext ctx) async {
    ctx.setExerciseType(r.type);
    ctx.startNewCode('${ctx.writeCodeTemplate()}\n');
    ctx.addTutorMessage(r.prompt);
    ctx.playQuestion();
  }
}

class SocraticQuestionHandler extends ResponseHandler<SocraticQuestion> {
  const SocraticQuestionHandler();
  @override
  Future<void> handle(SocraticQuestion r, TutorContext ctx) async {
    ctx.setExerciseType(r.type);
    ctx.startNewCode('');
    ctx.addTutorMessage(r.prompt);
    ctx.playQuestion();
  }
}

class MultipleChoiceHandler extends ResponseHandler<MultipleChoice> {
  const MultipleChoiceHandler();
  @override
  Future<void> handle(MultipleChoice r, TutorContext ctx) async {
    ctx.setExerciseType(r.type);
    // Shuffle to defeat the LLM's positional bias (it tends to put the
    // correct answer in slot A). Grader sees the picked text, not the
    // position, so the round-trip is unaffected.
    final shuffled = [...r.options]..shuffle(Random());
    ctx.setActiveMcq(prompt: r.prompt, code: r.code, options: shuffled);
    ctx.playQuestion();
  }
}

class AnswerHandler extends ResponseHandler<Answer> {
  const AnswerHandler();
  @override
  Future<void> handle(Answer r, TutorContext ctx) async {
    if (r.prompt.isNotEmpty) {
      ctx.addTutorMessage(r.prompt);
      ctx.playQuestion();
    }
    final type = ctx.getCurrentExerciseType();
    if (type == 'complete_code' || type == 'write_code') {
      ctx.addSystemNotice(const ChatNotice(ChatNoticeKind.submitViaEditor));
    }
  }
}

class HintHandler extends ResponseHandler<Hint> {
  const HintHandler();
  @override
  Future<void> handle(Hint r, TutorContext ctx) async {
    ctx.addTutorMessage(r.prompt);
    ctx.playQuestion();
    ctx.conductor.hintProvided();
  }
}

class CodeFeedbackHandler extends ResponseHandler<CodeFeedback> {
  const CodeFeedbackHandler();
  @override
  Future<void> handle(CodeFeedback r, TutorContext ctx) async {
    if (r.prompt.isNotEmpty) {
      ctx.addTutorMessage(r.prompt);
      ctx.playQuestion();
    }
    final outcome = await ctx.integrateGradedAnswer(
      overallQuality: r.quality,
      loSignals: r.loSignals,
      followUp: r.followUp,
    );
    if (outcome != IntegrateOutcome.continuing) return;
    await ctx.requestExercise();
  }
}

class McqFeedbackHandler extends ResponseHandler<McqFeedback> {
  const McqFeedbackHandler();
  @override
  Future<void> handle(McqFeedback r, TutorContext ctx) async {
    ctx.applyMcqFeedback(prompt: r.prompt, quality: r.quality);
    ctx.playQuestion();
    await ctx.integrateGradedAnswer(
      overallQuality: r.quality,
      loSignals: r.loSignals,
      followUp: r.followUp,
    );
    // Advance is deferred until the student clicks "Volgende" inside the
    // MCQ render — see TutorService.advanceFromMcq. A follow-up presented
    // here will simply replace that flow on the next student turn.
  }
}

class ExplainFeedbackHandler extends ResponseHandler<ExplainFeedback> {
  const ExplainFeedbackHandler();
  @override
  Future<void> handle(ExplainFeedback r, TutorContext ctx) async {
    if (r.prompt.isNotEmpty) {
      ctx.addTutorMessage(r.prompt);
      ctx.playQuestion();
    }
    final outcome = await ctx.integrateGradedAnswer(
      overallQuality: r.quality,
      loSignals: r.loSignals,
      followUp: r.followUp,
    );
    if (outcome != IntegrateOutcome.continuing) return;
    await ctx.requestExercise();
  }
}

class SocraticFeedbackHandler extends ResponseHandler<SocraticFeedback> {
  const SocraticFeedbackHandler();
  @override
  Future<void> handle(SocraticFeedback r, TutorContext ctx) async {
    if (r.prompt.isNotEmpty) {
      ctx.addTutorMessage(r.prompt);
      ctx.playQuestion();
    }
    final outcome = await ctx.integrateGradedAnswer(
      overallQuality: r.quality,
      loSignals: r.loSignals,
      followUp: r.followUp,
    );
    if (outcome != IntegrateOutcome.continuing) return;
    await ctx.requestExercise();
  }
}

class StatusSummaryHandler extends ResponseHandler<StatusSummary> {
  const StatusSummaryHandler();
  @override
  Future<void> handle(StatusSummary r, TutorContext ctx) async {
    final override = ctx.statusReportGoalIdOverride;
    if (override != null) {
      await ctx.updateReportForGoal(override, r.prompt);
      return;
    }
    await ctx.updateReportForCurrentGoal(r.prompt);
  }
}

class ErrorResponseHandler extends ResponseHandler<ErrorResponse> {
  const ErrorResponseHandler();
  @override
  Future<void> handle(ErrorResponse r, TutorContext ctx) async {
    ctx.addSystemNotice(r.chatNotice);
    await ctx.maybeRetry();
  }
}

class _DispatchEntry {
  const _DispatchEntry(this.matches, this.handle);
  final bool Function(ChatResponse parsed) matches;
  final Future<void> Function(ChatResponse parsed, TutorContext ctx) handle;
}

_DispatchEntry _entry<R extends ChatResponse>(ResponseHandler<R> handler) {
  return _DispatchEntry(
    (parsed) => parsed is R,
    (parsed, ctx) => handler.handle(parsed as R, ctx),
  );
}

final List<_DispatchEntry> _dispatchTable = [
  _entry(const CompleteCodeHandler()),
  _entry(const ExplainCodeHandler()),
  _entry(const WriteCodeHandler()),
  _entry(const SocraticQuestionHandler()),
  _entry(const MultipleChoiceHandler()),
  _entry(const AnswerHandler()),
  _entry(const HintHandler()),
  _entry(const CodeFeedbackHandler()),
  _entry(const McqFeedbackHandler()),
  _entry(const ExplainFeedbackHandler()),
  _entry(const SocraticFeedbackHandler()),
  _entry(const StatusSummaryHandler()),
  _entry(const ErrorResponseHandler()),
];

/// Dispatches a parsed [ChatResponse] to the matching handler.
/// Returns false when the response type has no handler.
Future<bool> dispatchResponse(ChatResponse parsed, TutorContext ctx) async {
  ctx.recordParsedResponse(parsed);
  for (final entry in _dispatchTable) {
    if (entry.matches(parsed)) {
      await entry.handle(parsed, ctx);
      return true;
    }
  }
  return false;
}
