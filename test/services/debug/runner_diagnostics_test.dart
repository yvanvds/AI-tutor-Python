// #74 — the runner section a bug report always carries.
//
// The case these tests care about most is the runner being *completely*
// unavailable: no interpreter, no host process, nothing to ask. That is the
// exact situation a student reports, so it must produce a full section rather
// than an exception or a blank.

import 'package:ai_tutor_python/services/debug/runner_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:py_runner/py_runner.dart';

/// A locator that fails the way the real one does when nothing is installed.
class _MissingLocator implements PyHostLocator {
  @override
  Future<PyHostPaths> resolve() async => throw const PyRunnerNotInstalled(
    r'Bundled Python interpreter not found at: C:\Users\jane.doe\app\python'
    r'\python.exe',
  );
}

class _WorkingLocator implements PyHostLocator {
  @override
  Future<PyHostPaths> resolve() async => const PyHostPaths(
    pythonExecutable: r'C:\Users\jane.doe\repo\build\python_bundle\python.exe',
    hostScript: r'C:\Users\jane.doe\repo\packages\py_runner\python\host.py',
    source: PyHostSource.devCheckout,
  );
}

/// Not a [PyRunner] at all: stands for the runner itself being broken, which
/// must still produce a section instead of taking the report down with it.
class _HostileRunner implements PyRunner {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('runner is gone');
}

void main() {
  group('RunnerDiagnostics.collect', () {
    test('reports the resolution failure when nothing is installed', () async {
      final d = await RunnerDiagnostics.collect(
        PyRunner(locator: _MissingLocator()),
      );

      expect(d.status, 'stopped');
      expect(d.pythonExecutable, isNull);
      expect(d.resolutionError, contains('PyRunnerNotInstalled'));

      final md = d.toMarkdown();
      expect(md, contains('Python runner state'));
      expect(md, contains('resolution error:'));
      expect(md, contains('python.exe'));
      expect(md, contains('(no host has started this session)'));
      expect(md, contains('(no run has finished this session)'));
      // …and no host was ever spawned to get any of this.
      expect(md, isNot(contains('jane.doe')));
    });

    test('names the locator branch that produced the paths', () async {
      final d = await RunnerDiagnostics.collect(
        PyRunner(locator: _WorkingLocator()),
      );

      expect(d.source, contains('dev checkout'));
      expect(d.resolutionError, isNull);
      expect(d.toMarkdown(), contains('locator branch:'));
      expect(d.toMarkdown(), contains('build/python_bundle'));
    });

    test('a runner that throws on every read still yields a section', () async {
      final d = await RunnerDiagnostics.collect(_HostileRunner());

      expect(d.collectionError, contains('runner is gone'));
      expect(d.toMarkdown(), contains('diagnostics unavailable'));
      expect(d.toMarkdown(), contains('Python runner state'));
    });
  });

  group('redactUserPaths', () {
    test('strips the account name from a Windows profile path', () {
      expect(
        redactUserPaths(r'C:\Users\jane.doe\app\python\python.exe'),
        r'C:\Users\<user>\app\python\python.exe',
      );
    });

    test('handles forward slashes and an account name with a space', () {
      expect(
        redactUserPaths('C:/Users/Jane Doe/app/host.py'),
        'C:/Users/<user>/app/host.py',
      );
    });

    test('strips posix home directories too', () {
      expect(redactUserPaths('/home/jane/app'), '/home/<user>/app');
      expect(redactUserPaths('/Users/jane/app'), '/Users/<user>/app');
    });

    test('redacts every occurrence, on every line', () {
      final text = redactUserPaths(
        'python: C:\\Users\\jane.doe\\python.exe\n'
        'host:   C:\\Users\\jane.doe\\host.py',
      );
      expect(text, isNot(contains('jane.doe')));
      expect('<user>'.allMatches(text).length, 2);
    });

    test('falls back to the profile directory when it is not under Users', () {
      expect(
        redactUserPaths(
          r'D:\profiles\jane\bundle\python.exe',
          homeDirectory: r'D:\profiles\jane',
        ),
        r'<user-profile>\bundle\python.exe',
      );
    });

    test('leaves ordinary text alone', () {
      expect(
        redactUserPaths('the run button did nothing'),
        'the run button did nothing',
      );
    });
  });
}
