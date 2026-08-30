import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double topBarHeight = 64;

class TopBar extends ConsumerWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(sectionProvider);
    final inSession = section == Section.session;

    return SizedBox(
      height: topBarHeight,
      child: Stack(
        children: [
          // Body row
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.ink0,
                border: Border(
                  bottom: BorderSide(color: AppColors.ink2, width: 1),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
              child: Row(
                children: [
                  const Expanded(child: _Greeting()),
                  AnimatedOpacity(
                    duration: AppDurations.modeFade,
                    opacity: inSession ? 1.0 : 0.0,
                    child: IgnorePointer(
                      ignoring: !inSession,
                      child: const ModeSwitcher(),
                    ),
                  ),
                  const Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: StatStrip(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 2px ambient progress line at the very top edge
          const Positioned(top: 0, left: 0, right: 0, child: AmbientProgress()),
        ],
      ),
    );
  }
}

class _Greeting extends ConsumerWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final section = ref.watch(sectionProvider);
    final l = AppLocalizations.of(context);

    final subline = section == Section.session
        ? (profile.topic.isEmpty
              ? l.topBar_subline_default
              : l.topBar_subline_withTopic(profile.topic))
        : section.label(context);

    final name = profile.name.isEmpty ? '...' : profile.name;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.topBar_greeting(name),
          style: const TextStyle(
            color: AppColors.fg,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        Text(
          subline,
          style: const TextStyle(
            color: AppColors.fgMute,
            fontSize: 12.5,
            fontWeight: FontWeight.w400,
            height: 1.3,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class ModeSwitcher extends ConsumerWidget {
  const ModeSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(modeProvider);

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.ink1,
        border: Border.all(color: AppColors.ink2),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in SessionMode.values)
            _ModeButton(
              mode: m,
              active: m == mode,
              onTap: () => ref.read(modeProvider.notifier).state = m,
            ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatefulWidget {
  const _ModeButton({
    required this.mode,
    required this.active,
    required this.onTap,
  });

  final SessionMode mode;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_ModeButton> createState() => _ModeButtonState();
}

class _ModeButtonState extends State<_ModeButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.active
        ? AppColors.ink3
        : (_hovering ? AppColors.ink2 : Colors.transparent);
    final fg = widget.active ? AppColors.fg : AppColors.fgMute;

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
            horizontal: AppSpacing.m,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            widget.mode.label(context),
            style: TextStyle(
              color: fg,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class StatStrip extends ConsumerWidget {
  const StatStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StreakChip(streak: p.streak),
        const SizedBox(width: AppSpacing.s),
        _XpPill(level: p.level, xp: p.xp, xpNext: p.xpNext),
      ],
    );
  }
}

class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.streak});
  final int streak;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.ink1,
        border: Border.all(color: AppColors.ink2),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department_outlined,
            size: 14,
            color: AppColors.accent,
          ),
          const SizedBox(width: 4),
          Text('$streak', style: AppMono.tnum(size: 12.5, color: AppColors.fg)),
          const SizedBox(width: 4),
          Text(
            AppLocalizations.of(context).topBar_streak_days,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.fgMute,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _XpPill extends StatelessWidget {
  const _XpPill({required this.level, required this.xp, required this.xpNext});

  final int level;
  final int xp;
  final int xpNext;

  @override
  Widget build(BuildContext context) {
    final fraction = xpNext <= 0 ? 0.0 : (xp / xpNext).clamp(0.0, 1.0);
    return Container(
      width: 152,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.ink1,
        border: Border.all(color: AppColors.ink2),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                AppLocalizations.of(context).topBar_xp_level(level),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.fg,
                ),
              ),
              const Spacer(),
              Text(
                '$xp / $xpNext',
                style: AppMono.tnum(
                  size: 10.5,
                  weight: FontWeight.w500,
                  color: AppColors.fgMute,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 3,
              child: Stack(
                children: [
                  Container(color: AppColors.ink2),
                  AnimatedFractionallySizedBox(
                    duration: AppDurations.progressFill,
                    curve: AppCurves.layout,
                    widthFactor: fraction,
                    alignment: Alignment.centerLeft,
                    child: Container(color: AppColors.accent),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AmbientProgress extends ConsumerWidget {
  const AmbientProgress({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(ambientProgressProvider).clamp(0.0, 1.0);
    return SizedBox(
      height: 2,
      child: Stack(
        children: [
          Container(color: AppColors.ink2),
          AnimatedFractionallySizedBox(
            duration: AppDurations.progressFill,
            curve: AppCurves.layout,
            widthFactor: progress,
            alignment: Alignment.centerLeft,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.accent, AppColors.accent2],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
