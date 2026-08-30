import 'dart:async';

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/student_state/student_calibration.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account.dart';

class AccountService extends Notifier<Account?> {
  AccountService({CosmosContainer? container}) : _containerOverride = container;

  final CosmosContainer? _containerOverride;

  StreamSubscription<Account?>? _accountSub;

  CosmosContainer get _container =>
      _containerOverride ?? CosmosPaths.accounts();

  @override
  Account? build() {
    ref.listen<AccountIdentity?>(
      authServiceProvider,
      (_, identity) => _onAuthChanged(identity),
      fireImmediately: true,
    );
    ref.onDispose(() => _accountSub?.cancel());
    return null;
  }

  String? get currentUid => ref.read(authServiceProvider)?.oid;

  // --- AUTH-DRIVEN LIFECYCLE ----------------------------------------------

  void _onAuthChanged(AccountIdentity? identity) {
    _accountSub?.cancel();
    _accountSub = null;

    if (identity == null) {
      state = null;
      return;
    }

    unawaited(_ensureProfileGuarded(identity));

    _accountSub = watchAccount(identity.oid).listen((account) {
      state = account;
      // First sign-in with Cosmos unreachable (#7): the profile create
      // failed, so the account doc never appears and `main.dart` would sit
      // on its spinner forever. Retry the create on every poll that still
      // comes back empty.
      if (account == null && _ensureProfileFailed) {
        unawaited(_ensureProfileGuarded(identity));
      }
    });
  }

  bool _ensureProfileFailed = false;
  bool _ensureProfileInFlight = false;

  Future<void> _ensureProfileGuarded(AccountIdentity identity) async {
    if (_ensureProfileInFlight) return;
    _ensureProfileInFlight = true;
    try {
      await _ensureProfile(identity);
      _ensureProfileFailed = false;
    } catch (e) {
      debugPrint('AccountService: ensureProfile failed, will retry: $e');
      _ensureProfileFailed = true;
    } finally {
      _ensureProfileInFlight = false;
    }
  }

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
    final doc = await safeCosmos(() => _container.read(uid, partitionKey: uid));
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
    return safeCosmosStream(pollingStream(() => safeCosmos(_fetchAllAccounts)));
  }

  Future<List<Account>> getAllAccounts() => safeCosmos(_fetchAllAccounts);

  // --- WRITES -------------------------------------------------------------

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
    if (uid == null) throw StateError('No authenticated user.');
    await _patch(uid, {'targetGoal': targetGoal});
  }

  Future<void> setMayUseGlobalKey({
    required String uid,
    required bool value,
  }) async {
    await _patch(uid, {'mayUseGlobalKey': value});
  }

  /// Persists the calibration substructure on the current user's account
  /// doc. Called by the conductor after every belief update.
  Future<void> setCalibration(StudentCalibration calibration) async {
    final uid = currentUid;
    if (uid == null) return;
    await _patch(uid, {'calibration': calibration.toJson()});
  }

  /// Records that the current user had a successful tutor turn "today".
  /// Implements the streak counter from issue #10 (option c): one int +
  /// one timestamp stored on the account doc, with a 36-hour grace window
  /// so a single missed day doesn't reset the streak.
  ///
  /// - Same UTC day as `streakLastAt`: no-op.
  /// - Within 36 h of `streakLastAt`: increment.
  /// - Otherwise (or no prior): reset to 1.
  Future<void> registerSessionTurn({DateTime? now}) async {
    final uid = currentUid;
    if (uid == null) return;
    final acc = state;
    if (acc == null) return;

    final ts = (now ?? DateTime.now()).toUtc();
    final last = acc.streakLastAt?.toUtc();

    if (last != null &&
        last.year == ts.year &&
        last.month == ts.month &&
        last.day == ts.day) {
      return;
    }

    final next = (last != null && ts.difference(last).inHours <= 36)
        ? acc.streakDays + 1
        : 1;

    await _patch(uid, {
      'streakDays': next,
      'streakLastAt': ts.toIso8601String(),
    });
  }

  Future<void> deleteAccountDoc(String uid) async {
    await safeCosmos(() => _container.delete(uid, partitionKey: uid));
  }

  // --- HELPERS ------------------------------------------------------------

  Future<void> _patch(String uid, Map<String, Object?> changes) async {
    final doc = await safeCosmos(() => _container.read(uid, partitionKey: uid));
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
    final docs = await _container.query(
      'SELECT * FROM c',
      crossPartition: true,
    );
    final accounts = docs.map(Account.fromMap).toList();
    accounts.sort((a, b) {
      final ad = a.createdAt;
      final bd = b.createdAt;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });
    return accounts;
  }
}

// Provider declared here so importing account_service.dart is sufficient.
final accountServiceProvider = NotifierProvider<AccountService, Account?>(
  AccountService.new,
);
