<!-- META
last_updated_at: 2026-05-02
status: planning — no code changes have landed
-->

# PYTHON_IMPLEMENTATION

Replacing the [`py_engine_desktop`](https://pub.dev/packages/py_engine_desktop) Flutter plugin currently driving [features/dashboard/output.dart](lib/features/dashboard/output.dart) with a custom long-lived Python host process backed by an Astral [python-build-standalone](https://github.com/astral-sh/python-build-standalone) interpreter bundled into the Inno Setup installer.

## 1. Goal & non-goals

### Goal

Give students a Python runtime that has a real `tkinter` (so `turtle` and `matplotlib`'s `TkAgg` backend work), supports `input()`, doesn't `pip install` on every Output-widget mount, and that we — not a one-star hobby plugin — control. Replace `py_engine_desktop` end-to-end while keeping every existing dashboard behaviour.

### Non-goals

No new student-visible features in the replacement milestone (steps 1–9 below). No sandboxing, no figure embedding, no AST analysis, no multi-run, no macOS/Linux. Those are listed in §6 as future expansions the wire protocol and `PyRunner` API must accommodate, not as work to do now. The `safeCosmos`/polling/crash-recovery code is untouched.

## 2. Architecture overview

### 2.1 Host-process model

One long-lived `python.exe` per app session, launched on first need and reused for every Run-button press. Communication is newline-delimited UTF-8 JSON frames over the host's stdin (Flutter→host) and stdout (host→Flutter). The host's `stderr` carries only host-internal log lines (never student program output — student output is wrapped into `stdout`/`stderr` *frames*). One frame = one line. Inside frame text fields, embedded newlines are preserved as `\n` per JSON encoding.

Every frame carries a run `id` (UUID v4 minted in Dart per `PyRunner.run` call). v1 host serves one run at a time and rejects an `exec` while another is active *unless* the active run's `id` matches a pending cancel — see §2.3. The protocol is multi-run-shaped from day one so adding a second concurrent run later is a host-internal change.

The host runs with `-X utf8 -u`, `PYTHONIOENCODING=utf-8`, and `PYTHONUNBUFFERED=1`. The Dart side decodes stdin/stdout as UTF-8. (Critical for Dutch students typing `ë`, `é`.)

### 2.2 Wire protocol — v1 frames

All frames are JSON objects with a `type` field. Field order is irrelevant; unknown fields are ignored by both sides (forward-compat). Strings are UTF-8.

#### Flutter → host

| `type` | Fields | Purpose |
|---|---|---|
| `exec` | `id: string`, `code: string`, `cwd?: string` | Start a run. `cwd` defaults to a per-run temp dir. |
| `cancel` | `id: string` | Request cancellation of run `id`. Idempotent; no-op if `id` isn't active. |
| `input_response` | `id: string`, `request_id: int`, `value: string` | Fulfill an `input_request`. (v1 host accepts the frame but step 10 is the first step that emits `input_request`.) |

Examples:
```json
{"type":"exec","id":"7f1c…","code":"print('hi')\n"}
{"type":"cancel","id":"7f1c…"}
{"type":"input_response","id":"7f1c…","request_id":1,"value":"Yvan"}
```

#### Host → Flutter

| `type` | Fields | Purpose |
|---|---|---|
| `ready` | `python_version: string`, `platform: string`, `capabilities: string[]` | Sent once on host startup. v1 capabilities: `["exec","cancel"]`. |
| `stdout` | `id: string`, `text: string` | Chunk of student stdout (may not be a full line). |
| `stderr` | `id: string`, `text: string` | Chunk of student stderr. |
| `input_request` | `id: string`, `request_id: int`, `prompt: string` | Student code called `input(prompt)`. v1 host does not emit this; reserved by protocol. |
| `exception` | `id: string`, `exc_type: string`, `message: string`, `traceback: string` | Unhandled exception in student code. Always followed by a `done` with `status:"error"`. |
| `done` | `id: string`, `status: "ok"\|"error"\|"cancelled"`, `duration_ms: int` | Run terminated. After this, the `id` is dead. |
| `host_log` | `level: "info"\|"warn"\|"error"`, `message: string` | Host-internal diagnostic. Not tied to a run. |

Examples:
```json
{"type":"ready","python_version":"3.14.0","platform":"win_amd64","capabilities":["exec","cancel"]}
{"type":"stdout","id":"7f1c…","text":"hi\n"}
{"type":"exception","id":"7f1c…","exc_type":"ZeroDivisionError","message":"division by zero","traceback":"Traceback (most recent call last):\n  File \"<student>\", line 1, in <module>\nZeroDivisionError: division by zero\n"}
{"type":"done","id":"7f1c…","status":"error","duration_ms":34}
```

### 2.3 Cancel semantics (v1)

The host runs the student `exec()` on a worker thread; the main thread keeps reading stdin. On a `cancel` frame matching the active run, the host raises `KeyboardInterrupt` asynchronously in the worker thread via `ctypes.pythonapi.PyThreadState_SetAsyncExc` and waits up to 250 ms; if the worker hasn't yielded, the host kills its *own* process (PyRunner respawns on next `run`). This is the v1 simplification — step 11 replaces the kill-self with a per-run subprocess.

### 2.4 `PyRunner` Dart API

Lives in [`packages/py_runner/lib/py_runner.dart`](packages/py_runner/lib/py_runner.dart). Streaming-handle based; nothing call-and-block.

```dart
/// Long-lived host-process owner. Construct once, register as a
/// get_it lazy singleton, call [start] before the first run.
class PyRunner {
  PyRunner({required PyHostLocator locator});

  /// Spawn the host and await the `ready` frame.
  Future<void> start();

  /// Kill the host. Idempotent.
  Future<void> shutdown();

  /// True once `ready` was received and no shutdown has been issued.
  ValueListenable<PyRunnerStatus> get status;

  /// Start a run. Cancels any currently-active run before starting
  /// the new one (the "replace current run" affordance — students
  /// hit Run again without awaiting). The returned handle is the
  /// only way to observe the run.
  RunHandle run(String code, {String? cwd});
}

enum PyRunnerStatus { stopped, starting, ready, crashed }

/// One Python execution. All streams are single-subscription and
/// close when [done] completes.
class RunHandle {
  String get id;
  Stream<String> get stdout;
  Stream<String> get stderr;
  Stream<InputRequest> get inputRequests; // empty in v1
  Future<RunResult> get done;

  /// Reply to an [InputRequest]. No-op if the run is no longer active.
  void respondToInput(int requestId, String value);

  /// Request cancellation. Resolves when the host emits `done`
  /// (with status `cancelled` if the cancel landed in time).
  Future<void> cancel();
}

class RunResult {
  final RunStatus status;       // ok | error | cancelled
  final Duration duration;
  final PyException? exception; // populated when status == error
}

class InputRequest {
  final int requestId;
  final String prompt;
}
```

`RunHandle` does not pre-buffer streams; if a caller subscribes late, lines emitted before subscription are dropped. The `OutputService` adapter pins subscriptions immediately on `run` to avoid this.

### 2.5 Where it sits relative to existing services

```
controllers.dart  ─►  DataService.output.run(code)  (unchanged call)
                      │
                      ▼
                 OutputService            (lib/services/output, thin adapter)
                      │  delegates to
                      ▼
                 PyRunner                 (registered on DataService alongside OutputService)
                      │  spawns / talks to
                      ▼
                 host.py via python.exe   (packages/py_runner/python/host.py)
```

Callers in `controllers.dart` keep using `DataService.output.run/stop`. They do not learn that `PyRunner` exists. `OutputService` retains its `OutputController.bind(...)` seam — the new `output.dart` widget rebuilds its log view from `OutputService` streams instead of from `py_engine_desktop` streams.

## 3. Package layout

```
packages/py_runner/
├── pubspec.yaml                    # name: py_runner, environment matches root
├── README.md                       # one-screen "what this is"
├── analysis_options.yaml           # inherits root lints
├── lib/
│   ├── py_runner.dart              # public exports only
│   └── src/
│       ├── py_runner.dart          # class PyRunner, status notifier
│       ├── run_handle.dart         # RunHandle, RunResult, RunStatus, InputRequest, PyException
│       ├── frames.dart             # frame dataclasses + encode/decode
│       ├── host_process.dart       # spawn python.exe, line-pump stdin/stdout
│       └── host_locator.dart       # PyHostLocator: resolves bundled python.exe path
├── python/
│   └── host.py                     # the long-lived host script (single file, no deps beyond stdlib)
└── test/
    ├── frames_test.dart            # round-trip every frame type
    ├── host_process_test.dart      # uses fixtures/echo_host.py — no real python required
    ├── py_runner_test.dart         # end-to-end against bundled python (gated on env var)
    └── fixtures/
        └── echo_host.py            # stdlib-only fake host, ships with the test
```

### Bundled-package metadata: single source of truth

`tooling/python/manifest.toml` — read by the build script, by the installer-build wrapper, and (optionally) by `PyRunner.start` for a sanity check at runtime.

```toml
# tooling/python/manifest.toml
[python]
# python-build-standalone release tag and asset.
# CONFIRM the exact tag against https://github.com/astral-sh/python-build-standalone/releases
# before merging — the version below is the planning placeholder.
version       = "3.14.0"
release_tag   = "20260122"
asset         = "cpython-3.14.0+20260122-x86_64-pc-windows-msvc-install_only.tar.gz"
sha256        = "<fill-in-from-release-page>"

[packages]
# Pinned. Pre-installed at build time; never pip-installed at runtime.
numpy      = "2.3.*"
pandas     = "2.3.*"
matplotlib = "3.10.*"
requests   = "2.32.*"
# scikit-learn is in the current py_engine_desktop install list. Verify
# cp314 wheel availability before adding it; otherwise leave it out of v1
# and document for students that scikit-learn is unavailable until the
# bundle moves to a Python that has wheels for it.
```

### Where the host script lives at runtime

Shipped as a regular file via the installer to `{app}\py_runner\host.py`, **not** as a Flutter asset. Reasons: (1) it must be argv-passable to `python.exe`; extracting it from `rootBundle` to a temp file on first run is strictly worse than letting Inno Setup put it on disk; (2) keeping it next to the bundled interpreter makes the install layout self-explanatory; (3) updates ship through the existing installer flow that already handles the rest of the app.

## 4. Installer integration

### 4.1 Build-time pipeline

`tooling/python/build_bundle.ps1` — produces `build/python_bundle/`:

1. Read `tooling/python/manifest.toml`.
2. Download `cpython-…-install_only.tar.gz` from the github release; verify SHA-256 against the manifest. Cache under `tooling/python/.cache/` so re-runs are fast.
3. Extract to `build/python_bundle/` so `build/python_bundle/python/python.exe` exists.
4. `build/python_bundle/python/python.exe -m pip install --no-warn-script-location <every package from manifest>`.
5. (Optional) Pre-compile to `.pyc` with `python -m compileall -q build/python_bundle/python` to cut first-import latency.
6. Write `build/python_bundle/MANIFEST_LOCK.json` — the resolved versions actually installed, for runtime sanity-check.

The script is idempotent and content-addressed via the manifest's tag + sha — re-running with the same manifest is a no-op.

### 4.2 Inno Setup wiring

`flutter_distributor`'s default `make_config.yaml` flow generates an Inno Setup script that doesn't know about our extra files. Two viable shapes:

- **A.** If `flutter_distributor`'s `exe` target supports an `inno_setup_script:` override (verify — see open questions §7), point it at a custom `windows/packaging/exe/installer.iss` template and add:

  ```ini
  [Files]
  Source: "..\..\..\build\python_bundle\python\*"; DestDir: "{app}\python"; \
      Flags: recursesubdirs createallsubdirs ignoreversion
  Source: "..\..\..\packages\py_runner\python\host.py"; DestDir: "{app}\py_runner"; \
      Flags: ignoreversion
  ```

- **B.** If the override isn't supported, drop `flutter_distributor` for the .iss step: keep its `flutter build windows --release` invocation, then run `iscc.exe windows\packaging\exe\installer.iss` ourselves from a `tooling/build_release.ps1` wrapper. The wrapper sequence becomes: `build_bundle.ps1` → `flutter build windows --release` → `iscc.exe …`. `make_config.yaml` is left as documentation only or deleted.

Either way, `tooling/build_release.ps1` is the single command teachers/CI run. Uninstall cleanup is automatic — Inno Setup removes everything under `{app}` on uninstall, including `{app}\python\` and `{app}\py_runner\`.

### 4.3 Pinning

`tooling/python/manifest.toml` is the single source of truth for the Python version and the pre-installed package list. To bump Python or a package, edit that file, re-run `build_bundle.ps1`, ship a new installer. There is no second list to keep in sync.

## 5. Multi-step implementation plan

Each step is independently testable and reviewable. Steps 1–9 land the existing dashboard on the new runner with no behaviour changes. Steps 10–11 add `input()` and timeouts. Later expansions (§6) build on step 11.

### Step 1 — Bundle pipeline (no Flutter changes)

**What.** Add `tooling/python/manifest.toml`, `tooling/python/build_bundle.ps1`, `tooling/python/.gitignore` (excludes `.cache/`). Extend root `.gitignore` for `build/python_bundle/`.

**Definition of done.** Running `pwsh tooling/python/build_bundle.ps1` from a clean checkout produces `build/python_bundle/python/python.exe` and the listed packages. `build/python_bundle/python/python.exe -c "import numpy, pandas, matplotlib, requests, tkinter; print('ok')"` prints `ok`. Re-running the script is a no-op (cache hit). `flutter analyze` clean (no Dart changes). No tests yet.

### Step 2 — Standalone `host.py` with manual smoke tests

**What.** Add `packages/py_runner/python/host.py`. Single-file, stdlib-only, ~200 lines:
- main thread reads stdin line-by-line, decodes JSON frames;
- `exec` frame: spawns a worker thread that compiles + `exec()`s the code with `redirect_stdout`/`redirect_stderr` into queues drained by the main thread into `stdout`/`stderr` frames;
- `cancel` frame: `PyThreadState_SetAsyncExc(KeyboardInterrupt)`, then `os._exit` after 250 ms if still alive;
- on worker exit, emit `done` with `ok` / `error` / `cancelled`;
- emits `ready` on startup.

**Definition of done.** Manual: `Get-Content frames.txt | build\python_bundle\python\python.exe -X utf8 -u packages\py_runner\python\host.py` where `frames.txt` contains an `exec` frame produces matching `ready` → `stdout` → `done` frames. A `cancel` mid-run yields a `cancelled` `done`. `python -m py_compile packages/py_runner/python/host.py` passes. No Dart changes; `flutter analyze` clean.

### Step 3 — `packages/py_runner/` skeleton + framing

**What.** Create the path-package with `pubspec.yaml`, exports, `frames.dart` (encode/decode for every frame type from §2.2), and unit tests covering every frame. No process logic yet.

**Definition of done.** `dart test packages/py_runner` passes. `flutter analyze packages/py_runner` clean. The package builds without a `path:` reference from the root yet.

### Step 4 — `host_process.dart` + `PyRunner` + `RunHandle`

**What.** Implement `host_process.dart` (spawn python.exe with the right args/env; line-pump stdin and stdout; route lines through `frames.dart`), `host_locator.dart` (placeholder: takes an explicit path for now), `py_runner.dart`, `run_handle.dart`. Register `PyRunner` and `RunHandle` exports.

**Definition of done.** `dart test packages/py_runner` passes against `test/fixtures/echo_host.py` (a stdlib-only fake host that echoes a canned `done` per `exec`). An env-gated end-to-end test (`PY_RUNNER_E2E_PYTHON=path\to\python.exe dart test`) drives the real bundled python from step 1, runs `print('hi')`, observes a `stdout` and `done`. `flutter analyze packages/py_runner` clean.

### Step 5 — Installer integration

**What.** Add `windows/packaging/exe/installer.iss` (or extend `make_config.yaml` if the override is supported). Add `tooling/build_release.ps1` that runs `build_bundle.ps1` → `flutter build windows --release` → installer build. Update [distribute_options.yaml](distribute_options.yaml) only if option A from §4.2 turns out to work.

**Definition of done.** `pwsh tooling/build_release.ps1` produces `public/PythonTeacherSetup.exe`. Installing on a clean Windows 11 VM places `C:\Program Files\Python Teacher\python\python.exe` and `C:\Program Files\Python Teacher\py_runner\host.py`. Uninstalling removes both. Installer size is documented (expect ~250 MB; flag if larger). No Dart changes; `flutter analyze` clean.

### Step 6 — Real `host_locator.dart`

**What.** `PyHostLocator.resolve()` returns `<dir of Platform.resolvedExecutable>\python\python.exe` and `<dir>\py_runner\host.py`. Dev-mode override: `PY_RUNNER_PYTHON` and `PY_RUNNER_HOST_SCRIPT` env vars (used during `flutter run -d windows` so we can point at `build/python_bundle/`). Throws `PyRunnerNotInstalled` with a clear message if the files are missing. Handles paths containing spaces by passing argv list, never command string.

**Definition of done.** Unit tests cover dev-override and missing-files paths. With env vars set, `dart packages/py_runner/example/smoke.dart` (a tiny example added in this step) prints `hi` from the bundled python via the real locator.

### Step 7 — Wire `PyRunner` into `DataService`; rebuild `OutputService` as adapter

**What.**
- Root `pubspec.yaml`: add `py_runner: { path: packages/py_runner }`. (`py_engine_desktop` stays for now — step 9 removes it.)
- [`lib/services/data_service.dart`](lib/services/data_service.dart): register `PyRunner` as a lazy singleton; add a `DataService.pyRunner` static getter; keep `DataService.output` registration.
- [`lib/services/output/output_service.dart`](lib/services/output/output_service.dart): new internal logic — `run(code)` calls `DataService.pyRunner.run(code)` (lazy `start()` on first use), pins subscriptions to the returned `RunHandle`, exposes them via the `OutputController` for the widget. The existing `OutputController.bind(...)` seam is preserved for back-compat but becomes a no-op shim during the transition.
- Add a tiny set of `ValueNotifier`s on `OutputService` for the widget to listen to: `lines: ValueNotifier<List<OutputLine>>`, `isRunning: ValueNotifier<bool>`. (Matches the existing `get_it` + `ValueNotifier` pattern; no Riverpod / Bloc / Provider creep.)

**Definition of done.** `flutter analyze` clean. `flutter test` passes. The dashboard still uses `py_engine_desktop` because `output.dart` hasn't been swapped yet — this step adds the new path alongside the old one without removing anything.

### Step 8 — Replace `output.dart` widget body

**What.** Rewrite [`lib/features/dashboard/output.dart`](lib/features/dashboard/output.dart) to listen to `OutputService.lines` + `OutputService.isRunning`. Remove all `py_engine_desktop` calls, the `pipInstall` block, the `_initializePython` method, and the `student_script.py` temp-file write (code is now passed as a string in the `exec` frame). Keep the `OutputController.bind` call removed — `OutputService` no longer needs a widget-bound runner.

**Definition of done.**
- `flutter analyze` clean, `flutter test` passes.
- `flutter run -d windows` from a build that ran `build_bundle.ps1` first (with `PY_RUNNER_PYTHON` set):
  - `print("hello")` → output appears.
  - `print("ë")` → renders correctly.
  - `import numpy as np; print(np.arange(3))` → `[0 1 2]`.
  - `import turtle; t = turtle.Turtle(); t.forward(100); turtle.done()` → Tk window opens (note: not parented to Flutter — see §6).
  - `import matplotlib; matplotlib.use("TkAgg"); import matplotlib.pyplot as plt; plt.plot([1,2,3]); plt.show()` → window opens.
  - `import time; [print(i) or time.sleep(1) for i in range(10)]` then Stop button → run terminates within ~1 s.
  - Three Run-button presses in quick succession → only the last run produces output.

### Step 9 — Drop `py_engine_desktop`

**What.** Remove `py_engine_desktop` from [pubspec.yaml](pubspec.yaml). `flutter pub get`. Confirm no other imports remain.

**Definition of done.** `flutter analyze` clean. `flutter test` passes. All step-8 manual tests still pass. **This is the milestone where the existing dashboard works on the new runner with no feature changes.**

### Step 10 — `input()` support

**What.**
- `host.py`: install a `builtins.input` replacement that emits an `input_request` frame and blocks the worker thread on a per-run `Queue` until a matching `input_response` arrives. Concurrent `input_request`s within one run get monotonic `request_id`s.
- `PyRunner` / `RunHandle`: surface `inputRequests` stream and `respondToInput(requestId, value)` (already in the API; v1 was a no-op).
- `OutputService`: surface `pendingInputRequest: ValueNotifier<InputRequest?>` and a `submitInput(value)` method.
- [`output.dart`](lib/features/dashboard/output.dart): when `pendingInputRequest != null`, render an inline `TextField` + send button below the log; submitting calls `OutputService.submitInput(value)`. Cancelling the run clears the pending request.

**Definition of done.** Manual: `name = input("Naam? "); print(f"Hallo {name}")` shows the prompt, accepts text input, prints. Hitting Stop while waiting on input cancels cleanly. `flutter analyze` clean.

### Step 11 — Per-run timeout & per-run subprocess cleanup

**What.**
- `PyRunner.run(code, {Duration? timeout})` — defaults to `null` (no timeout). Caller may pass one.
- `host.py`: on timeout, `PyThreadState_SetAsyncExc(TimeoutError)` in the worker; if not honoured within 2 s, host emits `done(status:cancelled, reason:"timeout-hard")` and exits. `PyRunner` respawns transparently on next run.
- Replace v1's "kill self" cancel fallback with the same hard-kill path.

**Definition of done.** Manual: `while True: pass` with a 5 s timeout produces a `cancelled` done within ~5 s. `import time; time.sleep(60)` with a 2 s timeout cancels promptly. The dashboard does not enable timeouts in the UI yet — this step exposes the capability for future use.

## 6. Risks & open questions

### Risks

- **Antivirus / SmartScreen.** Bundling a fresh, large `python.exe` plus an unsigned installer trips Defender on first install for many students; the installer's reputation has to build. Code-signing the installer (and ideally `python.exe` itself) is the standard remedy. Without a cert, expect "Windows protected your PC" prompts on first run and after every version bump. *Threat mitigated: false-positive blocks during deployment days. Action: budget for a code-signing cert, or accept the prompt-and-click-through workflow.*
- **Tk window ownership.** `turtle` and `TkAgg` open native top-level windows owned by the host `python.exe`, not by the Flutter window. They aren't z-ordered with Flutter and can be lost behind it. v1 documents this rather than fixing it; a real fix needs Win32 `SetParent` against the Flutter HWND, which is out of scope.
- **stdin line-buffering on Windows.** Without `PYTHONUNBUFFERED=1` and `-u`, Python buffers its stdout when the descriptor is a pipe — student `print()` calls would never reach Flutter until the run ended. The plan forces both. Worth a dedicated test that streams output during a long run, not just at end.
- **Bundle size.** `install_only` tarball is ~30 MB extracted; numpy + pandas + matplotlib + requests adds 150–250 MB. Installer goes from ~20 MB to ~250 MB. Confirm the school's bandwidth tolerates this on rollout day.
- **Code-signing implications.** If the installer is later signed, the bundled `python.exe` and DLLs are part of the signed payload — fine. But if anything inside `{app}\python\` is mutated at runtime (e.g., a future "let students pip install X" feature), Defender may flag tampering. v1 keeps the bundle read-only. Don't add runtime pip without revisiting this.
- **Uninstall cleanup.** Inno Setup removes everything under `{app}` on uninstall, including the bundled Python — desired. *But* if students later create venvs / write files inside `{app}\python\`, those are wiped on update. Fine for v1.
- **Multi-run interleaving.** v1 host serves one run at a time, but the protocol's `id` field forces the Dart pump to route by `id` from day one. A bug where run B's output leaks into run A's `RunHandle` would only surface in step 10+; cover it with a unit test on the pump.
- **Path with spaces.** `{app}` typically lives under `C:\Program Files\Python Teacher\`. `host_locator.dart` must pass argv as a list, never as a joined command string. Worth a unit test with a fixture path containing a space.
- **First-import latency.** numpy/pandas/matplotlib import is slow (~1–3 s combined) on first run after install. Mitigation: precompile to `.pyc` in step 1, and consider an "import warmup" at app startup that imports the heavy modules in the host before the student hits Run. *Defer the warmup — measure first.*

### Open questions

- **`flutter_distributor` extensibility (§4.2).** Verify whether the `exe` target accepts a custom `inno_setup_script:` path or whether we own the .iss build outright. Affects step 5 only; doesn't change the rest of the plan.
- **python-build-standalone exact tag.** The `release_tag` and SHA-256 in `manifest.toml` need to be filled in from the live release page before step 1 lands. The plan pins 3.14.0 per the architectural decision; if cp314 wheels for numpy/pandas/matplotlib aren't yet published when step 1 runs, fall back to the latest 3.13.x build with full wheel coverage.
- **scikit-learn.** Currently in the `py_engine_desktop` install list but not used anywhere in dashboard examples I can see. Confirm with Yvan whether students need it in v1; if not, drop it from the manifest to save ~80 MB.
- **`config/global` `Model` parity.** Unrelated to Python execution but worth flagging: the plan touches `OutputService` and `data_service.dart`. While there, do not "fix" the unused `LocalApiKeyStorage` / `GlobalConfig.apiKey` paths called out in [PROJECT_OVERVIEW.md §7](PROJECT_OVERVIEW.md). Out of scope.
- **Touching anything outside the allowed paths.** The constraints limit changes to `packages/py_runner/`, `lib/services/output/`, `features/dashboard/output.dart`, `pubspec.yaml`, `windows/packaging/`, and new `tooling/` scripts. Likely *additional* touches — flagged here, not silently included:
  - [`lib/services/data_service.dart`](lib/services/data_service.dart) — needs a `PyRunner` registration. *Open question: is this in-scope as part of "lib/services/output/" since it's the wiring point, or a separate exception to request?*
  - [pubspec.yaml](pubspec.yaml) — explicitly in-scope, but worth confirming the `path:` dependency on `packages/py_runner/` is acceptable.
  - Root `.gitignore` — to exclude `build/python_bundle/` and `tooling/python/.cache/`. Cosmetic; confirm acceptable.
- **Future expansions design check.** The protocol leaves room for `figure`, `ast_summary`, `var_repr`, and per-run subprocess sandboxing (step 11 already moves toward this) without breaking changes. Worth a brief design review with Yvan after step 9 ships, before step 10.

## 7. Definition of done — summary

For each step above, the consolidated bar is:

1. Code compiles (`flutter pub get` succeeds; `dart pub get` in `packages/py_runner`).
2. `flutter analyze` clean across the whole repo.
3. `flutter test` passes (and `dart test packages/py_runner` for steps 3+).
4. The step-specific manual smoke tests pass on `flutter run -d windows`, run from an installer-built or dev-locator-pointed Python bundle.
5. No regression in dashboard behaviour observable from the editor + Run/Stop/Hint/Submit toolbar.

Step 9 is the explicit "feature-parity-with-`py_engine_desktop`" gate. Steps 10–11 strictly add capability.
