// Issue #58 — the README's "create the containers below" table drifted from
// the containers the app actually opens: `lo_beliefs`, `turn_history`,
// `content` and `modules` were all live in `lib/core/cosmos_paths.dart` but
// missing from the table, so a fresh deployment came up half-working (the
// missing containers 404 on first query, and `safeCosmosStream` absorbs that
// into what looks like empty data).
//
// Nothing in the running app can catch this — the drift is between source and
// prose — so the two files are compared directly here, the same way
// `test/l10n/arb_parity_test.dart` and `test/tooling/installer_version_test.dart`
// compare repo files. `cosmos_paths.dart` is the source of truth; the README
// table must list exactly its containers with exactly its partition keys.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('${file.path} is missing (cwd: ${Directory.current})');
  }
  // A Windows checkout with core.autocrlf hands these over as CRLF, and a
  // stray \r would break the `$`-anchored matches below.
  return file.readAsStringSync().replaceAll('\r\n', '\n');
}

/// Container name -> partition key, as declared in `cosmos_paths.dart`.
///
/// Each container is a private `const String _xContainer = 'name';` plus a
/// getter whose doc comment opens with the partition key, e.g.
/// ``/// `/uid` partition. One doc per user.``
Map<String, String> _fromSource(String source) {
  final constants = <String, String>{
    for (final m in RegExp(
      r"^const String (_\w+) = '([^']+)';",
      multiLine: true,
    ).allMatches(source))
      m.group(1)!: m.group(2)!,
  };

  final result = <String, String>{};
  for (final m in RegExp(
    r'///\s*`(/\w+)` partition[\s\S]*?_client\.container\((_\w+)\)',
  ).allMatches(source)) {
    final partitionKey = m.group(1)!;
    final constant = m.group(2)!;
    final name = constants[constant];
    expect(
      name,
      isNotNull,
      reason: '$constant has no `const String $constant = ...` declaration.',
    );
    result[name!] = partitionKey;
  }
  return result;
}

/// Container name -> partition key, as listed in the README's step 3 table.
Map<String, String> _fromReadme(String readme) => {
  for (final m in RegExp(
    r'^\s*\|\s*`([a-z_]+)`\s*\|\s*`(/\w+)`\s*\|\s*$',
    multiLine: true,
  ).allMatches(readme))
    m.group(1)!: m.group(2)!,
};

void main() {
  final source = _read('lib/core/cosmos_paths.dart');
  final readme = _read('README.md');

  test('every container in cosmos_paths.dart is documented in the README', () {
    final declared = _fromSource(source);

    // Guard the parser itself: if the shape of `cosmos_paths.dart` changes so
    // that containers stop being recognised, this test would silently pass on
    // an empty comparison.
    expect(
      declared.length,
      RegExp(r'static CosmosContainer \w+\(\)').allMatches(source).length,
      reason:
          'Some container getter is missing the leading '
          '"/// `/<key>` partition" doc comment this test reads the partition '
          'key from — add it, or the container escapes this check.',
    );

    expect(
      _fromReadme(readme),
      declared,
      reason:
          'README.md step 3 must list exactly the containers declared in '
          'lib/core/cosmos_paths.dart, with the same partition keys. A '
          'container that is live in code but missing from the table means a '
          'fresh deployment never creates it (#58).',
    );
  });
}
