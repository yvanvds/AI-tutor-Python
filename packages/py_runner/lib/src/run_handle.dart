part of 'py_runner.dart';

/// Terminal state of a run.
enum RunStatus { ok, error, cancelled }

/// Mirror of an [ExceptionFrame] for the public API.
class PyException {
  const PyException({
    required this.type,
    required this.message,
    required this.traceback,
  });

  /// Exception class name from the host (e.g. `ZeroDivisionError`).
  final String type;

  /// `str(exc)` from the host.
  final String message;

  /// Formatted traceback, already trimmed by host.py to start at the first
  /// `<student>` frame.
  final String traceback;

  @override
  String toString() => 'PyException($type: $message)';
}

/// Mirror of an [InputRequestFrame] for the public API. Reserved for step 10.
class InputRequest {
  const InputRequest({required this.requestId, required this.prompt});

  final int requestId;
  final String prompt;
}

/// Result delivered when a run terminates.
class RunResult {
  const RunResult({
    required this.status,
    required this.duration,
    this.exception,
  });

  final RunStatus status;
  final Duration duration;

  /// Populated when [status] is [RunStatus.error].
  final PyException? exception;

  @override
  String toString() =>
      'RunResult(status: $status, duration: $duration, exception: $exception)';
}

/// Streaming handle for a single Python run.
///
/// Streams are broadcast and *not* pre-buffered: late subscribers miss
/// already-emitted lines. The `OutputService` adapter (step 7) pins
/// subscriptions immediately on `run` to avoid this.
class RunHandle {
  RunHandle._(this._controller);

  final _RunController _controller;

  /// UUID v4 minted by [PyRunner.run], echoed in every wire frame for this run.
  String get id => _controller.id;

  Stream<String> get stdout => _controller._stdout.stream;
  Stream<String> get stderr => _controller._stderr.stream;

  /// Empty in v1 — host.py never emits `input_request` until step 10.
  Stream<InputRequest> get inputRequests => _controller._inputRequests.stream;

  /// Resolves when the host emits `done`, or when the run is synthesised as
  /// terminal because the host crashed.
  Future<RunResult> get done => _controller._done.future;

  /// Reply to an [InputRequest]. No-op once the run is terminal.
  void respondToInput(int requestId, String value) {
    _controller._respondToInput(requestId, value);
  }

  /// Request cancellation. Resolves when [done] does — with status
  /// [RunStatus.cancelled] if the cancel landed before the worker finished.
  Future<void> cancel() => _controller._cancel();
}

/// Internal state machine for one run. Owns the broadcast controllers and the
/// done completer; [RunHandle] is a thin read-only view.
class _RunController {
  _RunController({required this.id, required this._sendFrame}) {
    handle = RunHandle._(this);
  }

  final String id;
  final void Function(HostInboundFrame frame) _sendFrame;

  final _stdout = StreamController<String>.broadcast();
  final _stderr = StreamController<String>.broadcast();
  final _inputRequests = StreamController<InputRequest>.broadcast();
  final _done = Completer<RunResult>();

  late final RunHandle handle;

  PyException? _pendingException;
  bool _execSent = false;
  bool _cancelRequested = false;

  bool get isDone => _done.isCompleted;
  bool get cancelRequested => _cancelRequested;

  void _markExecSent() {
    _execSent = true;
  }

  void _onStdout(String text) {
    if (!_stdout.isClosed) _stdout.add(text);
  }

  void _onStderr(String text) {
    if (!_stderr.isClosed) _stderr.add(text);
  }

  void _onInputRequest(InputRequestFrame frame) {
    if (_inputRequests.isClosed) return;
    _inputRequests.add(
      InputRequest(requestId: frame.requestId, prompt: frame.prompt),
    );
  }

  void _onException(ExceptionFrame frame) {
    _pendingException = PyException(
      type: frame.excType,
      message: frame.message,
      traceback: frame.traceback,
    );
  }

  void _onDone(DoneFrame frame) {
    if (_done.isCompleted) return;
    _done.complete(
      RunResult(
        status: switch (frame.status) {
          DoneStatus.ok => RunStatus.ok,
          DoneStatus.error => RunStatus.error,
          DoneStatus.cancelled => RunStatus.cancelled,
        },
        duration: Duration(milliseconds: frame.durationMs),
        exception: _pendingException,
      ),
    );
    _closeStreams();
  }

  /// Forces a terminal state without a wire frame. Used when the run is
  /// cancelled before its `exec` was ever sent, or when the host process
  /// exits unexpectedly.
  void _synthesizeDone(RunStatus status, {PyException? exception}) {
    if (_done.isCompleted) return;
    _done.complete(
      RunResult(
        status: status,
        duration: Duration.zero,
        exception: exception ?? _pendingException,
      ),
    );
    _closeStreams();
  }

  void _respondToInput(int requestId, String value) {
    if (_done.isCompleted) return;
    _sendFrame(InputResponseFrame(id: id, requestId: requestId, value: value));
  }

  Future<void> _cancel() async {
    if (_done.isCompleted) return;
    _requestCancel();
    try {
      await _done.future;
    } catch (_) {
      // The handle's caller will observe via [done] directly if it cares.
    }
  }

  void _requestCancel() {
    if (_cancelRequested) return;
    _cancelRequested = true;
    if (_execSent && !_done.isCompleted) {
      _sendFrame(CancelFrame(id: id));
    }
    // If the exec hasn't been sent yet, [PyRunner._scheduleStart] sees
    // [_cancelRequested] when our turn comes up and synthesises a cancelled
    // done instead of sending the exec.
  }

  void _closeStreams() {
    if (!_stdout.isClosed) _stdout.close();
    if (!_stderr.isClosed) _stderr.close();
    if (!_inputRequests.isClosed) _inputRequests.close();
  }
}
