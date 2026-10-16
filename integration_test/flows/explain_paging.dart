// End-to-end (#115): the Uitleg footer pages back through theory the
// student has already seen. Sam has finished "Print" and is on "Variables",
// so the lesson that opens is the Variables one and "Previous" walks back to
// the Print lesson; "Next" only appears once they have paged back, and is
// gone again on the newest page. Paging is view-local — the tutor keeps
// working against "Variables" the whole time.
//
// Which lesson is actually on screen is read from the *real* WebView: each
// lesson carries its own `<pre class="run">` block, so the code the page
// posts on the runner channel names the page that loaded.
//
// The second test goes on into earlier goals (#272): Sam has finished
// "Basics" and "Setup" (which has no lessons) and is on "Slicing", the first
// subgoal of "Strings". "Previous" there goes on to the last lesson of
// "Basics", the header says "BASICS · 2 / 2", and a question typed in the
// chat is about that page and written for that goal — while the tutor stays
// on "Slicing".
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/explain_paging.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/features/chat/widgets/composer_idle.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/viewed_content_state.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

/// The Python inside the Variables lesson's live-preview block — distinct
/// from `kLessonExampleCode`, so the runner tells the two pages apart.
const String kVariablesExampleCode = 'stad = "Gent"\nprint(stad)';

const String kVariablesBody =
    '<h2>Variables</h2>'
    '<p>Een naam voor een waarde.</p>'
    '<pre class="run"><code>$kVariablesExampleCode</code></pre>';

/// "Print" is done, so the conductor lands the student on "Variables" —
/// which now carries a lesson of its own.
Map<String, List<Map<String, dynamic>>> onVariables() => {
  'progress': [
    {
      'id': '${kStudentUid}_s1',
      'uid': kStudentUid,
      'goalId': 's1',
      'progress': 1.0,
      'updatedAt': '2026-07-20T10:00:00Z',
      'lastSessionAt': '2026-07-20T10:00:00Z',
    },
  ],
  'goals': [
    goalDoc(
      id: 's2',
      title: 'Variables',
      parentId: 'r1',
      order: 2000,
      contentId: 's2',
      objectives: [objective('lo-var', 'Assign a value to a name')],
    ),
  ],
  'content': [
    {
      'id': 's2',
      'type': 'content',
      'title': 'Variables',
      'body': kVariablesBody,
      'updatedAt': '2026-05-01T10:00:00Z',
    },
  ],
};

/// The Python inside the Slicing lesson's live-preview block.
const String kSlicingExampleCode = 'woord = "Python"\nprint(woord[0:2])';

const String kSlicingBody =
    '<h2>Slicing</h2>'
    '<p>Een stuk van een tekst.</p>'
    '<pre class="run"><code>$kSlicingExampleCode</code></pre>';

Map<String, dynamic> done(String goalId, String at) => {
  'id': '${kStudentUid}_$goalId',
  'uid': kStudentUid,
  'goalId': goalId,
  'progress': 1.0,
  'updatedAt': at,
  'lastSessionAt': at,
};

/// "Basics" (both subgoals with a lesson) and "Setup" (no lessons) are done;
/// the walk lands Sam on "Slicing", the first subgoal of "Strings", which
/// they have opened but not practised yet.
Map<String, List<Map<String, dynamic>>> onStrings() {
  final basics = onVariables();
  return {
    'progress': [
      done('s1', '2026-07-20T10:00:00Z'),
      done('s2', '2026-07-21T10:00:00Z'),
      done('x1', '2026-07-22T10:00:00Z'),
      {
        'id': '${kStudentUid}_s3',
        'uid': kStudentUid,
        'goalId': 's3',
        'progress': 0.0,
        'updatedAt': '2026-07-23T10:00:00Z',
        'lastSessionAt': '2026-07-23T10:00:00Z',
      },
    ],
    'goals': [
      ...basics['goals']!,
      goalDoc(id: 'rx', title: 'Setup', order: 1500),
      goalDoc(
        id: 'x1',
        title: 'Install',
        parentId: 'rx',
        order: 1000,
        objectives: [objective('lo-install', 'Install Python')],
      ),
      goalDoc(id: 'r2', title: 'Strings', order: 2000),
      goalDoc(
        id: 's3',
        title: 'Slicing',
        parentId: 'r2',
        order: 1000,
        contentId: 's3',
        objectives: [objective('lo-slice', 'Take part of a text')],
      ),
    ],
    'content': [
      ...basics['content']!,
      {
        'id': 's3',
        'type': 'content',
        'title': 'Slicing',
        'body': kSlicingBody,
        'updatedAt': '2026-05-01T10:00:00Z',
      },
    ],
  };
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Previous re-opens the lesson of the finished subgoal, Next '
      'returns to the current one, and the tutor never moves', (tester) async {
    final harness = AppHarness(
      extraDocs: onVariables(),
      lessonResults: {
        kLessonExampleCode: const LessonRunResult(stdout: 'Hallo Mira'),
        kVariablesExampleCode: const LessonRunResult(stdout: 'Gent'),
      },
    );
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));

    Future<void> lessonOnScreen(String code) => pumpUntil(
      tester,
      () =>
          harness.lessonRunner.ran.isNotEmpty &&
          harness.lessonRunner.ran.last == code,
      timeout: const Duration(seconds: 30),
      reason: 'the lesson page with "$code" never loaded',
    );

    String? target() =>
        harness.container.read(goalSelectionProvider).activeChildGoal?.id;

    // The newest page: the lesson of the subgoal the tutor is working on.
    await lessonOnScreen(kVariablesExampleCode);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('Previous'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
    expect(target(), 's2');
    // #116: the footer names the XP the shell really awards for finishing
    // this subgoal — it used to promise a flat, invented "+10 XP".
    expect(find.text('+$kXpPerSubgoal XP on completion'), findsOneWidget);

    // Back to the theory of the subgoal already finished.
    await tester.tap(find.text('Previous'));
    await lessonOnScreen(kLessonExampleCode);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(target(), 's2', reason: 'paging back moved the tutor target');
    // "Print" is already done and its 100 XP already in the pill, so the
    // footer promises nothing here (#116).
    expect(find.textContaining('XP on completion'), findsNothing);

    // Forward again: the newest page, and no Next to press.
    await tester.tap(find.text('Next'));
    await lessonOnScreen(kVariablesExampleCode);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
    expect(find.text('Try it yourself'), findsOneWidget);
    expect(find.text('+$kXpPerSubgoal XP on completion'), findsOneWidget);
    expect(target(), 's2');

    await harness.dispose(tester);
  });

  testWidgets('Previous on the first lesson of a goal goes on to the lessons '
      'of the goals before it, under their own header; a question there is '
      'about that page; the tutor never moves', (tester) async {
    final llm = ScriptedLlm([
      llmEnvelope(
        text: 'Een variabele is een naam voor een waarde.',
        meta: '{"type":"answer"}',
      ),
    ]);
    final harness = AppHarness(
      llm: llm,
      extraDocs: onStrings(),
      lessonResults: {
        kLessonExampleCode: const LessonRunResult(stdout: 'Hallo Mira'),
        kVariablesExampleCode: const LessonRunResult(stdout: 'Gent'),
        kSlicingExampleCode: const LessonRunResult(stdout: 'Py'),
      },
    );
    await harness.boot(tester);

    // "Strings" is the third card in the learning path, below the fold.
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    final continueButton = find.text('Continue');
    await pumpUntilFound(tester, continueButton);
    await tester.ensureVisible(continueButton);
    await tester.pump();
    await tester.tap(continueButton);
    await pumpUntilFound(tester, find.byType(ExplainView));

    Future<void> lessonOnScreen(String code) => pumpUntil(
      tester,
      () =>
          harness.lessonRunner.ran.isNotEmpty &&
          harness.lessonRunner.ran.last == code,
      timeout: const Duration(seconds: 30),
      reason: 'the lesson page with "$code" never loaded',
    );

    /// The header of the page on screen: its goal and its place there.
    void expectHeader(String goal, String counter) {
      for (final text in [goal, counter]) {
        expect(
          find.descendant(
            of: find.byType(ExplainView),
            matching: find.text(text),
          ),
          findsOneWidget,
          reason: 'the header does not read "$goal · $counter"',
        );
      }
    }

    ({String? root, String? child}) target() {
      final s = harness.container.read(goalSelectionProvider);
      return (root: s.activeRootGoal?.id, child: s.activeChildGoal?.id);
    }

    String? viewed() => harness.container.read(viewedContentIdProvider);

    bool previousEnabled() =>
        tester.widget<Text>(find.text('Previous')).style!.color ==
        AppColors.fgMute;

    // The newest page: the first lesson of "Strings", and still a Previous.
    await lessonOnScreen(kSlicingExampleCode);
    expectHeader('STRINGS', '1 / 1');
    expect(previousEnabled(), isTrue);
    expect(find.text('Next'), findsNothing);
    expect(target(), (root: 'r2', child: 's3'));

    // Back past "Setup", which has no lessons, to the last one of "Basics".
    await tester.tap(find.text('Previous'));
    await lessonOnScreen(kVariablesExampleCode);
    expectHeader('BASICS', '2 / 2');
    expect(find.text('STRINGS'), findsNothing);
    expect(find.text('Next'), findsOneWidget);
    expect(find.textContaining('XP on completion'), findsNothing);
    expect(target(), (root: 'r2', child: 's3'));
    await pumpUntil(
      tester,
      () => viewed() == 's2',
      reason: 'the page on screen was never published',
    );

    // A question there is about that page, and written for its goal.
    final composer = find.descendant(
      of: find.byType(ComposerIdle),
      matching: find.byType(TextField),
    );
    await pumpUntilFound(tester, composer);
    await tester.tap(composer);
    await tester.pump();
    await tester.enterText(composer, 'Wat is een variabele?');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    await pumpUntil(
      tester,
      () => llm.sends == 1,
      timeout: const Duration(seconds: 30),
      reason: 'the question never went out',
    );
    final question = jsonDecode(llm.sentInputs.single) as Map<String, dynamic>;
    expect(question['request_type'], 'content_question');
    expect(question['content_title'], 'Variables');
    expect(question['content'], contains('Een naam voor een waarde.'));
    expect(
      llm.sentInstructions.single,
      contains('belongs to the subgoal "Variables" of the goal "Basics"'),
    );
    expect(llm.sentInstructions.single, isNot(contains('"Strings"')));
    await pumpUntilFound(
      tester,
      find.textContaining('naam voor een waarde', findRichText: true),
    );
    expect(target(), (root: 'r2', child: 's3'));

    // The first lesson of the first goal: nothing older.
    await tester.tap(find.text('Previous'));
    await lessonOnScreen(kLessonExampleCode);
    expectHeader('BASICS', '1 / 2');
    expect(previousEnabled(), isFalse);

    // Forward again, across the goals, to the newest page.
    await tester.tap(find.text('Next'));
    await lessonOnScreen(kVariablesExampleCode);
    expectHeader('BASICS', '2 / 2');
    await tester.tap(find.text('Next'));
    await lessonOnScreen(kSlicingExampleCode);
    expectHeader('STRINGS', '1 / 1');
    expect(find.text('Next'), findsNothing);
    expect(find.text('+$kXpPerSubgoal XP on completion'), findsOneWidget);
    expect(target(), (root: 'r2', child: 's3'));
    expect(llm.remaining, 0);

    await harness.dispose(tester);
  });
}
