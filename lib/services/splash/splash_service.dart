import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the goal-reached overlay shows. Carries data only — the title and
/// the encouragement phrase are localized by the overlay (#23), so this
/// holds the phrase's index rather than its text, and the goal's id next to
/// its Dutch text: the overlay shows the goal in the app language (#211).
class GoalSplashState {
  /// The subgoal that was reached.
  final String goalId;

  /// [goalId]'s Dutch title and description as they were when it was
  /// reached: what the overlay shows when the goal has no translation into
  /// the app language.
  final String goalTitle;
  final String description;

  /// Index into the localized encouragement phrases,
  /// `0 <= phraseIndex < SplashService.phraseCount`.
  final int phraseIndex;

  const GoalSplashState({
    required this.goalId,
    required this.goalTitle,
    required this.description,
    required this.phraseIndex,
  });
}

class SplashService {
  SplashService({this._onStateChanged});

  final void Function(GoalSplashState?)? _onStateChanged;
  GoalSplashState? _current;

  final _random = Random();

  /// Number of over-the-top encouragements in the ARB files
  /// (`splash_phrase_01` … `splash_phrase_25`).
  static const int phraseCount = 25;

  /// Call this from TutorService when a goal is reached, with the goal's
  /// id and its Dutch title and description.
  void showGoalReached({
    required String goalId,
    required String goalTitle,
    required String description,
    Duration duration = const Duration(seconds: 10),
  }) {
    final splash = GoalSplashState(
      goalId: goalId,
      goalTitle: goalTitle,
      description: description,
      phraseIndex: randomPhraseIndex(),
    );
    _current = splash;
    _onStateChanged?.call(splash);

    Future.delayed(duration, () {
      if (_current?.goalId == goalId) {
        _current = null;
        _onStateChanged?.call(null);
      }
    });
  }

  void hide() {
    _current = null;
    _onStateChanged?.call(null);
  }

  int randomPhraseIndex() => _random.nextInt(phraseCount);
}

final splashStateProvider = StateProvider<GoalSplashState?>((_) => null);

final splashServiceProvider = Provider<SplashService>((ref) {
  return SplashService(
    onStateChanged: (s) => ref.read(splashStateProvider.notifier).state = s,
  );
});
