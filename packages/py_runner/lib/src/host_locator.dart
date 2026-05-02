import 'dart:async';

/// Resolves where the bundled `python.exe` and `host.py` live on disk.
///
/// Step 4 ships only [ExplicitPyHostLocator] — callers hand it the two paths
/// directly. Step 6 will add an installer-aware locator that derives the
/// paths from `Platform.resolvedExecutable`, plus dev-mode env-var overrides.
abstract class PyHostLocator {
  const PyHostLocator();

  Future<PyHostPaths> resolve();
}

/// Bundle of paths returned by [PyHostLocator.resolve].
class PyHostPaths {
  const PyHostPaths({
    required this.pythonExecutable,
    required this.hostScript,
  });

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
  Future<PyHostPaths> resolve() async => PyHostPaths(
        pythonExecutable: pythonExecutable,
        hostScript: hostScript,
      );
}
