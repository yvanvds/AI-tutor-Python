// End-to-end (#116): the "Level N" celebration only appears when a level
// threshold is actually crossed.
//
// Mastering a concept used to push the overlay on its own — the 10-minute
// throttle was the only gate — so a student who had just earned 100 of the
// 500 XP a level costs was congratulated for reaching the level they were
// already on. With the flat 500-XP curve the misfire would only have got
// more frequent.
//
// Why this has to run against the real app rather than the controller test
// next to it: the level the gate compares against does not come from the
// mastery signal at all. It arrives later, from `xpStateProvider`, which is
// derived from goal docs plus a *polling* progress stream three providers
// away, and reaches the controller through a listener `TutorService` sets up
// when the app boots. Nothing below the whole running app has that chain.
// The mastery signal itself is armed the way the conductor arms it.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/level_up_gate.dart -d windows

import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/progression/level_up_controller.dart';
import 'package:ai_tutor_python/widgets/level_up_overlay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/seed.dart';

/// A finished non-optional subgoal, written the way the conductor would.
/// Each one is worth [kXpPerSubgoal].
Map<String, dynamic> donePr(String goalId) => {
  'id': '${kStudentUid}_$goalId',
  'uid': kStudentUid,
  'goalId': goalId,
  'progress': 1.0,
  'updatedAt': '2026-07-20T10:00:00Z',
  'lastSessionAt': '2026-07-20T10:00:00Z',
};

/// Four more finished subgoals under "Basics" — 400 XP banked, so the
/// student sits one completed subgoal below the level-2 threshold.
Map<String, List<Map<String, dynamic>>> fourSubgoalsDone() => {
  'goals': [
    for (var i = 3; i <= 6; i++)
      goalDoc(
        id: 's$i',
        title: 'Extra $i',
        parentId: 'r1',
        order: i * 1000,
        objectives: [objective('lo-$i', 'Something already learned')],
      ),
  ],
  'progress': [for (var i = 3; i <= 6; i++) donePr('s$i')],
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Arms the mastery signal exactly as `TutorService._onConceptMastered`
  /// does when the conductor reports a mastered concept goal.
  void masterConcept(AppHarness harness, String concept) {
    harness.container
        .read(levelUpControllerProvider.notifier)
        .armConceptMastered(conceptName: concept, xpAwarded: kXpPerSubgoal);
  }

  Future<void> xpPillReads(WidgetTester tester, String text) => pumpUntil(
    tester,
    () => find.text(text).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 30),
    reason: 'the XP pill never read "$text"',
  );

  /// Text inside the celebration itself. The top bar carries a "Level N"
  /// chip of its own, so a bare `find.text('Level 1')` would match the
  /// shell that is *always* on screen and prove nothing.
  Finder inOverlay(String text) => find.descendant(
    of: find.byType(LevelUpOverlay),
    matching: find.text(text),
  );

  testWidgets('a mastered concept that banks no level shows no overlay', (
    tester,
  ) async {
    final harness = AppHarness();
    await harness.boot(tester);

    // Nothing done yet — and the pill proves the XP chain is live, so the
    // level the gate compares against is a real one.
    await xpPillReads(tester, '0 / 500');

    masterConcept(harness, 'Print');
    harness.cosmos['progress'].docs['${kStudentUid}_s1'] = donePr('s1');

    // The XP lands…
    await xpPillReads(tester, '100 / 500');
    // …and 100 of 500 is not a level, so nothing is celebrated. A few more
    // frames so a late overlay would still have shown up.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(inOverlay('Level 1'), findsNothing);
    expect(find.textContaining("You've mastered"), findsNothing);
    expect(find.textContaining('CONCEPT UNLOCKED'), findsNothing);

    await harness.dispose(tester);
  });

  testWidgets('the same mastery one subgoal later does cross, and is '
      'celebrated', (tester) async {
    final harness = AppHarness(extraDocs: fourSubgoalsDone());
    await harness.boot(tester);

    // Four subgoals banked: one short of the 500 XP a level costs.
    await xpPillReads(tester, '400 / 500');

    masterConcept(harness, 'Print');
    harness.cosmos['progress'].docs['${kStudentUid}_s1'] = donePr('s1');

    // The fifth completed subgoal tips it over, and the overlay names the
    // level actually reached and the concept that got there.
    await pumpUntil(
      tester,
      () => inOverlay('Level 2').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
      reason: 'crossing into level 2 never opened the level-up overlay',
    );
    expect(inOverlay("You've mastered Print."), findsOneWidget);
    expect(inOverlay('+$kXpPerSubgoal XP · CONCEPT UNLOCKED'), findsOneWidget);
    // The pill agrees: level 2, and the remainder starts over.
    expect(find.text('0 / 500'), findsWidgets);

    await harness.dispose(tester);
  });
}
