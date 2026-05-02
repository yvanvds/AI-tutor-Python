"""host.py - long-lived Python host for the Flutter AI tutor app.

Wire protocol: newline-delimited UTF-8 JSON frames over stdin/stdout.
See PYTHON_IMPLEMENTATION.md section 2.2 for the full frame catalogue.

Run modes
---------
Orchestrator (default, no flags):
    Long-lived process reading frames from Flutter's stdin and routing them to
    per-run worker subprocesses.  Cancellation and timeouts are handled at OS
    level by killing the subprocess — no GIL contention, so even
    ``math.factorial(5_000_000)`` (a GIL-holding C call) is terminated promptly.

Worker (``--worker`` flag):
    Short-lived process spawned once per run.  Reads an exec context frame from
    stdin line 1, executes the student code, and writes protocol frames to its
    own stdout (which the orchestrator relays verbatim to Flutter).
    ``input()`` is replaced by a function that emits an ``input_request`` frame
    and blocks reading the next line from the worker's stdin; the orchestrator
    feeds ``input_response`` frames written by Flutter into that pipe.

Expected to be spawned with:
    python.exe -s -X utf8 -u host.py [--worker]
and env: PYTHONIOENCODING=utf-8, PYTHONUNBUFFERED=1, PYTHONNOUSERSITE=1.
"""

from __future__ import annotations

import contextlib
import io
import json
import os
import platform
import subprocess
import sys
import threading
import time
import traceback


_PROTOCOL_VERSION = 1
_STUDENT_FILE = "<student>"
_SCRIPT_PATH = os.path.abspath(__file__)

# Frames are written here. Captured BEFORE any redirect_stdout the worker
# installs, so emission stays on the real stdout regardless of redirects.
_FRAME_OUT = sys.stdout
_write_lock = threading.Lock()


def _emit(frame: dict) -> None:
    """Serialize one frame as a single line on the frame stream."""
    line = json.dumps(frame, ensure_ascii=False, separators=(",", ":"))
    with _write_lock:
        _FRAME_OUT.write(line + "\n")
        _FRAME_OUT.flush()


def _log(level: str, message: str) -> None:
    _emit({"type": "host_log", "level": level, "message": message})


# ---- shared helpers -------------------------------------------------------


class _StreamWriter(io.TextIOBase):
    """Wraps writes from student code into stdout/stderr frames."""

    def __init__(self, run_id: str, kind: str):
        super().__init__()
        self._run_id = run_id
        self._kind = kind  # "stdout" or "stderr"

    def writable(self) -> bool:
        return True

    def write(self, s: str) -> int:
        if not s:
            return 0
        _emit({"type": self._kind, "id": self._run_id, "text": s})
        return len(s)

    def flush(self) -> None:
        # Each write is already flushed; nothing to do.
        pass


def _duration_ms(start_ns: int) -> int:
    return max(0, int((time.monotonic_ns() - start_ns) / 1_000_000))


def _student_traceback(exc: BaseException) -> str:
    """Format exc's traceback starting at the first <student> frame.

    Without this, every traceback shows host.py's ``exec(compiled, globs)``
    frame, which is irrelevant noise for students.
    """
    tb_obj = exc.__traceback__
    while tb_obj is not None and tb_obj.tb_frame.f_code.co_filename != _STUDENT_FILE:
        tb_obj = tb_obj.tb_next
    if tb_obj is None:
        return "".join(traceback.format_exception(exc))
    lines = ["Traceback (most recent call last):\n"]
    lines.extend(traceback.format_list(traceback.extract_tb(tb_obj)))
    lines.extend(traceback.format_exception_only(type(exc), exc))
    return "".join(lines)


# ===========================================================================
# Worker mode
# ===========================================================================


def _make_worker_input_fn(run_id: str, stdin_reader: io.TextIOWrapper):
    """Return a builtins.input replacement for the worker subprocess.

    Emits an ``input_request`` frame then blocks reading stdin until the
    orchestrator writes back a matching ``input_response`` frame.
    """
    next_req_id = 0
    req_lock = threading.Lock()

    def _input(prompt: str = "") -> str:
        nonlocal next_req_id
        with req_lock:
            req_id = next_req_id
            next_req_id += 1
        _emit({
            "type": "input_request",
            "id": run_id,
            "request_id": req_id,
            "prompt": str(prompt),
        })
        while True:
            line = stdin_reader.readline()
            if not line:
                raise KeyboardInterrupt  # stdin closed = run cancelled
            line = line.strip()
            if not line:
                continue
            try:
                resp = json.loads(line)
            except json.JSONDecodeError:
                continue
            if (
                resp.get("type") == "input_response"
                and resp.get("request_id") == req_id
            ):
                return str(resp.get("value", ""))

    return _input


def _worker_main() -> int:
    """Entry point for a per-run worker subprocess (launched with --worker)."""
    stdin = io.TextIOWrapper(
        sys.stdin.buffer, encoding="utf-8", errors="replace", newline="\n"
    )

    raw = stdin.readline()
    if not raw:
        return 1
    try:
        ctx = json.loads(raw.strip())
    except json.JSONDecodeError as exc:
        _log("error", f"worker: bad exec context: {exc.msg}")
        return 1

    run_id = ctx.get("id")
    code = ctx.get("code")
    cwd = ctx.get("cwd")
    if not isinstance(run_id, str) or not isinstance(code, str):
        _log("error", "worker: exec context missing id or code")
        return 1

    start_ns = time.monotonic_ns()
    out = _StreamWriter(run_id, "stdout")
    err = _StreamWriter(run_id, "stderr")
    status = "ok"

    if isinstance(cwd, str):
        try:
            os.chdir(cwd)
        except OSError as exc:
            _log("warn", f"chdir failed: {exc!r}")

    globs: dict = {
        "__name__": "__main__",
        "__doc__": None,
        "__package__": None,
        "__loader__": None,
        "__spec__": None,
        "__builtins__": __builtins__,
        "__file__": _STUDENT_FILE,
        "input": _make_worker_input_fn(run_id, stdin),
    }

    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            compiled = compile(code, _STUDENT_FILE, "exec")
            exec(compiled, globs)
        except KeyboardInterrupt:
            status = "cancelled"
        except SystemExit as exc:  # NOSONAR python:S5754
            # SystemExit from student code must end the run, not the worker
            # subprocess.  sys.exit(0) / sys.exit(None) is a clean finish.
            exit_code = exc.code
            if exit_code in (None, 0):
                status = "ok"
            else:
                status = "error"
                _emit({
                    "type": "exception",
                    "id": run_id,
                    "exc_type": "SystemExit",
                    "message": str(exit_code),
                    "traceback": _student_traceback(exc),
                })
        except BaseException as exc:  # noqa: BLE001
            status = "error"
            _emit({
                "type": "exception",
                "id": run_id,
                "exc_type": type(exc).__name__,
                "message": str(exc),
                "traceback": _student_traceback(exc),
            })

    _emit({
        "type": "done",
        "id": run_id,
        "status": status,
        "duration_ms": _duration_ms(start_ns),
    })
    return 0


# ===========================================================================
# Orchestrator mode
# ===========================================================================


class _RunState:
    __slots__ = ("id", "start_ns", "proc", "timer", "thread")

    def __init__(self, run_id: str, start_ns: int):
        self.id = run_id
        self.start_ns = start_ns
        self.proc: subprocess.Popen | None = None
        self.timer: threading.Timer | None = None
        self.thread: threading.Thread | None = None  # pump thread


_state_lock = threading.Lock()
_active: _RunState | None = None


def _kill_run(state: _RunState) -> None:
    """Kill the worker subprocess at OS level. The pump thread emits done."""
    if state.timer is not None:
        state.timer.cancel()
        state.timer = None
    if state.proc is not None:
        try:
            state.proc.kill()
        except ProcessLookupError:
            pass  # already dead


def _drain_stderr(proc: subprocess.Popen, run_id: str) -> None:
    """Drain subprocess stderr continuously so the OS pipe buffer can't fill."""
    try:
        reader = io.TextIOWrapper(
            proc.stderr, encoding="utf-8", errors="replace"
        )
        for line in reader:
            line = line.strip()
            if line:
                _log("warn", f"worker[{run_id[:8]}] stderr: {line}")
    except Exception:  # noqa: BLE001
        pass


def _pump_worker(proc: subprocess.Popen, state: _RunState) -> None:
    """Read frames from the worker subprocess stdout and relay to Flutter."""
    saw_done = False
    try:
        reader = io.TextIOWrapper(
            proc.stdout, encoding="utf-8", errors="replace", newline="\n"
        )
        for raw_line in reader:
            line = raw_line.strip()
            if not line:
                continue
            try:
                frame = json.loads(line)
            except json.JSONDecodeError:
                _log("warn", f"worker emitted bad JSON: {line[:80]!r}")
                continue
            if frame.get("type") == "done":
                saw_done = True
            _emit(frame)
    except Exception as exc:  # noqa: BLE001
        _log("warn", f"pump error for run {state.id[:8]}: {exc!r}")
    finally:
        if state.timer is not None:
            state.timer.cancel()
            state.timer = None
        if not saw_done:
            _emit({
                "type": "done",
                "id": state.id,
                "status": "cancelled",
                "duration_ms": _duration_ms(state.start_ns),
            })
        with _state_lock:
            global _active
            if _active is state:
                _active = None
        try:
            proc.kill()
        except Exception:  # noqa: BLE001
            pass
        try:
            proc.wait(timeout=2.0)
        except Exception:  # noqa: BLE001
            pass
        try:
            proc.stdin.close()
        except Exception:  # noqa: BLE001
            pass


# ---- frame handlers -------------------------------------------------------


def _handle_exec(frame: dict) -> None:
    run_id = frame.get("id")
    code = frame.get("code")
    cwd = frame.get("cwd")
    timeout_ms_raw = frame.get("timeout_ms")
    timeout_s: float | None = None
    if isinstance(timeout_ms_raw, (int, float)) and timeout_ms_raw > 0:
        timeout_s = timeout_ms_raw / 1000.0

    if not isinstance(run_id, str) or not isinstance(code, str):
        _log("error", "exec frame missing id or code")
        return

    with _state_lock:
        global _active
        if _active is not None:
            _log("error", f"exec rejected: run {_active.id} still active")
            _emit({
                "type": "exception",
                "id": run_id,
                "exc_type": "RuntimeError",
                "message": "another run is already active",
                "traceback": "",
            })
            _emit({
                "type": "done",
                "id": run_id,
                "status": "error",
                "duration_ms": 0,
            })
            return
        state = _RunState(run_id, time.monotonic_ns())
        _active = state

    env = {
        **os.environ,
        "PYTHONIOENCODING": "utf-8",
        "PYTHONUNBUFFERED": "1",
        "PYTHONNOUSERSITE": "1",
    }
    try:
        proc = subprocess.Popen(
            [sys.executable, "-s", "-X", "utf8", "-u", _SCRIPT_PATH, "--worker"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
        )
    except OSError as exc:
        _log("error", f"failed to spawn worker: {exc!r}")
        _emit({
            "type": "exception",
            "id": run_id,
            "exc_type": "OSError",
            "message": str(exc),
            "traceback": "",
        })
        _emit({
            "type": "done",
            "id": run_id,
            "status": "error",
            "duration_ms": 0,
        })
        with _state_lock:
            if _active is state:
                _active = None
        return

    state.proc = proc

    context_line = (
        json.dumps(
            {"type": "exec", "id": run_id, "code": code, "cwd": cwd},
            ensure_ascii=False,
        )
        + "\n"
    )
    proc.stdin.write(context_line.encode("utf-8"))
    proc.stdin.flush()

    pump = threading.Thread(
        target=_pump_worker,
        args=(proc, state),
        daemon=True,
        name=f"py-pump-{run_id[:8]}",
    )
    pump.start()
    state.thread = pump

    threading.Thread(
        target=_drain_stderr,
        args=(proc, run_id),
        daemon=True,
        name=f"py-stderr-{run_id[:8]}",
    ).start()

    if timeout_s is not None:
        timer = threading.Timer(timeout_s, _handle_timeout, args=(state,))
        timer.daemon = True
        timer.start()
        state.timer = timer


def _handle_timeout(state: _RunState) -> None:
    with _state_lock:
        if _active is not state:
            return  # run already finished before the timer fired
    _log("warn", f"timeout reached for run {state.id[:8]}")
    _kill_run(state)


def _handle_cancel(frame: dict) -> None:
    """Cancel the active run by killing its worker subprocess at OS level.

    Because the student code runs in a separate subprocess, even GIL-holding C
    calls (e.g. ``math.factorial(5_000_000)``) are terminated immediately by the
    OS without waiting for the GIL.
    """
    run_id = frame.get("id")
    if not isinstance(run_id, str):
        return
    with _state_lock:
        state = _active
    if state is None or state.id != run_id:
        return
    _kill_run(state)


def _handle_input_response(frame: dict) -> None:
    run_id = frame.get("id")
    request_id = frame.get("request_id")
    value = frame.get("value", "")
    if not isinstance(run_id, str) or not isinstance(request_id, int):
        return
    with _state_lock:
        state = _active
    if state is None or state.id != run_id or state.proc is None:
        return
    if state.proc.poll() is not None:
        return  # subprocess already dead
    try:
        response_line = (
            json.dumps(
                {
                    "type": "input_response",
                    "request_id": request_id,
                    "value": str(value),
                },
                ensure_ascii=False,
            )
            + "\n"
        )
        state.proc.stdin.write(response_line.encode("utf-8"))
        state.proc.stdin.flush()
    except OSError:
        pass  # subprocess stdin closed


_HANDLERS = {
    "exec": _handle_exec,
    "cancel": _handle_cancel,
    "input_response": _handle_input_response,
}


# ---- main loop ------------------------------------------------------------


def _ready() -> None:
    py = sys.version_info
    arch = platform.machine().lower() or "unknown"
    sysname = platform.system().lower() or "unknown"
    _emit({
        "type": "ready",
        "python_version": f"{py.major}.{py.minor}.{py.micro}",
        "platform": f"{sysname}_{arch}",
        "capabilities": ["exec", "cancel", "input", "timeout"],
        "protocol_version": _PROTOCOL_VERSION,
    })


def _dispatch_line(line: str) -> None:
    line = line.strip()
    if not line:
        return
    try:
        frame = json.loads(line)
    except json.JSONDecodeError as exc:
        _log("error", f"bad frame: {exc.msg}")
        return
    if not isinstance(frame, dict):
        _log("error", "bad frame: not an object")
        return
    kind = frame.get("type")
    handler = _HANDLERS.get(kind)
    if handler is None:
        _log("warn", f"unknown frame type: {kind!r}")
        return
    try:
        handler(frame)
    except Exception as exc:  # noqa: BLE001
        _log("error", f"handler {kind} crashed: {exc!r}")


def _await_active_run() -> None:
    """Block until any active run's pump thread finishes."""
    with _state_lock:
        pending = _active.thread if _active is not None else None
    if pending is not None:
        pending.join()


def main() -> int:
    stdin = io.TextIOWrapper(
        sys.stdin.buffer, encoding="utf-8", errors="replace", newline="\n"
    )
    _ready()

    while True:
        line = stdin.readline()
        if not line:
            # EOF on stdin -> graceful shutdown.  Wait for any active run so
            # its `done` frame is emitted before we exit (pump thread is a
            # daemon, so the interpreter would otherwise kill it mid-frame).
            _await_active_run()
            break
        _dispatch_line(line)

    return 0


if __name__ == "__main__":
    if "--worker" in sys.argv:
        sys.exit(_worker_main())
    else:
        sys.exit(main())
