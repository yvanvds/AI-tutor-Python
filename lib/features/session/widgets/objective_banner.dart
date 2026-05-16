import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Huidig doel" banner shown at the top of [PracticeView]. Renders nothing
/// when there is no active goal (e.g. before the conductor has selected one).
class ObjectiveBanner extends ConsumerWidget {
  const ObjectiveBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(goalSelectionProvider);
    final activeChildGoal = selection.activeChildGoal;
    final goal = activeChildGoal ?? selection.activeRootGoal;
    if (goal == null) return const SizedBox.shrink();

    final description = (goal.description ?? '').trim();
    final progress =
        activeChildGoal == null ? 0.0 : ref.watch(ambientProgressProvider).clamp(0.0, 1.0);
    final completed = progress >= 0.999;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.m,
      ),
      decoration: const BoxDecoration(
        color: AppColors.ink1,
        border: Border(
          bottom: BorderSide(color: AppColors.ink2, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  AppLocalizations.of(context)
                      .session_objectiveBanner_pill
                      .toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Text(
                  goal.title,
                  style: const TextStyle(
                    color: AppColors.fg,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              description,
              style: const TextStyle(
                color: AppColors.fgMute,
                fontSize: 12,
                height: 1.35,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (activeChildGoal != null) ...[
            const SizedBox(height: AppSpacing.s),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: SizedBox(
                height: 4,
                child: Stack(
                  children: [
                    Container(color: AppColors.ink2),
                    AnimatedFractionallySizedBox(
                      duration: AppDurations.progressFill,
                      curve: AppCurves.layout,
                      widthFactor: progress,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        color: completed ? AppColors.accent2 : AppColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
