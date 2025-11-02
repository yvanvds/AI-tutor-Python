import 'dart:convert';

import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/data/ai/ai_response_provider.dart';
import 'package:ai_tutor_python/data/code/code_provider.dart';
import 'package:ai_tutor_python/data/status_report/report_providers.dart';
import 'package:ai_tutor_python/data/status_report/status_report.dart';
import 'package:ai_tutor_python/services/chat_service.dart';
import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:ai_tutor_python/services/tutor/instruction_generator.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/question_formatter.dart';
import 'package:ai_tutor_python/services/tutor/responses/ai_response_parser.dart';
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
import 'package:hooks_riverpod/hooks_riverpod.dart';

class TutorService {
  final Ref ref;
  TutorService({required this.ref}) {
    _connector = OpenaiConnector(ref: ref);
    _conductor = Conductor(ref: ref);
  }
  bool _initialized = false;

  InstructionGenerator get _instructionGenerator =>
      InstructionGenerator(ref: ref);

  late final OpenaiConnector _connector;
  late final Conductor _conductor;

  String _currentExerciseType = '';

  // ---- Public API -----------------------------------------------------------

  Future<void> initializeSession() async {
    if (_initialized) return;
    _initialized = true;
    final chat = ref.read(chatServiceProvider);

    chat.clear();

    await _conductor.initialize();

    final newQuestion = _conductor.getNextQuestion();

    if (newQuestion.$1 == ChatRequestType.noResult) {
      chat.addSystemMessage(
        "There are no goals available to work on. Have fun!",
      );
      return;
    }

    //queryTutor(type: newQuestion.$1, difficulty: newQuestion.$2, newSession: true);
  }

  Future<void> queryTutor({
    required ChatRequestType type,
    QuestionDifficulty? difficulty,
    String? code,
    String? prompt,
  }) async {
    final working = ref.read(tutorWorkingProvider.notifier);
    if (working.state) return;
    working.state = true;

    final instructions = await _instructionGenerator.generateInstructions(
      type,
      _conductor.currentRootGoal!,
      _conductor.currentChildGoal!,
    );

    String input = "";
    PreviousInputs includeHistory = PreviousInputs.includeSession;

    switch (type) {
      case ChatRequestType.socraticQuestion:
        input = QuestionFormatter.socraticQuestion(difficulty!);
        includeHistory = PreviousInputs.newSession;
        break;

      case ChatRequestType.mcQuestion:
        input = QuestionFormatter.mcQuestion(difficulty!);
        includeHistory = PreviousInputs.newSession;
        break;

      case ChatRequestType.explainCodeQuestion:
        input = QuestionFormatter.explainCodeQuestion(difficulty!);
        includeHistory = PreviousInputs.newSession;
        break;

      case ChatRequestType.completeCodeQuestion:
        input = QuestionFormatter.completeCodeQuestion(difficulty!);
        includeHistory = PreviousInputs.newSession;
        break;

      case ChatRequestType.writeCodeQuestion:
        input = QuestionFormatter.writeCodeQuestion(difficulty!);
        includeHistory = PreviousInputs.newSession;
        break;

      case ChatRequestType.submitCode:
        if (code == null) return;
        input = QuestionFormatter.submitCode(code);
        break;

      case ChatRequestType.mcqAnswer:
        if (prompt == null) return;
        input = QuestionFormatter.mcqAnswer(prompt);
        break;

      case ChatRequestType.requestHint:
        if (code == null) return;
        input = QuestionFormatter.requestHint(code);
        break;

      case ChatRequestType.studentQuestion:
        if (prompt == null) return;
        input = QuestionFormatter.studentQuestion(prompt, code);
        break;

      case ChatRequestType.explainAnswer:
        if (prompt == null) return;
        input = QuestionFormatter.explainAnswer(prompt);
        break;

      case ChatRequestType.socraticFeedback:
        if (prompt == null) return;
        input = QuestionFormatter.socraticFeedback(prompt);
        break;

      case ChatRequestType.status:
        input = QuestionFormatter.status();
        includeHistory = PreviousInputs.includeAll;
        break;

      case ChatRequestType.noResult:
        return;
    }

    dynamic result;
    try {
      result = await _connector.sendRequest(
        input: input,
        instructions: instructions,
        inputs: includeHistory,
      );
    } finally {
      working.state = false;
    }
    if (result != null) {
      _handleResponse(result);
    }
  }

  Future<void> handleStudentMessage(String message) async {
    if (_currentExerciseType == 'multiple_choice') {
      await queryTutor(type: ChatRequestType.mcqAnswer, prompt: message);
    } else if (_currentExerciseType == 'socratic_question') {
      await queryTutor(type: ChatRequestType.socraticFeedback, prompt: message);
    } else if (_currentExerciseType == 'explain_code') {
      await queryTutor(type: ChatRequestType.explainAnswer, prompt: message);
    } else {
      await queryTutor(type: ChatRequestType.studentQuestion, prompt: message);
    }
  }

  Future<void> requestHint(String? code) async {
    await queryTutor(type: ChatRequestType.requestHint, code: code);
  }

  Future<void> submitCode(String code) async {
    //if (_currentExerciseType == 'complete_code' ||
    //    _currentExerciseType == 'write_code') {
    await queryTutor(type: ChatRequestType.submitCode, code: code);
    //}
  }

  Future<void> requestExercise() async {
    final newQuestion = _conductor.getNextQuestion();

    if (newQuestion.$1 == ChatRequestType.noResult) {
      final chat = ref.read(chatServiceProvider);
      chat.addSystemMessage(
        "There are no goals available to work on. Have fun!",
      );
      return;
    }

    await queryTutor(type: newQuestion.$1, difficulty: newQuestion.$2);
  }

  void dispose() {}

  // ---- Private helpers ------------------------------------------------------

  void _handleResponse(dynamic response) async {
    final parsed = AIResponseParser.parse(
      response,
    ); // returns Exercise | Answer | ...

    assert(() {
      print("We got a response: ${parsed.type}");
      print(const JsonEncoder.withIndent('  ').convert(parsed.toJson()));
      return true;
    }());
    _connector.addResponse(parsed);

    final chat = ref.read(chatServiceProvider);

    if (parsed is CompleteCode) {
      //
      // The AI has sent Code to Complete
      //
      CompleteCode exercise = parsed;

      // Update code provider
      ref.read(codeProvider.notifier).state = exercise.code;
      chat.addTutorMessage(exercise.prompt);
    } else if (parsed is ExplainCode) {
      //
      // The AI has sent Code to Explain
      //
      ExplainCode exercise = parsed;
      _currentExerciseType = exercise.type;
      ref.read(codeProvider.notifier).state = exercise.code;
      chat.addTutorMessage(exercise.prompt);
    } else if (parsed is WriteCode) {
      //
      // The AI has sent instructions to write code
      //
      WriteCode exercise = parsed;
      _currentExerciseType = exercise.type;
      ref.read(codeProvider.notifier).state =
          '# Start writing your code here\n';
      chat.addTutorMessage(exercise.prompt);
    } else if (parsed is SocraticQuestion) {
      //
      // The AI has sent a socratic question
      //
      SocraticQuestion exercise = parsed;
      _currentExerciseType = exercise.type;
      ref.read(codeProvider.notifier).state = '';
      chat.addTutorMessage(exercise.prompt);
    } else if (parsed is MultipleChoice) {
      //
      // the AI has sent a multiple choice question
      //
      MultipleChoice exercise = parsed;
      _currentExerciseType = exercise.type;
      ref.read(codeProvider.notifier).state = exercise.code;
      chat.addTutorMessage(exercise.prompt);
      for (final option in exercise.options) {
        chat.addTutorMessage(option);
      }
    } else if (parsed is Answer) {
      //
      // The AI answered a generic question
      //
      Answer answer = parsed;
      if (answer.answer.isNotEmpty) {
        chat.addTutorMessage(answer.answer);
      }
    } else if (parsed is Hint) {
      //
      // The AI has sent a Hint
      //
      Hint hint = parsed;
      chat.addTutorMessage(hint.hint);
      _conductor.hintProvided();
    } else if (parsed is CodeFeedback) {
      //
      // The AI gives feedback on code
      //
      CodeFeedback feedback = parsed;
      if (feedback.summary.isNotEmpty) chat.addTutorMessage(feedback.summary);

      final suggestionAllowed = await _conductor.updateProgress(
        feedback.quality,
      );
      if (feedback.suggestion.isNotEmpty && suggestionAllowed) {
        chat.addTutorMessage(feedback.suggestion);
      } else {
        await requestExercise();
      }
    } else if (parsed is McqFeedback) {
      //
      // The AI gives feedback on MCQ answer
      //
      McqFeedback feedback = parsed;
      chat.addTutorMessage(feedback.explanation);

      await _conductor.updateProgress(feedback.quality);
      await requestExercise();
    } else if (parsed is ExplainFeedback) {
      //
      // The AI gives feedback on explanation
      //
      ExplainFeedback explain = parsed;
      if (explain.feedback.isNotEmpty) {
        chat.addTutorMessage(explain.feedback);
      }

      final suggestionAllowed = await _conductor.updateProgress(
        explain.quality,
      );
      if (explain.followUp != null && suggestionAllowed) {
        chat.addTutorMessage(explain.followUp!);
      } else {
        await requestExercise();
      }
    } else if (parsed is SocraticFeedback) {
      //
      // The AI gives feedback on an answer to a socratic question
      //
      SocraticFeedback feedback = parsed;
      if (feedback.feedback.isNotEmpty) {
        chat.addTutorMessage(feedback.feedback);
      }

      final suggestionAllowed = await _conductor.updateProgress(
        feedback.quality,
      );
      if (feedback.followUp != null && suggestionAllowed) {
        chat.addTutorMessage(feedback.followUp!);
      } else {
        await requestExercise();
      }
    } else if (parsed is StatusSummary) {
      //
      // AI gives a status report when a goal is reached
      //
      StatusSummary status = parsed;
      await _updateReport(status.summary);
    } else if (parsed is ErrorResponse) {
      ErrorResponse error = parsed;
      chat.addSystemMessage(error.message);

      // resend the request
      final result = await _resendLastRequest();
      _handleResponse(result);
    } else {
      chat.addTutorMessage('Received unknown response from tutor.');

      // resend the request
      final result = await _resendLastRequest();
      _handleResponse(result);
    }
  }

  Future<dynamic> _resendLastRequest() async {
    final working = ref.read(tutorWorkingProvider.notifier);
    if (working.state) return;
    working.state = true;
    dynamic result;
    try {
      result = await _connector.resendRequest();
    } finally {
      working.state = false;
    }

    return result;
  }

  Future<void> _updateReport(String newReport) async {
    if (_conductor.currentChildGoal == null) return;

    // 1) Upsert child
    await ref.read(
      upsertStatusReportProviderFuture(
        StatusReport(
          goalID: _conductor.currentChildGoal!.id,
          statusReport: newReport,
        ),
      ).future,
    );
  }
}
