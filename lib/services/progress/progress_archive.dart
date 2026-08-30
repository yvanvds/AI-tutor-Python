// Export / import of a student's progress (#32).
//
// Why it exists even though progress lives in Cosmos: the docs are keyed by
// uid, so they follow the *account*, not the machine. A student who arrives
// with a personal Microsoft account and later gets a school one — or who
// signs up twice by accident — has no way to take their learning history
// with them. This is that way: one JSON file, written by the Options panel
// and read back into whichever account is signed in when it is imported.
//
// What travels: the progress cache, its history samples, the per-LO beliefs
// and the difficulty calibration — everything the conductor reads to decide
// what to ask next. What does not: `turn_history`, which is a debugging /
// analytics log of raw tutor turns rather than student state, and would make
// the file an order of magnitude larger for no behavioural difference.
//
// The file carries no uid, no email and no key: identity is stamped on write
// by the services, from whoever is signed in at import time.

import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:ai_tutor_python/services/progress/progress_sample.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:ai_tutor_python/services/student_state/lo_belief.dart';
import 'package:ai_tutor_python/services/student_state/lo_beliefs_service.dart';
import 'package:ai_tutor_python/services/student_state/student_calibration.dart';
import 'package:ai_tutor_python/version.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Raised when an imported file is not a progress archive this build can
/// read. The message is shown to the user, so it says what is wrong.
class ProgressArchiveException implements Exception {
  ProgressArchiveException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// What an import wrote, for the confirmation message.
typedef ProgressImportSummary = ({int goals, int samples, int beliefs});

class ProgressArchive {
  ProgressArchive({
    required ProgressService progress,
    required LoBeliefsService loBeliefs,
    required StudentCalibration? Function() calibration,
    required Future<void> Function(StudentCalibration) setCalibration,
  }) : _progress = progress,
       _loBeliefs = loBeliefs,
       _calibration = calibration,
       _setCalibration = setCalibration;

  final ProgressService _progress;
  final LoBeliefsService _loBeliefs;
  final StudentCalibration? Function() _calibration;
  final Future<void> Function(StudentCalibration) _setCalibration;

  /// Marker so an unrelated `.json` is rejected with a useful message rather
  /// than half-imported.
  static const String kind = 'ai-tutor-python/progress';

  /// Bumped only when the shape stops being readable by an older build.
  static const int formatVersion = 1;

  /// Everything the signed-in user's learning state consists of, as a plain
  /// JSON-encodable map.
  Future<Map<String, dynamic>> export() async {
    final progress = await _progress.getAll();
    final history = await _progress.getAllHistory();
    final beliefs = await _loBeliefs.getAllForCurrentUser();
    final calibration = _calibration();

    return {
      'kind': kind,
      'version': formatVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'appVersion': kAppVersion,
      if (calibration != null) 'calibration': calibration.toJson(),
      'progress': progress.map(_stripped).toList(growable: false),
      'history': history.map(_strippedSample).toList(growable: false),
      'beliefs': beliefs.map(_strippedBelief).toList(growable: false),
    };
  }

  /// Replaces the signed-in user's progress with [data].
  ///
  /// Destructive on purpose: merging two histories would produce a student
  /// model that matches neither machine, so the panel asks for confirmation
  /// and this then wipes before it writes.
  Future<ProgressImportSummary> import(Map<String, dynamic> data) async {
    if (data['kind'] != kind) {
      throw ProgressArchiveException(
        'Not an AI Tutor progress file (kind: ${data['kind'] ?? 'missing'}).',
      );
    }
    final version = data['version'];
    if (version is! int || version > formatVersion) {
      throw ProgressArchiveException(
        'Unsupported progress file version: ${version ?? 'missing'}.',
      );
    }

    final progress = _listOfMaps(
      data['progress'],
      'progress',
    ).map(Progress.fromCosmos).toList(growable: false);
    final history = _listOfMaps(
      data['history'],
      'history',
    ).map(ProgressSample.fromCosmos).toList(growable: false);
    final beliefs = _listOfMaps(
      data['beliefs'],
      'beliefs',
    ).map(LoBelief.fromCosmos).toList(growable: false);
    final rawCalibration = data['calibration'];
    final calibration = rawCalibration is Map
        ? StudentCalibration.fromJson(rawCalibration.cast<String, dynamic>())
        : null;

    // Parse fully before touching Cosmos: a malformed file should leave the
    // account it was aimed at exactly as it was.
    await _progress.deleteAllForCurrentUser();
    await _loBeliefs.deleteAllForCurrentUser();

    for (final p in progress) {
      await _progress.upsert(p, recordHistory: false);
    }
    await _progress.importHistory(history);
    for (final b in beliefs) {
      await _loBeliefs.upsert(b);
    }
    if (calibration != null) await _setCalibration(calibration);

    return (
      goals: progress.length,
      samples: history.length,
      beliefs: beliefs.length,
    );
  }

  /// The Cosmos serializers are reused so the archive can never drift from
  /// the on-disk schema; `id` and `uid` are dropped because the file has to
  /// be importable into a *different* account than it came from.
  static Map<String, dynamic> _stripped(Progress p) => {
    'goalId': p.goalID,
    'progress': p.progress,
    if (p.updatedAt != null)
      'updatedAt': p.updatedAt!.toUtc().toIso8601String(),
    if (p.lastSessionAt != null)
      'lastSessionAt': p.lastSessionAt!.toUtc().toIso8601String(),
  };

  static Map<String, dynamic> _strippedSample(ProgressSample s) =>
      s.toMap(uid: '')..removeWhere((k, _) => k == 'id' || k == 'uid');

  static Map<String, dynamic> _strippedBelief(LoBelief b) =>
      b.toMap(uid: '')..removeWhere((k, _) => k == 'id' || k == 'uid');

  static List<Map<String, dynamic>> _listOfMaps(Object? raw, String field) {
    if (raw == null) return const [];
    if (raw is! List) {
      throw ProgressArchiveException(
        'Progress file field "$field" is damaged.',
      );
    }
    return raw
        .map((e) {
          if (e is! Map) {
            throw ProgressArchiveException(
              'Progress file field "$field" is damaged.',
            );
          }
          return e.cast<String, dynamic>();
        })
        .toList(growable: false);
  }
}

final progressArchiveProvider = Provider<ProgressArchive>((ref) {
  return ProgressArchive(
    progress: ref.watch(progressServiceProvider),
    loBeliefs: ref.watch(loBeliefsServiceProvider),
    calibration: () => ref.read(accountServiceProvider)?.calibration,
    setCalibration: (c) =>
        ref.read(accountServiceProvider.notifier).setCalibration(c),
  );
});
