"""verify_bundle.py - post-build sanity check for the bundled Python host.

Run by tooling/python/build_bundle.ps1 with the *bundled* interpreter:

    python.exe -s -X utf8 verify_bundle.py numpy pandas matplotlib tkinter turtle

Every module named on the command line must import. On top of that, the
script proves the two things a bare import does not:

* ``tkinter`` - a Tcl interpreter can be created (the relocated
  ``tcl/`` library directory resolves) and a Tk root window can be opened
  and destroyed, which is what ``turtle`` needs at runtime.
* ``turtle`` - on top of the Tk check, the ``Lib/turtle.cfg`` written by
  ``build_bundle.ps1`` is picked up: a new turtle is shaped like a turtle,
  not the stock ``classic`` arrowhead (#180). The script runs from an empty
  temporary directory, as student code does, so a ``turtle.cfg`` in the
  build's working directory cannot fake the result.
* ``matplotlib`` - the ``Agg`` backend renders a figure to a PNG, so
  ``plt.savefig(...)`` works even with no window, and the default backend
  the student would get from ``plt.show()`` is reported.

Exit status 0 means the bundle is usable; anything else fails the build.
"""

from __future__ import annotations

import importlib
import os
import sys
import tempfile


def _check_tk() -> None:
    import tkinter

    # Tcl() has no window, so it isolates "init.tcl not found" from
    # "no desktop session" failures.
    tcl = tkinter.Tcl()
    tcl_version = tcl.eval("info patchlevel")
    root = tkinter.Tk()
    root.withdraw()
    root.update()
    root.destroy()
    print(f"  tkinter ok (Tcl/Tk {tcl_version})")


# What build_bundle.ps1 writes to Lib/turtle.cfg (#180).
_TURTLE_DEFAULTS = {"shape": "turtle", "title": "Turtle"}


def _check_turtle_defaults() -> None:
    import turtle

    # turtle reads turtle.cfg once, at import, into _CFG. A Python release
    # that changes where it looks would leave the arrow back in place without
    # any error, so compare the values rather than the file's presence.
    for key, expected in _TURTLE_DEFAULTS.items():
        actual = turtle._CFG.get(key)
        if actual != expected:
            raise RuntimeError(
                f"turtle default {key!r} is {actual!r}, expected {expected!r} "
                "(is Lib/turtle.cfg missing or no longer read?)"
            )
    print(f"  turtle defaults ok (shape {turtle._CFG['shape']!r})")


def _check_matplotlib() -> None:
    import matplotlib

    default_backend = matplotlib.get_backend()
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, ax = plt.subplots()
    ax.plot([0, 1, 2], [0, 1, 4])
    with tempfile.TemporaryDirectory() as tmp:
        target = os.path.join(tmp, "verify.png")
        fig.savefig(target)
        size = os.path.getsize(target)
    plt.close(fig)
    if size <= 0:
        raise RuntimeError("matplotlib Agg produced an empty PNG")
    print(
        f"  matplotlib ok (Agg wrote {size} bytes; default backend "
        f"{default_backend})"
    )


_EXTRA_CHECKS = {
    "tkinter": (_check_tk,),
    "turtle": (_check_tk, _check_turtle_defaults),
    "matplotlib": (_check_matplotlib,),
}


def _verify(argv: list[str]) -> list[str]:
    failures: list[str] = []
    extra_done: set = set()
    for name in argv:
        try:
            module = importlib.import_module(name)
            version = getattr(module, "__version__", "")
            print(f"  import {name} ok {version}".rstrip())
            for check in _EXTRA_CHECKS.get(name, ()):
                if check not in extra_done:
                    extra_done.add(check)
                    check()
        except Exception as exc:  # noqa: BLE001 - report every failure
            failures.append(f"{name}: {type(exc).__name__}: {exc}")
            print(f"  {name} FAILED: {type(exc).__name__}: {exc}")
    return failures


def main(argv: list[str]) -> int:
    if not argv:
        print("usage: verify_bundle.py MODULE [MODULE ...]", file=sys.stderr)
        return 2

    print(f"[verify_bundle] {sys.executable}")
    print(f"[verify_bundle] Python {sys.version.split()[0]}")
    # Run from an empty directory, like a student's program: turtle also
    # reads a turtle.cfg from the working directory, which would mask a
    # missing one in the bundle. Imports resolve from the script's directory
    # and the bundle, never from the working directory, so nothing else moves.
    previous_cwd = os.getcwd()
    with tempfile.TemporaryDirectory() as scratch:
        os.chdir(scratch)
        try:
            failures = _verify(argv)
        finally:
            os.chdir(previous_cwd)

    if failures:
        print("[verify_bundle] FAILED:", file=sys.stderr)
        for line in failures:
            print(f"  {line}", file=sys.stderr)
        return 1
    print("[verify_bundle] all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
