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

/// A concept mastery waiting for the XP stream to confirm that it actually
/// pushed the student over a level threshold (#116).
class _PendingMastery {
  _PendingMastery({
    required this.conceptName,
    required this.xpAwarded,
    required this.baseline,
  });

  final String conceptName;
  final int xpAwarded;

  /// Level observed when the mastery was armed. `null` until the first
  /// [LevelUpController.observeLevel] call — the XP stream had not produced
  /// a value yet, so the first level it reports becomes the baseline.
  int? baseline;
}

/// Holds the current pending level-up event (null when no overlay is shown).
///
/// Mutate via [push] (start the moment unconditionally) or [pushThrottled]
/// (start the moment only if at least [minGap] has passed since the last
/// push). The throttle protects the "rare, 1-2× per session" feel when a
/// chain of concept completions lands in quick succession.
///
/// A mastered concept does *not* push on its own: [armConceptMastered]
/// records it, and only an [observeLevel] reporting a level above the one
/// seen when it was armed turns it into an overlay (#116). Before that the
/// throttle was the sole gate, so the overlay fired on masteries that
/// crossed no threshold at all — and the flatter 500-XP curve would have
/// made it misfire more often, not less.
class LevelUpController extends Notifier<LevelUpEvent?> {
  static const Duration defaultMinGap = Duration(minutes: 10);

  DateTime? _lastPushAt;

  /// Most recent level reported by [observeLevel].
  int? _observedLevel;

  _PendingMastery? _pending;

  @override
  LevelUpEvent? build() => null;

  /// Arms the "a concept just got mastered" signal. The overlay follows only
  /// if the level rises afterwards; if it never does, nothing is shown.
  void armConceptMastered({
    required String conceptName,
    required int xpAwarded,
  }) {
    _pending = _PendingMastery(
      conceptName: conceptName,
      xpAwarded: xpAwarded,
      baseline: _observedLevel,
    );
  }

  /// Feeds the level derived from the XP providers. Pushes the armed
  /// mastery (throttled) the first time [level] exceeds the baseline.
  void observeLevel(int level) {
    _observedLevel = level;
    final pending = _pending;
    if (pending == null) return;
    if (pending.baseline == null) {
      pending.baseline = level;
      return;
    }
    if (level <= pending.baseline!) return;
    _pending = null;
    pushThrottled(
      LevelUpEvent(
        newLevel: level,
        xpAwarded: pending.xpAwarded,
        conceptName: pending.conceptName,
      ),
    );
  }

  void push(LevelUpEvent event) {
    _lastPushAt = DateTime.now();
    state = event;
  }

  /// Pushes [event] only if at least [minGap] has elapsed since the last
  /// push (any push, including a manual debug one). Returns true when the
  /// overlay was actually triggered.
  bool pushThrottled(LevelUpEvent event, {Duration minGap = defaultMinGap}) {
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
