// LO-belief conductor (the conductor — there is no v1/v2 distinction).
//
// Source-of-truth for the algorithm is `docs/CONDUCTOR_POLICY.md` §1–§7,
// plus §8.2 event emission. Numeric constants come from
// `policy_constants.dart`. Belief arithmetic is delegated to
// `belief_math.dart`.
//
// Follow-up chaining (§6) lives at the TutorService boundary: the grader
// may emit a `followUp`, TutorService decides whether to present it under
// the §6.3 conditions, and on the next graded answer flags the call as
// `isFollowUp: true` so this conductor caps strength at `weak`, treats
// difficulty as `medium`, and skips calibration.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:ai_tutor_python/services/student_state/lo_belief.dart';
import 'package:ai_tutor_python/services/student_state/student_calibration.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/tutor/belief_math.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';
import 'package:collection/collection.dart';

/// Selected target for the next question, computed by [Conductor.planNext].
/// Returned to TutorService so it can pass `targetLOs` to the question
/// generator (CONDUCTOR_POLICY §1, §2).
class QuestionPlan {
  final ChatRequestType type;
  final QuestionDifficulty difficulty;
  final List<LearningObjective> targetLOs;
  final TurnSelectionReason reason;
  final bool blockedEmptyObjectives;
  final bool blockedSaturated;

  /// Set when [Conductor] is in degraded mode (CONDUCTOR_POLICY §7.3) and
  /// declines to plan anything. The conductor already surfaced its own
  /// "feedback is broken" system message at the moment of degradation, so
  /// callers should NOT also surface a "no more goals" celebration.
  final bool blockedDegraded;

  const QuestionPlan({
    required this.type,
    required this.difficulty,
    required this.targetLOs,
    required this.reason,
    this.blockedEmptyObjectives = false,
    this.blockedSaturated = false,
    this.blockedDegraded = false,
  });

  static const QuestionPlan noResult = QuestionPlan(
    type: ChatRequestType.noResult,
    difficulty: QuestionDifficulty.medium,
    targetLOs: [],
    reason: TurnSelectionReason(
      candidateLOs: [],
      chosenReason: 'no result',
      notchDropFired: false,
    ),
  );

  static const QuestionPlan degraded = QuestionPlan(
    type: ChatRequestType.noResult,
    difficulty: QuestionDifficulty.medium,
    targetLOs: [],
    reason: TurnSelectionReason(
      candidateLOs: [],
      chosenReason: 'degraded mode',
      notchDropFired: false,
    ),
    blockedDegraded: true,
  );

  factory QuestionPlan.emptyObjectives() {
    return const QuestionPlan(
      type: ChatRequestType.noResult,
      difficulty: QuestionDifficulty.medium,
      targetLOs: [],
      reason: TurnSelectionReason(
        candidateLOs: [],
        chosenReason: 'empty objectives',
        notchDropFired: false,
      ),
      blockedEmptyObjectives: true,
    );
  }

  factory QuestionPlan.saturated() {
    return const QuestionPlan(
      type: ChatRequestType.noResult,
      difficulty: QuestionDifficulty.medium,
      targetLOs: [],
      reason: TurnSelectionReason(
        candidateLOs: [],
        chosenReason: 'saturated',
        notchDropFired: false,
      ),
      blockedSaturated: true,
    );
  }
}

/// Result of integrating a graded answer (`updateProgress`).
class TurnOutcome {
  final AnswerQuality overallQuality;
  final bool subgoalAdvanced;
  final bool degraded;
  final List<TurnLoSignal> loSignals;
  final List<TurnAppliedSignal> appliedSignals;
  final List<TurnLoStatus> loStatusAfter;
  final double subgoalProgressAfter;
  final QuestionDifficulty calibrationBefore;
  final QuestionDifficulty calibrationAfter;
  final bool hadFallback;

  /// CONDUCTOR_POLICY §8.2 events fired during this turn. Empty for an
  /// ordinary graded turn; one or more entries when stuck-LO advance,
  /// single-LO deadlock, repeated demotions, sustained-LLM-failure or
  /// cascade-halt conditions tripped.
  final List<TurnSignalEvent> signalEvents;

  const TurnOutcome({
    required this.overallQuality,
    required this.subgoalAdvanced,
    required this.degraded,
    required this.loSignals,
    required this.appliedSignals,
    required this.loStatusAfter,
    required this.subgoalProgressAfter,
    required this.calibrationBefore,
    required this.calibrationAfter,
    required this.hadFallback,
    this.signalEvents = const [],
  });
}

/// Single (LO, signal, strength) tuple as parsed from the grader. Validation
/// happens before this enters the conductor.
class GradedSignal {
  final String subgoalId;
  final String loId;
  final LoSignalKind kind;
  final LoSignalStrength strength;
  const GradedSignal({
    required this.subgoalId,
    required this.loId,
    required this.kind,
    required this.strength,
  });
}

/// Input the conductor consumes when integrating a graded answer.
class GradedAnswer {
  final AnswerQuality overallQuality;
  final List<GradedSignal> signals;

  /// True when the grader response was unparseable / every signal failed
  /// validation and a fallback signal was synthesised. Counted toward the
  /// degraded-mode rule (CONDUCTOR_POLICY §7.3).
  final bool hadFallback;

  /// True when this grading call corresponds to a chained follow-up answer
  /// (CONDUCTOR_POLICY §6 / LLM_CONTRACT "Grading follow-up answers").
  /// The conductor:
  ///   - caps every signal's strength to `weak` before applying,
  ///   - treats the difficulty multiplier as `medium` regardless of the
  ///     original probe's difficulty,
  ///   - skips the calibration window update (§6.2 / §6.5),
  ///   - skips the notch-drop counter (a follow-up's effective difficulty
  ///     is medium, not the calibrated value).
  final bool isFollowUp;

  /// Depth of the follow-up at the time the answer was received: 1 for the
  /// direct follow-up, 2 for the chained one. Persisted on the turn record
  /// for debug visibility.
  final int chainDepth;

  const GradedAnswer({
    required this.overallQuality,
    required this.signals,
    this.hadFallback = false,
    this.isFollowUp = false,
    this.chainDepth = 0,
  });
}

class ConductorDeps {
  const ConductorDeps({
    required this.getGoalSelection,
    required this.setSelectedRoot,
    required this.setSelectedChild,
    required this.clearPreferred,
    required this.getRootGoals,
    required this.getChildren,
    required this.upsertProgress,
    required this.getProgressAll,
    required this.getProgressByGoalId,
    required this.setCurrentProgress,
    required this.addSystemNotice,
    required this.recordDebugEvent,
    required this.playCorrectAnswer,
    required this.playGoalReached,
    required this.showGoalReached,
    required this.pushConceptMastered,
    required this.getCalibration,
    required this.setCalibration,
    required this.getLoBelief,
    required this.getLoBeliefsForSubgoal,
    required this.upsertLoBelief,
    required this.appendTurnHistory,
  });

  final GoalSelectionState Function() getGoalSelection;
  final void Function(Goal?) setSelectedRoot;
  final void Function(Goal?) setSelectedChild;
  final void Function() clearPreferred;
  final Future<List<Goal>> Function() getRootGoals;
  final Future<List<Goal>> Function(String parentId) getChildren;
  final Future<void> Function(
    Progress p, {
    AnswerQuality? quality,
    bool recordHistory,
  })
  upsertProgress;
  final Future<List<Progress>> Function() getProgressAll;
  final Future<Progress?> Function(String goalId) getProgressByGoalId;
  final void Function(double) setCurrentProgress;

  /// Post a system pill in chat. Takes a [ChatNotice], not text — the
  /// conductor has no locale; the chat widget localizes (#23).
  final void Function(ChatNotice) addSystemNotice;
  final void Function(String name, [Map<String, Object?>?]) recordDebugEvent;
  final void Function() playCorrectAnswer;
  final void Function() playGoalReached;
  final void Function({required String goalTitle, required String description})
  showGoalReached;

  /// Invoked when a subgoal with `kind == 'concept'` masters. The host
  /// (tutor_service) decides whether to show the level-up overlay and what
  /// numbers to put on it — the conductor only signals the event.
  final void Function(String conceptName) pushConceptMastered;

  /// Calibration accessors. The current-account calibration substructure is
  /// embedded on `accounts/{uid}` (STUDENT_MODEL).
  final StudentCalibration Function() getCalibration;
  final Future<void> Function(StudentCalibration) setCalibration;

  final Future<LoBelief?> Function({
    required String subgoalId,
    required String loId,
  })
  getLoBelief;
  final Future<List<LoBelief>> Function(String subgoalId)
  getLoBeliefsForSubgoal;
  final Future<void> Function(LoBelief belief) upsertLoBelief;

  final Future<void> Function(PersistedTurnRecord record) appendTurnHistory;
}

class Conductor {
  Conductor({required this._deps});

  final ConductorDeps _deps;

  // Per-subgoal in-flight state. Reset on every advance.
  String? _lastTargetLoId;
  ChatRequestType? _lastQuestionType;

  // Sustained-failure counter (CONDUCTOR_POLICY §7.3). Per-session, not
  // persisted: a fresh `setTarget()` clears it.
  final List<bool> _recentFallbacks = [];
  bool _degraded = false;

  // Rolling cap on consecutive subgoal auto-skips during cascade-advance
  // (CONDUCTOR_POLICY §4.5). Also resets on `setTarget()`.
  int _cascadeDepth = 0;

  // Holds the id of the just-mastered subgoal for the post-mastery status
  // report. TutorService picks this up and fires a status query.
  String? _pendingStatusReportGoalId;

  // Session-scoped event-emission state (CONDUCTOR_POLICY §8.2). All reset
  // on `setTarget()`.

  /// Consecutive-demotions counter. Increments on demotion, resets on
  /// promotion, otherwise unchanged. Crossing
  /// `repeatedDemotionsThreshold` fires `repeatedDemotions` once.
  int _consecutiveDemotions = 0;

  /// True after `repeatedDemotions` has fired in this session — prevents
  /// re-firing every subsequent demotion.
  bool _repeatedDemotionsFired = false;

  /// True after `sustainedLlmFailure` has fired (the turn the conductor
  /// flips into degraded mode).
  bool _sustainedLlmFailureFired = false;

  /// Subgoal id we last fired `singleLoDeadlock` for in this session.
  /// Idempotency guard so the event fires once per (session, subgoal).
  String? _singleLoDeadlockSubgoalId;

  /// Pending audit event — populated when `_advanceWithCascadeCap` halts.
  /// Consumed by the next call to `integrateAnswer` so the cascade-halt
  /// rides on the same persisted turn that caused the advance.
  TurnSignalEvent? _pendingCascadeHaltEvent;

  /// Called on session entry / when the active subgoal changes externally.
  /// Picks the next subgoal if needed and resets per-subgoal state.
  Future<void> setTarget() async {
    if (_deps.getGoalSelection().preferredChild == null) {
      await _setTargetGoal();
    }
    final goal = _activeChildGoal;
    _lastTargetLoId = null;
    _lastQuestionType = null;
    _recentFallbacks.clear();
    _degraded = false;
    _cascadeDepth = 0;
    _consecutiveDemotions = 0;
    _repeatedDemotionsFired = false;
    _sustainedLlmFailureFired = false;
    _singleLoDeadlockSubgoalId = null;
    _pendingCascadeHaltEvent = null;
    _deps.recordDebugEvent('conductor.subgoal_set', {'subgoalId': goal?.id});
  }

  /// Pick the next question. CONDUCTOR_POLICY §1 (entry) and §2 (per-question).
  /// The same algorithm covers both; the only difference is what's empty.
  Future<QuestionPlan> planNext() async {
    if (_degraded) {
      return QuestionPlan.degraded;
    }
    final selection = _deps.getGoalSelection();
    final subgoal = selection.activeChildGoal;
    if (subgoal == null) {
      return QuestionPlan.noResult;
    }

    final objectives = subgoal.objectives;
    if (objectives.isEmpty) {
      _deps.recordDebugEvent('conductor.empty_objectives', {
        'subgoalId': subgoal.id,
      });
      return QuestionPlan.emptyObjectives();
    }

    final beliefs = await _deps.getLoBeliefsForSubgoal(subgoal.id);
    final byId = {for (final b in beliefs) b.loId: b};
    final now = DateTime.now().toUtc();

    // Snapshots after applying decay.
    final snapshots = <String, BeliefSnapshot>{};
    final masteredLoIds = <String>{};
    for (final lo in objectives) {
      final b = byId[lo.id];
      if (b == null) {
        snapshots[lo.id] = const BeliefSnapshot(
          PolicyConstants.prior,
          PolicyConstants.prior,
        );
        continue;
      }
      final snap = applyDecay(
        alpha: b.alpha,
        beta: b.beta,
        lastUpdatedAt: b.lastUpdatedAt,
        now: now,
      );
      snapshots[lo.id] = snap;
      if (meetsMasteryMeanAndEvidence(snap) &&
          b.lastPositiveAtCalibratedAt != null) {
        masteredLoIds.add(lo.id);
      }
    }

    // Unmastered = mean < threshold OR evidence < min OR cond3 not yet set.
    final unmastered = objectives
        .where((lo) => !masteredLoIds.contains(lo.id))
        .toList(growable: false);

    final calibration = _deps.getCalibration().difficulty;

    LearningObjective target;
    String chosenReason;

    if (unmastered.isNotEmpty) {
      // Prefer practiceable LOs: saturated ones can't move mean fast enough
      // for re-probing to help, and the saturated-stuck rule (CONDUCTOR_POLICY
      // §4.4) will normally have marked them stuck so the subgoal advances.
      // Falling back to the full unmastered pool only matters for the
      // purgatory case where every unmastered LO is saturated but sits in
      // [stuckSaturatedMeanCeiling, masteryMeanThreshold).
      final practiceable = unmastered
          .where((lo) => isPracticeable(snapshots[lo.id]!))
          .toList(growable: false);
      if (practiceable.isNotEmpty) {
        // Among practiceable: pick lowest mean, weight as tiebreaker.
        // Recency guard skips the previously-probed LO if alternatives exist.
        var pool = practiceable
            .where((lo) => lo.id != _lastTargetLoId)
            .toList(growable: false);
        if (pool.isEmpty) pool = practiceable;
        pool = pool.toList()
          ..sort((a, b) {
            final ma = snapshots[a.id]!.mean;
            final mb = snapshots[b.id]!.mean;
            if (ma != mb) return ma.compareTo(mb);
            // Higher weight wins on near-equal means.
            return b.weight.compareTo(a.weight);
          });
        target = pool.first;
        // Curriculum-order short-circuit during cold start: if every
        // snapshot is the prior, "lowest mean" ties on every LO — pick the
        // first in authoring order (CONDUCTOR_POLICY §1.1).
        final allFresh = unmastered.every((lo) {
          final snap = snapshots[lo.id]!;
          return snap.alpha == PolicyConstants.prior &&
              snap.beta == PolicyConstants.prior;
        });
        if (allFresh) {
          target = unmastered.first;
          chosenReason = 'cold start: first LO in order';
        } else if (pool.length < practiceable.length) {
          chosenReason = 'lowest mean (recency relaxed)';
        } else {
          chosenReason = 'lowest mean unmastered';
        }
      } else {
        // Every unmastered LO is saturated but not stuck. Pick the one
        // closest to mastery so the slow climb has the best chance to flip
        // an LO and unblock subgoal advance.
        final sorted = unmastered.toList()
          ..sort(
            (a, b) => snapshots[b.id]!.mean.compareTo(snapshots[a.id]!.mean),
          );
        target = sorted.first;
        chosenReason = 'all unmastered saturated: highest-mean fallback';
      }
    } else {
      // All mastered: top-up branch. Pick the mastered LO with the lowest
      // mean among practiceable ones (CONDUCTOR_POLICY §1.3).
      final practiceable = objectives
          .where((lo) => isPracticeable(snapshots[lo.id]!))
          .toList(growable: false);
      if (practiceable.isEmpty) {
        return QuestionPlan.saturated();
      }
      final sorted = practiceable.toList()
        ..sort(
          (a, b) => snapshots[a.id]!.mean.compareTo(snapshots[b.id]!.mean),
        );
      target = sorted.first;
      chosenReason = 'all mastered: lowest-mean practiceable';
    }

    final type = _pickType(target, snapshots[target.id]!);
    var difficulty = calibration;
    var notchDrop = false;
    final maybeDrop = await _shouldDropNotch(
      lo: target,
      subgoalId: subgoal.id,
      snap: snapshots[target.id]!,
      calibration: calibration,
    );
    if (maybeDrop) {
      difficulty = _stepDown(calibration);
      notchDrop = true;
    }

    final candidateStats = (unmastered.isNotEmpty ? unmastered : objectives)
        .take(3)
        .map(
          (lo) => CandidateLoStat(
            loId: lo.id,
            mean: snapshots[lo.id]!.mean,
            evidence: snapshots[lo.id]!.evidence,
          ),
        )
        .toList(growable: false);

    final reason = TurnSelectionReason(
      candidateLOs: candidateStats,
      chosenReason: chosenReason,
      notchDropFired: notchDrop,
    );

    return QuestionPlan(
      type: type,
      difficulty: difficulty,
      targetLOs: [target],
      reason: reason,
    );
  }

  /// Acceptable types per LO `kind` (CONDUCTOR_POLICY §2.2).
  static const Map<LoKind, List<ChatRequestType>> _acceptableTypes = {
    LoKind.recall: [
      ChatRequestType.mcQuestion,
      ChatRequestType.socraticQuestion,
    ],
    LoKind.apply: [
      ChatRequestType.completeCodeQuestion,
      ChatRequestType.writeCodeQuestion,
    ],
    LoKind.predict: [
      ChatRequestType.mcQuestion,
      ChatRequestType.explainCodeQuestion,
      ChatRequestType.socraticQuestion,
    ],
    LoKind.reason: [
      ChatRequestType.explainCodeQuestion,
      ChatRequestType.socraticQuestion,
    ],
  };

  /// Cold-start defaults per LO kind (CONDUCTOR_POLICY §1.1) and gentleness
  /// ordering used when `belief.mean < 0.5`.
  static const Map<LoKind, ChatRequestType> _coldStartDefault = {
    LoKind.recall: ChatRequestType.mcQuestion,
    LoKind.apply: ChatRequestType.completeCodeQuestion,
    LoKind.predict: ChatRequestType.mcQuestion,
    LoKind.reason: ChatRequestType.explainCodeQuestion,
  };

  static const List<ChatRequestType> _gentlenessOrder = [
    ChatRequestType.mcQuestion,
    ChatRequestType.completeCodeQuestion,
    ChatRequestType.explainCodeQuestion,
    ChatRequestType.writeCodeQuestion,
    ChatRequestType.socraticQuestion,
  ];

  ChatRequestType _pickType(LearningObjective lo, BeliefSnapshot snap) {
    final acceptable =
        _acceptableTypes[lo.kind] ?? const [ChatRequestType.socraticQuestion];
    final priorOnly =
        snap.alpha == PolicyConstants.prior &&
        snap.beta == PolicyConstants.prior;
    if (priorOnly) {
      // Cold-start default per kind. Fall back to the first acceptable if
      // the default is somehow not in the acceptable set.
      final def = _coldStartDefault[lo.kind] ?? acceptable.first;
      return acceptable.contains(def) ? def : acceptable.first;
    }
    final candidates = acceptable
        .where((t) => t.name != _lastQuestionTypeForLo(lo.id))
        .toList(growable: false);
    final pool = candidates.isEmpty ? acceptable : candidates;
    if (snap.mean < 0.5) {
      // Gentlest remaining.
      for (final t in _gentlenessOrder) {
        if (pool.contains(t)) return t;
      }
      return pool.first;
    }
    // Otherwise pick the type least-recently used on this LO. Without
    // per-(lo, type) timestamps we approximate as: not the last-used type.
    // The exclusion already handled that, so just take the first in the
    // acceptable set (deterministic).
    return pool.first;
  }

  String? _lastQuestionTypeForLo(String loId) {
    if (_lastTargetLoId != loId) return null;
    return _lastQuestionType?.name;
  }

  Future<bool> _shouldDropNotch({
    required LearningObjective lo,
    required String subgoalId,
    required BeliefSnapshot snap,
    required QuestionDifficulty calibration,
  }) async {
    // Two strikes at calibrated difficulty on this LO trigger a one-notch
    // drop (CONDUCTOR_POLICY §2.3). The literal rule is implemented via the
    // `recentNegativesAtCalibrated` counter on `LoBelief`: it increments on
    // each negative-at-calibrated answer and resets on any positive (any
    // difficulty). The override releases the next time a positive lands on
    // this LO, hence the `lastPositiveAtCalibratedAt is null` guard — once
    // the student has demonstrated this LO at calibration, we no longer
    // gate it back to easy.
    if (calibration == QuestionDifficulty.easy) return false;
    final belief = await _deps.getLoBelief(subgoalId: subgoalId, loId: lo.id);
    if (belief == null) return false;
    if (belief.lastPositiveAtCalibratedAt != null) return false;
    return belief.recentNegativesAtCalibrated >= 2;
  }

  QuestionDifficulty _stepDown(QuestionDifficulty d) {
    switch (d) {
      case QuestionDifficulty.easy:
        return QuestionDifficulty.easy;
      case QuestionDifficulty.medium:
        return QuestionDifficulty.easy;
      case QuestionDifficulty.hard:
        return QuestionDifficulty.medium;
    }
  }

  /// Records that the question described by [plan] is now the in-flight
  /// question. TutorService calls this immediately after deciding to fire
  /// a request so per-LO recency tracking lines up with the actual probe.
  void notePlannedQuestion(QuestionPlan plan) {
    _lastTargetLoId = plan.targetLOs.isEmpty ? null : plan.targetLOs.first.id;
    _lastQuestionType = plan.type;
  }

  /// Integrate a graded answer (CONDUCTOR_POLICY §3 + §4 + §5).
  ///
  /// [plan] is the plan that produced the question; the conductor needs it
  /// to know which LO was the intended target, what difficulty was set, and
  /// to populate the `selectionReason` on the persisted turn record.
  Future<TurnOutcome> integrateAnswer({
    required QuestionPlan plan,
    required GradedAnswer answer,
  }) async {
    final selection = _deps.getGoalSelection();
    final subgoal = selection.activeChildGoal;
    final targetLo = plan.targetLOs.isEmpty ? null : plan.targetLOs.first;

    final events = <TurnSignalEvent>[];

    // Track sustained-failure (degraded mode rule §7.3).
    _recentFallbacks.add(answer.hadFallback);
    while (_recentFallbacks.length > PolicyConstants.degradedWindow) {
      _recentFallbacks.removeAt(0);
    }
    final fallbackCount = _recentFallbacks.where((f) => f).length;
    if (fallbackCount >= PolicyConstants.degradedThreshold) {
      final wasDegraded = _degraded;
      _degraded = true;
      if (!wasDegraded) {
        _deps.addSystemNotice(
          const ChatNotice(ChatNoticeKind.feedbackDegraded),
        );
        _deps.recordDebugEvent('conductor.degraded_mode', {
          'fallbackCount': fallbackCount,
        });
      }
      if (!_sustainedLlmFailureFired) {
        _sustainedLlmFailureFired = true;
        events.add(
          TurnSignalEvent.of(
            TurnSignalEventKind.sustainedLlmFailure,
            details: {
              'fallbackCount': fallbackCount,
              'window': PolicyConstants.degradedWindow,
            },
          ),
        );
      }
    }

    if (subgoal == null) {
      // Nothing to update.
      return TurnOutcome(
        overallQuality: answer.overallQuality,
        subgoalAdvanced: false,
        degraded: _degraded,
        loSignals: const [],
        appliedSignals: const [],
        loStatusAfter: const [],
        subgoalProgressAfter: 0.0,
        calibrationBefore: _deps.getCalibration().difficulty,
        calibrationAfter: _deps.getCalibration().difficulty,
        hadFallback: answer.hadFallback,
        signalEvents: events,
      );
    }

    final calibrationBefore = _deps.getCalibration().difficulty;

    if (answer.overallQuality == AnswerQuality.correct) {
      _deps.playCorrectAnswer();
    }

    // ---- Belief updates --------------------------------------------------
    // For follow-up grading: cap strength at `weak` and treat the
    // difficulty multiplier as `medium` regardless of the original probe's
    // difficulty (CONDUCTOR_POLICY §6.2). The notch-drop counter and the
    // `lastPositiveAtCalibratedAt` ratchet are skipped because a follow-up
    // wasn't a calibrated probe.
    final appliedSignals = <TurnAppliedSignal>[];
    final touchedLoIds = <String>{};
    for (final sig in answer.signals) {
      if (sig.subgoalId != subgoal.id) continue; // scope already validated
      final lo = subgoal.objectives.firstWhereOrNull((o) => o.id == sig.loId);
      if (lo == null) continue;
      final existing = await _deps.getLoBelief(
        subgoalId: subgoal.id,
        loId: sig.loId,
      );
      final now = DateTime.now().toUtc();
      double alpha = existing?.alpha ?? PolicyConstants.prior;
      double beta = existing?.beta ?? PolicyConstants.prior;
      DateTime baseUpdatedAt = existing?.lastUpdatedAt ?? now;
      // Decay-on-read so subsequent persisted values are post-decay.
      final snap = applyDecay(
        alpha: alpha,
        beta: beta,
        lastUpdatedAt: baseUpdatedAt,
        now: now,
      );
      alpha = snap.alpha;
      beta = snap.beta;

      // §6.2 weak-cap: weaker = larger enum index (strong, moderate, weak).
      // For follow-up signals we keep sig.strength if it's already at-or-
      // weaker-than `weak` (i.e. weak), otherwise we floor it to `weak`.
      final effectiveStrength = answer.isFollowUp
          ? (sig.strength.index >= LoSignalStrength.weak.index
                ? sig.strength
                : LoSignalStrength.weak)
          : sig.strength;
      final effectiveDifficulty = answer.isFollowUp
          ? QuestionDifficulty.medium
          : plan.difficulty;
      final deltas = signalDeltas(
        kind: sig.kind,
        strength: effectiveStrength,
        difficulty: effectiveDifficulty,
      );
      final next = applyEvidence(
        alpha: alpha,
        beta: beta,
        alphaDelta: deltas.alphaDelta,
        betaDelta: deltas.betaDelta,
      );
      final hasPositive = sig.kind == LoSignalKind.positive;
      final hasNegative = sig.kind == LoSignalKind.negative;
      final isStrong = effectiveStrength == LoSignalStrength.strong;
      final atOrAbove = _difficultyAtLeast(plan.difficulty, calibrationBefore);
      final exactlyAtCalibration = plan.difficulty == calibrationBefore;
      // Follow-up grading does not satisfy the §4.3 ratchet (no calibrated
      // probe); skip both the timestamp set and the notch-drop counter.
      final newPositiveAtCalibrated =
          (!answer.isFollowUp && hasPositive && atOrAbove) ? now : null;

      // §2.3 counter: bump on a strong-negative at calibration, reset on
      // any positive (any difficulty / any strength), unchanged otherwise.
      // Moderate and weak negatives are too noisy to count as a strike —
      // see §2.3 "Two-strikes over one-strike" and the strong-negative
      // requirement on the most-recent answer.
      var nextNegativesAtCalibrated =
          existing?.recentNegativesAtCalibrated ?? 0;
      if (!answer.isFollowUp) {
        if (hasPositive) {
          nextNegativesAtCalibrated = 0;
        } else if (hasNegative && exactlyAtCalibration && isStrong) {
          nextNegativesAtCalibrated += 1;
        }
      }

      final updated = LoBelief(
        subgoalId: subgoal.id,
        loId: sig.loId,
        alpha: next.alpha,
        beta: next.beta,
        lastUpdatedAt: now,
        lastQuestionType: sig.loId == targetLo?.id
            ? plan.type.name
            : existing?.lastQuestionType,
        lastPositiveAtCalibratedAt:
            newPositiveAtCalibrated ?? existing?.lastPositiveAtCalibratedAt,
        recentNegativesAtCalibrated: nextNegativesAtCalibrated,
      );
      await _deps.upsertLoBelief(updated);
      appliedSignals.add(
        TurnAppliedSignal(
          loId: sig.loId,
          alphaDelta: next.alpha - alpha,
          betaDelta: next.beta - beta,
        ),
      );
      touchedLoIds.add(sig.loId);
    }

    // ---- Mastery + advancement ------------------------------------------
    final freshBeliefs = await _deps.getLoBeliefsForSubgoal(subgoal.id);
    final freshById = {for (final b in freshBeliefs) b.loId: b};
    final loStatus = <TurnLoStatus>[];
    final masteredCount = <bool>[];
    final stuckCount = <bool>[];
    for (final lo in subgoal.objectives) {
      final b = freshById[lo.id];
      final snap = b == null
          ? const BeliefSnapshot(PolicyConstants.prior, PolicyConstants.prior)
          : applyDecay(
              alpha: b.alpha,
              beta: b.beta,
              lastUpdatedAt: b.lastUpdatedAt,
              now: DateTime.now().toUtc(),
            );
      final isMastered =
          meetsMasteryMeanAndEvidence(snap) &&
          (b?.lastPositiveAtCalibratedAt != null);
      final stuck = isStuck(snap);
      loStatus.add(
        TurnLoStatus(
          loId: lo.id,
          mean: snap.mean,
          evidence: snap.evidence,
          mastered: isMastered,
          stuck: stuck,
        ),
      );
      if (!lo.optional) {
        masteredCount.add(isMastered);
        stuckCount.add(stuck);
      }
    }

    // Subgoal mastery: all non-optional LOs are mastered or stuck.
    // §7.7 deadlock: stuck-only single-LO subgoals do not advance.
    final allDoneOrStuck =
        masteredCount.every((m) => m) ||
        List.generate(
          masteredCount.length,
          (i) => masteredCount[i] || stuckCount[i],
        ).every((v) => v);
    final hasAtLeastOneMastered = masteredCount.any((m) => m);
    final subgoalMastered = allDoneOrStuck && hasAtLeastOneMastered;

    // Cache the subgoal progress (fraction of non-optional LOs that are
    // mastered). Stuck LOs do *not* count as progress in the cache — they
    // count for advancement but the chip honestly reflects mastery.
    final nonOptional = subgoal.objectives.where((lo) => !lo.optional).toList();
    final masteredNonOptional = loStatus
        .where(
          (s) =>
              !subgoal.objectives.firstWhere((lo) => lo.id == s.loId).optional,
        )
        .where((s) => s.mastered)
        .length;
    final cached = nonOptional.isEmpty
        ? 1.0
        : (subgoalMastered ? 1.0 : masteredNonOptional / nonOptional.length);

    bool advanced = false;
    if (subgoalMastered) {
      // §8.2 stuckLoAdvance: subgoal advanced with one or more stuck LOs.
      final stuckLoIds = <String>[];
      for (var i = 0; i < masteredCount.length; i++) {
        if (!masteredCount[i] && stuckCount[i]) {
          // Map back to the LO id by walking non-optional list in order.
          int idx = 0;
          for (final lo in subgoal.objectives) {
            if (lo.optional) continue;
            if (idx == i) {
              stuckLoIds.add(lo.id);
              break;
            }
            idx++;
          }
        }
      }
      if (stuckLoIds.isNotEmpty) {
        events.add(
          TurnSignalEvent.of(
            TurnSignalEventKind.stuckLoAdvance,
            details: {'subgoalId': subgoal.id, 'stuckLoIds': stuckLoIds},
          ),
        );
      }

      _pendingStatusReportGoalId = subgoal.id;
      await _persistSubgoalCache(
        cached,
        quality: answer.overallQuality,
        recordHistory: true,
      );
      _deps.setCurrentProgress(1.0);
      await _recomputeRoot();
      _deps.showGoalReached(
        goalTitle: subgoal.title,
        description: subgoal.description ?? '',
      );
      _deps.playGoalReached();
      if (subgoal.kind == 'concept') {
        _deps.pushConceptMastered(subgoal.title);
      }
      _cascadeDepth = 0;
      await _advanceWithCascadeCap();
      advanced = true;

      // Drain any cascade-halt audit event the advance produced.
      final pendingHalt = _pendingCascadeHaltEvent;
      if (pendingHalt != null) {
        events.add(pendingHalt);
        _pendingCascadeHaltEvent = null;
      }
    } else {
      // §7.7 single-LO deadlock detection: only fires when a non-optional
      // single-LO subgoal is stuck and (therefore) blocked from advancing.
      // Emit once per (session, subgoal) — `_singleLoDeadlockSubgoalId`.
      final nonOptionalLos = subgoal.objectives
          .where((lo) => !lo.optional)
          .toList();
      if (nonOptionalLos.length == 1 &&
          stuckCount.isNotEmpty &&
          stuckCount.first &&
          _singleLoDeadlockSubgoalId != subgoal.id) {
        _singleLoDeadlockSubgoalId = subgoal.id;
        events.add(
          TurnSignalEvent.of(
            TurnSignalEventKind.singleLoDeadlock,
            details: {'subgoalId': subgoal.id, 'loId': nonOptionalLos.first.id},
          ),
        );
      }

      await _persistSubgoalCache(
        cached,
        quality: answer.overallQuality,
        recordHistory: true,
      );
      _deps.setCurrentProgress(cached);
      await _recomputeRoot();
    }

    // ---- Calibration update (CONDUCTOR_POLICY §5) ------------------------
    // §6.2 / §6.5: follow-up answers don't enter the calibration window —
    // their difficulty is dialogue (medium-treated), not a calibrated probe.
    final cal = _deps.getCalibration();
    final updatedCal = answer.isFollowUp
        ? cal
        : _updateCalibration(
            current: cal,
            answer: CalibrationAnswer(
              quality: answer.overallQuality,
              difficulty: plan.difficulty,
              at: DateTime.now().toUtc(),
            ),
            questionTypeName: plan.type.name,
          );
    final calibrationAfter = updatedCal.difficulty;
    if (cal.difficulty != calibrationAfter) {
      _deps.addSystemNotice(
        ChatNotice(
          ChatNoticeKind.difficultyChanged,
          args: [cal.difficulty.name, calibrationAfter.name],
        ),
      );
    }
    await _deps.setCalibration(updatedCal);

    // §8.2 repeatedDemotions: counts consecutive demotions across the
    // session. Promotion resets; "no change" leaves the counter alone.
    if (calibrationAfter.index < calibrationBefore.index) {
      _consecutiveDemotions += 1;
      if (_consecutiveDemotions >= PolicyConstants.repeatedDemotionsThreshold &&
          !_repeatedDemotionsFired) {
        _repeatedDemotionsFired = true;
        events.add(
          TurnSignalEvent.of(
            TurnSignalEventKind.repeatedDemotions,
            details: {
              'count': _consecutiveDemotions,
              'calibrationAfter': calibrationAfter.name,
            },
          ),
        );
      }
    } else if (calibrationAfter.index > calibrationBefore.index) {
      _consecutiveDemotions = 0;
      _repeatedDemotionsFired = false;
    }

    return TurnOutcome(
      overallQuality: answer.overallQuality,
      subgoalAdvanced: advanced,
      degraded: _degraded,
      loSignals: answer.signals
          .map(
            (s) => TurnLoSignal(
              subgoalId: s.subgoalId,
              loId: s.loId,
              signal: s.kind.name,
              strength: s.strength.name,
            ),
          )
          .toList(growable: false),
      appliedSignals: appliedSignals,
      loStatusAfter: loStatus,
      subgoalProgressAfter: subgoalMastered ? 1.0 : cached,
      calibrationBefore: calibrationBefore,
      calibrationAfter: calibrationAfter,
      hadFallback: answer.hadFallback,
      signalEvents: List.unmodifiable(events),
    );
  }

  bool _difficultyAtLeast(QuestionDifficulty asked, QuestionDifficulty calib) {
    return asked.index >= calib.index;
  }

  StudentCalibration _updateCalibration({
    required StudentCalibration current,
    required CalibrationAnswer answer,
    required String questionTypeName,
  }) {
    final withAnswer = current.withAppendedAnswer(answer);
    final withType = withAnswer.withAppendedQuestionType(questionTypeName);
    final atCalibrated = withType.recentAnswers
        .where((a) => a.difficulty == withType.difficulty)
        .toList(growable: false);
    if (atCalibrated.length >= PolicyConstants.promotionMinSamples) {
      final correct = atCalibrated
          .where((a) => a.quality == AnswerQuality.correct)
          .length;
      final ratio = correct / atCalibrated.length;
      if (ratio >= PolicyConstants.promotionCorrectRatio) {
        final next = _stepUp(withType.difficulty);
        if (next != withType.difficulty) {
          return withType.copyWith(difficulty: next);
        }
      }
    }
    if (atCalibrated.length >= PolicyConstants.demotionMinSamples) {
      final bad = atCalibrated
          .where(
            (a) =>
                a.quality == AnswerQuality.wrong ||
                a.quality == AnswerQuality.partial,
          )
          .length;
      final ratio = bad / atCalibrated.length;
      if (ratio >= PolicyConstants.demotionBadRatio) {
        final next = _stepDown(withType.difficulty);
        if (next != withType.difficulty) {
          return withType.copyWith(difficulty: next);
        }
      }
    }
    return withType;
  }

  QuestionDifficulty _stepUp(QuestionDifficulty d) {
    switch (d) {
      case QuestionDifficulty.easy:
        return QuestionDifficulty.medium;
      case QuestionDifficulty.medium:
        return QuestionDifficulty.hard;
      case QuestionDifficulty.hard:
        return QuestionDifficulty.hard;
    }
  }

  // ---- Goal advancement ----------------------------------------------------

  /// Walk forward through subgoals; cap consecutive auto-skips at
  /// `cascadeSkipCap` (CONDUCTOR_POLICY §4.5). When the cascade halts the
  /// student lands on the subgoal that would have been skipped.
  Future<void> _advanceWithCascadeCap() async {
    if (_deps.getGoalSelection().preferredChild != null) {
      _deps.clearPreferred();
    }
    while (true) {
      final advanced = await _setTargetGoal();
      if (!advanced) return;
      final next = _activeChildGoal;
      if (next == null) return;
      // Is the next subgoal already mastered at entry? Then we cascade.
      final beliefs = await _deps.getLoBeliefsForSubgoal(next.id);
      final byId = {for (final b in beliefs) b.loId: b};
      bool allDone = next.objectives.isNotEmpty;
      for (final lo in next.objectives.where((lo) => !lo.optional)) {
        final b = byId[lo.id];
        if (b == null) {
          allDone = false;
          break;
        }
        final snap = applyDecay(
          alpha: b.alpha,
          beta: b.beta,
          lastUpdatedAt: b.lastUpdatedAt,
          now: DateTime.now().toUtc(),
        );
        if (!(meetsMasteryMeanAndEvidence(snap) &&
            b.lastPositiveAtCalibratedAt != null)) {
          allDone = false;
          break;
        }
      }
      if (!allDone) {
        _lastTargetLoId = null;
        _lastQuestionType = null;
        return;
      }
      // Auto-skip a mastered subgoal up to the cascade cap.
      _cascadeDepth += 1;
      if (_cascadeDepth > PolicyConstants.cascadeSkipCap) {
        _deps.recordDebugEvent('conductor.cascade_halt', {
          'subgoalId': next.id,
          'depth': _cascadeDepth,
        });
        // Audit event picked up by the calling `integrateAnswer` so the
        // record persists alongside the turn that triggered the cascade.
        _pendingCascadeHaltEvent = TurnSignalEvent.of(
          TurnSignalEventKind.cascadeHalt,
          details: {'haltedAtSubgoalId': next.id, 'depth': _cascadeDepth},
        );
        _lastTargetLoId = null;
        _lastQuestionType = null;
        return;
      }
      // Pretend this subgoal is already marked done in the progress cache.
      await _persistCacheFor(next.id, 1.0);
      await _recomputeRoot();
    }
  }

  Future<bool> _setTargetGoal() async {
    _deps.setSelectedRoot(null);
    _deps.setSelectedChild(null);

    final roots = await _deps.getRootGoals();
    final progressList = await _deps.getProgressAll();

    double progressFor(Goal g) {
      final p = progressList.firstWhereOrNull((x) => x.goalID == g.id);
      return p?.progress ?? 0.0;
    }

    for (final root in roots) {
      if (progressFor(root) < 1.0) {
        final subgoals = await _deps.getChildren(root.id);
        final targetChild = subgoals.firstWhereOrNull(
          (g) => progressFor(g) < 1.0,
        );

        if (targetChild != null) {
          _deps.setSelectedRoot(root);
          _deps.setSelectedChild(targetChild);
          _deps.setCurrentProgress(progressFor(targetChild));
          _deps.addSystemNotice(
            ChatNotice(
              ChatNoticeKind.newGoalSelected,
              args: [targetChild.title],
            ),
          );
          return true;
        }
      }
    }
    _deps.setCurrentProgress(0.0);
    return false;
  }

  /// Returns the id of the most recently mastered subgoal and clears the
  /// slot so the post-mastery status report fires once.
  String? takePendingStatusReportGoalId() {
    final id = _pendingStatusReportGoalId;
    _pendingStatusReportGoalId = null;
    return id;
  }

  /// Whether the conductor is currently in degraded mode (sustained
  /// LLM-contract failures, §7.3). Halts new question generation until the
  /// session resets.
  bool get isDegraded => _degraded;

  /// No-op kept for compatibility with hint dispatch. Hints don't enter
  /// calibration in the new conductor (CONDUCTOR_POLICY §5.2).
  void hintProvided() {
    _deps.recordDebugEvent('conductor.hint_provided');
  }

  // ---- Persistence helpers ------------------------------------------------

  Goal? get _activeChildGoal => _deps.getGoalSelection().activeChildGoal;

  Future<void> _persistSubgoalCache(
    double cached, {
    AnswerQuality? quality,
    bool recordHistory = true,
  }) async {
    final goal = _activeChildGoal;
    if (goal == null) return;
    await _persistCacheFor(
      goal.id,
      cached,
      quality: quality,
      recordHistory: recordHistory,
    );
  }

  Future<void> _persistCacheFor(
    String goalId,
    double cached, {
    AnswerQuality? quality,
    bool recordHistory = true,
  }) async {
    await _deps.upsertProgress(
      Progress(goalID: goalId, progress: cached),
      quality: quality,
      recordHistory: recordHistory,
    );
  }

  Future<void> _recomputeRoot() async {
    final selection = _deps.getGoalSelection();
    if (selection.selectedRoot == null) return;
    final root = selection.preferredRoot ?? selection.selectedRoot;
    if (root == null) return;
    final children = await _deps.getChildren(root.id);
    if (children.isEmpty) return;
    double sum = 0.0;
    for (final g in children) {
      final p = await _deps.getProgressByGoalId(g.id);
      sum += (p?.progress ?? 0.0);
    }
    await _deps.upsertProgress(
      Progress(goalID: root.id, progress: sum / children.length),
      recordHistory: false,
    );
  }
}
