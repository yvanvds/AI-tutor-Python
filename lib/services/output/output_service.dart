import 'dart:async';

import 'package:ai_tutor_python/services/output/output_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:py_runner/py_runner.dart';

class OutputLine {
  const OutputLine(this.text, {this.isError = false, this.isMeta = false});

  final String text;
  final bool isError;
  final bool isMeta;
}

class OutputService {
  OutputService({required PyRunner pyRunner}) : _pyRunner = pyRunner;

  final PyRunner _pyRunner;
  final OutputController _controller = OutputController();

  OutputController get controller => _controller;

  final ValueNotifier<List<OutputLine>> lines = ValueNotifier([]);
  final ValueNotifier<bool> isRunning = ValueNotifier(false);
  final ValueNotifier<InputRequest?> pendingInputRequest = ValueNotifier(null);

  RunHandle? _currentHandle;
  final List<StreamSubscription<dynamic>> _runSubs = [];

  // Python's `print` calls write() once per argument, once per separator,
  // and once for the trailing newline — so a single `print("a", "b")`
  // arrives here as four chunks. Buffer per stream and split on '\n'.
  final StringBuffer _stdoutBuf = StringBuffer();
  final StringBuffer _stderrBuf = StringBuffer();

  Future<void> run(String code) async {
    for (final sub in _runSubs) {
      await sub.cancel();
    }
    _runSubs.clear();

    lines.value = [];
    _stdoutBuf.clear();
    _stderrBuf.clear();
    isRunning.value = true;

    final RunHandle handle;
    try {
      await _pyRunner.start();
      // `run` throws synchronously when the host died between `start`
      // resolving and the exec being sent (#7); without the guard that
      // StateError escaped the Run button's tap handler.
      handle = _pyRunner.run(code);
    } catch (e) {
      _pushLine('[Python host error] $e', isError: true);
      isRunning.value = false;
      return;
    }
    _currentHandle = handle;

    _runSubs.add(handle.stdout.listen((t) => _appendChunk(t, isError: false)));
    _runSubs.add(handle.stderr.listen((t) => _appendChunk(t, isError: true)));
    _runSubs.add(
      handle.inputRequests.listen((req) {
        pendingInputRequest.value = req;
      }),
    );

    final capturedHandle = handle;
    unawaited(() async {
      try {
        final result = await handle.done;
        if (!identical(_currentHandle, capturedHandle)) return;
        _flushBuffers();
        final exception = result.exception;
        if (exception != null) {
          if (exception.traceback.isNotEmpty) {
            _appendChunk(exception.traceback, isError: true);
            _flushBuffers();
          } else {
            // Synthesised by py_runner when the host process died mid-run
            // (`HostExited`) or was no longer ready: there is no Python
            // traceback, so without this the run just stopped silently
            // and the panel reported "Done" (#7).
            _pushLine(
              '[Python host error] ${exception.type}: ${exception.message}',
              isError: true,
            );
          }
        }
        pendingInputRequest.value = null;
        isRunning.value = false;
      } catch (e) {
        if (!identical(_currentHandle, capturedHandle)) return;
        _pushLine('[Python host error] $e', isError: true);
        pendingInputRequest.value = null;
        isRunning.value = false;
      }
    }());
  }

  Future<void> stop() async {
    pendingInputRequest.value = null;
    await _currentHandle?.cancel();
  }

  void submitInput(String value) {
    final req = pendingInputRequest.value;
    if (req == null) return;
    pendingInputRequest.value = null;
    _currentHandle?.respondToInput(req.requestId, value);
  }

  /// Clear collected output without affecting an in-flight run. Used by the
  /// "Reset" button in the redesigned RunControls.
  void clear() {
    lines.value = [];
    _stdoutBuf.clear();
    _stderrBuf.clear();
  }

  void _appendChunk(String text, {required bool isError}) {
    if (text.isEmpty) return;
    final buf = isError ? _stderrBuf : _stdoutBuf;
    buf.write(text);
    final combined = buf.toString();
    final lastNl = combined.lastIndexOf('\n');
    if (lastNl < 0) return;
    final complete = combined.substring(0, lastNl);
    buf
      ..clear()
      ..write(combined.substring(lastNl + 1));
    final added = <OutputLine>[
      for (final line in complete.split('\n'))
        OutputLine(line, isError: isError),
    ];
    lines.value = [...lines.value, ...added];
  }

  void _flushBuffers() {
    final stdoutRemaining = _stdoutBuf.toString();
    final stderrRemaining = _stderrBuf.toString();
    _stdoutBuf.clear();
    _stderrBuf.clear();
    final added = <OutputLine>[];
    if (stdoutRemaining.isNotEmpty) {
      added.add(OutputLine(stdoutRemaining));
    }
    if (stderrRemaining.isNotEmpty) {
      added.add(OutputLine(stderrRemaining, isError: true));
    }
    if (added.isNotEmpty) {
      lines.value = [...lines.value, ...added];
    }
  }

  void _pushLine(String text, {bool isError = false}) {
    _flushBuffers();
    final trimmed = text.trimRight();
    if (trimmed.isEmpty) return;
    lines.value = [...lines.value, OutputLine(trimmed, isError: isError)];
  }
}

final outputServiceProvider = Provider<OutputService>((ref) {
  final service = OutputService(
    pyRunner: PyRunner(locator: const InstallerPyHostLocator()),
  );
  ref.onDispose(() async {
    await service.stop();
  });
  return service;
});
