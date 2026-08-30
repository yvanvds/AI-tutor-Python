// Composite doc-id conventions for Cosmos containers that combine multiple
// keys into a single id. Keep in one place so reads and writes can't drift.

import 'dart:math';

class CosmosDocId {
  /// Doc id for the `progress` container.
  static String progress(String uid, String goalId) => '${uid}_$goalId';

  /// Doc id for the `status_reports` container.
  static String statusReport(String uid, String goalId) => '${uid}_$goalId';

  /// Doc id for the `progress_history` container. ISO timestamp prefix
  /// keeps ids monotonically sortable; the random suffix avoids collisions
  /// for samples written within the same millisecond.
  static String progressHistory(DateTime at, {Random? random}) {
    final r = random ?? _random;
    final suffix = r.nextInt(1 << 32).toRadixString(36).padLeft(7, '0');
    return '${at.toUtc().toIso8601String()}_$suffix';
  }

  /// Doc id for the `turn_history` container. Same shape as
  /// `progressHistory` — sortable timestamp prefix + random suffix.
  static String turnHistory(DateTime at, {Random? random}) {
    final r = random ?? _random;
    final suffix = r.nextInt(1 << 32).toRadixString(36).padLeft(7, '0');
    return '${at.toUtc().toIso8601String()}_$suffix';
  }

  /// Doc id for the `playground_files` container. The name is already
  /// restricted by `PlaygroundFileStore.normalizeName` to letters, digits,
  /// spaces, `-` and `_`, so it can never contain a character Cosmos rejects
  /// in an id (`/`, `\`, `?`, `#`) or a leading/trailing space.
  static String playgroundFile(String uid, String name) => '${uid}_$name';

  /// Single global config doc.
  static const String globalConfig = 'global';

  static final Random _random = Random();
}
