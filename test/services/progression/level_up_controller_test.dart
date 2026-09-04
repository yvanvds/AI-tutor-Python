// Issue #116 — a mastered concept only becomes a level-up overlay when the
// level actually crosses. Before this, `_onConceptMastered` pushed on every
// mastered concept goal and the 10-minute throttle was the only gate, so the
// "Level N" celebration fired for masteries that moved no threshold at all —
// and it named the level the student was already on.
//
// The XP the mastery is worth reaches the provider on the next progress
// poll, which is why the crossing is checked against a *later* level report
// rather than one read at mastery time.

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

  test('a mastered concept that crosses no threshold shows nothing', () {
    final c = controller();
    c.observeLevel(1);
    c.armConceptMastered(conceptName: 'elif-ladder', xpAwarded: 100);
    // The XP landed, but 100 of 500 is not a level.
    c.observeLevel(1);
    expect(event(), isNull);
  });

  test('the overlay follows the level report that crosses', () {
    final c = controller();
    c.observeLevel(1);
    c.armConceptMastered(conceptName: 'elif-ladder', xpAwarded: 100);
    c.observeLevel(2);

    expect(event(), isNotNull);
    expect(event()!.newLevel, 2);
    expect(event()!.conceptName, 'elif-ladder');
    expect(event()!.xpAwarded, 100);
  });

  test('a crossing with nothing armed is not a celebration on its own', () {
    final c = controller();
    c.observeLevel(1);
    c.observeLevel(2);
    expect(event(), isNull);
  });

  test('one armed mastery is spent on one crossing', () {
    final c = controller();
    c.observeLevel(1);
    c.armConceptMastered(conceptName: 'for-lus', xpAwarded: 100);
    c.observeLevel(2);
    expect(event(), isNotNull);

    c.dismiss();
    // A later crossing that no mastery armed stays silent.
    c.observeLevel(3);
    expect(event(), isNull);
  });

  test(
    'the first level report after arming is the baseline, not a crossing',
    () {
      // The XP stream had not produced a value yet when the concept was
      // mastered, so the level it first reports is where the student *is*.
      final c = controller();
      c.armConceptMastered(conceptName: 'lijsten', xpAwarded: 100);
      c.observeLevel(4);
      expect(event(), isNull);

      c.observeLevel(5);
      expect(event()!.newLevel, 5);
    },
  );

  test('the throttle still gates a genuine crossing', () {
    final c = controller();
    c.observeLevel(1);
    c.armConceptMastered(conceptName: 'elif-ladder', xpAwarded: 100);
    c.observeLevel(2);
    expect(event()!.conceptName, 'elif-ladder');
    c.dismiss();

    c.armConceptMastered(conceptName: 'for-lus', xpAwarded: 100);
    c.observeLevel(3);
    expect(
      event(),
      isNull,
      reason:
          'a second crossing inside the 10-minute gap re-opened the '
          'overlay',
    );
  });

  test('push is unconditional — the developer trigger still works', () {
    final c = controller();
    c.observeLevel(1);
    c.push(
      const LevelUpEvent(newLevel: 5, xpAwarded: 20, conceptName: 'debug'),
    );
    expect(event()!.newLevel, 5);
  });
}
