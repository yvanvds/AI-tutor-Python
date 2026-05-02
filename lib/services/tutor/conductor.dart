import 'dart:math';

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:collection/collection.dart';

class Conductor {
  Conductor();

  // Mastery thresholds for the current subgoal.
  static const int _streakNeeded = 3;
  static const int _distinctTypesNeeded = 2;

  // Persisted floor that marks "guiding done, no practice yet" so a resumed
  // session can detect prior progress and skip guiding.
  static const double _guidingDoneMarker = 0.05;

  static const List<ChatRequestType> _practiceTypes = [
    ChatRequestType.mcQuestion,
    ChatRequestType.explainCodeQuestion,
    ChatRequestType.completeCodeQuestion,
    ChatRequestType.socraticQuestion,
    ChatRequestType.writeCodeQuestion,
  ];

  final _rand = Random();

  // Per-subgoal state — reset whenever the active subgoal changes.
  bool _guidingDone = false;
  double _guidingConfidence = 0.0;
  int _correctStreak = 0;
  final Set<ChatRequestType> _typesInStreak = {};

  // Cross-subgoal state — survives advancement.
  QuestionDifficulty _difficulty = QuestionDifficulty.easy;
  int _hintsUsed = 0;
  final List<AnswerQuality> _answerHistory = [];
  ChatRequestType? _currentQuestionType;

  // Set after mastering subgoal X to issue one diagnostic on subgoal Y. If
  // the student nails it, Y is also marked mastered (fast-forward).
  bool _diagnosingNext = false;

  // ---- Lifecycle ----------------------------------------------------------

  Future<void> setTarget() async {
    if (DataService.goals.preferredChildGoal.value == null) {
      await _setTargetGoal();
    }
    final persisted = await _getCurrentProgress();
    _resetSubgoalState(persistedProgress: persisted);
  }

  /// Resets per-subgoal state. Recovers `_guidingDone` and `_correctStreak`
  /// from [persistedProgress] so a resumed session doesn't visually rewind.
  void _resetSubgoalState({double persistedProgress = 0.0}) {
    _guidingDone = persistedProgress > 0.0;
    _guidingConfidence = 0.0;
    _correctStreak = (persistedProgress * _streakNeeded)
        .round()
        .clamp(0, _streakNeeded - 1);
    _typesInStreak.clear();
    _currentQuestionType = null;
    _diagnosingNext = false;
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
    if (quality == AnswerQuality.correct) {
      DataService.sound.correctAnswer();
    }

    if (_diagnosingNext) {
      return _handleDiagnosticAnswer(quality);
    }

    final from = _displayProgress();
    _adaptStreak(quality);
    _adaptDifficulty(quality);
    _hintsUsed = 0;
    final to = _displayProgress();

    DataService.chat.addSystemMessage(
      'Vooruitgang: ${(from * 100).toStringAsFixed(0)}% -> ${(to * 100).toStringAsFixed(0)}%',
    );

    if (_isMastered()) {
      await _markMasteredAndAdvance();
      return false;
    }

    await _persistDisplayProgress();
    return _allowFollowUp(quality);
  }

  Future<bool> _handleDiagnosticAnswer(AnswerQuality quality) async {
    _diagnosingNext = false;
    _hintsUsed = 0;

    if (quality == AnswerQuality.correct) {
      DataService.chat.addSystemMessage(
        'Diagnostisch antwoord goed — dit subdoel wordt overgeslagen.',
      );
      await _markMasteredAndAdvance();
    } else {
      DataService.chat.addSystemMessage(
        'We pakken dit subdoel rustig op.',
      );
    }
    return false;
  }

  bool _isMastered() =>
      _correctStreak >= _streakNeeded &&
      _typesInStreak.length >= _distinctTypesNeeded;

  Future<void> _markMasteredAndAdvance() async {
    final goal = _activeChildGoal;
    if (goal != null) {
      await DataService.progress.upsert(
        Progress(goalID: goal.id, progress: 1.0),
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

    final correctCount =
        recent.where((q) => q == AnswerQuality.correct).length;
    final wrongCount = recent.where((q) => q == AnswerQuality.wrong).length;
    final partialCount =
        recent.where((q) => q == AnswerQuality.partial).length;

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
    final persisted = await _getCurrentProgress();
    _resetSubgoalState(persistedProgress: persisted);
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
        final targetChild =
            subgoals.firstWhereOrNull((g) => progressFor(g) < 1.0);

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

  Future<double> _getCurrentProgress() async {
    final goal = _activeChildGoal;
    if (goal == null) return 0.0;
    final p = await DataService.progress.getByGoalId(goal.id);
    return p?.progress ?? 0.0;
  }

  Future<void> _persistDisplayProgress() async {
    final goal = _activeChildGoal;
    if (goal == null) return;
    final pct = _displayProgress();
    await DataService.progress.upsert(
      Progress(goalID: goal.id, progress: pct),
    );
    DataService.progress.currentProgress.value = pct;
    await _recomputeRoot();
  }

  Future<void> _recomputeRoot() async {
    if (DataService.goals.selectedRootGoal.value == null) return;
    final root = DataService.goals.preferredRootGoal.value ??
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
    );
  }
}
