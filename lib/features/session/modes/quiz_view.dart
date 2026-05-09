import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/code_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/tutor_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// MCQ render — full-bleed multiple-choice presentation, lifted from the
/// old top-level Quiz mode. `PracticeView` mounts this whenever
/// `activeMcqProvider` is non-null. The layout (header pill, code card,
/// option grid, feedback area) is preserved from the original sketch; the
/// data is now live from the tutor flow.
class QuizView extends ConsumerWidget {
  const QuizView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mcq = ref.watch(activeMcqProvider);
    if (mcq == null) return const SizedBox.shrink();
    final tutorState = ref.watch(tutorServiceProvider);

    return Container(
      color: AppColors.ink0,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxxl,
          vertical: AppSpacing.xxl,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _QuizHeader(),
                const SizedBox(height: AppSpacing.xl),
                TutorMarkdown(
                  mcq.prompt,
                  style: const TextStyle(
                    color: AppColors.fg,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    letterSpacing: -0.2,
                  ),
                ),
                if (mcq.code.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _CodeCard(code: mcq.code),
                ],
                const SizedBox(height: AppSpacing.lg),
                _OptionGrid(
                  options: mcq.options,
                  selected: mcq.selected,
                  feedbackQuality: mcq.feedbackQuality,
                  onPick: (option) => ref
                      .read(tutorServiceProvider.notifier)
                      .submitMcqAnswer(option),
                ),
                if (mcq.hasFeedback) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _FeedbackPanel(
                    text: mcq.feedback!,
                    quality: mcq.feedbackQuality,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _AdvanceButton(
                    enabled: tutorState == TutorState.idle,
                    onTap: () => ref
                        .read(tutorServiceProvider.notifier)
                        .advanceFromMcq(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuizHeader extends StatelessWidget {
  const _QuizHeader();

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
          child: const Text(
            'QUIZVRAAG',
            style: TextStyle(
              color: AppColors.accent,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ],
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.ink1,
        border: Border.all(color: AppColors.ink2),
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
      ),
      child: HighlightView(
        code,
        language: 'python',
        theme: tutorCodeTheme,
        textStyle: AppMono.code(),
      ),
    );
  }
}

class _OptionGrid extends StatelessWidget {
  const _OptionGrid({
    required this.options,
    required this.selected,
    required this.feedbackQuality,
    required this.onPick,
  });

  final List<String> options;
  final String? selected;
  final AnswerQuality? feedbackQuality;
  final void Function(String) onPick;

  static const _badges = ['A', 'B', 'C', 'D', 'E', 'F'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < options.length; i += 2) ...[
          if (i > 0) const SizedBox(height: AppSpacing.m),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildOption(i)),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: i + 1 < options.length
                      ? _buildOption(i + 1)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOption(int i) {
    return _Option(
      badge: i < _badges.length ? _badges[i] : '${i + 1}',
      label: options[i],
      state: _stateFor(options[i]),
      onTap: () => onPick(options[i]),
    );
  }

  _OptionState _stateFor(String option) {
    if (selected == null) return _OptionState.idle;
    final isThisSelected = option == selected;
    if (!isThisSelected) return _OptionState.dismissed;
    // Selected. Visual depends on feedback (if any yet).
    switch (feedbackQuality) {
      case null:
        return _OptionState.selectedPending;
      case AnswerQuality.correct:
      case AnswerQuality.partial:
        return _OptionState.correctChosen;
      case AnswerQuality.wrong:
        return _OptionState.wrongChosen;
    }
  }
}

enum _OptionState { idle, selectedPending, correctChosen, wrongChosen, dismissed }

class _Option extends StatefulWidget {
  const _Option({
    required this.badge,
    required this.label,
    required this.state,
    required this.onTap,
  });

  final String badge;
  final String label;
  final _OptionState state;
  final VoidCallback onTap;

  @override
  State<_Option> createState() => _OptionRowState();
}

class _OptionRowState extends State<_Option> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final visuals = _visualsFor(widget.state, _hovering);
    final disabled = widget.state != _OptionState.idle;

    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: disabled ? null : widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppDurations.hover,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.m,
            vertical: AppSpacing.s,
          ),
          decoration: BoxDecoration(
            color: visuals.bg,
            border: Border.all(color: visuals.border),
            borderRadius: BorderRadius.circular(AppRadius.cardLarge),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: visuals.badgeBg,
                  borderRadius: BorderRadius.circular(AppRadius.inputSmall),
                ),
                child: Text(
                  widget.badge,
                  style: AppMono.code(color: visuals.badgeFg, size: 13)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: Text(
                  widget.label,
                  style: AppMono.code(color: visuals.fg, size: 13.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _OptionVisuals _visualsFor(_OptionState state, bool hovering) {
    switch (state) {
      case _OptionState.idle:
        final bg = hovering ? AppColors.ink2 : AppColors.ink1;
        return _OptionVisuals(
          bg: bg,
          border: AppColors.ink2,
          fg: AppColors.fg,
          badgeBg: AppColors.ink2,
          badgeFg: AppColors.fgMute,
        );
      case _OptionState.selectedPending:
        return _OptionVisuals(
          bg: AppColors.accent.withValues(alpha: 0.18),
          border: AppColors.accent.withValues(alpha: 0.6),
          fg: AppColors.accent,
          badgeBg: AppColors.accent,
          badgeFg: AppColors.ink0,
        );
      case _OptionState.correctChosen:
        return _OptionVisuals(
          bg: AppColors.accent2.withValues(alpha: 0.18),
          border: AppColors.accent2.withValues(alpha: 0.6),
          fg: AppColors.accent2,
          badgeBg: AppColors.accent2,
          badgeFg: AppColors.ink0,
        );
      case _OptionState.wrongChosen:
        return _OptionVisuals(
          bg: AppColors.danger.withValues(alpha: 0.18),
          border: AppColors.danger.withValues(alpha: 0.6),
          fg: AppColors.danger,
          badgeBg: AppColors.danger,
          badgeFg: AppColors.ink0,
        );
      case _OptionState.dismissed:
        return _OptionVisuals(
          bg: AppColors.ink1,
          border: AppColors.ink2,
          fg: AppColors.fgFaint,
          badgeBg: AppColors.ink2,
          badgeFg: AppColors.fgFaint,
        );
    }
  }
}

class _OptionVisuals {
  const _OptionVisuals({
    required this.bg,
    required this.border,
    required this.fg,
    required this.badgeBg,
    required this.badgeFg,
  });

  final Color bg;
  final Color border;
  final Color fg;
  final Color badgeBg;
  final Color badgeFg;
}

class _FeedbackPanel extends StatelessWidget {
  const _FeedbackPanel({required this.text, required this.quality});

  final String text;
  final AnswerQuality? quality;

  @override
  Widget build(BuildContext context) {
    final accent = switch (quality) {
      AnswerQuality.correct || AnswerQuality.partial => AppColors.accent2,
      AnswerQuality.wrong => AppColors.danger,
      null => AppColors.accent,
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
      ),
      child: TutorMarkdown(
        text,
        style: const TextStyle(
          color: AppColors.fg,
          fontSize: 14,
          height: 1.5,
        ),
      ),
    );
  }
}

class _AdvanceButton extends StatefulWidget {
  const _AdvanceButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_AdvanceButton> createState() => _AdvanceButtonState();
}

class _AdvanceButtonState extends State<_AdvanceButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final bg = enabled
        ? (_hovering ? AppColors.accent2 : AppColors.accent)
        : AppColors.ink2;
    final fg = enabled ? AppColors.ink0 : AppColors.fgMute;

    return Align(
      alignment: Alignment.centerRight,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: enabled ? widget.onTap : null,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppDurations.hover,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.s,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              'Volgende →',
              style: TextStyle(
                color: fg,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
