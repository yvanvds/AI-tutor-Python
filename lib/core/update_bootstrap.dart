/// The production wiring behind the update check (#47): where a published
/// release is read from, how its installer is fetched and verified, and how
/// it is launched.
///
/// Held apart from `update_controller.dart` on purpose — this is the only
/// file in the update layer that touches the real network, the real
/// filesystem and a real process, so everything above it stays drivable from
/// a test with no network and no `%TEMP%` write.
library;

import 'dart:io';

import 'package:ai_tutor_python/core/github_release.dart';
import 'package:ai_tutor_python/core/update_controller.dart';
import 'package:ai_tutor_python/core/update_info.dart';
import 'package:ai_tutor_python/core/whats_new_store.dart';
import 'package:ai_tutor_python/version.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the shell looks for a newer installer: GitHub's `/releases/latest`
/// for this repository (#50). Before that it was a `version.json` on GitHub
/// Pages, a second artifact that had to be kept in lockstep with the release
/// it described — and once was not (#45).
///
/// `null` disables the check entirely — the integration harness (#28)
/// overrides it, so a test boot never fetches, downloads or runs an
/// installer, and a flow that wants to drive the check points it at a
/// loopback server that speaks the same API.
final updateFeedUrlProvider = Provider<Uri?>((_) => kLatestReleaseEndpoint);

/// The version this build reports — `kAppVersion`, generated into
/// `version.dart` by `tooling/build_release.ps1`.
///
/// A provider rather than a direct read so the two things that compare
/// against it — the update check (`UpdateServices.localVersion`) and the
/// "What's new" stash (#119), which only fires when the stashed version *is*
/// the running one — can both be driven end-to-end without shipping a build.
final appVersionProvider = Provider<String>((_) => kAppVersion);

/// Whether a launch checks for an update by itself.
///
/// `kReleaseMode`, so a `flutter run` checkout and every integration-test
/// boot stay offline (#47). Before this gate, a developer running from source
/// had a release build installed over their machine the moment the published
/// release went ahead of the working tree. `UpdateController.check()` still
/// runs when it is asked to, which is what the manual check in #48 calls.
final updateAutoCheckProvider = Provider<bool>((_) => kReleaseMode);

/// The switches the installer is handed (#49).
///
/// - `/SILENT` rather than `/VERYSILENT`: the student sees a progress window,
///   so the app vanishing for half a minute is visibly *something happening*
///   rather than a crash.
/// - `/NOCANCEL`: there is no safe point to abandon a half-replaced install.
/// - `/NORESTART`: never reboot the machine out from under a student.
/// - `/RELAUNCH=1`: the custom switch `installer.iss` reads in its
///   `WantsRelaunch` check, which is what starts the app again afterwards. The
///   installer's ordinary `[Run]` entry is flagged `skipifsilent` and so is
///   skipped in exactly this case, which is why the app never used to come
///   back from an update at all.
const List<String> kSilentInstallArguments = <String>[
  '/SILENT',
  '/NOCANCEL',
  '/NORESTART',
  '/RELAUNCH=1',
];

/// How a verified installer is actually handed to Windows: spawn it, then end
/// this process.
///
/// A seam of its own because it is the one step that cannot run inside a test
/// — `Process.start` would put a real setup binary on the machine running the
/// suite and `exit(0)` would take the test runner with it. Overriding
/// [installerLauncherProvider] lets an end-to-end run drive the real feed,
/// download and checksum wiring and then assert on the handover itself.
typedef InstallerLauncher = Future<void> Function(
  String executable,
  List<String> arguments,
);

/// The production launcher. Never returns.
final installerLauncherProvider = Provider<InstallerLauncher>(
  (_) => runInstallerAndExit,
);

/// Verifies the download against the hash published beside it, and removes
/// it when it does not match: a corrupted or substituted installer is not
/// something to leave lying in `%TEMP%` for a later run to trip over.
Future<bool> verifyAndCleanUp(File installer, String expectedSha256) async {
  if (await verifySha256(installer, expectedSha256)) return true;
  try {
    installer.deleteSync();
  } on FileSystemException {
    // Nothing more to do; the installer is not going to run either way.
  }
  return false;
}

/// The update seams for a real install (#47).
///
/// A `null` feed URL yields a feed that reports "nothing published" without
/// a request, and switches [UpdateServices.autoCheck] off, so an override of
/// [updateFeedUrlProvider] alone is enough to take the whole feature off the
/// network.
final updateServicesProvider = Provider<UpdateServices>((ref) {
  final feedUrl = ref.watch(updateFeedUrlProvider);
  final launch = ref.watch(installerLauncherProvider);
  return UpdateServices(
    localVersion: ref.watch(appVersionProvider),
    feed: feedUrl == null
        ? () async => null
        : () => fetchLatestRelease(feedUrl),
    download: (release, onProgress) =>
        downloadToTemp(release.url, onProgress: onProgress),
    verify: verifyAndCleanUp,
    run: (installer) => launch(installer.path, kSilentInstallArguments),
    stashNotes: (version, notes) =>
        stashReleaseNotes(version: version, notes: notes),
    autoCheck: feedUrl != null && ref.watch(updateAutoCheckProvider),
  );
});
