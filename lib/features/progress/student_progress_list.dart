import 'package:ai_tutor_python/features/progress/goal_tile.dart';
import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:flutter/material.dart';

/// Displays all goals & subgoals for a student.
///
/// - Roots: parentId == null
/// - Subgoals: indented below their parent
/// - Each row: title, description, LinearProgressIndicator
/// - Subgoals only: "Work on this" button (callback provided by parent)
///
/// When [uid] is null the list is for the signed-in student and the action
/// buttons on subgoals are wired to the conductor. When [uid] is provided
/// the list is for *that* student (teacher-side detail drawer): the same
/// per-uid `Progress` is read but every action is suppressed and the
/// per-subgoal teacher annotations (recent-answers strip, persisted
/// difficulty label) are revealed.
class StudentProgressList extends StatelessWidget {
  const StudentProgressList({super.key, this.uid});

  final String? uid;

  bool get _readOnly => uid != null;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Goal>>(
      stream: DataService.goals.streamAllGoals(),
      builder: (context, goalsSnap) {
        if (goalsSnap.hasError) {
          return const Center(child: Text('Kon de doelen niet laden.'));
        }
        if (!goalsSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final goals = goalsSnap.data!;
        if (goals.isEmpty) {
          return const Center(
            child: Text('Er zijn nog geen doelen beschikbaar.'),
          );
        }

        return StreamBuilder<List<Progress>>(
          stream: _progressStream(),
          builder: (context, progressSnap) =>
              _buildProgressList(goals, progressSnap.data ?? const []),
        );
      },
    );
  }

  Stream<List<Progress>> _progressStream() {
    final pinned = uid;
    if (pinned == null) {
      return DataService.progress.watchAll();
    }
    return DataService.progress.watchProgressForUser(pinned);
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
        _buildGoalTiles(
          root,
          null,
          childrenByParent,
          progressById,
          depth: 0,
        ),
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
