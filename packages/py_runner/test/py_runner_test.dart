@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:py_runner/py_runner.dart';
import 'package:test/test.dart';

import 'support/python_resolver.dart';

void main() {
  late String pythonExe;

  setUpAll(() async {
    final resolved = await resolveTestPython();
    if (resolved == null) {
      throw StateError(
        'No python executable found on PATH. Set PY_RUNNER_TEST_PYTHON to '
        'point at one.',
      );
    }
    pythonExe = resolved;
  });

  PyRunner buildRunner() => PyRunner(
    locator: ExplicitPyHostLocator(
      pythonExecutable: pythonExe,
      hostScript: fixturePath('echo_host.py'),
    ),
  );

  test('start() transitions stopped → starting → ready', () async {
    final runner = buildRunner();
    addTearDown(runner.shutdown);

    final transitions = <PyRunnerStatus>[];
    final sub = runner.statusChanges.listen(transitions.add);
    addTearDown(sub.cancel);

    expect(runner.status, PyRunnerStatus.stopped);
    await runner.start().timeout(const Duration(seconds: 10));
    // Broadcast-controller adds are dispatched on a microtask, so the
    // 'ready' transition arrives at the listener after start() resolves.
    await Future<void>.delayed(Duration.zero);
    expect(runner.status, PyRunnerStatus.ready);
    expect(transitions, [PyRunnerStatus.starting, PyRunnerStatus.ready]);
    expect(runner.readyInfo, isNotNull);
    expect(runner.readyInfo!.platform, 'echo_fixture');
  });

  test('run() observes stdout and done(ok)', () async {
    final runner = buildRunner();
    addTearDown(runner.shutdown);
    await runner.start();

    final handle = runner.run('print("hi")');
    final stdoutLines = <String>[];
    final stdoutSub = handle.stdout.listen(stdoutLines.add);
    addTearDown(stdoutSub.cancel);

    final result = await handle.done.timeout(const Duration(seconds: 10));
    expect(result.status, RunStatus.ok);
    expect(result.exception, isNull);
    expect(stdoutLines.join(), contains('print("hi")'));
    expect(handle.id, hasLength(36)); // UUID v4 with dashes.
  });

  test('cancel() resolves with done(cancelled)', () async {
    final runner = buildRunner();
    addTearDown(runner.shutdown);
    await runner.start();

    final handle = runner.run('# sleep_ms=1000\n');
    // Let the worker enter its sleep loop before we cancel.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await handle.cancel().timeout(const Duration(seconds: 5));

    final result = await handle.done;
    expect(result.status, RunStatus.cancelled);
  });

  test(
    'a successor run cancels the predecessor and then completes itself',
    () async {
      final runner = buildRunner();
      addTearDown(runner.shutdown);
      await runner.start();

      final first = runner.run('# sleep_ms=1000\n');
      // Yield once so the first exec frame is on the wire before we replace.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final second = runner.run('print("second")');

      final firstResult = await first.done.timeout(const Duration(seconds: 5));
      final secondResult = await second.done.timeout(
        const Duration(seconds: 5),
      );

      expect(firstResult.status, RunStatus.cancelled);
      expect(secondResult.status, RunStatus.ok);
      expect(first.id, isNot(equals(second.id)));
    },
  );

  test('run() before start() throws StateError', () async {
    final runner = buildRunner();
    addTearDown(runner.shutdown);
    expect(() => runner.run('print(1)'), throwsStateError);
  });

  test('shutdown is idempotent and ends in stopped status', () async {
    final runner = buildRunner();
    await runner.start();
    await runner.shutdown();
    expect(runner.status, PyRunnerStatus.stopped);
    await runner.shutdown(); // second call is a no-op.
    expect(runner.status, PyRunnerStatus.stopped);
  });

  group('end-to-end against the real bundled python', () {
    // Gated by PY_RUNNER_E2E_PYTHON: the path to python.exe from a built
    // bundle (typically `build/python_bundle/python/python.exe` after
    // running `tooling/python/build_bundle.ps1`).
    final e2ePython = Platform.environment['PY_RUNNER_E2E_PYTHON'];
    final sep = Platform.pathSeparator;
    final realHostScript = '${Directory.current.path}${sep}python${sep}host.py';

    test(
      'print("hi") yields stdout and done(ok) on the real host',
      () async {
        final runner = PyRunner(
          locator: ExplicitPyHostLocator(
            pythonExecutable: e2ePython!,
            hostScript: realHostScript,
          ),
        );
        addTearDown(runner.shutdown);
        await runner.start().timeout(const Duration(seconds: 30));

        final handle = runner.run('print("hi")');
        final stdoutLines = <String>[];
        handle.stdout.listen(stdoutLines.add);
        final result = await handle.done.timeout(const Duration(seconds: 30));
        expect(result.status, RunStatus.ok);
        expect(stdoutLines.join(), contains('hi'));
      },
      skip: (e2ePython == null || e2ePython.isEmpty)
          ? 'Set PY_RUNNER_E2E_PYTHON=<path-to-python.exe> to enable.'
          : false,
    );
  });
}
