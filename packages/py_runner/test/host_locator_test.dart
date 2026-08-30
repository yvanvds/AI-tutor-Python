@TestOn('vm')
library;

import 'dart:io';

import 'package:py_runner/py_runner.dart';
import 'package:test/test.dart';

void main() {
  group('InstallerPyHostLocator — dev-override', () {
    test('returns env-var paths when both vars are set', () async {
      final locator = InstallerPyHostLocator(
        environment: const {
          'PY_RUNNER_PYTHON': r'C:\bundle\python.exe',
          'PY_RUNNER_HOST_SCRIPT': r'C:\bundle\host.py',
        },
      );
      final paths = await locator.resolve();
      expect(paths.pythonExecutable, r'C:\bundle\python.exe');
      expect(paths.hostScript, r'C:\bundle\host.py');
    });

    test(
      'falls through to installer layout when only PY_RUNNER_PYTHON is set',
      () async {
        final locator = InstallerPyHostLocator(
          appDir: r'C:\does-not-exist',
          environment: const {'PY_RUNNER_PYTHON': r'C:\bundle\python.exe'},
        );
        await expectLater(
          locator.resolve(),
          throwsA(isA<PyRunnerNotInstalled>()),
        );
      },
    );

    test('falls through to installer layout when only PY_RUNNER_HOST_SCRIPT is set', () async {
      final locator = InstallerPyHostLocator(
        appDir: r'C:\does-not-exist',
        environment: const {'PY_RUNNER_HOST_SCRIPT': r'C:\bundle\host.py'},
      );
      await expectLater(
        locator.resolve(),
        throwsA(isA<PyRunnerNotInstalled>()),
      );
    });

    test('falls through when env vars are empty strings', () async {
      final locator = InstallerPyHostLocator(
        appDir: r'C:\does-not-exist',
        environment: const {
          'PY_RUNNER_PYTHON': '',
          'PY_RUNNER_HOST_SCRIPT': '',
        },
      );
      await expectLater(
        locator.resolve(),
        throwsA(isA<PyRunnerNotInstalled>()),
      );
    });
  });

  group('InstallerPyHostLocator — installer layout', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('py_runner_locator_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    Future<void> createFile(String path) async {
      final f = File(path);
      await f.parent.create(recursive: true);
      await f.writeAsString('');
    }

    test('throws PyRunnerNotInstalled when python.exe is absent', () async {
      final locator = InstallerPyHostLocator(
        appDir: tempDir.path,
        environment: const {},
      );
      await expectLater(
        locator.resolve(),
        throwsA(
          isA<PyRunnerNotInstalled>().having(
            (e) => e.message,
            'message',
            allOf(contains('python.exe'), contains('PY_RUNNER_PYTHON')),
          ),
        ),
      );
    });

    test('throws PyRunnerNotInstalled when host.py is absent', () async {
      final sep = Platform.pathSeparator;
      await createFile('${tempDir.path}${sep}python${sep}python.exe');

      final locator = InstallerPyHostLocator(
        appDir: tempDir.path,
        environment: const {},
      );
      await expectLater(
        locator.resolve(),
        throwsA(
          isA<PyRunnerNotInstalled>().having(
            (e) => e.message,
            'message',
            allOf(contains('host.py'), contains('PY_RUNNER_HOST_SCRIPT')),
          ),
        ),
      );
    });

    test('resolves correct paths when both files exist', () async {
      final sep = Platform.pathSeparator;
      await createFile('${tempDir.path}${sep}python${sep}python.exe');
      await createFile('${tempDir.path}${sep}py_runner${sep}host.py');

      final locator = InstallerPyHostLocator(
        appDir: tempDir.path,
        environment: const {},
      );
      final paths = await locator.resolve();
      expect(paths.pythonExecutable, endsWith('python.exe'));
      expect(paths.hostScript, endsWith('host.py'));
      expect(paths.pythonExecutable, startsWith(tempDir.path));
      expect(paths.hostScript, startsWith(tempDir.path));
    });

    test('handles appDir containing spaces', () async {
      // Build a sub-directory whose name contains a space.
      final spaceDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}with spaces',
      );
      await spaceDir.create();

      final sep = Platform.pathSeparator;
      await createFile('${spaceDir.path}${sep}python${sep}python.exe');
      await createFile('${spaceDir.path}${sep}py_runner${sep}host.py');

      final locator = InstallerPyHostLocator(
        appDir: spaceDir.path,
        environment: const {},
      );
      final paths = await locator.resolve();
      expect(paths.pythonExecutable, contains(' '));
      expect(paths.hostScript, contains(' '));
    });
  });
}
