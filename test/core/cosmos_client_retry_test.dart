// Issue #7 — transient Cosmos failures (5xx / 408 / 449, a dropped socket,
// a request timeout) are retried inside the REST client before they
// surface. Previously only 429 was retried; everything else escaped as a
// raw SocketException / CosmosException on the first attempt, bypassing
// `safeCosmos` (which only knows about 401/403).
//
// The client is driven over `MockClient` with a zero base backoff so the
// retry schedule runs instantly.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

CosmosClient _client(Future<http.Response> Function(http.Request) handler) {
  return CosmosClient.withHttpClient(
    endpoint: Uri.parse('https://example.documents.azure.com/'),
    auth: MasterKeyAuth(base64Encode(List<int>.filled(32, 7))),
    httpClient: MockClient(handler),
    transientRetryBaseDelay: Duration.zero,
  );
}

http.Response _ok() => http.Response(jsonEncode({'id': 'g1', 'x': 1}), 200);

void main() {
  test('a 503 followed by a 200 returns the doc after one retry', () async {
    var calls = 0;
    final client = _client((_) async {
      calls++;
      return calls == 1 ? http.Response('unavailable', 503) : _ok();
    });

    final doc = await client
        .container('goals')
        .read('g1', partitionKey: 'goal');

    expect(doc, isNotNull);
    expect(doc!['x'], 1);
    expect(calls, 2);
  });

  test('a dropped socket followed by a 200 returns the doc', () async {
    var calls = 0;
    final client = _client((_) async {
      calls++;
      if (calls == 1) throw const SocketException('connection reset');
      return _ok();
    });

    final doc = await client
        .container('goals')
        .read('g1', partitionKey: 'goal');

    expect(doc, isNotNull);
    expect(calls, 2);
  });

  test('a request timeout is retried like a dropped socket', () async {
    var calls = 0;
    final client = _client((_) async {
      calls++;
      if (calls == 1) throw TimeoutException('slow');
      return _ok();
    });

    final docs = await client
        .container('goals')
        .query('SELECT * FROM c', partitionKey: 'goal');

    expect(docs, isEmpty);
    expect(calls, 2);
  });

  test('persistent 503s surface as a transient CosmosException after the '
      'retry budget', () async {
    var calls = 0;
    final client = _client((_) async {
      calls++;
      return http.Response('unavailable', 503);
    });

    await expectLater(
      client.container('goals').read('g1', partitionKey: 'goal'),
      throwsA(
        isA<CosmosException>()
            .having((e) => e.statusCode, 'statusCode', 503)
            .having((e) => e.isTransient, 'isTransient', isTrue),
      ),
    );
    // 1 attempt + 3 retries.
    expect(calls, 4);
  });

  test(
    'a network that never answers surfaces as a network CosmosException',
    () async {
      var calls = 0;
      final client = _client((_) async {
        calls++;
        throw const SocketException('no route');
      });

      await expectLater(
        client.container('goals').upsert({'id': 'g1'}, partitionKey: 'goal'),
        throwsA(
          isA<CosmosException>()
              .having((e) => e.isNetworkError, 'isNetworkError', isTrue)
              .having((e) => e.isTransient, 'isTransient', isTrue)
              .having((e) => e.message, 'message', contains('no route')),
        ),
      );
      expect(calls, 4);
    },
  );

  test('401 is not retried and is still an auth error', () async {
    var calls = 0;
    final client = _client((_) async {
      calls++;
      return http.Response(jsonEncode({'message': 'bad key'}), 401);
    });

    await expectLater(
      client.container('goals').read('g1', partitionKey: 'goal'),
      throwsA(
        isA<CosmosException>()
            .having((e) => e.isAuthError, 'isAuthError', isTrue)
            .having((e) => e.isTransient, 'isTransient', isFalse),
      ),
    );
    expect(calls, 1);
  });

  test('404 on read is still a null, not a retry', () async {
    var calls = 0;
    final client = _client((_) async {
      calls++;
      return http.Response('', 404);
    });

    final doc = await client
        .container('goals')
        .read('nope', partitionKey: 'goal');

    expect(doc, isNull);
    expect(calls, 1);
  });
}
