// Issue #13 — the lesson document wrapper must ship the live-preview
// bootstrap and speak a well-defined JSON protocol with the page.

import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:ai_tutor_python/widgets/lesson_document.dart';
import 'package:flutter_test/flutter_test.dart';

const _labels = LessonRunnerLabels(
  output: 'Output',
  run: 'Run',
  running: 'Running…',
  unavailable: 'Only in the app.',
);

void main() {
  group('buildLessonDocument', () {
    test('wraps the fragment with the stylesheet and the runner script', () {
      final doc = buildLessonDocument(
        fragment: '<p>hi</p><pre class="run"><code>print(1)</code></pre>',
        css: 'body{color:red}',
        labels: _labels,
      );

      expect(doc, startsWith('<!doctype html>'));
      expect(doc, contains('<style>body{color:red}</style>'));
      expect(doc, contains('<body class="lesson"><p>hi</p>'));
      expect(doc, contains('<pre class="run"><code>print(1)</code></pre>'));
      // The bootstrap sits after the fragment so the blocks exist when it
      // runs, and it targets exactly the authored class.
      expect(
        doc.indexOf('<script>'),
        greaterThan(doc.indexOf('<pre class="run">')),
      );
      expect(doc, contains("querySelectorAll('pre.run')"));
      expect(doc, contains("var CHANNEL = 'LessonRunner'"));
      expect(doc, contains('window.__lessonRunDeliver = function'));
    });

    test('labels reach the page as a JSON literal', () {
      final doc = buildLessonDocument(fragment: '', css: '', labels: _labels);
      expect(
        doc,
        contains(
          '{"output":"Output","run":"Run","running":"Running…",'
          '"unavailable":"Only in the app."}',
        ),
      );
    });

    test('a label containing </script> cannot close the script block', () {
      final doc = buildLessonDocument(
        fragment: '',
        css: '',
        labels: const LessonRunnerLabels(
          output: '</script><b>x</b>',
          run: 'r',
          running: 'r',
          unavailable: 'u',
        ),
      );
      expect(doc, isNot(contains('</script><b>')));
      expect(doc, contains(r'<\/script><b>'));
    });
  });

  group('LessonRunRequest.tryParse', () {
    test('accepts the page payload', () {
      final req = LessonRunRequest.tryParse(
        '{"id":"run-2","code":"print(\\"a\\")\\nprint(2)"}',
      );
      expect(req, isNotNull);
      expect(req!.id, 'run-2');
      expect(req.code, 'print("a")\nprint(2)');
    });

    test('rejects malformed payloads', () {
      expect(LessonRunRequest.tryParse('not json'), isNull);
      expect(LessonRunRequest.tryParse('[1,2]'), isNull);
      expect(LessonRunRequest.tryParse('{"id":1,"code":"x"}'), isNull);
      expect(LessonRunRequest.tryParse('{"id":"a"}'), isNull);
    });
  });

  test('lessonRunDeliverJs hands the result to the right block', () {
    final js = lessonRunDeliverJs(
      'run-0',
      const LessonRunResult(stdout: 'Hallo "Mira"\n', stderr: ''),
    );
    expect(
      js,
      'window.__lessonRunDeliver("run-0", '
      '{"stdout":"Hallo \\"Mira\\"\\n","stderr":""});',
    );
  });
}
