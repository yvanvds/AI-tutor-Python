// Issue #223 — a replace can be made conditional on the `_etag` of the doc
// as it was read. `CosmosContainer.replace(…, ifMatch:)` sends `If-Match`,
// and Cosmos' 412 ("the doc changed since") surfaces as a CosmosException
// the caller can tell apart, without the client retrying it: only the
// caller can decide anew on the doc as it is now.
//
// The client is driven over `MockClient`, as in cosmos_client_retry_test.

import 'dart:convert';

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

const Map<String, Object?> _doc = {'id': 'u1', 'uid': 'u1', 'x': 1};

void main() {
  test('a replace with ifMatch sends it as If-Match; one without sends '
      'none', () async {
    final sent = <http.Request>[];
    final client = _client((request) async {
      sent.add(request);
      return http.Response(jsonEncode({..._doc, '_etag': '"2"'}), 200);
    });
    final accounts = client.container('accounts');

    final written = await accounts.replace(
      'u1',
      _doc,
      partitionKey: 'u1',
      ifMatch: '"1"',
    );
    await accounts.replace('u1', _doc, partitionKey: 'u1');

    expect(written['_etag'], '"2"');
    expect(sent, hasLength(2));
    expect(sent[0].method, 'PUT');
    expect(sent[0].headers['If-Match'], '"1"');
    expect(sent[0].headers['x-ms-documentdb-partitionkey'], '["u1"]');
    expect(sent[1].headers.containsKey('If-Match'), isFalse);
  });

  test('a 412 surfaces as a precondition failure, once — not retried, not '
      'transient', () async {
    var calls = 0;
    final client = _client((_) async {
      calls++;
      return http.Response(
        jsonEncode({
          'code': 'PreconditionFailed',
          'message':
              'Operation cannot be performed because one of the specified '
              'precondition is not met.',
        }),
        412,
      );
    });

    await expectLater(
      client
          .container('accounts')
          .replace('u1', _doc, partitionKey: 'u1', ifMatch: '"1"'),
      throwsA(
        isA<CosmosException>()
            .having((e) => e.statusCode, 'statusCode', 412)
            .having((e) => e.isPreconditionFailed, 'isPreconditionFailed', true)
            .having((e) => e.code, 'code', 'PreconditionFailed')
            .having((e) => e.isTransient, 'isTransient', isFalse),
      ),
    );
    expect(calls, 1);
  });

  test('no other status is a precondition failure', () {
    for (final status in [400, 404, 409, 429, 503]) {
      expect(CosmosException(status, 'x').isPreconditionFailed, isFalse);
    }
  });
}
