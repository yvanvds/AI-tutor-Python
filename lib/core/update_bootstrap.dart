/// The production wiring behind the update check (#47): where the manifest
/// is read from, how an installer is fetched and verified, and how it is
/// launched.
///
/// Held apart from `update_controller.dart` on purpose — this is the only
/// file in the update layer that touches the real network, the real
/// filesystem and a real process, so everything above it stays drivable from
/// a test with no network and no `%TEMP%` write.
library;

import 'dart:io';

import 'package:ai_tutor_python/core/update_controller.dart';
import 'package:ai_tutor_python/core/update_info.dart';
import 'package:ai_tutor_python/version.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the shell looks for a newer installer. `null` disables the check
/// entirely — the integration harness (#28) overrides it so a test boot never
/// fetches, downloads or runs an installer. #50 moves this to the GitHub
/// Releases API.
final updateManifestUrlProvider = Provider<Uri?>(
  (_) => Uri.parse('https://yvanvds.github.io/AI-tutor-Python/version.json'),
);

/// Whether a launch checks for an update by itself.
///
/// `kReleaseMode`, so a `flutter run` checkout and every integration-test
/// boot stay offline (#47). Before this gate, a developer running from source
/// had a release build installed over their machine the moment the published
/// manifest went ahead of the working tree. `UpdateController.check()` still
/// runs when it is asked to, which is what the manual check in #48 calls.
final updateAutoCheckProvider = Provider<bool>((_) => kReleaseMode);

/// The switches the installer is handed: no wizard, and never reboot the
/// machine out from under a student.
const List<String> kSilentInstallArguments = <String>[
  '/VERYSILENT',
  '/NORESTART',
];

/// Verifies the download against the manifest hash, and removes it when it
/// does not match: a corrupted or substituted installer is not something to
/// leave lying in `%TEMP%` for a later run to trip over.
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
/// A `null` manifest URL yields a feed that reports "nothing published"
/// without a request, and switches [UpdateServices.autoCheck] off, so an
/// override of [updateManifestUrlProvider] alone is enough to take the whole
/// feature off the network.
final updateServicesProvider = Provider<UpdateServices>((ref) {
  final manifestUrl = ref.watch(updateManifestUrlProvider);
  return UpdateServices(
    localVersion: kAppVersion,
    feed: manifestUrl == null
        ? () async => null
        : () => fetchUpdateInfo(manifestUrl),
    // The progress callback is part of the seam but not yet fed: streaming
    // progress out of `downloadToTemp` arrives with the progress UI in #48.
    download: (release, onProgress) => downloadToTemp(release.url),
    verify: verifyAndCleanUp,
    run: (installer) =>
        runInstallerAndExit(installer, args: kSilentInstallArguments),
    autoCheck: manifestUrl != null && ref.watch(updateAutoCheckProvider),
  );
});
