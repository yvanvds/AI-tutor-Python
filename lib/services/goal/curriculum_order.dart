// The order the student sees the curriculum in.
//
// The Leerpad lists the root goals by `order`, each with its subgoals by
// `order`. The theory view pages back through the lessons of earlier goals
// in that same order (#272), so both read it here.

import 'package:ai_tutor_python/services/goal/goal.dart';

/// [goals] — roots and subgoals together, in any order, as
/// `GoalsService.streamAllGoals` hands them out — in the Leerpad's order.
class CurriculumOrder {
  CurriculumOrder(Iterable<Goal> goals)
    : roots = goals.where((g) => g.parentId == null).toList()..sort(_byOrder),
      childrenByParent = _childrenByParent(goals);

  /// The root goals, first to last.
  final List<Goal> roots;

  /// Each parent's subgoals, first to last, by the parent's id.
  final Map<String, List<Goal>> childrenByParent;

  /// The subgoals of [parentId], first to last; none for an unknown id.
  List<Goal> childrenOf(String parentId) =>
      childrenByParent[parentId] ?? const [];

  static int _byOrder(Goal a, Goal b) => a.order.compareTo(b.order);

  static Map<String, List<Goal>> _childrenByParent(Iterable<Goal> goals) {
    final out = <String, List<Goal>>{};
    for (final g in goals) {
      final parentId = g.parentId;
      if (parentId != null) out.putIfAbsent(parentId, () => []).add(g);
    }
    for (final list in out.values) {
      list.sort(_byOrder);
    }
    return out;
  }
}
