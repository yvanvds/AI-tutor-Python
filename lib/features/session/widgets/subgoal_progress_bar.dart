import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/translation/localized_text.dart';
import 'package:ai_tutor_python/services/tutor/lo_display.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The active subgoal's bar in the objective banner (#230, #325,
/// CONDUCTOR_POLICY §4.5): one [LoSegment] per non-optional LO, as the
/// conductor publishes them in [subgoalLoDisplayProvider]. Each segment
/// shows the right answers its LO still needs and fills along with that
/// number, carries a tick when the LO is demonstrated, and is framed when
/// the exercise on screen is about it; hovering or tapping one says it in
/// words. Hovering the bar between the segments, and the screen-reader
/// label, give the whole subgoal: "2 of 5 parts mastered, 6 more right
/// answers to go".
///
/// Until the conductor has published the active subgoal's segments — and
/// for a subgoal without LOs — it is the plain bar of the cached share
/// ([ambientProgressProvider]).
class SubgoalProgressBar extends ConsumerWidget {
  const SubgoalProgressBar({super.key});

  /// Height of the bar itself, tall enough for the number in a segment;
  /// the hover and tap area around it is taller.
  static const double barHeight = 14;

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

    final label = subgoalBarLabel(AppLocalizations.of(context), display);
    final objectives = {
      for (final lo
          in ref.watch(
                goalSelectionProvider.select(
                  (s) => s.activeChildGoal?.objectives,
                ),
              ) ??
              const <LearningObjective>[])
        lo.id: lo,
    };
    final done = display.masteredCount == display.los.length;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        container: true,
        label: label,
        child: _hitArea(
          Row(
            children: [
              for (var i = 0; i < display.los.length; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                Expanded(
                  child: LoSegment(
                    key: ValueKey('lo-segment-${display.los[i].loId}'),
                    subgoalId: display.subgoalId,
                    objective: objectives[display.los[i].loId],
                    entry: display.los[i],
                    current: display.currentLoId == display.los[i].loId,
                    done: done,
                  ),
                ),
              ],
            ],
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

/// The tooltip and screen-reader label of the whole bar (#325): how many
/// segments are mastered, and the right answers the others need together.
String subgoalBarLabel(AppLocalizations l, SubgoalLoDisplay display) {
  final total = display.los.length;
  final toGo = display.toGoTotal;
  return toGo == 0
      ? l.session_objectiveBanner_summary(display.masteredCount, total)
      : l.session_objectiveBanner_summaryToGo(
          display.masteredCount,
          total,
          toGo,
        );
}

/// What a segment's popup and screen-reader label say (#325), a line each:
/// the LO's "Je kan …" sentence ([statement], in the app language), its
/// state — the right answers to go, or mastered, and whether it is
/// demonstrated — why the number went up, when it did, and that the
/// exercise on screen is about it ([current]).
String loSegmentPopup(
  AppLocalizations l, {
  required String? statement,
  required LoDisplayEntry entry,
  bool current = false,
}) {
  final state = [
    entry.mastered ? l.session_lo_mastered : l.session_lo_toGo(entry.toGo),
    if (entry.demonstrated) l.leerpad_objective_demonstrated,
  ].join(' · ');
  return [
    if (statement != null && statement.trim().isNotEmpty) statement.trim(),
    state,
    if (entry.rose != null)
      switch (entry.rose!) {
        LoDisplayRise.notRight => l.session_lo_rose_notRight,
        LoDisplayRise.lowerLevel => l.session_lo_rose_lowerLevel,
        LoDisplayRise.otherQuestion => l.session_lo_rose_otherQuestion,
      },
    if (current) l.session_lo_current,
  ].join('\n');
}

/// One LO's segment of [SubgoalProgressBar] (#325): the right answers it
/// still needs as a number, filled along with that number
/// ([LoDisplayEntry.fill]: full at 0), a tick while it carries the mastery
/// stamp — also when the fill drops — and a frame when it is [current], the
/// LO of the exercise on screen. Hovering or tapping it opens its popup
/// ([loSegmentPopup]). [done] when every segment is mastered: the fill
/// takes the "finished" colour, like the plain bar did at 100%.
class LoSegment extends ConsumerWidget {
  const LoSegment({
    super.key,
    required this.subgoalId,
    required this.objective,
    required this.entry,
    this.current = false,
    this.done = false,
  });

  final String subgoalId;

  /// The LO, for its sentence; `null` when the subgoal no longer has it.
  final LearningObjective? objective;
  final LoDisplayEntry entry;
  final bool current;
  final bool done;

  /// Width of the frame around the [current] segment.
  static const double frameWidth = 1.5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lo = objective;
    final statement = lo == null
        ? null
        : ref.watch(localizedObjectiveOf(subgoalId, lo)).statement;
    final popup = loSegmentPopup(
      AppLocalizations.of(context),
      statement: statement,
      entry: entry,
      current: current,
    );
    return Tooltip(
      message: popup,
      excludeFromSemantics: true,
      triggerMode: TooltipTriggerMode.tap,
      constraints: const BoxConstraints(maxWidth: 320),
      child: Semantics(
        container: true,
        label: popup,
        child: ExcludeSemantics(
          child: _SegmentBody(entry: entry, current: current, done: done),
        ),
      ),
    );
  }
}

class _SegmentBody extends StatelessWidget {
  const _SegmentBody({
    required this.entry,
    required this.current,
    required this.done,
  });

  final LoDisplayEntry entry;
  final bool current;
  final bool done;

  /// The number and the tick in [number] and [tick]: drawn once over the
  /// empty part and once over the fill, clipped to it, so they read on both.
  Widget _content(Color number, Color tick) =>
      entry.mastered && !entry.demonstrated
      ? const SizedBox.shrink()
      : Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!entry.mastered)
                  Text(
                    '${entry.toGo}',
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: number,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                if (!entry.mastered && entry.demonstrated)
                  const SizedBox(width: 2),
                if (entry.demonstrated)
                  Icon(Icons.check_rounded, size: 11, color: tick),
              ],
            ),
          ),
        );

  @override
  Widget build(BuildContext context) {
    final fillColor = done ? AppColors.accent2 : AppColors.accent;
    final radius = BorderRadius.circular(AppRadius.pill);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: entry.fill),
      duration: AppDurations.progressFill,
      curve: AppCurves.layout,
      builder: (context, fill, _) => Container(
        foregroundDecoration: current
            ? BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: AppColors.fg,
                  width: LoSegment.frameWidth,
                ),
              )
            : null,
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: AppColors.ink2),
              _content(AppColors.fgMute, AppColors.accent2),
              ClipRect(
                clipper: _LeftShare(fill),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: fillColor),
                    _content(AppColors.ink0, AppColors.ink0),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Clips to the left [share] of the box.
class _LeftShare extends CustomClipper<Rect> {
  const _LeftShare(this.share);

  final double share;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * share.clamp(0.0, 1.0), size.height);

  @override
  bool shouldReclip(_LeftShare oldClipper) => oldClipper.share != share;
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
