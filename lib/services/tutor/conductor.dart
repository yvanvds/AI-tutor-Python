import 'dart:math';

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/progress/concept_attribution.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

class Conductor {
  Conductor();

  // Mastery thresholds for the current subgoal.
  static const int _streakNeeded = 3;
  static const int _distinctTypesNeeded = 2;

  // Persisted floor that marks "guiding done, no practice yet" so a resumed
  // session can detect prior progress and skip guiding.
  static const double _guidingDoneMarker = 0.05;

  /// A "new session" for a subgoal starts when the persisted lastSessionAt
  /// is null or older than this. Bump this down (e.g. to 1 minute) when
  /// manually testing the warm-up flow, then restore.
  static const Duration sessionResumeThreshold = Duration(minutes: 1);

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

  // Per-subgoal state — reset (and reseeded from persisted progress) whenever
  // the active subgoal changes. `_difficulty` and `_answerHistory` live on
  // the (uid, goalId) progress doc so they survive app restarts.
  bool _guidingDone = false;
  double _guidingConfidence = 0.0;
  int _correctStreak = 0;
  final Set<ChatRequestType> _typesInStreak = {};
  QuestionDifficulty _difficulty = QuestionDifficulty.easy;
  final List<AnswerQuality> _answerHistory = [];

  // AI-emitted suspected-concept attributions for the active subgoal,
  // oldest-first. Reseeded from persisted progress on subgoal change and
  // appended to in `recordConceptAttributions`. Trimmed on write.
  final List<ConceptAttribution> _attributions = [];

  // Quality of the most recent answer routed through `updateProgress`. The
  // feedback handlers always call `recordConceptAttributions` immediately
  // after `updateProgress`, so this field captures the quality to attach to
  // the attribution entries from the same turn.
  AnswerQuality? _lastQuality;

  // Countdown of warm-up questions left for the active subgoal. While > 0,
  // correct answers do not advance progress (the student already earned it
  // last session) but wrong/partial answers and difficulty adaptation
  // behave as in normal practice.
  int _warmupRemaining = 0;

  // Cross-subgoal state — survives advancement.
  int _hintsUsed = 0;
  ChatRequestType? _currentQuestionType;

  // Set after mastering subgoal X to issue one diagnostic on subgoal Y. If
  // the student nails it, Y is also marked mastered (fast-forward).
  bool _diagnosingNext = false;

  /// Whether the conductor is currently running warm-up questions. Exposed
  /// for tests; production code shouldn't need to read this.
  bool get isInWarmup => _warmupRemaining > 0;

  // ---- Lifecycle ----------------------------------------------------------

  Future<void> setTarget() async {
    if (DataService.goals.preferredChildGoal.value == null) {
      await _setTargetGoal();
    }
    final persisted = await _getActiveProgress();
    _resetSubgoalState(persisted: persisted);
  }

  /// Resets per-subgoal state. Recovers streak position, calibrated
  /// difficulty, and recent-answer window from [persisted] so a resumed
  /// session doesn't visually rewind or lose calibration. Also evaluates
  /// whether to start a warm-up for the new subgoal.
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
      DataService.chat.addSystemMessage(
        warmupGreetings[_rand.nextInt(warmupGreetings.length)],
      );
    }
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
    if (count > _maxWarmupQuestions) {
      count = _maxWarmupQuestions;
    }
    return count;
  }

  // ---- Question selection -------------------------------------------------

  (ChatRequestType, QuestionDifficulty) getNextQuestion() {
    if (DataService.goals.selectedChildGoal.value == null &&
        DataService.goals.preferredChildGoal.value == null) {
      return (ChatRequestType.noResult, _difficulty);
    }

    if (_diagnosingNext) {
      _currentQuestionType = ChatRequestType.writeCodeQuestion;
      return (_currentQuestionType!, QuestionDifficulty.medium);
    }

    if (!_guidingDone) {
      _currentQuestionType = ChatRequestType.guidingQuestion;
      return (_currentQuestionType!, QuestionDifficulty.easy);
    }

    final filtered = _practiceTypes
        .where((t) => t != _currentQuestionType)
        .toList(growable: false);
    final pool = filtered.isEmpty ? _practiceTypes : filtered;
    final pick = pool[_rand.nextInt(pool.length)];
    _currentQuestionType = pick;
    return (pick, _difficulty);
  }

  // ---- Guiding phase ------------------------------------------------------

  double getGuidingUnderstanding() => _guidingConfidence;

  Future<bool> guidingIsComplete(double understanding) async {
    _guidingConfidence = (_guidingConfidence + understanding).clamp(0.0, 1.0);

    if (_guidingConfidence >= 0.8) {
      _guidingDone = true;
      _guidingConfidence = 0.0;
      DataService.sound.guidingComplete();
      await _persistDisplayProgress();
      return true;
    }
    await _persistDisplayProgress();
    return false;
  }

  // ---- Practice answer ----------------------------------------------------

  /// Records [quality] and returns whether a follow-up message should be
  /// shown (instead of immediately advancing to a new exercise).
  Future<bool> updateProgress(AnswerQuality quality) async {
    _lastQuality = quality;
    if (quality == AnswerQuality.correct) {
      DataService.sound.correctAnswer();
    }

    if (_diagnosingNext) {
      return _handleDiagnosticAnswer(quality);
    }

    // Warm-up: a correct answer is a recheck — the student already earned
    // this ground last session, so suppress the positive streak bump.
    // Wrong/partial flow through normally so the existing negative delta
    // and difficulty adaptation still apply.
    final inWarmup = _warmupRemaining > 0;
    final suppressPositive = inWarmup && quality == AnswerQuality.correct;
    if (inWarmup) {
      _warmupRemaining -= 1;
    }

    final from = _displayProgress();
    if (!suppressPositive) {
      _adaptStreak(quality);
    }
    _adaptDifficulty(quality);
    _hintsUsed = 0;
    final to = _displayProgress();

    DataService.chat.addSystemMessage(
      'Vooruitgang: ${(from * 100).toStringAsFixed(0)}% -> ${(to * 100).toStringAsFixed(0)}%',
    );

    if (_isMastered()) {
      await _markMasteredAndAdvance(quality: quality, isWarmUp: inWarmup);
      return false;
    }

    await _persistDisplayProgress(quality: quality, isWarmUp: inWarmup);
    return _allowFollowUp(quality);
  }

  Future<bool> _handleDiagnosticAnswer(AnswerQuality quality) async {
    _diagnosingNext = false;
    _hintsUsed = 0;

    if (quality == AnswerQuality.correct) {
      DataService.chat.addSystemMessage(
        'Diagnostisch antwoord goed — dit subdoel wordt overgeslagen.',
      );
      await _markMasteredAndAdvance(quality: quality, isWarmUp: false);
    } else {
      DataService.chat.addSystemMessage('We pakken dit subdoel rustig op.');
    }
    return false;
  }

  bool _isMastered() =>
      _correctStreak >= _streakNeeded &&
      _typesInStreak.length >= _distinctTypesNeeded;

  Future<void> _markMasteredAndAdvance({
    AnswerQuality? quality,
    bool isWarmUp = false,
  }) async {
    final goal = _activeChildGoal;
    if (goal != null) {
      await DataService.progress.upsert(
        Progress(
          goalID: goal.id,
          progress: 1.0,
          difficulty: _difficulty,
          recentAnswers: List.unmodifiable(_answerHistory),
          recentConceptAttributions: List.unmodifiable(_attributions),
        ),
        quality: quality,
        isWarmUp: isWarmUp,
      );
      DataService.progress.currentProgress.value = 1.0;
      await _recomputeRoot();
    }
    await _handleGoalCompletion();
    if (_activeChildGoal != null) {
      _diagnosingNext = true;
    }
  }

  void _adaptStreak(AnswerQuality quality) {
    switch (quality) {
      case AnswerQuality.correct:
        _correctStreak += 1;
        if (_currentQuestionType != null) {
          _typesInStreak.add(_currentQuestionType!);
        }
      case AnswerQuality.partial:
        // Partial answers neither advance nor reset.
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
    // Streak is at the mastery threshold but `_isMastered()` didn't fire,
    // so the distinct-types requirement isn't met yet. Deny the follow-up
    // so the caller picks a fresh exercise — `getNextQuestion()` excludes
    // the current type, which is exactly what's needed to grow the set.
    if (_correctStreak >= _streakNeeded) return false;
    return true;
  }

  // ---- Difficulty adaptation ---------------------------------------------

  void _adaptDifficulty(AnswerQuality quality) {
    final previousDifficulty = _difficulty;
    _answerHistory.add(quality);
    const int window = 5;
    if (_answerHistory.length > 10) {
      _answerHistory.removeAt(0);
    }
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
      DataService.chat.addSystemMessage(
        'Moeilijkheid aangepast: ${previousDifficulty.name} -> ${_difficulty.name}',
      );
    }
  }

  void hintProvided() {
    _hintsUsed += 1;
  }

  // ---- Goal advancement ---------------------------------------------------

  Future<void> _handleGoalCompletion() async {
    final goal = _activeChildGoal;

    DataService.splash.showGoalReached(
      goalTitle: goal?.title ?? 'Onbekend doel',
      description: goal?.description ?? '',
    );
    DataService.sound.playGoalReached();

    if (DataService.goals.preferredChildGoal.value != null) {
      DataService.goals.preferredChildGoal.value = null;
      DataService.goals.preferredRootGoal.value = null;
    }
    await _setTargetGoal();
    final persisted = await _getActiveProgress();
    _resetSubgoalState(persisted: persisted);
  }

  Future<bool> _setTargetGoal() async {
    DataService.goals.selectedRootGoal.value = null;
    DataService.goals.selectedChildGoal.value = null;

    final roots = await DataService.goals.getRootGoalsOnce();
    final progressList = await DataService.progress.getAll();

    double progressFor(Goal g) {
      final p = progressList.firstWhereOrNull((x) => x.goalID == g.id);
      return p?.progress ?? 0.0;
    }

    for (final root in roots) {
      if (progressFor(root) < 1.0) {
        final subgoals = await DataService.goals.getChildrenOnce(root.id);
        final targetChild = subgoals.firstWhereOrNull(
          (g) => progressFor(g) < 1.0,
        );

        if (targetChild != null) {
          DataService.goals.selectedRootGoal.value = root;
          DataService.goals.selectedChildGoal.value = targetChild;
          DataService.progress.currentProgress.value = progressFor(targetChild);
          DataService.chat.addSystemMessage(
            'Nieuw doel geselecteerd: ${targetChild.title}',
          );
          return true;
        }
      }
    }
    DataService.progress.currentProgress.value = 0.0;
    return false;
  }

  // ---- Persistence helpers ------------------------------------------------

  Goal? get _activeChildGoal =>
      DataService.goals.preferredChildGoal.value ??
      DataService.goals.selectedChildGoal.value;

  Future<Progress?> _getActiveProgress() async {
    final goal = _activeChildGoal;
    if (goal == null) return null;
    return DataService.progress.getByGoalId(goal.id);
  }

  Future<void> _persistDisplayProgress({
    AnswerQuality? quality,
    bool isWarmUp = false,
  }) async {
    final goal = _activeChildGoal;
    if (goal == null) return;
    final pct = _displayProgress();
    await DataService.progress.upsert(
      Progress(
        goalID: goal.id,
        progress: pct,
        difficulty: _difficulty,
        recentAnswers: List.unmodifiable(_answerHistory),
        recentConceptAttributions: List.unmodifiable(_attributions),
      ),
      quality: quality,
      isWarmUp: isWarmUp,
    );
    DataService.progress.currentProgress.value = pct;
    await _recomputeRoot();
  }

  // ---- Concept attribution -----------------------------------------------

  /// Append AI-emitted suspected-concept tags from the most recent feedback
  /// turn to the active subgoal's [Progress.recentConceptAttributions].
  /// Tags not in the validation set (current root + earlier roots'
  /// `knownConcepts`) are dropped — we log them so drift stays visible in
  /// dev. No-ops on null/empty input. The list is trimmed on write.
  Future<void> recordConceptAttributions(List<String>? concepts) async {
    if (concepts == null || concepts.isEmpty) return;

    final goal = _activeChildGoal;
    if (goal == null) return;

    final rootGoal = DataService.goals.preferredRootGoal.value ??
        DataService.goals.selectedRootGoal.value;
    final allowed = rootGoal == null
        ? const <String>[]
        : await DataService.goals.getKnownConceptsInScope(rootGoal);
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
    if (DataService.goals.selectedRootGoal.value == null) return;
    final root =
        DataService.goals.preferredRootGoal.value ??
        DataService.goals.selectedRootGoal.value;
    if (root == null) return;
    final children = await DataService.goals.getChildrenOnce(root.id);
    if (children.isEmpty) return;
    double sum = 0.0;
    for (final g in children) {
      final p = await DataService.progress.getByGoalId(g.id);
      sum += (p?.progress ?? 0.0);
    }
    await DataService.progress.upsert(
      Progress(goalID: root.id, progress: sum / children.length),
      recordHistory: false,
    );
  }
}
