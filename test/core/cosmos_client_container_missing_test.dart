// Issue #170 — "Release" failed with a bare gateway 404 because the
// `reports` container did not exist in the account. The REST client could
// not tell that apart from a missing document: a document read turned the
// 404 into `null` ("not released yet"), and the upsert after it failed with
// "Entity with the specified id does not exist in the system", which names
// neither the container nor the fix.
//
// The gateway uses those same words for a missing document in a container
// that does exist, so the client now reads the container's own metadata on a
// 404 and, when that is a 404 too, throws `kCosmosContainerNotFound` with a
// message that names the container. These tests pin both sides: the missing
// container is loud on every operation, and a missing document is still the
// quiet `null` / idempotent delete it always was.

import 'dart:convert';

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/unprovisioned_cosmos.dart';

final Matcher _containerMissing = isA<CosmosException>()
    .having((e) => e.statusCode, 'statusCode', 404)
    .having((e) => e.isContainerNotFound, 'isContainerNotFound', isTrue)
    .having(
      (e) => e.message,
      'message',
      allOf(
        contains('Container "reports" does not exist'),
        contains('"python-tutor"'),
        contains('README'),
      ),
    );

/// An account where the container exists; [metadata] answers the check of
/// its own metadata, every document call is a plain "no such document".
({CosmosClient client, List<http.Request> requests}) _existing({
  http.Response Function()? metadata,
}) {
  final requests = <http.Request>[];
  final client = CosmosClient.withHttpClient(
    endpoint: Uri.parse('https://example.documents.azure.com/'),
    auth: MasterKeyAuth(base64Encode(List<int>.filled(32, 7))),
    transientRetryBaseDelay: Duration.zero,
    httpClient: MockClient((request) async {
      requests.add(request);
      if (!request.url.path.contains('/docs')) {
        return metadata?.call() ??
            http.Response(jsonEncode({'id': 'reports'}), 200);
      }
      return http.Response(
        jsonEncode({
          'code': 'NotFound',
          'message':
              'Entity with the specified id does not exist in the system.',
        }),
        404,
      );
    }),
  );
  return (client: client, requests: requests);
}

bool _isMetadataRead(http.Request r) =>
    r.method == 'GET' && !r.url.path.contains('/docs');

void main() {
  group('a container missing from the account', () {
    test('a document read throws instead of reading as "no document"', () {
      final cosmos = UnprovisionedCosmos('reports');
      expect(
        cosmos.container.read('u1_m1', partitionKey: 'u1'),
        throwsA(_containerMissing),
      );
    });

    test('every other operation names the container too', () async {
      final container = UnprovisionedCosmos('reports').container;
      final doc = {'id': 'u1_m1', 'uid': 'u1'};
      final calls = <String, Future<Object?> Function()>{
        'query': () => container.query(
          'SELECT * FROM c WHERE c.uid = @uid',
          parameters: {'@uid': 'u1'},
          partitionKey: 'u1',
        ),
        'create': () => container.create(doc, partitionKey: 'u1'),
        'upsert': () => container.upsert(doc, partitionKey: 'u1'),
        'replace': () => container.replace('u1_m1', doc, partitionKey: 'u1'),
        'delete': () => container.delete('u1_m1', partitionKey: 'u1'),
        'executeBatch': () => container.executeBatch([
          BatchOperation.upsert(doc),
        ], partitionKey: 'u1'),
      };
      for (final entry in calls.entries) {
        await expectLater(
          entry.value(),
          throwsA(_containerMissing),
          reason: entry.key,
        );
      }
    });

    test('the error reads as what it is', () async {
      final container = UnprovisionedCosmos('reports').container;
      Object? error;
      try {
        await container.read('u1_m1', partitionKey: 'u1');
      } catch (e) {
        error = e;
      }
      expect(
        '$error',
        'CosmosException(404 ContainerNotFound): Container "reports" does '
            'not exist in Cosmos database "python-tutor". Create it with the '
            'partition key listed in README step 3.',
      );
    });

    test('is asked again on the next call, so creating it while the app is '
        'open is picked up without a restart', () async {
      var created = false;
      final requests = <http.Request>[];
      final container = CosmosClient.withHttpClient(
        endpoint: Uri.parse('https://example.documents.azure.com/'),
        auth: MasterKeyAuth(base64Encode(List<int>.filled(32, 7))),
        transientRetryBaseDelay: Duration.zero,
        httpClient: MockClient((request) async {
          requests.add(request);
          if (_isMetadataRead(request) && created) {
            return http.Response(jsonEncode({'id': 'reports'}), 200);
          }
          return http.Response('{"code":"NotFound","message":"x"}', 404);
        }),
      ).container('reports');

      await expectLater(
        container.read('u1_m1', partitionKey: 'u1'),
        throwsA(_containerMissing),
      );
      created = true;
      expect(await container.read('u1_m1', partitionKey: 'u1'), isNull);
      expect(requests.where(_isMetadataRead), hasLength(2));
    });
  });

  group('a document missing from a container that exists', () {
    test(
      'still reads as null, and the container is checked only once',
      () async {
        final (:client, :requests) = _existing();
        final container = client.container('reports');

        expect(await container.read('u1_m1', partitionKey: 'u1'), isNull);
        expect(await container.read('u2_m1', partitionKey: 'u2'), isNull);
        // A new handle on the same client shares what it learned.
        expect(
          await client.container('reports').read('u3_m1', partitionKey: 'u3'),
          isNull,
        );

        expect(requests.where(_isMetadataRead), hasLength(1));
        expect(
          requests.where(_isMetadataRead).single.url.path,
          endsWith('/dbs/python-tutor/colls/reports'),
        );
      },
    );

    test('a delete of it stays idempotent', () async {
      final (:client, requests: _) = _existing();
      await client.container('reports').delete('u1_m1', partitionKey: 'u1');
    });

    test('a replace of it is a plain 404, not a missing container', () {
      final (:client, requests: _) = _existing();
      expect(
        client.container('reports').replace('u1_m1', {
          'id': 'u1_m1',
        }, partitionKey: 'u1'),
        throwsA(
          isA<CosmosException>()
              .having((e) => e.isNotFound, 'isNotFound', isTrue)
              .having(
                (e) => e.isContainerNotFound,
                'isContainerNotFound',
                isFalse,
              ),
        ),
      );
    });

    test('a check that cannot answer (403 on metadata) keeps the old '
        '"no document" reading instead of inventing an auth error', () async {
      final (:client, :requests) = _existing(
        metadata: () => http.Response('{"code":"Forbidden"}', 403),
      );
      expect(
        await client.container('reports').read('u1_m1', partitionKey: 'u1'),
        isNull,
      );
      expect(requests.where(_isMetadataRead), hasLength(1));
    });
  });
}
