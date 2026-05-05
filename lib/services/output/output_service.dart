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

  Future<void> run(String code) async {
    for (final sub in _runSubs) {
      await sub.cancel();
    }
    _runSubs.clear();

    lines.value = [];
    isRunning.value = true;

    try {
      await _pyRunner.start();
    } catch (e) {
      _addLine('[Python host error] $e', isError: true);
      isRunning.value = false;
      return;
    }

    final handle = _pyRunner.run(code);
    _currentHandle = handle;

    _runSubs.add(handle.stdout.listen(_addLine));
    _runSubs.add(handle.stderr.listen((t) => _addLine(t, isError: true)));
    _runSubs.add(handle.inputRequests.listen((req) {
      pendingInputRequest.value = req;
    }));

    final capturedHandle = handle;
    unawaited(() async {
      try {
        final result = await handle.done;
        if (!identical(_currentHandle, capturedHandle)) return;
        if (result.exception != null) {
          _addLine(result.exception!.traceback, isError: true);
        }
        pendingInputRequest.value = null;
        isRunning.value = false;
      } catch (_) {
        if (!identical(_currentHandle, capturedHandle)) return;
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
  }

  void _addLine(String text, {bool isError = false}) {
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
