import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'account.dart';
import 'account_repository.dart';

// Base Firebase instances
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final firebaseFirestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

// Repository
final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  final fs = ref.watch(firebaseFirestoreProvider);
  final auth = ref.watch(firebaseAuthProvider);
  return AccountRepository(fs, auth);
});

// Current user (FirebaseAuth)
final firebaseUserProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

// Current user's Account profile (Firestore)
final myAccountProvider = StreamProvider<Account?>((ref) {
  return ref.watch(accountRepositoryProvider).watchMyAccount();
});

// Fetch any account by uid once (for lookups in teacher/admin views)
final accountByUidProvider = FutureProvider.family<Account?, String>((
  ref,
  uid,
) async {
  return ref.watch(accountRepositoryProvider).getAccount(uid);
});
