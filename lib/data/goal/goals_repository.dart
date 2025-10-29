import 'package:ai_tutor_python/data/goal/goal.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GoalsRepository {
  // Make the collection strongly typed to avoid casts later:
  final CollectionReference<Map<String, dynamic>> _collection =
      FirebaseFirestore.instance.collection('goals');

  Stream<List<Goal>> streamRoots() => _collection
      .where('parentId', isNull: true)
      .orderBy('order')
      .snapshots()
      .map((s) => s.docs.map((d) => Goal.fromDoc(d)).toList());

  Stream<List<Goal>> streamChildren(String parentId) => _collection
      .where('parentId', isEqualTo: parentId)
      .orderBy('order')
      .snapshots()
      .map((s) => s.docs.map((d) => Goal.fromDoc(d)).toList());
}
