// A bug report as a file (#127).
//
// The GitHub path (#25, #57) needs a GitHub account, and for most students
// creating one is a bigger step than the bug is worth — so the reports did
// not come in. This is the other outcome of the same dialog: the report the
// issue would have carried, written to a `.txt` the student sends to the
// teacher over chat. The body is `buildBugReportBody`'s output, unchanged —
// same runner section, same turn payload, same redaction, because the
// teacher may paste the file straight into a public issue. Only a heading
// is added, so a file on its own says what it is and when it was taken.
//
// `.txt` rather than `.md`: it opens anywhere and every chat client attaches
// it without fuss. The content stays Markdown so it pastes into GitHub as-is.

import 'package:ai_tutor_python/services/debug/runner_diagnostics.dart';

/// The file's contents: a heading with the (redacted) title, the local time
/// the report was taken and the app version, then [body] verbatim.
///
///     # <title>
///     Reported: 2026-09-15 14:03  ·  App version 2.3.0+20
///
///     <body>
String buildBugReportFile({
  required String title,
  required DateTime reportedAt,
  required String appVersion,
  required String body,
}) {
  final buffer = StringBuffer()
    ..writeln('# ${redactUserPaths(title.trim())}')
    ..writeln(
      'Reported: ${formatReportStamp(reportedAt)}  ·  App version $appVersion',
    )
    ..writeln()
    ..write(body);
  return buffer.toString();
}

/// `ai-tutor-bugreport-<yyyy-MM-dd>-<title-slug>.txt`, mirroring the
/// progress archive's `ai-tutor-progress-<date>.json`. The slug is dropped
/// when nothing of the title survives slugging.
String bugReportFileName({
  required String title,
  required DateTime reportedAt,
}) {
  final date = formatReportStamp(reportedAt).substring(0, 10);
  final slug = slugifyTitle(title);
  return slug.isEmpty
      ? 'ai-tutor-bugreport-$date.txt'
      : 'ai-tutor-bugreport-$date-$slug.txt';
}

/// `yyyy-MM-dd HH:mm` in the local timezone — fixed, not locale-aware: a
/// file name and a heading should read the same on every machine.
String formatReportStamp(DateTime at) {
  final t = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}

/// Lower-case ASCII letters and digits, runs of anything else collapsed to a
/// single `-`, no leading or trailing `-`, at most [maxLength] characters.
/// Anything outside ASCII goes — a title is free text, and a file name is
/// not the place to find out which characters a chat client tolerates.
String slugifyTitle(String title, {int maxLength = 40}) {
  var slug = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.length > maxLength) {
    slug = slug.substring(0, maxLength).replaceAll(RegExp(r'-+$'), '');
  }
  return slug;
}
