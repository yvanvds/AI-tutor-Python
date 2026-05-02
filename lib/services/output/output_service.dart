import 'dart:async';

import 'package:ai_tutor_python/services/output/output_controller.dart';
import 'package:flutter/foundation.dart';
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

  RunHandle? _currentHandle;
  final List<StreamSubscription<dynamic>> _runSubs = [];

  Future<void> run(String code) async {
    for (final sub in _runSubs) {
      await sub.cancel();
    }
    _runSubs.clear();

    lines.value = [const OutputLine('▶ Running…', isMeta: true)];
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

    final capturedHandle = handle;
    unawaited(() async {
      try {
        final result = await handle.done;
        if (!identical(_currentHandle, capturedHandle)) return;
        if (result.exception != null) {
          _addLine(result.exception!.traceback, isError: true);
        }
        isRunning.value = false;
      } catch (_) {
        if (!identical(_currentHandle, capturedHandle)) return;
        isRunning.value = false;
      }
    }());
  }

  Future<void> stop() async {
    await _currentHandle?.cancel();
  }

  void _addLine(String text, {bool isError = false}) {
    if (text.isEmpty) return;
    lines.value = [...lines.value, OutputLine(text, isError: isError)];
  }
}
