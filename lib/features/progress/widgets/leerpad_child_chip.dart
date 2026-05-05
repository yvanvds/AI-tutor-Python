import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';

/// Compact child-goal pill rendered inside an active root card. Two-line:
/// title + tnum percentage; check icon when complete.
class LeerpadChildChip extends StatelessWidget {
  const LeerpadChildChip({
    super.key,
    required this.goal,
    required this.progress,
  });

  final Goal goal;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final completed = progress >= 0.999;
    final pct = '${(progress.clamp(0.0, 1.0) * 100).round()}%';

    return Container(
      width: 180,
      padding: const EdgeInsets.all(AppSpacing.s),
      decoration: BoxDecoration(
        color: AppColors.ink1,
        border: Border.all(
          color: completed
              ? AppColors.accent2.withValues(alpha: 0.4)
              : AppColors.ink2,
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  goal.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.fg,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ),
              if (completed) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.check_circle,
                  size: 14,
                  color: AppColors.accent2,
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: SizedBox(
                    height: 4,
                    child: Stack(
                      children: [
                        Container(color: AppColors.ink2),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress.clamp(0.0, 1.0),
                          child: Container(
                            color: completed
                                ? AppColors.accent2
                                : AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                pct,
                style: AppMono.tnum(
                  size: 10.5,
                  weight: FontWeight.w500,
                  color: completed ? AppColors.accent2 : AppColors.fgFaint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
