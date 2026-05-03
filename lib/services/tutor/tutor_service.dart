import 'dart:async';

import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/services/config/global_config_service.dart';
import 'package:ai_tutor_python/services/debug/debug_session_recorder.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/instructions/instructions_service.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:ai_tutor_python/services/sound/sound_service.dart';
import 'package:ai_tutor_python/services/splash/splash_service.dart';
import 'package:ai_tutor_python/services/status_report/report_service.dart';
import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:ai_tutor_python/services/tutor/instruction_generator.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/question_formatter.dart';
import 'package:ai_tutor_python/services/tutor/responses/ai_response_parser.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/error_summary.dart';
import 'package:ai_tutor_python/services/tutor/responses/response_handlers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum TutorState { idle, working, hasFollowUp }

class _RequestInput {
  const _RequestInput(
    this.input, [
    this.history = PreviousInputs.includeSession,
    this.streamable = true,
  ]);
  final String input;
  final PreviousInputs history;
  final bool streamable;
}

class TutorService extends Notifier<TutorState> {
  TutorService({
    OpenaiConnector? connectorOverride,
    Conductor? conductorOverride,
    InstructionGenerator? instructionGeneratorOverride,
  })  : _connectorOverride = connectorOverride,
        _conductorOverride = conductorOverride,
        _instructionGeneratorOverride = instructionGeneratorOverride;

  final OpenaiConnector? _connectorOverride;
  final Conductor? _conductorOverride;
  final InstructionGenerator? _instructionGeneratorOverride;

  late final OpenaiConnector _connector;
  late final Conductor _conductor;
  late final ChatService _chat;
  late final DebugSessionRecorder _debug;

  bool _initialized = false;
  String _currentExerciseType = '';
  String? _nextMessage;
  String? _nextCode;
  String? _statusReportGoalIdOverride;

  static const int _maxRetriesPerRequest = 1;
  int _retriesLeft = 0;

  InstructionGenerator get _instructionGenerator =>
      _instructionGeneratorOverride ?? InstructionGenerator();

  @override
  TutorState build() {
    _chat = ref.read(chatServiceProvider);
    _debug = ref.read(debugServiceProvider);
    _connector = _connectorOverride ?? OpenaiConnector(
      onRecordRawOutput: _debug.recordRawOutput,
      onRecordStreamFailure: _debug.recordStreamFailure,
      getConfig: () => ref.read(globalConfigServiceProvider),
    );
    _conductor = _conductorOverride ??
        Conductor(deps: _buildConductorDeps());

    ref.listen<AccountIdentity?>(
      authServiceProvider,
      (prev, next) {
        if (next == null) {
          _initialized = false;
          return;
        }
        if (!_initialized) unawaited(Future.microtask(initializeSession));
      },
      fireImmediately: true,
    );

    return TutorState.idle;
  }

  ConductorDeps _buildConductorDeps() {
    return ConductorDeps(
      getGoalSelection: () => ref.read(goalSelectionProvider),
      setSelectedRoot: (g) =>
          ref.read(goalSelectionProvider.notifier).setSelectedRoot(g),
      setSelectedChild: (g) =>
          ref.read(goalSelectionProvider.notifier).setSelectedChild(g),
      clearPreferred: () {
        ref.read(goalSelectionProvider.notifier).setPreferredRoot(null);
        ref.read(goalSelectionProvider.notifier).setPreferredChild(null);
      },
      getRootGoals: () => ref.read(goalsServiceProvider).getRootGoalsOnce(),
      getChildren: (id) =>
          ref.read(goalsServiceProvider).getChildrenOnce(id),
      getKnownConceptsInScope: (root, {cachedRoots}) =>
          ref.read(goalsServiceProvider).getKnownConceptsInScope(
            root,
            cachedRoots: cachedRoots,
          ),
      upsertProgress: (p, {quality, isWarmUp = false, recordHistory = true}) =>
          ref.read(progressServiceProvider).upsert(
            p,
            quality: quality,
            isWarmUp: isWarmUp,
            recordHistory: recordHistory,
          ),
      getProgressAll: () => ref.read(progressServiceProvider).getAll(),
      getProgressByGoalId: (id) =>
          ref.read(progressServiceProvider).getByGoalId(id),
      setCurrentProgress: (v) =>
          ref.read(progressServiceProvider).setCurrentProgress(v),
      addSystemMessage: _chat.addSystemMessage,
      recordDebugEvent: _debug.recordEvent,
      playCorrectAnswer: () =>
          unawaited(ref.read(soundServiceProvider).correctAnswer()),
      playGuidingComplete: () =>
          unawaited(ref.read(soundServiceProvider).guidingComplete()),
      playGoalReached: () =>
          unawaited(ref.read(soundServiceProvider).playGoalReached()),
      showGoalReached: ({required goalTitle, required description}) =>
          ref.read(splashServiceProvider).showGoalReached(
            goalTitle: goalTitle,
            description: description,
          ),
    );
  }

  // ---- Public API -----------------------------------------------------------

  Future<void> initializeSession({bool force = false}) async {
    if (_initialized && !force) return;
    _initialized = true;
    _chat.clear();

    if (force) {
      final user = ref.read(authServiceProvider);
      _debug.resetSession(
        uid: user?.oid,
        email: user?.email,
        modelName: ref.read(globalConfigServiceProvider)?.model,
      );
    }

    await _conductor.setTarget();

    final newQuestion = _conductor.getNextQuestion();
    if (newQuestion.$1 == ChatRequestType.noResult) {
      _chat.addSystemMessage(
        'Er zijn geen doelen meer om aan te werken. Gefeliciteerd!',
      );
    }
  }

  Future<void> queryTutor({
    required ChatRequestType type,
    QuestionDifficulty? difficulty,
    String? code,
    String? prompt,
  }) async {
    if (state != TutorState.idle) return;
    state = TutorState.working;
    _retriesLeft = _maxRetriesPerRequest;

    var turnOpened = false;
    try {
      final selection = ref.read(goalSelectionProvider);
      final instructions = await _instructionGenerator.generateInstructions(
        type,
        goalSelection: selection,
        cachedInstructions: ref.read(instructionsServiceProvider),
        fetchInstructions: () =>
            ref.read(instructionsServiceProvider.notifier).getAll(),
        fetchRootGoals: () => ref.read(goalsServiceProvider).getRootGoalsOnce(),
      );

      final request = _buildRequestInput(
        type: type,
        difficulty: difficulty,
        code: code,
        prompt: prompt,
      );
      if (request == null) {
        state = TutorState.idle;
        return;
      }

      _debug.beginTurn(
        requestType: type.name,
        currentExerciseTypeAtStart: _currentExerciseType,
        tutorStateAtStart: state.name,
        selectedRootGoalId: selection.selectedRoot?.id,
        selectedChildGoalId: selection.selectedChild?.id,
        preferredRootGoalId: selection.preferredRoot?.id,
        preferredChildGoalId: selection.preferredChild?.id,
        streamable: request.streamable,
        previousInputsMode: request.history.name,
      );
      turnOpened = true;
      _debug.recordRequestPayload(
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
      _chat.failStream();
      _chat.addSystemMessage('Er ging iets mis bij de tutor: $e');
    } finally {
      if (turnOpened) _debug.endTurn();
      if (state == TutorState.working) state = TutorState.idle;
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
          false,
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
      _ => '',
    };
    return _RequestInput(input, PreviousInputs.newSession);
  }

  Future<void> _runStream(Stream<StreamChunk> Function() open) async {
    _chat.startStream();
    final accumulated = StringBuffer();
    ChatResponse? completed;
    StreamFailed? failed;

    await for (final chunk in open()) {
      switch (chunk) {
        case StreamTextDelta(:final text):
          accumulated.write(text);
          _chat.updateStream(accumulated.toString());
        case StreamCompleted(:final response):
          completed = response;
        case StreamFailed():
          failed = chunk;
      }
    }

    if (failed != null) {
      _chat.failStream();
      _chat.addSystemMessage('Er ging iets mis bij de tutor: ${failed.message}');
      await _maybeRetryStream();
      return;
    }

    final response = completed ?? AIResponseParser.parse(accumulated.toString());
    _connector.addResponse(response);
    _chat.completeStream(_finalTextFor(response, accumulated));

    final dispatched = await dispatchResponse(response, _streamingContext());
    if (!dispatched) {
      _chat.addTutorMessage('Onbekend antwoord ontvangen.');
      await _maybeRetryStream();
    }
  }

  String _finalTextFor(ChatResponse response, StringBuffer accumulated) {
    if (response is ErrorResponse) return '';
    return accumulated.toString();
  }

  TutorContext _streamingContext() {
    var firstSuppressed = false;
    return _buildTutorContext(
      addTutorMessageOverride: (message) {
        if (!firstSuppressed) {
          firstSuppressed = true;
          return;
        }
        _chat.addTutorMessage(message);
      },
      maybeRetryOverride: _maybeRetryStream,
      statusGoalIdOverride: null,
    );
  }

  TutorContext _nonStreamingContext() {
    return _buildTutorContext(
      addTutorMessageOverride: null,
      maybeRetryOverride: _maybeRetry,
      statusGoalIdOverride: _statusReportGoalIdOverride,
    );
  }

  TutorContext _buildTutorContext({
    required void Function(String)? addTutorMessageOverride,
    required Future<void> Function() maybeRetryOverride,
    required String? statusGoalIdOverride,
  }) {
    final report = ref.read(reportServiceProvider);
    return TutorContext(
      conductor: _conductor,
      startNewCode: (code) => ref.read(codeServiceProvider).setText(code),
      addTutorMessage:
          addTutorMessageOverride ?? _chat.addTutorMessage,
      addSystemMessage: _chat.addSystemMessage,
      setExerciseType: _trackedSetExerciseType,
      setFollowUp: _trackedSetFollowUp,
      requestExercise: requestExercise,
      maybeRetry: maybeRetryOverride,
      playQuestion: () =>
          unawaited(ref.read(soundServiceProvider).askQuestion()),
      addMcqOptions: _chat.addMcqOptions,
      updateReportForGoal: report.updateForGoal,
      updateReportForCurrentGoal: report.updateForCurrentChildGoal,
      recordParsedResponse: _debug.recordParsedResponse,
      statusReportGoalIdOverride: statusGoalIdOverride,
    );
  }

  void _trackedSetExerciseType(String type) {
    final from = _currentExerciseType;
    _currentExerciseType = type;
    _debug.recordEvent('tutor.exercise_type_set', {'from': from, 'to': type});
  }

  void _trackedSetFollowUp({String? message, String? code}) {
    _setFollowUp(message: message, code: code);
    _debug.recordEvent('tutor.follow_up_set', {
      'hasMessage': message != null,
      'hasCode': code != null,
    });
  }

  Future<void> _processNonStreamingResult(ConnectorResult result) async {
    switch (result) {
      case ConnectorOk(:final output):
        await _handleResponse(output);
      case ConnectorFailure(:final message):
        _chat.addSystemMessage('Er ging iets mis bij de tutor: $message');
        await _maybeRetry();
    }
  }

  Future<void> _maybeRetry() async {
    _debug.recordEvent('tutor.maybe_retry', {'retriesLeft': _retriesLeft});
    if (_retriesLeft <= 0) return;
    _retriesLeft--;
    final result = await _resendLastRequest();
    if (result == null) return;
    await _processNonStreamingResult(result);
  }

  Future<void> _maybeRetryStream() async {
    _debug.recordEvent('tutor.maybe_retry', {'retriesLeft': _retriesLeft});
    if (_retriesLeft <= 0) return;
    _retriesLeft--;
    if (state != TutorState.working) state = TutorState.working;
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
    _debug.recordEvent('tutor.request_exercise.entered');

    final pendingStatusGoalId = _conductor.takePendingStatusReportGoalId();
    if (pendingStatusGoalId != null) {
      await _runStatusReportFor(pendingStatusGoalId);
    }

    final newQuestion = _conductor.getNextQuestion();
    _debug.recordEvent('tutor.request_exercise.next', {
      'type': newQuestion.$1.name,
      'difficulty': newQuestion.$2.name,
    });

    if (newQuestion.$1 == ChatRequestType.noResult) {
      _chat.addSystemMessage(
        'Er zijn geen doelen meer om aan te werken. Gefeliciteerd!',
      );
      return;
    }

    _chat.addSystemMessage('Je volgende oefening wordt voorbereid...');

    if (state == TutorState.working) state = TutorState.idle;
    await queryTutor(type: newQuestion.$1, difficulty: newQuestion.$2);
  }

  Future<void> _runStatusReportFor(String goalID) async {
    if (state == TutorState.working) state = TutorState.idle;
    _statusReportGoalIdOverride = goalID;
    try {
      await queryTutor(type: ChatRequestType.status);
    } finally {
      _statusReportGoalIdOverride = null;
    }
  }

  void moveToFollowUp() {
    if (_nextMessage != null) {
      _chat.addTutorMessage(_nextMessage!);
      _nextMessage = null;
    }
    if (_nextCode != null) {
      ref.read(codeServiceProvider).setText(_nextCode!);
      _nextCode = null;
    }
    state = TutorState.idle;
  }

  // ---- Private helpers ------------------------------------------------------

  Future<void> _handleResponse(String output) async {
    final parsed = AIResponseParser.parse(output);
    _connector.addResponse(parsed);
    final dispatched = await dispatchResponse(parsed, _nonStreamingContext());
    if (!dispatched) {
      _chat.addTutorMessage('Onbekend antwoord ontvangen.');
      await _maybeRetry();
    }
  }

  Future<ConnectorResult?> _resendLastRequest() async {
    if (state != TutorState.idle) return null;
    state = TutorState.working;
    try {
      return await _connector.resendRequest();
    } finally {
      state = TutorState.idle;
    }
  }

  void _setFollowUp({String? message, String? code}) {
    _nextMessage = message;
    _nextCode = code;
    state = TutorState.hasFollowUp;
  }
}

final tutorServiceProvider = NotifierProvider<TutorService, TutorState>(
  TutorService.new,
);
