// The school file (#307, part of #261): how a school hands its students the
// configuration the school mode needs, without a build of its own.
//
// A small JSON file the teacher makes once and shares freely:
//
//   {
//     "formatVersion": 1,
//     "schoolName": "Example School",
//     "tenantId": "<Entra tenant id>",
//     "clientId": "<client id of the school's app registration>",
//     "databaseEndpoint": "https://<account>.documents.azure.com:443/",
//     "databaseName": "python-tutor"
//   }
//
// `databaseName` is optional (default `python-tutor`), and so is
// `redirectUri` (default `http://localhost`; the sign-in binds its own
// loopback port anyway). So is `databaseAccess` (#306): `"signIn"` reaches
// the database with the user's own sign-in, `"masterKey"` (the default)
// with the database key of the build. That holds in a build with school
// data; a build without uses the sign-in either way
// (`SchoolConfig.databaseAccessIn`, #336). Nothing in it is secret. A file that carries a field that looks
// like a key, a token or a password is refused, so such a value is never
// read, let alone kept.
//
// The app keeps the imported file as `school.json` in its app-data folder
// ([SchoolFileStore]); the mode follows from it at the next start
// (lib/core/app_start.dart).

import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The newest school-file format this app reads. A file with a higher
/// `formatVersion` is refused with [SchoolFileProblem.newerFormat].
const int kSchoolFileFormatVersion = 1;

/// The redirect URI a school file without one gets.
const String kDefaultSchoolRedirectUri = 'http://localhost';

/// Why a school file was refused.
enum SchoolFileProblem {
  /// The file could not be read from disk.
  unreadable,

  /// Not JSON, or not a JSON object.
  notASchoolFile,

  /// Made for a newer version of the app.
  newerFormat,

  /// A required field is missing or has a value the app cannot use.
  invalidField,

  /// A field that looks like a key, token or password.
  containsSecret,
}

/// A school file the app will not use. Nothing was stored.
class SchoolFileException implements Exception {
  const SchoolFileException(this.problem, {this.field, this.version});

  final SchoolFileProblem problem;

  /// The field at fault, for [SchoolFileProblem.invalidField] and
  /// [SchoolFileProblem.containsSecret].
  final String? field;

  /// The file's `formatVersion`, for [SchoolFileProblem.newerFormat].
  final int? version;

  @override
  String toString() =>
      'SchoolFileException(${problem.name}'
      '${field == null ? '' : ', field: $field'}'
      '${version == null ? '' : ', version: $version'})';
}

/// Field names a school file must never carry: a school file is shared
/// freely, so anything secret in it is a mistake to stop, not to read.
final RegExp _secretLikeName = RegExp(
  r'key|secret|password|passwd|token|credential',
  caseSensitive: false,
);

/// The first field name anywhere in [json] that looks secret, or `null`.
String? _secretLikeField(Object? json) {
  if (json is Map) {
    for (final entry in json.entries) {
      final name = entry.key.toString();
      if (_secretLikeName.hasMatch(name)) return name;
      final nested = _secretLikeField(entry.value);
      if (nested != null) return nested;
    }
  } else if (json is List) {
    for (final item in json) {
      final nested = _secretLikeField(item);
      if (nested != null) return nested;
    }
  }
  return null;
}

/// Reads a school file's text. Throws [SchoolFileException] when the app
/// cannot use it.
SchoolConfig parseSchoolFile(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const SchoolFileException(SchoolFileProblem.notASchoolFile);
  }
  if (decoded is! Map<String, dynamic>) {
    throw const SchoolFileException(SchoolFileProblem.notASchoolFile);
  }
  final Map<String, dynamic> json = decoded;
  // Before anything else is read.
  final secret = _secretLikeField(json);
  if (secret != null) {
    throw SchoolFileException(SchoolFileProblem.containsSecret, field: secret);
  }
  final version = json['formatVersion'];
  if (version is! int || version < 1) {
    // Without a version it is not a school file at all.
    throw const SchoolFileException(SchoolFileProblem.notASchoolFile);
  }
  if (version > kSchoolFileFormatVersion) {
    throw SchoolFileException(SchoolFileProblem.newerFormat, version: version);
  }

  String required(String field) {
    final value = json[field];
    if (value is! String || SchoolConfig.isMissingValue(value)) {
      throw SchoolFileException(SchoolFileProblem.invalidField, field: field);
    }
    return value.trim();
  }

  String optional(String field, String fallback) {
    final value = json[field];
    if (value == null) return fallback;
    if (value is! String || value.trim().isEmpty) {
      throw SchoolFileException(SchoolFileProblem.invalidField, field: field);
    }
    return value.trim();
  }

  final schoolName = required('schoolName');
  final tenantId = required('tenantId');
  final clientId = required('clientId');
  final endpoint = Uri.tryParse(required('databaseEndpoint'));
  if (endpoint == null || endpoint.scheme != 'https' || endpoint.host.isEmpty) {
    throw const SchoolFileException(
      SchoolFileProblem.invalidField,
      field: 'databaseEndpoint',
    );
  }
  final accessName = optional('databaseAccess', DatabaseAccess.masterKey.name);
  final access = DatabaseAccess.values
      .where((a) => a.name == accessName)
      .firstOrNull;
  if (access == null) {
    throw const SchoolFileException(
      SchoolFileProblem.invalidField,
      field: 'databaseAccess',
    );
  }
  return SchoolConfig(
    tenantId: tenantId,
    clientId: clientId,
    redirectUri: optional('redirectUri', kDefaultSchoolRedirectUri),
    databaseEndpoint: endpoint,
    databaseName: optional('databaseName', kDefaultSchoolDatabaseName),
    schoolName: schoolName,
    databaseAccess: access,
  );
}

/// [config] as a school file, in the current format. [parseSchoolFile]
/// reads it back as the same value; it needs a [SchoolConfig.schoolName]
/// (see [SchoolConfig.named]).
String encodeSchoolFile(SchoolConfig config) {
  final name = config.schoolName;
  if (name == null || name.trim().isEmpty) {
    throw ArgumentError.value(config, 'config', 'a school file needs a name');
  }
  return const JsonEncoder.withIndent('  ').convert({
    'formatVersion': kSchoolFileFormatVersion,
    'schoolName': name,
    'tenantId': config.tenantId,
    'clientId': config.clientId,
    'redirectUri': config.redirectUri,
    'databaseEndpoint': config.databaseEndpoint.toString(),
    'databaseName': config.databaseName,
    // Only when it is not the default, so a file for a school on the
    // database key reads exactly as before #306.
    if (config.databaseAccess != DatabaseAccess.masterKey)
      'databaseAccess': config.databaseAccess.name,
  });
}

/// The imported school file, kept as `school.json` in the app-data folder.
class SchoolFileStore {
  SchoolFileStore(this._dir);

  /// The store in the app's own app-data folder.
  factory SchoolFileStore.appData() =>
      SchoolFileStore(getApplicationSupportDirectory);

  final Future<Directory> Function() _dir;

  static const String fileName = 'school.json';

  Future<File> get _file async => File(p.join((await _dir()).path, fileName));

  /// The stored school, or `null` when there is none. A stored file the app
  /// can no longer read counts as none: the start then asks again.
  Future<SchoolConfig?> read() async {
    final file = await _file;
    if (!file.existsSync()) return null;
    try {
      return parseSchoolFile(await file.readAsString());
    } catch (e) {
      debugPrint('SchoolFileStore: ignoring ${file.path}: $e');
      return null;
    }
  }

  /// Whether a school file is kept, readable or not.
  Future<bool> exists() async => (await _file).existsSync();

  /// Stores [config] as the school, replacing any earlier one. Written to a
  /// temporary file first, so an interrupted write leaves the old one.
  Future<void> write(SchoolConfig config) async {
    final file = await _file;
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(encodeSchoolFile(config), flush: true);
    await tmp.rename(file.path);
  }

  /// Forgets the school. Nothing else in the app-data folder is touched.
  Future<void> delete() async {
    final file = await _file;
    if (file.existsSync()) await file.delete();
  }
}

final schoolFileStoreProvider = Provider<SchoolFileStore>(
  (_) => SchoolFileStore.appData(),
);

/// Asks the user for a school file and returns its text, or `null` when they
/// cancelled. Throws [SchoolFileException] when the file cannot be read.
typedef SchoolFilePicker = Future<String?> Function();

Future<String?> _pickSchoolFileFromDisk() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );
  final path = result?.files.single.path;
  if (path == null) return null;
  try {
    return await File(path).readAsString();
  } on FileSystemException {
    throw const SchoolFileException(SchoolFileProblem.unreadable);
  } on FormatException {
    // Not UTF-8 text.
    throw const SchoolFileException(SchoolFileProblem.notASchoolFile);
  }
}

/// The OS file dialog in the app; a fixed answer in tests.
final schoolFilePickerProvider = Provider<SchoolFilePicker>(
  (_) => _pickSchoolFileFromDisk,
);
