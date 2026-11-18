// #262: the build's school configuration (`AzureConfig`) is read in one
// place, lib/core/app_mode.dart. Everything else asks `appModeProvider`, so
// the school file of #307 can replace the build without a hunt.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('only app_mode.dart reads AzureConfig', () {
    const allowed = {
      'lib/core/app_mode.dart',
      'lib/services/config/azure_config.dart',
      'lib/services/config/azure_config.g.dart',
    };
    // A use or an import; a comment that only names it reads nothing.
    final reader = RegExp(
      r"\bAzureConfig\s*\.|import\s+'[^']*azure_config\.dart'",
    );
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
