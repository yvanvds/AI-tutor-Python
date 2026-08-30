import 'dart:async';

import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';

/// Scripted [LessonCodeRunner]: records what it was asked to run and
/// answers from [results] (keyed by exact code), or with an empty result.
/// With [manual] the run stays pending until [complete] is called, so a
/// test can observe the in-flight state.
class FakeLessonCodeRunner implements LessonCodeRunner {
  FakeLessonCodeRunner({this.results = const {}, this.manual = false});

  final Map<String, LessonRunResult> results;
  final bool manual;

  final List<String> ran = [];
  final List<Completer<LessonRunResult>> _pending = [];

  @override
  Future<LessonRunResult> run(String code) {
    ran.add(code);
    if (!manual) {
      return Future.value(results[code] ?? const LessonRunResult());
    }
    final c = Completer<LessonRunResult>();
    _pending.add(c);
    return c.future;
  }

  /// Completes the oldest pending manual run.
  void complete(LessonRunResult result) {
    _pending.removeAt(0).complete(result);
  }
}
