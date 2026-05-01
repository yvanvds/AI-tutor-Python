// Cosmos-backed AccountService (Step 3 of the migration).
//
// Public API matches the prior FirebaseAuth + Firestore version exactly so
// nothing in `features/` needs to change. The internals subscribe to
// `AuthService.currentUser` instead of `FirebaseAuth.authStateChanges()`,
// and persist to the `accounts` Cosmos container via `CosmosPaths`.
//
// Container shape:
//   - container = `accounts`
//   - partition key = `/uid` (the Entra Object ID)
//   - doc id == uid (one doc per user)

import 'dart:async';

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/data_service.dart';
import 'package:flutter/material.dart';

import 'account.dart';

class AccountService {
  AccountService() {
    DataService.auth.currentUser.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  final ValueNotifier<Account?> currentAccount = ValueNotifier<Account?>(null);

  StreamSubscription<Account?>? _accountSub;

  /// The uid of the most recent identity for which we kicked off a tutor
  /// session init. Polling-based streams emit on every tick, so we dedupe
  /// here and only re-init when the *user* actually changes.
  String? _lastInitedUid;

  CosmosContainer get _container => CosmosPaths.accounts();

  String? get currentUid => DataService.auth.currentUser.value?.oid;

  // --- AUTH-DRIVEN LIFECYCLE ----------------------------------------------

  void _onAuthChanged() {
    final identity = DataService.auth.currentUser.value;
    _accountSub?.cancel();
    _accountSub = null;

    if (identity == null) {
      _lastInitedUid = null;
      currentAccount.value = null;
      return;
    }

    // Fire-and-forget profile creation. Subsequent polls of the account doc
    // will pick up the result.
    unawaited(_ensureProfile(identity));

    _accountSub = watchAccount(identity.oid).listen((account) {
      currentAccount.value = account;
      if (account != null && account.uid != _lastInitedUid) {
        _lastInitedUid = account.uid;
        DataService.tutor.initializeSession(force: true);
      }
    });
  }

  /// First-login hook: if no Cosmos doc exists for this Entra user yet,
  /// create one from the MSAL account claims. Replaces the explicit upsert
  /// the old sign-in/register page used to do.
  Future<void> _ensureProfile(AccountIdentity identity) async {
    final existing = await getAccount(identity.oid);
    if (existing != null) return;
    await upsertAccount(
      uid: identity.oid,
      firstName: identity.firstName,
      lastName: identity.lastName,
      email: identity.email,
    );
  }

  // --- READS --------------------------------------------------------------

  Future<Account?> getAccount(String uid) async {
    final doc = await safeCosmos(
      () => _container.read(uid, partitionKey: uid),
    );
    if (doc == null) return null;
    return Account.fromMap(doc);
  }

  Future<Account?> getMyAccount() async {
    final uid = currentUid;
    if (uid == null) return null;
    return getAccount(uid);
  }

  Stream<Account?> watchAccount(String uid) {
    return safeCosmosStream(
      pollingStream(() => safeCosmos(() => _fetchAccount(uid))),
    );
  }

  /// Stream the signed-in user's account. Emits a single null and stops if
  /// nobody is signed in — the AuthService listener resubscribes when a
  /// user signs in.
  Stream<Account?> watchMyAccount() {
    final uid = currentUid;
    if (uid == null) return Stream<Account?>.value(null);
    return watchAccount(uid);
  }

  Stream<bool> watchMayUseGlobalKey(String uid) {
    return safeCosmosStream(
      pollingStream(() => safeCosmos(() => _fetchMayUseGlobalKey(uid))),
    );
  }

  Stream<bool> watchMyMayUseGlobalKey() {
    final uid = currentUid;
    if (uid == null) return Stream<bool>.value(false);
    return watchMayUseGlobalKey(uid);
  }

  Stream<List<Account>> streamAllAccounts() {
    return safeCosmosStream(
      pollingStream(() => safeCosmos(_fetchAllAccounts)),
    );
  }

  Future<List<Account>> getAllAccounts() => safeCosmos(_fetchAllAccounts);

  // --- WRITES -------------------------------------------------------------

  /// Create or update the account profile for [uid]. Preserves existing
  /// `mayUseGlobalKey` / `targetGoal` / `createdAt` on update; stamps
  /// `updatedAt` on every write.
  Future<void> upsertAccount({
    required String uid,
    required String firstName,
    required String lastName,
    required String email,
  }) async {
    final existing = await safeCosmos(
      () => _container.read(uid, partitionKey: uid),
    );
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final doc = <String, Object?>{
      'id': uid,
      'uid': uid,
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'targetGoal': existing?['targetGoal'] ?? '',
      'mayUseGlobalKey': existing?['mayUseGlobalKey'] ?? false,
      'createdAt': existing?['createdAt'] ?? nowIso,
      'updatedAt': nowIso,
    };
    await safeCosmos(() => _container.upsert(doc, partitionKey: uid));
  }

  Future<void> setTargetGoal({required String targetGoal}) async {
    final uid = currentUid;
    if (uid == null) {
      throw StateError('No authenticated user.');
    }
    await _patch(uid, {'targetGoal': targetGoal});
  }

  Future<void> setMayUseGlobalKey({
    required String uid,
    required bool value,
  }) async {
    await _patch(uid, {'mayUseGlobalKey': value});
  }

  Future<void> deleteAccountDoc(String uid) async {
    await safeCosmos(() => _container.delete(uid, partitionKey: uid));
  }

  // --- HELPERS ------------------------------------------------------------

  Future<void> _patch(String uid, Map<String, Object?> changes) async {
    final doc = await safeCosmos(
      () => _container.read(uid, partitionKey: uid),
    );
    if (doc == null) return;
    doc.addAll(changes);
    doc['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    await safeCosmos(() => _container.replace(uid, doc, partitionKey: uid));
  }

  Future<Account?> _fetchAccount(String uid) async {
    final doc = await _container.read(uid, partitionKey: uid);
    if (doc == null) return null;
    return Account.fromMap(doc);
  }

  Future<bool> _fetchMayUseGlobalKey(String uid) async {
    final doc = await _container.read(uid, partitionKey: uid);
    if (doc == null) return false;
    final v = doc['mayUseGlobalKey'];
    return v is bool ? v : false;
  }

  Future<List<Account>> _fetchAllAccounts() async {
    // Cross-partition `ORDER BY` over REST at api version 2018-12-31 needs
    // gateway-coordination headers our hand-rolled client doesn't send, and
    // returns an empty set without erroring when they're missing. We have
    // ~20 accounts max, so sort client-side instead.
    final docs = await _container.query(
      'SELECT * FROM c',
      crossPartition: true,
    );
    final accounts = docs.map(Account.fromMap).toList();
    accounts.sort((a, b) {
      final ad = a.createdAt;
      final bd = b.createdAt;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1; // nulls last
      if (bd == null) return -1;
      return bd.compareTo(ad); // newest first
    });
    return accounts;
  }

  void dispose() {
    DataService.auth.currentUser.removeListener(_onAuthChanged);
    _accountSub?.cancel();
    currentAccount.dispose();
  }
}
