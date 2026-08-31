// A snapshot of the Python runner, for bug reports (#74).
//
// "The python script did not run" is the failure a student can see without
// understanding anything else, and it is the one the turn payload cannot
// explain: the turn describes the tutor's LLM call, while the failure lives in
// `py_runner`. So every report carries this section as well, always, with no
// dropdown to pick it.
//
// It must survive the runner being *completely* unavailable — that is the
// exact case worth reporting. Nothing here needs a live host process:
// resolution is a filesystem check, and every read is wrapped so a failure
// becomes a line in the report rather than an exception that blanks it.
//
// Privacy: these issues are filed on a **public** repository under the
// student's own GitHub account, and a Windows path embeds the account name
// (`C:\Users\<name>\…`). [redactUserPaths] strips that segment, and
// [toMarkdown] is the only way this leaves the process.

import 'dart:io';

import 'package:py_runner/py_runner.dart';

/// Replaces the user-profile segment of every path in [text] with `<user>`.
///
/// Deliberately over-eager rather than precise: the segment is taken as
/// everything up to the next path separator or end of line, so an unusual
/// username (one with a space, say) is redacted whole and at worst a few
/// harmless characters go with it. Losing a word is fine; publishing a real
/// name on a public repo is not.
///
/// [homeDirectory] is a backstop for a profile that does not live under
/// `Users`/`home`; it defaults to `USERPROFILE`/`HOME`. Pass it explicitly in
/// tests so the result does not depend on the machine.
String redactUserPaths(String text, {String? homeDirectory}) {
  var out = text
      // C:\Users\name\…  and  C:/Users/name/…
      .replaceAllMapped(
        RegExp(
          r'([A-Za-z]:[\\/]+Users[\\/]+)([^\\/\r\n]+)',
          caseSensitive: false,
        ),
        (m) => '${m[1]}<user>',
      )
      // /home/name/…  and  /Users/name/…
      .replaceAllMapped(
        RegExp(r'(/(?:home|Users)/)([^/\r\n]+)'),
        (m) => '${m[1]}<user>',
      );

  final home = homeDirectory ?? _defaultHomeDirectory();
  if (home != null && home.isNotEmpty) {
    out = out.replaceAll(
      RegExp(RegExp.escape(home), caseSensitive: false),
      '<user-profile>',
    );
  }
  return out;
}

String? _defaultHomeDirectory() {
  try {
    final env = Platform.environment;
    return env['USERPROFILE'] ?? env['HOME'];
  } catch (_) {
    return null;
  }
}

/// What the app can say about its Python runner without one running.
class RunnerDiagnostics {
  const RunnerDiagnostics({
    this.status,
    this.pythonExecutable,
    this.hostScript,
    this.source,
    this.resolutionError,
    this.pythonVersion,
    this.hostPlatform,
    this.lastStartError,
    this.lastRun,
    this.collectionError,
  });

  /// [PyRunner.status] — `stopped` when no host was ever asked for.
  final String? status;

  /// Resolved interpreter and host script, or null when resolution failed.
  final String? pythonExecutable;
  final String? hostScript;

  /// Which locator branch produced them (#75 added a third).
  final String? source;

  /// The exception resolution threw — the usual answer to "it didn't run".
  final String? resolutionError;

  /// From the host's `ready` frame; null when no host has started this
  /// session, which is itself the interesting answer.
  final String? pythonVersion;
  final String? hostPlatform;

  /// What the most recent [PyRunner.start] threw, if it threw.
  final String? lastStartError;

  /// Terminal state of the last run, already formatted.
  final String? lastRun;

  /// Set only when reading the runner itself blew up. The section is still
  /// emitted — a report that says "diagnostics unavailable: …" is worth more
  /// than a report with no section and no explanation.
  final String? collectionError;

  /// Reads everything above off [runner]. Never throws.
  static Future<RunnerDiagnostics> collect(PyRunner runner) async {
    try {
      String? pythonExecutable;
      String? hostScript;
      String? source;
      String? resolutionError;
      try {
        // Resolved fresh rather than read off the runner: a report is most
        // often filed *because* no host ever started, so there is nothing
        // cached to read. This is a filesystem check, not a process spawn.
        final paths = await runner.locator.resolve();
        pythonExecutable = paths.pythonExecutable;
        hostScript = paths.hostScript;
        source = _sourceLabel(paths.source);
      } catch (e) {
        resolutionError = e.toString();
      }

      final ready = runner.readyInfo;
      final startError = runner.lastStartError;
      final last = runner.lastRunResult;

      return RunnerDiagnostics(
        status: runner.status.name,
        pythonExecutable: pythonExecutable,
        hostScript: hostScript,
        source: source,
        resolutionError: resolutionError,
        pythonVersion: ready?.pythonVersion,
        hostPlatform: ready?.platform,
        lastStartError: startError?.toString(),
        lastRun: last == null ? null : _runLabel(last),
      );
    } catch (e) {
      return RunnerDiagnostics(collectionError: e.toString());
    }
  }

  static String _sourceLabel(PyHostSource source) => switch (source) {
    PyHostSource.explicit => 'explicit (paths supplied by the caller)',
    PyHostSource.environmentOverride =>
      'environment override (PY_RUNNER_PYTHON + PY_RUNNER_HOST_SCRIPT)',
    PyHostSource.installedLayout => 'installed layout (next to the app)',
    PyHostSource.devCheckout =>
      'dev checkout fallback (build/python_bundle in the source tree)',
  };

  static String _runLabel(RunResult result) {
    final buffer = StringBuffer()
      ..write(result.status.name)
      ..write(' after ${result.duration.inMilliseconds} ms');
    final exception = result.exception;
    if (exception != null) {
      buffer.write(' — ${exception.type}: ${exception.message}');
    }
    return buffer.toString();
  }

  /// The report section, redacted. This is the only path from a
  /// [RunnerDiagnostics] into an issue body, so redaction cannot be bypassed
  /// by a caller that formats the fields itself.
  String toMarkdown() {
    final version = pythonVersion;
    final host = version == null
        ? '(no host has started this session)'
        : (hostPlatform == null ? version : '$version on $hostPlatform');

    final lines = <String>[
      if (collectionError != null)
        'diagnostics unavailable: $collectionError'
      else ...[
        'runner status:      ${status ?? 'unknown'}',
        'locator branch:     ${source ?? '(resolution failed)'}',
        'python executable:  ${pythonExecutable ?? '(unresolved)'}',
        'host script:        ${hostScript ?? '(unresolved)'}',
        if (resolutionError != null) 'resolution error:   $resolutionError',
        'host python:        $host',
        if (lastStartError != null) 'last start error:   $lastStartError',
        'last run:           ${lastRun ?? '(no run has finished this session)'}',
      ],
    ];

    final buffer = StringBuffer()
      ..writeln('<details>')
      ..writeln('<summary>Python runner state</summary>')
      ..writeln()
      ..writeln('```text')
      ..writeln(lines.join('\n'))
      ..writeln('```')
      ..writeln('</details>');
    return redactUserPaths(buffer.toString());
  }
}
