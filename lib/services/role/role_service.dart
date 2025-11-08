import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';

class RoleService {
  RoleService() {
    FirebaseAuth.instance.authStateChanges().switchMap((user) {
      if (user == null) {
        isTeacher.value = false;
      } else {
        _subscription = FirebaseFirestore.instance
            .collection('roles')
            .doc(user.uid)
            .snapshots()
            .listen((snapshot) {
              isTeacher.value = snapshot.data()?['role'] == 'teacher';
            });
      }
      return const Stream.empty();
    });
  }

  final ValueNotifier<bool> isTeacher = ValueNotifier<bool>(false);
  late final StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>
  _subscription;

  void dispose() {
    _subscription.cancel();
    isTeacher.dispose();
  }
}

// Small Stream extension for switchMap without importing rxdart.
extension _SwitchMap<T> on Stream<T> {
  Stream<S> switchMap<S>(Stream<S> Function(T) project) async* {
    StreamSubscription<S>? innerSub;
    final controller = StreamController<S>();
    late StreamSubscription<T> outerSub;

    void closeAll() async {
      await innerSub?.cancel();
      await controller.close();
      await outerSub.cancel();
    }

    outerSub = listen(
      (event) {
        innerSub?.cancel();
        innerSub = project(
          event,
        ).listen(controller.add, onError: controller.addError);
      },
      onError: controller.addError,
      onDone: () async {
        await innerSub?.cancel();
        await controller.close();
      },
    );

    yield* controller.stream;
    closeAll();
  }
}
