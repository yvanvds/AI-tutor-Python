import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
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

/// A release the app can offer: which version, which installer, and the
/// hash the download has to match.
///
/// Built from the GitHub Releases API by `github_release.dart` (#50); it used
/// to come from a hand-published `version.json`.
class UpdateInfo {
  UpdateInfo(this.version, this.url, this.sha256, {this.notes = ''});

  final String version;
  final Uri url;
  final String sha256;

  /// The release notes, as written on the GitHub release. Empty when the
  /// release has none. The manifest could not carry these at all.
  final String notes;
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
Future<File> downloadToTemp(
  Uri url, {
  void Function(double fraction)? onProgress,
  http.Client? client,
  Duration responseTimeout = kUpdateRequestTimeout,
  Duration stallTimeout = kDownloadStallTimeout,
}) async {
  final owned = client == null;
  final c = client ?? http.Client();
  final tmp = File(
    p.join(Directory.systemTemp.path, 'python_teacher_install.exe'),
  );
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
  } on Object catch (e) {
    await _deleteQuietly(tmp);
    throw UpdateCheckException('installer download from $url failed: $e');
  } finally {
    if (owned) c.close();
  }
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
