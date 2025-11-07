import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'status_report.dart'; // your StatusReport class (shown in your message)

class ReportService {
  ReportService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('No authenticated user.');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('accounts').doc(uid).collection('status_reports');

  /// Load all status report docs once (returns empty list if none exist).
  Future<List<StatusReport>> getAll() async {
    final qs = await _col(_uid).get();
    return qs.docs.map((d) => StatusReport.fromDoc(d)).toList();
  }

  /// Realtime stream of all status report docs. Emits [] when none exist.
  Stream<List<StatusReport>> watchAll() {
    return _col(_uid).snapshots().map(
      (qs) => qs.docs.map((d) => StatusReport.fromDoc(d)).toList(),
    );
  }

  /// Get one goal’s status report (null if it doesn’t exist).
  Future<StatusReport?> getByGoalId(String goalID) async {
    final doc = await _col(_uid).doc(goalID).get();
    if (!doc.exists) return null;
    return StatusReport.fromDoc(doc);
  }

  /// Create or update a status report doc.
  ///
  /// Uses goalID as the document id, so writes are idempotent.
  Future<void> upsert(StatusReport p) async {
    await _col(_uid).doc(p.goalID).set(p.toMap(), SetOptions(merge: true));
  }

  /// Delete a status report doc (optional helper).
  Future<void> delete(String goalID) async {
    await _col(_uid).doc(goalID).delete();
  }
}
