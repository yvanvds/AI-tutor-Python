// End-to-end (#165): a build older than the minimum version the school has
// set on `config/global` gets the update screen instead of the app, with
// nothing to dismiss; a minimum raised while the app is open takes effect on
// the next poll; and every graded turn now says which build wrote it.
//
// Why: the update is offered, not imposed (#48), and a student who took
// **Later** on every launch kept running a build from before #103. That
// build's `toMap` did not know `highestPositiveDifficulty`, Cosmos treats an
// upsert as a whole-document replacement, and so her own session erased the
// field again within two minutes of a teacher restoring it by hand. Nothing
// in the app could see it happening — "which docs carry the field" split by
// student, not by date, and looked like old seed data. Two answers, both
// driven here through the real root widget, the real update wiring against
// a loopback release server, and the real tutor for the turn:
//
//   - a gate: `MinimumVersion` on `config/global`, read by `GoalsApp` in
//     front of `AppShell`, so a build below it never mounts the shell that
//     starts the session — and gets the one thing it may do, update, with
//     no **Later** this time;
//   - detection: `clientVersion` on every `turn_history` doc.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/update_required.dart -d windows

import 'dart:typed_data';

import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/session/session_view.dart';
import 'package:ai_tutor_python/features/shell/app_shell.dart';
import 'package:ai_tutor_python/features/shell/sidebar.dart';
import 'package:ai_tutor_python/version.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/fake_release_server.dart';
import '../harness/scripted_llm.dart';

final _screen = find.byKey(const ValueKey('update-required'));
final _message = find.byKey(const ValueKey('update-required-message'));
final _status = find.byKey(const ValueKey('update-required-status'));
final _applyButton = find.byKey(const ValueKey('update-required-apply'));
final _checkButton = find.byKey(const ValueKey('update-required-check'));
final _progressBar = find.byKey(const ValueKey('update-required-progress'));
final _offerBar = find.byKey(const ValueKey('update-offer'));
final _laterButton = find.byKey(const ValueKey('update-offer-later'));

/// The seed's `config/global` doc, with the school's minimum set on it.
Map<String, dynamic> configDoc({String? minimumVersion}) => {
  'id': 'global',
  'type': 'config',
  'Model': 'gpt-4o',
  'ApiKey': '',
  if (minimumVersion != null) 'MinimumVersion': minimumVersion,
};

String? _messageSays(WidgetTester tester) =>
    _message.evaluate().isEmpty ? null : tester.widget<Text>(_message).data;

String? _statusSays(WidgetTester tester) =>
    _status.evaluate().isEmpty ? null : tester.widget<Text>(_status).data;

const String kExercise = 'naam = ___\nprint("Hallo, " + naam)';
const String kNextExercise = 'stad = ___\nprint("Welkom in " + stad)';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a build below the minimum gets the update screen instead of '
      'the app: no shell, no Later, and Update drives the real download to '
      'its checksum', (tester) async {
    // Junk bytes: whatever they hash to, it is not the published
    // all-zeroes checksum, so `verifyAndCleanUp` rejects them and nothing
    // is ever handed to the installer launcher.
    final installer = Uint8List.fromList(
      List<int>.generate(64 * 1024, (i) => i % 256),
    );
    final server = await FakeReleaseServer.start(
      version: '99.0.0+1',
      installerBytes: installer,
    );

    final harness = AppHarness(
      appVersion: '2.4.0+21',
      updateFeedUrl: server.feedUrl,
      extraDocs: {
        'config': [configDoc(minimumVersion: '2.5.0')],
      },
    );
    await harness.boot(tester, waitForShell: false);

    await pumpUntilFound(tester, _screen);
    // Not chrome on top of the app: there is no app. The shell — and with
    // it the session view whose chat widget starts the tutor — never
    // mounted, and neither did the offer bar with its Later.
    expect(find.byType(AppShell), findsNothing);
    expect(find.byType(Sidebar), findsNothing);
    expect(find.byType(SessionView), findsNothing);
    expect(_offerBar, findsNothing);
    expect(_laterButton, findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    final message = _messageSays(tester)!;
    expect(message, contains('2.4.0+21'));
    expect(message, contains('2.5.0'));

    // The launch check ran from the screen, since the shell's never will:
    // the published release is what the button offers.
    await pumpUntilFound(tester, _applyButton);
    expect(find.textContaining('99.0.0+1'), findsWidgets);
    expect(
      server.checksumRequests,
      greaterThan(0),
      reason: 'the release was offered without fetching its checksum',
    );
    expect(server.installerRequests, 0, reason: 'downloaded before a press');
    expect(_progressBar, findsNothing);

    await tester.tap(_applyButton);
    await pumpUntilFound(tester, _progressBar);
    expect(server.installerRequests, 1);
    expect(tester.widget<FilledButton>(_applyButton).onPressed, isNull);

    await pumpUntil(
      tester,
      () => _statusSays(tester)?.contains('checksum') ?? false,
      timeout: const Duration(seconds: 30),
      reason: 'the failed checksum was never reported on the screen',
    );
    expect(harness.installerLaunches, isEmpty);
    // Still gated after the failed attempt — the button is back for another
    // try, and there is still nothing to dismiss.
    expect(_screen, findsOneWidget);
    expect(_applyButton, findsOneWidget);
    expect(_laterButton, findsNothing);
    expect(find.byType(AppShell), findsNothing);

    await harness.dispose(tester);
    await server.close();
  });

  testWidgets('a minimum raised while the app is open replaces it on the '
      'next poll, and one lowered again lets it back in', (tester) async {
    // The build as shipped, no minimum set, no release feed: the app boots
    // the way every other flow sees it.
    final harness = AppHarness();
    await harness.boot(tester);
    expect(_screen, findsNothing);
    expect(find.byType(Sidebar), findsOneWidget);

    // The teacher sets the minimum above every build there is.
    harness.cosmos['config'].upsert(configDoc(minimumVersion: '99.0.0'));
    await pumpUntilFound(tester, _screen, timeout: const Duration(seconds: 20));
    expect(find.byType(AppShell), findsNothing);
    expect(_laterButton, findsNothing);
    final message = _messageSays(tester)!;
    expect(message, contains(kAppVersion));
    expect(message, contains('99.0.0'));
    // With no release on offer the screen still gives the one way forward.
    expect(_checkButton, findsOneWidget);
    expect(_applyButton, findsNothing);

    // A typo corrected: the app comes back without a restart.
    harness.cosmos['config'].upsert(configDoc());
    await pumpUntilFound(
      tester,
      find.byType(AppShell),
      timeout: const Duration(seconds: 20),
    );
    expect(_screen, findsNothing);

    await harness.dispose(tester);
  });

  testWidgets('a graded turn records the build that wrote it', (tester) async {
    final harness = AppHarness(
      // Pinned to something that is not `kAppVersion`, so the doc can only
      // have got it from the running build's version provider.
      appVersion: '2.9.9+99',
      llm: ScriptedLlm([
        completeCodeReply(text: 'Vul de naam in.', code: kExercise),
        codeFeedbackReply(
          text: 'Goed zo.',
          quality: 'correct',
          loSignals: const [
            {
              'subgoalId': 's1',
              'loId': 'lo-print',
              'signal': 'positive',
              'strength': 'strong',
            },
          ],
        ),
        completeCodeReply(text: 'Nu de stad.', code: kNextExercise),
      ]),
    );
    await harness.boot(tester);
    expect(_screen, findsNothing, reason: 'no minimum is set');

    String editorText() =>
        (tester.widget<CodeField>(find.byType(CodeField)).controller).text;

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntil(
      tester,
      () => editorText() == kExercise,
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
      () => editorText() == kNextExercise,
      timeout: const Duration(seconds: 30),
      reason: 'the next exercise never reached the editor',
    );

    final turn = harness.cosmos['turn_history'].docs.values.single;
    expect(turn['subgoalId'], 's1');
    expect(turn['overallQuality'], 'correct');
    // Before #165 the doc carried no trace of the client that wrote it, and
    // an out-of-date laptop could only be inferred from the shape of the
    // belief docs it left behind.
    expect(turn['clientVersion'], '2.9.9+99');

    await harness.dispose(tester);
  });
}
