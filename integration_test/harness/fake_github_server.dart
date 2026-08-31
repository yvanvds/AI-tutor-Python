// A loopback stand-in for GitHub, so an end-to-end flow can drive the real
// bug reporter — the OAuth device flow (#57) and the issue it eventually
// files (#25) — without reaching github.com and without an account.
//
// It answers the four requests the app makes, in the shapes GitHub uses:
//
//   - `POST /login/device/code` with a fixed code pair, a one-second polling
//     interval (GitHub's five would make every flow wait five real seconds
//     per poll) and a fifteen-minute expiry;
//   - `POST /login/oauth/access_token` with `authorization_pending` until a
//     flow sets [approved], or with whatever [pollError] names — which is how
//     the refusal and expiry paths are driven;
//   - `GET /user`, the call the card makes to show who is connected;
//   - `POST /repos/<owner>/<repo>/issues`, recorded in [issues] so a flow can
//     assert on what the app actually posted.

import 'dart:convert';
import 'dart:io';

/// The token the flow hands out once a code is approved.
const String kFakeGitHubToken = 'gho_integrationtesttoken';

/// Who that token belongs to, as `/user` reports it.
const String kFakeGitHubLogin = 'student-tester';

/// The code pair a student sees and types.
const String kFakeUserCode = 'WDJB-MJHT';
const String _deviceCode = 'fake-device-code';

class FakeGitHubServer {
  FakeGitHubServer._(this._server, this.base, this.verificationUri);

  final HttpServer _server;

  /// What the harness points both `gitHubOAuthBaseProvider` and
  /// `gitHubApiBaseProvider` at. The two are separate hosts in production
  /// (github.com and api.github.com) but the paths do not collide, so one
  /// server can play both.
  final Uri base;

  /// Where the app tells the student to type the code. A real URL on purpose
  /// — the flow asserts the app hands exactly this to the browser launcher.
  final Uri verificationUri;

  /// Flipped by a flow to stand for "the student approved it in the browser".
  bool approved = false;

  /// When set (`access_denied`, `expired_token`, …), every poll answers with
  /// that error instead.
  String? pollError;

  /// How many times the app polled the token endpoint.
  int polls = 0;

  /// Every issue the app posted, as the decoded request body.
  final List<Map<String, dynamic>> issues = <Map<String, dynamic>>[];

  static Future<FakeGitHubServer> start({
    Duration interval = const Duration(seconds: 1),
    String repo = 'yvanvds/AI-tutor-Python',
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = Uri.parse('http://${server.address.address}:${server.port}');
    final fake = FakeGitHubServer._(
      server,
      base,
      base.resolve('/login/device'),
    );

    server.listen((request) async {
      final String path = request.uri.path;
      final String body = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      );

      if (path == '/login/device/code') {
        request.response.write(
          jsonEncode({
            'device_code': _deviceCode,
            'user_code': kFakeUserCode,
            'verification_uri': fake.verificationUri.toString(),
            'interval': interval.inSeconds,
            'expires_in': 900,
          }),
        );
      } else if (path == '/login/oauth/access_token') {
        fake.polls++;
        final String? error = fake.pollError;
        if (error != null) {
          request.response.write(jsonEncode({'error': error}));
        } else if (!fake.approved) {
          request.response.write(
            jsonEncode({'error': 'authorization_pending'}),
          );
        } else {
          request.response.write(
            jsonEncode({
              'access_token': kFakeGitHubToken,
              'token_type': 'bearer',
              'scope': 'public_repo',
            }),
          );
        }
      } else if (path == '/user') {
        if (request.headers.value('Authorization') !=
            'Bearer $kFakeGitHubToken') {
          request.response.statusCode = HttpStatus.unauthorized;
          request.response.write(jsonEncode({'message': 'Bad credentials'}));
        } else {
          request.response.write(jsonEncode({'login': kFakeGitHubLogin}));
        }
      } else if (path == '/repos/$repo/issues') {
        final Object? decoded = jsonDecode(body);
        fake.issues.add((decoded as Map).cast<String, dynamic>());
        request.response.statusCode = HttpStatus.created;
        request.response.write(
          jsonEncode({
            'html_url': 'https://github.com/$repo/issues/${fake.issues.length}',
          }),
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(jsonEncode({'message': 'Not Found'}));
      }
      await request.response.close();
    });

    return fake;
  }

  Future<void> close() => _server.close(force: true);
}
