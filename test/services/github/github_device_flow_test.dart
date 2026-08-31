// Issue #57 — GitHub's OAuth device flow, the sign-in that replaced the
// personal access token a student used to paste in.
//
// Everything here runs against a scripted `MockClient` and a `wait` seam, so
// the whole loop — the interval GitHub asks for, the back-off it demands, the
// four ways it can end — is exercised without a network and without spending
// the seconds a real poll would.

import 'dart:convert';

import 'package:ai_tutor_python/services/github/github_device_flow.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const String _clientId = 'Ov23liTESTCLIENTID';

/// The device-code answer GitHub gives, with the fields a flow may vary.
String _grantBody({
  String deviceCode = 'dev-code',
  String userCode = 'WDJB-MJHT',
  String verificationUri = 'https://github.com/login/device',
  int interval = 5,
  int expiresIn = 900,
}) => jsonEncode({
  'device_code': deviceCode,
  'user_code': userCode,
  'verification_uri': verificationUri,
  'interval': interval,
  'expires_in': expiresIn,
});

/// Collects every request and every pause, and answers from a script.
class _Github {
  _Github(this._answers);

  /// Called with the request number (1-based) of the *token* endpoint.
  final http.Response Function(int poll, http.Request request) _answers;

  final List<http.Request> requests = <http.Request>[];
  final List<Map<String, String>> bodies = <Map<String, String>>[];
  final List<Duration> waits = <Duration>[];

  int polls = 0;
  String grant = _grantBody();
  int grantStatus = 200;

  http.Client get client => MockClient((req) async {
    requests.add(req);
    bodies.add(Uri.splitQueryString(req.body));
    if (req.url.path == '/login/device/code') {
      return http.Response(grant, grantStatus);
    }
    polls++;
    return _answers(polls, req);
  });

  Future<void> wait(Duration d) async => waits.add(d);

  GitHubDeviceFlow flow({String clientId = _clientId}) => GitHubDeviceFlow(
    clientId: clientId,
    client: client,
    authBase: Uri.parse('https://github.test/'),
    wait: wait,
  );
}

/// A grant with the timings a flow wants, without going through the network.
DeviceCodeGrant _fakeGrant({
  Duration interval = const Duration(seconds: 5),
  Duration expiresIn = const Duration(minutes: 15),
}) => DeviceCodeGrant(
  deviceCode: 'dev-code',
  userCode: 'WDJB-MJHT',
  verificationUri: Uri.parse('https://github.com/login/device'),
  interval: interval,
  expiresIn: expiresIn,
);

Matcher _failsWith(DeviceFlowFailure reason) => throwsA(
  isA<DeviceFlowException>().having((e) => e.reason, 'reason', reason),
);

void main() {
  group('isConfigured', () {
    test('is false without a client id, and requestCode says so without '
        'asking GitHub', () async {
      final gh = _Github((_, _) => http.Response('{}', 200));
      final flow = gh.flow(clientId: '');

      expect(flow.isConfigured, isFalse);
      await expectLater(
        flow.requestCode(),
        _failsWith(DeviceFlowFailure.notConfigured),
      );
      expect(
        gh.requests,
        isEmpty,
        reason: 'an unconfigured build must not reach out at all',
      );
    });

    test('is true once a client id is compiled in', () {
      expect(
        _Github((_, _) => http.Response('{}', 200)).flow().isConfigured,
        isTrue,
      );
    });
  });

  group('requestCode', () {
    test('asks for the narrowest scope and reads the code pair back', () async {
      final gh = _Github((_, _) => http.Response('{}', 200));
      final grant = await gh.flow().requestCode();

      final req = gh.requests.single;
      expect(req.method, 'POST');
      expect(req.url.toString(), 'https://github.test/login/device/code');
      expect(req.headers['Accept'], 'application/json');
      expect(gh.bodies.single, {
        'client_id': _clientId,
        'scope': kGitHubOAuthScope,
      });
      // The scope is the whole point of the issue: `public_repo` is the
      // narrowest one that can open an issue on a public repository.
      expect(kGitHubOAuthScope, 'public_repo');

      expect(grant.deviceCode, 'dev-code');
      expect(grant.userCode, 'WDJB-MJHT');
      expect(
        grant.verificationUri.toString(),
        'https://github.com/login/device',
      );
      expect(grant.interval, const Duration(seconds: 5));
      expect(grant.expiresIn, const Duration(seconds: 900));
    });

    test('falls back to the documented defaults when GitHub omits the '
        'timings', () async {
      final gh = _Github((_, _) => http.Response('{}', 200))
        ..grant = jsonEncode({
          'device_code': 'd',
          'user_code': 'ABCD-EFGH',
          'verification_uri': 'https://github.com/login/device',
        });

      final grant = await gh.flow().requestCode();
      expect(grant.interval, const Duration(seconds: 5));
      expect(grant.expiresIn, const Duration(minutes: 15));
    });

    test('an error payload is a failure, not a grant', () async {
      final gh = _Github((_, _) => http.Response('{}', 200))
        ..grant = jsonEncode({
          'error': 'unauthorized_client',
          'error_description': 'The client id is not registered.',
        });

      await expectLater(
        gh.flow().requestCode(),
        throwsA(
          isA<DeviceFlowException>()
              .having((e) => e.reason, 'reason', DeviceFlowFailure.failed)
              .having(
                (e) => e.message,
                'message',
                'The client id is not registered.',
              ),
        ),
      );
    });

    test('a payload without a device code is a failure', () async {
      final gh = _Github((_, _) => http.Response('{}', 200))
        ..grant = jsonEncode({'user_code': 'ABCD-EFGH'});

      await expectLater(
        gh.flow().requestCode(),
        _failsWith(DeviceFlowFailure.failed),
      );
    });

    test('a non-JSON answer is a failure, not a crash', () async {
      final gh = _Github((_, _) => http.Response('{}', 200))
        ..grant = '<html>we are down</html>';

      await expectLater(
        gh.flow().requestCode(),
        _failsWith(DeviceFlowFailure.failed),
      );
    });

    test('an HTTP status that is neither 200 nor 400 is a failure', () async {
      final gh = _Github((_, _) => http.Response('{}', 200))
        ..grant = 'oops'
        ..grantStatus = 503;

      await expectLater(
        gh.flow().requestCode(),
        throwsA(
          isA<DeviceFlowException>().having(
            (e) => e.message,
            'message',
            contains('HTTP 503'),
          ),
        ),
      );
    });
  });

  group('pollForToken', () {
    test('waits the interval, keeps going while approval is pending, and '
        'returns the token', () async {
      final gh = _Github(
        (poll, _) => poll < 3
            ? http.Response('{"error":"authorization_pending"}', 200)
            : http.Response(
                '{"access_token":"gho_abc","scope":"public_repo"}',
                200,
              ),
      );

      final token = await gh.flow().pollForToken(
        _fakeGrant(interval: const Duration(seconds: 5)),
      );

      expect(token, 'gho_abc');
      expect(gh.polls, 3);
      expect(
        gh.waits,
        [
          const Duration(seconds: 5),
          const Duration(seconds: 5),
          const Duration(seconds: 5),
        ],
        reason: 'every poll must be preceded by the interval GitHub asked for',
      );
      expect(gh.bodies.first, {
        'client_id': _clientId,
        'device_code': 'dev-code',
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      });
    });

    test('slow_down backs off by five seconds and stays backed off', () async {
      final gh = _Github(
        (poll, _) => switch (poll) {
          1 => http.Response('{"error":"slow_down"}', 200),
          2 => http.Response('{"error":"authorization_pending"}', 200),
          _ => http.Response('{"access_token":"gho_abc"}', 200),
        },
      );

      await gh.flow().pollForToken(
        _fakeGrant(interval: const Duration(seconds: 5)),
      );

      expect(gh.waits, [
        const Duration(seconds: 5),
        const Duration(seconds: 10),
        const Duration(seconds: 10),
      ]);
    });

    test('a slow_down that names an interval is honoured over the default '
        'step', () async {
      final gh = _Github(
        (poll, _) => poll == 1
            ? http.Response('{"error":"slow_down","interval":30}', 200)
            : http.Response('{"access_token":"gho_abc"}', 200),
      );

      await gh.flow().pollForToken(
        _fakeGrant(interval: const Duration(seconds: 5)),
      );

      expect(gh.waits, [
        const Duration(seconds: 5),
        const Duration(seconds: 30),
      ]);
    });

    test('expired_token ends the flow as expired', () async {
      final gh = _Github(
        (_, _) => http.Response('{"error":"expired_token"}', 200),
      );

      await expectLater(
        gh.flow().pollForToken(_fakeGrant()),
        _failsWith(DeviceFlowFailure.expired),
      );
    });

    test('access_denied ends the flow as denied', () async {
      final gh = _Github(
        (_, _) => http.Response('{"error":"access_denied"}', 200),
      );

      await expectLater(
        gh.flow().pollForToken(_fakeGrant()),
        _failsWith(DeviceFlowFailure.denied),
      );
    });

    test('an RFC-shaped 400 is read as a flow error, not a transport '
        'failure', () async {
      final gh = _Github(
        (poll, _) => poll == 1
            ? http.Response('{"error":"authorization_pending"}', 400)
            : http.Response('{"access_token":"gho_abc"}', 400),
      );

      expect(await gh.flow().pollForToken(_fakeGrant()), 'gho_abc');
      expect(gh.polls, 2);
    });

    test('an unknown error ends the flow, quoting what GitHub said', () async {
      final gh = _Github(
        (_, _) => http.Response(
          '{"error":"incorrect_device_code",'
          '"error_description":"That code is not one of ours."}',
          200,
        ),
      );

      await expectLater(
        gh.flow().pollForToken(_fakeGrant()),
        throwsA(
          isA<DeviceFlowException>()
              .having((e) => e.reason, 'reason', DeviceFlowFailure.failed)
              .having(
                (e) => e.message,
                'message',
                'That code is not one of ours.',
              ),
        ),
      );
    });

    // GitHub is not obliged to volunteer `expired_token`, and a loop that
    // polls a dead code forever is the one failure a student never sees end.
    test('gives up on its own once the code has outlived expires_in, even if '
        'GitHub keeps saying pending', () async {
      final gh = _Github(
        (_, _) => http.Response('{"error":"authorization_pending"}', 200),
      );

      await expectLater(
        gh.flow().pollForToken(
          _fakeGrant(
            interval: const Duration(seconds: 5),
            expiresIn: const Duration(seconds: 12),
          ),
        ),
        _failsWith(DeviceFlowFailure.expired),
      );
      expect(gh.polls, 2, reason: 'it must stop polling, not poll forever');
    });

    test('cancelling stops the loop and asks GitHub nothing more', () async {
      bool cancelled = false;
      final gh = _Github((_, _) {
        cancelled = true;
        return http.Response('{"error":"authorization_pending"}', 200);
      });

      await expectLater(
        gh.flow().pollForToken(_fakeGrant(), isCancelled: () => cancelled),
        _failsWith(DeviceFlowFailure.cancelled),
      );
      expect(gh.polls, 1, reason: 'the poll after the cancel must not happen');
    });

    test('a cancel before the first wait costs no request at all', () async {
      final gh = _Github((_, _) => http.Response('{}', 200));

      await expectLater(
        gh.flow().pollForToken(_fakeGrant(), isCancelled: () => true),
        _failsWith(DeviceFlowFailure.cancelled),
      );
      expect(gh.requests, isEmpty);
      expect(gh.waits, isEmpty);
    });

    test('a transport error is reported, not swallowed', () async {
      final flow = GitHubDeviceFlow(
        clientId: _clientId,
        client: MockClient((_) async => throw http.ClientException('no')),
        authBase: Uri.parse('https://github.test/'),
        wait: (_) async {},
      );

      await expectLater(
        flow.pollForToken(_fakeGrant()),
        throwsA(
          isA<DeviceFlowException>()
              .having((e) => e.reason, 'reason', DeviceFlowFailure.failed)
              .having((e) => e.message, 'message', contains('failed')),
        ),
      );
    });

    // `res.body` guesses latin1 for a response without a JSON charset, which
    // is the bug `core/github_release.dart` was bitten by (#45).
    test(
      'the body is decoded as UTF-8 regardless of the declared charset',
      () async {
        final flow = GitHubDeviceFlow(
          clientId: _clientId,
          client: MockClient(
            (_) async => http.Response.bytes(
              utf8.encode('{"error":"x","error_description":"café niet ok"}'),
              200,
              headers: const {'content-type': 'application/octet-stream'},
            ),
          ),
          authBase: Uri.parse('https://github.test/'),
          wait: (_) async {},
        );

        await expectLater(
          flow.pollForToken(_fakeGrant()),
          throwsA(
            isA<DeviceFlowException>().having(
              (e) => e.message,
              'message',
              'café niet ok',
            ),
          ),
        );
      },
    );
  });
}
