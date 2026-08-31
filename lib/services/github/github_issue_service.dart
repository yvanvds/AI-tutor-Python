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

/// Builds the Markdown body for a bug report. The turn payload is attached
/// inside a collapsed block; the tutor instructions (system prompt) are
/// dropped because they are large and not specific to the reported turn.
///
/// [runner] is required rather than optional (#74): the turn payload answers
/// questions about the tutor, and the single most likely thing a student
/// reports — "it didn't run" — is not one of them. The runner section is
/// always attached, whatever the student picked in the turn dropdown.
///
/// The whole body goes through [redactUserPaths] on the way out. These issues
/// land on a public repository under the student's own account, and a Windows
/// path carries their name in it; funnelling every field through one redactor
/// means a future field cannot quietly reintroduce the leak.
String buildBugReportBody({
  required String description,
  required String appVersion,
  required RunnerDiagnostics runner,
  Map<String, dynamic>? turn,
}) {
  final buffer = StringBuffer()
    ..writeln(
      description.trim().isEmpty ? '_(no description)_' : description.trim(),
    )
    ..writeln()
    ..writeln('---')
    ..writeln('App version: `$appVersion`')
    ..writeln()
    ..write(runner.toMarkdown());
  if (turn != null) {
    final redacted = Map<String, dynamic>.from(turn)..remove('instructions');
    final encoded = const JsonEncoder.withIndent('  ').convert(redacted);
    buffer
      ..writeln()
      ..writeln('<details>')
      ..writeln('<summary>Turn debug payload</summary>')
      ..writeln()
      ..writeln('```json')
      ..writeln(encoded)
      ..writeln('```')
      ..writeln('</details>');
  }
  return redactUserPaths(buffer.toString());
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
