/// The production wiring behind the update check (#47): where a published
/// release is read from, how its installer is fetched and verified, and how
/// it is launched.
///
/// Held apart from `update_controller.dart` on purpose — this is the only
/// file in the update layer that touches the real network, the real
/// filesystem, a real process, the registry and WinHTTP, so everything above
/// it stays drivable from a test with no network and no `%TEMP%` write.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

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
        GetLastError,
        GlobalFree,
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

/// How `curl.exe` is told to answer a proxy's login challenge with the
/// logged-in Windows user (#140): `--proxy-anyauth` lets it pick whatever
/// the proxy offers (Negotiate over NTLM over the rest), and `--proxy-user :`
/// — a bare colon — is the documented spelling of "take the user name and
/// password from the environment", which on an SSPI build is the current
/// Windows session. Passed only beside a `--proxy` that names no login of
/// its own.
const List<String> kCurlProxyWindowsLogin = <String>[
  '--proxy-anyauth',
  '--proxy-user',
  ':',
];

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
///   handed, bypass list included. [proxy] is looked up per request, not
///   taken at construction: the setting is resolved once per launch and,
///   when it comes from a PAC script (#135), not before a request needs it.
/// - `--proxy-anyauth --proxy-user :` beside it (#140), unless the proxy
///   URL carries a login of its own: a proxy that authenticates answers the
///   `CONNECT` with a 407, and this is curl's documented way of answering a
///   Negotiate / NTLM challenge through SSPI as the logged-in Windows user —
///   the empty login is what tells it to. No credential is stored, passed
///   or logged. A proxy that only offers Basic is not answered at all —
///   curl ignores Basic for an empty login, rightly — and the request fails
///   exactly as it failed before. With a login in the URL
///   (`https_proxy=http://user:pass@…`) curl is left to send that, as
///   Dart's client does.
///
/// Nothing here weakens verification: the fallback trusts what the operating
/// system trusts, and `verifyAndCleanUp` still hashes what arrives.
NativeGet? curlNativeGet({
  required String curlPath,
  ProcessRunner run = _runProcess,
  FutureOr<UpdateProxy?> Function()? proxy,
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
      final UpdateProxy? through = await proxy?.call();
      final String? via = through?.curlProxyFor(url);
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
        if (via != null) ...<String>[
          '--proxy',
          via,
          if (!through!.hasLogin) ...kCurlProxyWindowsLogin,
        ],
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

// --- PAC / WPAD through WinHTTP (#135) -------------------------------------
//
// The `win32` package binds WinHTTP's COM `WinHttpRequest` but not its C
// API, so the five entry points the auto-proxy read needs are looked up here
// directly. Only `WinHttpGetIEProxyConfigForCurrentUser` and
// `WinHttpGetProxyForUrl` do any work; the rest is session housekeeping.

const int _winHttpAccessTypeNoProxy = 1;
const int _winHttpAutoProxyAutoDetect = 0x00000001;
const int _winHttpAutoProxyConfigUrl = 0x00000002;
const int _winHttpAutoDetectTypeDhcp = 0x00000001;
const int _winHttpAutoDetectTypeDnsA = 0x00000002;
const int _errorWinHttpLoginFailure = 12015;

/// WinHTTP's own names for the failures a PAC/WPAD lookup most often ends
/// in; anything else is reported by number.
const Map<int, String> _winHttpErrorNames = <int, String>{
  12002: 'ERROR_WINHTTP_TIMEOUT',
  12007: 'ERROR_WINHTTP_NAME_NOT_RESOLVED',
  12015: 'ERROR_WINHTTP_LOGIN_FAILURE',
  12029: 'ERROR_WINHTTP_CANNOT_CONNECT',
  12166: 'ERROR_WINHTTP_BAD_AUTO_PROXY_SCRIPT',
  12167: 'ERROR_WINHTTP_UNABLE_TO_DOWNLOAD_SCRIPT',
  12180: 'ERROR_WINHTTP_AUTODETECTION_FAILED',
};

/// `WINHTTP_CURRENT_USER_IE_PROXY_CONFIG`.
final class _IeProxyConfig extends Struct {
  @Int32()
  external int fAutoDetect;
  external Pointer<Utf16> lpszAutoConfigUrl;
  external Pointer<Utf16> lpszProxy;
  external Pointer<Utf16> lpszProxyBypass;
}

/// `WINHTTP_AUTOPROXY_OPTIONS`.
final class _AutoProxyOptions extends Struct {
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int dwAutoDetectFlags;
  external Pointer<Utf16> lpszAutoConfigUrl;
  external Pointer<Void> lpvReserved;
  @Uint32()
  external int dwReserved;
  @Int32()
  external int fAutoLogonIfChallenged;
}

/// `WINHTTP_PROXY_INFO`.
final class _ProxyInfo extends Struct {
  @Uint32()
  external int dwAccessType;
  external Pointer<Utf16> lpszProxy;
  external Pointer<Utf16> lpszProxyBypass;
}

typedef _WinHttpOpenC = Pointer<Void> Function(
  Pointer<Utf16> agent,
  Uint32 accessType,
  Pointer<Utf16> proxy,
  Pointer<Utf16> proxyBypass,
  Uint32 flags,
);
typedef _WinHttpOpenDart = Pointer<Void> Function(
  Pointer<Utf16> agent,
  int accessType,
  Pointer<Utf16> proxy,
  Pointer<Utf16> proxyBypass,
  int flags,
);
typedef _WinHttpCloseHandleC = Int32 Function(Pointer<Void> handle);
typedef _WinHttpCloseHandleDart = int Function(Pointer<Void> handle);
typedef _WinHttpSetTimeoutsC = Int32 Function(
  Pointer<Void> handle,
  Int32 resolve,
  Int32 connect,
  Int32 send,
  Int32 receive,
);
typedef _WinHttpSetTimeoutsDart = int Function(
  Pointer<Void> handle,
  int resolve,
  int connect,
  int send,
  int receive,
);
typedef _WinHttpGetIEProxyConfigC = Int32 Function(
  Pointer<_IeProxyConfig> config,
);
typedef _WinHttpGetIEProxyConfigDart = int Function(
  Pointer<_IeProxyConfig> config,
);
typedef _WinHttpGetProxyForUrlC = Int32 Function(
  Pointer<Void> session,
  Pointer<Utf16> url,
  Pointer<_AutoProxyOptions> options,
  Pointer<_ProxyInfo> info,
);
typedef _WinHttpGetProxyForUrlDart = int Function(
  Pointer<Void> session,
  Pointer<Utf16> url,
  Pointer<_AutoProxyOptions> options,
  Pointer<_ProxyInfo> info,
);

/// `winhttp.dll`, opened on first use — per isolate, since the lookup runs
/// off the main one — and only ever on Windows.
class _WinHttp {
  _WinHttp() : _library = DynamicLibrary.open('winhttp.dll');

  final DynamicLibrary _library;

  late final _WinHttpOpenDart open = _library
      .lookupFunction<_WinHttpOpenC, _WinHttpOpenDart>('WinHttpOpen');
  late final _WinHttpCloseHandleDart closeHandle = _library
      .lookupFunction<_WinHttpCloseHandleC, _WinHttpCloseHandleDart>(
        'WinHttpCloseHandle',
      );
  late final _WinHttpSetTimeoutsDart setTimeouts = _library
      .lookupFunction<_WinHttpSetTimeoutsC, _WinHttpSetTimeoutsDart>(
        'WinHttpSetTimeouts',
      );
  late final _WinHttpGetIEProxyConfigDart getIEProxyConfigForCurrentUser =
      _library.lookupFunction<
        _WinHttpGetIEProxyConfigC,
        _WinHttpGetIEProxyConfigDart
      >('WinHttpGetIEProxyConfigForCurrentUser');
  late final _WinHttpGetProxyForUrlDart getProxyForUrl = _library
      .lookupFunction<_WinHttpGetProxyForUrlC, _WinHttpGetProxyForUrlDart>(
        'WinHttpGetProxyForUrl',
      );
}

/// A string WinHTTP allocated for the caller, read and given back.
String? _takeWinHttpString(Pointer<Utf16> value) {
  if (value == nullptr) return null;
  try {
    return value.toDartString();
  } finally {
    GlobalFree(value.cast());
  }
}

String _winHttpError(String call, int code) {
  final String? name = _winHttpErrorNames[code];
  return '$call failed: error $code${name == null ? '' : ' ($name)'}';
}

/// The automatic-configuration half of Internet Options (#135): whether
/// "Automatically detect settings" is ticked and which script URL is set, as
/// `WinHttpGetIEProxyConfigForCurrentUser` reports them. Windows only.
///
/// The explicit half — `lpszProxy` / `lpszProxyBypass`, which the same call
/// also returns — is deliberately still read from the registry by
/// [readInternetSettingsProxy], where the per-machine policy is honoured
/// (#133); this reads only what the registry does not keep in the clear
/// (WPAD sits in a binary blob under `Connections`).
AutoProxyConfig readAutoProxyConfig() => using((Arena arena) {
  final _WinHttp api = _WinHttp();
  final Pointer<_IeProxyConfig> config = arena<_IeProxyConfig>();
  if (api.getIEProxyConfigForCurrentUser(config) == 0) {
    throw StateError(
      _winHttpError('WinHttpGetIEProxyConfigForCurrentUser', GetLastError()),
    );
  }
  _takeWinHttpString(config.ref.lpszProxy);
  _takeWinHttpString(config.ref.lpszProxyBypass);
  return (
    autoDetect: config.ref.fAutoDetect != 0,
    configUrl: _takeWinHttpString(config.ref.lpszAutoConfigUrl),
  );
});

/// How long the PAC/WPAD lookup may take before the check goes ahead without
/// it (#135). A script on a school LAN answers well inside a second; WPAD
/// on a network that has none — a student's home, with "Automatically
/// detect settings" at its Windows default of on — fails in a few, and
/// WinHTTP's auto-proxy service remembers that between launches. The cap is
/// what keeps a script server that accepts and never answers from holding
/// the check for WinHTTP's own thirty-second deadline.
const Duration kAutoProxyTimeout = Duration(seconds: 5);

/// The WinHTTP side of the PAC/WPAD lookup, in whatever isolate it is
/// called on: one session, one `WinHttpGetProxyForUrl`, and the strings it
/// hands back. Throws a [StateError] naming WinHTTP's error when the lookup
/// does not complete.
AutoProxyResult _winHttpProxyForUrl(
  String url, {
  required bool autoDetect,
  required String? configUrl,
}) => using((Arena arena) {
  final _WinHttp api = _WinHttp();
  final Pointer<Void> session = api.open(
    'AI-tutor-Python'.toNativeUtf16(allocator: arena),
    _winHttpAccessTypeNoProxy,
    nullptr,
    nullptr,
    0,
  );
  if (session == nullptr) {
    throw StateError(_winHttpError('WinHttpOpen', GetLastError()));
  }
  try {
    // The session's own deadlines, for the in-process script download;
    // the out-of-process auto-proxy service keeps its own, which is why
    // the caller's [kAutoProxyTimeout] is the one that is guaranteed.
    final int ms = kAutoProxyTimeout.inMilliseconds;
    api.setTimeouts(session, ms, ms, ms, ms);
    final Pointer<_AutoProxyOptions> options = arena<_AutoProxyOptions>();
    options.ref.dwFlags =
        (autoDetect ? _winHttpAutoProxyAutoDetect : 0) |
        (configUrl == null ? 0 : _winHttpAutoProxyConfigUrl);
    options.ref.dwAutoDetectFlags = autoDetect
        ? _winHttpAutoDetectTypeDhcp | _winHttpAutoDetectTypeDnsA
        : 0;
    options.ref.lpszAutoConfigUrl = configUrl == null
        ? nullptr
        : configUrl.toNativeUtf16(allocator: arena);
    // As the documentation recommends: without automatic logon first, and
    // again with it only when the script server asked for credentials.
    options.ref.fAutoLogonIfChallenged = 0;
    final Pointer<Utf16> target = url.toNativeUtf16(allocator: arena);
    final Pointer<_ProxyInfo> info = arena<_ProxyInfo>();
    if (api.getProxyForUrl(session, target, options, info) == 0) {
      int error = GetLastError();
      if (error == _errorWinHttpLoginFailure) {
        options.ref.fAutoLogonIfChallenged = 1;
        if (api.getProxyForUrl(session, target, options, info) == 0) {
          error = GetLastError();
          throw StateError(_winHttpError('WinHttpGetProxyForUrl', error));
        }
      } else {
        throw StateError(_winHttpError('WinHttpGetProxyForUrl', error));
      }
    }
    final String? proxy = _takeWinHttpString(info.ref.lpszProxy);
    final String? bypass = _takeWinHttpString(info.ref.lpszProxyBypass);
    // `DIRECT` comes back as `WINHTTP_ACCESS_TYPE_NO_PROXY` and no string.
    return (
      proxy: info.ref.dwAccessType == _winHttpAccessTypeNoProxy ? null : proxy,
      bypass: bypass,
    );
  } finally {
    api.closeHandle(session);
  }
});

/// Asks WinHTTP which proxy [config]'s script or WPAD names for [target]:
/// the seam behind [systemUpdateProxy]'s third source (#135).
typedef AutoProxyResolver = Future<AutoProxyResult> Function(
  Uri target,
  AutoProxyConfig config,
);

/// The production [AutoProxyResolver]: `WinHttpGetProxyForUrl` with
/// `WINHTTP_AUTOPROXY_AUTO_DETECT` and/or `WINHTTP_AUTOPROXY_CONFIG_URL`,
/// which fetches and evaluates the script. Windows only.
///
/// Off the main isolate, because the call blocks for as long as the
/// download and the WPAD probes take, and the UI must not. The future is
/// not bounded here — [systemUpdateProxy] applies [kAutoProxyTimeout] to
/// whatever resolver it was given, so the cap is pinned with a fake — and
/// completes with an error, not a value, when WinHTTP could not say.
Future<AutoProxyResult> resolveAutoProxy(Uri target, AutoProxyConfig config) {
  final String url = target.toString();
  final bool autoDetect = config.autoDetect;
  final String? configUrl = config.configUrl?.trim();
  return Isolate.run(
    () => _winHttpProxyForUrl(
      url,
      autoDetect: autoDetect,
      configUrl: configUrl == null || configUrl.isEmpty ? null : configUrl,
    ),
    debugName: 'update-auto-proxy',
  );
}

/// The proxy this machine states for the updater's requests to [target]
/// (#133, #135), or `null` for a direct connection: the environment first
/// (`https_proxy`, `all_proxy`), then — on Windows — Internet Options'
/// explicit server, then the one its PAC script or WPAD yields for
/// [target]. Each seam defaults to the real thing and exists so a test can
/// hand in a string instead; the order is what `update_bootstrap_test.dart`
/// pins.
///
/// Nothing here may fail the check over its own diagnostics: a registry or
/// WinHTTP read that throws is logged and counts as "no proxy" for that
/// source, and a script lookup that has not answered within
/// [autoProxyTimeout] is abandoned the same way — the check goes ahead
/// directly rather than wait on it.
Future<UpdateProxy?> systemUpdateProxy(
  Uri target, {
  Map<String, String>? environment,
  InternetSettingsProxy Function() internetSettings = readInternetSettingsProxy,
  AutoProxyConfig Function() autoProxyConfig = readAutoProxyConfig,
  AutoProxyResolver autoProxy = resolveAutoProxy,
  Duration autoProxyTimeout = kAutoProxyTimeout,
  bool? windows,
}) async {
  final UpdateProxy? fromEnvironment = proxyFromEnvironment(
    environment ?? Platform.environment,
  );
  if (fromEnvironment != null) return fromEnvironment;
  if (!(windows ?? Platform.isWindows)) return null;
  try {
    final UpdateProxy? explicit = proxyFromInternetSettings(internetSettings());
    if (explicit != null) return explicit;
  } on Object catch (e) {
    debugPrint('Update: could not read the Windows proxy setting: $e');
  }
  final AutoProxyConfig config;
  try {
    config = autoProxyConfig();
  } on Object catch (e) {
    debugPrint('Update: could not read the Windows auto-proxy setting: $e');
    return null;
  }
  if (!config.isConfigured) return null;
  try {
    final AutoProxyResult result = await autoProxy(
      target,
      config,
    ).timeout(autoProxyTimeout);
    return proxyFromAutoProxy(result);
  } on TimeoutException {
    debugPrint(
      'Update: ${config.describe} did not name a proxy within '
      '${autoProxyTimeout.inSeconds}s; connecting directly.',
    );
    return null;
  } on Object catch (e) {
    debugPrint(
      'Update: ${config.describe} could not name a proxy for $target ($e); '
      'connecting directly.',
    );
    return null;
  }
}

/// The proxy setting as the transports receive it: a look-up that resolves
/// it at most once per launch, and not before a request needs it.
///
/// A look-up rather than the value because a PAC script (#135) takes a
/// moment to answer, and rather than an eager future because building the
/// update services must not touch WinHTTP — a debug launch never checks,
/// and a test that only reads the wiring must not probe the machine.
typedef UpdateProxyLookup = Future<UpdateProxy?> Function();

/// A look-up that always answers [proxy]: what the integration harness and
/// the tests hand in for a setting they already know.
UpdateProxyLookup fixedUpdateProxy(UpdateProxy? proxy) =>
    () => Future<UpdateProxy?>.value(proxy);

/// A look-up that runs [resolve] on its first call and answers every later
/// one — the checksum's, the installer's — with that same future.
UpdateProxyLookup updateProxyResolvedOnce(
  Future<UpdateProxy?> Function() resolve,
) {
  Future<UpdateProxy?>? pending;
  return () => pending ??= resolve();
}

/// The proxy every request of the updater goes through (#133) — Dart's own
/// and the `curl.exe` fallback alike — resolved for the feed's endpoint by
/// the first request that asks and shared by every later one. With the feed
/// off there is nothing to reach and nothing is ever asked. The integration
/// harness overrides it: with `null` so a test boot never depends on the
/// machine's setting, or with a loopback proxy a flow put between the app
/// and its release server.
final updateProxyProvider = Provider<UpdateProxyLookup>((ref) {
  final Uri? feedUrl = ref.watch(updateFeedUrlProvider);
  if (feedUrl == null) return fixedUpdateProxy(null);
  return updateProxyResolvedOnce(() => systemUpdateProxy(feedUrl));
});

/// The transport the updater falls back to when Dart cannot complete a TLS
/// handshake (#124) or answer a proxy's login challenge (#140): `curl.exe`
/// on Windows, nothing anywhere else. The integration harness overrides it
/// — with `null` to keep a test boot from ever spawning a process, or with a
/// stand-in that trusts a loopback certificate the way Schannel would trust
/// the school's, and answers a loopback proxy's challenge the way SSPI would
/// answer the school's.
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
  final UpdateProxyLookup proxy = ref.watch(updateProxyProvider);
  return (version) async => fetchReleaseNotesByTag(
    releaseByTagEndpoint(feedUrl, version),
    nativeGet: nativeGet,
    proxy: await proxy(),
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
  final UpdateProxyLookup proxy = ref.watch(updateProxyProvider);
  return UpdateServices(
    localVersion: ref.watch(appVersionProvider),
    feed: feedUrl == null
        ? () async => null
        : () async => fetchLatestRelease(
            feedUrl,
            nativeGet: nativeGet,
            proxy: await proxy(),
            log: debugPrint,
          ),
    download: (release, onProgress) async => downloadToTemp(
      release.url,
      onProgress: onProgress,
      nativeGet: nativeGet,
      // A check that only got through natively is not going to fare better
      // on the installer, which sits behind the same inspection.
      preferNative: release.viaNativeTransport,
      proxy: await proxy(),
      log: debugPrint,
    ),
    verify: verifyAndCleanUp,
    run: (installer) => launch(installer.path, kSilentInstallArguments),
    stashNotes: (version, notes) =>
        stashReleaseNotes(version: version, notes: notes),
    autoCheck: feedUrl != null && ref.watch(updateAutoCheckProvider),
  );
});
