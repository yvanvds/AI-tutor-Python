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
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/explain_paging.dart -d windows

import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
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

    // Back to the theory of the subgoal already finished.
    await tester.tap(find.text('Previous'));
    await lessonOnScreen(kLessonExampleCode);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(target(), 's2', reason: 'paging back moved the tutor target');

    // Forward again: the newest page, and no Next to press.
    await tester.tap(find.text('Next'));
    await lessonOnScreen(kVariablesExampleCode);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
    expect(find.text('Try it yourself'), findsOneWidget);
    expect(target(), 's2');

    await harness.dispose(tester);
  });
}
