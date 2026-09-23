// A Cosmos account, driven through the real REST client, in which one
// container was never created (#170) — the state the live deployment was in
// when "Release" first failed: `reports` had been added to the app (#150)
// but not to the account.
//
// Unlike `InMemoryCosmos`, this goes through `CosmosContainer`'s own HTTP
// handling, because that is where the bug lived: a document read turned the
// gateway's 404 into "no such document", and only the write that followed
// failed, with a message that did not name the container. The answers below
// are what the live gateway returned on 2026-09-23 for a container that does
// not exist (probed read-only):
//
//   - a document read, write or query: 404, "Entity with the specified id
//     does not exist in the system" — the very words it also uses for a
//     missing document in a container that does exist;
//   - the container's own metadata (`GET dbs/{db}/colls/{coll}`): 404,
//     "Resource Not Found".

import 'dart:convert';

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class UnprovisionedCosmos {
  UnprovisionedCosmos(this.containerId) {
    container = CosmosClient.withHttpClient(
      endpoint: Uri.parse('https://example.documents.azure.com/'),
      auth: MasterKeyAuth(base64Encode(List<int>.filled(32, 7))),
      httpClient: MockClient(_answer),
      transientRetryBaseDelay: Duration.zero,
    ).container(containerId);
  }

  /// The container the account lacks.
  final String containerId;

  /// The real REST handle to it.
  late final CosmosContainer container;

  /// Every request the client sent, in order.
  final List<http.Request> requests = [];

  /// The requests that tried to change a document — anything but a read,
  /// a query or the container-metadata check.
  Iterable<http.Request> get writes => requests.where(
    (r) => r.method != 'GET' && r.headers['x-ms-documentdb-isquery'] != 'true',
  );

  Future<http.Response> _answer(http.Request request) async {
    requests.add(request);
    final metadataRead =
        request.method == 'GET' && !request.url.path.contains('/docs');
    return http.Response(
      jsonEncode({
        'code': 'NotFound',
        'message': metadataRead
            ? 'Message: {"Errors":["Resource Not Found. Learn more: '
                  'https://aka.ms/cosmosdb-tsg-not-found"]}'
            : 'Entity with the specified id does not exist in the system. '
                  'More info: https://aka.ms/cosmosdb-tsg-not-found',
      }),
      404,
      headers: {'content-type': 'application/json'},
    );
  }
}
