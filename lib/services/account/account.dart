import 'package:ai_tutor_python/services/badges/earned_badges.dart';
import 'package:ai_tutor_python/services/student_state/student_calibration.dart';

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

  /// Per-student difficulty calibration substructure (STUDENT_MODEL §
  /// "Account doc"). Defaults to a fresh calibration when the field is
  /// absent on disk.
  final StudentCalibration calibration;

  /// Number of consecutive "active days" with a successful tutor turn.
  /// Bumped by AccountService.registerSessionTurn with a 36-hour grace
  /// window (issue #10, option c).
  final int streakDays;

  /// UTC timestamp of the most recent successful tutor turn, or null for
  /// a fresh account. Used for the streak grace-window calculation and
  /// for de-duplicating same-day increments.
  final DateTime? streakLastAt;

  /// Class/group tag assigned by the teacher on the Students page (#86).
  /// Free text; empty means "no class". Drives the class filter above the
  /// students table.
  final String className;

  /// How many oefeningen the student has made (#217): one per question,
  /// counted at its first graded answer whatever the grade, never for a
  /// follow-up. Only ever goes up — a progress reset or archive import
  /// leaves it alone — and is worth `kXpPerOefening` each in the XP.
  /// `0` when the field is absent on disk.
  final int oefeningCount;

  /// The badges the student earned (#220): per badge the tier and when it
  /// was reached. `null` when the doc has no `badges` field — the app never
  /// looked at this student's badges yet. Written only by
  /// `AccountService.awardBadges`, which never lowers a tier.
  final EarnedBadges? badges;

  const Account({
    required this.uid,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.targetGoal,
    this.mayUseGlobalKey = false,
    this.createdAt,
    this.updatedAt,
    this.calibration = const StudentCalibration(
      difficulty: StudentCalibration.defaultDifficulty,
    ),
    this.streakDays = 0,
    this.streakLastAt,
    this.className = '',
    this.oefeningCount = 0,
    this.badges,
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
    'calibration': calibration.toJson(),
    'streakDays': streakDays,
    if (streakLastAt != null)
      'streakLastAt': streakLastAt!.toUtc().toIso8601String(),
    'className': className,
    'oefeningCount': oefeningCount,
    if (badges != null)
      'badges': {
        for (final entry in badges!.byId.entries)
          entry.key: entry.value.toJson(),
      },
  };

  factory Account.fromMap(Map<String, dynamic> data) {
    final created = data['createdAt'];
    final updated = data['updatedAt'];
    final rawCal = data['calibration'];
    final cal = rawCal is Map
        ? StudentCalibration.fromJson(rawCal.cast<String, dynamic>())
        : StudentCalibration.fresh();
    return Account(
      uid: (data['uid'] as String?) ?? data['id'] as String,
      email: data['email'] as String? ?? '',
      firstName: data['firstName'] as String? ?? '',
      lastName: data['lastName'] as String? ?? '',
      targetGoal: data['targetGoal'] as String? ?? '',
      mayUseGlobalKey: (data['mayUseGlobalKey'] as bool?) ?? false,
      createdAt: created is String ? DateTime.tryParse(created) : null,
      updatedAt: updated is String ? DateTime.tryParse(updated) : null,
      calibration: cal,
      streakDays: (data['streakDays'] as int?) ?? 0,
      streakLastAt: data['streakLastAt'] is String
          ? DateTime.tryParse(data['streakLastAt'] as String)
          : null,
      className: data['className'] as String? ?? '',
      oefeningCount: oefeningCountOf(data),
      badges: EarnedBadges.fromDoc(data),
    );
  }
}

/// The `oefeningCount` on an account doc map (#217): a whole number of at
/// least 0, `0` when the field is missing or not a number.
int oefeningCountOf(Map<String, dynamic> doc) {
  final raw = doc['oefeningCount'];
  if (raw is! num || raw.isNaN || raw.isInfinite) return 0;
  final n = raw.toInt();
  return n < 0 ? 0 : n;
}
