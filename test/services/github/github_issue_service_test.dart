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

    // #314 — the whole session instead of one exercise.
    group('with the whole session', () {
      Map<String, dynamic> exercise(int id, {String filler = ''}) => {
        'turnId': id,
        'sessionId': 'session-1',
        'instructions': 'SECRET PROMPT $id',
        'userInput': 'answer $id $filler',
        'events': [
          {
            'atMs': 12,
            'name': 'conductor.planned',
            'data': {
              'targetLO': 'lo_$id',
              'candidateLOs': [
                {'loId': 'lo_$id', 'mean': 0.5677, 'evidence': 6.144},
              ],
            },
          },
        ],
        'persisted': {
          'uid': '',
          'subgoalProgressAfter': 0.42,
          'loStatusAfter': [
            {'loId': 'lo_$id', 'mean': 0.5677, 'mastered': false},
          ],
        },
      };

      BugReportSession session(List<Map<String, dynamic>> turns) =>
          BugReportSession(
            sessionId: 'session-1',
            startedAt: DateTime.utc(2026, 11, 19, 8, 30),
            turns: turns,
          );

      /// The JSON inside the collapsed block, as a reader would paste it.
      Map<String, dynamic> payloadOf(String body) {
        final start = body.indexOf('```json\n') + '```json\n'.length;
        final end = body.indexOf('\n```', start);
        return jsonDecode(body.substring(start, end)) as Map<String, dynamic>;
      }

      test('attaches every exercise, each one redacted', () {
        final body = buildBugReportBody(
          description: 'the questions keep coming',
          appVersion: '1.0.0',
          runner: runner,
          session: session([
            exercise(1),
            exercise(2, filler: r'C:\Users\sam.student\Desktop\a.py'),
            exercise(3),
          ]),
        );

        expect(body, contains('Session debug payload (3 exercises)'));
        expect(body, isNot(contains('Turn debug payload')));
        expect(body, isNot(contains('omitted')));
        expect(body, contains('Python runner state'));

        final payload = payloadOf(body);
        expect(payload['sessionId'], 'session-1');
        expect(payload['sessionStartedAt'], '2026-11-19T08:30:00.000Z');
        expect(payload['turnCount'], 3);
        expect(payload.containsKey('omittedOlderTurns'), isFalse);
        final turns = (payload['turns'] as List).cast<Map<String, dynamic>>();
        expect(turns.map((t) => t['turnId']), [1, 2, 3]);

        // No system prompt, in any exercise.
        expect(body, isNot(contains('SECRET PROMPT')));
        expect(turns.any((t) => t.containsKey('instructions')), isFalse);
        // No belief number, in any exercise.
        expect(body, isNot(contains('0.5677')));
        expect(body, isNot(contains('6.144')));
        expect(body, isNot(contains('0.42')));
        expect(
          body,
          isNot(matches(RegExp(r'"(mean|evidence|mastered)":\s*[0-9tf]'))),
        );
        expect('"mean": "<redacted>"'.allMatches(body), hasLength(6));
        // No account name out of a path, wherever in the session it was.
        expect(body, isNot(contains('sam.student')));
        expect(body, contains(r'C:\\Users\\<user>\\Desktop\\a.py'));
        // …and what a report is diagnosed from is still there.
        expect(body, contains('"targetLO": "lo_2"'));
      });

      // The recorder knows who is signed in, and its own `exportJson()` says
      // so. A report is built from the turns and the session id only.
      test('carries neither the uid nor the e-mail of the student', () {
        final recorder = DebugSessionRecorder()
          ..resetSession(
            uid: 'uid-of-the-student',
            email: 'sam.student@school.example',
            modelName: 'model-x',
          );
        for (var i = 0; i < 2; i++) {
          recorder
            ..beginTurn(
              requestType: 'submitCode',
              currentExerciseTypeAtStart: null,
              tutorStateAtStart: 'idle',
              selectedRootGoalId: null,
              selectedChildGoalId: null,
              preferredRootGoalId: null,
              preferredChildGoalId: null,
              streamable: true,
              previousInputsMode: 'includeSession',
            )
            ..endTurn();
        }
        // What must not be reused as-is.
        expect(recorder.exportJson()['uid'], 'uid-of-the-student');

        final body = buildBugReportBody(
          description: 'x',
          appVersion: '1.0.0',
          runner: runner,
          session: BugReportSession(
            sessionId: recorder.sessionId,
            startedAt: recorder.sessionStartedAt,
            turns: [for (final t in recorder.buffer) t.toJson()],
          ),
        );

        expect(body, contains('"sessionId": "${recorder.sessionId}"'));
        expect(body, contains('"turnCount": 2'));
        expect(body, isNot(contains('uid-of-the-student')));
        expect(body, isNot(contains('sam.student')));
        expect(body, isNot(contains('school.example')));
        expect(body, isNot(contains('"email"')));
      });

      test('a file gets the whole session however long it is', () {
        final turns = [
          for (var i = 1; i <= 60; i++) exercise(i, filler: 'x' * 3000),
        ];
        final body = buildBugReportBody(
          description: 'x',
          appVersion: '1.0.0',
          runner: runner,
          session: session(turns),
        );

        expect(body.length, greaterThan(kGitHubIssueBodyLimit));
        expect(payloadOf(body)['turns'], hasLength(60));
        expect(body, isNot(contains('omitted')));
      });

      test('an issue keeps the most recent exercises that fit and says how '
          'many were left out', () {
        final turns = [
          for (var i = 1; i <= 60; i++) exercise(i, filler: 'x' * 3000),
        ];
        final body = buildBugReportBody(
          description: 'x',
          appVersion: '1.0.0',
          runner: runner,
          session: session(turns),
          maxLength: kGitHubIssueBodyLimit,
        );

        expect(body.length, lessThanOrEqualTo(kGitHubIssueBodyLimit));
        final payload = payloadOf(body);
        final kept = (payload['turns'] as List).cast<Map<String, dynamic>>();
        final omitted = 60 - kept.length;
        expect(kept, isNotEmpty);
        expect(omitted, greaterThan(0));
        // The newest ones, in order, ending at the last exercise.
        expect(kept.map((t) => t['turnId']), [
          for (var i = omitted + 1; i <= 60; i++) i,
        ]);
        expect(payload['turnCount'], 60);
        expect(payload['omittedOlderTurns'], omitted);
        expect(
          body,
          contains(
            '_$omitted older exercises omitted to fit a GitHub issue — save '
            'the report as a file for the whole session._',
          ),
        );
        expect(
          body,
          contains('Session debug payload (${kept.length} of 60 exercises)'),
        );
        // As many as fit: one more would have been over the limit.
        final oneMore = buildBugReportBody(
          description: 'x',
          appVersion: '1.0.0',
          runner: runner,
          session: session(turns.sublist(omitted - 1)),
        );
        expect(oneMore.length, greaterThan(kGitHubIssueBodyLimit));
        // Still redacted.
        expect(body, isNot(contains('SECRET PROMPT')));
        expect(body, isNot(contains('0.5677')));
      });

      test('an issue whose newest exercise alone is too long still posts, '
          'with none attached', () {
        final body = buildBugReportBody(
          description: 'x',
          appVersion: '1.0.0',
          runner: runner,
          session: session([
            exercise(1),
            exercise(2, filler: 'x' * (kGitHubIssueBodyLimit + 1)),
          ]),
          maxLength: kGitHubIssueBodyLimit,
        );

        expect(body.length, lessThanOrEqualTo(kGitHubIssueBodyLimit));
        expect(payloadOf(body)['turns'], isEmpty);
        expect(body, contains('_2 older exercises omitted'));
      });

      test('a session that fits an issue is not shortened', () {
        final body = buildBugReportBody(
          description: 'x',
          appVersion: '1.0.0',
          runner: runner,
          session: session([exercise(1), exercise(2)]),
          maxLength: kGitHubIssueBodyLimit,
        );

        expect(payloadOf(body)['turns'], hasLength(2));
        expect(body, isNot(contains('omitted')));
      });
    });

    test('omits the payload block when no turn is attached', () {
      final body = buildBugReportBody(
        description: '',
        appVersion: '1.0.0',
        runner: runner,
      );
      expect(body, contains('_(no description)_'));
      expect(body, isNot(contains('debug payload')));
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
