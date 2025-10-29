import 'package:cloud_firestore/cloud_firestore.dart';

class ProgressRepository {
  final CollectionReference<Map<String, dynamic>> _collection =
      FirebaseFirestore.instance.collection('progress');
}
