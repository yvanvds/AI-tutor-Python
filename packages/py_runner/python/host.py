"""host.py - long-lived Python host for the Flutter AI tutor app.

Wire protocol: newline-delimited UTF-8 JSON frames over stdin/stdout.
See PYTHON_IMPLEMENTATION.md section 2.2 for the full frame catalogue.

Expected to be spawned with:
    python.exe -s -X utf8 -u host.py
and env: PYTHONIOENCODING=utf-8, PYTHONUNBUFFERED=1, PYTHONNOUSERSITE=1.
"""

from __future__ import annotations

import contextlib
import ctypes
import io
import json
import os
import platform
import queue
import sys
import threading
import time
import traceback


_PROTOCOL_VERSION = 1
_HARD_KILL_GRACE_S = 0.250
_STUDENT_FILE = "<student>"

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


# ---- run state ---------------------------------------------------------


class _RunState:
    __slots__ = ("id", "code", "cwd", "thread", "cancelled", "start_ns",
                 "input_queue", "_next_req_id", "_req_lock")

    def __init__(self, run_id: str, code: str, cwd: str | None):
        self.id = run_id
        self.code = code
        self.cwd = cwd
        self.thread: threading.Thread | None = None
        self.cancelled = False
        self.start_ns = 0
        self.input_queue: queue.Queue[dict] = queue.Queue()
        self._next_req_id = 0
        self._req_lock = threading.Lock()

    def next_request_id(self) -> int:
        with self._req_lock:
            req_id = self._next_req_id
            self._next_req_id += 1
            return req_id


_state_lock = threading.Lock()
_active: _RunState | None = None


# ---- streamed stdout/stderr from student code --------------------------


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


# ---- async cancel ------------------------------------------------------


def _async_raise(thread: threading.Thread, exc: type[BaseException]) -> None:
    """Raise ``exc`` asynchronously in ``thread``."""
    tid = thread.ident
    if tid is None:
        return
    res = ctypes.pythonapi.PyThreadState_SetAsyncExc(
        ctypes.c_ulong(tid), ctypes.py_object(exc)
    )
    if res == 0:
        _log("warn", f"async_raise: invalid thread id {tid}")
    elif res > 1:
        ctypes.pythonapi.PyThreadState_SetAsyncExc(ctypes.c_ulong(tid), None)
        _log("error", "async_raise: PyThreadState_SetAsyncExc affected >1 thread")


def _duration_ms(start_ns: int) -> int:
    return max(0, int((time.monotonic_ns() - start_ns) / 1_000_000))


def _student_traceback(exc: BaseException) -> str:
    """Format ``exc``'s traceback starting at the first ``<student>`` frame.

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


# ---- input() override --------------------------------------------------


def _make_input_fn(state: _RunState):
    """Return a replacement for builtins.input bound to *state*.

    Emits an ``input_request`` frame then blocks the worker thread on the
    run's queue until a matching ``input_response`` arrives (or the run is
    cancelled, in which case KeyboardInterrupt is raised).
    """
    def _input(prompt: str = "") -> str:
        req_id = state.next_request_id()
        _emit({
            "type": "input_request",
            "id": state.id,
            "request_id": req_id,
            "prompt": str(prompt),
        })
        while True:
            try:
                response = state.input_queue.get(timeout=0.1)
                if response.get("request_id") == req_id:
                    return str(response.get("value", ""))
                # Wrong request_id — re-enqueue and loop (shouldn't happen in v1).
                state.input_queue.put(response)
            except queue.Empty:
                if state.cancelled:
                    raise KeyboardInterrupt
    return _input


# ---- worker ------------------------------------------------------------


def _run_worker(state: _RunState) -> None:
    out = _StreamWriter(state.id, "stdout")
    err = _StreamWriter(state.id, "stderr")
    status = "ok"

    try:
        if state.cwd:
            try:
                os.chdir(state.cwd)
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
            "input": _make_input_fn(state),
        }

        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                compiled = compile(state.code, _STUDENT_FILE, "exec")
                exec(compiled, globs)
            except KeyboardInterrupt:
                status = "cancelled"
            except SystemExit as exc:  # NOSONAR python:S5754
                # Don't reraise: SystemExit from student code must end the
                # *run*, not the host. The host process services many runs
                # in one session. sys.exit() / sys.exit(0) is treated as a
                # clean run end, matching what `python script.py` does.
                code = exc.code
                if code in (None, 0):
                    status = "ok"
                else:
                    status = "error"
                    _emit({
                        "type": "exception",
                        "id": state.id,
                        "exc_type": "SystemExit",
                        "message": str(code),
                        "traceback": _student_traceback(exc),
                    })
            except BaseException as exc:  # noqa: BLE001
                status = "error"
                _emit({
                    "type": "exception",
                    "id": state.id,
                    "exc_type": type(exc).__name__,
                    "message": str(exc),
                    "traceback": _student_traceback(exc),
                })
    finally:
        if state.cancelled and status != "error":
            status = "cancelled"
        _emit({
            "type": "done",
            "id": state.id,
            "status": status,
            "duration_ms": _duration_ms(state.start_ns),
        })
        with _state_lock:
            global _active
            if _active is state:
                _active = None


# ---- frame handlers ----------------------------------------------------


def _handle_exec(frame: dict) -> None:
    run_id = frame.get("id")
    code = frame.get("code")
    cwd = frame.get("cwd")
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
        state = _RunState(run_id, code, cwd if isinstance(cwd, str) else None)
        state.start_ns = time.monotonic_ns()
        thread = threading.Thread(
            target=_run_worker,
            args=(state,),
            name=f"py-run-{run_id[:8]}",
            daemon=True,
        )
        state.thread = thread
        _active = state

    thread.start()


def _handle_cancel(frame: dict) -> None:
    """Cancel the active run.

    Best-effort under the v1 single-process design: PyThreadState_SetAsyncExc
    only fires at the worker's next bytecode boundary, so a worker stuck in a
    long C call that doesn't release the GIL (e.g. ``math.factorial(5_000_000)``)
    will defeat both the async exception AND the watchdog (the watchdog thread
    can't acquire the GIL to run). Step 11 of PYTHON_IMPLEMENTATION.md replaces
    this with a per-run subprocess that we can kill at the OS level. Cooperative
    code (anything that yields the GIL — ``time.sleep``, I/O, pure-Python loops)
    cancels promptly.
    """
    run_id = frame.get("id")
    if not isinstance(run_id, str):
        return
    with _state_lock:
        state = _active
    if state is None or state.id != run_id:
        return
    state.cancelled = True
    if state.thread is not None and state.thread.is_alive():
        _async_raise(state.thread, KeyboardInterrupt)

    def _watchdog() -> None:
        deadline = time.monotonic() + _HARD_KILL_GRACE_S
        while time.monotonic() < deadline:
            if state.thread is None or not state.thread.is_alive():
                return
            time.sleep(0.01)
        _emit({
            "type": "done",
            "id": state.id,
            "status": "cancelled",
            "duration_ms": _duration_ms(state.start_ns),
        })
        _log("warn", f"hard-kill after cancel grace: run {state.id}")
        os._exit(0)

    threading.Thread(
        target=_watchdog, name="py-cancel-watchdog", daemon=True
    ).start()


def _handle_input_response(frame: dict) -> None:
    run_id = frame.get("id")
    request_id = frame.get("request_id")
    value = frame.get("value", "")
    if not isinstance(run_id, str) or not isinstance(request_id, int):
        return
    with _state_lock:
        state = _active
    if state is None or state.id != run_id:
        return
    state.input_queue.put({"request_id": request_id, "value": str(value)})


_HANDLERS = {
    "exec": _handle_exec,
    "cancel": _handle_cancel,
    "input_response": _handle_input_response,
}


# ---- main loop ---------------------------------------------------------


def _ready() -> None:
    py = sys.version_info
    arch = platform.machine().lower() or "unknown"
    sysname = platform.system().lower() or "unknown"
    _emit({
        "type": "ready",
        "python_version": f"{py.major}.{py.minor}.{py.micro}",
        "platform": f"{sysname}_{arch}",
        "capabilities": ["exec", "cancel", "input"],
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
    """Block until any active run finishes, so its done frame is emitted."""
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
            # EOF on stdin -> graceful shutdown. Wait for any active run to
            # finish so its `done` frame is emitted before we exit (daemon
            # workers would otherwise be killed during interpreter shutdown).
            _await_active_run()
            break
        _dispatch_line(line)

    return 0


if __name__ == "__main__":
    sys.exit(main())
