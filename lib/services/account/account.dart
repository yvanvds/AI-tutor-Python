import 'package:cloud_firestore/cloud_firestore.dart';

class Account {
  final String uid;
  final String email;
  final String firstName;
  final String lastName;
  final String targetGoal;
  final bool mayUseGlobalKey;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  const Account({
    required this.uid,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.targetGoal,
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
      'targetGoal': targetGoal,
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
      targetGoal: data['targetGoal'] as String? ?? '',
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

  static Future<void> update({
    String? uid,
    String? email,
    String? firstName,
    String? lastName,
    String? targetGoal,
    bool? mayUseGlobalKey,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) async {
    var updates = <String, dynamic>{};
    if (uid != null) updates['uid'] = uid;
    if (email != null) updates['email'] = email;
    if (firstName != null) updates['firstName'] = firstName;
    if (lastName != null) updates['lastName'] = lastName;
    if (targetGoal != null) updates['targetGoal'] = targetGoal;
    if (mayUseGlobalKey != null) updates['mayUseGlobalKey'] = mayUseGlobalKey;
    if (createdAt != null) updates['createdAt'] = createdAt;
    if (updatedAt != null) updates['updatedAt'] = updatedAt;

    if (updates.isEmpty) return Future.value();

    Future updateTransaction(Transaction tx) async {
      final DocumentSnapshot ds = await tx.get(
        FirebaseFirestore.instance.collection('accounts').doc(uid),
      );
      tx.update(ds.reference, updates);
      return {'updated': true};
    }

    return FirebaseFirestore.instance
        .runTransaction(updateTransaction)
        .then((result) => result['updated'])
        .catchError((error) {
          return false;
        });
  }
}
