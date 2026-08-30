// End-to-end (#28, exercising #13 / #23 surfaces): a student boots the app,
// opens the learning path, continues the active root, and lands on the
// lesson for its first subgoal. The lesson renders in the real WebView and
// its `<pre class="run">` block goes through the real JS bridge to the
// runner.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/lesson_flow.dart -d windows

import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:ai_tutor_python/widgets/lesson_html_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/seed.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppHarness harness;

  setUp(() {
    harness = AppHarness(
      lessonResults: {
        kLessonExampleCode: const LessonRunResult(stdout: 'Hallo Mira'),
      },
    );
  });

  testWidgets('boot -> learning path -> Continue opens the lesson and runs '
      'its live example', (tester) async {
    await harness.boot(tester);

    // Signed in, on the bundled key: straight to the shell.
    expect(find.text('Hi Sam,'), findsOneWidget);
    expect(find.text('Sign in with school account'), findsNothing);

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    // Page header plus the top-bar section subline.
    expect(find.text('Learning path'), findsNWidgets(2));
    expect(find.text('Basics'), findsOneWidget);
    // The active root is expanded: its subgoals and the CTA are visible.
    expect(find.text('Print'), findsOneWidget);
    expect(find.text('Variables'), findsOneWidget);

    final runsBefore = harness.lessonRunner.ran.length;
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));

    // The conductor targeted the first unstarted subgoal, whose lesson the
    // explain view now hosts.
    expect(find.text('BASICS'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('Try it yourself'), findsOneWidget);
    expect(find.byType(LessonHtmlView), findsOneWidget);

    // The page loaded in the real WebView, its bootstrap found the
    // `<pre class="run">` block and posted it on the runner channel.
    await pumpUntil(
      tester,
      () => harness.lessonRunner.ran.length > runsBefore,
      timeout: const Duration(seconds: 30),
      reason: 'the lesson page never asked to run its example',
    );
    expect(harness.lessonRunner.ran.last, kLessonExampleCode);

    await harness.dispose(tester);
  });
}
