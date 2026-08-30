import 'dart:async';

import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
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

/// Whether [code] pulls in Python's `turtle` module, and so will open a Tk
/// window that lives outside the app and blocks the run until it is closed
/// (#51).
///
/// Deliberately syntactic and line-based: an `import`/`from` statement is
/// matched only at the start of a line, so `# import turtle` and a `turtle`
/// mentioned in a string or an identifier do not count.
bool codeImportsTurtle(String code) {
  for (final line in code.split('\n')) {
    final trimmed = line.trimLeft();
    final from = RegExp(r'^from\s+turtle\b').firstMatch(trimmed);
    if (from != null) return true;
    final import = RegExp(r'^import\s+(.+)$').firstMatch(trimmed);
    if (import == null) continue;
    for (final part in import.group(1)!.split(',')) {
      // `import turtle as t` / `import turtle.shapes` both count.
      final module = part.trim().split(RegExp(r'\s')).first;
      if (module == 'turtle' || module.startsWith('turtle.')) return true;
    }
  }
  return false;
}

class OutputService {
  OutputService({
    required PyRunner pyRunner,
    required AppLocalizations Function() localizations,
  }) : _pyRunner = pyRunner,
       _localizations = localizations;

  final PyRunner _pyRunner;

  /// Resolved per call rather than held, so a language switch mid-session
  /// reaches the next meta line. See `appLocalizationsProvider`.
  final AppLocalizations Function() _localizations;

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

    // Said up front, not on completion: a turtle program idiomatically ends
    // in `turtle.done()`, which blocks until the window is closed, so the run
    // legitimately sits there looking like a hang (#51).
    if (codeImportsTurtle(code)) {
      _pushLine(
        _localizations().session_output_meta_turtleWindow,
        isMeta: true,
      );
    }

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
    final handle = _currentHandle;
    if (handle == null) return;
    final wasRunning = isRunning.value;
    await handle.cancel();
    // Without this the panel is left exactly as blank as it was before Stop
    // was pressed (#51). Skipped when nothing was running — `stop()` is also
    // what the provider calls on dispose.
    if (wasRunning && identical(_currentHandle, handle)) {
      _pushLine(_localizations().session_output_meta_stopped, isMeta: true);
    }
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

  void _pushLine(String text, {bool isError = false, bool isMeta = false}) {
    _flushBuffers();
    final trimmed = text.trimRight();
    if (trimmed.isEmpty) return;
    lines.value = [
      ...lines.value,
      OutputLine(trimmed, isError: isError, isMeta: isMeta),
    ];
  }
}

/// The Python host behind [outputServiceProvider]. Split out from the service
/// so the end-to-end harness can drive Run/Stop without the bundled
/// interpreter; production always gets the real one.
final pyRunnerProvider = Provider<PyRunner>(
  (ref) => PyRunner(locator: const InstallerPyHostLocator()),
);

final outputServiceProvider = Provider<OutputService>((ref) {
  final service = OutputService(
    pyRunner: ref.watch(pyRunnerProvider),
    localizations: () => ref.read(appLocalizationsProvider),
  );
  ref.onDispose(() async {
    await service.stop();
  });
  return service;
});
