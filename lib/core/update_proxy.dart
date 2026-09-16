/// The forward proxy the updater's requests go through (#133), and how it
/// is read out of the three places a machine states one.
///
/// Dart's `HttpClient` knows nothing of the proxy Windows is configured with:
/// it dials `api.github.com` directly, and on a school network where only
/// the proxy has a route out, that direct connection is simply dropped. The
/// check then reports "request … timed out after 10s" — not the handshake
/// error #124 dealt with — and the `curl.exe` fallback, told nothing about
/// the proxy either, would fail the same way. So both transports are handed
/// the same [UpdateProxy], resolved once per launch by
/// `update_bootstrap.dart`: `HttpClient.findProxy` for Dart, `--proxy` for
/// curl.
///
/// Three sources, in this order, the way Python's `urllib` and most tools
/// resolve it:
///
/// - the environment (`https_proxy` / `all_proxy`, with `no_proxy`), which is
///   how a developer or an admin script states one explicitly;
/// - on Windows, Internet Options — `ProxyEnable`, `ProxyServer` and
///   `ProxyOverride` under `HKCU\…\Internet Settings` — which is what Edge,
///   Chrome, .NET and `WinHttpGetIEProxyConfigForCurrentUser` honour, and
///   what a school's group policy writes;
/// - on Windows, when Internet Options name no explicit server, the proxy a
///   PAC script (`AutoConfigURL`) or WPAD auto-detection yields for the
///   endpoint (#135) — the way a managed filter most often states its proxy.
///   That needs WinHTTP to fetch and evaluate the script, which
///   `update_bootstrap.dart` does through `WinHttpGetProxyForUrl`; what comes
///   back (`lpszProxy` / `lpszProxyBypass`) is the same shape Internet
///   Options keep, and [proxyFromAutoProxy] parses it the same way.
///
/// This file parses and decides; it reads nothing. `update_bootstrap.dart`
/// does the reading, so everything here is drivable from a test with a
/// string.
library;

/// A proxy to go through, and the hosts to skip it for.
class UpdateProxy {
  const UpdateProxy(this.url, {this.bypass = const <String>[]});

  /// `http://[user:pass@]host:port`. Always plain HTTP to the proxy itself:
  /// HTTPS targets are tunnelled through it with `CONNECT`, which is what
  /// both Dart's `HttpClient` and `curl.exe` do with such a URL.
  final Uri url;

  /// Hosts that are reached directly regardless — Windows' `ProxyOverride`
  /// entries or the environment's `no_proxy` list, as written: `<local>`,
  /// `*.school.be`, `10.*`, `example.com`, `.example.com`. See [bypasses].
  final List<String> bypass;

  /// Whether [target]'s host is on the [bypass] list.
  ///
  /// `<local>` is a host without a dot (WinINET's meaning); `*` matches all;
  /// a pattern with wildcards is a glob over the host; a plain entry matches
  /// the host itself and, as `no_proxy` has it, any subdomain of it. A
  /// scheme, a port or a leading dot on the entry is ignored.
  bool bypasses(Uri target) {
    final String host = target.host.toLowerCase();
    for (final String raw in bypass) {
      String pattern = raw.trim().toLowerCase();
      if (pattern.isEmpty) continue;
      if (pattern == '*') return true;
      if (pattern == '<local>') {
        if (!host.contains('.')) return true;
        continue;
      }
      final int scheme = pattern.indexOf('://');
      if (scheme >= 0) pattern = pattern.substring(scheme + 3);
      pattern = _withoutPort(pattern);
      if (pattern.startsWith('.')) pattern = pattern.substring(1);
      if (pattern.isEmpty) continue;
      if (pattern.contains('*') || pattern.contains('?')) {
        if (_glob(pattern).hasMatch(host)) return true;
        continue;
      }
      if (host == pattern || host.endsWith('.$pattern')) return true;
    }
    return false;
  }

  /// What `HttpClient.findProxy` wants for [target]: `PROXY host:port`, with
  /// the credentials in front when [url] carries any, or `DIRECT` for a
  /// bypassed host.
  String findProxy(Uri target) {
    if (bypasses(target)) return 'DIRECT';
    final String credentials = url.userInfo.isEmpty ? '' : '${url.userInfo}@';
    return 'PROXY $credentials${url.host}:${url.port}';
  }

  /// What `curl.exe --proxy` wants for [target], or `null` for a bypassed
  /// host — in which case the flag is left off.
  String? curlProxyFor(Uri target) => bypasses(target) ? null : url.toString();

  /// [url] without its credentials: what a log line or an error message may
  /// say about the proxy. Only the two transports are handed the password.
  String get redactedUrl => url.replace(userInfo: '').toString();

  @override
  String toString() =>
      'UpdateProxy($redactedUrl${bypass.isEmpty ? '' : ', bypass: $bypass'})';
}

/// `ProxyServer`, `ProxyEnable` and `ProxyOverride` as they sit under
/// `HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings`, read
/// by `update_bootstrap.dart` and parsed by [proxyFromInternetSettings].
typedef InternetSettingsProxy = ({
  bool enabled,
  String? server,
  String? override,
});

/// What Internet Options say about *automatic* configuration (#135), as
/// `WinHttpGetIEProxyConfigForCurrentUser` reports it: whether "Automatically
/// detect settings" (WPAD) is ticked, and the "Use automatic configuration
/// script" URL when one is set. Read by `update_bootstrap.dart`; whether it
/// is worth asking WinHTTP about is [AutoProxyConfigX.isConfigured].
typedef AutoProxyConfig = ({bool autoDetect, String? configUrl});

/// What WinHTTP hands back once it has evaluated the script for a URL
/// (`WINHTTP_PROXY_INFO`): `lpszProxy` — one or more
/// `[protocol=]host[:port]` entries, `;`- or space-separated, exactly the
/// `ProxyServer` shape — and `lpszProxyBypass` in the `ProxyOverride` shape.
/// A `null` [AutoProxyResult.proxy] is the script's `DIRECT`.
typedef AutoProxyResult = ({String? proxy, String? bypass});

extension AutoProxyConfigX on AutoProxyConfig {
  /// Whether there is anything to evaluate at all. A machine with neither
  /// box ticked is not asked, which spares it a WinHTTP session per launch.
  bool get isConfigured {
    final String? url = configUrl;
    return autoDetect || (url != null && url.trim().isNotEmpty);
  }

  /// For a log line: where the answer would have come from.
  String get describe {
    final String? url = configUrl;
    final bool hasUrl = url != null && url.trim().isNotEmpty;
    if (autoDetect && hasUrl) return 'WPAD and the script at ${url.trim()}';
    if (hasUrl) return 'the script at ${url.trim()}';
    return 'WPAD';
  }
}

/// The proxy the environment states, or `null` when it states none.
///
/// `https_proxy` first — every request the updater makes is HTTPS — then
/// `all_proxy`, each in either case; `no_proxy` becomes the bypass list. A
/// value that is not an HTTP proxy (a `socks5://` URL, say) counts as none:
/// neither transport could use it. Without a port the conventional 1080 is
/// assumed, as `curl` and Dart's own `findProxyFromEnvironment` do.
UpdateProxy? proxyFromEnvironment(Map<String, String> environment) {
  String? first(List<String> names) {
    for (final String name in names) {
      final String? value = environment[name];
      if (value != null && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  final String? raw = first(const <String>[
    'https_proxy',
    'HTTPS_PROXY',
    'all_proxy',
    'ALL_PROXY',
  ]);
  if (raw == null) return null;
  final Uri? url = _proxyUrl(raw, defaultPort: 1080);
  if (url == null) return null;
  final String? noProxy = first(const <String>['no_proxy', 'NO_PROXY']);
  return UpdateProxy(
    url,
    bypass: noProxy == null ? const <String>[] : noProxy.split(','),
  );
}

/// The proxy Internet Options states for HTTPS, or `null` when the setting
/// is off, empty, or names no proxy for HTTPS.
///
/// `ProxyServer` is either one `host:port` for every protocol, or a
/// `;`-separated `protocol=host:port` list when "use the same proxy server
/// for all protocols" is unticked — in which case only the `https=` entry
/// applies, exactly as WinINET applies it. Without a port, WinINET's default
/// of 80 is assumed. `ProxyOverride` becomes the bypass list.
UpdateProxy? proxyFromInternetSettings(InternetSettingsProxy settings) {
  if (!settings.enabled) return null;
  final String? server = settings.server;
  if (server == null || server.trim().isEmpty) return null;
  final Uri? url = _httpsProxyIn(server);
  if (url == null) return null;
  final String? override = settings.override;
  return UpdateProxy(
    url,
    bypass: override == null ? const <String>[] : override.split(';'),
  );
}

/// The proxy a PAC script or WPAD yielded for the endpoint (#135), or `null`
/// when the script said `DIRECT` or named no proxy usable for HTTPS.
///
/// `lpszProxy` is parsed exactly as `ProxyServer` is: a per-protocol list
/// applies only through its `https=` entry, and a plain list — a script's
/// `PROXY a:8080; PROXY b:8080` comes back as `a:8080;b:8080` — through its
/// first, which is the one WinINET would try first too. Neither transport
/// fails over to a second proxy, so the rest is not kept. `lpszProxyBypass`
/// becomes the bypass list, as `ProxyOverride` does.
UpdateProxy? proxyFromAutoProxy(AutoProxyResult result) {
  final String? proxy = result.proxy;
  if (proxy == null || proxy.trim().isEmpty) return null;
  final Uri? url = _httpsProxyIn(proxy);
  if (url == null) return null;
  final String? bypass = result.bypass;
  return UpdateProxy(
    url,
    bypass: bypass == null ? const <String>[] : bypass.split(_listSeparator),
  );
}

/// What separates the entries of a `ProxyServer`-shaped list: `;` in the
/// registry, `;` or whitespace from WinHTTP.
final RegExp _listSeparator = RegExp(r'[;\s]+');

/// The proxy for HTTPS in a `ProxyServer`-shaped list, or `null`.
///
/// Entries are `[protocol=]address`; a `protocol=` entry counts only when it
/// is `https=`, a plain entry always does, and the first that counts wins.
/// `DIRECT`, which a PAC result may carry, is skipped.
Uri? _httpsProxyIn(String proxyServer) {
  for (final String entry in proxyServer.split(_listSeparator)) {
    if (entry.isEmpty || entry.toLowerCase() == 'direct') continue;
    final int eq = entry.indexOf('=');
    if (eq < 0) return _proxyUrl(entry, defaultPort: 80);
    if (entry.substring(0, eq).trim().toLowerCase() == 'https') {
      return _proxyUrl(entry.substring(eq + 1), defaultPort: 80);
    }
  }
  return null;
}

/// `[scheme://][user:pass@]host[:port][/]` as an `http://` URL with a port,
/// or `null` for anything that is not an HTTP proxy address.
///
/// An `https://` prefix is read as the same proxy over plain HTTP: neither
/// Dart's `HttpClient` nor the fallback is asked to speak TLS *to* a proxy,
/// and WinINET's `https=` entry names the proxy for HTTPS traffic, not a
/// proxy reached over HTTPS.
Uri? _proxyUrl(String raw, {required int defaultPort}) {
  String address = raw.trim();
  final int scheme = address.indexOf('://');
  if (scheme >= 0) {
    final String protocol = address.substring(0, scheme).toLowerCase();
    if (protocol != 'http' && protocol != 'https') return null;
    address = address.substring(scheme + 3);
  }
  while (address.endsWith('/')) {
    address = address.substring(0, address.length - 1);
  }
  if (address.isEmpty) return null;
  final Uri? url = Uri.tryParse('http://$address');
  if (url == null || url.host.isEmpty || url.path.isNotEmpty) return null;
  return url.hasPort ? url : url.replace(port: defaultPort);
}

/// `host:port` → `host`; leaves an IPv6 literal and a bare host alone.
String _withoutPort(String pattern) {
  final int colon = pattern.lastIndexOf(':');
  if (colon < 0 || pattern.contains(']')) return pattern;
  if (int.tryParse(pattern.substring(colon + 1)) == null) return pattern;
  return pattern.substring(0, colon);
}

RegExp _glob(String pattern) => RegExp(
  '^${RegExp.escape(pattern).replaceAll(r'\*', '.*').replaceAll(r'\?', '.')}\$',
);
