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

/// Whether a launch checks for an update by itself.
///
/// `kReleaseMode`, so a `flutter run` checkout and every integration-test
/// boot stay offline (#47). Before this gate, a developer running from source
/// had a release build installed over their machine the moment the published
/// release went ahead of the working tree. `UpdateController.check()` still
/// runs when it is asked to, which is what the manual check in #48 calls.
final updateAutoCheckProvider = Provider<bool>((_) => kReleaseMode);

/// The switches the installer is handed: no wizard, and never reboot the
/// machine out from under a student.
const List<String> kSilentInstallArguments = <String>[
  '/VERYSILENT',
  '/NORESTART',
];

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
  return UpdateServices(
    localVersion: kAppVersion,
    feed: feedUrl == null
        ? () async => null
        : () => fetchLatestRelease(feedUrl),
    download: (release, onProgress) =>
        downloadToTemp(release.url, onProgress: onProgress),
    verify: verifyAndCleanUp,
    run: (installer) =>
        runInstallerAndExit(installer, args: kSilentInstallArguments),
    autoCheck: feedUrl != null && ref.watch(updateAutoCheckProvider),
  );
});
