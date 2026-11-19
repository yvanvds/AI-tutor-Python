// GitHub bug-report support for the Options panel (issue #25).
//
// Auth is an OAuth token obtained through the device flow in
// `github_device_flow.dart` (#57) — a student approves a short code in the
// browser instead of creating and pasting a personal access token. Either
// kind of token works here; this file only ever sees a bearer string.
//
// The token is kept in SharedPreferences next to the other local settings —
// the same storage the local OpenAI key uses (`local_api_key_storage.dart`),
// which is the app's existing per-device secret store.

import 'dart:convert';

import 'package:ai_tutor_python/services/debug/runner_diagnostics.dart';
import 'package:ai_tutor_python/services/debug/turn_payload_redaction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String kBugReportRepo = 'yvanvds/AI-tutor-Python';

/// Persisted GitHub personal access token. State is the token, or `null`
/// while none is stored.
class GitHubTokenStorage extends Notifier<String?> {
  static const String _keyName = 'github_token';

  @override
  String? build() {
    _hydrate();
    return null;
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(_keyName);
  }

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyName, token);
    state = token;
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyName);
    state = null;
  }
}

final githubTokenStorageProvider =
    NotifierProvider<GitHubTokenStorage, String?>(GitHubTokenStorage.new);

class GitHubApiException implements Exception {
  const GitHubApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => 'GitHub $statusCode: $message';
}

class GitHubIssueService {
  GitHubIssueService({
    http.Client? client,
    this._repo = kBugReportRepo,
    Uri? apiBase,
  }) : _client = client ?? http.Client(),
       _apiBase = apiBase ?? Uri.parse('https://api.github.com');

  final http.Client _client;
  final String _repo;
  final Uri _apiBase;

  Map<String, String> _headers(String token) => {
    'Accept': 'application/vnd.github+json',
    'Authorization': 'Bearer $token',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  /// Verifies [token] and returns the login it belongs to.
  Future<String> loginFor(String token) async {
    final res = await _client.get(
      _apiBase.resolve('/user'),
      headers: _headers(token),
    );
    if (res.statusCode != 200) {
      throw GitHubApiException(res.statusCode, _errorMessage(res));
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return (json['login'] as String?) ?? '';
  }

  /// Creates an issue on the bug-report repository and returns its web URL.
  Future<Uri> createIssue({
    required String token,
    required String title,
    required String body,
  }) async {
    final res = await _client.post(
      _apiBase.resolve('/repos/$_repo/issues'),
      headers: {..._headers(token), 'Content-Type': 'application/json'},
      body: jsonEncode({'title': title, 'body': body}),
    );
    if (res.statusCode != 201) {
      throw GitHubApiException(res.statusCode, _errorMessage(res));
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return Uri.parse(json['html_url'] as String);
  }

  static String _errorMessage(http.Response res) {
    try {
      final json = jsonDecode(res.body);
      if (json is Map && json['message'] is String) {
        return json['message'] as String;
      }
    } catch (_) {}
    return res.reasonPhrase ?? res.body;
  }
}

/// The longest body GitHub accepts for an issue. One character more and the
/// API answers 422, which the student would only see as "Posting failed".
const int kGitHubIssueBodyLimit = 65536;

/// The whole session as a bug report attaches it (#314): what
/// `DebugSessionRecorder` holds in memory, minus who the student is. It
/// deliberately has no room for the recorder's `uid` and `email` — the
/// recorder's own `exportJson()` carries both, which is why a report is not
/// built from it.
class BugReportSession {
  const BugReportSession({
    required this.sessionId,
    required this.startedAt,
    required this.turns,
  });

  final String sessionId;
  final DateTime startedAt;

  /// `TurnRecord.toJson()` per exercise, oldest first.
  final List<Map<String, dynamic>> turns;
}

/// Builds the Markdown body for a bug report. The debug payload is attached
/// inside a collapsed block: one exercise ([turn]), or the whole session
/// ([session], #314) — a problem like "the questions keep coming and I am not
/// getting anywhere" lives in the sequence, not in one answer. When both are
/// given the session wins; it contains the turn.
///
/// The tutor instructions (system prompt) are dropped from every exercise
/// because they are large and not specific to the reported one.
///
/// [runner] is required rather than optional (#74): the turn payload answers
/// questions about the tutor, and the single most likely thing a student
/// reports — "it didn't run" — is not one of them. The runner section is
/// always attached, whatever the student picked in the dropdown.
///
/// The whole body goes through [redactUserPaths] on the way out. These issues
/// land on a public repository under the student's own account, and a Windows
/// path carries their name in it; funnelling every field through one redactor
/// means a future field cannot quietly reintroduce the leak.
///
/// Every exercise additionally goes through [redactBeliefData] (#79), for
/// the same reason and in the same shape: the conductor's planning event and
/// the persisted turn carry the student's mastery estimates, which say nothing
/// about the bug and everything about the student. The redaction happens here,
/// not in the recorder — Options → Developer tools → Recent turns keeps the
/// full numbers.
///
/// [maxLength] caps the length of the returned body (pass
/// [kGitHubIssueBodyLimit] for an issue, nothing for a file). A session that
/// does not fit keeps its most recent exercises and says how many older ones
/// were left out. Only a session is shortened: one exercise is either
/// attached or not.
String buildBugReportBody({
  required String description,
  required String appVersion,
  required RunnerDiagnostics runner,
  Map<String, dynamic>? turn,
  BugReportSession? session,
  int? maxLength,
}) {
  final head = StringBuffer()
    ..writeln(
      description.trim().isEmpty ? '_(no description)_' : description.trim(),
    )
    ..writeln()
    ..writeln('---')
    ..writeln('App version: `$appVersion`')
    ..writeln()
    ..write(runner.toMarkdown());

  if (session != null) {
    final turns = session.turns.map(_reportableTurn).toList(growable: false);
    // Measured on the finished, path-redacted text: `<user>` can be longer
    // than the account name it replaces.
    String build(int kept) =>
        redactUserPaths('$head${_sessionBlock(session, turns, kept: kept)}');
    final whole = build(turns.length);
    if (maxLength == null || whole.length <= maxLength) return whole;
    // The largest number of recent exercises that fits. Dropping one more
    // never makes the body longer, so a binary search finds it.
    var lo = 0;
    var hi = turns.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (build(mid).length <= maxLength) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return build(lo);
  }

  if (turn != null) {
    final encoded = const JsonEncoder.withIndent('  ')
        .convert(_reportableTurn(turn));
    head
      ..writeln()
      ..writeln('<details>')
      ..writeln('<summary>Turn debug payload</summary>')
      ..writeln()
      ..writeln('```json')
      ..writeln(encoded)
      ..writeln('```')
      ..writeln('</details>');
  }
  return redactUserPaths(head.toString());
}

/// One exercise as a report may carry it. Two different reasons to drop
/// something: `instructions` is the system prompt — large, identical every
/// turn, and not about the reported one; the belief data is the student's
/// own (#79).
Map<String, dynamic> _reportableTurn(Map<String, dynamic> turn) =>
    redactBeliefData(Map<String, dynamic>.from(turn)..remove('instructions'));

/// The collapsed session block with the [kept] most recent of [turns].
String _sessionBlock(
  BugReportSession session,
  List<Map<String, dynamic>> turns, {
  required int kept,
}) {
  final omitted = turns.length - kept;
  final encoded = const JsonEncoder.withIndent('  ').convert({
    'sessionId': session.sessionId,
    'sessionStartedAt': session.startedAt.toUtc().toIso8601String(),
    'turnCount': turns.length,
    if (omitted > 0) 'omittedOlderTurns': omitted,
    'turns': turns.sublist(omitted),
  });
  final buffer = StringBuffer()..writeln();
  if (omitted > 0) {
    buffer
      ..writeln(
        '_$omitted older ${omitted == 1 ? 'exercise' : 'exercises'} omitted '
        'to fit a GitHub issue — save the report as a file for the whole '
        'session._',
      )
      ..writeln();
  }
  buffer
    ..writeln('<details>')
    ..writeln(
      '<summary>Session debug payload '
      '(${omitted > 0 ? '$kept of ${turns.length}' : '${turns.length}'} '
      '${turns.length == 1 ? 'exercise' : 'exercises'})</summary>',
    )
    ..writeln()
    ..writeln('```json')
    ..writeln(encoded)
    ..writeln('```')
    ..writeln('</details>');
  return buffer.toString();
}

/// Where the REST API lives. A seam, like `gitHubOAuthBaseProvider`: an
/// end-to-end flow points it at a loopback server so the real service, real
/// headers and real error handling run without reaching github.com.
final gitHubApiBaseProvider = Provider<Uri>(
  (_) => Uri.parse('https://api.github.com'),
);

final githubIssueServiceProvider = Provider<GitHubIssueService>(
  (ref) => GitHubIssueService(apiBase: ref.watch(gitHubApiBaseProvider)),
);
