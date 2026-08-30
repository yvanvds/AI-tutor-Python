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
/// Throws [PyRunnerNotInstalled] if neither override is active and the expected
/// files are absent.
///
/// Paths are always returned as plain strings and passed to [Process.start] as
/// an argument list — they are never shell-joined, so spaces in `{appDir}` are
/// handled correctly.
class InstallerPyHostLocator extends PyHostLocator {
  const InstallerPyHostLocator({this._appDir, this._environment});

  /// Override for the application directory. Defaults to the directory
  /// containing [Platform.resolvedExecutable]. Exposed for unit testing.
  final String? _appDir;

  /// Override for the process environment. Defaults to [Platform.environment].
  /// Exposed for unit testing so that dev-override behaviour can be verified
  /// without modifying global state.
  final Map<String, String>? _environment;

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

    if (!File(python).existsSync()) {
      throw PyRunnerNotInstalled(
        'Bundled Python interpreter not found at: $python\n'
        'Re-run the installer, or set PY_RUNNER_PYTHON and '
        'PY_RUNNER_HOST_SCRIPT to point at a dev bundle.',
      );
    }
    if (!File(host).existsSync()) {
      throw PyRunnerNotInstalled(
        'host.py not found at: $host\n'
        'Re-run the installer, or set PY_RUNNER_HOST_SCRIPT.',
      );
    }

    return PyHostPaths(pythonExecutable: python, hostScript: host);
  }
}
