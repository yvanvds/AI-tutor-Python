// Issue #33 — a start() whose locator (or spawn) fails must surface the
// error only to its callers, not additionally as an unhandled async error
// in the calling zone via the orphaned `_startCompleter`.
//
// No python is needed: the locator throws before anything is spawned.

import 'dart:async';

import 'package:py_runner/py_runner.dart';
import 'package:test/test.dart';

class _ThrowingLocator implements PyHostLocator {
  @override
  Future<PyHostPaths> resolve() async {
    throw StateError('no python host here');
  }
}

/// Runs [body] in a zone that records uncaught async errors instead of
/// failing the test outright, so we can assert there are none.
Future<List<Object>> _strayErrorsOf(Future<void> Function() body) async {
  final stray = <Object>[];
  final done = Completer<void>();
  runZonedGuarded(
    () => body().then(done.complete, onError: done.completeError),
    (e, _) => stray.add(e),
  );
  await done.future;
  // Give an orphaned completer's error a chance to reach the zone handler.
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  return stray;
}

void main() {
  test('start() spawn failure rethrows to the caller only (#33)', () async {
    final runner = PyRunner(locator: _ThrowingLocator());

    final stray = await _strayErrorsOf(() async {
      await expectLater(
        runner.start(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          'no python host here',
        )),
      );
    });

    expect(stray, isEmpty,
        reason: 'the start completer must not leak an unobserved error');
    expect(runner.status, PyRunnerStatus.crashed);
  });

  test('concurrent start() callers all see the failure (#33)', () async {
    final runner = PyRunner(locator: _ThrowingLocator());

    final stray = await _strayErrorsOf(() async {
      final first = runner.start();
      final second = runner.start();
      await expectLater(first, throwsStateError);
      await expectLater(second, throwsStateError);
    });

    expect(stray, isEmpty);
  });

  test('start() can be retried after a failure', () async {
    var calls = 0;
    final runner = PyRunner(
      locator: _CountingLocator(() {
        calls++;
        throw StateError('attempt $calls');
      }),
    );

    final stray = await _strayErrorsOf(() async {
      await expectLater(runner.start(), throwsStateError);
      await expectLater(runner.start(), throwsStateError);
    });

    expect(calls, 2);
    expect(stray, isEmpty);
  });

  test('shutdown() after a failed start() ends in stopped status', () async {
    final runner = PyRunner(locator: _ThrowingLocator());

    final stray = await _strayErrorsOf(() async {
      await expectLater(runner.start(), throwsStateError);
      await runner.shutdown();
    });

    expect(stray, isEmpty);
    expect(runner.status, PyRunnerStatus.stopped);
  });
}

class _CountingLocator implements PyHostLocator {
  _CountingLocator(this._onResolve);

  final Never Function() _onResolve;

  @override
  Future<PyHostPaths> resolve() async => _onResolve();
}
