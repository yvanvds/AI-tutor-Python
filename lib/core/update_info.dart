import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/core/update_proxy.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:pub_semver/pub_semver.dart'; // add to pubspec
import 'package:path/path.dart' as p;

/// The update check failed: the network was unreachable, the server
/// answered with something other than a release, or a request ran out of
/// time.
///
/// This is deliberately distinct from a `null` result (#46). `null` means
/// "nothing is published" and is a normal, silent outcome; a thrown
/// [UpdateCheckException] means the check itself did not complete and must
/// reach a log. Before #46 both collapsed into `null`, which is how the BOM
/// bug (#45) stayed invisible for the whole life of the feature.
class UpdateCheckException implements Exception {
  UpdateCheckException(this.message);
  final String message;

  @override
  String toString() => 'UpdateCheckException: $message';
}

/// How long a small update request — the release lookup, the checksum —
/// may take before it is abandoned. Without it a black-hole network hangs
/// the check forever (#46).
const kUpdateRequestTimeout = Duration(seconds: 10);

/// How long the installer download may go without delivering a single
/// chunk. The whole download has no deadline — an installer on a slow line
/// is legitimate — but a stalled socket is not.
const kDownloadStallTimeout = Duration(seconds: 60);

/// A GET made by something other than Dart's own TLS stack (#124).
///
/// On a school network that inspects TLS — a web filter or endpoint software
/// re-signing every certificate with its own CA — Dart's `HttpClient` fails
/// the handshake to GitHub with `CERTIFICATE_VERIFY_FAILED`: BoringSSL takes
/// a snapshot of the Windows *root* store at startup, never fetches a missing
/// intermediate, and so cannot chain what the filter hands it. Edge, `.NET`
/// and `curl.exe` on the same laptop all succeed, because Schannel trusts what
/// the machine trusts. This is the seam through which the updater borrows
/// that trust: `update_bootstrap.dart` wires it to the `curl.exe` Windows
/// ships, tests wire a fake, and everything above it keeps parsing the same
/// [http.Response].
///
/// Fetches [url] with [headers]. [timeout] bounds the whole request; `null`
/// means no deadline beyond a stall (the installer on a slow line is
/// legitimate). With [to] the body is streamed into that file and the
/// returned response has an empty body; without it the body comes back in
/// the response. Throws [UpdateCheckException] when the request itself did
/// not complete; an HTTP error status is returned, not thrown, so the caller
/// applies the same rules it applies to Dart's own answer.
///
/// `badCertificateCallback => true` is explicitly *not* what this is: the
/// updater executes what it downloads, and a middlebox that can replace the
/// installer can replace the `.sha256` beside it too. The fallback trusts
/// what the operating system trusts, and `verifySha256` still runs after it.
typedef NativeGet = Future<http.Response> Function(
  Uri url, {
  Map<String, String> headers,
  Duration? timeout,
  File? to,
});

/// Where a transport diagnostic goes when nothing is shown on screen.
typedef TransportLog = void Function(String message);

/// Whether [error] is Dart's `HttpClient` reporting that the proxy refused
/// to open the `CONNECT` tunnel for want of a login (#140): the
/// `HttpException("Proxy failed to establish tunnel (407 …)")` it throws
/// when the proxy answers the tunnel request with `407 Proxy Authentication
/// Required`, as `package:http` hands it on — a `ClientException` carrying
/// the same message.
///
/// That is what an authenticating school proxy (NTLM / Kerberos, the usual
/// with an AD-joined filter) does to every request the updater makes, and
/// it is the second and last reason the [NativeGet] fallback is engaged:
/// Dart can only answer such a challenge with a login it is given, and the
/// app has none — the student is logged in to Windows, not to the app —
/// while the `curl.exe` Windows ships answers it through SSPI with that
/// Windows login and no stored secret. Recognised by that message and that
/// status, and by nothing wider: a tunnel refused for another reason (a 502
/// from a proxy with no route, a 403 from one that blocks the host), a 404,
/// a timeout or a dead socket are not the login problem, and the fallback
/// would only mask them. The wording is `dart:io`'s own, matched as a
/// prefix so the proxy's reason phrase after the status does not matter.
bool isProxyLoginChallenge(Object error) {
  final String message = switch (error) {
    http.ClientException e => e.message,
    HttpException e => e.message,
    _ => '',
  };
  return message.startsWith('Proxy failed to establish tunnel (407');
}

/// What About says for a proxy that asks for a login (#140), in front of
/// whatever the transports said: "407 Proxy Authentication Required" is the
/// network's wording and not something a student can act on; this is what
/// they can tell whoever runs the network.
const String kProxyLoginReason =
    "the network's proxy asks for a login "
    '(HTTP 407 Proxy Authentication Required)';

/// The client the updater's own requests are made with: Dart's `HttpClient`,
/// told about [proxy] when there is one (#133).
///
/// `package:http`'s default client ignores every proxy setting a machine has;
/// `IOClient` over a configured `HttpClient` is the documented way to give it
/// one, and `UpdateProxy.findProxy` answers per URL so a bypassed host still
/// goes direct. Without a proxy this is the plain client it always was.
http.Client httpClientVia(UpdateProxy? proxy) {
  if (proxy == null) return http.Client();
  return IOClient(HttpClient()..findProxy = proxy.findProxy);
}

/// A release the app can offer: which version, which installer, and the
/// hash the download has to match.
///
/// Built from the GitHub Releases API by `github_release.dart` (#50); it used
/// to come from a hand-published `version.json`.
class UpdateInfo {
  UpdateInfo(
    this.version,
    this.url,
    this.sha256, {
    this.notes = '',
    this.viaNativeTransport = false,
  });

  final String version;
  final Uri url;
  final String sha256;

  /// The release notes, as written on the GitHub release. Empty when the
  /// release has none. The manifest could not carry these at all.
  final String notes;

  /// Whether the check that found this release only got through on the
  /// [NativeGet] fallback (#124, #140).
  ///
  /// Carried on the release so the download that follows goes straight to
  /// the transport that worked, instead of failing the same handshake — or
  /// the same proxy login challenge — again first. The installer asset sits
  /// behind the same inspection, and the same proxy, as the API.
  final bool viaNativeTransport;
}

bool isNewer(String remote, String local) {
  // Allow build metadata (+n) by stripping and comparing separately
  Version parse(String v) {
    final parts = v.split('+');
    return Version.parse(parts.first);
  }

  final r = parse(remote), l = parse(local);
  if (r > l) return true;
  if (r == l) {
    // compare build numbers if present
    int buildNum(String v) =>
        int.tryParse(v.split('+').elementAtOrNull(1) ?? '') ?? 0;
    return buildNum(remote) > buildNum(local);
  }
  return false;
}

/// Downloads the installer to a temp file, reporting how far it has got.
///
/// [onProgress] is called with a 0..1 fraction after every chunk, but only
/// when the server declared a `Content-Length`: without one there is no
/// denominator, the caller is left on 0, and the UI renders that as an
/// indeterminate bar rather than a bar frozen at 0% (#48).
///
/// The body is consumed with a listen loop rather than `pipe`/`addStream`,
/// which hand the whole stream to the sink and offer no per-chunk hook —
/// that is why there was no progress to report before (#48).
///
/// Throws an [UpdateCheckException] on any failure — a non-200 status, a
/// transport error, a request that never gets a response, or a stream that
/// stalls for [stallTimeout]. It used to return `null` for a bad status and
/// hang forever on a dead socket (#46). A partial file is removed.
///
/// A TLS handshake Dart cannot complete (#124), or a proxy that refuses the
/// tunnel for want of a login (#140, [isProxyLoginChallenge]) — and only
/// those — are retried through [nativeGet] when one is given, and
/// [preferNative] skips straight to it for a release whose check already
/// needed it. The fallback reports no progress: the bar stays indeterminate,
/// which the UI already renders for a download with no declared length. A
/// 404, a timeout, a dead socket are neither the certificate problem nor
/// the login problem and are never retried natively — that would only hide
/// what actually went wrong.
///
/// [proxy] is the machine's proxy setting (#133), honoured when no [client]
/// is given; the native transport was built with the same one.
Future<File> downloadToTemp(
  Uri url, {
  void Function(double fraction)? onProgress,
  http.Client? client,
  Duration responseTimeout = kUpdateRequestTimeout,
  Duration stallTimeout = kDownloadStallTimeout,
  NativeGet? nativeGet,
  bool preferNative = false,
  UpdateProxy? proxy,
  TransportLog? log,
}) async {
  final tmp = File(
    p.join(Directory.systemTemp.path, 'python_teacher_install.exe'),
  );
  if (preferNative && nativeGet != null) {
    return _downloadNatively(nativeGet, url, tmp);
  }

  final owned = client == null;
  final c = client ?? httpClientVia(proxy);
  try {
    final res = await c.send(http.Request('GET', url)).timeout(responseTimeout);
    if (res.statusCode != HttpStatus.ok) {
      throw UpdateCheckException(
        'installer download from $url returned HTTP ${res.statusCode}',
      );
    }
    final total = res.contentLength;
    var received = 0;
    final sink = tmp.openWrite();
    try {
      await for (final chunk in res.stream.timeout(stallTimeout)) {
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null && total != null && total > 0) {
          onProgress(received / total);
        }
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      // Close by hand rather than letting the sink dangle: `pipe` used to do
      // this and then made the close below throw "File closed", burying the
      // timeout that actually went wrong.
      try {
        await sink.close();
      } catch (_) {
        // Already broken; the real failure is the one being rethrown.
      }
      rethrow;
    }
    return tmp;
  } on UpdateCheckException {
    rethrow;
  } on TimeoutException {
    await _deleteQuietly(tmp);
    throw UpdateCheckException('installer download from $url stalled');
  } on HandshakeException catch (e) {
    // One clause above the catch-all on purpose: `package:http` wraps only
    // `SocketException` and `HttpException`, so this arrives as itself.
    await _deleteQuietly(tmp);
    return _retryDownloadNatively(
      nativeGet,
      url,
      tmp,
      reason: '$e',
      why: 'Dart could not complete the TLS handshake for the installer ($e)',
      log: log,
    );
  } on http.ClientException catch (e) {
    // The proxy's 407 on the tunnel arrives wrapped in this (#140); every
    // other `ClientException` is an ordinary failure and reported as one.
    await _deleteQuietly(tmp);
    if (!isProxyLoginChallenge(e)) {
      throw UpdateCheckException('installer download from $url failed: $e');
    }
    return _retryDownloadNatively(
      nativeGet,
      url,
      tmp,
      reason: kProxyLoginReason,
      why:
          'the proxy asks for a login to open the tunnel for the installer '
          '($e)',
      log: log,
    );
  } on Object catch (e) {
    await _deleteQuietly(tmp);
    throw UpdateCheckException('installer download from $url failed: $e');
  } finally {
    if (owned) c.close();
  }
}

/// The installer through [nativeGet] after Dart's own attempt failed for
/// [reason] — or, with no [nativeGet] to retry on, that reason as the
/// failure. [why] is the log line's account of it.
///
/// When the fallback fails too, [reason] stays in front: it is the one that
/// explains the network, and the one About should still be telling the
/// truth about.
Future<File> _retryDownloadNatively(
  NativeGet? nativeGet,
  Uri url,
  File tmp, {
  required String reason,
  required String why,
  TransportLog? log,
}) async {
  if (nativeGet == null) {
    throw UpdateCheckException('installer download from $url failed: $reason');
  }
  log?.call('Update: $why; retrying through the Windows-native transport.');
  try {
    return await _downloadNatively(nativeGet, url, tmp);
  } on UpdateCheckException catch (native) {
    throw UpdateCheckException(
      'installer download from $url failed: $reason; the Windows-native '
      'fallback failed too: ${native.message}',
    );
  }
}

/// The installer through [nativeGet], into [tmp]. No progress: the bar stays
/// indeterminate for the length of the download.
Future<File> _downloadNatively(NativeGet nativeGet, Uri url, File tmp) async {
  final http.Response res;
  try {
    res = await nativeGet(url, to: tmp);
  } on UpdateCheckException {
    await _deleteQuietly(tmp);
    rethrow;
  } on Object catch (e) {
    await _deleteQuietly(tmp);
    throw UpdateCheckException('installer download from $url failed: $e');
  }
  if (res.statusCode != HttpStatus.ok) {
    await _deleteQuietly(tmp);
    throw UpdateCheckException(
      'installer download from $url returned HTTP ${res.statusCode}',
    );
  }
  return tmp;
}

Future<void> _deleteQuietly(File file) async {
  try {
    if (file.existsSync()) await file.delete();
  } on FileSystemException {
    // A leftover temp file is not worth failing the update check over.
  }
}

/// Hashes [file] against [expectedHex] without ever holding it in memory.
///
/// Read back in chunks off `openRead()`: the installer is ~250 MB, and
/// `readAsBytes` pulled all of it into RAM on a machine that has just
/// finished writing the same bytes to disk (#48). The download itself was
/// already streamed; the hashing was the one place that buffered.
Future<bool> verifySha256(File file, String expectedHex) async {
  Digest? result;
  final input = sha256.startChunkedConversion(
    ChunkedConversionSink<Digest>.withCallback(
      (digests) => result = digests.single,
    ),
  );
  try {
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
  } finally {
    input.close();
  }
  final digest = result;
  if (digest == null) return false;
  return digest.toString().toLowerCase() == expectedHex.toLowerCase();
}

/// Spawns the installer detached and ends this process, so the installer can
/// replace the files underneath it.
///
/// Does not come back: the `exit(0)` is the point. The app is brought back
/// afterwards by the installer's own `[Run]` entry, which fires on the
/// `/RELAUNCH=1` switch in `kSilentInstallArguments` (#49) — before that the
/// silent install skipped every `[Run]` entry and the app was simply gone.
///
/// Takes a path and an argument list rather than the seams' [File] so the one
/// call that spawns a process and kills the app is a value a test can swap
/// out and assert on.
Future<void> runInstallerAndExit(
  String executable,
  List<String> arguments,
) async {
  // Spawn detached so it continues after this process exits
  await Process.start(executable, arguments, mode: ProcessStartMode.detached);
  // Close the app
  exit(0);
}
