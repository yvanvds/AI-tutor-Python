import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/code_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';

/// Quiz mode — full-bleed multiple-choice presentation.
///
/// Phase 3 ships with hard-coded sample content so the layout, progress
/// segments, and answer feedback (correct → accent-2, wrong → danger) can be
/// validated. Wiring to the live MCQ flow (the `mcq_options` custom message
/// in `chat_service`) is a follow-up: read the active MCQ message's
/// `metadata['options']` here and reuse the chat path's
/// `markMcqAnswered` + `addMessage` + `tutorService.handleStudentMessage`.
class QuizView extends StatefulWidget {
  const QuizView({super.key});

  @override
  State<QuizView> createState() => _QuizViewState();
}

class _QuizViewState extends State<QuizView> {
  static const _total = 5;
  static const _current = 3;

  static const _correct = [true, true, false]; // questions 1..3 - 3 in flight

  static const _question = 'Wat zal Python printen?';
  static const _code = '''score = 78
if score >= 90:
    print("A")
elif score >= 75:
    print("B")
elif score >= 60:
    print("C")
else:
    print("D")''';
  static const _options = ['"A"', '"B"', '"C"', '"D"'];
  static const _correctAnswer = '"B"';

  String? _selected;

  void _pick(String option) {
    if (_selected != null) return;
    setState(() => _selected = option);
  }

  @override
  Widget build(BuildContext context) {
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
                _QuizHeader(
                  current: _current,
                  total: _total,
                  history: _correct,
                ),
                const SizedBox(height: AppSpacing.xl),
                const Text(
                  _question,
                  style: TextStyle(
                    color: AppColors.fg,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const _CodeCard(code: _code),
                const SizedBox(height: AppSpacing.lg),
                _OptionGrid(
                  options: _options,
                  selected: _selected,
                  correct: _correctAnswer,
                  onPick: _pick,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuizHeader extends StatelessWidget {
  const _QuizHeader({
    required this.current,
    required this.total,
    required this.history,
  });

  final int current;
  final int total;
  final List<bool> history;

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
            'QUIZ VRAAG $current / $total',
            style: const TextStyle(
              color: AppColors.accent,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
        ),
        const Spacer(),
        _ProgressSegments(
          current: current,
          total: total,
          history: history,
        ),
      ],
    );
  }
}

class _ProgressSegments extends StatelessWidget {
  const _ProgressSegments({
    required this.current,
    required this.total,
    required this.history,
  });

  final int current;
  final int total;
  final List<bool> history;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (i) {
        final n = i + 1;
        final Color color;
        if (n < current) {
          final ok = i < history.length ? history[i] : true;
          color = ok ? AppColors.accent2 : AppColors.danger;
        } else if (n == current) {
          color = AppColors.accent;
        } else {
          color = AppColors.ink2;
        }
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Container(
            width: 22,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
        );
      }),
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
    required this.correct,
    required this.onPick,
  });

  final List<String> options;
  final String? selected;
  final String correct;
  final void Function(String) onPick;

  static const _badges = ['A', 'B', 'C', 'D', 'E', 'F'];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.m,
      crossAxisSpacing: AppSpacing.m,
      childAspectRatio: 4.4,
      children: [
        for (var i = 0; i < options.length; i++)
          _Option(
            badge: i < _badges.length ? _badges[i] : '${i + 1}',
            label: options[i],
            state: _stateFor(options[i]),
            onTap: () => onPick(options[i]),
          ),
      ],
    );
  }

  _OptionState _stateFor(String option) {
    if (selected == null) return _OptionState.idle;
    final isThisCorrect = option == correct;
    final isThisSelected = option == selected;
    if (isThisSelected && isThisCorrect) return _OptionState.correctChosen;
    if (isThisSelected && !isThisCorrect) return _OptionState.wrongChosen;
    if (!isThisSelected && isThisCorrect) return _OptionState.correctReveal;
    return _OptionState.dismissed;
  }
}

enum _OptionState { idle, correctChosen, wrongChosen, correctReveal, dismissed }

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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
      case _OptionState.correctChosen:
      case _OptionState.correctReveal:
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
