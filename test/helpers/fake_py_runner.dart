// Scripted stand-in for the bundled Python host, for tests that need to
// drive a run (Run → output → Stop) without the interpreter being installed
// on the machine. The run never finishes on its own — which is exactly the
// shape of a turtle program blocked in `turtle.done()` (#51) — until the test
// completes it or cancels it.

import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:py_runner/py_runner.dart';

class FakeRunHandle extends Fake implements RunHandle {
  final _stdout = StreamController<String>.broadcast();
  final _stderr = StreamController<String>.broadcast();
  final _inputRequests = StreamController<InputRequest>.broadcast();
  final _done = Completer<RunResult>();

  /// Every `respondToInput` the service sent, as `(requestId, value)`.
  final List<({int requestId, String value})> inputResponses = [];

  bool cancelled = false;

  @override
  String get id => 'fake-run';

  @override
  Stream<String> get stdout => _stdout.stream;

  @override
  Stream<String> get stderr => _stderr.stream;

  @override
  Stream<InputRequest> get inputRequests => _inputRequests.stream;

  @override
  Future<RunResult> get done => _done.future;

  @override
  void respondToInput(int requestId, String value) {
    inputResponses.add((requestId: requestId, value: value));
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
    complete(
      const RunResult(status: RunStatus.cancelled, duration: Duration.zero),
    );
  }

  void emitStdout(String text) => _stdout.add(text);

  void emitStderr(String text) => _stderr.add(text);

  void complete(RunResult result) {
    if (!_done.isCompleted) _done.complete(result);
  }

  Future<void> dispose() async {
    complete(const RunResult(status: RunStatus.ok, duration: Duration.zero));
    await _stdout.close();
    await _stderr.close();
    await _inputRequests.close();
  }
}

class FakePyRunner extends Fake implements PyRunner {
  /// Source of every run the app asked for, in order.
  final List<String> ran = [];

  /// The handles handed out, in order.
  final List<FakeRunHandle> handles = [];

  FakeRunHandle get lastHandle => handles.last;

  @override
  Future<void> start() async {}

  @override
  RunHandle run(String code, {String? cwd, Duration? timeout}) {
    ran.add(code);
    final handle = FakeRunHandle();
    handles.add(handle);
    return handle;
  }

  Future<void> dispose() async {
    for (final handle in handles) {
      await handle.dispose();
    }
  }
}
