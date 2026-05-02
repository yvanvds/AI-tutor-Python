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
