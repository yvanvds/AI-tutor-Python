// End-to-end (#311): an answer that is not wrong never takes mastery away.
//
// The teacher answered twenty exercises of one subgoal right and saw the
// progress fall after every right follow-up answer. Forgetting per answer
// (#278) shrinks what an LO holds before new evidence lands, and a
// follow-up weighs only 0.5 (§6.2): on an LO just over the bar that left
// less evidence than mastery wants (5.75, §4.1), so the LO was not
// mastered any more, the cached share of the subgoal fell, and the tutor
// asked the LO again. A transfer credit (§3.7) did the same to mastered
// LOs of earlier subgoals.
//
// The mastery guard (CONDUCTOR_POLICY §3.4): a write without a negative on
// an LO that is mastered is tried with forgetting first; would that leave
// it under the bar, the evidence is added without forgetting.
//
// Flow 1, on "Print" with two LOs, lo-a one right answer from mastery:
//   1. lo-a right                → mastered, share 0.5; a follow-up comes
//   2. the follow-up, right      → still mastered, share still 0.5
//   3. lo-b right                → (lo-b needs a second right answer)
//   4. the next question is on lo-b again, not on lo-a
// Flow 2: a transfer credit on a just-mastered LO of an earlier subgoal
// leaves it mastered.
//
// Real app, real navigation, real practice view, editor and chat, real
// TutorService → conductor → belief math → Cosmos services. Only the model
// is scripted (`ScriptedLlm`, raw assistant text through the production
// parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/mastery_guard.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/features/chat/widgets/composer_idle.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/services/student_state/lo_belief.dart';
import 'package:ai_tutor_python/services/tutor/belief_math.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const List<String> _exercises = [
  'print(___)',
  'print("a", ___)',
  'print(1, ___)',
  'print("klaar", ___)',
];

Map<String, String> _positive(String subgoalId, String loId) => {
  'subgoalId': subgoalId,
  'loId': loId,
  'signal': 'positive',
  'strength': 'strong',
};

/// "Print" without its lesson, so the leerpad opens the editor, with two
/// LOs.
Map<String, dynamic> _printGoal() => goalDoc(
  id: 's1',
  title: 'Print',
  parentId: 'r1',
  order: 1000,
  objectives: [
    objective('lo-a', 'Print a sentence'),
    objective('lo-b', 'Print several values at once'),
  ],
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      (tester.widget<CodeField>(find.byType(CodeField)).controller).text;

  Future<void> waitForExercise(WidgetTester tester, String code) => pumpUntil(
    tester,
    () => editorText(tester) == code,
    timeout: const Duration(seconds: 30),
    reason: 'the exercise "$code" never reached the editor',
  );

  List<Map<String, dynamic>> turns(AppHarness harness) =>
      harness.cosmos['turn_history'].docs.values.toList()..sort(
        (a, b) => (a['turnAt'] as String).compareTo(b['turnAt'] as String),
      );

  Future<void> waitForTurns(WidgetTester tester, AppHarness harness, int n) =>
      pumpUntil(
        tester,
        () => harness.cosmos['turn_history'].docs.length == n,
        timeout: const Duration(seconds: 30),
        reason: 'turn $n was never recorded',
      );

  bool masteredAfter(Map<String, dynamic> turn, String loId) =>
      (turn['loStatusAfter'] as List).cast<Map>().firstWhere(
            (l) => l['loId'] == loId,
          )['mastered']
          as bool;

  testWidgets('a right follow-up answer on a just-mastered LO leaves it '
      'mastered: the share of the subgoal does not fall and the tutor does '
      'not ask the LO again', (tester) async {
    final written = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
    final llm = ScriptedLlm([
      completeCodeReply(text: 'Print een zin.', code: _exercises[0]),
      // 1. lo-a right: (4.4, 1) → (5.38, 1), mastered. With a follow-up.
      llmEnvelope(
        text: 'Helemaal juist.',
        meta: jsonEncode({
          'type': 'code_feedback',
          'suggestion': '',
          'overallQuality': 'correct',
          'loSignals': [_positive('s1', 'lo-a')],
          'followUp': {'question': 'Waarom staan er aanhalingstekens?'},
        }),
      ),
      // 2. The follow-up, right: capped at weak, 0.5.
      llmEnvelope(
        text: 'Juist: zo weet Python dat het tekst is.',
        meta: jsonEncode({
          'type': 'socratic_feedback',
          'overallQuality': 'correct',
          'loSignals': [_positive('s1', 'lo-a')],
        }),
      ),
      completeCodeReply(text: 'Print twee waarden.', code: _exercises[1]),
      // 3. lo-b right, its first right own question.
      codeFeedbackReply(
        text: 'Helemaal juist.',
        quality: 'correct',
        loSignals: [_positive('s1', 'lo-b')],
      ),
      completeCodeReply(text: 'Nog twee waarden.', code: _exercises[2]),
      // 4. Not right, so the subgoal stays open and the flow ends here.
      codeFeedbackReply(
        text: 'Niet juist: er ontbreekt een waarde.',
        quality: 'wrong',
        loSignals: [
          {
            'subgoalId': 's1',
            'loId': 'lo-b',
            'signal': 'negative',
            'strength': 'weak',
          },
        ],
      ),
      completeCodeReply(text: 'Nog eens.', code: _exercises[3]),
    ]);
    final harness = AppHarness(
      llm: llm,
      extraDocs: {
        'goals': [_printGoal()],
        'lo_beliefs': [
          // Two right own questions on medium: one more masters it.
          LoBelief(
            subgoalId: 's1',
            loId: 'lo-a',
            alpha: 4.4,
            beta: 1,
            lastUpdatedAt: written,
            lastQuestionType: 'socraticQuestion',
            lastPositiveAtCalibratedAt: written,
            highestPositiveDifficulty: QuestionDifficulty.medium,
            lastProbedAt: written,
            ownQuestions: 2,
            ownQuestionsRight: 2,
            ownQuestionsRightNonMcq: 1,
          ).toMap(uid: kStudentUid),
          // Seen from the side only, never asked: a higher mean than lo-a,
          // so lo-a goes first, and no right own question yet.
          LoBelief(
            subgoalId: 's1',
            loId: 'lo-b',
            alpha: 5,
            beta: 1,
            lastUpdatedAt: written,
            ownQuestions: 0,
            ownQuestionsRight: 0,
            ownQuestionsRightNonMcq: 0,
          ).toMap(uid: kStudentUid),
        ],
      },
    );
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await waitForExercise(tester, _exercises[0]);

    double cachedShare() =>
        (harness.cosmos['progress'].docs['${kStudentUid}_s1']!['progress']
                as num)
            .toDouble();
    Map<String, dynamic> storedA() =>
        harness.cosmos['lo_beliefs'].docs['${kStudentUid}_s1_lo-a']!;

    // 1. The own question, right: mastered.
    await tester.tap(find.byTooltip('Send to tutor'));
    await waitForTurns(tester, harness, 1);
    final own = turns(harness)[0];
    expect(own['targetLOIds'], ['lo-a']);
    expect(masteredAfter(own, 'lo-a'), isTrue);
    expect(own['subgoalProgressAfter'], 0.5);
    await pumpUntil(
      tester,
      () => cachedShare() == 0.5,
      reason: 'the mastered LO never reached the cached share',
    );
    final mastered = Map<String, dynamic>.from(storedA());
    expect(mastered['alpha'], closeTo(5.38, 1e-2));
    final stamp = mastered['firstMasteredAt'];
    expect(stamp, isNotNull);

    // 2. The follow-up comes in the chat; the student answers it right.
    await pumpUntilFound(
      tester,
      find.textContaining('Waarom staan er', findRichText: true),
    );
    await pumpUntil(
      tester,
      () => harness.container.read(tutorServiceProvider) == TutorState.idle,
    );
    final composer = find.descendant(
      of: find.byType(ComposerIdle),
      matching: find.byType(TextField),
    );
    await pumpUntilFound(tester, composer);
    await tester.tap(composer);
    await tester.pump();
    await tester.enterText(composer, 'Omdat het tekst is.');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    await waitForTurns(tester, harness, 2);

    final followUp = turns(harness)[1];
    expect(followUp['isFollowUp'], isTrue);
    expect(
      (followUp['appliedSignals'] as List).cast<Map>().single['alphaDelta'],
      closeTo(PolicyConstants.weightWeak, 1e-9),
    );
    // Still mastered, and the share did not fall.
    expect(masteredAfter(followUp, 'lo-a'), isTrue);
    expect(followUp['subgoalProgressAfter'], 0.5);
    expect(cachedShare(), 0.5);
    // The 0.5 came on top, without forgetting: after forgetting the LO
    // would hold 5.57 of evidence, under the bar.
    final after = storedA();
    final decayed = applyDecay(
      alpha: (mastered['alpha'] as num).toDouble(),
      beta: (mastered['beta'] as num).toDouble(),
      lastUpdatedAt: DateTime.parse(mastered['lastUpdatedAt'] as String),
      now: DateTime.parse(after['lastUpdatedAt'] as String),
    );
    expect(
      forgetBeforeEvidence(decayed).evidence + PolicyConstants.weightWeak,
      lessThan(PolicyConstants.masteryEvidenceMin),
    );
    expect(
      after['alpha'],
      closeTo(decayed.alpha + PolicyConstants.weightWeak, 1e-9),
    );
    expect(after['beta'], closeTo(decayed.beta, 1e-9));
    expect(after['firstMasteredAt'], stamp);

    // 3. The next question is on lo-b; right.
    await waitForExercise(tester, _exercises[1]);
    await tester.tap(find.byTooltip('Send to tutor'));
    await waitForTurns(tester, harness, 3);
    expect(turns(harness)[2]['targetLOIds'], ['lo-b']);
    expect(masteredAfter(turns(harness)[2], 'lo-b'), isFalse);

    // 4. And the one after it too: lo-a is mastered, so it is not asked
    //    again — before the guard it was, as the only other open LO.
    await waitForExercise(tester, _exercises[2]);
    await tester.tap(find.byTooltip('Send to tutor'));
    await waitForTurns(tester, harness, 4);
    expect(turns(harness)[3]['targetLOIds'], ['lo-b']);
    expect(masteredAfter(turns(harness)[3], 'lo-a'), isTrue);
    expect(cachedShare(), 0.5);

    await waitForExercise(tester, _exercises[3]);
    expect(llm.remaining, 0);
    await harness.dispose(tester);
  });

  testWidgets('a transfer credit on a just-mastered LO of an earlier '
      'subgoal leaves it mastered: added without forgetting', (tester) async {
    const exercise = 'stad = ___\nprint("Welkom in " + stad)';
    const nextExercise = 'leeftijd = ___\nprint(leeftijd)';
    final written = DateTime.now().toUtc().subtract(const Duration(hours: 1));
    final harness = AppHarness(
      llm: ScriptedLlm([
        completeCodeReply(text: 'Vul de stad in.', code: exercise),
        codeFeedbackReply(
          text: 'Helemaal juist.',
          quality: 'correct',
          loSignals: [_positive('s2', 'lo-var')],
          transferLOs: const [
            {'subgoalId': 's1', 'loId': 'lo-print'},
          ],
        ),
        completeCodeReply(text: 'Nu de leeftijd.', code: nextExercise),
      ]),
      extraDocs: {
        // "Print" is done, so the student is on "Variables".
        'progress': [
          {
            'id': '${kStudentUid}_s1',
            'uid': kStudentUid,
            'goalId': 's1',
            'progress': 1.0,
            'updatedAt': written.toIso8601String(),
            'lastSessionAt': written.toIso8601String(),
          },
        ],
        'lo_beliefs': [
          // Mastered an hour ago at its third right answer on medium.
          LoBelief(
            subgoalId: 's1',
            loId: 'lo-print',
            alpha: 5.38,
            beta: 1,
            lastUpdatedAt: written,
            lastQuestionType: 'completeCodeQuestion',
            lastPositiveAtCalibratedAt: written,
            highestPositiveDifficulty: QuestionDifficulty.medium,
            firstMasteredAt: written,
            lastProbedAt: written,
            ownQuestions: 3,
            ownQuestionsRight: 3,
            ownQuestionsRightNonMcq: 3,
          ).toMap(uid: kStudentUid),
        ],
      },
    );
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await waitForExercise(tester, exercise);
    await tester.tap(find.byTooltip('Send to tutor'));
    await waitForTurns(tester, harness, 1);
    await waitForExercise(tester, nextExercise);

    final turn = turns(harness).single;
    expect(turn['subgoalId'], 's2');
    final credit = (turn['transferCredits'] as List).cast<Map>().single;
    expect(credit['loId'], 'lo-print');
    expect(credit['alphaDelta'], closeTo(PolicyConstants.weightWeak, 1e-9));

    final print =
        harness.cosmos['lo_beliefs'].docs['${kStudentUid}_s1_lo-print']!;
    final decayed = applyDecay(
      alpha: 5.38,
      beta: 1,
      lastUpdatedAt: written,
      now: DateTime.parse(print['lastUpdatedAt'] as String),
    );
    // After forgetting the credit would leave 5.57 of evidence, under the
    // bar; it is added without.
    expect(
      forgetBeforeEvidence(decayed).evidence + PolicyConstants.weightWeak,
      lessThan(PolicyConstants.masteryEvidenceMin),
    );
    expect(
      print['alpha'],
      closeTo(decayed.alpha + PolicyConstants.weightWeak, 1e-9),
    );
    expect(print['beta'], closeTo(decayed.beta, 1e-9));
    expect(
      meetsMasteryMeanAndEvidence(
        BeliefSnapshot(
          (print['alpha'] as num).toDouble(),
          (print['beta'] as num).toDouble(),
        ),
      ),
      isTrue,
    );
    expect(print['firstMasteredAt'], written.toIso8601String());

    await harness.dispose(tester);
  });
}
