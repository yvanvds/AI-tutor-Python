import 'package:ai_tutor_python/features/progress/widgets/leerpad_child_chip.dart';
import 'package:ai_tutor_python/features/progress/widgets/leerpad_objectives_panel.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:ai_tutor_python/services/student_state/mastery_stamps.dart';
import 'package:ai_tutor_python/services/translation/localized_text.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Single root goal card on the Leerpad. Active = tinted bg + accent border
/// + horizontal row of child chips + "Verder" CTA. Completed = check badge,
/// "voltooid" caption, and the same row of child chips (#243). Tapping a
/// chip opens the list of its learning objectives under the row, each
/// demonstrated or not yet. The root's title and description are in the app
/// language when there is a translation, else in Dutch (#210).
///
/// The bars count the mastery stamp the grade reads ([stamps], #243): a
/// chip's bar is its share of non-optional LOs with the stamp, the root's
/// the average over its non-optional subgoals. While [stamps] is `null`
/// (loading, or unreadable) a bar falls back on the cached `progress`, as
/// does a subgoal without non-optional LOs.
class LeerpadCard extends ConsumerStatefulWidget {
  const LeerpadCard({
    super.key,
    required this.index,
    required this.root,
    required this.children,
    required this.progressById,
    required this.isActive,
    required this.onContinue,
    this.stamps,
  });

  final int index;
  final Goal root;
  final List<Goal> children;
  final Map<String, Progress> progressById;
  final bool isActive;
  final VoidCallback onContinue;

  /// The student's mastery stamps; `null` while they load or when they
  /// could not be read.
  final MasteryStamps? stamps;

  @override
  ConsumerState<LeerpadCard> createState() => _LeerpadCardState();
}

class _LeerpadCardState extends ConsumerState<LeerpadCard> {
  /// The subgoal whose learning objectives are open under the chips.
  String? _openChildId;

  DemonstratedCount? _countOf(Goal child) {
    final count = widget.stamps?.countFor(child);
    return (count == null || count.total == 0) ? null : count;
  }

  double _barOf(Goal child) =>
      _countOf(child)?.fraction ??
      widget.progressById[child.id]?.progress ??
      0.0;

  void _toggle(String childId) =>
      setState(() => _openChildId = _openChildId == childId ? null : childId);

  @override
  Widget build(BuildContext context) {
    final root = widget.root;
    final children = widget.children;
    final progressById = widget.progressById;
    final isActive = widget.isActive;
    final shown = ref.watch(localizedGoalOf(root));
    final required = children.where((c) => !c.optional).toList();
    final progress = required.isEmpty
        ? 0.0
        : (required.map(_barOf).fold<double>(0, (a, b) => a + b) /
                  required.length)
              .clamp(0.0, 1.0);
    // Finished means every required subgoal was advanced past (#161); the
    // bar can sit below 100% when one of them advanced on a stuck LO.
    final completed =
        required.isNotEmpty &&
        required.every((c) => progressById[c.id]?.isAdvanced ?? false);
    final showChildren = (isActive || completed) && children.isNotEmpty;
    final open = showChildren
        ? children.where((c) => c.id == _openChildId).firstOrNull
        : null;

    final bg = isActive
        ? AppColors.accent.withValues(alpha: 0.06)
        : AppColors.ink1;
    final border = isActive
        ? AppColors.accent.withValues(alpha: 0.5)
        : AppColors.ink2;

    return AnimatedContainer(
      duration: AppDurations.modeFade,
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
      ),
      padding: const EdgeInsets.all(AppSpacing.lgPlus),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            index: widget.index,
            title: shown.title,
            description: shown.description,
            isActive: isActive,
            completed: completed,
          ),
          const SizedBox(height: AppSpacing.m),
          _ProgressRow(value: progress, completed: completed),
          if (showChildren) ...[
            const SizedBox(height: AppSpacing.lg),
            _ChildrenRow(
              children: children,
              progressById: progressById,
              barOf: _barOf,
              countOf: _countOf,
              openChildId: open?.id,
              onTap: _toggle,
            ),
            AnimatedSize(
              duration: AppDurations.modeFade,
              curve: AppCurves.layout,
              alignment: Alignment.topCenter,
              child: open == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.m),
                      child: LeerpadObjectivesPanel(
                        key: ValueKey(open.id),
                        subgoal: open,
                        stamps: widget.stamps,
                      ),
                    ),
            ),
          ],
          if (isActive) ...[
            const SizedBox(height: AppSpacing.lg),
            Align(
              alignment: Alignment.centerRight,
              child: _VerderButton(onTap: widget.onContinue),
            ),
          ],
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.index,
    required this.title,
    required this.description,
    required this.isActive,
    required this.completed,
  });

  final int index;
  final String title;
  final String? description;
  final bool isActive;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IndexBadge(index: index, isActive: isActive, completed: completed),
        const SizedBox(width: AppSpacing.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: AppColors.fg,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              if (description != null && description!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  description!,
                  style: TextStyle(
                    color: AppColors.fgMute,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _IndexBadge extends StatelessWidget {
  const _IndexBadge({
    required this.index,
    required this.isActive,
    required this.completed,
  });

  final int index;
  final bool isActive;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final Widget child;

    if (completed) {
      bg = AppColors.accent2;
      fg = AppColors.ink0;
      child = Icon(Icons.check, size: 16, color: AppColors.ink0);
    } else if (isActive) {
      bg = AppColors.accent;
      fg = AppColors.ink0;
      child = Text(
        '$index',
        style: AppMono.tnum(
          size: 13,
          weight: FontWeight.w700,
          color: AppColors.ink0,
        ),
      );
    } else {
      bg = AppColors.ink2;
      fg = AppColors.fgMute;
      child = Text(
        '$index',
        style: AppMono.tnum(size: 13, weight: FontWeight.w600, color: fg),
      );
    }

    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: child,
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.value, required this.completed});
  final double value;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final color = completed ? AppColors.accent2 : AppColors.accent;
    final label = completed
        ? AppLocalizations.of(context).leerpad_card_completed
        : '${(value * 100).round()}%';

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Container(color: AppColors.ink2),
                  AnimatedFractionallySizedBox(
                    duration: AppDurations.progressFill,
                    curve: AppCurves.layout,
                    alignment: Alignment.centerLeft,
                    widthFactor: value,
                    child: Container(color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.m),
        SizedBox(
          width: 70,
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: AppMono.tnum(
              size: 12,
              weight: FontWeight.w500,
              color: completed ? AppColors.accent2 : AppColors.fgMute,
            ),
          ),
        ),
      ],
    );
  }
}

class _ChildrenRow extends StatelessWidget {
  const _ChildrenRow({
    required this.children,
    required this.progressById,
    required this.barOf,
    required this.countOf,
    required this.openChildId,
    required this.onTap,
  });

  final List<Goal> children;
  final Map<String, Progress> progressById;
  final double Function(Goal) barOf;
  final DemonstratedCount? Function(Goal) countOf;
  final String? openChildId;
  final void Function(String childId) onTap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final c in children)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.s),
              child: LeerpadChildChip(
                goal: c,
                progress: barOf(c),
                completed: progressById[c.id]?.isAdvanced ?? false,
                demonstrated: countOf(c),
                selected: c.id == openChildId,
                onTap: c.objectives.isEmpty ? null : () => onTap(c.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _VerderButton extends StatefulWidget {
  const _VerderButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_VerderButton> createState() => _VerderButtonState();
}

class _VerderButtonState extends State<_VerderButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppDurations.hover,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.s,
          ),
          decoration: BoxDecoration(
            color: _hovering
                ? Color.alphaBlend(
                    Colors.white.withValues(alpha: 0.06),
                    AppColors.accent,
                  )
                : AppColors.accent,
            borderRadius: BorderRadius.circular(AppRadius.inputLarge),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalizations.of(context).leerpad_card_button_continue,
                style: TextStyle(
                  color: AppColors.ink0,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.arrow_forward, size: 14, color: AppColors.ink0),
            ],
          ),
        ),
      ),
    );
  }
}
