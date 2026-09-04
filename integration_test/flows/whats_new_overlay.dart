// End-to-end (#119): after the app updates itself, the first launch of the
// new build tells the student what changed — once.
//
// The feature spans a process boundary, which is exactly why it needs to run
// against the real app twice rather than against the controller alone. The
// updater already fetched the release notes and then dropped them:
// `runInstallerAndExit` ends the process, and the build that comes back has
// never spoken to GitHub. So the two legs here are the two sides of that
// boundary:
//
//   1. The outgoing app, driven through the real feed, the real streamed
//      download and the real sha256, leaves the notes on disk *before* the
//      installer handover — the last moment any code of its runs.
//   2. The build that comes back reads them, shows the card, and forgets them
//      when the student clicks it away. A third boot proves the "once": the
//      same build, started again, says nothing.
//
// The installer launcher is replaced by the harness in every flow (it spawns
// a real setup and calls `exit(0)`), and the second leg stands in for the
// restart by booting a fresh app pinned to the version the installer would
// have put down. Nothing here reaches github.com — the feed is the loopback
// `FakeReleaseServer`.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/whats_new_overlay.dart -d windows

import 'dart:io';
import 'dart:typed_data';

import 'package:ai_tutor_python/core/whats_new_store.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../harness/app_harness.dart';
import '../harness/fake_release_server.dart';

const String _installedVersion = '99.0.0+1';

/// What `FakeReleaseServer` publishes as the release body for that version.
const String _publishedNotes = 'What changed in $_installedVersion.';

final _applyButton = find.byKey(const ValueKey('update-offer-apply'));
final _overlay = find.byKey(const ValueKey('whats-new-overlay'));
final _title = find.byKey(const ValueKey('whats-new-title'));
final _notes = find.byKey(const ValueKey('whats-new-notes'));
final _dismiss = find.byKey(const ValueKey('whats-new-dismiss'));

/// The stash as it stands on disk, in the shape `AppHarness.prefs` seeds a
/// launch from — so a leg can hand the next boot literally what the previous
/// one left behind, rather than a hand-written guess at it.
Future<Map<String, Object>> _stashOnDisk() async {
  final prefs = await SharedPreferences.getInstance();
  return <String, Object>{
    for (final key in const [kWhatsNewVersionPref, kWhatsNewNotesPref])
      if (prefs.getString(key) != null) key: prefs.getString(key)!,
  };
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an accepted update leaves its notes behind for the build that '
      'comes back', (tester) async {
    // Not a real setup binary — nothing runs it. It only has to hash to the
    // value the release publishes so the app's own verify step passes and the
    // flow reaches the handover.
    final installerBytes = Uint8List.fromList(
      List<int>.generate(48 * 1024, (i) => (i * 11) % 256),
    );
    final server = await FakeReleaseServer.start(
      version: _installedVersion,
      installerBytes: installerBytes,
      installerSha256: sha256.convert(installerBytes).toString(),
    );

    final harness = AppHarness(updateFeedUrl: server.feedUrl);
    await harness.boot(tester);

    // Nothing is stashed on the way in: only an update actually going ahead
    // may leave notes for the next launch.
    expect(await _stashOnDisk(), isEmpty);

    await pumpUntilFound(tester, _applyButton);
    await tester.tap(_applyButton);
    await pumpUntil(
      tester,
      () => harness.installerLaunches.isNotEmpty,
      timeout: const Duration(seconds: 30),
      reason: 'the verified installer was never handed over',
    );

    // The handover has happened — in production this process would already be
    // gone — so whatever the next build needs is on disk by now.
    final stash = await _stashOnDisk();
    expect(stash[kWhatsNewVersionPref], _installedVersion);
    expect(stash[kWhatsNewNotesPref], _publishedNotes);

    await harness.dispose(tester);
    await server.close();
    final downloaded = File(harness.installerLaunches.single.executable);
    if (downloaded.existsSync()) downloaded.deleteSync();
  });

  testWidgets('the first launch of the installed version shows the notes, '
      'and only that launch', (tester) async {
    // The restart, stood in for: a fresh app that reports the version the
    // installer put down, starting from exactly the stash the previous leg
    // would have written.
    final harness = AppHarness(
      appVersion: _installedVersion,
      prefs: const {
        kWhatsNewVersionPref: _installedVersion,
        kWhatsNewNotesPref: _publishedNotes,
      },
    );
    await harness.boot(tester);

    await pumpUntilFound(tester, _overlay);
    expect(
      tester.widget<Text>(_title).data,
      "What's new in $_installedVersion",
    );
    expect(tester.widget<Text>(_notes).data, _publishedNotes);

    // Clicking it away is the only thing that consumes the stash.
    await tester.tap(_dismiss);
    await pumpUntilGone(tester, _overlay);
    expect(await _stashOnDisk(), isEmpty);

    await harness.dispose(tester);

    // Start the same build again, from what the dismissal left behind.
    final again = AppHarness(
      appVersion: _installedVersion,
      prefs: await _stashOnDisk(),
    );
    await again.boot(tester);

    // A few seconds of real frames: the load is fired from the shell's first
    // post-frame callback and is asynchronous, so a card that was going to
    // appear would have appeared by now.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_overlay, findsNothing);
    expect(find.textContaining("What's new"), findsNothing);

    await again.dispose(tester);
  });
}
