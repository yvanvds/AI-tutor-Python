// The one place that knows which mode the app runs in (#262, part of #261).
//
// There is one build and one installer. The mode follows from whether there
// is a school configuration:
//
//   - a school configuration → [SchoolMode]: sign in with the school's Entra
//     tenant and work in the school's database, as students always have;
//   - none → [StandaloneMode]: no account, no server.
//
// The school configuration comes from a school file the user imported
// (#307, lib/core/school_file.dart) or, until it leaves the build (#308),
// from the build (`.env`, through `AzureConfig`). A build whose `.env`
// carries no school data — empty values, the all-zero GUID or a `dummy`
// placeholder, as CI generates — has none. Which one applies, and when the
// app asks at first start, is decided in lib/core/app_start.dart; `main()`
// then overrides [appModeProvider] with the result.
//
// `AzureConfig` is read here and nowhere else
// (test/core/app_mode_single_reader_test.dart). The rest of the app asks
// [appModeProvider].

import 'dart:io';

import 'package:ai_tutor_python/services/config/azure_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// The database every school configuration from the build uses.
const String kDefaultSchoolDatabaseName = 'python-tutor';

/// What the app needs to know about a school: where to sign in and where its
/// database lives. Holds no secrets, so a school file (#307) can carry it.
@immutable
class SchoolConfig {
  const SchoolConfig({
    required this.tenantId,
    required this.clientId,
    required this.redirectUri,
    required this.databaseEndpoint,
    this.databaseName = kDefaultSchoolDatabaseName,
    this.schoolName,
  });

  /// Entra tenant (directory) id of the school.
  final String tenantId;

  /// Client id of the school's app registration.
  final String clientId;

  /// Redirect URI registered on that app registration.
  final String redirectUri;

  /// Cosmos DB account endpoint, e.g. `https://<account>.documents.azure.com:443/`.
  final Uri databaseEndpoint;

  /// Cosmos DB database id inside that account.
  final String databaseName;

  /// Shown to the user where it helps; the build's own school has none.
  final String? schoolName;

  /// The build's own school configuration, or `null` when the build has none.
  static SchoolConfig? get fromBuild => fromBuildValues(
    tenantId: AzureConfig.tenantId,
    clientId: AzureConfig.clientId,
    redirectUri: AzureConfig.redirectUri,
    databaseEndpoint: AzureConfig.cosmosEndpoint,
  );

  /// This configuration with [name] as the school's name.
  SchoolConfig named(String name) => SchoolConfig(
    tenantId: tenantId,
    clientId: clientId,
    redirectUri: redirectUri,
    databaseEndpoint: databaseEndpoint,
    databaseName: databaseName,
    schoolName: name,
  );

  /// The build's school configuration, or `null` when the build's values are
  /// not a school's (see [isMissingValue]).
  static SchoolConfig? fromBuildValues({
    required String tenantId,
    required String clientId,
    required String redirectUri,
    required String databaseEndpoint,
  }) {
    if (isMissingValue(tenantId) ||
        isMissingValue(clientId) ||
        isMissingValue(databaseEndpoint)) {
      return null;
    }
    final endpoint = Uri.tryParse(databaseEndpoint.trim());
    if (endpoint == null || !endpoint.hasScheme || endpoint.host.isEmpty) {
      return null;
    }
    return SchoolConfig(
      tenantId: tenantId.trim(),
      clientId: clientId.trim(),
      redirectUri: redirectUri.trim(),
      databaseEndpoint: endpoint,
    );
  }

  /// Whether a build value stands for "no school": empty, the all-zero GUID,
  /// or a `dummy` placeholder (the CI build's `.env`).
  static bool isMissingValue(String value) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty) return true;
    if (v.contains('dummy')) return true;
    return RegExp(r'^\{?0{8}-0{4}-0{4}-0{4}-0{12}\}?$').hasMatch(v);
  }

  @override
  bool operator ==(Object other) =>
      other is SchoolConfig &&
      other.tenantId == tenantId &&
      other.clientId == clientId &&
      other.redirectUri == redirectUri &&
      other.databaseEndpoint == databaseEndpoint &&
      other.databaseName == databaseName &&
      other.schoolName == schoolName;

  @override
  int get hashCode => Object.hash(
    tenantId,
    clientId,
    redirectUri,
    databaseEndpoint,
    databaseName,
    schoolName,
  );
}

/// School or stand-alone. Ask [appModeProvider]; never the build.
@immutable
sealed class AppMode {
  const AppMode();

  /// The mode of this build alone, decided once: what tests and the
  /// default [appModeProvider] see. The app itself starts in the mode
  /// `decideStartMode` (lib/core/app_start.dart) picks.
  static AppMode get fromBuild =>
      _fromBuild ??= fromSchoolConfig(SchoolConfig.fromBuild);
  static AppMode? _fromBuild;

  /// [SchoolMode] with a school configuration, [StandaloneMode] without.
  static AppMode fromSchoolConfig(SchoolConfig? school) =>
      school == null ? const StandaloneMode() : SchoolMode(school);

  /// The school configuration, or `null` in stand-alone mode.
  SchoolConfig? get school;

  /// The key under which this mode keeps [key] in shared preferences, so the
  /// two modes never share local data (sign-in, local storage of #263).
  /// School mode keeps every key as it was, so existing installs keep their
  /// sign-in. Language and theme are shared on purpose: they do not go
  /// through here.
  String scopedPrefsKey(String key);

  /// The folder under [base] where this mode keeps its local files. School
  /// mode keeps [base] itself, where its files have always been.
  Directory localDataDir(Directory base);
}

/// Signed in with a school; data in the school's database.
final class SchoolMode extends AppMode {
  const SchoolMode(this.config);

  final SchoolConfig config;

  @override
  SchoolConfig get school => config;

  @override
  String scopedPrefsKey(String key) => key;

  @override
  Directory localDataDir(Directory base) => base;

  @override
  bool operator ==(Object other) =>
      other is SchoolMode && other.config == config;

  @override
  int get hashCode => config.hashCode;
}

/// No school: a local profile and local data (#263, #264).
final class StandaloneMode extends AppMode {
  const StandaloneMode();

  static const String _scope = 'standalone';

  @override
  SchoolConfig? get school => null;

  @override
  String scopedPrefsKey(String key) => '$_scope.$key';

  @override
  Directory localDataDir(Directory base) =>
      Directory(p.join(base.path, _scope));

  @override
  bool operator ==(Object other) => other is StandaloneMode;

  @override
  int get hashCode => (StandaloneMode).hashCode;
}

/// The master key for the build's school database.
///
/// Only `CosmosClient.instance` asks for it, and only in school mode. It is
/// not part of [SchoolConfig]: a school file carries no secrets, and #306
/// replaces it with the user's own sign-in.
String buildSchoolDatabaseKey() => AzureConfig.cosmosKey;

/// The mode the app runs in. `main()` overrides it with the mode decided at
/// start (#307); tests override it too. Unoverridden it reads the build.
final appModeProvider = Provider<AppMode>((ref) => AppMode.fromBuild);
