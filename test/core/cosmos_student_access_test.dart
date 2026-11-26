// Issue #306 — with access through the user's own sign-in, Cosmos decides
// what a user may do from roles an administrator assigns per container. The
// list of those roles is `kStudentAccess` in `lib/core/cosmos_paths.dart`,
// worked out from the code; the README repeats it as a table and as the `az`
// commands to run.
//
// A container that the app opens but that has no role makes every student's
// request there fail with 403, and nothing in the running app says why.
// Nothing at runtime can catch the list drifting from the containers or
// from the README, so the files are compared here, as
// `cosmos_paths_readme_parity_test.dart` does for the partition keys:
//
// - every container in `cosmos_paths.dart` has an entry, and no entry is for
//   a container that is not there;
// - the README's table says the same access per container;
// - the README's commands give students Data Contributor exactly on the
//   read-and-write containers and Data Reader exactly on the read ones, and
//   teachers Data Contributor on the whole database, with the built-in
//   role ids.

import 'dart:io';

import 'package:ai_tutor_python/core/cosmos_paths.dart';
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

/// The container names declared in `cosmos_paths.dart`.
Set<String> _containersIn(String source) {
  final names = {
    for (final m in RegExp(
      r"^const String _\w+Container = '([^']+)';",
      multiLine: true,
    ).allMatches(source))
      m.group(1)!,
  };
  // Guard the parser: a container declared another way would escape the
  // comparison instead of failing it.
  expect(
    names.length,
    RegExp(r'static CosmosContainer \w+\(\)').allMatches(source).length,
    reason:
        'Every container getter in cosmos_paths.dart should have its own '
        "`const String _xContainer = 'name';` declaration.",
  );
  return names;
}

const Map<String, StudentAccess> _readmeLabels = {
  'read and write': StudentAccess.readWrite,
  'read': StudentAccess.read,
  'none': StudentAccess.none,
};

/// Container -> access, from the README's "Roles per container" table.
Map<String, StudentAccess> _tableIn(String readme) {
  final out = <String, StudentAccess>{};
  for (final m in RegExp(
    r'^\|\s*`([a-z_]+)`\s*\|\s*(read and write|read|none)\s*\|[^\n]*\|\s*$',
    multiLine: true,
  ).allMatches(readme)) {
    expect(
      out.containsKey(m.group(1)),
      isFalse,
      reason: 'README lists `${m.group(1)}` twice in the roles table.',
    );
    out[m.group(1)!] = _readmeLabels[m.group(2)]!;
  }
  return out;
}

final _studentCommand = RegExp(
  r'^az cosmosdb sql role assignment create --account-name \$account '
  r'--resource-group \$group --scope "/dbs/\$db/colls/([a-z_]+)" '
  r'--principal-id \$students --role-definition-id \$(reader|contributor)$',
  multiLine: true,
);

void main() {
  final source = _read('lib/core/cosmos_paths.dart');
  final readme = _read('README.md');

  test('every container in cosmos_paths.dart has a role for students', () {
    final containers = _containersIn(source);
    expect(containers, isNotEmpty);
    expect(
      kStudentAccess.keys.toSet(),
      containers,
      reason:
          'kStudentAccess in lib/core/cosmos_paths.dart must have one entry '
          'per container declared there: work out from the code whether a '
          "student's session writes it, only reads it, or never opens it "
          '(#306).',
    );
  });

  test('the README table gives every container the access of '
      'kStudentAccess', () {
    expect(
      _tableIn(readme),
      kStudentAccess,
      reason:
          'The "Roles per container" table in README.md must list exactly '
          'the containers of kStudentAccess, each with its access.',
    );
  });

  test('the README commands assign exactly those roles', () {
    final assigned = <String, StudentAccess>{};
    for (final m in _studentCommand.allMatches(readme)) {
      expect(
        assigned.containsKey(m.group(1)),
        isFalse,
        reason: 'README assigns students a role on `${m.group(1)}` twice.',
      );
      assigned[m.group(1)!] = m.group(2) == 'contributor'
          ? StudentAccess.readWrite
          : StudentAccess.read;
    }
    expect(
      assigned,
      {
        for (final e in kStudentAccess.entries)
          if (e.value != StudentAccess.none) e.key: e.value,
      },
      reason:
          'README.md must give students Data Contributor on every '
          'read-and-write container, Data Reader on every read one, and '
          'no role on the others.',
    );

    // Any other line that assigns students a role would slip past the
    // pattern above, so count them all.
    expect(
      RegExp(r'--principal-id \$students').allMatches(readme).length,
      assigned.length,
      reason:
          'Every students role command must have the exact shape the '
          'test reads.',
    );

    expect(
      readme,
      contains(
        r'az cosmosdb sql role assignment create --account-name $account '
        r'--resource-group $group --scope "/dbs/$db" --principal-id $teachers '
        r'--role-definition-id $contributor',
      ),
      reason: 'Teachers get Data Contributor on the whole database.',
    );
  });

  test('the README names the built-in role ids', () {
    expect(
      readme,
      contains(r'$reader      = "00000000-0000-0000-0000-000000000001"'),
    );
    expect(
      readme,
      contains(r'$contributor = "00000000-0000-0000-0000-000000000002"'),
    );
  });
}
