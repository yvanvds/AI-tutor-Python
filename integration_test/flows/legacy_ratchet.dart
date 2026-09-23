// End-to-end (#164): a graded turn on a belief doc from before the
// three-level ratchet existed (#103) — the old calibrated-positive flag set,
// no `highestPositiveDifficulty` — rewrites the doc without inventing a
// level for it.
//
// Before #164, `LoBelief.fromCosmos` read such a doc as `medium`, the
// conductor carried that guess through the ratchet unchanged on a negative,
// and `toMap` wrote it to `lo_beliefs` as if it had been measured. From then
// on nothing could tell the guess from a measurement, and a student who had
// really demonstrated the LO at hard was capped at medium for good: the
// tutor does not re-probe a mastered LO, and in the grade formula that costs
// `d`, 40% of everything above the 50-line (PUNTENFORMULE §2.3/§2.5). Now
// the doc keeps saying "unknown" until a positive records the level actually
// asked; the formula alone applies §2.5's old-data reading, at grade time
// (grade_proposal.dart covers that side).
//
// Nothing on screen shows the level; the doc is the user-visible surface
// (as in difficulty_ratchet.dart). Real app, real navigation, real practice
// view and editor, real TutorService → conductor → belief math → Cosmos
// services. Only the model is scripted (`ScriptedLlm`, raw assistant text
// through the production parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/legacy_ratchet.dart -d windows

import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String kExercise = 'naam = ___\nprint("Hallo, " + naam)';
const String kNextExercise = 'stad = ___\nprint("Welkom in " + stad)';

/// The belief on `lo-print` as a build from before #103 left it: one
/// calibrated positive on record and no `highestPositiveDifficulty`. (3, 1)
/// is one strong positive short of mastery, so "Print" stays the active
/// subgoal and the probe lands on this very LO. Written just now, so no
/// decay moves it first; no `lastQuestionType`, so type rotation (§2.2)
/// asks the same first exercise a fresh student gets.
Map<String, dynamic> legacyPrintBelief(DateTime at) => {
  'id': '${kStudentUid}_s1_lo-print',
  'type': 'lo_belief',
  'uid': kStudentUid,
  'subgoalId': 's1',
  'loId': 'lo-print',
  'alpha': 3.0,
  'beta': 1.0,
  'lastUpdatedAt': at.toIso8601String(),
  'lastPositiveAtCalibratedAt': at.toIso8601String(),
  'recentNegativesAtCalibrated': 0,
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      (tester.widget<CodeField>(find.byType(CodeField)).controller).text;

  testWidgets('a wrong answer on a pre-ratchet belief doc rewrites it '
      'without a level: the old guess is no longer written as a '
      'measurement', (tester) async {
    // Whole seconds: the value must come back from the doc as written.
    final now = DateTime.now().toUtc();
    final seededAt = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
    );
    final harness = AppHarness(
      llm: ScriptedLlm([
        completeCodeReply(text: 'Vul de naam in.', code: kExercise),
        codeFeedbackReply(
          text: 'print() mist zijn haakjes.',
          quality: 'wrong',
          loSignals: const [
            {
              'subgoalId': 's1',
              'loId': 'lo-print',
              'signal': 'negative',
              'strength': 'strong',
            },
          ],
        ),
        completeCodeReply(text: 'Nu de stad.', code: kNextExercise),
      ]),
      extraDocs: {
        'lo_beliefs': [legacyPrintBelief(seededAt)],
      },
    );
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntil(
      tester,
      () => editorText(tester) == kExercise,
      timeout: const Duration(seconds: 30),
      reason: 'the exercise never reached the editor',
    );

    await tester.tap(find.byTooltip('Send to tutor'));
    await pumpUntil(
      tester,
      () => harness.cosmos['turn_history'].docs.isNotEmpty,
      timeout: const Duration(seconds: 30),
      reason: 'no turn was recorded after the code was sent',
    );
    await pumpUntil(
      tester,
      () => editorText(tester) == kNextExercise,
      timeout: const Duration(seconds: 30),
      reason: 'the next exercise never reached the editor',
    );

    // A calibrated probe of this LO, graded wrong.
    final turn = harness.cosmos['turn_history'].docs.values.single;
    expect(turn['subgoalId'], 's1');
    expect(turn['difficulty'], 'medium');
    expect(turn['overallQuality'], 'wrong');

    final belief =
        harness.cosmos['lo_beliefs'].docs['${kStudentUid}_s1_lo-print'];
    expect(belief, isNotNull, reason: 'the seeded belief doc went missing');
    // The turn reached the doc: the strong negative at medium landed on β
    // (×1.0), α stayed ...
    expect(belief!['alpha'], closeTo(3.0, 0.05));
    expect(belief['beta'], closeTo(1.0 + PolicyConstants.weightStrong, 0.05));
    // ... the old flag it came with is still the seeded one ...
    expect(
      DateTime.parse(belief['lastPositiveAtCalibratedAt'] as String),
      seededAt,
    );
    // ... and no level was invented for it. Before #164 this key read
    // `"medium"` here: a guess, written as if measured.
    expect(
      belief.containsKey('highestPositiveDifficulty'),
      isFalse,
      reason: 'a level the app never measured must not reach the doc',
    );

    await harness.dispose(tester);
  });
}
