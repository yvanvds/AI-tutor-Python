/// One row of the `accounts` Cosmos container. Doc id == uid (the Entra
/// Object ID), partition key is the same uid.
class Account {
  final String uid;
  final String email;
  final String firstName;
  final String lastName;
  final String targetGoal;
  final bool mayUseGlobalKey;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Account({
    required this.uid,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.targetGoal,
    this.mayUseGlobalKey = false,
    this.createdAt,
    this.updatedAt,
  });

  String get displayFirstName => firstName;
  String get fullName => '$firstName $lastName';

  /// Convenience for the routing logic in `main.dart` / `LocalKeyGateScreen`.
  bool get requiresLocalKey => !mayUseGlobalKey;

  /// Build a Cosmos doc map. The service is in charge of stamping
  /// `updatedAt` (and `createdAt` on first insert), so this serializer just
  /// echoes the model's current values — see AccountService.upsertAccount.
  Map<String, dynamic> toMap() => {
    'id': uid,
    'uid': uid,
    'email': email,
    'firstName': firstName,
    'lastName': lastName,
    'targetGoal': targetGoal,
    'mayUseGlobalKey': mayUseGlobalKey,
    if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
  };

  factory Account.fromMap(Map<String, dynamic> data) {
    final created = data['createdAt'];
    final updated = data['updatedAt'];
    return Account(
      uid: (data['uid'] as String?) ?? data['id'] as String,
      email: data['email'] as String? ?? '',
      firstName: data['firstName'] as String? ?? '',
      lastName: data['lastName'] as String? ?? '',
      targetGoal: data['targetGoal'] as String? ?? '',
      mayUseGlobalKey: (data['mayUseGlobalKey'] as bool?) ?? false,
      createdAt: created is String ? DateTime.tryParse(created) : null,
      updatedAt: updated is String ? DateTime.tryParse(updated) : null,
    );
  }
}
