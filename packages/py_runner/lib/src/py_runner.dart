import 'dart:async';
import 'dart:math';

import 'frames.dart';
import 'host_locator.dart';
import 'host_process.dart';

part 'run_handle.dart';

/// Lifecycle states surfaced via [PyRunner.statusChanges].
enum PyRunnerStatus { stopped, starting, ready, crashed }

/// Long-lived owner of one host `python.exe` process. Construct once
/// (typically as a `get_it` lazy singleton in the consuming app), call
/// [start] before the first run, [shutdown] at app exit.
///
/// Step 4 supports a single in-flight run at a time; the protocol's `id`
/// field is preserved end-to-end so adding concurrent runs later is a
/// host-internal change.
class PyRunner {
  PyRunner({required this.locator});

  final PyHostLocator locator;

  HostProcess? _host;
  StreamSubscription<HostOutboundFrame>? _framesSub;
  ReadyFrame? _readyInfo;

  PyRunnerStatus _status = PyRunnerStatus.stopped;
  final _statusController = StreamController<PyRunnerStatus>.broadcast();
  final _hostLogController = StreamController<HostLogFrame>.broadcast();

  /// Latest run handed out by [run]. Used to chain cancellation when a
  /// successor `run` arrives before this one has emitted `done`.
  _RunController? _inFlight;

  /// Runs whose `exec` has been sent and that haven't yet emitted `done`.
  /// The frame pump dispatches into this map by `id`.
  final Map<String, _RunController> _activeRuns = <String, _RunController>{};

  Completer<void>? _startCompleter;

  PyRunnerStatus get status => _status;

  /// Broadcast stream of status transitions.
  Stream<PyRunnerStatus> get statusChanges => _statusController.stream;

  /// Diagnostic frames emitted by the host (`host_log` on the wire).
  Stream<HostLogFrame> get hostLogs => _hostLogController.stream;

  /// Information from the `ready` frame; null until [start] resolves.
  ReadyFrame? get readyInfo => _readyInfo;

  /// Spawn the host and await the `ready` frame. Idempotent: concurrent
  /// callers share the in-progress future, and a successful start is a
  /// no-op.
  Future<void> start() async {
    if (_status == PyRunnerStatus.ready) return;
    if (_startCompleter != null) return _startCompleter!.future;

    final completer = Completer<void>();
    _startCompleter = completer;
    _setStatus(PyRunnerStatus.starting);

    try {
      final paths = await locator.resolve();
      final host = await HostProcess.spawn(
        pythonExecutable: paths.pythonExecutable,
        hostScript: paths.hostScript,
      );
      _host = host;

      final readyCompleter = Completer<ReadyFrame>();
      _framesSub = host.frames.listen(
        (frame) {
          if (!readyCompleter.isCompleted) {
            if (frame is ReadyFrame) {
              readyCompleter.complete(frame);
              return;
            }
            // host.py always emits `ready` first; anything else before it is
            // out-of-spec, so drop it.
            return;
          }
          _onFrame(frame);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!readyCompleter.isCompleted) {
            readyCompleter.completeError(error, stackTrace);
          }
        },
        onDone: () {
          if (!readyCompleter.isCompleted) {
            readyCompleter.completeError(
              StateError('host process exited before emitting ready'),
            );
          }
          _onHostExit();
        },
      );

      _readyInfo = await readyCompleter.future;
      _setStatus(PyRunnerStatus.ready);
      completer.complete();
    } catch (error, stackTrace) {
      _setStatus(PyRunnerStatus.crashed);
      if (!completer.isCompleted) {
        // The first caller gets the error via `rethrow` below; the completer
        // only exists so concurrent callers (and shutdown()) can await the
        // same attempt. Mark its future observed so an error with no other
        // waiters isn't reported as unhandled in the calling zone (#33).
        completer.future.ignore();
        completer.completeError(error, stackTrace);
      }
      _startCompleter = null;
      rethrow;
    }
    _startCompleter = null;
  }

  /// Kill the host and abort every in-flight run. Idempotent.
  Future<void> shutdown() async {
    // If startup is racing, wait for it to settle before tearing down so
    // we don't leak the spawning Process.
    final pending = _startCompleter;
    if (pending != null) {
      try {
        await pending.future;
      } catch (_) {
        // start() failed; tear down what little state we built.
      }
    }

    if (_host == null && _status == PyRunnerStatus.stopped) return;

    final host = _host;
    _host = null;

    final survivors = <_RunController>[
      ..._activeRuns.values,
      if (_inFlight != null && !_activeRuns.containsKey(_inFlight!.id))
        _inFlight!,
    ];
    _activeRuns.clear();
    _inFlight = null;
    for (final ctrl in survivors) {
      ctrl._synthesizeDone(RunStatus.cancelled);
    }

    await _framesSub?.cancel();
    _framesSub = null;

    await host?.shutdown();

    _setStatus(PyRunnerStatus.stopped);
  }

  /// Start a Python run. Cancels any currently in-flight run before sending
  /// the new `exec`. Returns immediately; observe progress via the handle.
  ///
  /// [timeout] is forwarded to the host as `timeout_ms`; the host kills the
  /// worker subprocess when it elapses. Null means no timeout.
  RunHandle run(String code, {String? cwd, Duration? timeout}) {
    if (_status != PyRunnerStatus.ready || _host == null) {
      throw StateError(
        'PyRunner is not ready (status: $_status); call start() first.',
      );
    }

    final id = _newRunId();
    final ctrl = _RunController(
      id: id,
      sendFrame: (frame) => _host?.send(frame),
    );

    final prior = _inFlight;
    _inFlight = ctrl;

    if (prior != null && !prior.isDone) {
      prior._requestCancel();
    }

    unawaited(_scheduleStart(ctrl, prior, code, cwd, timeout));

    return ctrl.handle;
  }

  Future<void> _scheduleStart(
    _RunController ctrl,
    _RunController? prior,
    String code,
    String? cwd,
    Duration? timeout,
  ) async {
    if (prior != null) {
      try {
        await prior.handle.done;
      } catch (_) {
        // Predecessor errored; we still want to run.
      }
    }

    if (ctrl.cancelRequested) {
      // A successor `run` overtook us before our `exec` was sent.
      ctrl._synthesizeDone(RunStatus.cancelled);
      if (identical(_inFlight, ctrl)) _inFlight = null;
      return;
    }

    if (_status != PyRunnerStatus.ready || _host == null) {
      ctrl._synthesizeDone(
        RunStatus.error,
        exception: const PyException(
          type: 'StateError',
          message: 'PyRunner is no longer ready',
          traceback: '',
        ),
      );
      if (identical(_inFlight, ctrl)) _inFlight = null;
      return;
    }

    _activeRuns[ctrl.id] = ctrl;
    ctrl._markExecSent();
    _host!.send(
      ExecFrame(
        id: ctrl.id,
        code: code,
        cwd: cwd,
        timeoutMs: timeout?.inMilliseconds,
      ),
    );

    unawaited(
      ctrl.handle.done.whenComplete(() {
        _activeRuns.remove(ctrl.id);
        if (identical(_inFlight, ctrl)) _inFlight = null;
      }),
    );
  }

  void _onFrame(HostOutboundFrame frame) {
    switch (frame) {
      case ReadyFrame():
        // Spurious post-startup ready; ignore.
        break;
      case StdoutFrame():
        _activeRuns[frame.id]?._onStdout(frame.text);
      case StderrFrame():
        _activeRuns[frame.id]?._onStderr(frame.text);
      case InputRequestFrame():
        _activeRuns[frame.id]?._onInputRequest(frame);
      case ExceptionFrame():
        _activeRuns[frame.id]?._onException(frame);
      case DoneFrame():
        _activeRuns.remove(frame.id)?._onDone(frame);
      case HostLogFrame():
        if (!_hostLogController.isClosed) _hostLogController.add(frame);
    }
  }

  void _onHostExit() {
    if (_status == PyRunnerStatus.stopped) return;
    _setStatus(PyRunnerStatus.crashed);

    final survivors = <_RunController>[
      ..._activeRuns.values,
      if (_inFlight != null && !_activeRuns.containsKey(_inFlight!.id))
        _inFlight!,
    ];
    _activeRuns.clear();
    _inFlight = null;
    for (final ctrl in survivors) {
      ctrl._synthesizeDone(
        RunStatus.error,
        exception: const PyException(
          type: 'HostExited',
          message: 'host process exited unexpectedly',
          traceback: '',
        ),
      );
    }
  }

  void _setStatus(PyRunnerStatus next) {
    if (_status == next) return;
    _status = next;
    if (!_statusController.isClosed) _statusController.add(next);
  }

  static final _random = Random.secure();

  /// Generates a UUID v4 string for a run id (RFC 4122 §4.4 layout).
  static String _newRunId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    String hex(int n) => n.toRadixString(16).padLeft(2, '0');
    final s = bytes.map(hex).join();
    return '${s.substring(0, 8)}-'
        '${s.substring(8, 12)}-'
        '${s.substring(12, 16)}-'
        '${s.substring(16, 20)}-'
        '${s.substring(20)}';
  }
}
