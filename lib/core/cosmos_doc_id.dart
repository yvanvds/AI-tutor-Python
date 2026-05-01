// Doc-id conventions for Cosmos. Two containers (`progress`, `status_reports`)
// flatten what used to be Firestore subcollections into composite ids — keep
// the format in one place so reads, writes, and the Step 5 migration script
// can't drift.

class CosmosDocId {
  /// `accounts/{uid}/progress/{goalId}` → `progress` doc with this id.
  static String progress(String uid, String goalId) => '${uid}_$goalId';

  /// `accounts/{uid}/status_reports/{goalId}` → `status_reports` doc with
  /// this id.
  static String statusReport(String uid, String goalId) => '${uid}_$goalId';

  /// Single global config doc.
  static const String globalConfig = 'global';
}
