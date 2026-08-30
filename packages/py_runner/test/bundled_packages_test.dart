@TestOn('vm')
library;

import 'dart:io';

import 'package:py_runner/py_runner.dart';
import 'package:test/test.dart';

/// Proves the packages promised by issue #5 (numpy, pandas, matplotlib,
/// turtle) are usable *through the py_runner path* — i.e. from a worker
/// subprocess spawned by host.py with `-s -X utf8 -u` and
/// `PYTHONNOUSERSITE=1`, stdout redirected into frames — not merely from
/// `python.exe -c`.
///
/// Gated on `PY_RUNNER_E2E_PYTHON` pointing at the bundled interpreter
/// (`build/python_bundle/python/python.exe` after running
/// `tooling/python/build_bundle.ps1`), same as the e2e group in
/// `py_runner_test.dart`.
///
/// "Supported" here means:
///   * numpy / pandas: import and basic use.
///   * matplotlib: `Agg` rendering to a file works with no window (headless);
///     `plt.show()` uses the bundled Tk (TkAgg) and opens a native window
///     owned by python.exe, not embedded in the Flutter window.
///   * turtle: draws in a native Tk window owned by python.exe. The test
///     opens one, draws, reads the turtle position and closes it again.
void main() {
  final e2ePython = Platform.environment['PY_RUNNER_E2E_PYTHON'];
  final skipReason = (e2ePython == null || e2ePython.isEmpty)
      ? 'Set PY_RUNNER_E2E_PYTHON=<path-to-bundled-python.exe> to enable.'
      : null;

  final sep = Platform.pathSeparator;
  final realHostScript = '${Directory.current.path}${sep}python${sep}host.py';

  Future<({RunResult result, String stdout, String stderr})> runOnHost(
    String code,
  ) async {
    final runner = PyRunner(
      locator: ExplicitPyHostLocator(
        pythonExecutable: e2ePython!,
        hostScript: realHostScript,
      ),
    );
    addTearDown(runner.shutdown);
    await runner.start().timeout(const Duration(seconds: 30));

    final handle = runner.run(code);
    final out = StringBuffer();
    final err = StringBuffer();
    handle.stdout.listen(out.write);
    handle.stderr.listen(err.write);
    // First import of matplotlib builds its font cache; allow for that.
    final result = await handle.done.timeout(const Duration(seconds: 120));
    return (result: result, stdout: out.toString(), stderr: err.toString());
  }

  group('bundled packages through the real host', () {
    test('numpy, pandas, matplotlib and turtle all import', () async {
      final r = await runOnHost('''
import numpy, pandas, matplotlib, turtle, tkinter
print("numpy", numpy.__version__)
print("pandas", pandas.__version__)
print("matplotlib", matplotlib.__version__)
print("tk", tkinter.TkVersion)
print("ALL_IMPORTS_OK")
''');
      expect(r.result.status, RunStatus.ok, reason: r.stderr);
      expect(r.result.exception, isNull);
      expect(r.stdout, contains('ALL_IMPORTS_OK'));
      expect(r.stdout, contains('numpy 2.'));
      expect(r.stdout, contains('pandas 2.'));
      expect(r.stdout, contains('matplotlib 3.'));
    });

    test('numpy + pandas compute inside the worker', () async {
      final r = await runOnHost('''
import numpy as np
import pandas as pd
df = pd.DataFrame({"x": np.arange(4)})
df["y"] = df["x"] ** 2
print(int(df["y"].sum()))
''');
      expect(r.result.status, RunStatus.ok, reason: r.stderr);
      expect(r.stdout.trim(), '14');
    });

    test('matplotlib renders a PNG headlessly via Agg', () async {
      final tmp = Directory.systemTemp.createTempSync('py_runner_mpl_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final target = '${tmp.path}${sep}plot.png';
      final escaped = target.replaceAll(r'\', r'\\');

      final r = await runOnHost('''
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
fig, ax = plt.subplots()
ax.plot([0, 1, 2], [0, 1, 4])
fig.savefig("$escaped")
print("SAVED")
''');
      expect(r.result.status, RunStatus.ok, reason: r.stderr);
      expect(r.stdout, contains('SAVED'));
      final png = File(target);
      expect(png.existsSync(), isTrue);
      final bytes = png.readAsBytesSync();
      expect(bytes.length, greaterThan(0));
      // PNG signature.
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });

    test('matplotlib default backend is the bundled TkAgg', () async {
      final r = await runOnHost('''
import matplotlib
import matplotlib.pyplot as plt
print(matplotlib.get_backend().lower())
''');
      expect(r.result.status, RunStatus.ok, reason: r.stderr);
      expect(r.stdout.trim(), 'tkagg');
    });

    test('turtle draws in a Tk window and closes cleanly', () async {
      final r = await runOnHost('''
import turtle
t = turtle.Turtle()
t.speed(0)
t.forward(50)
t.left(90)
t.forward(25)
x, y = t.pos()
turtle.bye()
print(round(x), round(y))
''');
      expect(r.result.status, RunStatus.ok, reason: r.stderr);
      expect(r.stdout.trim(), '50 25');
    });
  }, skip: skipReason);
}
