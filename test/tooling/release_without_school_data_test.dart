// #308, step 3: a release has no school data. The school's settings come
// from the school file (#307) and from `config/global` (#337), and the
// database is reached with the user's own sign-in (#306, #336).
//
// `tooling/build_release.ps1` builds a release from a release `.env`: the
// school's values replaced by the placeholders CI uses, the values that are
// not a school's kept. Envied may obfuscate a value, so searching the build
// output proves nothing. The proof is on the Dart side, against the very
// files the build compiles:
//
//   - The first group is that check. The script runs it with
//     `--dart-define=RELEASE_WITHOUT_SCHOOL_DATA=true` after it generated the
//     release's envied files, and stops the release when a test fails, is
//     skipped or does not run at all. Every other run (a developer's `.env`,
//     CI's) skips it.
//   - The second group runs everywhere and holds the script to its half: each
//     `.env` key the app reads is either a school's (replaced) or not (kept),
//     and the placeholders mean "no school" to the app.
//
// Every assertion is on a bool, so no value from `.env` ever reaches the
// output.

import 'dart:io';

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/services/github/github_device_flow.dart';
import 'package:ai_tutor_python/services/tutor/openai_wiring.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Set by `tooling/build_release.ps1` on the release `.env`.
const bool _releaseCheck = bool.fromEnvironment('RELEASE_WITHOUT_SCHOOL_DATA');

/// Set by the script when the developer's `.env` has a GitHub OAuth client
/// id, which the release keeps.
const bool _keepsGitHubOAuth = bool.fromEnvironment(
  'RELEASE_KEEPS_GITHUB_OAUTH',
);

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('${file.path} is missing (cwd: ${Directory.current})');
  }
  // CRLF on a Windows checkout (core.autocrlf); the matches below are per line.
  return file.readAsStringSync().replaceAll('\r\n', '\n');
}

/// What lies between [open] and the next [close] after `$<name> = ` in
/// [script].
String _block(String script, String name, String open, String close) {
  final start = script.indexOf('\$$name = ');
  if (start == -1) throw StateError('\$$name is gone from build_release.ps1');
  final from = script.indexOf(open, start) + open.length;
  return script.substring(from, script.indexOf(close, from));
}

/// The release script's placeholders for the school's `.env` keys
/// (`$SchoolEnvValues`) and the keys it keeps (`$KeptEnvKeys`).
({Map<String, String> placeholders, Set<String> kept}) _releaseEnvKeys() {
  final script = _read(p.join('tooling', 'build_release.ps1'));
  final entry = RegExp(r"^\s*'([A-Z0-9_]+)'\s*=\s*'([^']*)'", multiLine: true);
  return (
    placeholders: {
      for (final m in entry.allMatches(
        _block(script, 'SchoolEnvValues', '@{', '}'),
      ))
        m.group(1)!: m.group(2)!,
    },
    kept: RegExp(r"'([A-Z0-9_]+)'")
        .allMatches(_block(script, 'KeptEnvKeys', '@(', ')'))
        .map((m) => m.group(1)!)
        .toSet(),
  );
}

/// The `.env` keys every envied class in lib/ reads.
Set<String> _enviedKeys() {
  final keys = <String>{};
  final varName = RegExp(r"varName:\s*'([A-Z0-9_]+)'");
  for (final file in Directory('lib').listSync(recursive: true)) {
    if (file is! File || !file.path.endsWith('.dart')) continue;
    if (file.path.endsWith('.g.dart')) continue;
    final source = file.readAsStringSync();
    if (!source.contains('@Envied(')) continue;
    keys.addAll(varName.allMatches(source).map((m) => m.group(1)!));
  }
  return keys;
}

void main() {
  group(
    'a release without school data',
    skip: _releaseCheck
        ? null
        : 'only tooling/build_release.ps1 runs this, on the release .env',
    () {
      test('the build has no school configuration', () {
        expect(SchoolConfig.fromBuild == null, isTrue);
        expect(AppMode.fromBuild is StandaloneMode, isTrue);
      });

      test('the build has no school data and no database key', () {
        expect(buildHasSchoolData(), isFalse);
        expect(SchoolConfig.isMissingValue(buildSchoolDatabaseKey()), isTrue);
      });

      test('the school AI key has no fallback from the build', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        expect(container.read(fallbackSchoolApiKeyProvider) == null, isTrue);
      });

      test('what is no school data stays: the GitHub OAuth app', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final clientId = container.read(gitHubOAuthClientIdProvider);
        expect(clientId.trim().isNotEmpty, _keepsGitHubOAuth);
      });
    },
  );

  group('build_release.ps1 builds without school data', () {
    test("every .env key the app reads is a school's or kept", () {
      final (:placeholders, :kept) = _releaseEnvKeys();
      expect(placeholders, isNotEmpty);
      expect(kept, isNotEmpty);
      expect(placeholders.keys.toSet().intersection(kept), isEmpty);
      expect(
        _enviedKeys().difference({...placeholders.keys, ...kept}),
        isEmpty,
        reason:
            'build_release.ps1 must say whether a new .env key is school '
            'data (SchoolEnvValues) or not (KeptEnvKeys)',
      );
    });

    test('the placeholders are no school, no database key and no AI key', () {
      final placeholders = _releaseEnvKeys().placeholders;
      String value(String key) {
        expect(placeholders, contains(key));
        return placeholders[key]!;
      }

      expect(
        SchoolConfig.fromBuildValues(
          tenantId: value('ENTRA_TENANT_ID'),
          clientId: value('ENTRA_CLIENT_ID'),
          redirectUri: value('ENTRA_REDIRECT_URI'),
          databaseEndpoint: value('COSMOS_ENDPOINT'),
        ),
        isNull,
      );
      expect(SchoolConfig.isMissingValue(value('COSMOS_KEY')), isTrue);
      expect(fallbackSchoolApiKeyFrom(value('OPEN_AI_API_KEY')), isNull);
    });
  });
}
