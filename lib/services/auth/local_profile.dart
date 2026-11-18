// The local profile of the stand-alone mode (#264, part of #261).
//
// Without a school there is no Entra and no id-token. The user gives a name
// on the welcome screen, the app makes a uid (a uuid) and keeps both in
// shared preferences, under the stand-alone scope (`AppMode.scopedPrefsKey`).
// `AuthService` turns it into the same `AccountIdentity` a school sign-in
// gives, so every service downstream works unchanged.
//
// One profile per Windows user: shared preferences already are.

import 'dart:convert';

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

@immutable
class LocalProfile {
  const LocalProfile({
    required this.uid,
    required this.firstName,
    this.lastName = '',
  });

  /// A new profile with a fresh uid. Names are trimmed.
  factory LocalProfile.create({
    required String firstName,
    String lastName = '',
  }) => LocalProfile(
    uid: const Uuid().v4(),
    firstName: firstName.trim(),
    lastName: lastName.trim(),
  );

  /// The partition key of the user's docs, as an Entra `oid` is in school
  /// mode.
  final String uid;
  final String firstName;
  final String lastName;

  LocalProfile withName({required String firstName, String lastName = ''}) =>
      LocalProfile(
        uid: uid,
        firstName: firstName.trim(),
        lastName: lastName.trim(),
      );

  String get displayName =>
      [firstName, lastName].where((s) => s.isNotEmpty).join(' ');

  /// The identity the rest of the app reads. Never a teacher, no e-mail.
  AccountIdentity toIdentity() => AccountIdentity(
    oid: uid,
    displayName: displayName,
    email: '',
    firstName: firstName,
    lastName: lastName,
    isTeacher: false,
  );

  Map<String, Object?> toJson() => {
    'uid': uid,
    'firstName': firstName,
    'lastName': lastName,
  };

  /// `null` for anything that is not a profile with a uid.
  static LocalProfile? fromJson(Object? json) {
    if (json is! Map) return null;
    final uid = json['uid'];
    if (uid is! String || uid.isEmpty) return null;
    final first = json['firstName'];
    final last = json['lastName'];
    return LocalProfile(
      uid: uid,
      firstName: first is String ? first : '',
      lastName: last is String ? last : '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LocalProfile &&
      other.uid == uid &&
      other.firstName == firstName &&
      other.lastName == lastName;

  @override
  int get hashCode => Object.hash(uid, firstName, lastName);
}

/// Where [LocalProfile] is kept: shared preferences, scoped per mode.
class LocalProfileStore {
  const LocalProfileStore(this.mode);

  final AppMode mode;

  static const String prefsKey = 'local_profile_v1';

  String get _key => mode.scopedPrefsKey(prefsKey);

  Future<LocalProfile?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return LocalProfile.fromJson(jsonDecode(raw));
    } catch (e) {
      debugPrint('LocalProfileStore: unreadable profile: $e');
      return null;
    }
  }

  Future<void> save(LocalProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(profile.toJson()));
  }
}
