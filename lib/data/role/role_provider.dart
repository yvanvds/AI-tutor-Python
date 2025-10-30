import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final isTeacherProviderFuture = FutureProvider.family<bool, String>((
  ref,
  uid,
) async {
  final doc = await FirebaseFirestore.instance
      .collection('roles')
      .doc(uid)
      .get();

  if (!doc.exists) return false;
  final role = doc.data()?['role'];
  return role == 'teacher';
});
