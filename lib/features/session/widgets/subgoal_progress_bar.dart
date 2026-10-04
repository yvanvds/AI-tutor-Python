import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/tutor/lo_display.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The active subgoal's bar in the objective banner (#230,
/// CONDUCTOR_POLICY §4.5): one [LoSegment] per non-optional LO, each empty,
/// half (one right answer away) or full (mastered or stuck), as the
/// conductor publishes them in [subgoalLoDisplayProvider]. A tooltip and the
/// screen-reader label say it in words, in the app language: "2 parts
/// mastered, 1 almost, 2 still to do".
///
/// Until the conductor has published the active subgoal's segments — and
/// for a subgoal without LOs — it is the plain bar of the cached share
/// ([ambientProgressProvider]).
class SubgoalProgressBar extends ConsumerWidget {
  const SubgoalProgressBar({super.key});

  /// Height of the bar itself; the hover and tap area around it is taller.
  static const double barHeight = 4;

  /// Space between two segments.
  static const double gap = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final display = ref.watch(activeSubgoalLoDisplayProvider);
    if (display == null || display.los.isEmpty) {
      return _hitArea(
        _PlainBar(progress: ref.watch(ambientProgressProvider).clamp(0.0, 1.0)),
      );
    }

    final label = AppLocalizations.of(context).session_objectiveBanner_segments(
      display.fullCount,
      display.halfCount,
      display.emptyCount,
    );
    final done = display.fullCount == display.los.length;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        container: true,
        label: label,
        child: ExcludeSemantics(
          child: _hitArea(
            Row(
              children: [
                for (var i = 0; i < display.los.length; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  Expanded(
                    child: LoSegment(
                      key: ValueKey('lo-segment-${display.los[i].loId}'),
                      state: display.los[i].state,
                      done: done,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The bar, centred in an area tall enough to hover for the tooltip.
  static Widget _hitArea(Widget bar) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
    child: SizedBox(height: barHeight, child: bar),
  );
}

/// One LO's segment of [SubgoalProgressBar]: empty, filled halfway or full.
/// [done] when every segment is full: the bar takes the "finished" colour,
/// like the plain bar did at 100%.
class LoSegment extends StatelessWidget {
  const LoSegment({super.key, required this.state, required this.done});

  final LoDisplayState state;
  final bool done;

  /// How much of the segment is filled.
  double get fill => switch (state) {
    LoDisplayState.empty => 0.0,
    LoDisplayState.half => 0.5,
    LoDisplayState.full => 1.0,
  };

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Stack(
        children: [
          Container(color: AppColors.ink2),
          AnimatedFractionallySizedBox(
            duration: AppDurations.progressFill,
            curve: AppCurves.layout,
            widthFactor: fill,
            alignment: Alignment.centerLeft,
            child: Container(
              color: done ? AppColors.accent2 : AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// The bar before #230: one fill of the cached share.
class _PlainBar extends StatelessWidget {
  const _PlainBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Stack(
        children: [
          Container(color: AppColors.ink2),
          AnimatedFractionallySizedBox(
            duration: AppDurations.progressFill,
            curve: AppCurves.layout,
            widthFactor: progress,
            alignment: Alignment.centerLeft,
            child: Container(
              color: progress >= 0.999 ? AppColors.accent2 : AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}
