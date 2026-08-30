import 'dart:convert';

import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';

/// Name of the JavaScript channel the lesson page posts run requests on.
/// The Windows WebView exposes it as `window.LessonRunner.postMessage`.
const String kLessonRunnerChannel = 'LessonRunner';

/// CSS class an author puts on a `<pre>` to get a live preview of its
/// output: `<pre class="run"><code>print(1)</code></pre>` (#13).
const String kLessonRunClass = 'run';

/// UI strings injected into the lesson page for the live-preview blocks.
/// Resolved from `AppLocalizations` by the host widget — the page itself
/// has no access to Flutter's localisation.
class LessonRunnerLabels {
  const LessonRunnerLabels({
    required this.output,
    required this.run,
    required this.running,
    required this.unavailable,
  });

  /// Header above the captured output ("Output").
  final String output;

  /// Button that re-runs the example ("Run").
  final String run;

  /// Placeholder while a run is in flight ("Running…").
  final String running;

  /// Shown when the page has no bridge to the app (opened outside it).
  final String unavailable;

  Map<String, String> toJson() => {
    'output': output,
    'run': run,
    'running': running,
    'unavailable': unavailable,
  };
}

/// One run request as posted by the page: which block, and its code.
class LessonRunRequest {
  const LessonRunRequest({required this.id, required this.code});

  final String id;
  final String code;

  /// Parses the JSON the page posts on [kLessonRunnerChannel]. Returns null
  /// for anything that isn't a well-formed request.
  static LessonRunRequest? tryParse(String message) {
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map) return null;
      final id = decoded['id'];
      final code = decoded['code'];
      if (id is! String || code is! String) return null;
      return LessonRunRequest(id: id, code: code);
    } on FormatException {
      return null;
    }
  }
}

/// Wraps an authored body [fragment] in the minimal lesson document: the
/// shared stylesheet inlined, plus the live-preview bootstrap that turns
/// every `pre.run` block into a code + output pair.
String buildLessonDocument({
  required String fragment,
  required String css,
  required LessonRunnerLabels labels,
}) {
  return '<!doctype html>'
      '<html><head>'
      '<meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width,initial-scale=1">'
      '<style>$css</style>'
      '</head>'
      '<body class="lesson">$fragment'
      '<script>${lessonRunnerScript(labels)}</script>'
      '</body>'
      '</html>';
}

/// JavaScript that Dart runs inside the page to hand a finished run back
/// to the block that asked for it.
String lessonRunDeliverJs(String id, LessonRunResult result) {
  return 'window.__lessonRunDeliver('
      '${_jsLiteral(id)}, ${_jsLiteral(result.toJson())});';
}

/// The in-page bootstrap. Kept as one self-contained IIFE so the authored
/// fragment stays inert HTML; only the app adds behaviour.
String lessonRunnerScript(LessonRunnerLabels labels) {
  final labelsJs = _jsLiteral(labels.toJson());
  return '''
(function () {
  var CHANNEL = '$kLessonRunnerChannel';
  var LABELS = $labelsJs;
  var blocks = {};

  function post(id, code) {
    var bridge = window[CHANNEL];
    if (!bridge || typeof bridge.postMessage !== 'function') return false;
    bridge.postMessage(JSON.stringify({ id: id, code: code }));
    return true;
  }

  function setup(pre, index) {
    var id = 'run-' + index;
    var codeEl = pre.querySelector('code');
    var code = (codeEl || pre).textContent;

    var box = document.createElement('div');
    box.className = 'run-output';
    box.setAttribute('data-run-id', id);

    var head = document.createElement('div');
    head.className = 'run-output-head';
    var label = document.createElement('span');
    label.className = 'run-output-label';
    label.textContent = LABELS.output;
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'run-btn';
    btn.textContent = LABELS.run;
    head.appendChild(label);
    head.appendChild(btn);

    var body = document.createElement('pre');
    body.className = 'run-output-body';

    box.appendChild(head);
    box.appendChild(body);
    pre.insertAdjacentElement('afterend', box);

    var block = { box: box, body: body, btn: btn, code: code };
    blocks[id] = block;

    function start() {
      box.classList.remove('error');
      box.classList.add('running');
      btn.disabled = true;
      body.textContent = LABELS.running;
      if (!post(id, code)) {
        box.classList.remove('running');
        body.textContent = LABELS.unavailable;
      }
    }

    btn.addEventListener('click', start);
    start();
  }

  window.__lessonRunDeliver = function (id, result) {
    var block = blocks[id];
    if (!block) return;
    block.box.classList.remove('running');
    block.btn.disabled = false;
    var text = result.stdout || '';
    if (result.stderr) {
      block.box.classList.add('error');
      text = text ? text + '\\n' + result.stderr : result.stderr;
    }
    block.body.textContent = text;
  };

  var pres = document.querySelectorAll('pre.$kLessonRunClass');
  for (var i = 0; i < pres.length; i++) setup(pres[i], i);
})();
''';
}

/// JSON-encodes [value] for embedding in a `<script>` block or a
/// `runJavaScript` call. `</` is escaped so a stray `</script>` inside a
/// string can't terminate the block early.
String _jsLiteral(Object? value) {
  return jsonEncode(value).replaceAll('</', r'<\/');
}
