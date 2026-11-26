// #306 — the database through the user's own sign-in. The client sends the
// token as `type=aad&ver=1.0&sig=<token>` (URL-encoded) on reads, queries
// and every kind of write; a 401 renews the token once and tries once more;
// a school on the database key never asks for a sign-in token, and a school
// on the sign-in never asks for the key.
//
// Everything runs over fakes: a token function and a `MockClient` for
// Cosmos. Nothing reaches Entra or a real database.

import 'dart:convert';

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/services/auth/cosmos_token_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A fake token function: hands out `token-<n>`, a new n on each forced
/// renewal, and records how it was asked.
class _FakeTokens {
  int renewals = 0;
  bool failRenewal = false;

  Future<String> call({bool forceRefresh = false}) async {
    if (forceRefresh) {
      if (failRenewal) {
        throw CosmosException(401, 'no token', code: 'TokenRequestFailed');
      }
      renewals++;
    }
    return 'token-$renewals';
  }
}

String _header(String token) =>
    Uri.encodeComponent('type=aad&ver=1.0&sig=$token');

CosmosClient _client(
  _FakeTokens tokens,
  Future<http.Response> Function(http.Request) handler,
) => CosmosClient.withHttpClient(
  endpoint: Uri.parse('https://example.documents.azure.com/'),
  auth: AadTokenAuth(tokens.call),
  httpClient: MockClient(handler),
  transientRetryBaseDelay: Duration.zero,
);

http.Response _ok([Map<String, Object?> body = const {'id': 'u1'}]) =>
    http.Response(jsonEncode(body), 200);

void main() {
  test('reads, queries and writes all carry the sign-in token', () async {
    final tokens = _FakeTokens();
    final sent = <http.Request>[];
    final client = _client(tokens, (request) async {
      sent.add(request);
      if (request.headers['x-ms-documentdb-isquery'] == 'true') {
        return _ok({'Documents': <Object>[]});
      }
      return _ok();
    });
    final c = client.container('accounts');
    const doc = {'id': 'u1', 'uid': 'u1'};

    await c.read('u1', partitionKey: 'u1');
    await c.query('SELECT * FROM c', partitionKey: 'u1');
    await c.create(doc, partitionKey: 'u1');
    await c.upsert(doc, partitionKey: 'u1');
    await c.replace('u1', doc, partitionKey: 'u1', ifMatch: '"1"');
    await c.delete('u1', partitionKey: 'u1');
    await c.executeBatch([BatchOperation.upsert(doc)], partitionKey: 'u1');

    expect(sent, hasLength(7));
    for (final request in sent) {
      expect(request.headers['Authorization'], _header('token-0'));
      expect(request.headers['x-ms-version'], '2018-12-31');
    }
    expect(tokens.renewals, 0);
  });

  test(
    'a 401 renews the token once and the retry carries the new one',
    () async {
      final tokens = _FakeTokens();
      final sent = <http.Request>[];
      final client = _client(tokens, (request) async {
        sent.add(request);
        return sent.length == 1
            ? http.Response(jsonEncode({'message': 'expired'}), 401)
            : _ok({'id': 'g1', 'x': 1});
      });

      final doc = await client
          .container('goals')
          .read('g1', partitionKey: 'goal');

      expect(doc!['x'], 1);
      expect(sent, hasLength(2));
      expect(tokens.renewals, 1);
      expect(sent[0].headers['Authorization'], _header('token-0'));
      expect(sent[1].headers['Authorization'], _header('token-1'));
    },
  );

  test('a second 401 surfaces as an auth error, after one renewal', () async {
    final tokens = _FakeTokens();
    var calls = 0;
    final client = _client(tokens, (_) async {
      calls++;
      return http.Response(jsonEncode({'message': 'no role'}), 401);
    });

    await expectLater(
      client.container('goals').upsert({'id': 'g1'}, partitionKey: 'goal'),
      throwsA(
        isA<CosmosException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.isAuthError, 'isAuthError', isTrue),
      ),
    );
    expect(calls, 2);
    expect(tokens.renewals, 1);
  });

  test(
    'a renewal that fails leaves the 401 as it was, without a retry',
    () async {
      final tokens = _FakeTokens()..failRenewal = true;
      var calls = 0;
      final client = _client(tokens, (_) async {
        calls++;
        return http.Response(jsonEncode({'message': 'expired'}), 401);
      });

      await expectLater(
        client.container('goals').read('g1', partitionKey: 'goal'),
        throwsA(
          isA<CosmosException>().having((e) => e.statusCode, 'status', 401),
        ),
      );
      expect(calls, 1);
    },
  );

  test('a 403 (no role) is not retried with a new token', () async {
    final tokens = _FakeTokens();
    var calls = 0;
    final client = _client(tokens, (_) async {
      calls++;
      return http.Response(jsonEncode({'message': 'forbidden'}), 403);
    });

    await expectLater(
      client.container('goals').read('g1', partitionKey: 'goal'),
      throwsA(
        isA<CosmosException>().having((e) => e.statusCode, 'status', 403),
      ),
    );
    expect(calls, 1);
    expect(tokens.renewals, 0);
  });

  test('no token at all fails the call before anything is sent, as nobody '
      'signed in rather than an auth error (#345)', () async {
    var calls = 0;
    final client = CosmosClient.withHttpClient(
      endpoint: Uri.parse('https://example.documents.azure.com/'),
      auth: AadTokenAuth(
        ({bool forceRefresh = false}) async => throw CosmosException(
          401,
          'not signed in',
          code: kCosmosNotSignedIn,
        ),
      ),
      httpClient: MockClient((_) async {
        calls++;
        return _ok();
      }),
      transientRetryBaseDelay: Duration.zero,
    );

    await expectLater(
      client.container('goals').read('g1', partitionKey: 'goal'),
      throwsA(
        isA<CosmosException>()
            .having((e) => e.isNotSignedIn, 'not signed in', isTrue)
            .having((e) => e.isAuthError, 'auth', isFalse),
      ),
    );
    expect(calls, 0);
  });

  test('the database key never renews: a 401 stays a single request', () async {
    var calls = 0;
    final client = CosmosClient.withHttpClient(
      endpoint: Uri.parse('https://example.documents.azure.com/'),
      auth: MasterKeyAuth(base64Encode(List<int>.filled(32, 7))),
      httpClient: MockClient((_) async {
        calls++;
        return http.Response('{"message":"bad key"}', 401);
      }),
      transientRetryBaseDelay: Duration.zero,
    );

    await expectLater(
      client.container('goals').read('g1', partitionKey: 'goal'),
      throwsA(isA<CosmosException>()),
    );
    expect(calls, 1);
  });

  group('CosmosClient.forMode', () {
    SchoolConfig school(DatabaseAccess access) => SchoolConfig(
      tenantId: '11111111-1111-1111-1111-111111111111',
      clientId: '22222222-2222-2222-2222-222222222222',
      redirectUri: 'http://localhost',
      databaseEndpoint: Uri.parse('https://test-school.documents.azure.com/'),
      databaseAccess: access,
    );

    test('a school on the sign-in never asks for the database key', () {
      var keyAsked = false;
      CosmosClient.forMode(
        SchoolMode(school(DatabaseAccess.signIn)),
        databaseKey: () {
          keyAsked = true;
          throw StateError('no key in this build');
        },
        tokenSource: CosmosTokenSource(
          school: school(DatabaseAccess.signIn),
          tokensPrefsKey: 'unused',
        ),
      );
      expect(keyAsked, isFalse);
    });

    test('a school on the database key asks for it, as before', () {
      var keyAsked = false;
      CosmosClient.forMode(
        SchoolMode(school(DatabaseAccess.masterKey)),
        databaseKey: () {
          keyAsked = true;
          return base64Encode(List<int>.filled(32, 7));
        },
        // In a build with school data; without, it is the sign-in (#336).
        schoolDataInBuild: () => true,
      );
      expect(keyAsked, isTrue);
    });
  });
}
