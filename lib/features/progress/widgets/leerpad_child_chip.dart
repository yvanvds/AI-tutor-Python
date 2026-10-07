import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/student_state/mastery_stamps.dart';
import 'package:ai_tutor_python/services/translation/localized_text.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Compact subgoal tile in a root card on the Leerpad: the title, a check
/// mark when the conductor has moved the student past it, a bar, and under
/// it how many of its learning objectives are demonstrated — "3 van 4
/// aangetoond" (#243). Tapping it opens the list of those objectives in the
/// card ([onTap]). The title is in the app language when there is a
/// translation, else in Dutch (#210).
class LeerpadChildChip extends ConsumerWidget {
  const LeerpadChildChip({
    super.key,
    required this.goal,
    required this.progress,
    required this.completed,
    this.demonstrated,
    this.selected = false,
    this.onTap,
  });

  final Goal goal;

  /// The bar: [DemonstratedCount.fraction] of [demonstrated] — the share of
  /// non-optional LOs with the mastery stamp the grade reads (#243). Stays
  /// below 1.0 after a stuck-advance (#161), check mark or not.
  final double progress;

  /// `Progress.isAdvanced`: the subgoal was advanced past. Drives the check
  /// mark and the colour, never the bar's length.
  final bool completed;

  /// "x van y aangetoond"; `null` while the stamps load or when they could
  /// not be read, or when the subgoal has no non-optional LOs: no line then.
  final DemonstratedCount? demonstrated;

  /// Its list of objectives is open in the card.
  final bool selected;

  /// Opens or closes the list of objectives; `null` when there is none.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = ref.watch(localizedGoalOf(goal)).title;
    final count = demonstrated;
    final value = progress.clamp(0.0, 1.0);
    final tap = onTap;

    final Color borderColor;
    if (selected) {
      borderColor = AppColors.accent.withValues(alpha: 0.6);
    } else if (completed) {
      borderColor = AppColors.accent2.withValues(alpha: 0.4);
    } else {
      borderColor = AppColors.ink2;
    }

    final tile = Container(
      width: 180,
      padding: const EdgeInsets.all(AppSpacing.s),
      decoration: BoxDecoration(
        color: AppColors.ink1,
        border: Border.all(color: borderColor),
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
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.fg,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ),
              if (completed) ...[
                const SizedBox(width: 4),
                Icon(Icons.check_circle, size: 14, color: AppColors.accent2),
              ],
              if (tap != null) ...[
                const SizedBox(width: 2),
                Icon(
                  selected ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: AppColors.fgFaint,
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: SizedBox(
              height: 4,
              child: Stack(
                children: [
                  Container(color: AppColors.ink2),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: value,
                    child: Container(
                      color: completed ? AppColors.accent2 : AppColors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (count != null) ...[
            const SizedBox(height: 5),
            Text(
              AppLocalizations.of(context)
                  .leerpad_child_demonstrated(count.demonstrated, count.total),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // Green only when every one is demonstrated: a finished
              // subgoal with an open LO must not read as all done.
              style: AppMono.tnum(
                size: 10.5,
                weight: FontWeight.w500,
                color: count.demonstrated >= count.total
                    ? AppColors.accent2
                    : AppColors.fgMute,
              ),
            ),
          ],
        ],
      ),
    );

    if (tap == null) return tile;
    return Semantics(
      button: true,
      selected: selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: tap,
          behavior: HitTestBehavior.opaque,
          child: tile,
        ),
      ),
    );
  }
}
