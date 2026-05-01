import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:collection/collection.dart';
import 'dart:math';

class Conductor {
  Conductor();

  static const double _followUpDenialChance = 0.35;

  final _rand = Random();

  double _currentProgress = 0.0;
  double _guidingUnderstanding = 0.0; // used to move on from guiding questions

  QuestionDifficulty _difficulty = QuestionDifficulty.easy;
  int _hintsUsed = 0;
  List<AnswerQuality> _answerHistory = [];

  ChatRequestType? _currentQuestionType;

  Future<void> setTarget() async {
    if (DataService.goals.preferredChildGoal.value == null) {
      // 1. Set target goal
      await _setTargetGoal();
    }

    // 2. Get the current progress
    _currentProgress = await _getCurrentProgress();
  }

  (ChatRequestType, QuestionDifficulty) getNextQuestion() {
    if (DataService.goals.selectedChildGoal.value == null &&
        DataService.goals.preferredChildGoal.value == null) {
      return (ChatRequestType.noResult, _difficulty);
    }

    // Step 1: choose candidate pool based on progress band
    final List<ChatRequestType> candidates;
    _currentProgress = DataService.progress.currentProgress.value;

    if (_currentProgress < 0.2) {
      candidates = const [ChatRequestType.guidingQuestion];
    } else if (_currentProgress < 0.4) {
      candidates = const [
        ChatRequestType.mcQuestion,
        ChatRequestType.explainCodeQuestion,
      ];
    } else if (_currentProgress < 0.7) {
      candidates = const [
        ChatRequestType.completeCodeQuestion,
        ChatRequestType.socraticQuestion,
      ];
    } else {
      candidates = const [
        ChatRequestType.writeCodeQuestion,
        ChatRequestType.socraticQuestion,
      ];
    }

    // Step 2: filter out the current type (avoid back-to-back repeats)
    final filtered = candidates
        .where((type) => type != _currentQuestionType)
        .toList(growable: false);

    // Step 3: pick random from remaining (fallback to full set if needed)
    ChatRequestType pick;
    if (filtered.isNotEmpty) {
      pick = filtered[_rand.nextInt(filtered.length)];
    } else {
      pick = candidates[_rand.nextInt(candidates.length)];
    }

    _currentQuestionType = pick;
    return (pick, _difficulty);
  }

  double getGuidingUnderstanding() {
    return _guidingUnderstanding;
  }

  Future<bool> guidingIsComplete(double understanding) async {
    _currentProgress = DataService.progress.currentProgress.value;
    _guidingUnderstanding += understanding;

    // updating progress here is just to give the student
    // an indication that something progresses
    // We divide the max value (1) by 5 so we can never get above 0.2 at this point
    final previousProgress = _currentProgress;

    if (_guidingUnderstanding >= 0.8) {
      _currentProgress = 0.2;
    } else {
      _currentProgress = (_guidingUnderstanding / 5);
    }

    DataService.chat.addSystemMessage(
      'Vooruitgang: ${(previousProgress * 100).toStringAsFixed(1)}% -> ${(_currentProgress * 100).toStringAsFixed(1)}%',
    );

    await _updateProgress(_currentProgress);

    if (_guidingUnderstanding >= 0.8) {
      _guidingUnderstanding = 0.0;
      DataService.sound.guidingComplete();
      return true;
    }
    return false;
  }

  Future<bool> updateProgress(AnswerQuality quality) async {
    if (quality == AnswerQuality.correct) {
      DataService.sound.correctAnswer();
    }

    final double start = DataService.progress.currentProgress.value;
    final double delta = _computeDelta(quality);
    final double next = (start + delta).clamp(0.0, 1.0);
    bool followUpAllowed = !_crossesMilestone(start, next);

    DataService.chat.addSystemMessage(
      'Vooruitgang: ${(start * 100).toStringAsFixed(1)}% -> ${(next * 100).toStringAsFixed(1)}%',
    );
    _currentProgress = next;
    _adaptDifficulty(quality);
    _hintsUsed = 0;
    await _updateProgress(next);

    if (next >= 1.0) await _handleGoalCompletion();
    return _rollFollowUpAllowance(followUpAllowed);
  }

  /// Returns the signed progress delta for [quality], scaled by question
  /// type, declared difficulty, and a hint-usage penalty.
  double _computeDelta(AnswerQuality quality) {
    final double baseDelta = switch (quality) {
      AnswerQuality.wrong => -0.05,
      AnswerQuality.partial => 0.07,
      AnswerQuality.correct => 0.14,
    };

    // order from small to large: mc < explain < complete < (socratic|write)
    final double typeMult = switch (_currentQuestionType) {
      ChatRequestType.mcQuestion => 0.7,
      ChatRequestType.explainCodeQuestion => 0.9,
      ChatRequestType.completeCodeQuestion => 1.2,
      ChatRequestType.socraticQuestion ||
      ChatRequestType.writeCodeQuestion => 1.4,
      _ => 1.0, // non-exercise interactions: neutral weight
    };

    final double diffMult = switch (_difficulty) {
      QuestionDifficulty.easy => 0.8,
      QuestionDifficulty.medium => 1.0,
      QuestionDifficulty.hard => 1.5,
    };

    final double hintPenalty = 0.02 * _hintsUsed;

    double delta = baseDelta * typeMult * diffMult;
    if (delta > 0) {
      // don't punish a correct/partial into negative solely by hints
      delta = (delta - hintPenalty).clamp(0.0, double.infinity);
    } else {
      // wrong answers can be made slightly worse by heavy hint usage, bounded
      delta = delta - (hintPenalty * 0.5);
    }
    return delta;
  }

  /// True when [from] -> [to] newly crosses any of the {0.3, 0.7, 1.0} thresholds.
  bool _crossesMilestone(double from, double to) {
    const milestones = [0.3, 0.7, 1.0];
    return milestones.any((m) => from < m && to >= m);
  }

  /// Records [quality] in the recent-answer window and applies up/down
  /// difficulty rules, emitting a system message when difficulty changes.
  void _adaptDifficulty(AnswerQuality quality) {
    final previousDifficulty = _difficulty;
    _answerHistory.add(quality);
    const int window = 5;
    if (_answerHistory.length > 10) {
      _answerHistory.removeAt(0); // keep recent 10
    }
    final recent = _answerHistory.length <= window
        ? List<AnswerQuality>.from(_answerHistory)
        : _answerHistory.sublist(_answerHistory.length - window);

    final int correctCount = recent
        .where((q) => q == AnswerQuality.correct)
        .length;
    final int wrongCount = recent.where((q) => q == AnswerQuality.wrong).length;
    final int partialCount = recent
        .where((q) => q == AnswerQuality.partial)
        .length;

    // Up-difficulty: doing very well recently (≥4/5 correct) without spamming hints
    if (correctCount >= 4 &&
        _difficulty != QuestionDifficulty.hard &&
        _hintsUsed <= 1) {
      _difficulty = QuestionDifficulty.values[_difficulty.index + 1];
    }

    // Down-difficulty: struggling (≥3 wrong) or (≥4 not-correct) recently
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

  /// Plays the goal-completion feedback, clears any preferred goal, picks the
  /// next target goal, and resets [_currentProgress] to that goal's progress.
  Future<void> _handleGoalCompletion() async {
    final goal =
        DataService.goals.preferredChildGoal.value ??
        DataService.goals.selectedChildGoal.value;

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

    if (DataService.goals.selectedChildGoal.value != null) {
      _currentProgress = await _getCurrentProgress();
    }
  }

  /// Probabilistically denies an otherwise-allowed follow-up to keep variety.
  bool _rollFollowUpAllowance(bool currentlyAllowed) {
    if (_rand.nextDouble() < _followUpDenialChance) return false;
    return currentlyAllowed;
  }

  void hintProvided() {
    _hintsUsed += 1;
  }

  /// Computes and selects the next target goal/subgoal.
  /// Returns true if a selection was made, false otherwise.
  Future<bool> _setTargetGoal() async {
    // Clear previous selection
    DataService.goals.selectedRootGoal.value = null;
    DataService.goals.selectedChildGoal.value = null;

    // Take stable snapshots
    final roots = await DataService.goals.getRootGoalsOnce(); // List<Goal>
    final progressList = await DataService.progress.getAll(); // List<Progress>

    double progressFor(Goal g) {
      final p = progressList.firstWhereOrNull((x) => x.goalID == g.id);
      return p?.progress ?? 0.0;
    }

    for (final root in roots) {
      if (progressFor(root) < 1.0) {
        // Load children for this root on demand (family provider)
        final subgoals = await DataService.goals.getChildrenOnce(root.id);

        // Pick first incomplete subgoal (if any)
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
        // else: all children complete -> try next root
      }
    }
    DataService.progress.currentProgress.value = 0.0;
    return false;
  }

  // --- helpers / progress ---

  Future<double> _getCurrentProgress() async {
    final currentChildGoal =
        DataService.goals.preferredChildGoal.value ??
        DataService.goals.selectedChildGoal.value;
    if (currentChildGoal == null) return 0.0;
    final progress = await DataService.progress.getByGoalId(
      currentChildGoal.id,
    );
    return progress?.progress ?? 0.0;
  }

  Future<void> _updateProgress(double newProgress) async {
    if (DataService.goals.selectedChildGoal.value == null &&
        DataService.goals.preferredChildGoal.value == null)
      return;

    // 1) Upsert child
    final currentChildGoal =
        DataService.goals.preferredChildGoal.value ??
        DataService.goals.selectedChildGoal.value;
    await DataService.progress.upsert(
      Progress(goalID: currentChildGoal!.id, progress: newProgress),
    );
    DataService.progress.currentProgress.value = newProgress;

    if (DataService.goals.selectedRootGoal.value == null) return;

    final currentRootGoal =
        DataService.goals.preferredRootGoal.value ??
        DataService.goals.selectedRootGoal.value;

    // 2) Read child goals under the current root (provider names are examples)
    final children = await DataService.goals.getChildrenOnce(
      currentRootGoal!.id,
    );

    // 3) Sum each child’s progress (missing -> 0.0)
    double sum = 0.0;
    for (final g in children) {
      final p = await DataService.progress.getByGoalId(g.id);
      sum += (p?.progress ?? 0.0);
    }
    final rootAvg = sum / children.length;

    // 4) Upsert root
    await DataService.progress.upsert(
      Progress(goalID: currentRootGoal.id, progress: rootAvg),
    );
  }
}
