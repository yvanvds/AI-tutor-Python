// The theory page as text for the model (#132).
//
// A lesson body is an HTML fragment (`Content.body`, rendered in the WebView
// by `LessonHtmlView`). When the student asks a question about the page,
// the page goes along with the question — as text, not markup: tags cost
// tokens and tell the model nothing, and the `<pre class="run">` scaffolding
// of the live examples (#13) is a rendering detail. What survives is what a
// reader sees: headings on their own line, list items as `- ` lines, code
// blocks as fenced code, inline code in backticks, entities decoded,
// whitespace collapsed.
//
// A regex pass is enough: the input is teacher-authored lesson HTML from
// the Lesinhoud editor, not the open web, and there is no HTML parser in
// the dependency tree to reach for.

/// Longest page text sent with a content question, in characters. Lesson
/// pages are a few thousand characters; this bounds the tokens a page can
/// cost without ever cutting a real one.
const int kContentQuestionMaxChars = 12000;

/// Ellipsis appended when [lessonHtmlToText] has to cut a page short.
const String kContentTruncationMarker = '…';

/// Plain text of a lesson HTML [fragment], at most [maxChars] long.
///
/// - `<pre>` blocks (with or without an inner `<code>`) become fenced code
///   blocks; the code keeps its newlines and indentation and loses any
///   inline markup (a highlighter's `<span>`s, say).
/// - inline `<code>` becomes `` `code` ``.
/// - `<h1>`–`<h6>` become `#`-prefixed lines of their own.
/// - `<li>` becomes a `- ` line; `<br>` and block elements break the line.
/// - every other tag is dropped, comments and `<script>`/`<style>` bodies
///   with them; entities are decoded; runs of blanks collapse to one space
///   and runs of blank lines to one.
/// - a result longer than [maxChars] is cut and ends in
///   [kContentTruncationMarker]; the whole result is never longer than
///   [maxChars].
String lessonHtmlToText(
  String fragment, {
  int maxChars = kContentQuestionMaxChars,
}) {
  var s = fragment.replaceAll('\r\n', '\n');

  // What a reader never sees.
  s = s.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  s = s.replaceAll(
    RegExp(
      r'<(script|style)\b[^>]*>.*?</\1\s*>',
      caseSensitive: false,
      dotAll: true,
    ),
    '',
  );

  // Code blocks are lifted out first so the whitespace pass below leaves
  // their newlines and indentation alone.
  final blocks = <String>[];
  s = s.replaceAllMapped(
    RegExp(r'<pre\b[^>]*>(.*?)</pre\s*>', caseSensitive: false, dotAll: true),
    (m) {
      final code = _decodeEntities(_stripTags(m.group(1)!));
      blocks.add(code.trim());
      return '\n\n\u0000${blocks.length - 1}\u0000\n\n';
    },
  );

  s = s.replaceAllMapped(
    RegExp(r'<code\b[^>]*>(.*?)</code\s*>', caseSensitive: false, dotAll: true),
    (m) => '`${_stripTags(m.group(1)!)}`',
  );
  s = s.replaceAllMapped(
    RegExp(
      r'<h([1-6])\b[^>]*>(.*?)</h\1\s*>',
      caseSensitive: false,
      dotAll: true,
    ),
    (m) => '\n\n${'#' * int.parse(m.group(1)!)} ${m.group(2)!}\n\n',
  );

  // Line and paragraph breaks where the page shows them.
  s = s.replaceAll(RegExp(r'<li\b[^>]*>', caseSensitive: false), '\n- ');
  s = s.replaceAll(RegExp(r'</li\s*>', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<hr\s*/?>', caseSensitive: false), '\n\n');
  s = s.replaceAll(
    RegExp(r'</(tr|dt|dd|td|th)\s*>', caseSensitive: false),
    '\n',
  );
  s = s.replaceAll(
    RegExp(
      r'</?(p|div|section|article|aside|header|footer|main|nav|blockquote|'
      r'figure|figcaption|ul|ol|dl|table|thead|tbody|details|summary)\b'
      r'[^>]*>',
      caseSensitive: false,
    ),
    '\n\n',
  );
  s = _decodeEntities(_stripTags(s));

  // Prose whitespace: one space within a line, no blanks at line ends, one
  // blank line at most between paragraphs.
  s = s.replaceAll(RegExp(r'[ \t\u00a0]+'), ' ');
  s = s.replaceAll(RegExp(r' *\n *'), '\n');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');

  s = s
      .replaceAllMapped(
        RegExp('\u0000(\\d+)\u0000'),
        (m) => '```\n${blocks[int.parse(m.group(1)!)]}\n```',
      )
      .trim();

  if (s.length > maxChars) {
    final keep = maxChars - kContentTruncationMarker.length;
    s = s.substring(0, keep < 0 ? 0 : keep).trimRight();
    s = '$s$kContentTruncationMarker';
  }
  return s;
}

String _stripTags(String s) => s.replaceAll(RegExp(r'<[^>]*>'), '');

const Map<String, String> _namedEntities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': '\u00a0',
  'hellip': '…',
  'ndash': '–',
  'mdash': '—',
  'lsquo': '‘',
  'rsquo': '’',
  'ldquo': '“',
  'rdquo': '”',
  'euro': '€',
  'copy': '©',
};

/// One pass over `&name;`, `&#123;` and `&#x1F;`, so `&amp;lt;` decodes to
/// `&lt;` and not to `<`. An unknown name stays as written.
String _decodeEntities(String s) =>
    s.replaceAllMapped(RegExp(r'&(#[xX][0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (m) {
      final ref = m.group(1)!;
      if (ref.startsWith('#')) {
        final hex = ref[1] == 'x' || ref[1] == 'X';
        final code = int.tryParse(
          ref.substring(hex ? 2 : 1),
          radix: hex ? 16 : 10,
        );
        return code == null || code > 0x10FFFF
            ? m.group(0)!
            : String.fromCharCode(code);
      }
      return _namedEntities[ref.toLowerCase()] ?? m.group(0)!;
    });
