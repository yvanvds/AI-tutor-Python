import 'dart:math';

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/progress/concept_attribution.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

class ConductorDeps {
  const ConductorDeps({
    required this.getGoalSelection,
    required this.setSelectedRoot,
    required this.setSelectedChild,
    required this.clearPreferred,
    required this.getRootGoals,
    required this.getChildren,
    required this.getKnownConceptsInScope,
    required this.upsertProgress,
    required this.getProgressAll,
    required this.getProgressByGoalId,
    required this.setCurrentProgress,
    required this.addSystemMessage,
    required this.recordDebugEvent,
    required this.playCorrectAnswer,
    required this.playGuidingComplete,
    required this.playGoalReached,
    required this.showGoalReached,
  });

  final GoalSelectionState Function() getGoalSelection;
  final void Function(Goal?) setSelectedRoot;
  final void Function(Goal?) setSelectedChild;
  final void Function() clearPreferred;
  final Future<List<Goal>> Function() getRootGoals;
  final Future<List<Goal>> Function(String parentId) getChildren;
  final Future<List<String>> Function(
    Goal targetRoot, {
    List<Goal>? cachedRoots,
  })
  getKnownConceptsInScope;
  final Future<void> Function(
    Progress p, {
    AnswerQuality? quality,
    bool isWarmUp,
    bool recordHistory,
  })
  upsertProgress;
  final Future<List<Progress>> Function() getProgressAll;
  final Future<Progress?> Function(String goalId) getProgressByGoalId;
  final void Function(double) setCurrentProgress;
  final void Function(String) addSystemMessage;
  final void Function(String name, [Map<String, Object?>?]) recordDebugEvent;
  final void Function() playCorrectAnswer;
  final void Function() playGuidingComplete;
  final void Function() playGoalReached;
  final void Function({required String goalTitle, required String description})
  showGoalReached;
}

class Conductor {
  Conductor({required ConductorDeps deps}) : _deps = deps;

  final ConductorDeps _deps;

  // Mastery thresholds for the current subgoal.
  static const int _streakNeeded = 3;
  static const int _distinctTypesNeeded = 2;

  // Persisted floor that marks "guiding done, no practice yet" so a resumed
  // session can detect prior progress and skip guiding.
  static const double _guidingDoneMarker = 0.05;

  /// A "new session" for a subgoal starts when the persisted lastSessionAt
  /// is null or older than this.
  static const Duration sessionResumeThreshold = Duration(hours: 12);

  /// When the gap to lastSessionAt exceeds this, the warm-up gets +1
  /// question on top of the success-ratio derived count.
  static const Duration staleSessionThreshold = Duration(days: 14);

  static const int _maxWarmupQuestions = 3;

  /// Short Dutch system messages emitted before the first warm-up question
  /// of a session. Public so tests can match them.
  static const List<String> warmupGreetings = [
    'Welkom terug! Laten we even kijken of dit nog vlot zit.',
    'Hé, daar ben je weer. Eerst even kort opfrissen.',
    'Even een korte herhaling om in te komen.',
  ];

  static const List<ChatRequestType> _practiceTypes = [
    ChatRequestType.mcQuestion,
    ChatRequestType.explainCodeQuestion,
    ChatRequestType.completeCodeQuestion,
    ChatRequestType.socraticQuestion,
    ChatRequestType.writeCodeQuestion,
  ];

  final _rand = Random();

  // Per-subgoal state.
  bool _guidingDone = false;
  double _guidingConfidence = 0.0;
  int _correctStreak = 0;
  final Set<ChatRequestType> _typesInStreak = {};
  QuestionDifficulty _difficulty = QuestionDifficulty.easy;
  final List<AnswerQuality> _answerHistory = [];

  // AI-emitted suspected-concept attributions for the active subgoal.
  final List<ConceptAttribution> _attributions = [];

  // Quality of the most recent answer routed through `updateProgress`.
  AnswerQuality? _lastQuality;

  // Countdown of warm-up questions left for the active subgoal.
  int _warmupRemaining = 0;

  // Cross-subgoal state.
  int _hintsUsed = 0;
  ChatRequestType? _currentQuestionType;

  // Set after PRACTICE mastery to issue one diagnostic on the next subgoal.
  bool _diagnosingNext = false;

  // Holds the id of the just-mastered subgoal for the post-mastery status report.
  String? _pendingStatusReportGoalId;

  /// Whether the conductor is currently running warm-up questions.
  bool get isInWarmup => _warmupRemaining > 0;

  // ---- Lifecycle ----------------------------------------------------------

  Future<void> setTarget() async {
    if (_deps.getGoalSelection().preferredChild == null) {
      await _setTargetGoal();
    }
    final persisted = await _getActiveProgress();
    _resetSubgoalState(persisted: persisted);
  }

  void _resetSubgoalState({Progress? persisted}) {
    final pct = persisted?.progress ?? 0.0;
    _guidingDone = pct > 0.0;
    _guidingConfidence = 0.0;
    _correctStreak = (pct * _streakNeeded).round().clamp(0, _streakNeeded - 1);
    _typesInStreak.clear();
    _currentQuestionType = null;
    _diagnosingNext = false;
    _difficulty = persisted?.difficulty ?? QuestionDifficulty.easy;
    _answerHistory
      ..clear()
      ..addAll(persisted?.recentAnswers ?? const []);
    _attributions
      ..clear()
      ..addAll(persisted?.recentConceptAttributions ?? const []);
    _lastQuality = null;
    _warmupRemaining = _computeWarmupCount(persisted);
    if (_warmupRemaining > 0) {
      _deps.addSystemMessage(
        warmupGreetings[_rand.nextInt(warmupGreetings.length)],
      );
    }
    _deps.recordDebugEvent('conductor.subgoal_set', {
      'goalId': _activeChildGoal?.id,
      'persistedProgress': persisted?.progress ?? 0.0,
      'warmupRemaining': _warmupRemaining,
    });
  }

  int _computeWarmupCount(Progress? persisted) {
    if (persisted == null) return 0;
    if (persisted.progress < 0.5) return 0;

    final last = persisted.lastSessionAt;
    final now = DateTime.now().toUtc();
    if (last != null && now.difference(last) <= sessionResumeThreshold) {
      return 0;
    }

    final history = persisted.recentAnswers;
    int count;
    if (history.length < 2) {
      count = 1;
    } else {
      var score = 0.0;
      for (final q in history) {
        switch (q) {
          case AnswerQuality.correct:
            score += 1.0;
          case AnswerQuality.partial:
            score += 0.5;
          case AnswerQuality.wrong:
            break;
        }
      }
      final ratio = score / history.length;
      if (ratio >= 0.8) {
        count = 1;
      } else if (ratio >= 0.5) {
        count = 2;
      } else {
        count = 3;
      }
    }

    if (last != null && now.difference(last) > staleSessionThreshold) {
      count += 1;
    }
    if (count > _maxWarmupQuestions) count = _maxWarmupQuestions;
    return count;
  }

  // ---- Question selection -------------------------------------------------

  (ChatRequestType, QuestionDifficulty) getNextQuestion() {
    final selection = _deps.getGoalSelection();
    late final (ChatRequestType, QuestionDifficulty) result;
    if (selection.selectedChild == null && selection.preferredChild == null) {
      result = (ChatRequestType.noResult, _difficulty);
    } else if (_diagnosingNext) {
      _currentQuestionType = ChatRequestType.writeCodeQuestion;
      result = (_currentQuestionType!, QuestionDifficulty.hard);
    } else if (!_guidingDone) {
      _currentQuestionType = ChatRequestType.guidingQuestion;
      result = (_currentQuestionType!, QuestionDifficulty.easy);
    } else {
      final filtered = _practiceTypes
          .where((t) => t != _currentQuestionType)
          .toList(growable: false);
      final pool = filtered.isEmpty ? _practiceTypes : filtered;
      final pick = pool[_rand.nextInt(pool.length)];
      _currentQuestionType = pick;
      result = (pick, _difficulty);
    }
    _deps.recordDebugEvent('conductor.next_question', {
      'type': result.$1.name,
      'difficulty': result.$2.name,
      'diagnosingNext': _diagnosingNext,
      'guidingDone': _guidingDone,
    });
    return result;
  }

  // ---- Guiding phase ------------------------------------------------------

  double getGuidingUnderstanding() => _guidingConfidence;

  Future<bool> guidingIsComplete(double understanding) async {
    _guidingConfidence = (_guidingConfidence + understanding).clamp(0.0, 1.0);
    final completed = _guidingConfidence >= 0.8;
    _deps.recordDebugEvent('conductor.guiding_progress', {
      'delta': understanding,
      'total': _guidingConfidence,
      'completed': completed,
    });

    if (completed) {
      _guidingDone = true;
      _guidingConfidence = 0.0;
      _deps.playGuidingComplete();
      await _persistDisplayProgress();
      return true;
    }
    await _persistDisplayProgress();
    return false;
  }

  // ---- Practice answer ----------------------------------------------------

  Future<bool> updateProgress(AnswerQuality quality) async {
    _lastQuality = quality;
    if (quality == AnswerQuality.correct) {
      _deps.playCorrectAnswer();
    }

    if (_diagnosingNext) {
      return _handleDiagnosticAnswer(quality);
    }

    final inWarmup = _warmupRemaining > 0;
    final suppressPositive = inWarmup && quality == AnswerQuality.correct;
    if (inWarmup) _warmupRemaining -= 1;

    final streakBefore = _correctStreak;
    final difficultyBefore = _difficulty;
    final from = _displayProgress();
    if (!suppressPositive) _adaptStreak(quality);
    _adaptDifficulty(quality);
    _hintsUsed = 0;
    final to = _displayProgress();
    final mastered = _isMastered();
    final allowFollowUp = !mastered && _allowFollowUp(quality);

    _deps.recordDebugEvent('conductor.update_progress', {
      'quality': quality.name,
      'isWarmup': inWarmup,
      'suppressPositive': suppressPositive,
      'streakBefore': streakBefore,
      'streakAfter': _correctStreak,
      'typesInStreak': _typesInStreak.map((t) => t.name).toList(),
      'difficultyBefore': difficultyBefore.name,
      'difficultyAfter': _difficulty.name,
      'displayFrom': from,
      'displayTo': to,
      'mastered': mastered,
      'allowFollowUp': allowFollowUp,
    });

    _deps.addSystemMessage(
      'Vooruitgang: ${(from * 100).toStringAsFixed(0)}% -> ${(to * 100).toStringAsFixed(0)}%',
    );

    if (mastered) {
      await _markMasteredAndAdvance(
        quality: quality,
        isWarmUp: inWarmup,
        armDiagnostic: true,
      );
      return false;
    }

    await _persistDisplayProgress(quality: quality, isWarmUp: inWarmup);
    return _allowFollowUp(quality);
  }

  Future<bool> _handleDiagnosticAnswer(AnswerQuality quality) async {
    _diagnosingNext = false;
    _hintsUsed = 0;

    if (quality == AnswerQuality.correct) {
      _deps.addSystemMessage(
        'Diagnostisch antwoord goed — dit subdoel wordt overgeslagen.',
      );
      await _markMasteredAndAdvance(
        quality: quality,
        isWarmUp: false,
        armDiagnostic: false,
      );
    } else {
      _deps.addSystemMessage('We pakken dit subdoel rustig op.');
    }
    return false;
  }

  bool _isMastered() =>
      _correctStreak >= _streakNeeded &&
      _typesInStreak.length >= _distinctTypesNeeded;

  Future<void> _markMasteredAndAdvance({
    AnswerQuality? quality,
    bool isWarmUp = false,
    required bool armDiagnostic,
  }) async {
    final goal = _activeChildGoal;
    _deps.recordDebugEvent('conductor.mastered_and_advanced', {
      'goalId': goal?.id,
      'quality': quality?.name,
      'isWarmup': isWarmUp,
      'armDiagnostic': armDiagnostic,
    });
    if (goal != null) {
      await _deps.upsertProgress(
        Progress(
          goalID: goal.id,
          progress: 1.0,
          difficulty: _difficulty,
          recentAnswers: List.unmodifiable(_answerHistory),
          recentConceptAttributions: List.unmodifiable(_attributions),
        ),
        quality: quality,
        isWarmUp: isWarmUp,
        recordHistory: true,
      );
      _deps.setCurrentProgress(1.0);
      await _recomputeRoot();
    }
    if (armDiagnostic && goal != null) {
      _pendingStatusReportGoalId = goal.id;
    }
    await _handleGoalCompletion();
    if (_activeChildGoal != null && armDiagnostic) {
      _diagnosingNext = true;
    }
  }

  /// Returns the id of the most recently mastered subgoal (practice
  /// mastery only) and clears the slot.
  String? takePendingStatusReportGoalId() {
    final id = _pendingStatusReportGoalId;
    _pendingStatusReportGoalId = null;
    return id;
  }

  void _adaptStreak(AnswerQuality quality) {
    switch (quality) {
      case AnswerQuality.correct:
        _correctStreak += 1;
        if (_currentQuestionType != null) {
          _typesInStreak.add(_currentQuestionType!);
        }
      case AnswerQuality.partial:
        break;
      case AnswerQuality.wrong:
        _correctStreak = 0;
        _typesInStreak.clear();
    }
  }

  double _displayProgress() {
    if (!_guidingDone) return 0.0;
    if (_correctStreak == 0) return _guidingDoneMarker;
    return _correctStreak / _streakNeeded;
  }

  bool _allowFollowUp(AnswerQuality quality) {
    if (quality == AnswerQuality.wrong) return false;
    if (_correctStreak >= _streakNeeded) return false;
    return true;
  }

  // ---- Difficulty adaptation ---------------------------------------------

  void _adaptDifficulty(AnswerQuality quality) {
    final previousDifficulty = _difficulty;
    _answerHistory.add(quality);
    const int window = 5;
    if (_answerHistory.length > 10) _answerHistory.removeAt(0);
    final recent = _answerHistory.length <= window
        ? List<AnswerQuality>.from(_answerHistory)
        : _answerHistory.sublist(_answerHistory.length - window);

    final correctCount = recent.where((q) => q == AnswerQuality.correct).length;
    final wrongCount = recent.where((q) => q == AnswerQuality.wrong).length;
    final partialCount = recent.where((q) => q == AnswerQuality.partial).length;

    if (correctCount >= 4 &&
        _difficulty != QuestionDifficulty.hard &&
        _hintsUsed <= 1) {
      _difficulty = QuestionDifficulty.values[_difficulty.index + 1];
    }
    if ((wrongCount >= 3 || (wrongCount + partialCount) >= 4) &&
        _difficulty != QuestionDifficulty.easy) {
      _difficulty = QuestionDifficulty.values[_difficulty.index - 1];
    }
    if (previousDifficulty != _difficulty) {
      _deps.addSystemMessage(
        'Moeilijkheid aangepast: ${previousDifficulty.name} -> ${_difficulty.name}',
      );
    }
  }

  void hintProvided() {
    _hintsUsed += 1;
    _deps.recordDebugEvent('conductor.hint_provided');
  }

  // ---- Goal advancement ---------------------------------------------------

  Future<void> _handleGoalCompletion() async {
    final goal = _activeChildGoal;

    _deps.showGoalReached(
      goalTitle: goal?.title ?? 'Onbekend doel',
      description: goal?.description ?? '',
    );
    _deps.playGoalReached();

    final selection = _deps.getGoalSelection();
    if (selection.preferredChild != null) {
      _deps.clearPreferred();
    }
    await _setTargetGoal();
    final persisted = await _getActiveProgress();
    _resetSubgoalState(persisted: persisted);
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
          _deps.addSystemMessage(
            'Nieuw doel geselecteerd: ${targetChild.title}',
          );
          return true;
        }
      }
    }
    _deps.setCurrentProgress(0.0);
    return false;
  }

  // ---- Persistence helpers ------------------------------------------------

  Goal? get _activeChildGoal => _deps.getGoalSelection().activeChildGoal;

  Future<Progress?> _getActiveProgress() async {
    final goal = _activeChildGoal;
    if (goal == null) return null;
    return _deps.getProgressByGoalId(goal.id);
  }

  Future<void> _persistDisplayProgress({
    AnswerQuality? quality,
    bool isWarmUp = false,
  }) async {
    final goal = _activeChildGoal;
    if (goal == null) return;
    final pct = _displayProgress();
    await _deps.upsertProgress(
      Progress(
        goalID: goal.id,
        progress: pct,
        difficulty: _difficulty,
        recentAnswers: List.unmodifiable(_answerHistory),
        recentConceptAttributions: List.unmodifiable(_attributions),
      ),
      quality: quality,
      isWarmUp: isWarmUp,
      recordHistory: true,
    );
    _deps.setCurrentProgress(pct);
    await _recomputeRoot();
  }

  // ---- Concept attribution -----------------------------------------------

  Future<void> recordConceptAttributions(List<String>? concepts) async {
    if (concepts == null || concepts.isEmpty) return;

    final goal = _activeChildGoal;
    if (goal == null) return;

    final selection = _deps.getGoalSelection();
    final rootGoal = selection.preferredRoot ?? selection.selectedRoot;
    final allowed = rootGoal == null
        ? const <String>[]
        : await _deps.getKnownConceptsInScope(
            rootGoal,
            cachedRoots: selection.cachedRoots.isNotEmpty
                ? selection.cachedRoots
                : null,
          );
    final allowedSet = allowed.toSet();

    final accepted = <String>[];
    final dropped = <String>[];
    for (final raw in concepts) {
      final tag = raw.trim();
      if (tag.isEmpty) continue;
      if (allowedSet.contains(tag)) {
        accepted.add(tag);
      } else {
        dropped.add(tag);
      }
    }
    _deps.recordDebugEvent('conductor.record_concepts', {
      'input': concepts,
      'accepted': accepted,
      'dropped': dropped,
    });
    if (dropped.isNotEmpty) {
      debugPrint(
        'Conductor: dropped suspected_concepts not in scope: $dropped',
      );
    }
    if (accepted.isEmpty) return;

    final now = DateTime.now().toUtc();
    final quality = _lastQuality ?? AnswerQuality.wrong;
    for (final tag in accepted) {
      _attributions.add(
        ConceptAttribution(concept: tag, at: now, quality: quality),
      );
    }
    if (_attributions.length > Progress.recentConceptAttributionsWindow) {
      _attributions.removeRange(
        0,
        _attributions.length - Progress.recentConceptAttributionsWindow,
      );
    }

    await _persistDisplayProgress();
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
      isWarmUp: false,
      recordHistory: false,
    );
  }
}
