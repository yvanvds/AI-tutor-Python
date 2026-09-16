// #127 — the bug report as a file: a heading over the unchanged issue body,
// and a file name that says what and when.

import 'package:ai_tutor_python/services/debug/bug_report_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Local time, so the stamp below is what a machine in any timezone shows
  // for its own clock — the formatter must not shift it to UTC.
  final at = DateTime(2026, 9, 15, 14, 3, 59);

  group('buildBugReportFile', () {
    test('puts a title, a local timestamp and the version over the body', () {
      final file = buildBugReportFile(
        title: '  The Run button did nothing ',
        reportedAt: at,
        appVersion: '2.3.0+20',
        body: 'It stopped.\n\n---\nApp version: `2.3.0+20`\n',
      );

      expect(
        file,
        '# The Run button did nothing\n'
        'Reported: 2026-09-15 14:03  ·  App version 2.3.0+20\n'
        '\n'
        'It stopped.\n\n---\nApp version: `2.3.0+20`\n',
      );
    });

    test('the body is passed through untouched', () {
      const body =
          '<details>\n<summary>Turn debug payload</summary>\n'
          '```json\n{"mean": "<redacted>"}\n```\n</details>\n';
      final file = buildBugReportFile(
        title: 't',
        reportedAt: at,
        appVersion: '1.0.0',
        body: body,
      );
      expect(file, endsWith('\n\n$body'));
    });

    // The body is already redacted by `buildBugReportBody`; the title is the
    // one field that used to bypass it, and a file the teacher pastes into
    // a public issue must not carry the student's profile name either.
    test('redacts a user path typed into the title', () {
      final file = buildBugReportFile(
        title: r'cannot open C:\Users\sam.student\Desktop\x.py',
        reportedAt: at,
        appVersion: '1.0.0',
        body: '',
      );
      expect(file, startsWith(r'# cannot open C:\Users\<user>\Desktop\x.py'));
      expect(file, isNot(contains('sam.student')));
    });
  });

  group('bugReportFileName', () {
    test('is the date and a slug of the title, as .txt', () {
      expect(
        bugReportFileName(title: 'The Run button did nothing', reportedAt: at),
        'ai-tutor-bugreport-2026-09-15-the-run-button-did-nothing.txt',
      );
    });

    test('drops the slug when nothing of the title survives', () {
      expect(
        bugReportFileName(title: '???', reportedAt: at),
        'ai-tutor-bugreport-2026-09-15.txt',
      );
    });

    test('pads a single-digit month and day', () {
      expect(
        bugReportFileName(title: 'x', reportedAt: DateTime(2026, 1, 5, 9)),
        'ai-tutor-bugreport-2026-01-05-x.txt',
      );
    });
  });

  group('slugifyTitle', () {
    test('lower-cases, collapses runs of punctuation and space, trims', () {
      expect(slugifyTitle('  Hello,  World!! (again) '), 'hello-world-again');
    });

    test('drops non-ASCII rather than guessing at it', () {
      expect(slugifyTitle('Één fout: crash'), 'n-fout-crash');
    });

    test('caps the length without leaving a dangling dash', () {
      // 39 letters, a dash at position 40, then more: the cut lands on the
      // dash, which must not be left behind.
      final long = '${'a' * 39}-${'b' * 10}';
      expect(slugifyTitle(long), 'a' * 39);
      expect(slugifyTitle('a' * 50), 'a' * 40);
    });
  });

  group('formatReportStamp', () {
    test('is yyyy-MM-dd HH:mm, zero-padded', () {
      expect(formatReportStamp(DateTime(2026, 3, 7, 8, 5)), '2026-03-07 08:05');
    });
  });
}
