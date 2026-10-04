// Issue #116 — a mastered concept only becomes a level-up overlay when the
// level actually crosses. Before this, `_onConceptMastered` pushed on every
// mastered concept goal and the 10-minute throttle was the only gate, so the
// "Level N" celebration fired for masteries that moved no threshold at all —
// and it named the level the student was already on.
//
// The XP the mastery is worth reaches the provider on the next progress
// poll, which is why the crossing is checked against a *later* level report
// rather than one read at mastery time.
//
// Issue #217 — every oefening is worth 20 XP, so most crossings now come
// from the oefening counter on the account doc, on its own poll. Such a
// crossing gets its own moment ("Level N · al X oefeningen gemaakt"); the
// concept's moment is kept for a crossing the mastery XP itself made.

import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/progression/level_up_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });
  tearDown(() => container.dispose());

  LevelUpController controller() =>
      container.read(levelUpControllerProvider.notifier);
  LevelUpEvent? event() => container.read(levelUpControllerProvider);

  /// A report of level [level] made of mastery XP alone — what the #116
  /// tests are about.
  void at(LevelUpController c, int level) =>
      c.observeXp(oefeningCount: 0, masteryXp: (level - 1) * kXpPerLevel);

  test('a mastered concept that crosses no threshold shows nothing', () {
    final c = controller();
    at(c, 1);
    c.armConceptMastered(conceptName: 'elif-ladder', xpAwarded: 100);
    // The XP landed, but 100 of 500 is not a level.
    at(c, 1);
    expect(event(), isNull);
  });

  test('the overlay follows the level report that crosses', () {
    final c = controller();
    at(c, 1);
    c.armConceptMastered(
      conceptName: 'elif-ladder',
      goalId: 's-elif',
      xpAwarded: 100,
    );
    at(c, 2);

    expect(event(), isNotNull);
    expect(event()!.newLevel, 2);
    expect(event()!.conceptName, 'elif-ladder');
    // #211: the goal's id travels along, so the overlay can name the
    // concept in the app language.
    expect(event()!.goalId, 's-elif');
    expect(event()!.xpAwarded, 100);
  });

  test('a crossing with nothing armed is not a celebration on its own', () {
    final c = controller();
    at(c, 1);
    at(c, 2);
    expect(event(), isNull);
  });

  test('one armed mastery is spent on one crossing', () {
    final c = controller();
    at(c, 1);
    c.armConceptMastered(conceptName: 'for-lus', xpAwarded: 100);
    at(c, 2);
    expect(event(), isNotNull);

    c.dismiss();
    // A later crossing that no mastery armed stays silent.
    at(c, 3);
    expect(event(), isNull);
  });

  test(
    'the first level report after arming is the baseline, not a crossing',
    () {
      // The XP stream had not produced a value yet when the concept was
      // mastered, so the level it first reports is where the student *is*.
      final c = controller();
      c.armConceptMastered(conceptName: 'lijsten', xpAwarded: 100);
      at(c, 4);
      expect(event(), isNull);

      at(c, 5);
      expect(event()!.newLevel, 5);
    },
  );

  test('the throttle still gates a genuine crossing', () {
    final c = controller();
    at(c, 1);
    c.armConceptMastered(conceptName: 'elif-ladder', xpAwarded: 100);
    at(c, 2);
    expect(event()!.conceptName, 'elif-ladder');
    c.dismiss();

    c.armConceptMastered(conceptName: 'for-lus', xpAwarded: 100);
    at(c, 3);
    expect(
      event(),
      isNull,
      reason:
          'a second crossing inside the 10-minute gap re-opened the '
          'overlay',
    );
  });

  group('oefeningen (#217)', () {
    test('an oefening whose XP crosses the threshold shows the oefeningen '
        'moment, with the count', () {
      final c = controller();
      c.observeXp(oefeningCount: 24, masteryXp: 0); // 480 XP
      c.armOefening();
      c.observeXp(oefeningCount: 25, masteryXp: 0); // 500 XP

      final e = event()!;
      expect(e.fromOefeningen, isTrue);
      expect(e.newLevel, 2);
      expect(e.oefeningCount, 25);
      expect(e.xpAwarded, kXpPerOefening);
      expect(e.conceptName, isEmpty);
      expect(e.goalId, isNull);
    });

    test('an oefening that crosses nothing shows nothing', () {
      final c = controller();
      c.observeXp(oefeningCount: 10, masteryXp: 0);
      c.armOefening();
      c.observeXp(oefeningCount: 11, masteryXp: 0);
      expect(event(), isNull);
    });

    test('a count that jumps with nothing armed — the first report, a '
        'sign-in, the counter filled in from turn_history — is no moment', () {
      final c = controller();
      c.observeXp(oefeningCount: 3, masteryXp: 0);
      c.observeXp(oefeningCount: 140, masteryXp: 300);
      expect(event(), isNull);
    });

    test('a concept armed, but the oefening count crossed first: the '
        'oefeningen moment, and the mastery XP after it shows nothing', () {
      final c = controller();
      c.observeXp(oefeningCount: 24, masteryXp: 0);
      c.armOefening();
      c.armConceptMastered(conceptName: 'for-lus', xpAwarded: 100);
      // The account poll lands before the progress poll.
      c.observeXp(oefeningCount: 25, masteryXp: 0);
      expect(event()!.fromOefeningen, isTrue);
      expect(event()!.oefeningCount, 25);
      c.dismiss();

      c.observeXp(oefeningCount: 25, masteryXp: 100);
      expect(event(), isNull);
    });

    test('a concept whose own mastery XP crosses gets the concept moment, '
        'though an oefening was counted with it', () {
      final c = controller();
      c.observeXp(oefeningCount: 20, masteryXp: 0); // 400
      c.armOefening();
      c.armConceptMastered(
        conceptName: 'elif-ladder',
        goalId: 's-elif',
        xpAwarded: 100,
      );
      c.observeXp(oefeningCount: 21, masteryXp: 0); // 420: no crossing yet
      expect(event(), isNull);
      c.observeXp(oefeningCount: 21, masteryXp: 100); // 520

      final e = event()!;
      expect(e.fromOefeningen, isFalse);
      expect(e.newLevel, 2);
      expect(e.conceptName, 'elif-ladder');
      expect(e.goalId, 's-elif');
    });

    test('a crossing by the mastery of a subgoal that is no concept is the '
        'oefeningen moment', () {
      final c = controller();
      c.observeXp(oefeningCount: 20, masteryXp: 0);
      c.armOefening();
      c.observeXp(oefeningCount: 20, masteryXp: 100);
      expect(event()!.fromOefeningen, isTrue);
      expect(event()!.oefeningCount, 20);
    });

    test('after a dip in the mastery XP the level has to climb past where it '
        'stood, not just back to it', () {
      final c = controller();
      c.observeXp(oefeningCount: 0, masteryXp: 1000); // level 3
      c.armOefening();
      c.observeXp(oefeningCount: 0, masteryXp: 900); // an LO fell back: 2
      c.armOefening();
      c.observeXp(oefeningCount: 5, masteryXp: 900); // 1000: level 3 again
      expect(event(), isNull);
      c.armOefening();
      c.observeXp(oefeningCount: 30, masteryXp: 900); // 1500: level 4
      expect(event()!.newLevel, 4);
    });

    test('the throttle is shared by both moments', () {
      final c = controller();
      at(c, 1);
      c.armConceptMastered(conceptName: 'lijsten', xpAwarded: 100);
      at(c, 2);
      expect(event()!.fromOefeningen, isFalse);
      c.dismiss();

      c.armOefening();
      c.observeXp(oefeningCount: 25, masteryXp: kXpPerLevel); // level 3
      expect(event(), isNull, reason: 'inside the 10-minute gap');
    });

    test("reset forgets the last student's level, so the next one's "
        'crossing is measured from their own', () {
      final c = controller();
      c.observeXp(oefeningCount: 0, masteryXp: 3000); // level 7
      c.armOefening();
      c.reset();

      // Another student signs in at level 3 and counts an oefening.
      c.observeXp(oefeningCount: 0, masteryXp: 1000);
      c.armOefening();
      c.observeXp(oefeningCount: 25, masteryXp: 1000); // 1500: level 4
      expect(event()!.newLevel, 4);
    });
  });

  test('push is unconditional — the developer trigger still works', () {
    final c = controller();
    at(c, 1);
    c.push(
      const LevelUpEvent(newLevel: 5, xpAwarded: 20, conceptName: 'debug'),
    );
    expect(event()!.newLevel, 5);
  });
}
