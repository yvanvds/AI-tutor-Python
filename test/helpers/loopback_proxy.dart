// A loopback forward proxy and a loopback black hole (#133): together they
// reproduce a network where the app's own sockets go nowhere and only the
// proxy has a route out — which is what an explicit school proxy looks like
// from a laptop whose direct egress is firewalled. A loopback PAC server
// (#135) adds the other way a school states that proxy: as a script the
// machine is told to fetch and evaluate.
//
// [LoopbackProxy] speaks the one half of HTTP proxying the updater relies on:
// `CONNECT host:port`, the tunnel both Dart's `HttpClient` and `curl.exe`
// open through a proxy for an HTTPS URL — and every URL the updater
// touches is HTTPS. Plain absolute-form requests are refused, so a test that
// accidentally sends one fails loudly rather than passing on a path
// production never takes. It is written on a raw `ServerSocket` because
// Dart's `HttpServer` cannot parse an authority-form request target
// (`CONNECT 127.0.0.1:443` fails `Uri.parse` before any handler runs).
//
// A CONNECT to a target the proxy has a [LoopbackProxy.routes] entry for is
// dialled at the routed address instead. That is the stand-in for the route
// out: a flow points the app at a [BlackHole] — a listener that accepts every
// connection and never answers, so a direct request times out exactly as the
// production symptom reads — and routes that same address, at the proxy, to
// the real `FakeReleaseServer`. The app then only ever reaches its release
// through the proxy, and reaches it at all only if it honoured the setting.
//
// With [LoopbackProxy.requireLogin] (#140) the proxy also authenticates, as
// a school's AD-joined filter does: a CONNECT without a `Proxy-Authorization`
// header is refused with `407 Proxy Authentication Required`, which Dart's
// `HttpClient` cannot answer, and only one that carries the header is
// tunnelled.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_tutor_python/core/update_proxy.dart';

/// A CONNECT proxy on the loopback interface.
class LoopbackProxy {
  LoopbackProxy._(this._server, this.routes, this.requireLogin);

  final ServerSocket _server;

  /// `host:port` as the client asked for it → `host:port` actually dialled.
  final Map<String, String> routes;

  /// Whether a CONNECT has to carry a `Proxy-Authorization` header to be
  /// tunnelled (#140) — what an authenticating school proxy demands. One
  /// without it is answered `407 Proxy Authentication Required` with a
  /// `Negotiate` challenge and the connection is closed, which is exactly
  /// what Dart's `HttpClient` fails on; one with it — any value at all — is
  /// tunnelled. The header is looked for, not verified: what a test needs
  /// to see is that the client answered a challenge, not with what.
  ///
  /// `Negotiate` because that is the challenge an AD-joined filter sends
  /// and the one that makes `curl.exe`'s SSPI answer as the logged-in
  /// Windows user (`--proxy-anyauth --proxy-user :`): on a machine outside
  /// any domain SSPI still produces a token — NTLM's first message, for the
  /// local account — so the answer is visible here, while completing the
  /// exchange (and so verifying it) would need a domain. A `Basic`
  /// challenge would show nothing: curl rightly ignores Basic for an empty
  /// login, which is not a login at all.
  final bool requireLogin;

  /// Every `CONNECT` target, as the client asked for it, in order — the
  /// challenged ones included. The proof that a request went through the
  /// proxy rather than straight out.
  final List<String> connects = <String>[];

  /// How many CONNECTs were refused with a 407 for carrying no login.
  int challenges = 0;

  /// The `Proxy-Authorization` value of every CONNECT that carried one, in
  /// order: the proof a client answered the challenge.
  final List<String> logins = <String>[];

  final List<Socket> _open = <Socket>[];

  int get port => _server.port;

  /// The proxy as the app should be configured with it.
  UpdateProxy get updateProxy =>
      UpdateProxy(Uri.parse('http://${_server.address.address}:$port'));

  static Future<LoopbackProxy> start({
    Map<String, String> routes = const <String, String>{},
    bool requireLogin = false,
  }) async {
    final ServerSocket server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final LoopbackProxy proxy = LoopbackProxy._(server, routes, requireLogin);
    server.listen(proxy._serve);
    return proxy;
  }

  void _serve(Socket client) {
    _open.add(client);
    final BytesBuilder head = BytesBuilder(copy: false);
    Socket? upstream;
    late final StreamSubscription<Uint8List> subscription;
    subscription = client.listen(
      (Uint8List data) async {
        final Socket? tunnel = upstream;
        if (tunnel != null) {
          tunnel.add(data);
          return;
        }
        head.add(data);
        final Uint8List bytes = head.toBytes();
        final int end = _endOfHead(bytes);
        if (end < 0) return;
        // Nothing more is read until the tunnel is up, so a client that
        // pipelines its first TLS bytes behind the CONNECT keeps its order.
        subscription.pause();
        final List<String> lines = ascii
            .decode(bytes.sublist(0, end), allowInvalid: true)
            .split('\r\n');
        final List<String> parts = lines.first.split(' ');
        if (parts.length != 3 || parts[0] != 'CONNECT') {
          client.write(
            'HTTP/1.1 405 Method Not Allowed\r\nConnection: close\r\n\r\n',
          );
          client.destroy();
          return;
        }
        final String target = parts[1];
        connects.add(target);
        final String? login = _headerValue(lines, 'proxy-authorization');
        if (login != null) logins.add(login);
        if (requireLogin && login == null) {
          challenges++;
          client.write(
            'HTTP/1.1 407 Proxy Authentication Required\r\n'
            'Proxy-Authenticate: Negotiate\r\n'
            'Content-Length: 0\r\n'
            'Connection: close\r\n'
            '\r\n',
          );
          // Flushed before the close so the challenge is not lost with the
          // socket: the client has to read it to know why it was refused.
          try {
            await client.flush();
          } on Object {
            // The client went away first; nothing to deliver to.
          }
          client.destroy();
          return;
        }
        final String route = routes[target] ?? target;
        final int colon = route.lastIndexOf(':');
        final Socket dialled;
        try {
          dialled = await Socket.connect(
            route.substring(0, colon),
            int.parse(route.substring(colon + 1)),
          );
        } on Object {
          client.write('HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n');
          client.destroy();
          return;
        }
        _open.add(dialled);
        upstream = dialled;
        dialled.listen(
          (Uint8List chunk) {
            try {
              client.add(chunk);
            } on Object {
              // The client went away first; the tunnel is over either way.
            }
          },
          onDone: client.destroy,
          onError: (Object _) => client.destroy(),
        );
        client.write('HTTP/1.1 200 Connection established\r\n\r\n');
        final Uint8List excess = bytes.sublist(end + 4);
        if (excess.isNotEmpty) dialled.add(excess);
        subscription.resume();
      },
      onDone: () => upstream?.destroy(),
      onError: (Object _) => upstream?.destroy(),
    );
  }

  Future<void> close() async {
    for (final Socket socket in _open) {
      socket.destroy();
    }
    await _server.close();
  }
}

/// The value of the header [name] (lower-case) in a request head's [lines],
/// or `null` when the head does not carry it.
String? _headerValue(List<String> lines, String name) {
  for (final String line in lines.skip(1)) {
    final int colon = line.indexOf(':');
    if (colon < 0) continue;
    if (line.substring(0, colon).trim().toLowerCase() == name) {
      return line.substring(colon + 1).trim();
    }
  }
  return null;
}

/// The index of the `\r\n\r\n` that ends a request head, or -1.
int _endOfHead(Uint8List bytes) {
  for (int i = 0; i + 3 < bytes.length; i++) {
    if (bytes[i] == 13 &&
        bytes[i + 1] == 10 &&
        bytes[i + 2] == 13 &&
        bytes[i + 3] == 10) {
      return i;
    }
  }
  return -1;
}

/// A loopback listener that accepts every connection and never sends a byte:
/// what a firewalled direct route looks like to a client, and what makes the
/// update check report "timed out" rather than "refused".
class BlackHole {
  BlackHole._(this._server);

  final ServerSocket _server;
  final List<Socket> _held = <Socket>[];

  /// How many connections were swallowed. A flow proves the app never went
  /// direct with this.
  int get connections => _held.length;

  /// `host:port`, for a URL or a proxy route.
  String get authority => '${_server.address.address}:${_server.port}';

  static Future<BlackHole> start() async {
    final ServerSocket server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final BlackHole hole = BlackHole._(server);
    server.listen((Socket socket) {
      hole._held.add(socket);
      // Drain, so a client that writes is not blocked by a full buffer and
      // waits on the answer that never comes.
      socket.listen((_) {}, onError: (Object _) {}, cancelOnError: true);
    });
    return hole;
  }

  Future<void> close() async {
    for (final Socket socket in _held) {
      socket.destroy();
    }
    await _server.close();
  }
}

/// A loopback HTTP server serving one proxy auto-configuration script
/// (#135): what a school publishes at its `AutoConfigURL`, and what WinHTTP
/// fetches and evaluates when the app asks it which proxy a URL takes. A
/// flow points the app's auto-configuration at [url] and the script at a
/// [LoopbackProxy]; the app then reaches its release only if it resolved
/// the script, which is the whole difference #135 makes.
class LoopbackPacServer {
  LoopbackPacServer._(this._server, this.script);

  final HttpServer _server;

  /// The JavaScript served, verbatim.
  final String script;

  /// How many times the script was fetched: the proof WinHTTP came for it.
  int fetches = 0;

  /// Where Internet Options would point: `http://127.0.0.1:<port>/proxy.pac`.
  Uri get url =>
      Uri.parse('http://${_server.address.address}:${_server.port}/proxy.pac');

  static Future<LoopbackPacServer> start({required String script}) async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final LoopbackPacServer pac = LoopbackPacServer._(server, script);
    server.listen((HttpRequest req) async {
      pac.fetches++;
      req.response.headers.contentType = ContentType(
        'application',
        'x-ns-proxy-autoconfig',
      );
      req.response.write(script);
      await req.response.close();
    });
    return pac;
  }

  Future<void> close() => _server.close(force: true);
}

/// A PAC script that sends every URL through [proxy] (`host:port`), except
/// the hosts in [direct], which it answers `DIRECT` for — the two answers a
/// school's script gives, in the shape WinHTTP hands back for each.
String pacScript({required String proxy, List<String> direct = const []}) {
  final String directHosts = direct
      .map((String host) => 'host == "$host"')
      .join(' || ');
  return '''
function FindProxyForURL(url, host) {
  ${directHosts.isEmpty ? '' : 'if ($directHosts) return "DIRECT";'}
  return "PROXY $proxy";
}
''';
}
