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

Future<UpdateInfo?> fetchUpdateInfo(Uri manifestUrl) async {
  final res = await http.get(manifestUrl);
  if (res.statusCode != 200) return null;
  final j = jsonDecode(res.body);
  return UpdateInfo.fromJson(j);
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
