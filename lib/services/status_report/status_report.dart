import 'package:cloud_firestore/cloud_firestore.dart';

class StatusReport {
  final String goalID;
  final String statusReport;
  final DateTime? updatedAt;

  StatusReport({
    required this.goalID,
    required this.statusReport,
    this.updatedAt,
  });

  factory StatusReport.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    final ts = data['updatedAt'];
    return StatusReport(
      goalID: doc.id,
      statusReport: (data['statusReport'] as String?) ?? '',
      updatedAt: ts is Timestamp ? ts.toDate() : null,
    );
  }

  Map<String, dynamic> toMap() => {
    // goalID is the doc id
    'statusReport': statusReport,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
