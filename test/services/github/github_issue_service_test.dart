import 'dart:convert';

import 'package:ai_tutor_python/services/debug/debug_session_recorder.dart';
import 'package:ai_tutor_python/services/debug/runner_diagnostics.dart';
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
    const runner = RunnerDiagnostics(
      status: 'crashed',
      source: 'installed layout (next to the app)',
      pythonExecutable: r'C:\Users\jane.doe\AI Tutor\python\python.exe',
      hostScript: r'C:\Users\jane.doe\AI Tutor\py_runner\host.py',
      lastRun: 'error after 12 ms — ZeroDivisionError: division by zero',
    );

    test('includes description, version and the turn minus instructions', () {
      final body = buildBugReportBody(
        description: 'It broke',
        appVersion: '1.2.3',
        runner: runner,
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
      expect(body, contains('Turn debug payload'));
    });

    // The whole point of #74: the turn payload is optional and the runner
    // section is not, because "it didn't run" is not a question about the turn.
    test('attaches the runner section even with no turn payload', () {
      final body = buildBugReportBody(
        description: 'the python script did not run',
        appVersion: '1.0.0',
        runner: runner,
      );

      expect(body, isNot(contains('Turn debug payload')));
      expect(body, contains('Python runner state'));
      expect(body, contains('runner status:      crashed'));
      expect(body, contains('locator branch:     installed layout'));
      expect(body, contains('ZeroDivisionError'));
    });

    test('redacts the account name out of every path in the body', () {
      final body = buildBugReportBody(
        description: r'it wrote to C:\Users\jane.doe\Desktop\out.txt',
        appVersion: '1.0.0',
        runner: runner,
      );

      expect(body, isNot(contains('jane.doe')));
      expect(body, contains(r'C:\Users\<user>\AI Tutor\python\python.exe'));
      expect(body, contains(r'C:\Users\<user>\Desktop\out.txt'));
    });

    // #79. The payload the app attaches is diagnosed by a human reading the
    // JSON, so assert on the rendered body rather than on the map.
    test('publishes the plan but not the student it was planned for', () {
      final body = buildBugReportBody(
        description: 'the exercise had nothing to fill in',
        appVersion: '1.0.0',
        runner: runner,
        turn: {
          'turnId': 4,
          'userInput': '{"request":"exercise"}',
          'events': [
            {
              'atMs': 12,
              'name': 'conductor.planned',
              'data': {
                'targetLO': 'write_input_call',
                'questionType': 'completeCodeQuestion',
                'difficulty': 'medium',
                'chosenReason': 'lowest mean unmastered',
                'notchDropFired': false,
                'candidateLOs': [
                  {
                    'loId': 'write_input_call',
                    'mean': 0.5677,
                    'evidence': 6.144,
                  },
                  {
                    'loId': 'recall_input_returns_string',
                    'mean': 0.6657,
                    'evidence': 10.98,
                  },
                ],
              },
            },
          ],
          'persisted': {
            'subgoalProgressAfter': 0.42,
            'loStatusAfter': [
              {
                'loId': 'write_input_call',
                'mean': 0.5677,
                'evidence': 6.144,
                'mastered': false,
                'stuck': true,
              },
            ],
          },
        },
      );

      // Not one belief number reaches the public repository.
      expect(body, isNot(contains('0.5677')));
      expect(body, isNot(contains('6.144')));
      expect(body, isNot(contains('0.6657')));
      expect(body, isNot(contains('10.98')));
      expect(body, isNot(contains('0.42')));
      expect(body, isNot(matches(RegExp(r'"(mean|evidence)":\s*[0-9]'))));
      expect(body, contains('"mean": "<redacted>"'));

      // …and the payload is still worth attaching: this is the material #78
      // was diagnosed from.
      expect(body, contains('Turn debug payload'));
      expect(body, contains('"targetLO": "write_input_call"'));
      expect(body, contains('"questionType": "completeCodeQuestion"'));
      expect(body, contains('"difficulty": "medium"'));
      expect(body, contains('"chosenReason": "lowest mean unmastered"'));
      expect(body, contains('"loId": "recall_input_returns_string"'));
      expect(body, contains('"atMs": 12'));
    });

    // The other half of the same decision: the numbers are useful on the
    // teacher's own machine, so filing a report must not disturb what
    // Options → Developer tools → Recent turns shows. The recorder hands out
    // its event data by reference, so this is a real hazard, not a formality.
    test('leaves the recorded turn intact for the local debug view', () {
      final recorder = DebugSessionRecorder();
      recorder.beginTurn(
        requestType: 'exercise',
        currentExerciseTypeAtStart: null,
        tutorStateAtStart: 'idle',
        selectedRootGoalId: null,
        selectedChildGoalId: null,
        preferredRootGoalId: null,
        preferredChildGoalId: null,
        streamable: true,
        previousInputsMode: 'includeSession',
      );
      recorder.recordEvent('conductor.planned', {
        'targetLO': 'write_input_call',
        'candidateLOs': [
          {'loId': 'write_input_call', 'mean': 0.5677, 'evidence': 6.144},
        ],
      });
      recorder.endTurn();

      final turn = recorder.buffer.single;
      final body = buildBugReportBody(
        description: 'x',
        appVersion: '1.0.0',
        runner: runner,
        turn: turn.toJson(),
      );
      expect(body, isNot(contains('0.5677')));

      final data = turn.events.single.data!;
      final candidate = (data['candidateLOs'] as List).single as Map;
      expect(candidate['mean'], 0.5677);
      expect(candidate['evidence'], 6.144);
      final again = const JsonEncoder.withIndent('  ').convert(turn.toJson());
      expect(again, contains('0.5677'));
    });

    test('omits the payload block when no turn is attached', () {
      final body = buildBugReportBody(
        description: '',
        appVersion: '1.0.0',
        runner: runner,
      );
      expect(body, contains('_(no description)_'));
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
