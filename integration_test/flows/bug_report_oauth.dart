// End-to-end (#28, exercising #57): signing in to GitHub with the OAuth
// device flow from the Options panel, and filing a bug report with the token
// it produces.
//
// Why this has to run against the real app rather than the widget test next
// to it:
//
//   - the whole point of the flow is that it *waits*. The app hands out a
//     code, keeps polling on a real timer while the student is elsewhere, and
//     has to come back to a live widget tree when the answer changes. A
//     widget test drives that under `FakeAsync` with a hand-wound clock; only
//     a real run proves the polling, the frames and the state actually
//     survive each other.
//   - the Bug reports card sits part-way down a real, lazily-built
//     `ListView`. An earlier version of this showed the code *inside* that
//     card, and scrolling the card past the fold disposed its state and
//     silently abandoned the sign-in the student was in the middle of. Only a
//     real window with a real scroll extent shows that; the widget test,
//     which lays every card out at once, cannot.
//   - the token then travels through SharedPreferences into a second service
//     (`GitHubIssueService`) and back out as a posted issue. The handover
//     between the two is only wired up in the real app.
//
// GitHub itself is a loopback server (`harness/fake_github_server.dart`); the
// browser launcher is recorded rather than run, so no window opens on the
// machine running the suite.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/bug_report_oauth.dart -d windows

import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:py_runner/py_runner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../harness/app_harness.dart';
import '../harness/fake_github_server.dart';

/// A client id shaped like the ones GitHub hands out. Its only job is to be
/// non-empty: the fake server never checks it.
const String _clientId = 'Ov23liINTEGRATIONTEST';

/// Stands for the runner being *completely* unavailable (#74) — no bundle, no
/// host, nothing to ask. The account name in the message is deliberate: it is
/// what the real `PyRunnerNotInstalled` carries, and what must not reach a
/// public repository.
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
  final scrollable = find
      .descendant(
        of: find.byType(OptionsPage),
        matching: find.byType(Scrollable),
      )
      .first;
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(finder, 120, scrollable: scrollable);
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 200));
}

/// Scrolls the control itself into view and then taps it.
///
/// Never `tap` without this: `ensureVisible` stops the moment its target's
/// bottom edge clears the fold, so a button one row *below* the thing that
/// was scrolled to is still off-screen, and tapping it hit-tests somewhere
/// else entirely. Which of the panel's buttons that catches depends on where
/// the list happened to be — an intermittent failure, not a reliable one.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _scrollTo(tester, finder);
  await tester.tap(finder);
  await tester.pump();
}

/// Drops any confirmation still on screen. A snackbar sits at the bottom of
/// the window over whatever is there, including the button the next step
/// wants to press.
Future<void> _clearSnacks(WidgetTester tester) async {
  ScaffoldMessenger.of(tester.element(find.byType(OptionsPage)))
      .clearSnackBars();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _openOptions(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Options'));
  await pumpUntilFound(tester, find.byType(OptionsPage));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Bug reports: a device code signs the student in, and the bug '
      'goes to GitHub', (tester) async {
    final github = await FakeGitHubServer.start();
    final harness = AppHarness(github: github, githubOAuthClientId: _clientId);
    await harness.boot(tester);
    await _openOptions(tester);

    await _scrollTo(tester, find.text('Not connected to GitHub.'));
    expect(find.text('Report a bug…'), findsNothing);

    await _tap(tester, find.text('Connect GitHub'));
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey('github-device-dialog')),
    );

    // The code is on screen, readable, and the app is waiting for it. The
    // dialog is a modal route rather than a card in the list on purpose: it
    // cannot be scrolled out of existence mid-sign-in (which is exactly how
    // an inline panel lost the flow the student was in the middle of).
    expect(
      tester
          .widget<SelectableText>(
            find.byKey(const ValueKey('github-device-code')),
          )
          .data,
      kFakeUserCode,
    );
    expect(
      find.text('Waiting for you to approve it on GitHub…'),
      findsOneWidget,
    );

    // Nothing is stored while the student is still deciding.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('github_token'), isFalse);

    // The browser button hands the operating system exactly the URL GitHub
    // named, and no other. (No scrolling: the dialog is fully on screen.)
    await tester.tap(find.text('Open GitHub'));
    await tester.pump();
    expect(harness.browserLaunches, [github.verificationUri]);

    // It really is polling, on its own timer, while nothing else happens.
    await pumpUntil(
      tester,
      () => github.polls >= 2,
      reason: 'the app stopped polling GitHub while waiting for approval',
    );
    expect(
      find.byKey(const ValueKey('github-device-dialog')),
      findsOneWidget,
      reason: 'the code must stay on screen until it is approved',
    );

    // Approval in the browser, and the next poll turns into a token.
    github.approved = true;
    await pumpUntilFound(
      tester,
      find.text('Connected to GitHub as $kFakeGitHubLogin.'),
    );
    await pumpUntilGone(
      tester,
      find.byKey(const ValueKey('github-device-dialog')),
    );
    expect(prefs.getString('github_token'), kFakeGitHubToken);

    // …and the token is good for the thing it was collected for. The
    // confirmation snackbar goes first: it covers the bottom of the window,
    // and "Report a bug…" can land under it.
    await _clearSnacks(tester);
    await _tap(tester, find.text('Report a bug…'));
    await pumpUntilFound(tester, find.text('Report a bug'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'The Run button did nothing',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Post issue'));
    await pumpUntil(
      tester,
      () => github.issues.isNotEmpty,
      reason: 'the issue never reached GitHub',
    );

    expect(github.issues.single['title'], 'The Run button did nothing');
    await pumpUntilFound(tester, find.textContaining('Issue posted:'));

    await harness.dispose(tester);
    await github.close();
  });

  // #74. The report that started this said "the python script did not run",
  // and arrived describing the tutor turn instead — the runner was never
  // mentioned. So: file the same report with the runner genuinely absent, and
  // check the issue that lands on GitHub can answer the question on its own.
  //
  // End-to-end rather than a widget test, because the thing under test is what
  // the *app* posts: the runner behind the Run button, the panel's report
  // button, the body builder and the real HTTP call, in that order. A widget
  // test can only assert on a body it assembled itself.
  testWidgets('Bug reports: the issue says what the Python runner was doing, '
      'with no host running and no username in it', (tester) async {
    final github = await FakeGitHubServer.start();
    final harness = AppHarness(
      github: github,
      githubOAuthClientId: _clientId,
      pyRunner: PyRunner(locator: _MissingPythonLocator()),
    );
    await harness.boot(tester);
    await _openOptions(tester);

    // Already approved in the browser: this flow is about the report body, and
    // the sign-in itself is covered above.
    github.approved = true;
    await _scrollTo(tester, find.text('Not connected to GitHub.'));
    await _tap(tester, find.text('Connect GitHub'));
    await pumpUntilFound(
      tester,
      find.text('Connected to GitHub as $kFakeGitHubLogin.'),
    );

    await _clearSnacks(tester);
    await _tap(tester, find.text('Report a bug…'));
    await pumpUntilFound(tester, find.text('Report a bug'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'the python script did not run',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Post issue'));
    await pumpUntil(
      tester,
      () => github.issues.isNotEmpty,
      reason: 'the issue never reached GitHub',
    );

    final body = github.issues.single['body'] as String;

    // Attached with no dropdown, no turn to attach, and no host alive.
    expect(body, contains('Python runner state'));
    expect(body, isNot(contains('Turn debug payload')));
    expect(body, contains('PyRunnerNotInstalled'));
    expect(body, contains('python.exe'));
    expect(body, contains('(no host has started this session)'));
    expect(body, contains('(no run has finished this session)'));

    // Public repo, student's own account: the path is there, the name is not.
    expect(body, isNot(contains('student.name')));
    expect(body, contains(r'C:\Users\<user>\'));

    await harness.dispose(tester);
    await github.close();
  });

  // A fork that never registered an OAuth app is a legitimate build. It must
  // say so where the sign-in would have been, rather than offering a button
  // that could only fail — and it must not reach out at all.
  testWidgets('Bug reports: a build with no OAuth client id says so instead '
      'of offering a sign-in', (tester) async {
    final github = await FakeGitHubServer.start();
    final harness = AppHarness(github: github, githubOAuthClientId: '');
    await harness.boot(tester);
    await _openOptions(tester);

    await _scrollTo(
      tester,
      find.byKey(const ValueKey('github-not-configured')),
    );
    expect(
      find.textContaining('compiled without a GitHub OAuth client id'),
      findsOneWidget,
    );
    expect(find.text('Connect GitHub'), findsNothing);
    expect(find.text('Not connected to GitHub.'), findsNothing);
    expect(github.polls, 0);
    expect(harness.browserLaunches, isEmpty);

    await harness.dispose(tester);
    await github.close();
  });
}
