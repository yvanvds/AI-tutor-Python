import 'package:ai_tutor_python/features/progress/widgets/leerpad_card.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:ai_tutor_python/services/progress/teacher_signals.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Student "Leerpad" — a vertical list of root goal cards, with the
/// currently-active root expanded to show its children. Replaces the older
/// `StudentProgressList` view for the student-facing path.
class LeerpadPage extends ConsumerWidget {
  const LeerpadPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsService = ref.read(goalsServiceProvider);
    final progressService = ref.read(progressServiceProvider);
    final topic = ref.watch(profileProvider).topic;

    return Container(
      color: AppColors.ink0,
      child: StreamBuilder<List<Goal>>(
        stream: goalsService.streamAllGoals(),
        builder: (context, goalsSnap) {
          if (goalsSnap.hasError) {
            return const _Centered('Kon de doelen niet laden.');
          }
          if (!goalsSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final goals = goalsSnap.data!;
          if (goals.isEmpty) {
            return const _Centered('Er zijn nog geen doelen beschikbaar.');
          }

          return StreamBuilder<List<Progress>>(
            stream: progressService.watchAll(),
            builder: (context, progressSnap) {
              return _LeerpadBody(
                goals: goals,
                progress: progressSnap.data ?? const [],
                topic: topic,
              );
            },
          );
        },
      ),
    );
  }
}

class _LeerpadBody extends ConsumerWidget {
  const _LeerpadBody({
    required this.goals,
    required this.progress,
    required this.topic,
  });

  final List<Goal> goals;
  final List<Progress> progress;
  final String topic;

  static const _maxWidth = 760.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressById = {for (final p in progress) p.goalID: p};
    final roots = goals.where((g) => g.parentId == null).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final childrenByParent = <String, List<Goal>>{};
    for (final g in goals.where((g) => g.parentId != null)) {
      childrenByParent.putIfAbsent(g.parentId!, () => []).add(g);
    }
    for (final list in childrenByParent.values) {
      list.sort((a, b) => a.order.compareTo(b.order));
    }

    final activeRootId = _resolveActiveRoot(
      ref: ref,
      roots: roots,
      progressById: progressById,
      progressAll: progress,
      childrenByParent: childrenByParent,
    );

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxxl,
        vertical: AppSpacing.xxl,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: _Header(topic: topic),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        for (var i = 0; i < roots.length; i++)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxWidth),
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.m),
                child: LeerpadCard(
                  index: i + 1,
                  root: roots[i],
                  children: childrenByParent[roots[i].id] ?? const [],
                  progressById: progressById,
                  isActive: roots[i].id == activeRootId,
                  onContinue: () => _continueRoot(ref, roots[i]),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String? _resolveActiveRoot({
    required WidgetRef ref,
    required List<Goal> roots,
    required Map<String, Progress> progressById,
    required List<Progress> progressAll,
    required Map<String, List<Goal>> childrenByParent,
  }) {
    final selection = ref.watch(goalSelectionProvider);
    final fromSelection = selection.activeRootGoal?.id;
    if (fromSelection != null && roots.any((r) => r.id == fromSelection)) {
      return fromSelection;
    }

    final mostRecent = mostRecentlyActive(progressAll);
    if (mostRecent != null) {
      final goal = goals.firstWhere(
        (g) => g.id == mostRecent.goalID,
        orElse: () => roots.first,
      );
      if (goal.parentId == null) return goal.id;
      return goal.parentId;
    }

    for (final root in roots) {
      final children = childrenByParent[root.id] ?? const <Goal>[];
      final p = _aggregateRootProgress(children, progressById);
      if (p > 0 && p < 1) return root.id;
    }
    return roots.isEmpty ? null : roots.first.id;
  }

  void _continueRoot(WidgetRef ref, Goal root) {
    final sel = ref.read(goalSelectionProvider.notifier);
    sel.setPreferredRoot(root);
    sel.setPreferredChild(null);
    ref.read(tutorServiceProvider.notifier).initializeSession(force: true);
    ref.read(sectionProvider.notifier).state = Section.session;
    ref.read(modeProvider.notifier).state = SessionMode.explain;
  }
}

double _aggregateRootProgress(
  List<Goal> children,
  Map<String, Progress> progressById,
) {
  final required = children.where((c) => !c.optional).toList();
  if (required.isEmpty) return 0;
  double sum = 0;
  for (final c in required) {
    sum += progressById[c.id]?.progress ?? 0;
  }
  return (sum / required.length).clamp(0.0, 1.0);
}

class _Header extends StatelessWidget {
  const _Header({required this.topic});
  final String topic;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Leerpad',
          style: TextStyle(
            color: AppColors.fg,
            fontSize: 30,
            fontWeight: FontWeight.w700,
            height: 1.15,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          topic.isEmpty ? 'Python — beginnersreis' : topic,
          style: const TextStyle(
            color: AppColors.fgFaint,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: const TextStyle(color: AppColors.fgMute, fontSize: 14),
      ),
    );
  }
}
