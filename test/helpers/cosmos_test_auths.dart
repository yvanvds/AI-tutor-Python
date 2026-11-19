// The two ways a school reaches its database (#306), for the CosmosClient
// tests that must hold for both: the build's key (`MasterKeyAuth`) and the
// user's own sign-in (`AadTokenAuth`, here over a token that is always
// valid). Each test file runs its tests once per entry of [cosmosTestAuths].

import 'dart:convert';

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:flutter_test/flutter_test.dart';

class CosmosTestAuth {
  const CosmosTestAuth(this.name, this.make, {required this.renewsAfter401});

  final String name;
  final CosmosAuth Function() make;

  /// Whether a 401 makes this auth renew and the client try once more.
  final bool renewsAfter401;
}

final List<CosmosTestAuth> cosmosTestAuths = [
  CosmosTestAuth(
    'database key',
    () => MasterKeyAuth(base64Encode(List<int>.filled(32, 7))),
    renewsAfter401: false,
  ),
  CosmosTestAuth(
    'sign-in token',
    () => AadTokenAuth(({bool forceRefresh = false}) async => 'test-token'),
    renewsAfter401: true,
  ),
];

/// Registers [body] once per auth in a group named after it; [body] reads
/// the auth of the running test from the argument it gets.
void forEachCosmosAuth(void Function(CosmosTestAuth Function() auth) body) {
  for (final access in cosmosTestAuths) {
    group('with the ${access.name}', () {
      body(() => access);
    });
  }
}
