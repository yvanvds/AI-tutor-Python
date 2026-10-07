// The learning objectives the signed-in student has demonstrated, for the
// Leerpad (#243): the ones whose `lo_beliefs` doc carries the one-way
// mastery stamp, `firstMasteredAt` (#168). That stamp is what the grade
// reads as "mastered" (PUNTENFORMULE §2.2), so the Leerpad and the grade
// count the same thing.
//
// Display only. Nothing here writes, and the belief itself, the tutor and
// the cached `progress` doc are neither read for this nor changed by it.
// The practice bar of #230 (`lo_display.dart`) keeps its own reading.

import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/student_state/lo_belief.dart';
import 'package:ai_tutor_python/services/student_state/lo_beliefs_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How many of a subgoal's non-optional learning objectives are
/// demonstrated: "3 van 4 aangetoond".
@immutable
class DemonstratedCount {
  const DemonstratedCount({required this.demonstrated, required this.total});

  /// Non-optional LOs of the subgoal that carry the stamp.
  final int demonstrated;

  /// Non-optional LOs of the subgoal.
  final int total;

  /// [demonstrated] over [total]; `null` for a subgoal without non-optional
  /// LOs, which has nothing to count.
  double? get fraction => total == 0 ? null : demonstrated / total;

  @override
  bool operator ==(Object other) =>
      other is DemonstratedCount &&
      other.demonstrated == demonstrated &&
      other.total == total;

  @override
  int get hashCode => Object.hash(demonstrated, total);

  @override
  String toString() => 'DemonstratedCount($demonstrated/$total)';
}

/// The stamped learning objectives of one student.
@immutable
class MasteryStamps {
  const MasteryStamps.empty() : _stamped = const {};

  /// The LOs among [beliefs] whose doc carries `firstMasteredAt`. A doc
  /// without it is not demonstrated, also when its belief would meet the
  /// three conditions today: the grade applies no such fallback either.
  MasteryStamps.fromBeliefs(Iterable<LoBelief> beliefs)
    : _stamped = {
        for (final b in beliefs)
          if (b.firstMasteredAt != null) _key(b.subgoalId, b.loId),
      };

  final Set<String> _stamped;

  static String _key(String subgoalId, String loId) => '$subgoalId/$loId';

  /// Whether the learning objective [loId] of the subgoal [subgoalId]
  /// carries the stamp.
  bool isDemonstrated(String subgoalId, String loId) =>
      _stamped.contains(_key(subgoalId, loId));

  /// The count over [subgoal]'s non-optional learning objectives, as its
  /// `objectives` list them: a belief on an LO that is no longer in the
  /// subgoal does not count.
  DemonstratedCount countFor(Goal subgoal) {
    final required = subgoal.objectives.where((o) => !o.optional).toList();
    return DemonstratedCount(
      demonstrated: required
          .where((o) => isDemonstrated(subgoal.id, o.id))
          .length,
      total: required.length,
    );
  }
}

/// The signed-in student's stamps, read once each time the Leerpad opens:
/// one single-partition query of `lo_beliefs`, the size of the curriculum.
/// Nothing on the Leerpad itself changes a stamp — practice happens in the
/// session, and leaving the Leerpad disposes this — so it is not polled.
final masteryStampsProvider = FutureProvider.autoDispose<MasteryStamps>((
  ref,
) async {
  final beliefs = await ref
      .watch(loBeliefsServiceProvider)
      .getAllForCurrentUser();
  return MasteryStamps.fromBeliefs(beliefs);
});
