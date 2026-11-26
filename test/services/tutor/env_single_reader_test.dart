// #337: `OPEN_AI_API_KEY` from `.env` (`Env`) is read in one place,
// lib/services/tutor/openai_wiring.dart, where it is only the fallback for a
// school's `config/global` without `ApiKey`. A connector or a service that
// read it on its own would go out on the fallback past the school's key.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('only openai_wiring.dart reads Env', () {
    const allowed = {
      'lib/services/tutor/openai_wiring.dart',
      'lib/services/tutor/env.dart',
      'lib/services/tutor/env.g.dart',
    };
    // A use or an import; a comment that only names it reads nothing.
    final reader = RegExp(r"\bEnv\s*\.|import\s+'[^']*tutor/env\.dart'");
    final readers = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => p.posix.joinAll(p.split(f.path)))
        .where((path) => !allowed.contains(path))
        .where((path) => reader.hasMatch(File(path).readAsStringSync()))
        .toList();
    expect(readers, isEmpty);
  });
}
