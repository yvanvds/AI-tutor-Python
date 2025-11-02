import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'account.dart';
import 'account_repository.dart';

/*
In our homeshell, we have buttons on the left to go to different pages, like dashboard, goals and instructions. The all build their own scaffold with their contents.

I want you to build a new page AccountsPage. In there, we should display a scrollable list of all accounts. We show their email, firstName and lastName, and when they are last logged in. Next to that, there should be a toggle that switches the value of mayUseGlobalKey. Next to that, there should be a button that deletes the account.
*/

// Base Firebase instances
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final firebaseFirestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final firebaseCurrentUserProvider = Provider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).currentUser;
});

// Repository
final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  final fs = ref.watch(firebaseFirestoreProvider);
  final auth = ref.watch(firebaseAuthProvider);
  return AccountRepository(fs, auth);
});

// Current user (FirebaseAuth)
final firebaseUserProviderStream = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

// Current user's Account profile (Firestore)
final myAccountProviderStream = StreamProvider<Account?>((ref) {
  return ref.watch(accountRepositoryProvider).watchMyAccount();
});

final myAccountProviderFuture = FutureProvider.autoDispose<Account?>((ref) {
  return ref.watch(accountRepositoryProvider).getMyAccount();
});

// Fetch any account by uid once (for lookups in teacher/admin views)
final accountByUidProviderFuture = FutureProvider.autoDispose
    .family<Account?, String>((ref, uid) async {
      return ref.watch(accountRepositoryProvider).getAccount(uid);
    });

/// Live stream of all accounts.
final allAccountsProviderStream = StreamProvider<List<Account>>((ref) {
  return ref.watch(accountRepositoryProvider).streamAllAccounts();
});

/// One-shot fetch of all accounts.
final allAccountsProviderFuture = FutureProvider.autoDispose<List<Account>>((
  ref,
) {
  return ref.watch(accountRepositoryProvider).getAllAccounts();
});

/// Stream a specific account by uid (handy for detail panes).
final accountByUidProviderStream = StreamProvider.family<Account?, String>((
  ref,
  uid,
) {
  return ref.watch(accountRepositoryProvider).watchAccount(uid);
});

// --- Flag streams ---

/// Live boolean for the signed-in user. Emits `false` if signed out or missing.
final myMayUseGlobalKeyProviderStream = StreamProvider<bool>((ref) {
  return ref.watch(accountRepositoryProvider).watchMyMayUseGlobalKey();
});

/// Live boolean for any user (use in teacher/admin UI).
final mayUseGlobalKeyByUidProviderStream = StreamProvider.family<bool, String>((
  ref,
  uid,
) {
  return ref.watch(accountRepositoryProvider).watchMayUseGlobalKey(uid);
});

/// Whether we should show the local-key gate screen (AsyncValue<bool>):
/// - `true`: show the “Provide your own key” screen
/// - `false`: show the normal dashboard
/// - loading/error: handle with standard AsyncValue UI
final shouldShowLocalKeyGateProvider = Provider<AsyncValue<bool>>((ref) {
  final userAv = ref.watch(firebaseUserProviderStream);
  final flagAv = ref.watch(myMayUseGlobalKeyProviderStream);

  // Not logged in → don't show the gate (router likely handles auth separately)
  if (userAv is AsyncData<User?> && userAv.value == null) {
    return const AsyncData(false);
  }

  // If either is loading, surface loading
  if (userAv.isLoading || flagAv.isLoading) {
    return const AsyncLoading();
  }

  // Bubble up errors if any
  if (userAv.hasError)
    return AsyncError(userAv.error!, userAv.stackTrace ?? StackTrace.current);
  if (flagAv.hasError)
    return AsyncError(flagAv.error!, flagAv.stackTrace ?? StackTrace.current);

  final hasGlobalKey = (flagAv as AsyncData<bool>).value;
  return AsyncData(!hasGlobalKey);
});

// --- Command (teacher/admin) ---

/// Callable to toggle the flag from UI code:
/// `ref.read(setMayUseGlobalKeyProvider)(uid, true);`
final setMayUseGlobalKeyProvider =
    Provider<Future<void> Function(String uid, bool value)>((ref) {
      final repo = ref.watch(accountRepositoryProvider);
      return (String uid, bool value) =>
          repo.setMayUseGlobalKey(uid: uid, value: value);
    });

/// Delete account profile doc.
/// Usage: await ref.read(deleteAccountProvider)(uid);
final deleteAccountProvider = Provider<Future<void> Function(String uid)>((
  ref,
) {
  final repo = ref.watch(accountRepositoryProvider);
  return (String uid) => repo.deleteAccountDoc(uid);
});
