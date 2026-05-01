/// One row of the `status_reports` Cosmos container. Flattened from the old
/// `accounts/{uid}/status_reports/{goalId}` Firestore subcollection — each
/// doc now carries its own `uid` and `goalId`, with composite id
/// `${uid}_${goalId}` and the user's uid as the partition key.
class StatusReport {
  final String goalID;
  final String statusReport;
  final DateTime? updatedAt;

  StatusReport({
    required this.goalID,
    required this.statusReport,
    this.updatedAt,
  });

  Map<String, dynamic> toMap({required String uid}) => {
    'id': '${uid}_$goalID',
    'uid': uid,
    'goalId': goalID,
    'statusReport': statusReport,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  };

  factory StatusReport.fromCosmos(Map<String, dynamic> doc) {
    final raw = doc['updatedAt'];
    return StatusReport(
      goalID: (doc['goalId'] as String?) ?? '',
      statusReport: (doc['statusReport'] as String?) ?? '',
      updatedAt: raw is String ? DateTime.tryParse(raw) : null,
    );
  }
}
