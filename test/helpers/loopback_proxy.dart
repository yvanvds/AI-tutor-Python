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

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_tutor_python/core/update_proxy.dart';

/// A CONNECT proxy on the loopback interface.
class LoopbackProxy {
  LoopbackProxy._(this._server, this.routes);

  final ServerSocket _server;

  /// `host:port` as the client asked for it → `host:port` actually dialled.
  final Map<String, String> routes;

  /// Every `CONNECT` target, as the client asked for it, in order. The proof
  /// that a request went through the proxy rather than straight out.
  final List<String> connects = <String>[];

  final List<Socket> _open = <Socket>[];

  int get port => _server.port;

  /// The proxy as the app should be configured with it.
  UpdateProxy get updateProxy =>
      UpdateProxy(Uri.parse('http://${_server.address.address}:$port'));

  static Future<LoopbackProxy> start({
    Map<String, String> routes = const <String, String>{},
  }) async {
    final ServerSocket server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final LoopbackProxy proxy = LoopbackProxy._(server, routes);
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
        final String requestLine = ascii
            .decode(bytes.sublist(0, end), allowInvalid: true)
            .split('\r\n')
            .first;
        final List<String> parts = requestLine.split(' ');
        if (parts.length != 3 || parts[0] != 'CONNECT') {
          client.write(
            'HTTP/1.1 405 Method Not Allowed\r\nConnection: close\r\n\r\n',
          );
          client.destroy();
          return;
        }
        final String target = parts[1];
        connects.add(target);
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
