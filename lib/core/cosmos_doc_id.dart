// Composite doc-id conventions for Cosmos containers that combine multiple
// keys into a single id. Keep in one place so reads and writes can't drift.

class CosmosDocId {
  /// Doc id for the `progress` container.
  static String progress(String uid, String goalId) => '${uid}_$goalId';

  /// Doc id for the `status_reports` container.
  static String statusReport(String uid, String goalId) => '${uid}_$goalId';

  /// Single global config doc.
  static const String globalConfig = 'global';
}
