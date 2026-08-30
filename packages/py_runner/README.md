# py_runner

Dart side of the long-lived Python host that drives the AI tutor's Output
panel. Owns one `python.exe` process per app session, talks to it over
newline-delimited UTF-8 JSON frames on stdin/stdout, and exposes a streaming
`PyRunner` / `RunHandle` API.

The full design — wire protocol, package layout, multi-step rollout — lives in
[`PYTHON_IMPLEMENTATION.md`](../../PYTHON_IMPLEMENTATION.md) at the repo root.

This step (3) ships only the path-package skeleton and the `Frame` codec used
by both ends of the pipe. Process spawning, the `PyRunner` class, and the
`RunHandle` type land in step 4.

## Bundled packages (issue #5)

The interpreter shipped by the installer (`tooling/python/build_bundle.ps1`,
pinned in `tooling/python/manifest.toml`) carries `numpy`, `pandas`,
`matplotlib` and `requests`, plus the stdlib `tkinter` / `turtle` backed by the
Tcl/Tk that python-build-standalone ships. Students never `pip install`.

What "supported" means on the student machine:

- `numpy`, `pandas`: import and use as normal.
- `matplotlib`: the default backend is `TkAgg`, so `plt.show()` opens a native
  window owned by `python.exe` (not embedded in the Flutter window, and not
  z-ordered with it). `plt.savefig(...)` renders headlessly through `Agg` and
  works without any window.
- `turtle`: draws in a native Tk window owned by `python.exe`, same caveat as
  `plt.show()`. The run stays active until the window closes or the student
  presses Stop.

`build_bundle.ps1` fails the build unless `tooling/python/verify_bundle.py`
passes inside the bundle (imports, Tcl/Tk start, Agg render). The same promise
is checked through the real `host.py` path by
`test/bundled_packages_test.dart`, gated on `PY_RUNNER_E2E_PYTHON`:

```powershell
$env:PY_RUNNER_E2E_PYTHON = "D:\path\to\build\python_bundle\python\python.exe"
dart test test/bundled_packages_test.dart
```
