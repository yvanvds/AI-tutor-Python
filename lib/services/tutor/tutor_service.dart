import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:ai_tutor_python/services/tutor/instruction_generator.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/question_formatter.dart';
import 'package:ai_tutor_python/services/tutor/responses/ai_response_parser.dart';
import 'package:ai_tutor_python/services/tutor/responses/response_handlers.dart';
import 'package:flutter/material.dart';

enum TutorState { idle, working, hasFollowUp }

class TutorService {
  final ValueNotifier<TutorState> state = ValueNotifier<TutorState>(
    TutorState.idle,
  );

  TutorService({
    OpenaiConnector? connector,
    Conductor? conductor,
    InstructionGenerator? instructionGenerator,
  }) {
    _connector = connector ?? OpenaiConnector();
    _conductor = conductor ?? Conductor();
    _instructionGeneratorOverride = instructionGenerator;
    _ctx = TutorContext(
      conductor: _conductor,
      startNewCode: _startNewCode,
      addTutorMessage: _addTutorMessage,
      addSystemMessage: _addSystemMessage,
      setExerciseType: (type) => _currentExerciseType = type,
      setFollowUp: _setFollowUp,
      requestExercise: requestExercise,
      maybeRetry: _maybeRetry,
    );
  }
  bool _initialized = false;

  InstructionGenerator? _instructionGeneratorOverride;

  InstructionGenerator get _instructionGenerator =>
      _instructionGeneratorOverride ?? InstructionGenerator();

  late final OpenaiConnector _connector;
  late final Conductor _conductor;
  late final TutorContext _ctx;

  String _currentExerciseType = '';

  String? _nextMessage;
  String? _nextCode;

  static const int _maxRetriesPerRequest = 1;
  int _retriesLeft = 0;

  // ---- Public API -----------------------------------------------------------

  Future<void> initializeSession({bool force = false}) async {
    if (_initialized && !force) return;
    _initialized = true;
    DataService.chat.clear();

    await _conductor.setTarget();

    final newQuestion = _conductor.getNextQuestion();

    if (newQuestion.$1 == ChatRequestType.noResult) {
      DataService.chat.addSystemMessage(
        "Er zijn geen doelen meer om aan te werken. Gefeliciteerd!",
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
    _retriesLeft = _maxRetriesPerRequest;

    ConnectorResult? result;
    try {
      final instructions = await _instructionGenerator.generateInstructions(
        type,
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

      result = await _connector.sendRequest(
        input: input,
        instructions: instructions,
        inputs: includeHistory,
      );
    } finally {
      state.value = TutorState.idle;
    }
    await _processResult(result);
  }

  Future<void> _processResult(ConnectorResult result) async {
    switch (result) {
      case ConnectorOk(:final output):
        await _handleResponse(output);
      case ConnectorFailure(:final message):
        _addSystemMessage('Er ging iets mis bij de tutor: $message');
        await _maybeRetry();
    }
  }

  Future<void> _maybeRetry() async {
    if (_retriesLeft <= 0) return;
    _retriesLeft--;
    final result = await _resendLastRequest();
    if (result == null) return;
    await _processResult(result);
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
        "Er zijn geen doelen meer om aan te werken. Gefeliciteerd!",
      );
      return;
    }

    DataService.chat.addSystemMessage(
      "Je volgende oefening wordt voorbereid...",
    );
    await queryTutor(type: newQuestion.$1, difficulty: newQuestion.$2);
  }

  void moveToFollowUp() {
    if (_nextMessage != null) {
      _addTutorMessage(_nextMessage!);
      _nextMessage = null;
    }
    if (_nextCode != null) {
      _startNewCode(_nextCode!);
      _nextCode = null;
    }
    state.value = TutorState.idle;
  }

  // ---- Private helpers ------------------------------------------------------

  Future<void> _handleResponse(dynamic response) async {
    final parsed = AIResponseParser.parse(response);
    _connector.addResponse(parsed);

    final dispatched = await dispatchResponse(parsed, _ctx);
    if (!dispatched) {
      _addTutorMessage('Onbekend antwoord ontvangen.');
      await _maybeRetry();
    }
  }

  Future<ConnectorResult?> _resendLastRequest() async {
    if (state.value != TutorState.idle) return null;
    state.value = TutorState.working;
    try {
      return await _connector.resendRequest();
    } finally {
      state.value = TutorState.idle;
    }
  }

  void _setFollowUp({String? message, String? code}) {
    _nextMessage = message;
    _nextCode = code;
    state.value = TutorState.hasFollowUp;
  }

  void _startNewCode(String code) {
    DataService.code.setText(code);
  }

  void _addTutorMessage(String message) {
    DataService.chat.addTutorMessage(message);
  }

  void _addSystemMessage(String message) {
    DataService.chat.addSystemMessage(message);
  }
}
