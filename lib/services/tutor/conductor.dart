import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/data/goal/goal.dart';
import 'package:ai_tutor_python/data/goal/goal_providers.dart';
import 'package:ai_tutor_python/data/progress/progress.dart';
import 'package:ai_tutor_python/data/progress/progress_providers.dart';
import 'package:ai_tutor_python/services/tutor/responses/answer.dart';
import 'package:collection/collection.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'dart:math';

class Conductor {
  final Ref ref;
  Conductor({required this.ref});

  final _rand = Random();

  Goal? currentRootGoal;
  Goal? currentChildGoal;

  double _currentProgress = 0.0;
  QuestionDifficulty _difficulty = QuestionDifficulty.easy;
  int _hintsUsed = 0;
  List<AnswerQuality> _answerHistory = [];

  ChatRequestType? _currentQuestionType;

  Future<void> initialize() async {
    // 1. Set target goal
    await _setTargetGoal();

    // 2. Get the current progress
    _currentProgress = await _getCurrentProgress();
  }

  (ChatRequestType, QuestionDifficulty) getNextQuestion() {
    if (currentChildGoal == null) {
      return (ChatRequestType.noResult, _difficulty);
    }

    // Step 1: choose candidate pool based on progress band
    final List<ChatRequestType> candidates;
    if (_currentProgress < 0.3) {
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

    // Step 4: add light random variation in difficulty
    // Occasionally (10%) bump or lower difficulty to keep engagement
    // if (_rand.nextDouble() < 0.1) {
    //   final change = _rand.nextBool() ? 1 : -1;
    //   final newIndex = (_difficulty.index + change)
    //       .clamp(0, Difficulty.values.length - 1);
    //   _difficulty = Difficulty.values[newIndex];
    // }

    _currentQuestionType = pick;
    return (pick, _difficulty);
  }

  Future<bool> updateProgress(AnswerQuality quality) async {
    bool followUpAllowed = true; // we return this value if we allow follow-ups

    // --- 1) base delta by answer quality ---
    double baseDelta;
    switch (quality) {
      case AnswerQuality.wrong:
        baseDelta = -0.03; // small setback for wrong answers
        break;
      case AnswerQuality.partial: // (typo kept to match your enum)
        baseDelta = 0.03; // small gain for partial
        break;
      case AnswerQuality.correct:
        baseDelta = 0.07; // modest gain for correct
        break;
    }

    // --- 2) scale by question type difficulty/effort ---
    // order from small to large: mc < explain < complete < (socratic|write)
    double typeMult;
    switch (_currentQuestionType) {
      case ChatRequestType.mcQuestion:
        typeMult = 0.6;
        break;
      case ChatRequestType.explainCodeQuestion:
        typeMult = 0.8;
        break;
      case ChatRequestType.completeCodeQuestion:
        typeMult = 1.0;
        break;
      case ChatRequestType.socraticQuestion:
      case ChatRequestType.writeCodeQuestion:
        typeMult = 1.4;
        break;

      // Non-exercise interactions: keep neutral weight
      default:
        typeMult = 1.0;
        break;
    }

    // --- 3) scale by declared difficulty ---
    double diffMult;
    switch (_difficulty) {
      case QuestionDifficulty.easy:
        diffMult = 0.8;
        break;
      case QuestionDifficulty.medium:
        diffMult = 1.0;
        break;
      case QuestionDifficulty.hard:
        diffMult = 1.3;
        break;
    }

    // --- 4) penalty for hints used (each hint slightly reduces gain) ---
    // Linear penalty; clamped so we don’t invert a positive delta purely by hints.
    final double hintPenalty = 0.02 * _hintsUsed;

    double delta = baseDelta * typeMult * diffMult;
    if (delta > 0) {
      delta = (delta - hintPenalty);
      if (delta < 0)
        delta =
            0; // don’t punish a correct/partial into negative solely by hints
    } else {
      // Wrong answers can be made *slightly* worse by heavy hint usage, but bounded.
      delta = delta - (hintPenalty * 0.5);
    }

    // Clamp and apply
    double next = _currentProgress + delta;
    if (next < 0.0) next = 0.0;
    if (next > 1.0) next = 1.0;

    if (_currentProgress < 0.3 && next >= 0.3) {
      // Crossing first milestone: deny follow-up question
      followUpAllowed = false;
    } else if (_currentProgress < 0.7 && next >= 0.7) {
      // Crossing second milestone: deny follow-up question
      followUpAllowed = false;
    } else if (_currentProgress < 1.0 && next >= 1.0) {
      // wrapping to completion: deny follow-up question
      followUpAllowed = false;
    }

    _currentProgress = next;

    // --- 5) track history & adapt difficulty ---
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

    // Up-difficulty rule: doing very well recently (≥4/5 correct) and not spamming hints
    if (correctCount >= 4 &&
        _difficulty != QuestionDifficulty.hard &&
        _hintsUsed <= 1) {
      _difficulty = QuestionDifficulty.values[_difficulty.index + 1];
    }

    // Down-difficulty rule: struggling (≥3 wrong) or (≥4 not-correct) recently
    if ((wrongCount >= 3 || (wrongCount + partialCount) >= 4) &&
        _difficulty != QuestionDifficulty.easy) {
      _difficulty = QuestionDifficulty.values[_difficulty.index - 1];
    }

    // --- 6) reset hints used for next question cycle ---
    _hintsUsed = 0;
    await _updateProgress(_currentProgress);

    // 7. check for goal completion
    if (_currentProgress >= 1.0) {
      // mark goal as complete and select next
      await _setTargetGoal();

      if (currentChildGoal != null) {
        // reset progress for new goal
        _currentProgress = await _getCurrentProgress();
      }
    }

    return followUpAllowed;
  }

  void hintProvided() {
    _hintsUsed += 1;
  }

  /// Computes and selects the next target goal/subgoal.
  /// Returns true if a selection was made, false otherwise.
  Future<bool> _setTargetGoal() async {
    // Clear previous selection
    ref.read(selectedRootGoalProviderNotifier.notifier).select(null);
    ref.read(selectedChildGoalProviderNotifier.notifier).select(null);

    // Take stable snapshots
    final roots = await ref.read(rootGoalsProviderFuture.future); // List<Goal>
    final progressList = await ref.read(
      progressListProviderFuture.future,
    ); // List<Progress>

    double progressFor(Goal g) {
      final p = progressList.firstWhereOrNull((x) => x.goalID == g.id);
      return p?.progress ?? 0.0;
    }

    for (final root in roots) {
      if (progressFor(root) < 1.0) {
        // Load children for this root on demand (family provider)
        final subgoals = await ref.read(
          childGoalsByParentProviderFuture(root.id).future,
        );

        // Pick first incomplete subgoal (if any)
        final targetChild = subgoals.firstWhereOrNull(
          (g) => progressFor(g) < 1.0,
        );

        if (targetChild != null) {
          ref.read(selectedRootGoalProviderNotifier.notifier).select(root.id);
          ref
              .read(selectedChildGoalProviderNotifier.notifier)
              .select(targetChild.id);
          currentRootGoal = root;
          currentChildGoal = targetChild;
          return true;
        }
        // else: all children complete -> try next root
      }
    }

    // Nothing to select
    currentChildGoal = null;
    currentRootGoal = null;
    return false;
  }

  // --- helpers / progress ---

  Future<double> _getCurrentProgress() async {
    final progress = await ref.read(
      progressByGoalProviderFuture(currentChildGoal?.id ?? '').future,
    );

    if (progress == null) {
      return 0.0;
    } else {
      return progress.progress;
    }
  }

  Future<void> _updateProgress(double newProgress) async {
    if (currentChildGoal == null) return;

    // 1) Upsert child
    await ref.read(
      upsertProgressProviderFuture(
        Progress(goalID: currentChildGoal!.id, progress: newProgress),
      ).future,
    );

    ref.invalidate(progressByGoalProviderFuture);

    if (currentRootGoal == null) return;

    // 2) Read child goals under the current root (provider names are examples)
    final children = await ref.read(
      childGoalsByParentProviderFuture(currentRootGoal!.id).future,
    );

    // 3) Sum each child’s progress (missing -> 0.0)
    double sum = 0.0;
    for (final g in children) {
      final p = await ref.read(
        progressByGoalProviderFuture(g.id).future,
      ); // Progress?
      sum += (p?.progress ?? 0.0);
    }
    final rootAvg = sum / children.length;

    // 4) Upsert root
    await ref.read(
      upsertProgressProviderFuture(
        Progress(goalID: currentRootGoal!.id, progress: rootAvg),
      ).future,
    );
  }
}
