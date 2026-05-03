import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:ai_tutor_python/services/tutor/responses/answer.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/code_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/complete_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/error_summary.dart';
import 'package:ai_tutor_python/services/tutor/responses/explain_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/explain_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/guiding_exercise.dart';
import 'package:ai_tutor_python/services/tutor/responses/guiding_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/hint.dart';
import 'package:ai_tutor_python/services/tutor/responses/mcq_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_question.dart';
import 'package:ai_tutor_python/services/tutor/responses/status_summary.dart';
import 'package:ai_tutor_python/services/tutor/responses/write_code.dart';

class TutorContext {
  TutorContext({
    required this.conductor,
    required this.startNewCode,
    required this.addTutorMessage,
    required this.addSystemMessage,
    required this.setExerciseType,
    required this.setFollowUp,
    required this.requestExercise,
    required this.maybeRetry,
    required this.playQuestion,
    required this.addMcqOptions,
    required this.updateReportForGoal,
    required this.updateReportForCurrentGoal,
    required this.recordParsedResponse,
    this.statusReportGoalIdOverride,
  });

  final Conductor conductor;
  final void Function(String code) startNewCode;
  final void Function(String message) addTutorMessage;
  final void Function(String message) addSystemMessage;
  final void Function(String type) setExerciseType;
  final void Function({String? message, String? code}) setFollowUp;
  final Future<void> Function() requestExercise;
  final Future<void> Function() maybeRetry;
  final void Function() playQuestion;
  final void Function(List<String> options) addMcqOptions;
  final Future<void> Function(String goalId, String report) updateReportForGoal;
  final Future<void> Function(String report) updateReportForCurrentGoal;
  final void Function(ChatResponse response) recordParsedResponse;

  /// Goal id the StatusSummaryHandler should write against. Set by
  /// TutorService when firing a post-mastery status query so the report
  /// lands on the just-mastered subgoal rather than the now-current one.
  final String? statusReportGoalIdOverride;
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
    ctx.startNewCode('# Schrijf hier je code\n');
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
    ctx.startNewCode(r.code);
    ctx.addTutorMessage(r.prompt);
    ctx.addMcqOptions(r.options);
    ctx.playQuestion();
  }
}

class GuidingExerciseHandler extends ResponseHandler<GuidingExercise> {
  const GuidingExerciseHandler();
  @override
  Future<void> handle(GuidingExercise r, TutorContext ctx) async {
    ctx.setExerciseType(r.type);
    ctx.startNewCode(r.code);
    ctx.addTutorMessage(r.prompt);
    ctx.playQuestion();
  }
}

class GuidingFeedbackHandler extends ResponseHandler<GuidingFeedback> {
  const GuidingFeedbackHandler();
  @override
  Future<void> handle(GuidingFeedback r, TutorContext ctx) async {
    if (r.prompt.isNotEmpty) {
      ctx.addTutorMessage(r.prompt);
      ctx.playQuestion();
    }

    final guidingComplete = await ctx.conductor.guidingIsComplete(
      r.understanding,
    );
    if (guidingComplete) {
      await ctx.requestExercise();
      return;
    }

    ctx.setFollowUp(
      message: r.followUp.isNotEmpty ? r.followUp : null,
      code: r.code.isNotEmpty ? r.code : null,
    );
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

    final suggestionAllowed = await ctx.conductor.updateProgress(r.quality);
    await ctx.conductor.recordConceptAttributions(r.suspectedConcepts);
    if (r.suggestion.isNotEmpty && suggestionAllowed) {
      ctx.setFollowUp(message: r.suggestion);
    } else {
      await ctx.requestExercise();
    }
  }
}

class McqFeedbackHandler extends ResponseHandler<McqFeedback> {
  const McqFeedbackHandler();
  @override
  Future<void> handle(McqFeedback r, TutorContext ctx) async {
    ctx.addTutorMessage(r.prompt);
    ctx.playQuestion();
    await ctx.conductor.updateProgress(r.quality);
    await ctx.conductor.recordConceptAttributions(r.suspectedConcepts);
    await ctx.requestExercise();
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

    final suggestionAllowed = await ctx.conductor.updateProgress(r.quality);
    await ctx.conductor.recordConceptAttributions(r.suspectedConcepts);
    if (r.followUp != null && suggestionAllowed) {
      ctx.setFollowUp(message: r.followUp);
    } else {
      await ctx.requestExercise();
    }
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

    final suggestionAllowed = await ctx.conductor.updateProgress(r.quality);
    await ctx.conductor.recordConceptAttributions(r.suspectedConcepts);
    if (r.followUp != null && suggestionAllowed) {
      ctx.setFollowUp(message: r.followUp);
    } else {
      await ctx.requestExercise();
    }
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
    ctx.addSystemMessage(r.message);
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
  _entry(const GuidingExerciseHandler()),
  _entry(const GuidingFeedbackHandler()),
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
