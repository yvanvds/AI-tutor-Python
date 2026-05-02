import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:flutter/material.dart';

class GoalTile extends StatelessWidget {
  final Goal goal;
  final Goal? rootGoal;
  final double progress;
  final int depth;
  final bool isSubgoal;

  /// When true, the tile renders as a teacher peek: action buttons are
  /// hidden and the per-subgoal teacher annotations (recent-answers strip,
  /// persisted difficulty) are revealed when [progressDoc] is available.
  final bool readOnly;

  /// Full progress doc for this goal. Optional — only the read-only/teacher
  /// path needs the extra fields off it. The student-facing call sites can
  /// keep passing nothing.
  final Progress? progressDoc;

  const GoalTile({
    super.key,
    required this.goal,
    required this.rootGoal,
    required this.progress,
    required this.depth,
    required this.isSubgoal,
    this.readOnly = false,
    this.progressDoc,
  });

  @override
  Widget build(BuildContext context) {
    final indent = depth * 16.0;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(left: indent, bottom: 12),
      child: Card(
        elevation: isSubgoal ? 0 : 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title + optional button
              Row(
                children: [
                  Expanded(
                    child: Text(goal.title, style: theme.textTheme.titleMedium),
                  ),
                  if (!readOnly && isSubgoal && progress < 1.0)
                    ElevatedButton.icon(
                      onPressed: () async {
                        final newProgress = (progress + 0.1).clamp(0.0, 1.0);
                        await DataService.progress.upsert(
                          Progress(goalID: goal.id, progress: newProgress),
                        );
                        DataService.progress.currentProgress.value =
                            newProgress;
                      },
                      icon: const Icon(Icons.fast_forward),
                      label: const Text('Ga sneller'),
                    ),
                  if (!readOnly && isSubgoal)
                    ElevatedButton.icon(
                      onPressed: () async {
                        DataService.goals.preferredChildGoal.value = goal;
                        DataService.goals.preferredRootGoal.value = rootGoal;

                        if (progress >= 1.0) {
                          await DataService.progress.upsert(
                            Progress(goalID: goal.id, progress: 0.5),
                          );
                          DataService.progress.currentProgress.value = 0.5;
                        } else {
                          DataService.progress.currentProgress.value = progress;
                        }

                        DataService.tutor.initializeSession(force: true);
                      },
                      label: const Text('Werk hieraan'),
                      icon: const Icon(Icons.play_arrow),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                      ),
                    ),
                ],
              ),

              // Description
              if (goal.description != null &&
                  goal.description!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                  child: Text(
                    goal.description!,
                    style: theme.textTheme.bodySmall,
                  ),
                ),

              // Progress bar + %
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${(progress * 100).round()}%'),
                ],
              ),

              if (readOnly && isSubgoal && progressDoc != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: _TeacherSubgoalAnnotations(progress: progressDoc!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact strip rendered under the progress bar in the teacher detail
/// drawer. Shows the persisted difficulty label and up to 5 colour-coded
/// dots from `recentAnswers` (oldest left).
class _TeacherSubgoalAnnotations extends StatelessWidget {
  const _TeacherSubgoalAnnotations({required this.progress});

  final Progress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dots = progress.recentAnswers;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            _difficultyLabel(progress.difficulty),
            style: theme.textTheme.bodySmall,
          ),
        ),
        const SizedBox(width: 12),
        if (dots.isEmpty)
          Text(
            'Nog geen antwoorden',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Row(
            children: [
              for (final q in dots)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _AnswerDot(quality: q),
                ),
            ],
          ),
      ],
    );
  }

  String _difficultyLabel(QuestionDifficulty d) {
    switch (d) {
      case QuestionDifficulty.easy:
        return 'gemakkelijk';
      case QuestionDifficulty.medium:
        return 'gemiddeld';
      case QuestionDifficulty.hard:
        return 'moeilijk';
    }
  }
}

class _AnswerDot extends StatelessWidget {
  const _AnswerDot({required this.quality});

  final AnswerQuality quality;

  @override
  Widget build(BuildContext context) {
    final color = switch (quality) {
      AnswerQuality.wrong => Colors.red.shade400,
      AnswerQuality.partial => Colors.amber.shade400,
      AnswerQuality.correct => Colors.green.shade400,
    };
    return Tooltip(
      message: quality.name,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
