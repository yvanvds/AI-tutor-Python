import 'package:cloud_firestore/cloud_firestore.dart';

/// Single source of truth for Firestore collection and document paths.
class FsPaths {
  static FirebaseFirestore get root => FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> goals() =>
      root.collection('goals');

  static CollectionReference<Map<String, dynamic>> instructions() =>
      root.collection('instructions');

  static CollectionReference<Map<String, dynamic>> roles() =>
      root.collection('roles');

  static CollectionReference<Map<String, dynamic>> accounts() =>
      root.collection('accounts');

  static CollectionReference<Map<String, dynamic>> config() =>
      root.collection('config');

  static DocumentReference<Map<String, dynamic>> account(String uid) =>
      accounts().doc(uid);

  static DocumentReference<Map<String, dynamic>> role(String uid) =>
      roles().doc(uid);

  static CollectionReference<Map<String, dynamic>> progress(String uid) =>
      account(uid).collection('progress');

  static CollectionReference<Map<String, dynamic>> statusReports(String uid) =>
      account(uid).collection('status_reports');
}
