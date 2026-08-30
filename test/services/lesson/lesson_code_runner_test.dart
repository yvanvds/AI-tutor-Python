// Issue #13 — PyLessonCodeRunner must never let a lesson hang or throw:
// a host that cannot start becomes an error result the page can show.
//
// Real Python execution needs the bundled host next to the installed exe,
// which no test runner has; the happy path is covered by the widget test
// over a scripted runner.
//
// `PyRunner.start()` also raises the spawn failure as an unobserved
// completer error in the calling zone (#33). The tests below run inside
// `runZonedGuarded` so that stray error is captured — and asserted on —
// instead of failing the test that is checking the runner's own result.

import 'dart:async';

import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:py_runner/py_runner.dart';

class _MockPyRunner extends Mock implements PyRunner {}

class _MissingHostLocator implements PyHostLocator {
  @override
  Future<PyHostPaths> resolve() async {
    throw StateError('no python host here');
  }
}

/// Runs [body] in a zone that collects the stray py_runner error (#33).
Future<T> _guarded<T>(Future<T> Function() body) async {
  final stray = <Object>[];
  final done = Completer<T>();
  runZonedGuarded(
    () => body().then(done.complete, onError: done.completeError),
    (e, _) => stray.add(e),
  );
  final result = await done.future;
  await Future<void>.delayed(Duration.zero);
  expect(stray, isNotEmpty, reason: 'expected the #33 stray error');
  for (final e in stray) {
    expect('$e', contains('no python host here'));
  }
  return result;
}

void main() {
  test(
    'a host that fails to start yields an error result, not a throw',
    () async {
      final runner = PyLessonCodeRunner(
        pyRunner: PyRunner(locator: _MissingHostLocator()),
      );

      final result = await _guarded(() => runner.run('print(1)'));

      expect(result.stdout, isEmpty);
      expect(result.hasError, isTrue);
      expect(result.stderr, contains('Python host error'));
      expect(result.stderr, contains('no python host here'));
    },
  );

  test('runs are serialised and each gets its own result', () async {
    final runner = PyLessonCodeRunner(
      pyRunner: PyRunner(locator: _MissingHostLocator()),
    );

    final results = await _guarded(
      () => Future.wait([runner.run('print(1)'), runner.run('print(2)')]),
    );

    expect(results, hasLength(2));
    for (final r in results) {
      expect(r.hasError, isTrue);
    }
  });

  test('a host that is gone when the run is sent yields an error result (#7)',
      () async {
    final pyRunner = _MockPyRunner();
    when(() => pyRunner.start()).thenAnswer((_) async {});
    when(
      () => pyRunner.run(
        any(),
        cwd: any(named: 'cwd'),
        timeout: any(named: 'timeout'),
      ),
    ).thenThrow(StateError('PyRunner is not ready (status: crashed)'));

    final result = await PyLessonCodeRunner(pyRunner: pyRunner).run('print(1)');

    expect(result.hasError, isTrue);
    expect(result.stderr, contains('Python host error'));
    expect(result.stderr, contains('not ready'));
  });

  test('LessonRunResult serialises both streams', () {
    const r = LessonRunResult(stdout: 'a', stderr: 'b');
    expect(r.toJson(), {'stdout': 'a', 'stderr': 'b'});
    expect(const LessonRunResult().hasError, isFalse);
  });
}
