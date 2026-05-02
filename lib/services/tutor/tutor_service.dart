import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:ai_tutor_python/services/tutor/instruction_generator.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/question_formatter.dart';
import 'package:ai_tutor_python/services/tutor/responses/ai_response_parser.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/error_summary.dart';
import 'package:ai_tutor_python/services/tutor/responses/response_handlers.dart';
import 'package:flutter/material.dart';

enum TutorState { idle, working, hasFollowUp }

class _RequestInput {
  const _RequestInput(
    this.input, [
    this.history = PreviousInputs.includeSession,
    this.streamable = true,
  ]);
  final String input;
  final PreviousInputs history;

  /// Some request types (e.g. status_summary) don't produce a student-
  /// facing message, so streaming them just adds visual noise. Those use
  /// the non-streaming path.
  final bool streamable;
}

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
    var lastState = state.value;
    state.addListener(() {
      final next = state.value;
      DataService.debug.recordEvent('tutor.state_change', {
        'from': lastState.name,
        'to': next.name,
      });
      lastState = next;
    });
  }
  bool _initialized = false;

  InstructionGenerator? _instructionGeneratorOverride;

  InstructionGenerator get _instructionGenerator =>
      _instructionGeneratorOverride ?? InstructionGenerator();

  late final OpenaiConnector _connector;
  late final Conductor _conductor;

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

    if (force) {
      final user = DataService.auth.currentUser.value;
      DataService.debug.resetSession(
        uid: user?.oid,
        email: user?.email,
        modelName: DataService.globalConfig.cachedConfig?.model,
      );
    }

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

    var turnOpened = false;
    try {
      final instructions = await _instructionGenerator.generateInstructions(
        type,
      );

      final request = _buildRequestInput(
        type: type,
        difficulty: difficulty,
        code: code,
        prompt: prompt,
      );
      if (request == null) {
        state.value = TutorState.idle;
        return;
      }

      DataService.debug.beginTurn(
        requestType: type.name,
        currentExerciseTypeAtStart: _currentExerciseType,
        tutorStateAtStart: state.value.name,
        selectedRootGoalId: DataService.goals.selectedRootGoal.value?.id,
        selectedChildGoalId: DataService.goals.selectedChildGoal.value?.id,
        preferredRootGoalId: DataService.goals.preferredRootGoal.value?.id,
        preferredChildGoalId: DataService.goals.preferredChildGoal.value?.id,
        streamable: request.streamable,
        previousInputsMode: request.history.name,
      );
      turnOpened = true;
      DataService.debug.recordRequestPayload(
        userInput: request.input,
        instructions: instructions,
        instructionsDocId: type.name,
      );

      if (request.streamable) {
        await _runStream(
          () => _connector.sendRequestStream(
            input: request.input,
            instructions: instructions,
            inputs: request.history,
          ),
        );
      } else {
        final result = await _connector.sendRequest(
          input: request.input,
          instructions: instructions,
          inputs: request.history,
        );
        await _processNonStreamingResult(result);
      }
    } catch (e) {
      DataService.chat.failStream();
      _addSystemMessage('Er ging iets mis bij de tutor: $e');
    } finally {
      if (turnOpened) {
        DataService.debug.endTurn();
      }
      if (state.value == TutorState.working) {
        state.value = TutorState.idle;
      }
    }
  }

  _RequestInput? _buildRequestInput({
    required ChatRequestType type,
    QuestionDifficulty? difficulty,
    String? code,
    String? prompt,
  }) {
    switch (type) {
      case ChatRequestType.socraticQuestion:
      case ChatRequestType.mcQuestion:
      case ChatRequestType.explainCodeQuestion:
      case ChatRequestType.completeCodeQuestion:
      case ChatRequestType.writeCodeQuestion:
        return _buildQuestionRequest(type, difficulty);

      case ChatRequestType.submitCode:
        if (code == null) return null;
        return _RequestInput(QuestionFormatter.submitCode(code));

      case ChatRequestType.mcqAnswer:
        if (prompt == null) return null;
        return _RequestInput(QuestionFormatter.mcqAnswer(prompt));

      case ChatRequestType.requestHint:
        if (code == null) return null;
        return _RequestInput(QuestionFormatter.requestHint(code));

      case ChatRequestType.studentQuestion:
        if (prompt == null) return null;
        return _RequestInput(QuestionFormatter.studentQuestion(prompt, code));

      case ChatRequestType.explainAnswer:
        if (prompt == null) return null;
        return _RequestInput(QuestionFormatter.explainAnswer(prompt));

      case ChatRequestType.socraticFeedback:
        if (prompt == null) return null;
        return _RequestInput(QuestionFormatter.socraticFeedback(prompt));

      case ChatRequestType.guidingQuestion:
        return _RequestInput(
          QuestionFormatter.guidingQuestion(),
          PreviousInputs.newSession,
        );

      case ChatRequestType.guidingAnswer:
        if (prompt == null) return null;
        return _RequestInput(
          QuestionFormatter.guidingAnswer(
            prompt,
            _conductor.getGuidingUnderstanding(),
          ),
        );

      case ChatRequestType.status:
        return _RequestInput(
          QuestionFormatter.status(),
          PreviousInputs.includeAll,
          false, // not streamable: result is stored, not shown
        );

      case ChatRequestType.noResult:
        return null;
    }
  }

  _RequestInput _buildQuestionRequest(
    ChatRequestType type,
    QuestionDifficulty? difficulty,
  ) {
    final input = switch (type) {
      ChatRequestType.socraticQuestion =>
        QuestionFormatter.socraticQuestion(difficulty!),
      ChatRequestType.mcQuestion => QuestionFormatter.mcQuestion(difficulty!),
      ChatRequestType.explainCodeQuestion =>
        QuestionFormatter.explainCodeQuestion(difficulty!),
      ChatRequestType.completeCodeQuestion =>
        QuestionFormatter.completeCodeQuestion(difficulty!),
      ChatRequestType.writeCodeQuestion =>
        QuestionFormatter.writeCodeQuestion(difficulty!),
      _ => "",
    };
    return _RequestInput(input, PreviousInputs.newSession);
  }

  Future<void> _runStream(Stream<StreamChunk> Function() open) async {
    DataService.chat.startStream();
    final accumulated = StringBuffer();
    ChatResponse? completed;
    StreamFailed? failed;

    await for (final chunk in open()) {
      switch (chunk) {
        case StreamTextDelta(:final text):
          accumulated.write(text);
          DataService.chat.updateStream(accumulated.toString());
        case StreamCompleted(:final response):
          completed = response;
        case StreamFailed():
          failed = chunk;
      }
    }

    if (failed != null) {
      DataService.chat.failStream();
      _addSystemMessage('Er ging iets mis bij de tutor: ${failed.message}');
      await _maybeRetryStream();
      return;
    }

    final response = completed ??
        AIResponseParser.parse(accumulated.toString());
    _connector.addResponse(response);

    DataService.chat.completeStream(_finalTextFor(response, accumulated));

    final dispatched = await dispatchResponse(
      response,
      _streamingContext(),
    );
    if (!dispatched) {
      _addTutorMessage('Onbekend antwoord ontvangen.');
      await _maybeRetryStream();
    }
  }

  /// What we actually want to leave on screen after the stream finalises.
  /// For most types the streamed text already matches the model's `prompt`
  /// field. For [ErrorResponse] the model wrote the error in TEXT, but we
  /// don't want it lingering as a tutor message — clear it; the dispatcher
  /// will add a system message.
  String _finalTextFor(ChatResponse response, StringBuffer accumulated) {
    if (response is ErrorResponse) return '';
    return accumulated.toString();
  }

  /// Build a TutorContext whose first `addTutorMessage` is a no-op (the
  /// prompt was already shown via the stream). Subsequent calls — for
  /// example multiple_choice options or follow-up text — render normally.
  TutorContext _streamingContext() {
    var firstSuppressed = false;
    return TutorContext(
      conductor: _conductor,
      startNewCode: _startNewCode,
      addTutorMessage: (message) {
        if (!firstSuppressed) {
          firstSuppressed = true;
          return;
        }
        _addTutorMessage(message);
      },
      addSystemMessage: _addSystemMessage,
      setExerciseType: _trackedSetExerciseType,
      setFollowUp: _trackedSetFollowUp,
      requestExercise: requestExercise,
      maybeRetry: _maybeRetryStream,
    );
  }

  TutorContext _nonStreamingContext() {
    return TutorContext(
      conductor: _conductor,
      startNewCode: _startNewCode,
      addTutorMessage: _addTutorMessage,
      addSystemMessage: _addSystemMessage,
      setExerciseType: _trackedSetExerciseType,
      setFollowUp: _trackedSetFollowUp,
      requestExercise: requestExercise,
      maybeRetry: _maybeRetry,
    );
  }

  void _trackedSetExerciseType(String type) {
    final from = _currentExerciseType;
    _currentExerciseType = type;
    DataService.debug.recordEvent('tutor.exercise_type_set', {
      'from': from,
      'to': type,
    });
  }

  void _trackedSetFollowUp({String? message, String? code}) {
    _setFollowUp(message: message, code: code);
    DataService.debug.recordEvent('tutor.follow_up_set', {
      'hasMessage': message != null,
      'hasCode': code != null,
    });
  }

  Future<void> _processNonStreamingResult(ConnectorResult result) async {
    switch (result) {
      case ConnectorOk(:final output):
        await _handleResponse(output);
      case ConnectorFailure(:final message):
        _addSystemMessage('Er ging iets mis bij de tutor: $message');
        await _maybeRetry();
    }
  }

  Future<void> _maybeRetry() async {
    DataService.debug.recordEvent('tutor.maybe_retry', {
      'retriesLeft': _retriesLeft,
    });
    if (_retriesLeft <= 0) return;
    _retriesLeft--;
    final result = await _resendLastRequest();
    if (result == null) return;
    await _processNonStreamingResult(result);
  }

  Future<void> _maybeRetryStream() async {
    DataService.debug.recordEvent('tutor.maybe_retry', {
      'retriesLeft': _retriesLeft,
    });
    if (_retriesLeft <= 0) return;
    _retriesLeft--;
    if (state.value != TutorState.working) {
      state.value = TutorState.working;
    }
    await _runStream(() => _connector.resendRequestStream());
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
    DataService.debug.recordEvent('tutor.request_exercise.entered');
    final newQuestion = _conductor.getNextQuestion();
    DataService.debug.recordEvent('tutor.request_exercise.next', {
      'type': newQuestion.$1.name,
      'difficulty': newQuestion.$2.name,
    });

    if (newQuestion.$1 == ChatRequestType.noResult) {
      DataService.chat.addSystemMessage(
        "Er zijn geen doelen meer om aan te werken. Gefeliciteerd!",
      );
      return;
    }

    DataService.chat.addSystemMessage(
      "Je volgende oefening wordt voorbereid...",
    );

    // Often invoked from a feedback handler dispatched inside the outer
    // queryTutor's try block, so state is still `working` here. Release it
    // so the chained queryTutor below doesn't short-circuit on its idle guard.
    if (state.value == TutorState.working) {
      state.value = TutorState.idle;
    }

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

  Future<void> _handleResponse(String output) async {
    final parsed = AIResponseParser.parse(output);
    _connector.addResponse(parsed);

    final dispatched = await dispatchResponse(parsed, _nonStreamingContext());
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
