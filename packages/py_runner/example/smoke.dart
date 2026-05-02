// Smoke test for InstallerPyHostLocator + PyRunner end-to-end.
//
// Usage (from repo root):
//   $env:PY_RUNNER_PYTHON     = "build\python_bundle\python\python.exe"
//   $env:PY_RUNNER_HOST_SCRIPT = "packages\py_runner\python\host.py"
//   dart run packages/py_runner/example/smoke.dart

import 'dart:io';

import 'package:py_runner/py_runner.dart';

Future<void> main() async {
  final runner = PyRunner(locator: const InstallerPyHostLocator());

  try {
    await runner.start();
    stdout.writeln('Host ready — Python ${runner.readyInfo?.pythonVersion}');

    final handle = runner.run("print('hi')");
    final buf = StringBuffer();
    handle.stdout.listen(buf.write);

    final result = await handle.done;

    if (result.status != RunStatus.ok) {
      stderr.writeln('FAIL: status ${result.status}');
      if (result.exception != null) stderr.writeln(result.exception);
      exit(1);
    }

    final out = buf.toString().trim();
    if (!out.contains('hi')) {
      stderr.writeln('FAIL: expected "hi" in output, got: $out');
      exit(1);
    }

    stdout.writeln('stdout: $out');
    stdout.writeln('PASS');
  } on PyRunnerNotInstalled catch (e) {
    stderr.writeln(e);
    exit(1);
  } finally {
    await runner.shutdown();
  }
}
