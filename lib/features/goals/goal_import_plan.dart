// Planning for the goals-import Replace mode (#85).
//
// A "set" is one root goal (`parentId == null`) and its subtree. Replace used
// to delete every goal not in the file across *all* sets; the plan built here
// resolves each root entry in the file to one existing root and scopes the
// deletion to that root's subtree, so sets the file does not name are never
// touched. Entries that match no existing root are handed back so the page
// can ask the user (add as a new set / replace a chosen set / cancel).

import 'package:ai_tutor_python/services/goal/goal.dart';

/// One imported root entry resolved to what Replace will do with it.
class ReplaceTarget {
  ReplaceTarget({
    required this.entry,
    this.existingRoot,
    this.removedIds = const {},
  });

  /// The `{goal, subgoals}` map exactly as parsed from the file.
  final Map<String, dynamic> entry;

  /// The existing root whose subtree this entry replaces, or null when the
  /// entry is added as a new set (in which case nothing is deleted).
  final Goal? existingRoot;

  /// Ids in [existingRoot]'s subtree (root included) that are not in the
  /// file and will therefore be deleted.
  final Set<String> removedIds;

  String get importedTitle =>
      ((entry['goal'] as Map)['title'] as String?) ?? '';

  /// Nodes this entry ships: the root plus its subgoals.
  int get importedCount => 1 + ((entry['subgoals'] as List?)?.length ?? 0);
}

/// The automatic half of a scoped Replace: entries whose target root could be
/// resolved without asking ([resolved]) and entries that matched nothing
/// ([unmatched]) — the page asks the user what to do with those.
class ReplacePlan {
  ReplacePlan({required this.resolved, required this.unmatched});

  final List<ReplaceTarget> resolved;
  final List<Map<String, dynamic>> unmatched;
}

/// Ids of [rootId]'s subtree (root included) within [all].
Set<String> subtreeIds(List<Goal> all, String rootId) {
  final childrenOf = <String?, List<Goal>>{};
  for (final g in all) {
    childrenOf.putIfAbsent(g.parentId, () => []).add(g);
  }
  final out = <String>{};
  final queue = <String>[rootId];
  while (queue.isNotEmpty) {
    final id = queue.removeLast();
    if (!out.add(id)) continue;
    for (final child in childrenOf[id] ?? const <Goal>[]) {
      queue.add(child.id);
    }
  }
  return out;
}

/// Every id carried by one `{goal, subgoals}` entry.
Set<String> entryIds(Map<String, dynamic> entry) {
  final ids = <String>{};
  final gid = (entry['goal'] as Map)['id'];
  if (gid is String && gid.trim().isNotEmpty) ids.add(gid);
  final subgoals = (entry['subgoals'] as List?) ?? const [];
  for (final sg in subgoals.whereType<Map>()) {
    final sid = sg['id'];
    if (sid is String && sid.trim().isNotEmpty) ids.add(sid);
  }
  return ids;
}

/// Resolves each entry against the existing roots: first by root id, then by
/// exact title when that title identifies exactly one unclaimed root (the
/// escape hatch for a file whose ids were regenerated). Each existing root is
/// claimed by at most one entry. Entries that match nothing land in
/// [ReplacePlan.unmatched].
ReplacePlan buildReplacePlan(
  List<Goal> existing,
  List<Map<String, dynamic>> entries,
) {
  final roots = existing.where((g) => g.parentId == null).toList();
  final claimed = <String>{};
  final resolved = <ReplaceTarget>[];
  final unmatched = <Map<String, dynamic>>[];

  for (final entry in entries) {
    final goal = entry['goal'] as Map<String, dynamic>;
    final rootId = goal['id'];
    final title = (goal['title'] as String?) ?? '';

    Goal? match;
    if (rootId is String && rootId.trim().isNotEmpty) {
      for (final r in roots) {
        if (r.id == rootId && !claimed.contains(r.id)) {
          match = r;
          break;
        }
      }
    }
    if (match == null && title.isNotEmpty) {
      final byTitle = roots
          .where((r) => r.title == title && !claimed.contains(r.id))
          .toList();
      if (byTitle.length == 1) match = byTitle.first;
    }

    if (match == null) {
      unmatched.add(entry);
      continue;
    }
    claimed.add(match.id);
    resolved.add(resolveTarget(existing, entry, match));
  }
  return ReplacePlan(resolved: resolved, unmatched: unmatched);
}

/// The target for replacing [root]'s subtree with [entry]: everything under
/// [root] (root included) that the file does not mention gets deleted.
ReplaceTarget resolveTarget(
  List<Goal> existing,
  Map<String, dynamic> entry,
  Goal root,
) {
  return ReplaceTarget(
    entry: entry,
    existingRoot: root,
    removedIds: subtreeIds(existing, root.id).difference(entryIds(entry)),
  );
}
