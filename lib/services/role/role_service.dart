import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

class RoleService {
  RoleService() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      // No user: definitely not a teacher
      if (user == null) {
        isTeacher.value = false;
        await _roleSub?.cancel();
        _roleSub = null;
        return;
      }

      // Optional: live updates on role doc
      await _roleSub?.cancel();
      _roleSub = FirebaseFirestore.instance
          .collection('roles')
          .doc(user.uid)
          .snapshots()
          .listen((snapshot) {
            final role = snapshot.data()?['role'] as String?;
            isTeacher.value = role == 'teacher';
          });
    });
  }

  final ValueNotifier<bool> isTeacher = ValueNotifier<bool>(false);

  late final StreamSubscription<User?> _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _roleSub;

  Future<void> dispose() async {
    await _authSub.cancel();
    await _roleSub?.cancel();
    isTeacher.dispose();
  }
}
