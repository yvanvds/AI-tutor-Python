// #132 — the theory page goes to the model as text. A lesson body is the
// HTML fragment the WebView renders; `lessonHtmlToText` turns it into what
// a reader sees: fenced code for the `<pre>` blocks (the live examples of
// #13 included), `- ` lines for list items, headings on their own line, no
// tags, no entities, no runs of blanks — and never more than the cap.

import 'package:ai_tutor_python/services/content/lesson_html_to_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a run block and a plain pre both become fenced code, with their '
      'newlines and indentation kept and inner markup dropped', () {
    final text = lessonHtmlToText(
      '<h2>Print</h2>'
      '<p>Zo toon je iets op het scherm.</p>'
      '<pre class="run"><code>naam = "Mira"\nprint("Hallo", naam)</code></pre>'
      '<pre><code><span class="kw">for</span> i in range(3):\n'
      '    print(i)</code></pre>',
    );
    expect(
      text,
      '## Print\n'
      '\n'
      'Zo toon je iets op het scherm.\n'
      '\n'
      '```\n'
      'naam = "Mira"\n'
      'print("Hallo", naam)\n'
      '```\n'
      '\n'
      '```\n'
      'for i in range(3):\n'
      '    print(i)\n'
      '```',
    );
  });

  test('inline code is backticked and entities inside it are decoded', () {
    expect(
      lessonHtmlToText('<p>Gebruik <code>a &lt; b</code> voor kleiner.</p>'),
      'Gebruik `a < b` voor kleiner.',
    );
  });

  test('list items become dash lines; headings of every level get their '
      'own line', () {
    final text = lessonHtmlToText(
      '<h1>Titel</h1>'
      '<ul><li>een</li><li>twee <b>vet</b></li></ul>'
      '<h3>Sub</h3>'
      '<ol><li>eerst</li><li>dan</li></ol>',
    );
    expect(
      text,
      '# Titel\n'
      '\n'
      '- een\n'
      '- twee vet\n'
      '\n'
      '### Sub\n'
      '\n'
      '- eerst\n'
      '- dan',
    );
  });

  test('tags, comments, scripts and styles are gone; entities are decoded '
      'once; blanks and blank lines collapse', () {
    final text = lessonHtmlToText(
      '<!-- authoring note -->'
      '<style>p { color: red }</style>'
      '<script>alert(1)</script>'
      '<p>Tom &amp; Jerry&nbsp;&mdash;   &quot;hi&quot; &#65;&#x42; '
      '&amp;lt;</p>\n\n\n\n'
      '<div><p>Twee<br>regels</p></div>'
      '<p>&unknown; blijft</p>',
    );
    expect(
      text,
      'Tom & Jerry — "hi" AB &lt;\n'
      '\n'
      'Twee\n'
      'regels\n'
      '\n'
      '&unknown; blijft',
    );
    expect(text, isNot(contains('<')));
    expect(text, isNot(contains('alert')));
    expect(text, isNot(contains('color')));
  });

  test('the cap holds: a long page is cut to maxChars and ends in the '
      'marker; a short one is untouched', () {
    final paragraphs = List.generate(
      400,
      (i) => '<p>Alinea $i met wat tekst erin.</p>',
    ).join();
    final full = lessonHtmlToText(paragraphs);
    expect(full.length, greaterThan(100));

    final capped = lessonHtmlToText(paragraphs, maxChars: 100);
    expect(capped.length, lessThanOrEqualTo(100));
    expect(capped, endsWith(kContentTruncationMarker));
    expect(capped, startsWith('Alinea 0 met wat tekst erin.'));

    expect(
      lessonHtmlToText(paragraphs, maxChars: full.length),
      full,
      reason: 'a page that fits is not cut',
    );
    expect(kContentQuestionMaxChars, 12000);
  });

  test('windows line endings and tag case do not matter', () {
    expect(
      lessonHtmlToText('<P>Een</P>\r\n<PRE>x = 1\r\ny = 2</PRE>'),
      'Een\n\n```\nx = 1\ny = 2\n```',
    );
  });

  test('an empty or whitespace-only page is the empty string', () {
    expect(lessonHtmlToText(''), '');
    expect(lessonHtmlToText('<p>  </p>\n<div></div>'), '');
  });
}
