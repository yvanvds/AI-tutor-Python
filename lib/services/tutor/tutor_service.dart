import 'dart:convert';

import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/data/ai/ai_response_provider.dart';
import 'package:ai_tutor_python/data/code/code_provider.dart';
import 'package:ai_tutor_python/data/status_report/report_providers.dart';
import 'package:ai_tutor_python/data/status_report/status_report.dart';
import 'package:ai_tutor_python/services/chat_service.dart';
import 'package:ai_tutor_python/services/timeline/timeline.dart';
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
import 'package:ai_tutor_python/services/tutor/responses/guiding_exercise.dart';
import 'package:ai_tutor_python/services/tutor/responses/guiding_feedback.dart';
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
      case ChatRequestType.mcQuestion:
      case ChatRequestType.explainCodeQuestion:
      case ChatRequestType.completeCodeQuestion:
      case ChatRequestType.writeCodeQuestion:
        // All question types with difficulty parameter start a new session
        input = switch (type) {
          ChatRequestType.socraticQuestion =>
            QuestionFormatter.socraticQuestion(difficulty!),
          ChatRequestType.mcQuestion => QuestionFormatter.mcQuestion(
            difficulty!,
          ),
          ChatRequestType.explainCodeQuestion =>
            QuestionFormatter.explainCodeQuestion(difficulty!),
          ChatRequestType.completeCodeQuestion =>
            QuestionFormatter.completeCodeQuestion(difficulty!),
          ChatRequestType.writeCodeQuestion =>
            QuestionFormatter.writeCodeQuestion(difficulty!),
          _ => "", // unreachable
        };
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

      case ChatRequestType.guidingQuestion:
        input = QuestionFormatter.guidingQuestion();
        includeHistory = PreviousInputs.newSession;
        break;

      case ChatRequestType.guidingAnswer:
        if (prompt == null) return;
        input = QuestionFormatter.guidingAnswer(
          prompt,
          _conductor.getGuidingUnderstanding(),
        );
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
    } else if (_currentExerciseType == 'guiding_feedback' ||
        _currentExerciseType == 'guiding_exercise') {
      await queryTutor(type: ChatRequestType.guidingAnswer, prompt: message);
    } else {
      await queryTutor(type: ChatRequestType.studentQuestion, prompt: message);
    }
    _addUserMessage(message);
  }

  Future<void> requestHint(String? code) async {
    await queryTutor(type: ChatRequestType.requestHint, code: code);
  }

  Future<void> submitCode(String code) async {
    await queryTutor(type: ChatRequestType.submitCode, code: code);
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
      // print("We got a response: ${parsed.type}");
      // print(const JsonEncoder.withIndent('  ').convert(parsed.toJson()));
      return true;
    }());
    _connector.addResponse(parsed);

    if (parsed is CompleteCode) {
      //
      // The AI has sent Code to Complete
      //
      // add code to timeline and editor
      _startNewCode(parsed.code, true);

      // add message to timeline and chat
      _addTutorMessage(parsed.prompt, true);
    } else if (parsed is ExplainCode) {
      //
      // The AI has sent Code to Explain
      //
      _currentExerciseType = parsed.type;

      // add code to timeline and editor
      _startNewCode(parsed.code, true);

      // add message to timeline and chat
      _addTutorMessage(parsed.prompt, true);
    } else if (parsed is WriteCode) {
      //
      // The AI has sent instructions to write code
      //
      _currentExerciseType = parsed.type;
      _startNewCode('# Start writing your code here\n', true);
      _addTutorMessage(parsed.prompt, true);
    } else if (parsed is SocraticQuestion) {
      //
      // The AI has sent a socratic question
      //
      _currentExerciseType = parsed.type;
      _startNewCode('', true);

      _addTutorMessage(parsed.prompt, true);
    } else if (parsed is MultipleChoice) {
      //
      // the AI has sent a multiple choice question
      //
      _currentExerciseType = parsed.type;
      _startNewCode(parsed.code, true);

      _addTutorMessage(parsed.prompt, true);
      for (final option in parsed.options) {
        _addTutorMessage(option, true);
      }
    } else if (parsed is GuidingExcercise) {
      //
      // The AI has sent a guiding question
      //
      _currentExerciseType = parsed.type;
      _startNewCode(parsed.code, true);
      _addTutorMessage(parsed.prompt, true);
    } else if (parsed is GuidingFeedback) {
      //
      // The AI has sent feedback on a guiding answer
      //
      if (parsed.feedback.isNotEmpty) {
        _addTutorMessage(parsed.feedback, true);
      }

      bool guidingComplete = await _conductor.guidingIsComplete(
        parsed.understanding,
      );
      if (!guidingComplete) {
        if (parsed.code.isNotEmpty) {
          _startNewCode(parsed.code, false);
        }
        if (parsed.prompt.isNotEmpty) {
          _addTutorMessage(parsed.prompt, false);
        }
      } else {
        await requestExercise();
      }
    } else if (parsed is Answer) {
      //
      // The AI answered a generic question
      //
      if (parsed.answer.isNotEmpty) {
        _addTutorMessage(parsed.answer, true);
      }
    } else if (parsed is Hint) {
      //
      // The AI has sent a Hint
      //
      _addTutorMessage(parsed.hint, true);
      _conductor.hintProvided();
    } else if (parsed is CodeFeedback) {
      //
      // The AI gives feedback on code
      //
      if (parsed.summary.isNotEmpty) _addTutorMessage(parsed.summary, true);

      final suggestionAllowed = await _conductor.updateProgress(parsed.quality);
      if (parsed.suggestion.isNotEmpty && suggestionAllowed) {
        _addTutorMessage(parsed.suggestion, true);
      } else {
        await requestExercise();
      }
    } else if (parsed is McqFeedback) {
      //
      // The AI gives feedback on MCQ answer
      //
      _addTutorMessage(parsed.explanation, true);

      await _conductor.updateProgress(parsed.quality);
      await requestExercise();
    } else if (parsed is ExplainFeedback) {
      //
      // The AI gives feedback on explanation
      //
      if (parsed.feedback.isNotEmpty) {
        _addTutorMessage(parsed.feedback, true);
      }

      final suggestionAllowed = await _conductor.updateProgress(parsed.quality);
      if (parsed.followUp != null && suggestionAllowed) {
        _addTutorMessage(parsed.followUp!, true);
      } else {
        await requestExercise();
      }
    } else if (parsed is SocraticFeedback) {
      //
      // The AI gives feedback on an answer to a socratic question
      //
      if (parsed.feedback.isNotEmpty) {
        _addTutorMessage(parsed.feedback, true);
      }

      final suggestionAllowed = await _conductor.updateProgress(parsed.quality);
      if (parsed.followUp != null && suggestionAllowed) {
        _addTutorMessage(parsed.followUp!, true);
      } else {
        await requestExercise();
      }
    } else if (parsed is StatusSummary) {
      //
      // AI gives a status report when a goal is reached
      //
      await _updateReport(parsed.summary);
    } else if (parsed is ErrorResponse) {
      _addSystemMessage(parsed.message);

      // resend the request
      final result = await _resendLastRequest();
      _handleResponse(result);
    } else {
      _addTutorMessage('Received unknown response from tutor.', false);

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

  Future<void> _startNewCode(String code, bool updateEditor) async {
    // final timeline = ref.read(timeLineProvider);
    // timeline.startNewCode(code);
    // if (updateEditor) {
    ref.read(codeProvider.notifier).state = code;
    // }
  }

  Future<void> _addTutorMessage(String message, bool sendToChat) async {
    // final timeline = ref.read(timeLineProvider);
    // timeline.addAiMessage(message);

    // if (sendToChat) {
    final chat = ref.read(chatServiceProvider);
    chat.addTutorMessage(message);
    // }
  }

  Future<void> _addSystemMessage(String message) async {
    // we won't add system messages to the code timeline
    final chat = ref.read(chatServiceProvider);
    chat.addSystemMessage(message);
  }

  Future<void> _addUserMessage(String message) async {
    // add only to timeline, already added to chat when user sent it
    // final timeline = ref.read(timeLineProvider);
    // timeline.addUserMessage(message);
  }
}
