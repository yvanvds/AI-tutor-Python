import 'dart:convert';

import 'package:ai_tutor_python/services/github/github_issue_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('GitHubIssueService', () {
    test('loginFor returns the login for a valid token', () async {
      late http.Request seen;
      final svc = GitHubIssueService(
        client: MockClient((req) async {
          seen = req;
          return http.Response('{"login":"yvan"}', 200);
        }),
      );

      expect(await svc.loginFor('tok'), 'yvan');
      expect(seen.method, 'GET');
      expect(seen.url.toString(), 'https://api.github.com/user');
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(seen.headers['Accept'], 'application/vnd.github+json');
    });

    test('loginFor surfaces the API message on failure', () async {
      final svc = GitHubIssueService(
        client: MockClient(
          (_) async => http.Response('{"message":"Bad credentials"}', 401),
        ),
      );

      await expectLater(
        svc.loginFor('bad'),
        throwsA(
          isA<GitHubApiException>()
              .having((e) => e.statusCode, 'status', 401)
              .having((e) => e.message, 'message', 'Bad credentials'),
        ),
      );
    });

    test(
      'createIssue posts to the bug-report repo and returns the url',
      () async {
        late http.Request seen;
        final svc = GitHubIssueService(
          client: MockClient((req) async {
            seen = req;
            return http.Response(
              '{"html_url":"https://github.com/o/r/issues/7"}',
              201,
            );
          }),
          repo: 'o/r',
        );

        final url = await svc.createIssue(
          token: 'tok',
          title: 'Crash',
          body: 'details',
        );

        expect(url.toString(), 'https://github.com/o/r/issues/7');
        expect(seen.method, 'POST');
        expect(seen.url.toString(), 'https://api.github.com/repos/o/r/issues');
        expect(jsonDecode(seen.body), {'title': 'Crash', 'body': 'details'});
      },
    );

    test('createIssue throws on a non-201 response', () async {
      final svc = GitHubIssueService(
        client: MockClient(
          (_) async => http.Response('{"message":"Validation Failed"}', 422),
        ),
      );

      await expectLater(
        svc.createIssue(token: 't', title: '', body: ''),
        throwsA(isA<GitHubApiException>()),
      );
    });
  });

  group('buildBugReportBody', () {
    test('includes description, version and the turn minus instructions', () {
      final body = buildBugReportBody(
        description: 'It broke',
        appVersion: '1.2.3',
        turn: {
          'turnId': 4,
          'instructions': 'SECRET PROMPT',
          'userInput': 'x = 1',
        },
      );

      expect(body, startsWith('It broke'));
      expect(body, contains('App version: `1.2.3`'));
      expect(body, contains('"turnId": 4'));
      expect(body, contains('"userInput": "x = 1"'));
      expect(body, isNot(contains('SECRET PROMPT')));
      expect(body, contains('<details>'));
    });

    test('omits the payload block when no turn is attached', () {
      final body = buildBugReportBody(description: '', appVersion: '1.0.0');
      expect(body, contains('_(no description)_'));
      expect(body, isNot(contains('<details>')));
    });
  });

  group('GitHubTokenStorage', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('saves, hydrates and clears the token', () async {
      final c1 = ProviderContainer();
      addTearDown(c1.dispose);
      expect(c1.read(githubTokenStorageProvider), isNull);
      await c1.read(githubTokenStorageProvider.notifier).saveToken('tok');
      expect(c1.read(githubTokenStorageProvider), 'tok');

      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      c2.read(githubTokenStorageProvider);
      await Future<void>.delayed(Duration.zero);
      expect(c2.read(githubTokenStorageProvider), 'tok');

      await c2.read(githubTokenStorageProvider.notifier).clearToken();
      expect(c2.read(githubTokenStorageProvider), isNull);
    });
  });
}
