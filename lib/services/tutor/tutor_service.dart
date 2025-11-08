import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/services/status_report/status_report.dart';
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
import 'package:flutter/material.dart';

enum TutorState { idle, working, hasFollowUp }

class TutorService {
  final ValueNotifier<TutorState> state = ValueNotifier<TutorState>(
    TutorState.idle,
  );

  TutorService() {
    _connector = OpenaiConnector();
    _conductor = Conductor();
  }
  bool _initialized = false;

  InstructionGenerator get _instructionGenerator => InstructionGenerator();

  late final OpenaiConnector _connector;
  late final Conductor _conductor;

  String _currentExerciseType = '';

  String? _nextMessage;
  String? _nextCode;

  // ---- Public API -----------------------------------------------------------

  Future<void> initializeSession({bool force = false}) async {
    if (_initialized && !force) return;
    _initialized = true;
    DataService.chat.clear();

    await _conductor.initialize();

    final newQuestion = _conductor.getNextQuestion();

    if (newQuestion.$1 == ChatRequestType.noResult) {
      DataService.chat.addSystemMessage(
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
    if (state.value != TutorState.idle) return;
    state.value = TutorState.working;

    final instructions = await _instructionGenerator.generateInstructions(type);

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
      state.value = TutorState.idle;
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
      DataService.chat.addSystemMessage(
        "There are no goals available to work on. Have fun!",
      );
      return;
    }

    await queryTutor(type: newQuestion.$1, difficulty: newQuestion.$2);
  }

  void moveToFollowUp() {
    if (_nextMessage != null) {
      _addTutorMessage(_nextMessage!, true);
      _nextMessage = null;
    }
    if (_nextCode != null) {
      _startNewCode(_nextCode!, true);
      _nextCode = null;
    }
    state.value = TutorState.idle;
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
      if (parsed.prompt.isNotEmpty) {
        _addTutorMessage(parsed.prompt, true);
      }

      bool guidingComplete = await _conductor.guidingIsComplete(
        parsed.understanding,
      );
      if (!guidingComplete) {
        _nextCode = null;
        _nextMessage = null;
        if (parsed.code.isNotEmpty) {
          _nextCode = parsed.code;
        }
        if (parsed.followUp.isNotEmpty) {
          _nextMessage = parsed.followUp;
        }
        state.value = TutorState.hasFollowUp;
      } else {
        await requestExercise();
      }
    } else if (parsed is Answer) {
      //
      // The AI answered a generic question
      //
      if (parsed.prompt.isNotEmpty) {
        _addTutorMessage(parsed.prompt, true);
      }
    } else if (parsed is Hint) {
      //
      // The AI has sent a Hint
      //
      _addTutorMessage(parsed.prompt, true);
      _conductor.hintProvided();
    } else if (parsed is CodeFeedback) {
      //
      // The AI gives feedback on code
      //
      if (parsed.prompt.isNotEmpty) _addTutorMessage(parsed.prompt, true);

      final suggestionAllowed = await _conductor.updateProgress(parsed.quality);
      if (parsed.suggestion.isNotEmpty && suggestionAllowed) {
        _nextMessage = parsed.suggestion;
        _nextCode = null;
        state.value = TutorState.hasFollowUp;
      } else {
        await requestExercise();
      }
    } else if (parsed is McqFeedback) {
      //
      // The AI gives feedback on MCQ answer
      //
      _addTutorMessage(parsed.prompt, true);

      await _conductor.updateProgress(parsed.quality);
      await requestExercise();
    } else if (parsed is ExplainFeedback) {
      //
      // The AI gives feedback on explanation
      //
      if (parsed.prompt.isNotEmpty) {
        _addTutorMessage(parsed.prompt, true);
      }

      final suggestionAllowed = await _conductor.updateProgress(parsed.quality);
      if (parsed.followUp != null && suggestionAllowed) {
        _nextMessage = parsed.followUp!;
        _nextCode = null;
        state.value = TutorState.hasFollowUp;
      } else {
        await requestExercise();
      }
    } else if (parsed is SocraticFeedback) {
      //
      // The AI gives feedback on an answer to a socratic question
      //
      if (parsed.prompt.isNotEmpty) {
        _addTutorMessage(parsed.prompt, true);
      }

      final suggestionAllowed = await _conductor.updateProgress(parsed.quality);
      if (parsed.followUp != null && suggestionAllowed) {
        _nextMessage = parsed.followUp!;
        _nextCode = null;
        state.value = TutorState.hasFollowUp;
      } else {
        await requestExercise();
      }
    } else if (parsed is StatusSummary) {
      //
      // AI gives a status report when a goal is reached
      //
      await _updateReport(parsed.prompt);
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
    if (state.value != TutorState.idle) return;
    state.value = TutorState.working;
    dynamic result;
    try {
      result = await _connector.resendRequest();
    } finally {
      state.value = TutorState.idle;
    }

    return result;
  }

  Future<void> _updateReport(String newReport) async {
    if (DataService.goals.selectedChildGoal.value == null) return;

    // 1) Upsert child
    await DataService.report.upsert(
      StatusReport(
        goalID: DataService.goals.selectedChildGoal.value!.id,
        statusReport: newReport,
      ),
    );
  }

  Future<void> _startNewCode(String code, bool updateEditor) async {
    // final timeline = ref.read(timeLineProvider);
    // timeline.startNewCode(code);
    // if (updateEditor) {
    DataService.code.setText(code);
    // }
  }

  Future<void> _addTutorMessage(String message, bool sendToChat) async {
    // final timeline = ref.read(timeLineProvider);
    // timeline.addAiMessage(message);

    // if (sendToChat) {
    DataService.chat.addTutorMessage(message);
    // }
  }

  Future<void> _addSystemMessage(String message) async {
    // we won't add system messages to the code timeline
    DataService.chat.addSystemMessage(message);
  }

  Future<void> _addUserMessage(String message) async {
    // add only to timeline, already added to chat when user sent it
    // final timeline = ref.read(timeLineProvider);
    // timeline.addUserMessage(message);
  }
}
