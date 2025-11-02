import 'package:cloud_firestore/cloud_firestore.dart';

class Account {
  final String uid;
  final String email;
  final String firstName;
  final String lastName;
  final bool mayUseGlobalKey;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  const Account({
    required this.uid,
    required this.email,
    required this.firstName,
    required this.lastName,
    this.mayUseGlobalKey = false, // default to false for safety/back-compat
    this.createdAt,
    this.updatedAt,
  });

  String get displayFirstName => firstName;
  String get fullName => '$firstName $lastName';

  /// Convenience for your routing logic.
  bool get requiresLocalKey => !mayUseGlobalKey;

  Map<String, dynamic> toMap({bool includeTimestamps = true}) {
    final map = <String, dynamic>{
      'uid': uid,
      'email': email,
      'firstName': firstName,
      'lastName': lastName,
      'mayUseGlobalKey': mayUseGlobalKey, // NEW
    };
    if (includeTimestamps) {
      map['updatedAt'] = FieldValue.serverTimestamp();
      map['createdAt'] = createdAt ?? FieldValue.serverTimestamp();
    }
    return map;
  }

  factory Account.fromMap(Map<String, dynamic> data) {
    return Account(
      uid: data['uid'] as String,
      email: data['email'] as String? ?? '',
      firstName: data['firstName'] as String? ?? '',
      lastName: data['lastName'] as String? ?? '',
      mayUseGlobalKey: (data['mayUseGlobalKey'] as bool?) ?? false, // NEW
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
    );
  }

  factory Account.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    // Ensure uid falls back to doc.id if not present
    data['uid'] ??= doc.id;
    return Account.fromMap(data);
  }

  Account copyWith({
    String? uid,
    String? email,
    String? firstName,
    String? lastName,
    bool? mayUseGlobalKey,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return Account(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      mayUseGlobalKey: mayUseGlobalKey ?? this.mayUseGlobalKey,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
