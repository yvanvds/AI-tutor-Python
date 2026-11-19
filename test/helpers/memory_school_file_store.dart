// A school-file store in memory (#307), for widget tests: the real
// `SchoolFileStore` writes to disk, which a widget test's fake clock does not
// wait for. Encodes and parses on the way, so what a test reads back is what
// the real store would have kept.

import 'dart:io';

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/core/school_file.dart';

class MemorySchoolFileStore extends SchoolFileStore {
  MemorySchoolFileStore([SchoolConfig? stored])
    : _text = stored == null ? null : encodeSchoolFile(stored),
      super(() async => Directory.systemTemp);

  String? _text;

  /// The stored school, read back as the real store would.
  SchoolConfig? get stored => _text == null ? null : parseSchoolFile(_text!);

  @override
  Future<SchoolConfig?> read() async => stored;

  @override
  Future<void> write(SchoolConfig config) async =>
      _text = encodeSchoolFile(config);

  @override
  Future<void> delete() async => _text = null;
}

/// A school file as a teacher would make it.
String exampleSchoolFile({
  int formatVersion = 1,
  String schoolName = 'Example School',
  Map<String, Object?> extra = const {},
}) =>
    '''
{
  "formatVersion": $formatVersion,
  "schoolName": "$schoolName",
  "tenantId": "33333333-3333-3333-3333-333333333333",
  "clientId": "44444444-4444-4444-4444-444444444444",
  "databaseEndpoint": "https://example-school.documents.azure.com:443/"${extra.entries.map((e) => ',\n  "${e.key}": ${e.value is String ? '"${e.value}"' : e.value}').join()}
}
''';
