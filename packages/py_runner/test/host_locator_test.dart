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

  group('InstallerPyHostLocator — dev-mode source-checkout fallback', () {
    late Directory tempDir;
    late String repoRoot;
    late String debugAppDir;
    final sep = Platform.pathSeparator;

    Future<void> createFile(String path) async {
      final f = File(path);
      await f.parent.create(recursive: true);
      await f.writeAsString('');
    }

    String repoHostScript() =>
        '$repoRoot${sep}packages${sep}py_runner${sep}python${sep}host.py';

    String repoBundlePython() =>
        '$repoRoot${sep}build${sep}python_bundle${sep}python${sep}python.exe';

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('py_runner_devmode_');
      repoRoot = '${tempDir.path}${sep}checkout';
      // Mirrors the real `flutter run -d windows` layout: the debug executable
      // lives five directories below the repository root.
      debugAppDir =
          '$repoRoot${sep}build${sep}windows${sep}x64${sep}runner${sep}Debug';
      await Directory(debugAppDir).create(recursive: true);
      // host.py is committed, so a checkout always has it.
      await createFile(repoHostScript());
    });

    tearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('resolves the conventional bundle when it has been built', () async {
      await createFile(repoBundlePython());

      final locator = InstallerPyHostLocator(
        appDir: debugAppDir,
        environment: const {},
        devMode: true,
      );
      final paths = await locator.resolve();
      expect(paths.pythonExecutable, repoBundlePython());
      expect(paths.hostScript, repoHostScript());
    });

    test('env-var overrides still win over the dev fallback', () async {
      await createFile(repoBundlePython());

      final locator = InstallerPyHostLocator(
        appDir: debugAppDir,
        environment: const {
          'PY_RUNNER_PYTHON': r'C:\explicit\python.exe',
          'PY_RUNNER_HOST_SCRIPT': r'C:\explicit\host.py',
        },
        devMode: true,
      );
      final paths = await locator.resolve();
      expect(paths.pythonExecutable, r'C:\explicit\python.exe');
      expect(paths.hostScript, r'C:\explicit\host.py');
    });

    test(
      'an installed layout next to the exe wins over the dev bundle',
      () async {
        await createFile(repoBundlePython());
        await createFile('$debugAppDir${sep}python${sep}python.exe');
        await createFile('$debugAppDir${sep}py_runner${sep}host.py');

        final locator = InstallerPyHostLocator(
          appDir: debugAppDir,
          environment: const {},
          devMode: true,
        );
        final paths = await locator.resolve();
        expect(paths.pythonExecutable, startsWith(debugAppDir));
        expect(paths.hostScript, startsWith(debugAppDir));
      },
    );

    test('error names the conventional bundle path, the build script and both '
        'env vars when the bundle has not been built', () async {
      final locator = InstallerPyHostLocator(
        appDir: debugAppDir,
        environment: const {},
        devMode: true,
      );
      await expectLater(
        locator.resolve(),
        throwsA(
          isA<PyRunnerNotInstalled>().having(
            (e) => e.message,
            'message',
            allOf(
              contains(repoBundlePython()),
              contains('NOT present'),
              contains('build_bundle.ps1'),
              contains('PY_RUNNER_PYTHON'),
              contains('PY_RUNNER_HOST_SCRIPT'),
            ),
          ),
        ),
      );
    });

    test(
      'error says so when no source checkout is found above the app dir',
      () async {
        final orphan = '${tempDir.path}${sep}orphan';
        await Directory(orphan).create(recursive: true);

        final locator = InstallerPyHostLocator(
          appDir: orphan,
          environment: const {},
          devMode: true,
        );
        await expectLater(
          locator.resolve(),
          throwsA(
            isA<PyRunnerNotInstalled>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('No source checkout was found'),
                contains(orphan),
                contains('build_bundle.ps1'),
                contains('PY_RUNNER_PYTHON'),
                contains('PY_RUNNER_HOST_SCRIPT'),
              ),
            ),
          ),
        );
      },
    );

    test(
      'release builds stay hermetic: a present dev bundle is ignored',
      () async {
        await createFile(repoBundlePython());

        // devMode defaults to false — exactly what a release build constructs.
        final locator = InstallerPyHostLocator(
          appDir: debugAppDir,
          environment: const {},
        );
        await expectLater(
          locator.resolve(),
          throwsA(
            isA<PyRunnerNotInstalled>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('Re-run the installer'),
                isNot(contains('python_bundle')),
                isNot(contains('build_bundle.ps1')),
              ),
            ),
          ),
        );
      },
    );

    test('release builds ignore the dev bundle even when host.py is the only '
        'missing installer file', () async {
      await createFile(repoBundlePython());
      await createFile('$debugAppDir${sep}python${sep}python.exe');

      final locator = InstallerPyHostLocator(
        appDir: debugAppDir,
        environment: const {},
      );
      await expectLater(
        locator.resolve(),
        throwsA(
          isA<PyRunnerNotInstalled>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('host.py not found at:'),
              isNot(contains('python_bundle')),
            ),
          ),
        ),
      );
    });
  });
}
