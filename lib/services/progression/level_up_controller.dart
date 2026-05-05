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

  /// Short, lowercase Dutch concept name shown in the subtitle
  /// ("Je hebt de {concept} onder de knie."). Examples: `elif-ladder`,
  /// `for-lus`, `lijsten`.
  final String conceptName;
}

/// Holds the current pending level-up event (null when no overlay is shown).
///
/// Mutate via [push] (start the moment) and [dismiss] (close the overlay).
/// The decision *when* to push is intentionally not in this class — see
/// `TODO.md` § "Phase 6 — level-up trigger" for the open options.
class LevelUpController extends Notifier<LevelUpEvent?> {
  @override
  LevelUpEvent? build() => null;

  void push(LevelUpEvent event) => state = event;

  void dismiss() => state = null;
}

final levelUpControllerProvider =
    NotifierProvider<LevelUpController, LevelUpEvent?>(LevelUpController.new);
