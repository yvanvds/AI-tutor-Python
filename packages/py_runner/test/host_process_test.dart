@TestOn('vm')
library;

import 'dart:async';

import 'package:py_runner/py_runner.dart';
import 'package:py_runner/src/host_process.dart';
import 'package:test/test.dart';

import 'support/python_resolver.dart';

void main() {
  late String pythonExe;

  setUpAll(() async {
    final resolved = await resolveTestPython();
    if (resolved == null) {
      throw StateError(
        'No python executable found on PATH. Set PY_RUNNER_TEST_PYTHON to '
        'point at one (e.g. the bundled interpreter from '
        'tooling/python/build_bundle.ps1).',
      );
    }
    pythonExe = resolved;
  });

  Future<HostProcess> spawnEcho() => HostProcess.spawn(
    pythonExecutable: pythonExe,
    hostScript: fixturePath('echo_host.py'),
  );

  test('emits a ready frame on startup', () async {
    final host = await spawnEcho();
    final iter = StreamIterator(host.frames);
    addTearDown(() async {
      await iter.cancel();
      await host.shutdown();
    });

    expect(
      await iter.moveNext().timeout(const Duration(seconds: 5)),
      isTrue,
      reason: 'frames stream closed before ready',
    );
    expect(iter.current, isA<ReadyFrame>());
    final ready = iter.current as ReadyFrame;
    expect(ready.platform, 'echo_fixture');
    expect(ready.capabilities, containsAll(<String>['exec', 'cancel']));
    expect(ready.protocolVersion, 1);
  });

  test('exec round-trips through stdout + done(ok)', () async {
    final host = await spawnEcho();
    final iter = StreamIterator(host.frames);
    addTearDown(() async {
      await iter.cancel();
      await host.shutdown();
    });

    await iter.moveNext().timeout(const Duration(seconds: 5));
    expect(iter.current, isA<ReadyFrame>());

    host.send(const ExecFrame(id: 'r1', code: 'print("hi")'));

    await iter.moveNext().timeout(const Duration(seconds: 5));
    expect(iter.current, isA<StdoutFrame>());
    final stdout = iter.current as StdoutFrame;
    expect(stdout.id, 'r1');
    expect(stdout.text, contains('print("hi")'));

    await iter.moveNext().timeout(const Duration(seconds: 5));
    expect(iter.current, isA<DoneFrame>());
    final done = iter.current as DoneFrame;
    expect(done.id, 'r1');
    expect(done.status, DoneStatus.ok);
  });

  test('cancel during a sleeping run produces done(cancelled)', () async {
    final host = await spawnEcho();
    final iter = StreamIterator(host.frames);
    addTearDown(() async {
      await iter.cancel();
      await host.shutdown();
    });

    await iter.moveNext().timeout(const Duration(seconds: 5));
    expect(iter.current, isA<ReadyFrame>());

    host.send(const ExecFrame(id: 'r2', code: '# sleep_ms=1000\n'));
    // Give the worker a moment to enter its sleep loop.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    host.send(const CancelFrame(id: 'r2'));

    await iter.moveNext().timeout(const Duration(seconds: 5));
    final frame = iter.current;
    expect(frame, isA<DoneFrame>());
    final done = frame as DoneFrame;
    expect(done.id, 'r2');
    expect(done.status, DoneStatus.cancelled);
  });

  test('shutdown closes stdin and the process exits cleanly', () async {
    final host = await spawnEcho();
    final exitCode = await host.shutdown();
    expect(exitCode, 0);
  });

  test('non-utf8-safe payloads round-trip through stdin', () async {
    // Dutch students type ë and é; verifying the stdin path doesn't mangle
    // them is the whole reason for forcing utf-8 in HostProcess.
    final host = await spawnEcho();
    final iter = StreamIterator(host.frames);
    addTearDown(() async {
      await iter.cancel();
      await host.shutdown();
    });

    await iter.moveNext().timeout(const Duration(seconds: 5));
    expect(iter.current, isA<ReadyFrame>());

    host.send(const ExecFrame(id: 'utf8', code: 'print("ë é")'));

    await iter.moveNext().timeout(const Duration(seconds: 5));
    expect(iter.current, isA<StdoutFrame>());
    final stdout = iter.current as StdoutFrame;
    expect(stdout.text, contains('ë é'));
  });
}
