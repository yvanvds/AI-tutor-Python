import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'account.dart';

class AccountRepository {
  AccountRepository(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String? get currentUid => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('accounts');

  DocumentReference<Map<String, dynamic>> _doc(String uid) => _col.doc(uid);

  /// Create or update the account profile for a given uid.
  Future<void> upsertAccount({
    required String uid,
    required String firstName,
    required String lastName,
    required String email,
  }) async {
    final ref = _doc(uid);
    final snap = await ref.get();
    if (snap.exists) {
      await ref.update({
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.set({
        'uid': uid,
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Convenience method: ensure the current user has an account profile.
  Future<void> ensureCurrentUserProfile({
    required String firstName,
    required String lastName,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await upsertAccount(
      uid: user.uid,
      firstName: firstName,
      lastName: lastName,
      email: user.email ?? '',
    );
  }

  /// Fetch one account once.
  Future<Account?> getAccount(String uid) async {
    final snap = await _doc(uid).get();
    if (!snap.exists) return null;
    return Account.fromDoc(snap);
  }

  /// Fetch one account once.
  Future<Account?> getMyAccount() async {
    final snap = await _doc(currentUid!).get();
    if (!snap.exists) return null;
    return Account.fromDoc(snap);
  }

  /// Watch one account by uid.
  Stream<Account?> watchAccount(String uid) {
    return _doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Account.fromDoc(doc);
    });
  }

  /// Watch the signed-in user's account (null if signed out or doc missing).
  Stream<Account?> watchMyAccount() {
    // react to auth state changes and switch to the right doc stream
    return _auth.authStateChanges().switchMap((user) {
      if (user == null) return Stream<Account?>.value(null);
      return watchAccount(user.uid);
    });
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
