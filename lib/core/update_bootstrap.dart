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
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

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

/// Runs a process to completion. `Process.run` in production; a fake in
/// tests, so the argument shape of the curl fallback can be asserted without
/// spawning anything.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

Future<ProcessResult> _runProcess(String executable, List<String> arguments) =>
    Process.run(executable, arguments);

/// Where Windows has shipped `curl.exe` since 10 1803: a Schannel build, so
/// it trusts exactly what Edge trusts — the machine's certificate store,
/// including whatever CA a school's TLS-inspecting filter or an endpoint
/// agent has installed there — and chases missing intermediates over AIA.
/// Neither of which Dart's BoringSSL does (#124).
String windowsCurlPath() => p.join(
  Platform.environment['SystemRoot'] ?? r'C:\Windows',
  'System32',
  'curl.exe',
);

/// The Windows-native transport behind [NativeGet]: `curl.exe` at
/// [curlPath], or `null` when there is no such file — in which case the
/// updater keeps today's behaviour and today's error text.
///
/// Requests are shaped as `-sS -L --connect-timeout … [--max-time …]`
/// `--speed-limit 1 --speed-time … -H … -o FILE -w %{http_code} URL`:
///
/// - `-L` matters. The installer asset 302s to
///   `objects.githubusercontent.com`, which sits behind the same inspection.
/// - The body always goes to a file and only the status comes back on
///   stdout, so one shape serves the release JSON, the checksum and the
///   ~250 MB installer alike. A small response is read back and the scratch
///   file removed.
/// - `--speed-limit 1 --speed-time N` is curl's spelling of the stall
///   timeout Dart's download applies ([kDownloadStallTimeout]); `--max-time`
///   is the whole-request deadline and is only set when the caller asked
///   for one.
/// - No `--fail`: an HTTP error is a status the caller interprets — a 404
///   from `/releases/latest` still means "nothing published" — while a
///   non-zero exit is a transport failure and becomes an
///   [UpdateCheckException] carrying curl's own stderr.
///
/// Nothing here weakens verification: the fallback trusts what the operating
/// system trusts, and `verifyAndCleanUp` still hashes what arrives.
NativeGet? curlNativeGet({
  required String curlPath,
  ProcessRunner run = _runProcess,
}) {
  if (!File(curlPath).existsSync()) return null;
  return (
    Uri url, {
    Map<String, String> headers = const <String, String>{},
    Duration? timeout,
    File? to,
  }) async {
    final Directory? scratch = to == null
        ? Directory.systemTemp.createTempSync('ai_tutor_update_')
        : null;
    final File out = to ?? File(p.join(scratch!.path, 'body'));
    try {
      final List<String> arguments = <String>[
        '-sS',
        '-L',
        '--connect-timeout',
        '${kUpdateRequestTimeout.inSeconds}',
        if (timeout != null) ...<String>['--max-time', '${timeout.inSeconds}'],
        '--speed-limit',
        '1',
        '--speed-time',
        '${kDownloadStallTimeout.inSeconds}',
        for (final MapEntry<String, String> h in headers.entries) ...<String>[
          '-H',
          '${h.key}: ${h.value}',
        ],
        '-o',
        out.path,
        '-w',
        '%{http_code}',
        url.toString(),
      ];
      final ProcessResult result = await run(curlPath, arguments);
      if (result.exitCode != 0) {
        throw UpdateCheckException(
          'curl.exe exited with ${result.exitCode} for $url: '
          '${result.stderr.toString().trim()}',
        );
      }
      final int? status = int.tryParse(result.stdout.toString().trim());
      if (status == null) {
        throw UpdateCheckException(
          'curl.exe reported no HTTP status for $url: '
          '"${result.stdout.toString().trim()}"',
        );
      }
      final Uint8List body = to == null && out.existsSync()
          ? await out.readAsBytes()
          : Uint8List(0);
      return http.Response.bytes(body, status);
    } finally {
      try {
        scratch?.deleteSync(recursive: true);
      } on FileSystemException {
        // A leftover scratch directory is not worth failing the check over.
      }
    }
  };
}

/// The transport the updater falls back to when Dart cannot complete a TLS
/// handshake (#124): `curl.exe` on Windows, nothing anywhere else. The
/// integration harness overrides it — with `null` to keep a test boot from
/// ever spawning a process, or with a stand-in that trusts a loopback
/// certificate the way Schannel would trust the school's.
final nativeGetProvider = Provider<NativeGet?>(
  (_) => Platform.isWindows ? curlNativeGet(curlPath: windowsCurlPath()) : null,
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
  final nativeGet = ref.watch(nativeGetProvider);
  return UpdateServices(
    localVersion: ref.watch(appVersionProvider),
    feed: feedUrl == null
        ? () async => null
        : () => fetchLatestRelease(
            feedUrl,
            nativeGet: nativeGet,
            log: debugPrint,
          ),
    download: (release, onProgress) => downloadToTemp(
      release.url,
      onProgress: onProgress,
      nativeGet: nativeGet,
      // A check that only got through natively is not going to fare better
      // on the installer, which sits behind the same inspection.
      preferNative: release.viaNativeTransport,
      log: debugPrint,
    ),
    verify: verifyAndCleanUp,
    run: (installer) => launch(installer.path, kSilentInstallArguments),
    stashNotes: (version, notes) =>
        stashReleaseNotes(version: version, notes: notes),
    autoCheck: feedUrl != null && ref.watch(updateAutoCheckProvider),
  );
});
