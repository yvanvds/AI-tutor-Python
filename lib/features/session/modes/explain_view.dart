import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Uitleg — read-and-understand layout. Renders a single explanatory concept
/// as a scrollable canvas with a header, a "Hoe Python eraan denkt" card, an
/// info callout, and a footer.
///
/// Phase 3 ships with a hard-coded elif-ladder example matching the prototype.
/// Future work: lift the content to a data source (e.g. `instructions_service`)
/// and walk the curriculum tree.
class ExplainView extends ConsumerWidget {
  const ExplainView({super.key});

  static const _maxWidth = 680.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: AppColors.ink0,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxxl,
          vertical: AppSpacing.xxl,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(pill: 'Concept', current: 2, total: 4),
                SizedBox(height: AppSpacing.lg),
                _Title(),
                SizedBox(height: AppSpacing.xl),
                _ElifLadderCard(),
                SizedBox(height: AppSpacing.lg),
                _ImportantCallout(),
                SizedBox(height: AppSpacing.xxl),
                _Footer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.pill, required this.current, required this.total});
  final String pill;
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            pill.toUpperCase(),
            style: const TextStyle(
              color: AppColors.accent,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
        ),
        const Spacer(),
        Text(
          '$current / $total',
          style: AppMono.tnum(
            size: 12,
            weight: FontWeight.w500,
            color: AppColors.fgFaint,
          ),
        ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: AppColors.fg,
          fontSize: 30,
          fontWeight: FontWeight.w700,
          height: 1.15,
          letterSpacing: -0.4,
        ),
        children: [
          const TextSpan(text: 'De '),
          TextSpan(
            text: 'elif',
            style: AppMono.code(color: AppColors.accent, size: 26)
                .copyWith(fontWeight: FontWeight.w600),
          ),
          const TextSpan(text: '-ladder: één keuze tegelijk'),
        ],
      ),
    );
  }
}

class _ElifLadderCard extends StatelessWidget {
  const _ElifLadderCard();

  static const _steps = [
    _LadderStep(1, 'als score >= 90', '"A"'),
    _LadderStep(2, 'als score >= 75', '"B"'),
    _LadderStep(3, 'als score >= 60', '"C"'),
    _LadderStep(4, 'anders', '"D"'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.ink1,
        border: Border.all(color: AppColors.ink2),
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lgPlus,
              AppSpacing.md,
              AppSpacing.lgPlus,
              AppSpacing.s,
            ),
            child: const Text(
              'Hoe Python eraan denkt',
              style: TextStyle(
                color: AppColors.fg,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (var i = 0; i < _steps.length; i++) ...[
            if (i > 0) const _DashedDivider(),
            _LadderRow(step: _steps[i]),
          ],
        ],
      ),
    );
  }
}

class _LadderStep {
  const _LadderStep(this.index, this.condition, this.output);
  final int index;
  final String condition;
  final String output;
}

class _LadderRow extends StatelessWidget {
  const _LadderRow({required this.step});
  final _LadderStep step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lgPlus,
        vertical: AppSpacing.m,
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.ink2,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${step.index}',
              style: AppMono.tnum(
                size: 11,
                weight: FontWeight.w600,
                color: AppColors.fgMute,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Text(
              step.condition,
              style: AppMono.code(color: AppColors.fg, size: 13),
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          const Icon(Icons.arrow_forward, size: 14, color: AppColors.fgFaint),
          const SizedBox(width: AppSpacing.s),
          Text(
            step.output,
            style: AppMono.code(color: AppColors.syntaxStr, size: 13),
          ),
        ],
      ),
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lgPlus),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const dashWidth = 4.0;
          const dashSpace = 4.0;
          final count =
              (constraints.maxWidth / (dashWidth + dashSpace)).floor();
          return ClipRect(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(count, (_) {
                return const SizedBox(
                  width: dashWidth + dashSpace,
                  height: 1,
                  child: Padding(
                    padding: EdgeInsets.only(right: dashSpace),
                    child: ColoredBox(color: AppColors.ink2),
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }
}

class _ImportantCallout extends StatelessWidget {
  const _ImportantCallout();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.accent3.withValues(alpha: 0.1),
        border: Border.all(color: AppColors.accent3.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            size: 16,
            color: AppColors.accent3,
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: RichText(
              text: const TextSpan(
                style: TextStyle(
                  color: AppColors.fg,
                  fontSize: 13,
                  height: 1.5,
                ),
                children: [
                  TextSpan(
                    text: 'Belangrijk. ',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text:
                        'Python checkt de regels van boven naar beneden en stopt zodra er één klopt. '
                        'Zet daarom de strengste voorwaarde bovenaan.',
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

class _Footer extends ConsumerWidget {
  const _Footer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        _GhostButton(
          label: 'Vorige',
          icon: Icons.arrow_back,
          onTap: () {},
        ),
        const Spacer(),
        const Text(
          '+10 XP bij voltooien',
          style: TextStyle(
            color: AppColors.fgFaint,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: AppSpacing.m),
        _AccentButton(
          label: 'Probeer het zelf',
          onTap: () =>
              ref.read(modeProvider.notifier).state = SessionMode.practice,
        ),
      ],
    );
  }
}

class _GhostButton extends StatefulWidget {
  const _GhostButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<_GhostButton> {
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
            horizontal: AppSpacing.m,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: _hovering ? AppColors.ink2 : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.inputLarge),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: AppColors.fgMute),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: const TextStyle(
                  color: AppColors.fgMute,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccentButton extends StatefulWidget {
  const _AccentButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_AccentButton> createState() => _AccentButtonState();
}

class _AccentButtonState extends State<_AccentButton> {
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
                widget.label,
                style: const TextStyle(
                  color: AppColors.ink0,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.arrow_forward,
                size: 14,
                color: AppColors.ink0,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
