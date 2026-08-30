import 'package:ai_tutor_python/services/content/content.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';

/// Content docs that no goal points to via `contentId`.
///
/// This happens when a goal re-import in Replace mode ships new subgoal ids:
/// the old subgoals are deleted, but their content docs (keyed by the old
/// subgoal id) stay behind in Cosmos with nothing referencing them. It also
/// covers content that a teacher explicitly unlinked. Either way the authored
/// lesson is invisible in the editor tree until it is reassigned.
///
/// Returned in the order of [contents].
List<Content> orphanedContent(List<Goal> goals, List<Content> contents) {
  final referenced = <String>{
    for (final g in goals)
      if (g.contentId != null && g.contentId!.isNotEmpty) g.contentId!,
  };
  return contents.where((c) => !referenced.contains(c.id)).toList();
}
