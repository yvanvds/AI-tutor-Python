// The content the stand-alone mode ships with (#266, part of #261).
//
// The bundle is what `tooling/curriculum/export_bundle.py` (#265) writes to
// `assets/curriculum/`: `manifest.json` plus one JSON file per container. The
// format is documented in that script's docstring.
//
// At start, in stand-alone mode only, [installCurriculumBundle] compares the
// manifest's `contentVersion` with the version loaded last (kept next to the
// local data, so per mode) and, when they differ, rewrites the content in the
// local storage (#263):
//
//   - `goals`, `content`, `modules`, `instructions`, `translations`: what the
//     bundle holds is written; what is stored but no longer in the bundle is
//     removed;
//   - `config`: only the doc `global`;
//   - `questions`: the bundle's questions are stored with `fromBundle: true`,
//     and only those are replaced or removed; the questions the tutor made on
//     this pc stay;
//   - everything else (`accounts`, `lo_beliefs`, `progress`, `turn_history`,
//     `playground_files`, …) is never touched, whatever the bundle holds.
//
// The same bundle again writes nothing. No bundle (a folder without a
// manifest) installs nothing and leaves whatever was loaded before. The
// school mode never calls this: its content is the school's database.

import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/local_cosmos_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// The bundle format this build reads.
const int kCurriculumBundleFormat = 1;

/// Containers the bundle rewrites in full: stored docs not in the bundle go.
const Set<String> kBundleOwnedContainers = {
  'goals',
  'content',
  'modules',
  'instructions',
  'translations',
};

/// The `config` docs the bundle owns.
const Set<String> kBundleConfigIds = {'global'};

/// Marks a question that came from the bundle.
const String kFromBundleField = 'fromBundle';

/// Where the bundle sits among the app's assets.
const String kCurriculumAssetDir = 'assets/curriculum';

/// Reads a bundle file by name; `null` when it is not there.
abstract class CurriculumBundleSource {
  Future<String?> read(String fileName);
}

/// The bundle in the app's assets ([kCurriculumAssetDir]).
class AssetCurriculumBundleSource implements CurriculumBundleSource {
  AssetCurriculumBundleSource({AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;

  @override
  Future<String?> read(String fileName) async {
    try {
      return await _bundle.loadString(
        '$kCurriculumAssetDir/$fileName',
        cache: false,
      );
    } on Object {
      // Not in the build: no bundle shipped yet.
      return null;
    }
  }
}

/// A bundle in a folder on disk (tests, the fixture bundle).
class DirectoryCurriculumBundleSource implements CurriculumBundleSource {
  DirectoryCurriculumBundleSource(this.dir);

  final Directory dir;

  @override
  Future<String?> read(String fileName) async {
    final file = File(p.join(dir.path, fileName));
    if (!file.existsSync()) return null;
    return file.readAsString();
  }
}

/// A bundle, read and checked.
@immutable
class CurriculumBundle {
  const CurriculumBundle({required this.contentVersion, required this.docs});

  final String contentVersion;

  /// Docs per container, only for containers the bundle may write.
  final Map<String, List<Map<String, dynamic>>> docs;

  /// Reads the bundle from [source]. `null` when there is none: no manifest,
  /// or a manifest without content (the placeholder). Throws a
  /// [FormatException] on a bundle that is there but broken.
  static Future<CurriculumBundle?> read(CurriculumBundleSource source) async {
    final raw = await source.read('manifest.json');
    if (raw == null || raw.trim().isEmpty) return null;
    final manifest = jsonDecode(raw);
    if (manifest is! Map<String, dynamic>) {
      throw const FormatException('manifest.json is not an object');
    }
    final version = manifest['contentVersion'];
    final containers = manifest['containers'];
    if (version is! String || version.isEmpty || containers is! Map) {
      return null;
    }
    if (manifest['format'] != kCurriculumBundleFormat) {
      throw FormatException(
        'bundle format ${manifest['format']}, this build reads '
        '$kCurriculumBundleFormat',
      );
    }
    final docs = <String, List<Map<String, dynamic>>>{};
    for (final entry in containers.entries) {
      final name = entry.key as String;
      if (!_writable(name)) {
        // Student data never comes from a bundle, whatever it says.
        debugPrint('Curriculum bundle: ignored container $name');
        continue;
      }
      final fileName = (entry.value as Map)['file'] as String;
      final body = await source.read(fileName);
      if (body == null) {
        throw FormatException('$fileName is listed but missing');
      }
      final file = jsonDecode(body) as Map<String, dynamic>;
      final field = file['partitionKeyField'];
      if (field != kCosmosPartitionKeyFields[name]) {
        throw FormatException(
          '$fileName: partition key $field, the app uses '
          '${kCosmosPartitionKeyFields[name]}',
        );
      }
      docs[name] = [
        for (final d in file['docs'] as List)
          Map<String, dynamic>.from(d as Map),
      ];
    }
    return CurriculumBundle(contentVersion: version, docs: docs);
  }

  static bool _writable(String container) =>
      kBundleOwnedContainers.contains(container) ||
      container == 'config' ||
      container == 'questions';
}

/// What [installCurriculumBundle] did.
enum CurriculumInstall {
  /// No bundle shipped: nothing written.
  noBundle,

  /// The bundle was loaded before: nothing written.
  upToDate,

  /// The bundle was written to the local storage.
  installed,
}

/// The file that keeps which bundle the local storage holds, inside the
/// stand-alone data folder: deleting that folder loads the bundle afresh.
File curriculumVersionFile(Directory localDataRoot) =>
    File(p.join(localDataRoot.path, 'curriculum_bundle.json'));

/// Writes [source]'s bundle to [client] when it is not the one loaded last
/// (see the top of this file). Stand-alone mode only.
Future<CurriculumInstall> installCurriculumBundle({
  required CurriculumBundleSource source,
  required CosmosClient client,
  required File versionFile,
}) async {
  final bundle = await CurriculumBundle.read(source);
  if (bundle == null) return CurriculumInstall.noBundle;
  if (_loadedVersion(versionFile) == bundle.contentVersion) {
    return CurriculumInstall.upToDate;
  }

  for (final entry in bundle.docs.entries) {
    final name = entry.key;
    final field = kCosmosPartitionKeyFields[name]!;
    final container = client.container(name);
    final incoming = entry.value;
    if (name == 'questions') {
      for (final d in incoming) {
        d[kFromBundleField] = true;
      }
    }
    final keep = {for (final d in incoming) _keyOf(d, field)};

    final stored = await container.query(
      'SELECT * FROM c',
      crossPartition: true,
    );
    for (final d in stored) {
      if (keep.contains(_keyOf(d, field))) continue;
      final owned = switch (name) {
        'config' => kBundleConfigIds.contains(d['id']),
        'questions' => d[kFromBundleField] == true,
        _ => true,
      };
      if (!owned) continue;
      await container.delete(d['id'] as String, partitionKey: d[field]);
    }
    for (final d in incoming) {
      if (name == 'config' && !kBundleConfigIds.contains(d['id'])) continue;
      await container.upsert(d, partitionKey: d[field] as Object);
    }
  }

  // Last, so a start that stopped half way loads the bundle again.
  versionFile.parent.createSync(recursive: true);
  versionFile.writeAsStringSync(
    jsonEncode({'contentVersion': bundle.contentVersion}),
  );
  return CurriculumInstall.installed;
}

/// [installCurriculumBundle] at start (`main()`): stand-alone storage over
/// [localDataRoot]. A bundle that cannot be read or written is logged and
/// the app starts on what the local storage holds; it never stops the start.
Future<CurriculumInstall?> installCurriculumBundleAtStart({
  required CosmosClient client,
  required Directory localDataRoot,
  CurriculumBundleSource? source,
}) async {
  try {
    return await installCurriculumBundle(
      source: source ?? AssetCurriculumBundleSource(),
      client: client,
      versionFile: curriculumVersionFile(localDataRoot),
    );
  } on Object catch (e, st) {
    debugPrint('Curriculum bundle not loaded: $e\n$st');
    return null;
  }
}

String _keyOf(Map<String, dynamic> d, String field) =>
    '${jsonEncode(d[field])}\u0000${d['id']}';

String? _loadedVersion(File versionFile) {
  try {
    if (!versionFile.existsSync()) return null;
    final v = jsonDecode(versionFile.readAsStringSync());
    return v is Map ? v['contentVersion'] as String? : null;
  } on Object {
    return null;
  }
}
