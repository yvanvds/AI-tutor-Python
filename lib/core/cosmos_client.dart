// Thin REST wrapper around Azure Cosmos DB for NoSQL.
//
// We talk to the Cosmos REST API directly via package:http rather than pulling
// in a third-party SDK. All operations
// in this app fit a small surface area — read / query / upsert / delete plus
// transactional batch — so a hand-rolled client is the safest long-term bet.
//
// Auth is pluggable via [CosmosAuth]. Step 1 (this scaffolding) defaults to a
// [MasterKeyAuth] reading the obfuscated key from [AzureConfig]. When MSAL
// lands in Step 3, swap in an [AadTokenAuth] without touching call sites.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/services/config/azure_config.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

const String _apiVersion = '2018-12-31';
const String _databaseId = 'python-tutor';
const Duration _requestTimeout = Duration(seconds: 15);
const int _maxThrottleRetries = 3;
const Duration _maxThrottleBackoff = Duration(seconds: 5);

/// Transient failures (#7) — a dropped socket, a request timeout, or a
/// 408 / 449 / 5xx from Cosmos — are retried in-client with exponential
/// backoff before they surface, so a single blip during a graded turn
/// doesn't lose the student's answer. Cosmos' own guidance is to retry
/// 449 ("RetryWith") and 503 immediately; 5xx in general is safe to retry
/// because every write we do is an idempotent upsert / replace / delete
/// or a batch that either commits or doesn't.
const int _maxTransientRetries = 3;
const Duration _kTransientRetryBaseDelay = Duration(milliseconds: 200);

/// Status code used for [CosmosException]s that wrap a network-level
/// failure (no HTTP response at all: connection refused, DNS, timeout).
const int kCosmosNetworkStatus = 0;

const Set<int> _transientStatusCodes = {
  kCosmosNetworkStatus,
  408,
  449,
  500,
  502,
  503,
  504,
};

/// Thrown for any non-2xx response from Cosmos. Callers (and `safeCosmos`)
/// branch on [statusCode] — 401/403 means a bad key or revoked role
/// (force the user back through sign-in / reset), 429 means throttling
/// (the client retries internally, so by the time this surfaces we've
/// already exhausted retries). Network-level failures are wrapped with
/// [kCosmosNetworkStatus] so callers see one exception type for "Cosmos
/// didn't answer" regardless of where in the stack it failed.
class CosmosException implements Exception {
  CosmosException(this.statusCode, this.message, {this.code, this.activityId});

  final int statusCode;
  final String message;
  final String? code;
  final String? activityId;

  bool get isAuthError => statusCode == 401 || statusCode == 403;
  bool get isThrottled => statusCode == 429;
  bool get isNotFound => statusCode == 404;

  /// No HTTP response at all (socket / DNS / timeout).
  bool get isNetworkError => statusCode == kCosmosNetworkStatus;

  /// Worth retrying: the client already did, so by the time this surfaces
  /// the retries are exhausted — but callers can still treat it as "try
  /// again later" rather than "something is broken".
  bool get isTransient => _transientStatusCodes.contains(statusCode);

  @override
  String toString() {
    final parts = <String>['CosmosException($statusCode'];
    if (code != null) parts.add(' $code');
    parts.add('): $message');
    if (activityId != null) parts.add(' [activity=$activityId]');
    return parts.join();
  }
}

/// Produces the `Authorization` header for a Cosmos REST request.
abstract class CosmosAuth {
  /// [verb] is the HTTP method (`GET`, `POST`, etc.).
  /// [resourceType] is the Cosmos resource type (`docs`, `colls`, `dbs`).
  /// [resourceLink] is the path WITHOUT a leading slash to the resource the
  /// request acts on. For document-level ops it is
  /// `dbs/{db}/colls/{coll}/docs/{id}`; for collection-level ops (POST a new
  /// doc, query) it is `dbs/{db}/colls/{coll}`.
  /// [date] is the value sent in `x-ms-date` (RFC 1123, mixed case).
  String authHeader({
    required String verb,
    required String resourceType,
    required String resourceLink,
    required String date,
  });
}

/// Master-key auth: HMAC-SHA256 over the canonical request, base64-encoded,
/// then URL-encoded as `type=master&ver=1.0&sig=<sig>`.
class MasterKeyAuth implements CosmosAuth {
  MasterKeyAuth(String key) : _key = base64Decode(key);

  final List<int> _key;

  @override
  String authHeader({
    required String verb,
    required String resourceType,
    required String resourceLink,
    required String date,
  }) {
    final payload =
        '${verb.toLowerCase()}\n'
        '${resourceType.toLowerCase()}\n'
        '$resourceLink\n'
        '${date.toLowerCase()}\n'
        '\n';
    final hmac = Hmac(sha256, _key);
    final sig = base64Encode(hmac.convert(utf8.encode(payload)).bytes);
    return Uri.encodeComponent('type=master&ver=1.0&sig=$sig');
  }
}

/// AAD bearer-token auth (Step 3). Token provider returns a fresh access
/// token for the Cosmos resource (`https://<account>.documents.azure.com`).
/// Caching/refresh is the provider's responsibility.
class AadTokenAuth implements CosmosAuth {
  AadTokenAuth(this._tokenProvider);

  final String Function() _tokenProvider;

  @override
  String authHeader({
    required String verb,
    required String resourceType,
    required String resourceLink,
    required String date,
  }) {
    return Uri.encodeComponent('type=aad&ver=1.0&sig=${_tokenProvider()}');
  }
}

/// Lazy singleton. First access pulls config out of `AzureConfig`; tests or
/// the Step 3 auth swap can pre-seed via [overrideInstance].
class CosmosClient {
  CosmosClient._({
    required Uri endpoint,
    required CosmosAuth auth,
    http.Client? httpClient,
    Duration transientRetryBaseDelay = _kTransientRetryBaseDelay,
  }) : _endpoint = endpoint,
       _auth = auth,
       _http = httpClient ?? http.Client(),
       _transientRetryBaseDelay = transientRetryBaseDelay;

  /// Test seam: a client over an injected [http.Client]. Production code
  /// goes through [instance].
  @visibleForTesting
  factory CosmosClient.withHttpClient({
    required Uri endpoint,
    required CosmosAuth auth,
    required http.Client httpClient,
    Duration transientRetryBaseDelay = _kTransientRetryBaseDelay,
  }) => CosmosClient._(
    endpoint: endpoint,
    auth: auth,
    httpClient: httpClient,
    transientRetryBaseDelay: transientRetryBaseDelay,
  );

  static CosmosClient? _instance;

  static CosmosClient get instance {
    return _instance ??= CosmosClient._(
      endpoint: Uri.parse(AzureConfig.cosmosEndpoint),
      auth: MasterKeyAuth(AzureConfig.cosmosKey),
    );
  }

  static void overrideInstance(CosmosClient client) => _instance = client;

  final Uri _endpoint;
  final CosmosAuth _auth;
  final http.Client _http;
  final Duration _transientRetryBaseDelay;

  CosmosContainer container(String containerId) =>
      CosmosContainer._(this, _databaseId, containerId);

  Future<http.Response> _send({
    required String verb,
    required String resourceType,
    required String resourceLink,
    required String pathSegment,
    Map<String, String>? extraHeaders,
    Object? body,
  }) async {
    final url = _endpoint.resolve(pathSegment);
    final encodedBody = body == null ? null : utf8.encode(jsonEncode(body));

    int throttleAttempt = 0;
    int transientAttempt = 0;
    while (true) {
      final date = HttpDate.format(DateTime.now().toUtc());
      final headers = <String, String>{
        'x-ms-version': _apiVersion,
        'x-ms-date': date,
        'Authorization': _auth.authHeader(
          verb: verb,
          resourceType: resourceType,
          resourceLink: resourceLink,
          date: date,
        ),
        if (encodedBody != null) 'Content-Type': 'application/json',
        ...?extraHeaders,
      };

      final request = http.Request(verb, url)..headers.addAll(headers);
      if (encodedBody != null) request.bodyBytes = encodedBody;

      final http.Response response;
      try {
        final streamed = await _http.send(request).timeout(_requestTimeout);
        response = await http.Response.fromStream(streamed);
      } on Object catch (e) {
        if (!_isNetworkFailure(e)) rethrow;
        if (transientAttempt < _maxTransientRetries) {
          await Future.delayed(_transientBackoff(transientAttempt));
          transientAttempt++;
          continue;
        }
        throw CosmosException(
          kCosmosNetworkStatus,
          'No response from Cosmos after ${transientAttempt + 1} attempts: $e',
          code: 'NetworkError',
        );
      }

      if (response.statusCode == 429 && throttleAttempt < _maxThrottleRetries) {
        final retryMs =
            int.tryParse(response.headers['x-ms-retry-after-ms'] ?? '') ??
            (200 * (1 << throttleAttempt));
        final delay = Duration(
          milliseconds: retryMs.clamp(0, _maxThrottleBackoff.inMilliseconds),
        );
        await Future.delayed(delay);
        throttleAttempt++;
        continue;
      }

      if (_transientStatusCodes.contains(response.statusCode) &&
          transientAttempt < _maxTransientRetries) {
        await Future.delayed(_transientBackoff(transientAttempt));
        transientAttempt++;
        continue;
      }

      return response;
    }
  }

  Duration _transientBackoff(int attempt) {
    final ms = _transientRetryBaseDelay.inMilliseconds * (1 << attempt);
    return Duration(
      milliseconds: ms.clamp(0, _maxThrottleBackoff.inMilliseconds),
    );
  }

  static bool _isNetworkFailure(Object e) =>
      e is SocketException ||
      e is TimeoutException ||
      e is http.ClientException ||
      e is HttpException;
}

/// Handle to one container. Cheap to create — `CosmosPaths` makes new
/// instances per call without caching.
class CosmosContainer {
  CosmosContainer._(this._client, this._db, this._coll);

  final CosmosClient _client;
  final String _db;
  final String _coll;

  String get _collLink => 'dbs/$_db/colls/$_coll';
  String _docLink(String id) => '$_collLink/docs/$id';
  String _docsPath() => '$_collLink/docs';
  String _docPath(String id) => '${_docsPath()}/${Uri.encodeComponent(id)}';

  Map<String, String> _pkHeader(Object? partitionKey) => {
    'x-ms-documentdb-partitionkey': jsonEncode([partitionKey]),
  };

  /// Reads a single document. Returns `null` on 404.
  Future<Map<String, dynamic>?> read(
    String id, {
    required Object partitionKey,
  }) async {
    final response = await _client._send(
      verb: 'GET',
      resourceType: 'docs',
      resourceLink: _docLink(id),
      pathSegment: _docPath(id),
      extraHeaders: _pkHeader(partitionKey),
    );
    if (response.statusCode == 404) return null;
    _ensureOk(response);
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  /// Runs a SQL query. Pass `crossPartition: true` to fan out across all
  /// logical partitions (required for queries that don't filter on the
  /// partition key path).
  ///
  /// Pagination is handled internally — the returned list is the full result
  /// set. Fine for our scale (≲100 docs per container).
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
    Object? partitionKey,
    bool crossPartition = false,
  }) async {
    final body = <String, Object?>{
      'query': sql,
      'parameters': parameters.entries
          .map((e) => {'name': e.key, 'value': e.value})
          .toList(),
    };

    final out = <Map<String, dynamic>>[];
    String? continuation;
    do {
      final headers = <String, String>{
        'Content-Type': 'application/query+json',
        'x-ms-documentdb-isquery': 'true',
        if (crossPartition)
          'x-ms-documentdb-query-enablecrosspartition': 'true'
        else if (partitionKey != null)
          ..._pkHeader(partitionKey),
        if (continuation != null) 'x-ms-continuation': continuation,
      };
      final response = await _client._send(
        verb: 'POST',
        resourceType: 'docs',
        resourceLink: _collLink,
        pathSegment: _docsPath(),
        extraHeaders: headers,
        body: body,
      );
      _ensureOk(response);
      final decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final docs = (decoded['Documents'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      out.addAll(docs);
      continuation = response.headers['x-ms-continuation'];
    } while (continuation != null && continuation.isNotEmpty);
    return out;
  }

  /// Creates a new doc. Fails with 409 if the id already exists.
  Future<Map<String, dynamic>> create(
    Map<String, Object?> doc, {
    required Object partitionKey,
  }) async {
    final response = await _client._send(
      verb: 'POST',
      resourceType: 'docs',
      resourceLink: _collLink,
      pathSegment: _docsPath(),
      extraHeaders: _pkHeader(partitionKey),
      body: doc,
    );
    _ensureOk(response);
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  /// Creates or replaces a doc. The doc must contain its `id` field.
  Future<Map<String, dynamic>> upsert(
    Map<String, Object?> doc, {
    required Object partitionKey,
  }) async {
    final response = await _client._send(
      verb: 'POST',
      resourceType: 'docs',
      resourceLink: _collLink,
      pathSegment: _docsPath(),
      extraHeaders: {
        ..._pkHeader(partitionKey),
        'x-ms-documentdb-is-upsert': 'true',
      },
      body: doc,
    );
    _ensureOk(response);
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  /// Replaces an existing doc. Fails with 404 if the id is missing.
  Future<Map<String, dynamic>> replace(
    String id,
    Map<String, Object?> doc, {
    required Object partitionKey,
  }) async {
    final response = await _client._send(
      verb: 'PUT',
      resourceType: 'docs',
      resourceLink: _docLink(id),
      pathSegment: _docPath(id),
      extraHeaders: _pkHeader(partitionKey),
      body: doc,
    );
    _ensureOk(response);
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  /// Deletes a doc. 404 is treated as success (idempotent).
  Future<void> delete(String id, {required Object partitionKey}) async {
    final response = await _client._send(
      verb: 'DELETE',
      resourceType: 'docs',
      resourceLink: _docLink(id),
      pathSegment: _docPath(id),
      extraHeaders: _pkHeader(partitionKey),
    );
    if (response.statusCode == 404) return;
    _ensureOk(response);
  }

  /// Transactional batch — all ops succeed or none do. Every op MUST share
  /// the same logical partition key (Cosmos requirement).
  Future<void> executeBatch(
    List<BatchOperation> ops, {
    required Object partitionKey,
  }) async {
    if (ops.isEmpty) return;
    final response = await _client._send(
      verb: 'POST',
      resourceType: 'docs',
      resourceLink: _collLink,
      pathSegment: _docsPath(),
      extraHeaders: {
        ..._pkHeader(partitionKey),
        'x-ms-cosmos-is-batch-request': 'true',
        'x-ms-cosmos-batch-atomic': 'true',
      },
      body: ops.map((o) => o.toJson()).toList(),
    );
    _ensureOk(response);
  }

  void _ensureOk(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String message = response.body;
    String? code;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        message = (decoded['message'] as String?) ?? message;
        code = decoded['code'] as String?;
      }
    } catch (_) {
      // body wasn't JSON; keep raw text
    }
    throw CosmosException(
      response.statusCode,
      message,
      code: code,
      activityId: response.headers['x-ms-activity-id'],
    );
  }
}

/// One entry in a transactional batch. Mirrors the JSON shape Cosmos expects.
class BatchOperation {
  BatchOperation._(this.operationType, {this.id, this.resourceBody});

  factory BatchOperation.create(Map<String, Object?> doc) =>
      BatchOperation._('Create', resourceBody: doc);

  factory BatchOperation.upsert(Map<String, Object?> doc) =>
      BatchOperation._('Upsert', resourceBody: doc);

  factory BatchOperation.replace(String id, Map<String, Object?> doc) =>
      BatchOperation._('Replace', id: id, resourceBody: doc);

  factory BatchOperation.delete(String id) =>
      BatchOperation._('Delete', id: id);

  final String operationType;
  final String? id;
  final Map<String, Object?>? resourceBody;

  Map<String, Object?> toJson() => {
    'operationType': operationType,
    if (id != null) 'id': id,
    if (resourceBody != null) 'resourceBody': resourceBody,
  };
}
