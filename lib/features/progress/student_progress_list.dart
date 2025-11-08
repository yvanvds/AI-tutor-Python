import 'package:ai_tutor_python/features/progress/goal_tile.dart';
import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:flutter/material.dart';

/// Displays all goals & subgoals for the current student.
///
/// - Roots: parentId == null
/// - Subgoals: indented below their parent
/// - Each row: title, description, LinearProgressIndicator
/// - Subgoals only: “Work on this” button (callback provided by parent)
class StudentProgressList extends StatelessWidget {
  const StudentProgressList({super.key});

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
          stream: DataService.progress.watchAll(),
          builder: (context, progressSnap) {
            final progressList = progressSnap.data ?? const <Progress>[];

            // Map goalId -> Progress
            final progressById = <String, Progress>{
              for (final p in progressList) p.goalID: p,
            };

            // Separate roots and children
            final roots = goals.where((g) => g.parentId == null).toList()
              ..sort((a, b) => a.order.compareTo(b.order));

            final childrenByParent = <String, List<Goal>>{};
            for (final g in goals.where((g) => g.parentId != null)) {
              childrenByParent.putIfAbsent(g.parentId!, () => []).add(g);
            }
            for (final list in childrenByParent.values) {
              list.sort((a, b) => a.order.compareTo(b.order));
            }

            // Flatten tree into tiles
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
          },
        );
      },
    );
  }

  List<Widget> _buildGoalTiles(
    Goal goal,
    Goal? rootGoal,
    Map<String, List<Goal>> childrenByParent,
    Map<String, Progress> progressById, {
    required int depth,
  }) {
    final widgets = <Widget>[];

    widgets.add(
      GoalTile(
        goal: goal,
        progress: progressById[goal.id]?.progress ?? 0.0,
        depth: depth,
        isSubgoal: goal.parentId != null,
        rootGoal: rootGoal,
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
