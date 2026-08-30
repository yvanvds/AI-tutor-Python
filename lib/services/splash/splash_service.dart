import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the goal-reached overlay shows. Carries data only — the title and
/// the encouragement phrase are localized by the overlay (#23), so this
/// holds the phrase's index rather than its text.
class GoalSplashState {
  final String goalTitle;
  final String description;

  /// Index into the localized encouragement phrases,
  /// `0 <= phraseIndex < SplashService.phraseCount`.
  final int phraseIndex;

  const GoalSplashState({
    required this.goalTitle,
    required this.description,
    required this.phraseIndex,
  });
}

class SplashService {
  SplashService({void Function(GoalSplashState?)? onStateChanged})
    : _onStateChanged = onStateChanged;

  final void Function(GoalSplashState?)? _onStateChanged;
  GoalSplashState? _current;

  final _random = Random();

  /// Number of over-the-top encouragements in the ARB files
  /// (`splash_phrase_01` … `splash_phrase_25`).
  static const int phraseCount = 25;

  /// Call this from TutorService when a goal is reached.
  void showGoalReached({
    required String goalTitle,
    required String description,
    Duration duration = const Duration(seconds: 10),
  }) {
    final splash = GoalSplashState(
      goalTitle: goalTitle,
      description: description,
      phraseIndex: randomPhraseIndex(),
    );
    _current = splash;
    _onStateChanged?.call(splash);

    Future.delayed(duration, () {
      if (_current?.goalTitle == goalTitle) {
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
