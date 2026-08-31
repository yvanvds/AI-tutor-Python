import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:py_runner/py_runner.dart';

/// Captured output of one lesson example run (#13).
class LessonRunResult {
  const LessonRunResult({this.stdout = '', this.stderr = ''});

  final String stdout;
  final String stderr;

  bool get hasError => stderr.isNotEmpty;

  Map<String, String> toJson() => {'stdout': stdout, 'stderr': stderr};
}

/// Executes the Python inside a lesson's `<pre class="run">` block and
/// returns what it printed. The lesson WebView asks for one run per block
/// when the page loads (and again when the student presses the block's
/// run button); the result is pushed back into the page under the code.
abstract class LessonCodeRunner {
  Future<LessonRunResult> run(String code);
}

/// [LessonCodeRunner] backed by a [PyRunner]. Runs are serialised because
/// `PyRunner.run` cancels whatever is still in flight, and a lesson with
/// several examples fires all of them at once on load.
class PyLessonCodeRunner implements LessonCodeRunner {
  PyLessonCodeRunner({
    required this._pyRunner,
    this.timeout = const Duration(seconds: 10),
  });

  final PyRunner _pyRunner;

  /// Upper bound per example — a lesson must never hang on a stray loop.
  final Duration timeout;

  Future<void> _chain = Future.value();

  @override
  Future<LessonRunResult> run(String code) {
    final next = _chain.then((_) => _runOne(code));
    _chain = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<LessonRunResult> _runOne(String code) async {
    final RunHandle handle;
    try {
      await _pyRunner.start();
      // `run` throws synchronously if the host died right after `start`
      // resolved (#7); the lesson page must get a result either way.
      handle = _pyRunner.run(code, timeout: timeout);
    } catch (e) {
      return LessonRunResult(stderr: '[Python host error] $e');
    }
    final out = StringBuffer();
    final err = StringBuffer();
    final subs = <StreamSubscription<dynamic>>[
      handle.stdout.listen(out.write),
      handle.stderr.listen(err.write),
      // A lesson example has no keyboard; answer `input()` with an empty
      // line so the run terminates instead of waiting forever.
      handle.inputRequests.listen(
        (req) => handle.respondToInput(req.requestId, ''),
      ),
    ];

    try {
      final result = await handle.done;
      if (result.exception != null) {
        final tb = result.exception!.traceback;
        err.write(
          tb.isNotEmpty
              ? tb
              : '${result.exception!.type}: ${result.exception!.message}',
        );
      }
    } catch (e) {
      err.write('$e');
    } finally {
      for (final s in subs) {
        await s.cancel();
      }
    }

    return LessonRunResult(
      stdout: out.toString().trimRight(),
      stderr: err.toString().trimRight(),
    );
  }
}

/// Own Python host for lesson examples, separate from the practice editor's
/// [OutputService] host so a lesson loading never cancels a student's run.
final lessonCodeRunnerProvider = Provider<LessonCodeRunner>((ref) {
  final pyRunner = PyRunner(
    locator: const InstallerPyHostLocator(devMode: kDebugMode),
  );
  ref.onDispose(() async {
    await pyRunner.shutdown();
  });
  return PyLessonCodeRunner(pyRunner: pyRunner);
});
