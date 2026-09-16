/// The production wiring behind the update check (#47): where a published
/// release is read from, how its installer is fetched and verified, and how
/// it is launched.
///
/// Held apart from `update_controller.dart` on purpose — this is the only
/// file in the update layer that touches the real network, the real
/// filesystem, a real process and the registry, so everything above it stays
/// drivable from a test with no network and no `%TEMP%` write.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ai_tutor_python/core/github_release.dart';
import 'package:ai_tutor_python/core/update_controller.dart';
import 'package:ai_tutor_python/core/update_info.dart';
import 'package:ai_tutor_python/core/update_proxy.dart';
import 'package:ai_tutor_python/core/whats_new_store.dart';
import 'package:ai_tutor_python/version.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart'
    show
        ERROR_SUCCESS,
        HKEY_CURRENT_USER,
        HKEY_LOCAL_MACHINE,
        RRF_RT_REG_DWORD,
        RRF_RT_REG_SZ,
        RegGetValue;

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
/// - `--proxy` when the machine has one ([proxy], #133): `curl.exe` reads
///   `https_proxy` from the environment by itself but never Internet
///   Options, so it is told explicitly — the same decision Dart's client was
///   handed, bypass list included.
///
/// Nothing here weakens verification: the fallback trusts what the operating
/// system trusts, and `verifyAndCleanUp` still hashes what arrives.
NativeGet? curlNativeGet({
  required String curlPath,
  ProcessRunner run = _runProcess,
  UpdateProxy? proxy,
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
      final String? via = proxy?.curlProxyFor(url);
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
        if (via != null) ...<String>['--proxy', via],
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

/// Where Internet Options keeps the proxy setting, relative to the hive.
const String _internetSettingsKey =
    r'Software\Microsoft\Windows\CurrentVersion\Internet Settings';

/// The policy that moves the setting from the user's hive to the machine's:
/// "Make proxy settings per-machine (rather than per-user)", which a school
/// that manages its laptops may well have set. `ProxySettingsPerUser = 0`
/// under this key means Internet Options reads `HKLM`, not `HKCU`.
const String _internetSettingsPolicyKey =
    r'Software\Policies\Microsoft\Windows\CurrentVersion\Internet Settings';

String? _registryString(int hive, String key, String name) => using((
  Arena arena,
) {
  final Pointer<Utf16> keyPtr = key.toNativeUtf16(allocator: arena);
  final Pointer<Utf16> namePtr = name.toNativeUtf16(allocator: arena);
  final Pointer<Uint32> size = arena<Uint32>();
  // Once for the size, once for the bytes; the API guarantees the
  // terminating NUL for a string type.
  if (RegGetValue(
            hive,
            keyPtr,
            namePtr,
            RRF_RT_REG_SZ,
            nullptr,
            nullptr,
            size,
          ) !=
          ERROR_SUCCESS ||
      size.value == 0) {
    return null;
  }
  final Pointer<Uint8> data = arena<Uint8>(size.value);
  if (RegGetValue(hive, keyPtr, namePtr, RRF_RT_REG_SZ, nullptr, data, size) !=
      ERROR_SUCCESS) {
    return null;
  }
  return data.cast<Utf16>().toDartString();
});

int? _registryDword(int hive, String key, String name) => using((Arena arena) {
  final Pointer<Utf16> keyPtr = key.toNativeUtf16(allocator: arena);
  final Pointer<Utf16> namePtr = name.toNativeUtf16(allocator: arena);
  final Pointer<Uint32> data = arena<Uint32>();
  final Pointer<Uint32> size = arena<Uint32>()..value = sizeOf<Uint32>();
  if (RegGetValue(
        hive,
        keyPtr,
        namePtr,
        RRF_RT_REG_DWORD,
        nullptr,
        data,
        size,
      ) !=
      ERROR_SUCCESS) {
    return null;
  }
  return data.value;
});

/// The proxy setting of Internet Options, as it sits in the registry (#133):
/// `ProxyEnable`, `ProxyServer` and `ProxyOverride` under
/// `HKCU\…\Internet Settings` — or under `HKLM` when policy has made the
/// setting per-machine. Windows only.
///
/// Read through `RegGetValue` rather than by spawning `reg.exe`: this runs
/// on every launch, and three registry values are not worth a process. Only
/// the reading lives here; `proxyFromInternetSettings` turns the values into
/// an [UpdateProxy], and is what the tests pin.
InternetSettingsProxy readInternetSettingsProxy() {
  final int hive =
      _registryDword(
            HKEY_LOCAL_MACHINE,
            _internetSettingsPolicyKey,
            'ProxySettingsPerUser',
          ) ==
          0
      ? HKEY_LOCAL_MACHINE
      : HKEY_CURRENT_USER;
  return (
    enabled: _registryDword(hive, _internetSettingsKey, 'ProxyEnable') == 1,
    server: _registryString(hive, _internetSettingsKey, 'ProxyServer'),
    override: _registryString(hive, _internetSettingsKey, 'ProxyOverride'),
  );
}

/// The proxy this machine states for the updater's requests (#133), or
/// `null` for a direct connection: the environment first (`https_proxy`,
/// `all_proxy`), then — on Windows — Internet Options. Both seams default to
/// the real thing and exist so a test can hand in a string instead.
///
/// A registry read that fails outright is logged and counts as "no proxy":
/// the update check must not die over its own diagnostics.
UpdateProxy? systemUpdateProxy({
  Map<String, String>? environment,
  InternetSettingsProxy Function() internetSettings = readInternetSettingsProxy,
  bool? windows,
}) {
  final UpdateProxy? fromEnvironment = proxyFromEnvironment(
    environment ?? Platform.environment,
  );
  if (fromEnvironment != null) return fromEnvironment;
  if (!(windows ?? Platform.isWindows)) return null;
  try {
    return proxyFromInternetSettings(internetSettings());
  } on Object catch (e) {
    debugPrint('Update: could not read the Windows proxy setting: $e');
    return null;
  }
}

/// The proxy every request of the updater goes through (#133) — Dart's own
/// and the `curl.exe` fallback alike — resolved once per launch. The
/// integration harness overrides it: with `null` so a test boot never
/// depends on the machine's setting, or with a loopback proxy a flow put
/// between the app and its release server.
final updateProxyProvider = Provider<UpdateProxy?>((_) => systemUpdateProxy());

/// The transport the updater falls back to when Dart cannot complete a TLS
/// handshake (#124): `curl.exe` on Windows, nothing anywhere else. The
/// integration harness overrides it — with `null` to keep a test boot from
/// ever spawning a process, or with a stand-in that trusts a loopback
/// certificate the way Schannel would trust the school's.
final nativeGetProvider = Provider<NativeGet?>(
  (ref) => Platform.isWindows
      ? curlNativeGet(
          curlPath: windowsCurlPath(),
          proxy: ref.watch(updateProxyProvider),
        )
      : null,
);

/// Looks up the release notes published for [version] — the running build's,
/// when About's **What's new** button has nothing kept locally (#130).
/// Returns `null` when no release carries that tag; throws
/// [UpdateCheckException] when the lookup itself did not complete.
typedef ReleaseNotesFetcher = Future<String?> Function(String version);

/// The by-tag lookup behind **What's new** (#130), on the same feed, proxy
/// and native fallback as the update check — or `null` when the feed is off
/// (`updateFeedUrlProvider` overridden with `null`), in which case there is
/// nowhere to ask and the button says so instead of reaching out.
final releaseNotesFetcherProvider = Provider<ReleaseNotesFetcher?>((ref) {
  final feedUrl = ref.watch(updateFeedUrlProvider);
  if (feedUrl == null) return null;
  final nativeGet = ref.watch(nativeGetProvider);
  final proxy = ref.watch(updateProxyProvider);
  return (version) => fetchReleaseNotesByTag(
    releaseByTagEndpoint(feedUrl, version),
    nativeGet: nativeGet,
    proxy: proxy,
    log: debugPrint,
  );
});

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
  final proxy = ref.watch(updateProxyProvider);
  return UpdateServices(
    localVersion: ref.watch(appVersionProvider),
    feed: feedUrl == null
        ? () async => null
        : () => fetchLatestRelease(
            feedUrl,
            nativeGet: nativeGet,
            proxy: proxy,
            log: debugPrint,
          ),
    download: (release, onProgress) => downloadToTemp(
      release.url,
      onProgress: onProgress,
      nativeGet: nativeGet,
      // A check that only got through natively is not going to fare better
      // on the installer, which sits behind the same inspection.
      preferNative: release.viaNativeTransport,
      proxy: proxy,
      log: debugPrint,
    ),
    verify: verifyAndCleanUp,
    run: (installer) => launch(installer.path, kSilentInstallArguments),
    stashNotes: (version, notes) =>
        stashReleaseNotes(version: version, notes: notes),
    autoCheck: feedUrl != null && ref.watch(updateAutoCheckProvider),
  );
});
