import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/config/global_config_service.dart';
import 'package:ai_tutor_python/services/config/model_preference.dart';
import 'package:ai_tutor_python/services/debug/debug_session_recorder.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/instructions/instructions_service.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:ai_tutor_python/services/progression/level_up_controller.dart';
import 'package:ai_tutor_python/services/sound/sound_service.dart';
import 'package:ai_tutor_python/services/splash/splash_service.dart';
import 'package:ai_tutor_python/services/status_report/report_service.dart';
import 'package:ai_tutor_python/services/student_state/lo_beliefs_service.dart';
import 'package:ai_tutor_python/services/student_state/student_calibration.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/supervision/supervision_source.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:ai_tutor_python/services/tutor/belief_math.dart';
import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:ai_tutor_python/services/tutor/instruction_generator.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';
import 'package:collection/collection.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/question_formatter.dart';
import 'package:ai_tutor_python/services/tutor/responses/ai_response_parser.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/error_summary.dart';
import 'package:ai_tutor_python/services/tutor/responses/grader_payload.dart';
import 'package:ai_tutor_python/services/tutor/responses/graded_answer_builder.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:ai_tutor_python/services/tutor/responses/response_handlers.dart';
import 'package:ai_tutor_python/core/cosmos_doc_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum TutorState { idle, working, hasFollowUp }

/// Tracks a presented follow-up while we wait for the student's answer.
/// CONDUCTOR_POLICY §6 / §6.4: depth 1 by default, depth 2 when the active
/// subgoal has `allowChains: true`.
class _FollowUpInFlight {
  _FollowUpInFlight({
    required this.originalPlan,
    required this.depth,
    required this.question,
  });

  /// The plan the grader was originally answering (carries `targetLOs`,
  /// `difficulty`). Reused so the follow-up grading lands signals on the
  /// same LO unless the grader emits its own `loSignals`.
  final QuestionPlan originalPlan;

  /// 1 for the direct follow-up to the original probe; 2 when chained
  /// (only allowed when `subgoal.allowChains` is true).
  final int depth;

  final FollowUp question;
}

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
    this._connectorOverride,
    this._conductorOverride,
    this._instructionGeneratorOverride,
  });

  final OpenaiConnector? _connectorOverride;
  final Conductor? _conductorOverride;
  final InstructionGenerator? _instructionGeneratorOverride;

  late final OpenaiConnector _connector;
  late final Conductor _conductor;
  late final ChatService _chat;
  late final DebugSessionRecorder _debug;

  bool _initialized = false;
  String _currentExerciseType = '';
  String? _currentExerciseGoalId;
  String? _nextMessage;
  String? _nextCode;
  String? _statusReportGoalIdOverride;

  /// In-flight question plan. Set when a question request fires; consumed
  /// when the grader's feedback comes back so the conductor can integrate
  /// signals against the right LO/difficulty.
  QuestionPlan? _inFlightPlan;

  /// Subgoal ids for which `emptyObjectivesBlock` has already fired this
  /// session. Idempotency guard — same teacher-authoring gap shouldn't
  /// flood `turn_history` on every requestExercise tick.
  final Set<String> _emptyObjectivesAuditFiredFor = <String>{};

  /// Set when the grader emitted a `followUp` and the §6.3 conditions
  /// allowed presenting it. Cleared once the follow-up answer has been
  /// graded (or its conditions fail and we fall back to a regular probe).
  _FollowUpInFlight? _followUpInFlight;

  /// Set when an MCQ-driven grading advanced the subgoal and the next one has
  /// authored content. The mode flip to uitleg is deferred until the student
  /// clicks "Volgende" so the MCQ feedback panel survives long enough to be
  /// read. Consumed in [advanceFromMcq].
  bool _pendingExplainAfterMcqAdvance = false;

  /// Mid-flight curriculum-watch state (CONDUCTOR_POLICY §7.4). Subscribes
  /// to the active root's children so a teacher edit during a session can
  /// be reacted to (deleted subgoal → redirect, added LO → cache flip-back).
  StreamSubscription<List<Goal>>? _curriculumSub;
  String? _curriculumWatchedRootId;
  Map<String, Set<String>> _lastSubgoalLoIds = const {};

  static const int _maxRetriesPerRequest = 1;
  int _retriesLeft = 0;

  InstructionGenerator get _instructionGenerator =>
      _instructionGeneratorOverride ?? InstructionGenerator();

  @override
  TutorState build() {
    _chat = ref.read(chatServiceProvider);
    _debug = ref.read(debugServiceProvider);
    _connector =
        _connectorOverride ??
        OpenaiConnector(
          onRecordRawOutput: _debug.recordRawOutput,
          onRecordStreamFailure: _debug.recordStreamFailure,
          getConfig: () => ref.read(globalConfigServiceProvider),
          getModelOverride: () => ref.read(modelPreferenceProvider),
        );
    _conductor = _conductorOverride ?? Conductor(deps: _buildConductorDeps());

    ref.listen<AccountIdentity?>(authServiceProvider, (prev, next) {
      if (next == null) {
        _initialized = false;
        _stopCurriculumWatch();
        return;
      }
      if (!_initialized) unawaited(Future.microtask(initializeSession));
    }, fireImmediately: true);

    // Track active root + child so we can re-subscribe to the right
    // children stream when the student moves between goals (and tear
    // down the watch when nothing is selected).
    ref.listen<GoalSelectionState>(goalSelectionProvider, (prev, next) {
      final newRootId = next.activeRootGoal?.id;
      if (newRootId != _curriculumWatchedRootId) {
        _startCurriculumWatch(newRootId);
      }
    }, fireImmediately: true);

    ref.onDispose(_stopCurriculumWatch);

    return TutorState.idle;
  }

  // ---- Mid-flight curriculum watch (CONDUCTOR_POLICY §7.4) ---------------

  void _startCurriculumWatch(String? rootId) {
    _stopCurriculumWatch();
    _curriculumWatchedRootId = rootId;
    if (rootId == null) return;
    _curriculumSub = ref
        .read(goalsServiceProvider)
        .streamChildren(rootId)
        .listen(
          _onCurriculumTick,
          // `safeCosmosStream` absorbs poll errors upstream; this is the
          // belt for anything that still gets through (#7) so the watch
          // subscription is never torn down by an unhandled stream error.
          onError: (Object e) =>
              debugPrint('TutorService: curriculum watch error: $e'),
        );
  }

  // ---- Error surfacing (#7) ------------------------------------------------

  /// One student-facing line for an exception that escaped a tutor flow,
  /// as a [ChatNotice] the chat widget localizes (#23). Cosmos transient
  /// failures already went through the client's retries by the time they
  /// get here, so "try again" is honest advice.
  static ChatNotice describeFailure(Object e) {
    if (e is CosmosException && e.isTransient) {
      return const ChatNotice(ChatNoticeKind.databaseUnavailable);
    }
    return OpenaiConnector.describeTransportError(e);
  }

  static ChatNotice _tutorFailed(ChatNotice cause) =>
      ChatNotice(ChatNoticeKind.tutorFailed, cause: cause);

  /// Runs [body]; on failure posts a system message and resets whatever
  /// in-flight turn state would otherwise leak into the next request.
  /// `unawaited` entry points (curriculum ticks, MCQ advance, session
  /// start) had no catch at all before #7, so a Cosmos blip there was an
  /// uncaught async error and a silently stuck session.
  Future<void> _guarded(String what, Future<void> Function() body) async {
    try {
      await body();
    } catch (e, stack) {
      debugPrint('TutorService: $what failed: $e\n$stack');
      _debug.recordEvent('tutor.error', {'where': what, 'error': '$e'});
      _chat.failStream();
      _chat.addSystemNotice(_tutorFailed(describeFailure(e)));
      _inFlightPlan = null;
      _followUpInFlight = null;
      if (state == TutorState.working) state = TutorState.idle;
    }
  }

  void _stopCurriculumWatch() {
    _curriculumSub?.cancel();
    _curriculumSub = null;
    _curriculumWatchedRootId = null;
    _lastSubgoalLoIds = const {};
  }

  void _onCurriculumTick(List<Goal> children) {
    // Snapshot the LO ids per subgoal for the diff. Skip the first tick —
    // we only care about *changes* mid-session.
    final next = <String, Set<String>>{
      for (final c in children) c.id: c.objectives.map((o) => o.id).toSet(),
    };
    final prev = _lastSubgoalLoIds;
    _lastSubgoalLoIds = next;
    if (prev.isEmpty) return;

    final activeChild = ref.read(goalSelectionProvider).activeChildGoal;
    if (activeChild == null) return;

    // Subgoal-deleted redirect.
    if (prev.containsKey(activeChild.id) && !next.containsKey(activeChild.id)) {
      unawaited(
        _guarded(
          'subgoal-deleted redirect',
          () => _handleActiveSubgoalDeleted(deletedId: activeChild.id),
        ),
      );
      return;
    }

    // LO added to the active subgoal: flip the cached `progress` back from
    // 1.0 if it was mastered. The conductor's `planNext` will see the new
    // LO as unmastered automatically; the cache lag would otherwise leave
    // the leerpad chip incorrectly green for the rest of the polling
    // interval.
    final prevLos = prev[activeChild.id] ?? const <String>{};
    final nextLos = next[activeChild.id] ?? const <String>{};
    final added = nextLos.difference(prevLos);
    if (added.isNotEmpty) {
      unawaited(
        _guarded(
          'LO-added cache recompute',
          _recomputeActiveSubgoalCacheAfterLoAdded,
        ),
      );
    }
  }

  Future<void> _handleActiveSubgoalDeleted({required String deletedId}) async {
    _chat.addSystemNotice(
      const ChatNotice(ChatNoticeKind.subgoalDeletedRedirect),
    );
    await ref
        .read(turnHistoryServiceProvider)
        .appendAudit(
          subgoalId: deletedId,
          event: TurnSignalEvent.of(
            TurnSignalEventKind.subgoalDeletedRedirect,
            details: {'subgoalId': deletedId},
          ),
        );
    _inFlightPlan = null;
    _followUpInFlight = null;
    await _conductor.setTarget();
    await requestExercise();
  }

  Future<void> _recomputeActiveSubgoalCacheAfterLoAdded() async {
    final selection = ref.read(goalSelectionProvider);
    final activeChild = selection.activeChildGoal;
    if (activeChild == null) return;
    final beliefs = await ref
        .read(loBeliefsServiceProvider)
        .getAllForSubgoal(activeChild.id);
    final byId = {for (final b in beliefs) b.loId: b};
    final nonOptional = activeChild.objectives
        .where((lo) => !lo.optional)
        .toList();
    if (nonOptional.isEmpty) return;
    int mastered = 0;
    final now = DateTime.now().toUtc();
    for (final lo in nonOptional) {
      final b = byId[lo.id];
      if (b == null) continue;
      final snap = applyDecay(
        alpha: b.alpha,
        beta: b.beta,
        lastUpdatedAt: b.lastUpdatedAt,
        now: now,
      );
      if (meetsMasteryMeanAndEvidence(snap) &&
          b.lastPositiveAtCalibratedAt != null) {
        mastered += 1;
      }
    }
    final cached = mastered / nonOptional.length;
    await ref
        .read(progressServiceProvider)
        .upsert(
          Progress(goalID: activeChild.id, progress: cached),
          recordHistory: false,
        );
    ref.read(progressServiceProvider).setCurrentProgress(cached);
  }

  /// Translates the conductor's "a concept goal just mastered" signal into
  /// a throttled level-up overlay push. Reads the current derived XP/level
  /// from [xpStateProvider]; throttle lives on [LevelUpController].
  void _onConceptMastered(String conceptName) {
    final xpState = ref
        .read(xpStateProvider)
        .maybeWhen(data: (s) => s, orElse: () => null);
    ref
        .read(levelUpControllerProvider.notifier)
        .pushThrottled(
          LevelUpEvent(
            newLevel: xpState?.level ?? 1,
            xpAwarded: 100,
            conceptName: conceptName,
          ),
        );
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
      getChildren: (id) => ref.read(goalsServiceProvider).getChildrenOnce(id),
      upsertProgress: (p, {quality, recordHistory = true}) => ref
          .read(progressServiceProvider)
          .upsert(p, quality: quality, recordHistory: recordHistory),
      getProgressAll: () => ref.read(progressServiceProvider).getAll(),
      getProgressByGoalId: (id) =>
          ref.read(progressServiceProvider).getByGoalId(id),
      setCurrentProgress: (v) =>
          ref.read(progressServiceProvider).setCurrentProgress(v),
      addSystemNotice: _chat.addSystemNotice,
      recordDebugEvent: _debug.recordEvent,
      playCorrectAnswer: () =>
          unawaited(ref.read(soundServiceProvider).correctAnswer()),
      playGoalReached: () =>
          unawaited(ref.read(soundServiceProvider).playGoalReached()),
      showGoalReached: ({required goalTitle, required description}) => ref
          .read(splashServiceProvider)
          .showGoalReached(goalTitle: goalTitle, description: description),
      pushConceptMastered: _onConceptMastered,
      getCalibration: () =>
          ref.read(accountServiceProvider)?.calibration ??
          StudentCalibration.fresh(),
      setCalibration: (cal) =>
          ref.read(accountServiceProvider.notifier).setCalibration(cal),
      getLoBelief: ({required subgoalId, required loId}) => ref
          .read(loBeliefsServiceProvider)
          .getOne(subgoalId: subgoalId, loId: loId),
      getLoBeliefsForSubgoal: (id) =>
          ref.read(loBeliefsServiceProvider).getAllForSubgoal(id),
      upsertLoBelief: (b) => ref.read(loBeliefsServiceProvider).upsert(b),
      appendTurnHistory: (record) =>
          ref.read(turnHistoryServiceProvider).append(record),
    );
  }

  // ---- Public API -----------------------------------------------------------

  Future<void> initializeSession({bool force = false}) async {
    if (_initialized && !force) return;
    _initialized = true;
    _currentExerciseType = '';
    _currentExerciseGoalId = null;
    _inFlightPlan = null;
    _followUpInFlight = null;
    _chat.clear();

    if (force) {
      final user = ref.read(authServiceProvider);
      _debug.resetSession(
        uid: user?.oid,
        email: user?.email,
        modelName: ref.read(globalConfigServiceProvider)?.model,
      );
    }

    try {
      await _initializeSessionBody();
    } catch (e, stack) {
      // Session start reads goals, progress and beliefs from Cosmos. If
      // that fails the student used to get an empty chat and nothing else
      // (#7). Drop the initialised flag so the next ChatWidget mount (any
      // mode switch) retries from scratch.
      debugPrint('TutorService: initializeSession failed: $e\n$stack');
      _debug.recordEvent('tutor.error', {
        'where': 'initializeSession',
        'error': '$e',
      });
      _initialized = false;
      _chat.addSystemNotice(
        ChatNotice(
          ChatNoticeKind.sessionStartFailed,
          cause: describeFailure(e),
        ),
      );
    }
  }

  Future<void> _initializeSessionBody() async {
    await _conductor.setTarget();
    _emptyObjectivesAuditFiredFor.clear();

    final plan = await _conductor.planNext();
    if (plan.blockedEmptyObjectives) {
      await _surfaceEmptyObjectivesBlock();
      return;
    }
    if (plan.blockedSaturated) {
      _chat.addSystemNotice(const ChatNotice(ChatNoticeKind.subgoalSaturated));
      return;
    }
    if (plan.blockedDegraded) {
      // The conductor already surfaced its own degraded-mode message at the
      // moment of degradation. Stay quiet on follow-up planNext calls.
      return;
    }
    if (plan.type == ChatRequestType.noResult) {
      _chat.addSystemNotice(const ChatNotice(ChatNoticeKind.noGoalsLeft));
    }
  }

  /// Surface the empty-objectives system message and, on the first
  /// occurrence in this session for the active subgoal, append a
  /// `emptyObjectivesBlock` audit record (CONDUCTOR_POLICY §7.1 / §8.2).
  Future<void> _surfaceEmptyObjectivesBlock() async {
    _chat.addSystemNotice(const ChatNotice(ChatNoticeKind.emptyObjectives));
    final subgoalId = ref.read(goalSelectionProvider).activeChildGoal?.id;
    if (subgoalId == null) return;
    if (_emptyObjectivesAuditFiredFor.add(subgoalId)) {
      await ref
          .read(turnHistoryServiceProvider)
          .appendAudit(
            subgoalId: subgoalId,
            event: TurnSignalEvent.of(
              TurnSignalEventKind.emptyObjectivesBlock,
              details: {'subgoalId': subgoalId},
            ),
          );
    }
  }

  Future<void> queryTutor({
    required ChatRequestType type,
    QuestionPlan? plan,
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
        targetLOs: plan?.targetLOs ?? const [],
        goalScopeLOs: await _buildGoalScopeLOs(selection),
      );

      final request = await _buildRequestInput(
        type: type,
        plan: plan,
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

      if (plan != null) {
        _debug.recordEvent('conductor.planned', {
          'targetLO': plan.targetLOs.isEmpty ? null : plan.targetLOs.first.id,
          'questionType': plan.type.name,
          'difficulty': plan.difficulty.name,
          'chosenReason': plan.reason.chosenReason,
          'notchDropFired': plan.reason.notchDropFired,
          'candidateLOs': plan.reason.candidateLOs
              .map(
                (c) => {'loId': c.loId, 'mean': c.mean, 'evidence': c.evidence},
              )
              .toList(),
        });
        _conductor.notePlannedQuestion(plan);
        _inFlightPlan = plan;
      }

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
    } catch (e, stack) {
      // Anything past the connector: instruction fetch, response dispatch,
      // belief/progress writes while integrating a grade. The turn is
      // lost either way, so clear the in-flight plan — leaving it set made
      // the *next* student message grade against a stale question (#7).
      debugPrint('TutorService: queryTutor(${type.name}) failed: $e\n$stack');
      _debug.recordEvent('tutor.error', {'where': 'queryTutor', 'error': '$e'});
      _chat.failStream();
      _chat.addSystemNotice(_tutorFailed(describeFailure(e)));
      _inFlightPlan = null;
      _followUpInFlight = null;
    } finally {
      if (turnOpened) _debug.endTurn();
      if (state == TutorState.working) state = TutorState.idle;
    }
  }

  Future<List<({String subgoalId, LearningObjective lo})>> _buildGoalScopeLOs(
    GoalSelectionState selection,
  ) async {
    // Returns subgoalId × LearningObjective entries for every subgoal in
    // the active root, used by the grader's `goal_scope_los` payload (per
    // LLM_CONTRACT). Wrapped in a record list to keep the public surface
    // import-free.
    final root = selection.activeRootGoal;
    if (root == null) return const [];
    final subs = await ref.read(goalsServiceProvider).getChildrenOnce(root.id);
    final out = <({String subgoalId, LearningObjective lo})>[];
    for (final sub in subs) {
      for (final o in sub.objectives) {
        out.add((subgoalId: sub.id, lo: o));
      }
    }
    return out;
  }

  Future<_RequestInput?> _buildRequestInput({
    required ChatRequestType type,
    QuestionPlan? plan,
    String? code,
    String? prompt,
  }) async {
    final selection = ref.read(goalSelectionProvider);
    final scope = await _buildGradingScope(selection);
    switch (type) {
      case ChatRequestType.socraticQuestion:
      case ChatRequestType.mcQuestion:
      case ChatRequestType.explainCodeQuestion:
      case ChatRequestType.completeCodeQuestion:
      case ChatRequestType.writeCodeQuestion:
        if (plan == null) return null;
        return _buildQuestionRequest(type, plan);

      case ChatRequestType.submitCode:
        if (code == null) return null;
        return _RequestInput(
          QuestionFormatter.submitCode(
            code,
            targetLOs: _inFlightPlan?.targetLOs ?? const [],
            goalScopeLOs: scope,
          ),
        );

      case ChatRequestType.mcqAnswer:
        if (prompt == null) return null;
        return _RequestInput(
          QuestionFormatter.mcqAnswer(
            prompt,
            targetLOs: _inFlightPlan?.targetLOs ?? const [],
            goalScopeLOs: scope,
          ),
        );

      case ChatRequestType.requestHint:
        if (code == null) return null;
        return _RequestInput(QuestionFormatter.requestHint(code));

      case ChatRequestType.studentQuestion:
        if (prompt == null) return null;
        return _RequestInput(QuestionFormatter.studentQuestion(prompt, code));

      case ChatRequestType.explainAnswer:
        if (prompt == null) return null;
        return _RequestInput(
          QuestionFormatter.explainAnswer(
            prompt,
            targetLOs: _inFlightPlan?.targetLOs ?? const [],
            goalScopeLOs: scope,
          ),
        );

      case ChatRequestType.socraticFeedback:
        if (prompt == null) return null;
        return _RequestInput(
          QuestionFormatter.socraticFeedback(
            prompt,
            targetLOs: _inFlightPlan?.targetLOs ?? const [],
            goalScopeLOs: scope,
          ),
        );

      case ChatRequestType.followUpAnswer:
        if (prompt == null) return null;
        final fu = _followUpInFlight;
        if (fu == null) return null;
        return _RequestInput(
          QuestionFormatter.followUpAnswer(
            followUpQuestion: fu.question.question,
            studentAnswer: prompt,
            rationale: fu.question.rationale,
            chainDepth: fu.depth,
            targetLOs: fu.originalPlan.targetLOs,
            goalScopeLOs: scope,
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

  Future<List<({String subgoalId, LearningObjective lo})>> _buildGradingScope(
    GoalSelectionState selection,
  ) async {
    return _buildGoalScopeLOs(selection);
  }

  _RequestInput _buildQuestionRequest(ChatRequestType type, QuestionPlan plan) {
    final input = switch (type) {
      ChatRequestType.socraticQuestion => QuestionFormatter.socraticQuestion(
        plan.difficulty,
        targetLOs: plan.targetLOs,
      ),
      ChatRequestType.mcQuestion => QuestionFormatter.mcQuestion(
        plan.difficulty,
        targetLOs: plan.targetLOs,
      ),
      ChatRequestType.explainCodeQuestion =>
        QuestionFormatter.explainCodeQuestion(
          plan.difficulty,
          targetLOs: plan.targetLOs,
        ),
      ChatRequestType.completeCodeQuestion =>
        QuestionFormatter.completeCodeQuestion(
          plan.difficulty,
          targetLOs: plan.targetLOs,
        ),
      ChatRequestType.writeCodeQuestion => QuestionFormatter.writeCodeQuestion(
        plan.difficulty,
        targetLOs: plan.targetLOs,
      ),
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
      _chat.addSystemNotice(_tutorFailed(failed.notice));
      await _maybeRetryStream();
      return;
    }

    final response =
        completed ?? AIResponseParser.parse(accumulated.toString());
    _connector.addResponse(response);
    _chat.completeStream(_finalTextFor(response, accumulated));

    // Streak counter (issue #10): a successful tutor turn marks the day as
    // "active". Fire-and-forget so a streak write never blocks dispatch.
    unawaited(
      ref
          .read(accountServiceProvider.notifier)
          .registerSessionTurn()
          .catchError((Object e, StackTrace _) {
            debugPrint('TutorService: streak update failed: $e');
          }),
    );

    final dispatched = await dispatchResponse(response, _streamingContext());
    if (!dispatched) {
      _chat.addSystemNotice(const ChatNotice(ChatNoticeKind.unknownResponse));
      await _maybeRetryStream();
    }
  }

  String _finalTextFor(ChatResponse response, StringBuffer accumulated) {
    if (response is ErrorResponse) return '';
    if (response is MultipleChoice) return '';
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
      startNewCode: (code) =>
          ref.read(codeServiceProvider(SessionMode.practice)).setText(code),
      addTutorMessage: addTutorMessageOverride ?? _chat.addTutorMessage,
      addSystemNotice: _chat.addSystemNotice,
      // The editor comment a write-code exercise starts with. Read lazily so
      // it follows the language in effect when the exercise arrives.
      writeCodeTemplate: () =>
          ref.read(appLocalizationsProvider).session_writeCode_template,
      setExerciseType: _trackedSetExerciseType,
      setFollowUp: _trackedSetFollowUp,
      requestExercise: requestExercise,
      maybeRetry: maybeRetryOverride,
      playQuestion: () =>
          unawaited(ref.read(soundServiceProvider).askQuestion()),
      setActiveMcq: _setActiveMcq,
      applyMcqFeedback: _applyMcqFeedback,
      updateReportForGoal: report.updateForGoal,
      updateReportForCurrentGoal: report.updateForCurrentChildGoal,
      recordParsedResponse: _debug.recordParsedResponse,
      integrateGradedAnswer: _integrateGradedAnswer,
      getCurrentExerciseType: () => _currentExerciseType,
      statusReportGoalIdOverride: statusGoalIdOverride,
    );
  }

  Future<IntegrateOutcome> _integrateGradedAnswer({
    required AnswerQuality overallQuality,
    required List<LoSignal> loSignals,
    required List<TransferLoRef> transferLOs,
    required FollowUp? followUp,
  }) async {
    final plan = _inFlightPlan;
    if (plan == null) return IntegrateOutcome.continuing;
    final selection = ref.read(goalSelectionProvider);
    final activeRoot = selection.activeRootGoal;
    final activeChild = selection.activeChildGoal;
    final scopeSubgoals = activeRoot == null
        ? const <Goal>[]
        : await ref.read(goalsServiceProvider).getChildrenOnce(activeRoot.id);

    final priorFollowUp = _followUpInFlight;
    final isFollowUpGrading = priorFollowUp != null;
    final chainDepthOnAnswer = priorFollowUp?.depth ?? 0;

    final now = DateTime.now().toUtc();
    final provenance = await _resolveProvenance(at: now);
    final answer = GradedAnswerBuilder.build(
      overallQuality: overallQuality,
      rawSignals: loSignals,
      rawTransferLOs: transferLOs,
      scopeSubgoals: scopeSubgoals,
      intendedTargetLO: plan.targetLOs.isEmpty ? null : plan.targetLOs.first,
      intendedTargetSubgoalId: activeChild?.id,
      isFollowUp: isFollowUpGrading,
      chainDepth: chainDepthOnAnswer,
      provenance: provenance,
    );
    final outcome = await _conductor.integrateAnswer(
      plan: plan,
      answer: answer,
    );

    final record = PersistedTurnRecord(
      id: CosmosDocId.turnHistory(now),
      turnAt: now,
      subgoalId: activeChild?.id ?? '',
      targetLOIds: plan.targetLOs.map((lo) => lo.id).toList(),
      questionType: plan.type.name,
      difficulty: plan.difficulty,
      isFollowUp: isFollowUpGrading,
      chainDepth: chainDepthOnAnswer,
      selectionReason: plan.reason,
      overallQuality: outcome.overallQuality,
      loSignals: outcome.loSignals,
      hadFallback: outcome.hadFallback,
      appliedSignals: outcome.appliedSignals,
      calibrationBefore: outcome.calibrationBefore,
      calibrationAfter: outcome.calibrationAfter,
      subgoalProgressAfter: outcome.subgoalProgressAfter,
      loStatusAfter: outcome.loStatusAfter,
      subgoalAdvanced: outcome.subgoalAdvanced,
      signalEvents: outcome.signalEvents,
      provenance: provenance,
      transferCredits: outcome.transferCredits,
    );
    _debug.recordPersistedTurn(record, followUp: followUp);
    unawaited(ref.read(turnHistoryServiceProvider).append(record));

    // The current grading turn is consumed; clear in-flight and decide
    // whether a new follow-up should be presented.
    _inFlightPlan = null;
    _followUpInFlight = null;

    if (outcome.subgoalAdvanced) {
      // Drop back to uitleg so the new subgoal's theory is presented first,
      // before any practice question. Only when there's actually content to
      // show — without it the explain view renders an empty placeholder, so
      // fall through to the normal request-exercise path instead. For an
      // MCQ-driven advance, defer the mode flip until the student clicks
      // "Volgende" so the in-place MCQ feedback isn't unmounted before they
      // see it.
      final nextChild = ref.read(goalSelectionProvider).activeChildGoal;
      final hasContent =
          nextChild != null && (nextChild.contentId?.isNotEmpty ?? false);
      if (hasContent) {
        if (plan.type == ChatRequestType.mcQuestion) {
          _pendingExplainAfterMcqAdvance = true;
        } else {
          ref.read(modeProvider.notifier).state = SessionMode.explain;
        }
        return IntegrateOutcome.advanced;
      }
    }

    if (followUp != null &&
        _shouldPresentFollowUp(
          outcome: outcome,
          targetLO: plan.targetLOs.isEmpty ? null : plan.targetLOs.first,
          previousWasFollowUp: isFollowUpGrading,
          previousDepth: chainDepthOnAnswer,
        )) {
      _presentFollowUp(
        plan: plan,
        question: followUp,
        depth: chainDepthOnAnswer + 1,
      );
      return IntegrateOutcome.followUpPresented;
    }

    return IntegrateOutcome.continuing;
  }

  bool _shouldPresentFollowUp({
    required TurnOutcome outcome,
    required LearningObjective? targetLO,
    required bool previousWasFollowUp,
    required int previousDepth,
  }) {
    // §6.3 / §6.4 conditions:
    //   1. grader emitted followUp (caller already checked).
    //   2. depth boundary (default 1, 2 with allowChains).
    //   3. target LO not stuck.
    //   4. subgoal didn't just advance (caller already checked).
    final activeChild = ref.read(goalSelectionProvider).activeChildGoal;
    if (activeChild == null) return false;

    final allowChains = activeChild.allowChains;
    final maxDepth = allowChains
        ? PolicyConstants.followUpDepthWithChains
        : PolicyConstants.followUpDepthDefault;
    final nextDepth = previousDepth + 1;
    if (nextDepth > maxDepth) return false;

    // Depth-1 follow-up: ok unless the previous turn was already a
    // follow-up (which §6.3 condition 2 forbids without chains).
    if (previousWasFollowUp && !allowChains) return false;

    // Target-LO-stuck check.
    if (targetLO != null) {
      final status = outcome.loStatusAfter.firstWhereOrNull(
        (s) => s.loId == targetLO.id,
      );
      if (status != null && status.stuck) return false;
    }
    return true;
  }

  void _presentFollowUp({
    required QuestionPlan plan,
    required FollowUp question,
    required int depth,
  }) {
    _chat.addTutorMessage(question.question);
    unawaited(ref.read(soundServiceProvider).askQuestion());
    _followUpInFlight = _FollowUpInFlight(
      originalPlan: plan,
      depth: depth,
      question: question,
    );
    _debug.recordEvent('tutor.follow_up_presented', {
      'depth': depth,
      'rationale': question.rationale,
    });
  }

  /// Asks the supervision registry where the answer being graded was
  /// produced (#100). Fail-safe to `home`: a registry that cannot be reached
  /// or has no signed-in student must never hand out the supervised weight.
  Future<EvidenceProvenance> _resolveProvenance({required DateTime at}) async {
    final uid = ref.read(authServiceProvider)?.oid;
    if (uid == null) return EvidenceProvenance.home;
    try {
      final provenance = await ref
          .read(supervisionSourceProvider)
          .provenanceFor(uid: uid, at: at);
      _debug.recordEvent('tutor.provenance_resolved', {
        'provenance': provenance.name,
      });
      return provenance;
    } catch (e) {
      _debug.recordEvent('tutor.provenance_failed', {'error': e.toString()});
      return EvidenceProvenance.home;
    }
  }

  void _trackedSetExerciseType(String type) {
    final from = _currentExerciseType;
    _currentExerciseType = type;
    _currentExerciseGoalId = ref
        .read(goalSelectionProvider)
        .activeChildGoal
        ?.id;
    _debug.recordEvent('tutor.exercise_type_set', {
      'from': from,
      'to': type,
      'goalId': _currentExerciseGoalId,
    });
  }

  void _setActiveMcq({
    required String prompt,
    required String code,
    required List<String> options,
  }) {
    ref.read(activeMcqProvider.notifier).state = ActiveMcq(
      prompt: prompt,
      code: code,
      options: options,
    );
  }

  void _applyMcqFeedback({
    required String prompt,
    required AnswerQuality quality,
  }) {
    final current = ref.read(activeMcqProvider);
    if (current == null) return;
    ref.read(activeMcqProvider.notifier).state = current.copyWith(
      feedback: prompt,
      feedbackQuality: quality,
    );
  }

  /// Records the student's MCQ pick and asks the tutor to grade it.
  Future<void> submitMcqAnswer(String picked) async {
    final current = ref.read(activeMcqProvider);
    if (current == null || current.selected != null) return;
    ref.read(activeMcqProvider.notifier).state = current.copyWith(
      selected: picked,
    );
    await queryTutor(type: ChatRequestType.mcqAnswer, prompt: picked);
  }

  /// Dismisses the current MCQ render and asks the conductor for the next
  /// exercise. Called when the student clicks "Volgende" after seeing
  /// feedback.
  Future<void> advanceFromMcq() async {
    ref.read(activeMcqProvider.notifier).state = null;
    if (_pendingExplainAfterMcqAdvance) {
      _pendingExplainAfterMcqAdvance = false;
      ref.read(modeProvider.notifier).state = SessionMode.explain;
      return;
    }
    await _guarded('advanceFromMcq', requestExercise);
  }

  /// Whether there's an exercise rendered (or being prepared) for the
  /// current active subgoal.
  bool hasInFlightExercise() {
    final activeId = ref.read(goalSelectionProvider).activeChildGoal?.id;
    if (activeId == null) return false;
    if (state != TutorState.idle) return true;
    if (_currentExerciseType.isEmpty) return false;
    return _currentExerciseGoalId == activeId;
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
      case ConnectorFailure(:final notice):
        _chat.addSystemNotice(_tutorFailed(notice));
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
    // A pending follow-up takes precedence: the next student utterance is
    // the answer to the chained follow-up question, regardless of the
    // exercise type that produced the original probe.
    if (_followUpInFlight != null) {
      // Synthetic plan so the grader landing reuses the original probe's
      // target LO and gets the difficulty field. Conductor will treat the
      // grading as follow-up via the `_followUpInFlight != null` flag.
      _inFlightPlan = _followUpInFlight!.originalPlan;
      await queryTutor(type: ChatRequestType.followUpAnswer, prompt: message);
      return;
    }
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
    await queryTutor(type: ChatRequestType.submitCode, code: code);
  }

  /// Public entry (PracticeView mount, "Volgende" after an MCQ). The
  /// conductor's `planNext` reads beliefs from Cosmos; a failure there is
  /// reported in chat instead of escaping the widget callback (#7).
  Future<void> requestExercise() =>
      _guarded('requestExercise', _requestExerciseBody);

  Future<void> _requestExerciseBody() async {
    _debug.recordEvent('tutor.request_exercise.entered');

    final pendingStatusGoalId = _conductor.takePendingStatusReportGoalId();
    if (pendingStatusGoalId != null) {
      await _runStatusReportFor(pendingStatusGoalId);
    }

    final plan = await _conductor.planNext();
    _debug.recordEvent('tutor.request_exercise.next', {
      'type': plan.type.name,
      'difficulty': plan.difficulty.name,
      'targetLO': plan.targetLOs.isEmpty ? null : plan.targetLOs.first.id,
    });

    if (plan.blockedEmptyObjectives) {
      await _surfaceEmptyObjectivesBlock();
      return;
    }
    if (plan.blockedSaturated) {
      _chat.addSystemNotice(const ChatNotice(ChatNoticeKind.subgoalSaturated));
      return;
    }
    if (plan.blockedDegraded) {
      // The conductor already surfaced its own degraded-mode message at the
      // moment of degradation. Stay quiet on follow-up requestExercise calls.
      return;
    }
    if (plan.type == ChatRequestType.noResult) {
      _chat.addSystemNotice(const ChatNotice(ChatNoticeKind.noGoalsLeft));
      return;
    }

    _chat.addSystemNotice(const ChatNotice(ChatNoticeKind.preparingExercise));

    if (state == TutorState.working) state = TutorState.idle;
    await queryTutor(type: plan.type, plan: plan);
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
      ref.read(codeServiceProvider(SessionMode.practice)).setText(_nextCode!);
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
      _chat.addSystemNotice(const ChatNotice(ChatNoticeKind.unknownResponse));
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
