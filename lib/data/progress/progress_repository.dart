import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'progress.dart'; // your Progress class (shown in your message)

class ProgressRepository {
  ProgressRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
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
      _db.collection('accounts').doc(uid).collection('progress');

  /// Load all progress docs once (returns empty list if none exist).
  Future<List<Progress>> getAll() async {
    final qs = await _col(_uid).get();
    return qs.docs.map((d) => Progress.fromDoc(d)).toList();
  }

  /// Realtime stream of all progress docs. Emits [] when none exist.
  Stream<List<Progress>> watchAll() {
    return _col(
      _uid,
    ).snapshots().map((qs) => qs.docs.map((d) => Progress.fromDoc(d)).toList());
  }

  /// Get one goal’s progress (null if it doesn’t exist).
  Future<Progress?> getByGoalId(String goalID) async {
    final doc = await _col(_uid).doc(goalID).get();
    if (!doc.exists) return null;
    return Progress.fromDoc(doc);
  }

  /// Create or update a progress doc.
  ///
  /// Uses goalID as the document id, so writes are idempotent.
  Future<void> upsert(Progress p) async {
    await _col(_uid).doc(p.goalID).set(p.toMap(), SetOptions(merge: true));
  }

  /// Delete a progress doc (optional helper).
  Future<void> delete(String goalID) async {
    await _col(_uid).doc(goalID).delete();
  }
}
