import 'package:ai_tutor_python/services/goal/goal.dart';

/// Build quick parent lookup.
Map<String, String?> buildParentMap(Iterable<Goal> goals) => {
  for (final g in goals) g.id: g.parentId,
};

/// Returns true if `ancestorId` is an ancestor of `nodeId`.
bool isAncestor(
  Map<String, String?> parentOf,
  String? ancestorId,
  String nodeId,
) {
  var cur = parentOf[nodeId];
  while (cur != null) {
    if (cur == ancestorId) return true;
    cur = parentOf[cur];
  }
  return false;
}

/// Would assigning `newParentId` to `dragId` create a cycle?
bool wouldCreateCycle(
  Map<String, String?> parentOf,
  String? dragId,
  String? newParentId,
) {
  if (newParentId == null) return false; // moving to root is always safe
  if (newParentId == dragId) return true; // parent cannot be itself
  // If dragId is an ancestor of newParentId, we'd form a cycle.
  return isAncestor(parentOf, dragId, newParentId);
}
