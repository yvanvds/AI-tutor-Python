import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/student_state/mastery_stamps.dart';
import 'package:ai_tutor_python/services/translation/localized_text.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a subgoal asks, opened from its tile on the Leerpad (#243): each
/// learning objective as its "Je kan …" sentence, marked demonstrated or
/// not yet — the mastery stamp the grade reads (PUNTENFORMULE §2.2).
///
/// The non-optional LOs come first, as many as the tile counts; an
/// optional one follows, marked as such. There is no advice per LO and no
/// way to retry one from here: the app picks the exercises, and how an
/// open LO can still be shown is decided separately (#249).
///
/// [stamps] is `null` while they load or when they could not be read: the
/// sentences then show without a status.
class LeerpadObjectivesPanel extends ConsumerWidget {
  const LeerpadObjectivesPanel({
    super.key,
    required this.subgoal,
    required this.stamps,
  });

  final Goal subgoal;
  final MasteryStamps? stamps;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = ref.watch(localizedGoalOf(subgoal)).title;
    final ordered = [
      ...subgoal.objectives.where((o) => !o.optional),
      ...subgoal.objectives.where((o) => o.optional),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.ink0,
        border: Border.all(color: AppColors.ink2),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppColors.fg,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          for (final lo in ordered)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: LeerpadObjectiveRow(
                subgoalId: subgoal.id,
                objective: lo,
                demonstrated: stamps?.isDemonstrated(subgoal.id, lo.id),
              ),
            ),
        ],
      ),
    );
  }
}

/// One learning objective in [LeerpadObjectivesPanel]: its statement in the
/// app language when there is a translation, else in Dutch (#243), and
/// under it whether it is demonstrated.
class LeerpadObjectiveRow extends ConsumerWidget {
  const LeerpadObjectiveRow({
    super.key,
    required this.subgoalId,
    required this.objective,
    required this.demonstrated,
  });

  final String subgoalId;
  final LearningObjective objective;

  /// Whether the LO carries the mastery stamp; `null` when that is not
  /// known (stamps loading or unreadable).
  final bool? demonstrated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final statement = ref
        .watch(localizedObjectiveOf(subgoalId, objective))
        .statement;
    final done = demonstrated ?? false;
    final status = switch (demonstrated) {
      true => l.leerpad_objective_demonstrated,
      false => l.leerpad_objective_notYetDemonstrated,
      null => null,
    };
    final detail = [
      ?status,
      if (objective.optional) l.leerpad_objective_optional,
    ].join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: done ? AppColors.accent2 : AppColors.fgFaint,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                statement,
                style: TextStyle(
                  color: AppColors.fg,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              if (detail.isNotEmpty)
                Text(
                  detail,
                  style: TextStyle(
                    color: done ? AppColors.accent2 : AppColors.fgMute,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
