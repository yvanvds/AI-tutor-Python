// #306 — the database token from the user's own sign-in. Fetched silently
// with the stored refresh token, for the scope of the database account; kept
// in memory and renewed before it expires; never handed to another sign-in.
//
// The token endpoint is a `MockClient`; the clock is a fake.

import 'dart:convert';

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/auth/cosmos_token_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final SchoolConfig _school = SchoolConfig(
  tenantId: '11111111-1111-1111-1111-111111111111',
  clientId: '22222222-2222-2222-2222-222222222222',
  redirectUri: 'http://localhost',
  databaseEndpoint: Uri.parse('https://test-school.documents.azure.com:443/'),
  databaseAccess: DatabaseAccess.signIn,
);

const String _key = AuthService.tokensPrefsKey;

String _stored(String? refreshToken) => jsonEncode({
  'access_token': 'graph-access',
  'refresh_token': refreshToken,
  'id_token': 'id',
  'access_token_expiry': null,
});

/// A fake token endpoint: hands out `cosmos-<n>` for the n-th request.
class _Endpoint {
  final List<http.Request> requests = [];
  String? rotate;
  http.Response Function()? answer;

  late final MockClient client = MockClient((request) async {
    requests.add(request);
    final custom = answer;
    if (custom != null) return custom();
    return http.Response(
      jsonEncode({
        'access_token': 'cosmos-${requests.length}',
        'expires_in': 4800,
        if (rotate != null) 'refresh_token': rotate,
      }),
      200,
    );
  });
}

void main() {
  late DateTime now;
  late _Endpoint endpoint;

  CosmosTokenSource source() => CosmosTokenSource(
    school: _school,
    tokensPrefsKey: _key,
    httpClient: endpoint.client,
    now: () => now,
  );

  setUp(() {
    now = DateTime.utc(2026, 11, 19, 9);
    endpoint = _Endpoint();
    SharedPreferences.setMockInitialValues({_key: _stored('refresh-1')});
  });

  test('the scope is the database account without its port', () {
    expect(
      CosmosTokenSource.scopeFor(_school.databaseEndpoint),
      'https://test-school.documents.azure.com/user_impersonation',
    );
  });

  test('asks the school tenant for the database scope with the stored '
      'refresh token', () async {
    final token = await source().token();

    expect(token, 'cosmos-1');
    final request = endpoint.requests.single;
    expect(
      request.url.toString(),
      'https://login.microsoftonline.com/${_school.tenantId}/oauth2/v2.0/token',
    );
    expect(request.bodyFields, {
      'client_id': _school.clientId,
      'grant_type': 'refresh_token',
      'refresh_token': 'refresh-1',
      'scope':
          'https://test-school.documents.azure.com/user_impersonation '
          'offline_access',
    });
  });

  test('keeps the token while it is valid and renews it just before it '
      'expires', () async {
    final tokens = source();
    expect(await tokens.token(), 'cosmos-1');

    now = now.add(const Duration(minutes: 70));
    expect(await tokens.token(), 'cosmos-1');
    expect(endpoint.requests, hasLength(1));

    // Valid for 80 minutes; within five minutes of the end it is renewed.
    now = now.add(const Duration(minutes: 6));
    expect(await tokens.token(), 'cosmos-2');
    expect(endpoint.requests, hasLength(2));
  });

  test('forceRefresh renews a token that is still valid', () async {
    final tokens = source();
    await tokens.token();
    expect(await tokens.token(forceRefresh: true), 'cosmos-2');
  });

  test('requests that need a token together share one renewal', () async {
    final tokens = source();
    final all = await Future.wait([
      tokens.token(),
      tokens.token(),
      tokens.token(),
    ]);
    expect(all, ['cosmos-1', 'cosmos-1', 'cosmos-1']);
    expect(endpoint.requests, hasLength(1));
  });

  test('a rotated refresh token goes back to the stored sign-in, the rest '
      'of it untouched, and the cached token stays usable', () async {
    endpoint.rotate = 'refresh-2';
    final tokens = source();
    await tokens.token();

    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString(_key)!) as Map<String, dynamic>;
    expect(stored['refresh_token'], 'refresh-2');
    expect(stored['access_token'], 'graph-access');
    expect(stored['id_token'], 'id');

    expect(await tokens.token(), 'cosmos-1');
    expect(endpoint.requests, hasLength(1));
  });

  test('a new sign-in gets its own token, never the previous one', () async {
    final tokens = source();
    await tokens.token();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _stored('someone-else'));

    expect(await tokens.token(), 'cosmos-2');
    expect(endpoint.requests.last.bodyFields['refresh_token'], 'someone-else');
  });

  test('after a sign-out there is no token, cached or not', () async {
    final tokens = source();
    await tokens.token();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);

    await expectLater(
      tokens.token(),
      throwsA(
        isA<CosmosException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.code, 'code', 'NotSignedIn'),
      ),
    );
    expect(endpoint.requests, hasLength(1));
  });

  test('a refused token request is an auth error; a failing token service '
      'is not', () async {
    endpoint.answer = () => http.Response('{"error":"invalid_grant"}', 400);
    await expectLater(
      source().token(),
      throwsA(
        isA<CosmosException>().having((e) => e.isAuthError, 'auth', isTrue),
      ),
    );

    endpoint.answer = () => http.Response('unavailable', 503);
    await expectLater(
      source().token(),
      throwsA(
        isA<CosmosException>()
            .having((e) => e.statusCode, 'statusCode', 503)
            .having((e) => e.isAuthError, 'isAuthError', isFalse),
      ),
    );
  });

  test(
    'AadTokenAuth sends the token and, after a 401, a renewed one',
    () async {
      final auth = AadTokenAuth(source().token);
      Future<String> header() async => await auth.authHeader(
        verb: 'GET',
        resourceType: 'docs',
        resourceLink: 'dbs/d/colls/c/docs/x',
        date: 'Thu, 19 Nov 2026 09:00:00 GMT',
      );

      expect(
        await header(),
        Uri.encodeComponent('type=aad&ver=1.0&sig=cosmos-1'),
      );
      expect(await auth.renewAfterUnauthorized(), isTrue);
      expect(
        await header(),
        Uri.encodeComponent('type=aad&ver=1.0&sig=cosmos-2'),
      );
    },
  );
}
