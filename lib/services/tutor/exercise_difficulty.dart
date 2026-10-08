import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/student_state/student_calibration.dart';
import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the level in the top bar's difficulty chip comes from (#256).
enum DifficultySource {
  /// No exercise on screen: the account's calibration, the level the tutor
  /// asks its questions at. The chip shows it dimmed.
  calibration,

  /// The question on screen, at the level its plan set — the calibration,
  /// for an ordinary probe (CONDUCTOR_POLICY §2.3).
  plan,

  /// The question on screen, one level below the calibration for its LO:
  /// a notch-drop fired when it was planned (§2.3).
  notchDrop,

  /// A follow-up question (§6): dialogue, not a calibrated probe, and
  /// always treated as `medium` (§6.2).
  followUp,
}

/// A level the top bar's difficulty chip shows (#256), and where it comes
/// from.
@immutable
class ExerciseDifficulty {
  const ExerciseDifficulty(this.difficulty, this.source);

  /// The level of the question [plan] put on screen.
  factory ExerciseDifficulty.ofPlan(QuestionPlan plan) => ExerciseDifficulty(
    plan.difficulty,
    plan.reason.notchDropFired
        ? DifficultySource.notchDrop
        : DifficultySource.plan,
  );

  /// A follow-up question on screen (CONDUCTOR_POLICY §6): always `medium`.
  static const ExerciseDifficulty followUp = ExerciseDifficulty(
    QuestionDifficulty.medium,
    DifficultySource.followUp,
  );

  final QuestionDifficulty difficulty;
  final DifficultySource source;

  /// Whether this is the level of an exercise on screen, rather than the
  /// account's calibration.
  bool get onScreen => source != DifficultySource.calibration;

  @override
  bool operator ==(Object other) =>
      other is ExerciseDifficulty &&
      other.difficulty == difficulty &&
      other.source == source;

  @override
  int get hashCode => Object.hash(difficulty, source);

  @override
  String toString() => 'ExerciseDifficulty(${difficulty.name}, ${source.name})';
}

/// The level of the question the student has in front of them (#256), as
/// the tutor put it there: its plan's level — a notch-drop included — or
/// `medium` for a follow-up. The plan itself stays private to the tutor.
///
/// Set by `TutorService` when the question comes in — generated or from the
/// bank — and when a follow-up is presented; cleared with the question's ID
/// (`shownQuestionIdProvider`, #216), when the next question is planned or
/// the quiz is dismissed. `null` before the first question.
final shownQuestionDifficultyProvider = StateProvider<ExerciseDifficulty?>(
  (_) => null,
);

/// The signed-in account's calibration (STUDENT_MODEL): the level the tutor
/// asks its questions at. `medium`, the starting value, while signed out.
final calibrationDifficultyProvider = Provider<QuestionDifficulty>(
  (ref) => ref.watch(
    accountServiceProvider.select(
      (a) => a?.calibration.difficulty ?? StudentCalibration.defaultDifficulty,
    ),
  ),
);

/// What the top bar's difficulty chip shows (#256): the level of the
/// exercise on screen — [shownQuestionDifficultyProvider], while the
/// student is in Practice — and otherwise, in Explain, the Playground, on
/// another page or before the first question, the account's calibration.
final exerciseDifficultyProvider = Provider<ExerciseDifficulty>((ref) {
  final calibration = ExerciseDifficulty(
    ref.watch(calibrationDifficultyProvider),
    DifficultySource.calibration,
  );
  final shown = ref.watch(shownQuestionDifficultyProvider);
  if (shown == null) return calibration;
  final inPractice =
      ref.watch(sectionProvider) == Section.session &&
      ref.watch(modeProvider) == SessionMode.practice;
  return inPractice ? shown : calibration;
});
