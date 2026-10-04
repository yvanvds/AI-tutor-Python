import 'package:ai_tutor_python/features/shell/shell_state.dart'
    show kXpPerOefening, levelForXp;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One "level-up moment" — a rare, celebratory beat that crosses a level
/// threshold. The shell listens for non-null state and shows the overlay.
///
/// Two kinds (#217): a concept mastery that pushed the level over the
/// threshold names the concept; any other crossing — almost always the XP an
/// oefening is worth — says how many oefeningen the student has made
/// ([oefeningCount] is set).
@immutable
class LevelUpEvent {
  const LevelUpEvent({
    required this.newLevel,
    required this.xpAwarded,
    required this.conceptName,
    this.goalId,
  }) : oefeningCount = null;

  /// A level reached by making oefeningen (#217): [oefeningCount] is how
  /// many the student has made so far, [xpAwarded] what one is worth.
  const LevelUpEvent.oefeningen({
    required this.newLevel,
    required this.xpAwarded,
    required int this.oefeningCount,
  }) : conceptName = '',
       goalId = null;

  final int newLevel;
  final int xpAwarded;

  /// Short, lowercase concept name (the subgoal title as authored by the
  /// teacher, in Dutch) shown in the localized subtitle ("You've mastered
  /// {concept}.") when [goalId] has no translation into the app language.
  /// Examples: `elif-ladder`, `for-lus`, `lijsten`. Empty for an
  /// [LevelUpEvent.oefeningen] moment.
  final String conceptName;

  /// The mastered subgoal, so the overlay names it in the app language
  /// (#211). `null` for a moment that is not about a goal (the debug push,
  /// an oefeningen level-up): then [conceptName] is shown as it is.
  final String? goalId;

  /// How many oefeningen the student has made, for a level reached by
  /// making them (#217); `null` for a concept mastery.
  final int? oefeningCount;

  /// Whether this level came from oefeningen rather than a mastered concept.
  bool get fromOefeningen => oefeningCount != null;
}

/// Something that happened this session and may lift the level once the XP
/// providers report it: a mastered concept, or an oefening counted (#217).
/// [baseline] is the level observed when it was armed — `null` until the
/// first [LevelUpController.observeXp] call, whose level then becomes it.
class _Armed {
  _Armed({this.baseline});
  int? baseline;
}

/// A concept mastery waiting for the XP stream to confirm that it actually
/// pushed the student over a level threshold (#116).
class _PendingMastery extends _Armed {
  _PendingMastery({
    required this.conceptName,
    required this.goalId,
    required this.xpAwarded,
    super.baseline,
  });

  final String conceptName;
  final String? goalId;
  final int xpAwarded;
}

/// What the XP providers reported last.
typedef _Observed = ({int level, int oefeningCount, int masteryXp});

/// Holds the current pending level-up event (null when no overlay is shown).
///
/// Mutate via [push] (start the moment unconditionally) or [pushThrottled]
/// (start the moment only if at least [minGap] has passed since the last
/// push). The throttle protects the "rare, 1-2× per session" feel when a
/// chain of crossings lands in quick succession.
///
/// Nothing pushes on its own: [armConceptMastered] and [armOefening] record
/// that something this session may lift the level, and only an [observeXp]
/// reporting a level above the one seen when it was armed turns that into an
/// overlay (#116). A crossing nothing armed — the first report after start,
/// a sign-in, the counter filled in from outside — is not celebrated.
///
/// Which overlay (#217): the concept's, when a concept mastery is armed and
/// the mastery XP itself crossed the threshold; otherwise the oefeningen
/// one, which says how many the student has made. One crossing spends
/// everything armed.
class LevelUpController extends Notifier<LevelUpEvent?> {
  static const Duration defaultMinGap = Duration(minutes: 10);

  DateTime? _lastPushAt;

  _Observed? _observed;

  _PendingMastery? _pendingMastery;
  _Armed? _pendingOefening;

  @override
  LevelUpEvent? build() => null;

  /// Arms the "a concept just got mastered" signal. The overlay follows only
  /// if the level rises afterwards; if it never does, nothing is shown.
  /// [conceptName] is the subgoal's Dutch title, [goalId] its id.
  void armConceptMastered({
    required String conceptName,
    String? goalId,
    required int xpAwarded,
  }) {
    _pendingMastery = _PendingMastery(
      conceptName: conceptName,
      goalId: goalId,
      xpAwarded: xpAwarded,
      baseline: _observed?.level,
    );
  }

  /// Arms the "an oefening was just counted" signal (#217) — the tutor calls
  /// it for every first graded answer to a question. An oefening already
  /// armed keeps its baseline: after a dip in the mastery XP the level must
  /// climb past where it stood, not just back to it, to count as a new one.
  void armOefening() {
    _pendingOefening ??= _Armed(baseline: _observed?.level);
  }

  /// Feeds the two parts of the XP the providers derive. Pushes (throttled)
  /// the first time the level exceeds the baseline of something armed.
  void observeXp({required int oefeningCount, required int masteryXp}) {
    final level = levelForXp(oefeningCount * kXpPerOefening + masteryXp);
    final previous = _observed;
    _observed = (
      level: level,
      oefeningCount: oefeningCount,
      masteryXp: masteryXp,
    );

    final mastery = _pendingMastery;
    final oefening = _pendingOefening;
    for (final armed in [mastery, oefening]) {
      if (armed != null && armed.baseline == null) armed.baseline = level;
    }
    bool crossed(_Armed? a) => a != null && level > a.baseline!;
    final masteryArmedCrossed = crossed(mastery);
    if (!masteryArmedCrossed && !crossed(oefening)) return;

    _pendingMastery = null;
    _pendingOefening = null;

    // The mastery crossed the threshold itself when its new XP, on the
    // oefeningen counted before, already reaches a level above the last
    // one reported. The two parts arrive on separate polls, so a crossing
    // is nearly always one or the other.
    final masteryItselfCrossed =
        previous != null &&
        levelForXp(previous.oefeningCount * kXpPerOefening + masteryXp) >
            previous.level;
    if (mastery != null && masteryArmedCrossed && masteryItselfCrossed) {
      pushThrottled(
        LevelUpEvent(
          newLevel: level,
          xpAwarded: mastery.xpAwarded,
          conceptName: mastery.conceptName,
          goalId: mastery.goalId,
        ),
      );
      return;
    }
    pushThrottled(
      LevelUpEvent.oefeningen(
        newLevel: level,
        xpAwarded: kXpPerOefening,
        oefeningCount: oefeningCount,
      ),
    );
  }

  /// Forgets what was armed and observed, for the next student to sign in
  /// on this app: their level is not compared against the last one's. The
  /// throttle stays.
  void reset() {
    _observed = null;
    _pendingMastery = null;
    _pendingOefening = null;
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
