// End-to-end (#28, exercising #127): filing a bug report with no GitHub
// account at all — the same report, saved as a text file the student sends
// to the teacher over chat.
//
// Why this has to run against the real app rather than the widget test next
// to it:
//
//   - the report is assembled from three things only the running app has:
//     the runner behind the Run button (here genuinely absent, #74), a turn
//     the real conductor planned (with the belief numbers #79 strips), and
//     the recorder the dialog reads. A widget test can only assert on a
//     body it assembled itself.
//   - the file goes through the same save seam as the progress export, and
//     ends up on the real disk: what is asserted on is what the teacher
//     would open, not what a fake was handed.
//   - the Bug reports card sits below the fold of a real, lazily-built
//     `ListView`, and this build has no OAuth client id — which is how a
//     developer checkout and CI are built, and exactly the state in which
//     the card used to offer nothing to press.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/bug_report_file.dart -d windows

import 'dart:io';

import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/services/debug/debug_session_recorder.dart';
import 'package:ai_tutor_python/version.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:py_runner/py_runner.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';

/// A perfectly ordinary code-completion exercise — this flow is about what
/// the *file* carries, not about the exercise.
const String _exercise = 'voornaam = ___\nprint("Welkom, " + voornaam + "!")';

/// Stands for the runner being *completely* unavailable (#74). The account
/// name in the message is deliberate: it is what the real
/// `PyRunnerNotInstalled` carries, and what must not reach a file the teacher
/// may paste into a public issue.
class _MissingPythonLocator implements PyHostLocator {
  @override
  Future<PyHostPaths> resolve() async => throw const PyRunnerNotInstalled(
    'Bundled Python interpreter not found at: '
    r'C:\Users\student.name\AI Tutor\python\python.exe',
  );
}

/// Brings a card further down the Options list into view. The panel is a real
/// `ListView` in a real window, so anything below the fold is not built yet —
/// and a widget that is built but off-screen would be "tapped" at the wrong
/// place without a sound.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  final scrollable = optionsScrollable();
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(finder, 120, scrollable: scrollable);
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 200));
}

/// Scrolls the control itself into view and then taps it (see
/// `bug_report_oauth.dart` for why never `tap` without this).
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _scrollTo(tester, finder);
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Bug reports: with no GitHub account the report is saved as a '
      'text file — runner, turn, no names', (tester) async {
    final dir = Directory.systemTemp.createTempSync('ai_tutor_bugreport_');
    final file = File('${dir.path}/report.txt');
    final llm = ScriptedLlm([
      completeCodeReply(text: 'Vul de ontbrekende invoer in.', code: _exercise),
    ]);
    final harness = AppHarness(
      // No OAuth app registered: the state every developer checkout and CI
      // build is in, and the one that used to leave nothing to press.
      githubOAuthClientId: '',
      pyRunner: PyRunner(locator: _MissingPythonLocator()),
      archiveFile: file,
      llm: llm,
    );
    await harness.boot(tester);

    // A real conductor-planned turn first, so there is something to attach
    // and belief numbers to leave out.
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(PracticeView));

    final recorder = harness.container.read(debugServiceProvider);
    await pumpUntil(
      tester,
      () => recorder.buffer.any(
        (t) => t.events.any((e) => e.name == 'conductor.planned'),
      ),
      timeout: const Duration(seconds: 30),
      reason: 'the tutor never planned a turn to attach',
    );
    final planned = recorder.buffer
        .expand((t) => t.events)
        .lastWhere((e) => e.name == 'conductor.planned');
    final candidates = (planned.data!['candidateLOs'] as List)
        .cast<Map<String, dynamic>>();
    expect(candidates, isNotEmpty);
    expect(candidates.first['mean'], isA<double>());

    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));

    // The card says the sign-in is off, and offers the report anyway.
    await _scrollTo(
      tester,
      find.byKey(const ValueKey('github-not-configured')),
    );
    expect(find.text('Connect GitHub'), findsNothing);
    expect(find.text('Report a bug…'), findsOneWidget);

    await _tap(tester, find.text('Report a bug…'));
    await pumpUntilFound(tester, find.text('Report a bug'));
    // No token, so no posting — and no need for it.
    expect(find.text('Post on GitHub'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Save as file'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'The Run button did nothing',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'What went wrong?'),
      'I pressed Run and the output stayed empty.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save as file'));
    await pumpUntil(
      tester,
      file.existsSync,
      reason: 'the report never reached the disk',
    );
    await pumpUntilFound(tester, find.textContaining('Report saved as'));
    expect(
      find.textContaining('Send this file to your teacher.'),
      findsOneWidget,
    );

    // Offered as a dated `.txt` named for the title — what a chat client
    // attaches without fuss, and what the teacher can tell apart.
    expect(harness.fileSaves, hasLength(1));
    expect(
      harness.fileSaves.single.suggestedName,
      matches(
        RegExp(
          r'^ai-tutor-bugreport-\d{4}-\d{2}-\d{2}-the-run-button-did-nothing'
          r'\.txt$',
        ),
      ),
    );
    expect(harness.fileSaves.single.extensions, ['txt']);

    final text = file.readAsStringSync();

    // A file that says what it is on its own.
    expect(text, startsWith('# The Run button did nothing\n'));
    expect(
      text,
      contains(
        RegExp(
          r'^Reported: \d{4}-\d{2}-\d{2} \d{2}:\d{2}  ·  App version '
          '${RegExp.escape(kAppVersion)}\$',
          multiLine: true,
        ),
      ),
    );
    expect(text, contains('I pressed Run and the output stayed empty.'));

    // The runner section, with the runner genuinely absent (#74)…
    expect(text, contains('Python runner state'));
    expect(text, contains('PyRunnerNotInstalled'));
    expect(text, contains('(no host has started this session)'));

    // …the planned turn (#79)…
    expect(text, contains('Turn debug payload'));
    expect(text, contains('conductor.planned'));
    expect(text, contains('"loId": "${candidates.first['loId']}"'));

    // …and nothing about who the student is: not the Windows account name,
    // not the mastery estimates. The teacher may paste this into a public
    // issue as-is.
    expect(text, isNot(contains('student.name')));
    expect(text, contains(r'C:\Users\<user>\'));
    expect(text, isNot(matches(RegExp(r'"(mean|evidence)":\s*[0-9]'))));
    expect(text, contains('"mean": "<redacted>"'));

    await harness.dispose(tester);
    dir.deleteSync(recursive: true);
  });
}
