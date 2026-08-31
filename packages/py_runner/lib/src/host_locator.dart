import 'dart:async';
import 'dart:io';

/// Resolves where the bundled `python.exe` and `host.py` live on disk.
abstract class PyHostLocator {
  const PyHostLocator();

  Future<PyHostPaths> resolve();
}

/// Thrown by [InstallerPyHostLocator.resolve] when the bundled Python files
/// are not found at their expected installed locations and no dev-mode override
/// is active.
class PyRunnerNotInstalled implements Exception {
  const PyRunnerNotInstalled(this.message);

  final String message;

  @override
  String toString() => 'PyRunnerNotInstalled: $message';
}

/// Bundle of paths returned by [PyHostLocator.resolve].
class PyHostPaths {
  const PyHostPaths({required this.pythonExecutable, required this.hostScript});

  /// Absolute path to `python.exe` (or the platform equivalent).
  final String pythonExecutable;

  /// Absolute path to `host.py`.
  final String hostScript;
}

/// Step 4 placeholder: returns whatever paths the caller passed in.
///
/// Used by tests (pointed at `test/fixtures/echo_host.py`) and by the env-gated
/// end-to-end test that drives the real bundled python.
class ExplicitPyHostLocator extends PyHostLocator {
  const ExplicitPyHostLocator({
    required this.pythonExecutable,
    required this.hostScript,
  });

  final String pythonExecutable;
  final String hostScript;

  @override
  Future<PyHostPaths> resolve() async =>
      PyHostPaths(pythonExecutable: pythonExecutable, hostScript: hostScript);
}

/// Where a checked-out repository keeps `host.py`, relative to its root.
///
/// Doubles as the marker that identifies a directory *as* the repo root during
/// the dev-mode walk-up: it is committed, so every clone has it.
const List<String> _repoHostScript = [
  'packages',
  'py_runner',
  'python',
  'host.py',
];

/// Where `tooling/python/build_bundle.ps1` writes the dev bundle, relative to
/// the repository root.
const List<String> _repoBundlePython = [
  'build',
  'python_bundle',
  'python',
  'python.exe',
];

/// How many ancestors of the app directory to inspect when looking for the
/// repository root. A Windows debug build sits at
/// `{repoRoot}/build/windows/x64/runner/Debug`, i.e. five levels down; the
/// extra headroom covers other debug layouts without letting the search escape
/// into unrelated parts of the filesystem.
const int _repoRootSearchDepth = 8;

/// Result of looking for a source checkout (and its dev bundle) above the
/// running executable.
class _DevBundleProbe {
  _DevBundleProbe({
    required this.repoRoot,
    required this.hostScript,
    required this.pythonExecutable,
    required this.pythonExists,
  });

  final String repoRoot;
  final String hostScript;
  final String pythonExecutable;

  /// Whether `build_bundle.ps1` has actually produced the interpreter yet.
  final bool pythonExists;

  /// Walks up from [appDir] looking for a directory that holds
  /// [_repoHostScript]. Returns `null` when no checkout is found — which is the
  /// normal case for an installed app, and the case where the guess is simply
  /// wrong; callers then fall through to the ordinary "not installed" error.
  static _DevBundleProbe? locate(String appDir) {
    final sep = Platform.pathSeparator;
    var dir = Directory(appDir).absolute;

    for (var i = 0; i <= _repoRootSearchDepth; i++) {
      final root = dir.path;
      final host = '$root$sep${_repoHostScript.join(sep)}';
      if (File(host).existsSync()) {
        final python = '$root$sep${_repoBundlePython.join(sep)}';
        return _DevBundleProbe(
          repoRoot: root,
          hostScript: host,
          pythonExecutable: python,
          pythonExists: File(python).existsSync(),
        );
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break; // reached the filesystem root
      dir = parent;
    }
    return null;
  }
}

/// Production locator: derives paths from [Platform.resolvedExecutable] and
/// honours dev-mode env-var overrides.
///
/// ### Production layout (post-installer)
/// ```
/// {appDir}/python/python.exe
/// {appDir}/py_runner/host.py
/// ```
///
/// ### Dev-mode overrides
/// Set both `PY_RUNNER_PYTHON` and `PY_RUNNER_HOST_SCRIPT` to bypass the
/// filesystem check and point at any interpreter and host script — e.g. the
/// bundle produced by `tooling/python/build_bundle.ps1` during
/// `flutter run -d windows`.  Both vars must be non-empty; if only one is set
/// the locator falls through to the installer layout (avoids a surprising
/// half-override).
///
/// ### Dev-mode source-checkout fallback
/// When `devMode` is true (the app passes Flutter's `kDebugMode`; this package
/// is pure Dart and cannot read it itself) and the installer layout is absent,
/// the locator walks up from the app directory looking for a source checkout —
/// identified by `packages/py_runner/python/host.py` — and uses the bundle at
/// `{repoRoot}/build/python_bundle/python/python.exe` if `build_bundle.ps1` has
/// produced it. This makes `flutter run -d windows` work with no environment
/// variables set.
///
/// `devMode` defaults to **false**, so a release build never picks up a stray
/// bundle: its behaviour is byte-for-byte what it was before this fallback
/// existed.
///
/// Throws [PyRunnerNotInstalled] if no override is active and the expected
/// files are absent. In dev mode the message names the conventional bundle
/// path, says whether a bundle is there, and names the build script and the two
/// environment variables.
///
/// Paths are always returned as plain strings and passed to [Process.start] as
/// an argument list — they are never shell-joined, so spaces in `{appDir}` are
/// handled correctly.
class InstallerPyHostLocator extends PyHostLocator {
  const InstallerPyHostLocator({
    this._appDir,
    this._environment,
    this._devMode = false,
  });

  /// Override for the application directory. Defaults to the directory
  /// containing [Platform.resolvedExecutable]. Exposed for unit testing.
  final String? _appDir;

  /// Override for the process environment. Defaults to [Platform.environment].
  /// Exposed for unit testing so that dev-override behaviour can be verified
  /// without modifying global state.
  final Map<String, String>? _environment;

  /// Whether this is a debug/development build. Callers in the Flutter app pass
  /// `kDebugMode`; `py_runner` has no Flutter dependency, so it cannot read that
  /// symbol itself. Enables the source-checkout fallback and the longer,
  /// self-answering error message.
  final bool _devMode;

  @override
  Future<PyHostPaths> resolve() async {
    final env = _environment ?? Platform.environment;

    final envPython = env['PY_RUNNER_PYTHON'];
    final envHost = env['PY_RUNNER_HOST_SCRIPT'];
    if (envPython != null &&
        envPython.isNotEmpty &&
        envHost != null &&
        envHost.isNotEmpty) {
      return PyHostPaths(pythonExecutable: envPython, hostScript: envHost);
    }

    final dir = _appDir ?? File(Platform.resolvedExecutable).parent.path;
    final sep = Platform.pathSeparator;
    final python = '$dir${sep}python${sep}python.exe';
    final host = '$dir${sep}py_runner${sep}host.py';

    final pythonExists = File(python).existsSync();
    final hostExists = File(host).existsSync();
    if (pythonExists && hostExists) {
      return PyHostPaths(pythonExecutable: python, hostScript: host);
    }

    if (_devMode) {
      final probe = _DevBundleProbe.locate(dir);
      if (probe != null && probe.pythonExists) {
        return PyHostPaths(
          pythonExecutable: probe.pythonExecutable,
          hostScript: probe.hostScript,
        );
      }
      throw PyRunnerNotInstalled(_devMessage(dir, python, probe));
    }

    if (!pythonExists) {
      throw PyRunnerNotInstalled(
        'Bundled Python interpreter not found at: $python\n'
        'Re-run the installer, or set PY_RUNNER_PYTHON and '
        'PY_RUNNER_HOST_SCRIPT to point at a dev bundle.',
      );
    }
    throw PyRunnerNotInstalled(
      'host.py not found at: $host\n'
      'Re-run the installer, or set PY_RUNNER_HOST_SCRIPT.',
    );
  }

  /// The self-answering message for a development build: it names what was
  /// checked, what is missing, and the exact commands that fix it.
  static String _devMessage(
    String appDir,
    String installedPython,
    _DevBundleProbe? probe,
  ) {
    final buffer = StringBuffer()
      ..writeln('No Python environment found (development build).')
      ..writeln()
      ..writeln('Installed layout (used by the installer) — not present:')
      ..writeln('  $installedPython')
      ..writeln();

    if (probe == null) {
      buffer
        ..writeln(
          'No source checkout was found above the app directory, so the '
          'conventional dev bundle could not be checked. Searched upward from:',
        )
        ..writeln('  $appDir')
        ..writeln(
          '  (looking for ${_repoHostScript.join('/')} in each parent '
          'directory)',
        );
    } else {
      buffer
        ..writeln('Source checkout found at:')
        ..writeln('  ${probe.repoRoot}')
        ..writeln('Dev bundle interpreter — NOT present:')
        ..writeln('  ${probe.pythonExecutable}')
        ..writeln('Host script — present:')
        ..writeln('  ${probe.hostScript}');
    }

    buffer
      ..writeln()
      ..writeln('To fix, either:')
      ..writeln(
        '  1. Build the dev bundle, then restart the app:\n'
        '     pwsh tooling/python/build_bundle.ps1',
      )
      ..writeln(
        '  2. Or point at any interpreter by setting BOTH environment '
        'variables\n'
        '     before launching (setting only one is ignored):\n'
        '     PY_RUNNER_PYTHON       = <path to python.exe>\n'
        '     PY_RUNNER_HOST_SCRIPT  = <path to host.py>',
      );

    return buffer.toString().trimRight();
  }
}
