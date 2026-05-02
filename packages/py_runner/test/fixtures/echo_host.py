"""Stdlib-only fake host used by the py_runner Dart tests.

Mimics host.py's wire protocol just enough to exercise the Dart side without
needing a numpy/pandas-laden bundle. Behaviour:

  * Emits a `ready` frame on startup.
  * For each `exec` frame, emits a `stdout` frame that echoes the code, then
    a `done` frame with status `ok`. If the code body contains a line of the
    form ``# sleep_ms=<int>`` the worker waits that long (cooperatively
    polling for a cancel) before emitting `done`.
  * For a `cancel` frame matching the active run's id, transitions the run
    to cancelled; the worker emits `done(cancelled)` instead of the normal
    completion.
  * Ignores `input_response` (v1 host accepts it as a no-op).

Intentionally NOT a re-implementation of the real host: no `exec()`, no
redirect_stdout, no traceback formatting. Just enough wire-protocol surface
to drive the Dart pump.
"""
from __future__ import annotations

import json
import sys
import threading
import time


_lock = threading.Lock()
_active_id: str | None = None


def _emit(frame: dict) -> None:
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()


def _parse_sleep_ms(code: str) -> int:
    for line in code.splitlines():
        stripped = line.strip()
        if stripped.startswith("# sleep_ms="):
            try:
                return max(0, int(stripped.split("=", 1)[1]))
            except ValueError:
                return 0
    return 0


def _is_cancelled(run_id: str) -> bool:
    with _lock:
        return _active_id != run_id


def _handle_exec(frame: dict) -> None:
    global _active_id
    run_id = frame.get("id")
    code = frame.get("code", "")
    if not isinstance(run_id, str) or not isinstance(code, str):
        return
    sleep_ms = _parse_sleep_ms(code)

    with _lock:
        _active_id = run_id

    deadline = time.monotonic() + sleep_ms / 1000.0
    cancelled = False
    while time.monotonic() < deadline:
        time.sleep(0.01)
        if _is_cancelled(run_id):
            cancelled = True
            break

    if cancelled:
        _emit({
            "type": "done",
            "id": run_id,
            "status": "cancelled",
            "duration_ms": 0,
        })
        return

    with _lock:
        if _active_id != run_id:
            # Cancel landed exactly at the boundary.
            _emit({
                "type": "done",
                "id": run_id,
                "status": "cancelled",
                "duration_ms": 0,
            })
            return
        _active_id = None

    _emit({"type": "stdout", "id": run_id, "text": "echo:" + code})
    _emit({"type": "done", "id": run_id, "status": "ok", "duration_ms": 0})


def _handle_cancel(frame: dict) -> None:
    global _active_id
    run_id = frame.get("id")
    if not isinstance(run_id, str):
        return
    with _lock:
        if _active_id == run_id:
            _active_id = None


def main() -> int:
    _emit({
        "type": "ready",
        "python_version": "0.0.0-echo",
        "platform": "echo_fixture",
        "capabilities": ["exec", "cancel"],
        "protocol_version": 1,
    })

    workers: list[threading.Thread] = []

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            frame = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(frame, dict):
            continue
        kind = frame.get("type")
        if kind == "exec":
            t = threading.Thread(
                target=_handle_exec, args=(frame,), daemon=True
            )
            workers.append(t)
            t.start()
        elif kind == "cancel":
            _handle_cancel(frame)
        # input_response: silently ignored.

    # Drain any workers still running so the in-flight `done` reaches the
    # parent before we exit.
    for t in workers:
        t.join(timeout=2.0)
    return 0


if __name__ == "__main__":
    sys.exit(main())
