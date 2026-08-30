import 'dart:io';

/// Resolves a python interpreter usable for stdlib-only fixtures.
///
/// Order:
///   1. `PY_RUNNER_TEST_PYTHON` env var (explicit override, e.g. for CI or
///      to point at the bundled interpreter from `tooling/python/build_bundle.ps1`).
///   2. `python` on PATH (Windows).
///   3. `python3` on PATH (POSIX).
///
/// Returns null if none of the candidates respond to `--version` within a
/// short timeout — tests should `markTestSkipped` in that case rather than
/// failing the suite.
Future<String?> resolveTestPython() async {
  final candidates = <String>[
    if (Platform.environment['PY_RUNNER_TEST_PYTHON'] != null &&
        Platform.environment['PY_RUNNER_TEST_PYTHON']!.isNotEmpty)
      Platform.environment['PY_RUNNER_TEST_PYTHON']!,
    if (Platform.isWindows) 'python' else 'python3',
    if (Platform.isWindows) 'py' else 'python',
  ];

  for (final candidate in candidates) {
    if (await _probe(candidate)) return candidate;
  }
  return null;
}

Future<bool> _probe(String executable) async {
  try {
    final result = await Process.run(executable, <String>[
      '--version',
    ], runInShell: false).timeout(const Duration(seconds: 5));
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Absolute path to a fixture file under `test/fixtures/`. Tests are run
/// from the package root, so `Directory.current` is `packages/py_runner`.
String fixturePath(String relative) {
  final sep = Platform.pathSeparator;
  return '${Directory.current.path}${sep}test${sep}fixtures$sep$relative';
}
