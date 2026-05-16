import 'package:ai_tutor_python/features/progress/goal_tile.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Displays all goals & subgoals for a student.
///
/// When [uid] is null the list is for the signed-in student and the action
/// buttons on subgoals are wired to the conductor. When [uid] is provided
/// the list is for *that* student (teacher-side detail drawer): the same
/// per-uid `Progress` is read but every action is suppressed and the
/// per-subgoal teacher annotations are revealed.
class StudentProgressList extends ConsumerWidget {
  const StudentProgressList({super.key, this.uid});

  final String? uid;

  bool get _readOnly => uid != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsService = ref.read(goalsServiceProvider);
    final progressService = ref.read(progressServiceProvider);

    return StreamBuilder<List<Goal>>(
      stream: goalsService.streamAllGoals(),
      builder: (context, goalsSnap) {
        final l = AppLocalizations.of(context);
        if (goalsSnap.hasError) {
          return Center(child: Text(l.progress_loadError));
        }
        if (!goalsSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final goals = goalsSnap.data!;
        if (goals.isEmpty) {
          return Center(child: Text(l.progress_empty));
        }

        final progressStream = uid == null
            ? progressService.watchAll()
            : progressService.watchProgressForUser(uid!);

        return StreamBuilder<List<Progress>>(
          stream: progressStream,
          builder: (context, progressSnap) =>
              _buildProgressList(goals, progressSnap.data ?? const []),
        );
      },
    );
  }

  Widget _buildProgressList(List<Goal> goals, List<Progress> progressList) {
    final progressById = <String, Progress>{
      for (final p in progressList) p.goalID: p,
    };

    final roots = goals.where((g) => g.parentId == null).toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    final childrenByParent = <String, List<Goal>>{};
    for (final g in goals.where((g) => g.parentId != null)) {
      childrenByParent.putIfAbsent(g.parentId!, () => []).add(g);
    }
    for (final list in childrenByParent.values) {
      list.sort((a, b) => a.order.compareTo(b.order));
    }

    final tiles = <Widget>[];
    for (final root in roots) {
      tiles.addAll(
        _buildGoalTiles(root, null, childrenByParent, progressById, depth: 0),
      );
    }

    return ListView(padding: const EdgeInsets.all(16), children: tiles);
  }

  List<Widget> _buildGoalTiles(
    Goal goal,
    Goal? rootGoal,
    Map<String, List<Goal>> childrenByParent,
    Map<String, Progress> progressById, {
    required int depth,
  }) {
    final widgets = <Widget>[];
    final progressDoc = progressById[goal.id];

    widgets.add(
      GoalTile(
        goal: goal,
        progress: progressDoc?.progress ?? 0.0,
        depth: depth,
        isSubgoal: goal.parentId != null,
        rootGoal: rootGoal,
        readOnly: _readOnly,
        progressDoc: progressDoc,
      ),
    );

    final children = childrenByParent[goal.id] ?? const <Goal>[];
    for (final child in children) {
      widgets.addAll(
        _buildGoalTiles(
          child,
          goal,
          childrenByParent,
          progressById,
          depth: depth + 1,
        ),
      );
    }

    return widgets;
  }
}
