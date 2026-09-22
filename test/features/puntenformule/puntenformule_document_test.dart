// #129: `docs/PUNTENFORMULE.md` ships inside the app and is converted to
// HTML at load time. This reads the document the way the app does — through
// the asset bundle, so a missing `pubspec.yaml` entry fails here and not on
// a student's screen — and checks the conversion keeps every structure the
// document relies on. The guard the issue asks for: a future edit that
// breaks a table (a misaligned separator row, a lost pipe) leaves pipe text
// in a paragraph instead of a `<table>`, and this test says so.

import 'package:ai_tutor_python/features/puntenformule/puntenformule_page.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String source;
  late String html;

  setUpAll(() async {
    source = await rootBundle.loadString(kPuntenformuleAssetKey);
    html = puntenformuleToHtml(source);
  });

  test('the bundled document is the students\' one, with its version line', () {
    expect(source, startsWith('# Puntenformule'));
    expect(html, contains('<h1'));
    expect(html, contains('<strong>Versie '));
  });

  test('the version log and the header date agree (§5)', () {
    // §5: every edit to the document gets a new version number *and* a row
    // in the log, and the header's "Laatste wijziging" is that row's date.
    // A bump that forgets one of the two would otherwise only be noticed by
    // a student reading a document that dates itself wrong.
    final rows = RegExp(
      r'^\|\s*(\d+\.\d+(?:\.\d+)?)\s*\|\s*(\d{4}-\d{2}-\d{2})\s*\|',
      multiLine: true,
    ).allMatches(source).toList();
    expect(rows.length, greaterThan(1), reason: 'the version log went missing');

    final versions = rows.map((m) => m.group(1)!).toList();
    expect(
      versions.toSet().length,
      versions.length,
      reason: 'two log rows claim the same version: $versions',
    );

    // Highest version wins, not last row: the log is append-ordered by hand
    // and has been out of order before.
    List<int> parts(String v) {
      final p = v.split('.').map(int.parse).toList();
      return [...p, ...List<int>.filled(3 - p.length, 0)];
    }

    var newest = rows.first;
    for (final row in rows.skip(1)) {
      final a = parts(row.group(1)!);
      final b = parts(newest.group(1)!);
      for (var i = 0; i < 3; i++) {
        if (a[i] != b[i]) {
          if (a[i] > b[i]) newest = row;
          break;
        }
      }
    }

    expect(
      source,
      contains('Laatste wijziging: ${newest.group(2)}.'),
      reason:
          'the header date is not the date of the newest log row '
          '(${newest.group(1)}, ${newest.group(2)})',
    );
  });

  test('every pipe table in the source becomes a <table>', () {
    // One separator row (`| --- | --- |`) per table.
    final separators = RegExp(
      r'^\|\s*-{3,}',
      multiLine: true,
    ).allMatches(source).length;
    expect(separators, greaterThan(0), reason: 'the document lost its tables');
    expect('<table>'.allMatches(html).length, separators);
    expect(html, contains('<th>'));
    expect(html, contains('<td>'));
    // Nothing leaked through as text: a paragraph never starts a line with
    // the pipe a broken table would leave behind.
    expect(
      RegExp(r'<p>[^<]*^\|', multiLine: true).hasMatch(html),
      isFalse,
      reason: 'a pipe row rendered as paragraph text',
    );
  });

  test('every fenced formula block becomes an inert <pre><code>', () {
    final fences = RegExp(r'^```', multiLine: true).allMatches(source).length;
    expect(fences, greaterThan(0));
    expect(fences.isEven, isTrue, reason: 'an unclosed fence in the source');
    expect('<pre><code>'.allMatches(html).length, fences ~/ 2);
    // Only `<pre class="run">` gets a live-preview pane; the converter must
    // never produce one, and the document has no scripts of its own.
    expect(html, isNot(contains('class="run"')));
    expect(html, isNot(contains('<script')));
  });

  test('headings, lists, rules and the formula glyphs survive', () {
    expect(html, contains('<h2'));
    expect(html, contains('<h3'));
    expect(html, contains('<ol>'));
    expect(html, contains('<ul>'));
    expect(html, contains('<hr />'));
    for (final glyph in ['μ', 'α', 'β', '→', '≈', '×']) {
      expect(html, contains(glyph), reason: 'lost "$glyph"');
    }
  });
}
