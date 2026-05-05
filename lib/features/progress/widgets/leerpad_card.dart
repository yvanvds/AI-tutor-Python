import 'package:ai_tutor_python/features/progress/widgets/leerpad_child_chip.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';

/// Single root goal card on the Leerpad. Active = tinted bg + accent border
/// + horizontal row of child chips + "Verder" CTA. Completed = check badge,
/// "voltooid" caption.
class LeerpadCard extends StatelessWidget {
  const LeerpadCard({
    super.key,
    required this.index,
    required this.root,
    required this.children,
    required this.progressById,
    required this.isActive,
    required this.onContinue,
  });

  final int index;
  final Goal root;
  final List<Goal> children;
  final Map<String, Progress> progressById;
  final bool isActive;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final required = children.where((c) => !c.optional).toList();
    final progress = required.isEmpty
        ? 0.0
        : (required
                    .map((c) => progressById[c.id]?.progress ?? 0)
                    .fold<double>(0, (a, b) => a + b) /
                required.length)
            .clamp(0.0, 1.0);
    final completed = required.isNotEmpty && progress >= 0.999;

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
            index: index,
            title: root.title,
            description: root.description,
            isActive: isActive,
            completed: completed,
          ),
          const SizedBox(height: AppSpacing.m),
          _ProgressRow(value: progress, completed: completed),
          if (isActive && children.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _ChildrenRow(children: children, progressById: progressById),
          ],
          if (isActive) ...[
            const SizedBox(height: AppSpacing.lg),
            Align(
              alignment: Alignment.centerRight,
              child: _VerderButton(onTap: onContinue),
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
                style: const TextStyle(
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
                  style: const TextStyle(
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
      child = const Icon(Icons.check, size: 16, color: AppColors.ink0);
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
    final label = completed ? 'voltooid' : '${(value * 100).round()}%';

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
  const _ChildrenRow({required this.children, required this.progressById});

  final List<Goal> children;
  final Map<String, Progress> progressById;

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
                progress: progressById[c.id]?.progress ?? 0.0,
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
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Verder',
                style: TextStyle(
                  color: AppColors.ink0,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(width: 6),
              Icon(Icons.arrow_forward, size: 14, color: AppColors.ink0),
            ],
          ),
        ),
      ),
    );
  }
}
