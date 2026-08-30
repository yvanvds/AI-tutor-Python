import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart'; // add to pubspec
import 'package:path/path.dart' as p;

class UpdateInfo {
  final String version;
  final Uri url;
  final String sha256;
  UpdateInfo(this.version, this.url, this.sha256);
  factory UpdateInfo.fromJson(Map<String, dynamic> j) =>
      UpdateInfo(j['version'], Uri.parse(j['url']), j['sha256']);
}

/// A leading byte-order mark. `jsonDecode` does not skip it and fails with
/// `FormatException: Unexpected character (at character 1)`.
const _bom = '\u{FEFF}';

/// Parses a release manifest body into an [UpdateInfo], tolerating a BOM
/// that a caller decoded into the string (a hand-edited file read from
/// disk, a payload decoded elsewhere). See #45.
UpdateInfo parseUpdateManifest(String body) {
  final withoutBom = body.startsWith(_bom) ? body.substring(_bom.length) : body;
  return UpdateInfo.fromJson(jsonDecode(withoutBom));
}

Future<UpdateInfo?> fetchUpdateInfo(Uri manifestUrl) async {
  final res = await http.get(manifestUrl);
  if (res.statusCode != 200) return null;
  // Decode the bytes as UTF-8 rather than reading `res.body`: that getter
  // honours the response charset and falls back to latin1 for a type like
  // `application/octet-stream`, which turns the BOM the release manifest
  // carries (#45) into three characters and makes `jsonDecode` throw. JSON
  // is UTF-8 (RFC 8259), and `Utf8Decoder` drops a leading BOM.
  return parseUpdateManifest(utf8.decode(res.bodyBytes, allowMalformed: true));
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

Future<File?> downloadToTemp(Uri url) async {
  final res = await http.Client().send(http.Request('GET', url));
  if (res.statusCode != 200) return null;
  final tmp = File(
    p.join(Directory.systemTemp.path, 'python_teacher_install.exe'),
  );
  final sink = tmp.openWrite();
  await res.stream.pipe(sink);
  await sink.close();
  return tmp;
}

Future<bool> verifySha256(File file, String expectedHex) async {
  final bytes = await file.readAsBytes();
  final digest = sha256.convert(bytes).toString();
  return digest.toLowerCase() == expectedHex.toLowerCase();
}

Future<void> runInstallerAndExit(
  File installer, {
  List<String> args = const [],
}) async {
  // Spawn detached so it continues after this process exits
  await Process.start(installer.path, args, mode: ProcessStartMode.detached);
  // Close the app
  exit(0);
}
