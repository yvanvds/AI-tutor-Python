import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/data/account/account_providers.dart';
import 'package:ai_tutor_python/data/code/code_provider.dart';
import 'package:ai_tutor_python/data/goal/goal.dart';
import 'package:ai_tutor_python/data/goal/goal_providers.dart';
import 'package:ai_tutor_python/data/progress/progress.dart';
import 'package:ai_tutor_python/data/progress/progress_providers.dart';
import 'package:ai_tutor_python/data/status_report/report_providers.dart';
import 'package:ai_tutor_python/data/status_report/status_report.dart';
import 'package:ai_tutor_python/services/chat_service.dart';
import 'package:ai_tutor_python/services/tutor/instruction_generator.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/question_formatter.dart';
import 'package:ai_tutor_python/services/tutor/responses/ai_response_parser.dart';
import 'package:ai_tutor_python/services/tutor/responses/answer.dart';
import 'package:ai_tutor_python/services/tutor/responses/code_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/error_summary.dart';
import 'package:ai_tutor_python/services/tutor/responses/exercise.dart';
import 'package:ai_tutor_python/services/tutor/responses/explain_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/hint.dart';
import 'package:ai_tutor_python/services/tutor/responses/mcq_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/status_summary.dart';
import 'package:collection/collection.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final tutorServiceProvider = Provider<TutorService>((ref) {
  final service = TutorService(ref: ref);
  ref.onDispose(service.dispose);
  return service;
});

class TutorService {
  final Ref ref;
  TutorService({required this.ref});

  Goal? _currentRootGoal;
  Goal? _currentChildGoal;

  InstructionGenerator get _instructionGenerator =>
      InstructionGenerator(ref: ref);

  final OpenaiConnector _connector = OpenaiConnector();

  String _currentExerciseType = '';

  // ---- Public API -----------------------------------------------------------

  Future<void> initializeSession() async {
    final chat = ref.read(chatServiceProvider);

    chat.clear();
    // Resolve name & target using stable snapshots
    final userName = await _getUserFirstName();
    final hasTarget = await _setTargetGoal(); // selects providers inside

    if (!hasTarget) {
      chat.addSystemMessage(
        "There are no goals available to work on. Have fun!",
      );
      return;
    }

    chat.addSystemMessage(
      "Hello $userName, your current goal is '${_currentChildGoal?.title}' (under root '${_currentRootGoal?.title}'). Let's get started!",
    );

    queryTutor(type: ChatRequestType.generateExercise, newSession: true);
  }

  Future<void> queryTutor({
    required ChatRequestType type,
    String? code,
    String? prompt,
    bool newSession = false,
  }) async {
    final instructions = await _instructionGenerator.generateInstructions(
      type,
      _currentRootGoal!,
      _currentChildGoal!,
    );

    String input = "";
    final progress = await _getCurrentProgress();

    switch (type) {
      case ChatRequestType.generateExercise:
        input = QuestionFormatter.generateExcercise(progress);
        break;

      case ChatRequestType.submitCode:
        if (code == null) return;
        input = QuestionFormatter.submitCode(code, progress);
        break;

      case ChatRequestType.mcqAnswer:
        if (prompt == null) return;
        input = QuestionFormatter.mcqAnswer(prompt, progress);
        break;

      case ChatRequestType.requestHint:
        if (code == null) return;
        input = QuestionFormatter.requestHint(code, progress);
        break;

      case ChatRequestType.studentQuestion:
        if (prompt == null) return;
        input = QuestionFormatter.studentQuestion(prompt, progress, code);
        break;

      case ChatRequestType.explainAnswer:
        if (prompt == null) return;
        input = QuestionFormatter.explainAnswer(prompt, progress, code);
        break;

      case ChatRequestType.socraticFeedback:
        if (prompt == null) return;
        input = QuestionFormatter.socraticFeedback(prompt, progress);
        break;

      case ChatRequestType.status:
        input = QuestionFormatter.status();
        break;
    }

    final result = await _connector.sendRequest(
      input: input,
      instructions: instructions,
      newSession: newSession,
    );
    _handleResponse(result);
  }

  void handleStudentMessage(String message) {
    if (_currentExerciseType == 'multiple_choice') {
      queryTutor(type: ChatRequestType.mcqAnswer, prompt: message);
    } else if (_currentExerciseType == 'socratic_question') {
      queryTutor(type: ChatRequestType.socraticFeedback, prompt: message);
    } else if (_currentExerciseType == 'explain_code') {
      queryTutor(type: ChatRequestType.explainAnswer, prompt: message);
    } else {
      queryTutor(type: ChatRequestType.studentQuestion, prompt: message);
    }
  }

  void dispose() {}

  // ---- Private helpers ------------------------------------------------------

  void _handleResponse(dynamic response) async {
    final parsed = AIResponseParser.parse(
      response,
    ); // returns Exercise | Answer | ...

    final chat = ref.read(chatServiceProvider);

    if (parsed is Exercise) {
      //
      // The AI has sent a new Exercise
      //
      Exercise exercise = parsed;
      // remember the current exercise type, so that
      // we know what to do when the user asks a question.
      _currentExerciseType = exercise.exerciseType;

      if (exercise.code != null) {
        // Update code provider
        ref.read(codeProvider.notifier).state = exercise.code!;
      }

      if (exercise.prompt.isNotEmpty) {
        chat.addTutorMessage(exercise.prompt);
      }
    } else if (parsed is Answer) {
      //
      // The AI answered a generic question
      //
      Answer answer = parsed;
      if (answer.answer.isNotEmpty) {
        chat.addTutorMessage(answer.answer);
      }
      await _evaluateProgress(progress: answer.progress);
    } else if (parsed is Hint) {
      //
      // The AI has sent a Hint
      //
      Hint hint = parsed;
      chat.addTutorMessage(hint.hint);

      await _evaluateProgress(progress: hint.progress);
    } else if (parsed is CodeFeedback) {
      //
      // The AI gives feedback on code
      //
      CodeFeedback feedback = parsed;
      if (feedback.summary.isNotEmpty) chat.addTutorMessage(feedback.summary);
      if (feedback.suggestion.isNotEmpty) {
        chat.addTutorMessage(feedback.suggestion);
      }

      await _evaluateProgress(
        progress: feedback.progress,
        moveToNextQuestion: feedback.correct,
      );
    } else if (parsed is McqFeedback) {
      //
      // The AI gives feedback on MCQ answer
      //
      McqFeedback feedback = parsed;
      chat.addTutorMessage(feedback.explanation);

      if (feedback.correct) {
        // TODO: hide MCQ panel
      }
      await _evaluateProgress(
        progress: feedback.progress,
        moveToNextQuestion: feedback.correct,
      );
    } else if (parsed is ExplainFeedback) {
      //
      // The AI gives feedback on explanation
      //
      ExplainFeedback explain = parsed;
      if (explain.feedback.isNotEmpty) {
        chat.addTutorMessage(explain.feedback);
      }

      if (explain.followUp != null && explain.followUp!.isNotEmpty) {
        chat.addTutorMessage(explain.followUp!);
      } else {
        // only ask a new question if there is no follow up
        if (explain.correct) {
          queryTutor(type: ChatRequestType.generateExercise);
        }
      }
      _evaluateProgress(
        progress: explain.progress,
        moveToNextQuestion: explain.correct && explain.followUp != null,
      );
    } else if (parsed is SocraticFeedback) {
      //
      // The AI gives feedback on an answer to a socratic question
      //
      SocraticFeedback feedback = parsed;
      if (feedback.feedback.isNotEmpty) {
        chat.addTutorMessage(feedback.feedback);
      }

      if (feedback.followUp != null && feedback.followUp!.isNotEmpty) {
        chat.addTutorMessage(feedback.followUp!);
      } else {
        // only ask a new question if there is no follow up
        if (feedback.correct) {
          queryTutor(type: ChatRequestType.generateExercise);
        }
      }

      _evaluateProgress(
        progress: feedback.progress,
        moveToNextQuestion: feedback.correct && feedback.followUp != null,
      );
    } else if (parsed is StatusSummary) {
      //
      // AI gives a status report when a goal is reached
      //
      StatusSummary status = parsed;
      await _updateReport(status.summary);
    } else if (parsed is ErrorResponse) {
      ErrorResponse error = parsed;
      chat.addSystemMessage(error.toJson().toString());
    } else {
      if (parsed is String) {
        chat.addTutorMessage(parsed);
      } else {
        chat.addTutorMessage('Received unknown response from tutor.');
      }
    }
  }

  Future<void> _evaluateProgress({
    required double progress,
    bool moveToNextQuestion = false,
  }) async {
    final currentProgress = await _getCurrentProgress();
    final newProgress = currentProgress + progress;
    await _updateProgress(newProgress);

    if (moveToNextQuestion) {
      if (newProgress >= 1.0) {
        // request a status report
        await queryTutor(type: ChatRequestType.status);

        // move to the next goal
        final hasTarget = await _setTargetGoal(); // selects providers inside

        if (!hasTarget) {
          final chat = ref.read(chatServiceProvider);
          chat.addSystemMessage(
            "There are no more goals available to work on. Have fun!",
          );
          return;
        }

        // goal has changed, so request new session when starting an exercise
        await queryTutor(
          type: ChatRequestType.generateExercise,
          newSession: true,
        );
      } else {
        // next question, but not a new goal
        await queryTutor(type: ChatRequestType.generateExercise);
      }
    }
  }

  /// Computes and selects the next target goal/subgoal.
  /// Returns true if a selection was made, false otherwise.
  Future<bool> _setTargetGoal() async {
    // Clear previous selection
    ref.read(selectedRootGoalProviderNotifier.notifier).select(null);
    ref.read(selectedChildGoalProviderNotifier.notifier).select(null);

    // Take stable snapshots
    final roots = await ref.read(rootGoalsProviderFuture.future); // List<Goal>
    final progressList = await ref.read(
      progressListProviderFuture.future,
    ); // List<Progress>

    double progressFor(Goal g) {
      final p = progressList.firstWhereOrNull((x) => x.goalID == g.id);
      return p?.progress ?? 0.0;
    }

    for (final root in roots) {
      if (progressFor(root) < 1.0) {
        // Load children for this root on demand (family provider)
        final subgoals = await ref.read(
          childGoalsByParentProviderFuture(root.id).future,
        );

        // Pick first incomplete subgoal (if any)
        final targetChild = subgoals.firstWhereOrNull(
          (g) => progressFor(g) < 1.0,
        );

        if (targetChild != null) {
          ref.read(selectedRootGoalProviderNotifier.notifier).select(root.id);
          ref
              .read(selectedChildGoalProviderNotifier.notifier)
              .select(targetChild.id);
          _currentRootGoal = root;
          _currentChildGoal = targetChild;
          return true;
        }
        // else: all children complete -> try next root
      }
    }

    // Nothing to select
    return false;
  }

  Future<String> _getUserFirstName() async {
    final acc = await ref.read(myAccountProviderFuture.future);
    return acc?.firstName ?? 'Student';
  }

  Future<double> _getCurrentProgress() async {
    final progress = await ref.read(
      progressByGoalProviderFuture(_currentChildGoal?.id ?? '').future,
    );

    if (progress == null) {
      return 0.0;
    } else {
      return progress.progress;
    }
  }

  Future<void> _updateProgress(double newProgress) async {
    if (_currentChildGoal == null) return;

    // 1) Upsert child
    await ref.read(
      upsertProgressProviderFuture(
        Progress(goalID: _currentChildGoal!.id, progress: newProgress),
      ).future,
    );

    if (_currentRootGoal == null) return;

    // 2) Read child goals under the current root (provider names are examples)
    final children = await ref.read(
      childGoalsByParentProviderFuture(_currentRootGoal!.id).future,
    );

    // 3) Sum each child’s progress (missing -> 0.0)
    double sum = 0.0;
    for (final g in children) {
      final p = await ref.read(
        progressByGoalProviderFuture(g.id).future,
      ); // Progress?
      sum += (p?.progress ?? 0.0);
    }
    final rootAvg = sum / children.length;

    // 4) Upsert root
    await ref.read(
      upsertProgressProviderFuture(
        Progress(goalID: _currentRootGoal!.id, progress: rootAvg),
      ).future,
    );
  }

  Future<void> _updateReport(String newReport) async {
    if (_currentChildGoal == null) return;

    // 1) Upsert child
    await ref.read(
      upsertStatusReportProviderFuture(
        StatusReport(goalID: _currentChildGoal!.id, statusReport: newReport),
      ).future,
    );
  }
}
