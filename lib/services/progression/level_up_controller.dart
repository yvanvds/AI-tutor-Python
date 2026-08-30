import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One "level-up moment" — a rare, celebratory beat that crosses a level
/// threshold. The shell listens for non-null state and shows the overlay.
@immutable
class LevelUpEvent {
  const LevelUpEvent({
    required this.newLevel,
    required this.xpAwarded,
    required this.conceptName,
  });

  final int newLevel;
  final int xpAwarded;

  /// Short, lowercase concept name (the subgoal title as authored by the
  /// teacher) shown in the localized subtitle ("You've mastered {concept}.").
  /// Examples: `elif-ladder`, `for-lus`, `lijsten`.
  final String conceptName;
}

/// Holds the current pending level-up event (null when no overlay is shown).
///
/// Mutate via [push] (start the moment unconditionally) or [pushThrottled]
/// (start the moment only if at least [minGap] has passed since the last
/// push). The throttle protects the "rare, 1-2× per session" feel when a
/// chain of concept completions lands in quick succession.
class LevelUpController extends Notifier<LevelUpEvent?> {
  static const Duration defaultMinGap = Duration(minutes: 10);

  DateTime? _lastPushAt;

  @override
  LevelUpEvent? build() => null;

  void push(LevelUpEvent event) {
    _lastPushAt = DateTime.now();
    state = event;
  }

  /// Pushes [event] only if at least [minGap] has elapsed since the last
  /// push (any push, including a manual debug one). Returns true when the
  /// overlay was actually triggered.
  bool pushThrottled(
    LevelUpEvent event, {
    Duration minGap = defaultMinGap,
  }) {
    final now = DateTime.now();
    final last = _lastPushAt;
    if (last != null && now.difference(last) < minGap) return false;
    _lastPushAt = now;
    state = event;
    return true;
  }

  void dismiss() => state = null;
}

final levelUpControllerProvider =
    NotifierProvider<LevelUpController, LevelUpEvent?>(LevelUpController.new);
