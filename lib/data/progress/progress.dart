import 'package:cloud_firestore/cloud_firestore.dart';

class Progress {
  final String goalID;
  final double progress;
  final DateTime? updatedAt;

  Progress({required this.goalID, required this.progress, this.updatedAt});

  factory Progress.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    final ts = data['updatedAt'];
    return Progress(
      goalID: doc.id,
      progress: (data['progress'] as double?) ?? 0.0,
      updatedAt: ts is Timestamp ? ts.toDate() : null,
    );
  }

  Map<String, dynamic> toMap() => {
    // goalID is the doc id
    'progress': progress,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
