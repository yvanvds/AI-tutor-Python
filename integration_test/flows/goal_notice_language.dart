// End-to-end (#211): what the app tells the student about a goal — "Goal
// reached!", the level-up for a mastered concept, the warm-up and recheck
// pills in chat — names the goal in the student's language.
//
// Sam's app runs in English (the harness pins an en-US desktop). Sam
// finishes "Variabelen", a concept subgoal with an English translation, on
// the answer that also tips the XP over into level 2: the splash names it
// "Using variables" with the English description, and the level-up card
// says "You've mastered Using variables." A session that opens with a
// warm-up question on "Print" (translated "Printing") announces it in
// English, and switching to Nederlands in Options turns that pill already
// on screen back to the Dutch title. A recheck on "Print" is announced in
// English the same way. The prompts keep the Dutch goal text (#210): only
// what the student reads is translated.
//
// Real app, real navigation, real practice view and editor, real
// TutorService → grader payload → conductor → mastery → splash / level-up
// / chat pills, real TranslationService polling the (in-memory) Cosmos
// `translations` container. Only the model is scripted (`ScriptedLlm`, raw
// assistant text through the production parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/goal_notice_language.dart -d windows

import 'package:ai_tutor_python/features/chat/widgets/chat_system_pill.dart';
import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';
import 'package:ai_tutor_python/widgets/goal_splash_overlay.dart';
import 'package:ai_tutor_python/widgets/level_up_overlay.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String kVariablesExercise = 'stad = ___\nprint("Welkom in " + stad)';
const String kLoopsExercise = 'for i in range(___):\n    print(i)';
const String kPrintExercise = 'print(___)';

/// "Variabelen", a concept subgoal, as the teacher wrote it in Dutch.
Map<String, dynamic> variabelen() => {
  ...goalDoc(
    id: 's2',
    title: 'Variabelen',
    parentId: 'r1',
    order: 2000,
    objectives: [objective('lo-var', 'Assign a value to a name')],
  ),
  'description': 'Waarden onthouden onder een naam.',
  'kind': 'concept',
};

/// "Print" as the standard seed has it.
Map<String, dynamic> printGoal() => goalDoc(
  id: 's1',
  title: 'Print',
  parentId: 'r1',
  order: 1000,
  contentId: 's1',
  objectives: [objective('lo-print', 'Use print() to show text')],
);

/// The English translation of the goal [doc], made from its Dutch text.
Map<String, dynamic> english(
  Map<String, dynamic> doc, {
  required String title,
  String description = '',
}) => Translation.goal(
  language: 'en',
  goalId: doc['id'] as String,
  title: title,
  description: description,
  sourceHash: goalSourceHash(Goal.fromCosmos(doc)),
).toMap();

/// A finished subgoal, worth 100 XP.
Map<String, dynamic> done(String goalId) => {
  'id': '${kStudentUid}_$goalId',
  'uid': kStudentUid,
  'goalId': goalId,
  'progress': 1.0,
  'updatedAt': '2026-08-03T10:00:00Z',
  'lastSessionAt': '2026-08-03T10:00:00Z',
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      tester.widget<CodeField>(find.byType(CodeField)).controller.text;

  List<String> pills(WidgetTester tester) => tester
      .widgetList<ChatSystemPill>(find.byType(ChatSystemPill))
      .map((p) => p.text)
      .toList();

  /// Boots onto the first open subgoal (no lesson content, so the leerpad
  /// opens the practice editor directly) and waits for the first exercise.
  Future<void> openPractice(
    WidgetTester tester,
    AppHarness harness, {
    required String firstExercise,
  }) async {
    await harness.boot(tester);
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntil(
      tester,
      () => editorText(tester) == firstExercise,
      timeout: const Duration(seconds: 30),
      reason: 'the first exercise never reached the editor',
    );
  }

  testWidgets('in English, finishing a translated concept subgoal: the splash '
      'and the level-up name it in English', (tester) async {
    final now = DateTime.now().toUtc();
    final harness = AppHarness(
      llm: ScriptedLlm([
        completeCodeReply(text: 'Vul de stad in.', code: kVariablesExercise),
        codeFeedbackReply(
          text: 'Helemaal juist.',
          quality: 'correct',
          loSignals: const [
            {
              'subgoalId': 's2',
              'loId': 'lo-var',
              'signal': 'positive',
              'strength': 'strong',
            },
          ],
        ),
        llmEnvelope(
          text: 'Sam kent variabelen.',
          meta:
              '{"type":"status_summary","stats":{"hints_used":0,'
              '"common_issues":[],"last_exercise_type":"complete_code"}}',
        ),
        completeCodeReply(text: 'Nu een lus.', code: kLoopsExercise),
      ]),
      extraDocs: {
        'goals': [
          variabelen(),
          // Three more finished subgoals: with "Print" that is 400 XP, one
          // subgoal short of level 2 — so finishing "Variabelen" crosses.
          for (var i = 3; i <= 5; i++)
            goalDoc(
              id: 's$i',
              title: 'Extra $i',
              parentId: 'r1',
              order: i * 1000,
              objectives: [objective('lo-$i', 'Something already learned')],
            ),
          goalDoc(
            id: 's6',
            title: 'Lussen',
            parentId: 'r1',
            order: 6000,
            objectives: [objective('lo-loop', 'Repeat with a for loop')],
          ),
        ],
        'progress': [
          for (final id in ['s1', 's3', 's4', 's5']) done(id),
        ],
        'lo_beliefs': [
          // One strong positive short of mastery, calibrated positive on
          // record: (3, 1) → (5, 1) on the grade, mastered.
          {
            'id': '${kStudentUid}_s2_lo-var',
            'type': 'lo_belief',
            'uid': kStudentUid,
            'subgoalId': 's2',
            'loId': 'lo-var',
            'alpha': 3.0,
            'beta': 1.0,
            'lastUpdatedAt': now.toIso8601String(),
            'lastQuestionType': 'completeCodeQuestion',
            'lastPositiveAtCalibratedAt': now.toIso8601String(),
            'highestPositiveDifficulty': 'medium',
            'recentNegativesAtCalibrated': 0,
          },
        ],
        'translations': [
          english(
            variabelen(),
            title: 'Using variables',
            description: 'Keeping values under a name.',
          ),
        ],
      },
    );
    await openPractice(tester, harness, firstExercise: kVariablesExercise);

    await tester.tap(find.byTooltip('Send to tutor'));

    // "Goal reached!" names the subgoal in English, description included.
    Finder inSplash(Finder finder) =>
        find.descendant(of: find.byType(GoalSplashOverlay), matching: finder);
    await pumpUntilFound(tester, inSplash(find.text('Goal reached!')));
    expect(inSplash(find.text('Using variables')), findsOneWidget);
    expect(inSplash(find.text('Keeping values under a name.')), findsOneWidget);
    expect(inSplash(find.text('Variabelen')), findsNothing);
    expect(
      inSplash(find.text('Waarden onthouden onder een naam.')),
      findsNothing,
    );

    // The XP of the finished subgoal reaches the level on the next progress
    // poll: level 2, and the card names the concept in English.
    Finder inLevelUp(Finder finder) =>
        find.descendant(of: find.byType(LevelUpOverlay), matching: finder);
    await pumpUntil(
      tester,
      () => inLevelUp(find.text('Level 2')).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
      reason: 'finishing the concept never opened the level-up overlay',
    );
    expect(
      inLevelUp(find.text("You've mastered Using variables.")),
      findsOneWidget,
    );
    expect(inLevelUp(find.textContaining('Variabelen')), findsNothing);

    // Tap both away, as a student would; that also keeps the splash's 10 s
    // auto-dismiss from reaching into a torn-down container.
    await tester.tap(inLevelUp(find.text('Keep learning')));
    await pumpUntilGone(tester, inLevelUp(find.text('Level 2')));
    final splash = inSplash(find.text('Goal reached!'));
    if (splash.evaluate().isNotEmpty) {
      await tester.tap(splash);
      await pumpUntilGone(tester, splash);
    }

    // The walk goes on. The English text is for the student only: none of
    // it reached the model.
    await pumpUntil(
      tester,
      () => editorText(tester) == kLoopsExercise,
      timeout: const Duration(seconds: 30),
      reason: "the next subgoal's exercise never reached the editor",
    );
    final llm = harness.llm!;
    for (final sent in [...llm.sentInstructions, ...llm.sentInputs]) {
      expect(sent, isNot(contains('Using variables')));
      expect(sent, isNot(contains('Keeping values under a name.')));
    }

    await harness.dispose(tester);
  });

  testWidgets('in English the warm-up pill names the goal in English; '
      'Nederlands turns that pill back to the Dutch title', (tester) async {
    final sixWeeksAgo = DateTime.now().toUtc().subtract(
      PolicyConstants.warmUpStaleAfter + const Duration(days: 12),
    );
    final harness = AppHarness(
      llm: ScriptedLlm([
        completeCodeReply(
          text: 'Even opwarmen: toon een tekst.',
          code: kPrintExercise,
        ),
      ]),
      extraDocs: {
        'progress': [done('s1')],
        // "Print" mastered six weeks ago and not touched since: due for a
        // warm-up review.
        'lo_beliefs': [
          {
            'id': '${kStudentUid}_s1_lo-print',
            'type': 'lo_belief',
            'uid': kStudentUid,
            'subgoalId': 's1',
            'loId': 'lo-print',
            'alpha': 5.0,
            'beta': 1.0,
            'lastUpdatedAt': sixWeeksAgo.toIso8601String(),
            'lastQuestionType': 'writeCodeQuestion',
            'lastPositiveAtCalibratedAt': sixWeeksAgo.toIso8601String(),
            'highestPositiveDifficulty': 'medium',
            'recentNegativesAtCalibrated': 0,
            'firstMasteredAt': sixWeeksAgo.toIso8601String(),
          },
        ],
        'translations': [english(printGoal(), title: 'Printing')],
      },
    );
    await openPractice(tester, harness, firstExercise: kPrintExercise);

    await pumpUntil(
      tester,
      () => pills(tester)
          .contains('Quick warm-up first: one review question on Printing.'),
      reason: 'the warm-up pill never named "Printing"',
    );
    expect(
      pills(tester),
      isNot(contains('Quick warm-up first: one review question on Print.')),
    );

    // The student switches to Dutch and comes back to the session: the pill
    // that was already there now names the goal as written.
    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));
    await tester.tap(find.text('Nederlands'));
    await pumpUntilFound(tester, find.text('Opties'));
    await tester.tap(find.byTooltip('Sessie'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntil(
      tester,
      () =>
          pills(tester)
              .contains('Eerst even opwarmen: één opfrisvraag over Print.'),
      reason: 'the warm-up pill did not turn Dutch after the switch',
    );
    expect(pills(tester), isNot(contains(contains('Printing'))));

    await harness.dispose(tester);
  });

  testWidgets('in English the recheck pill names the goal in English', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    final twelveDaysAgo = now.subtract(const Duration(days: 12));
    final twoDaysAgo = now.subtract(const Duration(days: 2));
    final windowAt = now.subtract(const Duration(days: 1));
    final harness = AppHarness(
      llm: ScriptedLlm([
        completeCodeReply(
          text: 'Tussendoor: toon een tekst op het scherm.',
          code: kPrintExercise,
        ),
      ]),
      extraDocs: {
        // Ten right answers in a row: good enough recent work to be sent
        // back to a near goal (§2.6).
        'accounts': [
          {
            ...accountDoc(studentIdentity),
            'calibration': {
              'difficulty': 'medium',
              'recentAnswers': [
                for (var i = 0; i < PolicyConstants.calibrationWindow; i++)
                  {
                    'quality': 'correct',
                    'difficulty': 'medium',
                    'at': windowAt.toIso8601String(),
                  },
              ],
              'recentQuestionTypes': const <String>[],
            },
          },
        ],
        // "Print" advanced past twelve days ago with `lo-print` just under
        // the bar.
        'progress': [
          {
            'id': '${kStudentUid}_s1',
            'uid': kStudentUid,
            'goalId': 's1',
            'progress': 0.0,
            'updatedAt': twelveDaysAgo.toIso8601String(),
            'lastSessionAt': twelveDaysAgo.toIso8601String(),
            'advancedAt': twelveDaysAgo.toIso8601String(),
          },
        ],
        'lo_beliefs': [
          {
            'id': '${kStudentUid}_s1_lo-print',
            'type': 'lo_belief',
            'uid': kStudentUid,
            'subgoalId': 's1',
            'loId': 'lo-print',
            'alpha': 7.7,
            'beta': 2.3,
            'lastUpdatedAt': twoDaysAgo.toIso8601String(),
            'lastQuestionType': 'completeCodeQuestion',
            'recentNegativesAtCalibrated': 0,
            'lastProbedAt': twelveDaysAgo.toIso8601String(),
          },
        ],
        'translations': [english(printGoal(), title: 'Printing')],
      },
    );
    await openPractice(tester, harness, firstExercise: kPrintExercise);

    const recheck =
        'In between: one check question on Printing, so you can show '
        "you've got it now.";
    await pumpUntil(
      tester,
      () => pills(tester).contains(recheck),
      reason: 'the recheck pill never named "Printing"',
    );
    expect(pills(tester), isNot(contains(contains('on Print,'))));

    await harness.dispose(tester);
  });
}
