import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class McqOptionsWidget extends ConsumerWidget {
  const McqOptionsWidget({super.key, required this.message});

  final CustomMessage message;

  static const _badges = ['A', 'B', 'C', 'D', 'E', 'F'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metadata = message.metadata ?? const {};
    final options = (metadata['options'] as List?)?.cast<String>() ?? const [];
    final selected = metadata['selected'] as String?;
    final answered = selected != null;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < options.length; i++) ...[
            _OptionButton(
              badge: i < _badges.length ? _badges[i] : '${i + 1}',
              label: options[i],
              isSelected: options[i] == selected,
              isDisabled: answered,
              onTap: () => _onTap(ref, options[i]),
            ),
            if (i < options.length - 1) const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ),
    );
  }

  void _onTap(WidgetRef ref, String picked) {
    if (ref.read(tutorServiceProvider) != TutorState.idle) return;
    final chat = ref.read(chatServiceProvider);
    chat.markMcqAnswered(message, picked);
    chat.addMessage(picked);
    ref.read(tutorServiceProvider.notifier).handleStudentMessage(picked);
  }
}

class _OptionButton extends StatefulWidget {
  const _OptionButton({
    required this.badge,
    required this.label,
    required this.isSelected,
    required this.isDisabled,
    required this.onTap,
  });

  final String badge;
  final String label;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback onTap;

  @override
  State<_OptionButton> createState() => _OptionButtonState();
}

class _OptionButtonState extends State<_OptionButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.isSelected;
    final dimmed = widget.isDisabled && !selected;

    final Color bg;
    final Color border;
    final Color textColor;
    final Color badgeBg;
    final Color badgeFg;

    if (selected) {
      bg = AppColors.accent.withValues(alpha: 0.18);
      border = AppColors.accent.withValues(alpha: 0.6);
      textColor = AppColors.accent;
      badgeBg = AppColors.accent;
      badgeFg = AppColors.ink0;
    } else if (dimmed) {
      bg = AppColors.ink1;
      border = AppColors.ink2;
      textColor = AppColors.fgFaint;
      badgeBg = AppColors.ink2;
      badgeFg = AppColors.fgFaint;
    } else {
      bg = _hovering ? AppColors.ink2 : AppColors.ink1;
      border = AppColors.ink2;
      textColor = AppColors.fg;
      badgeBg = AppColors.ink2;
      badgeFg = AppColors.fgMute;
    }

    return MouseRegion(
      cursor: widget.isDisabled
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.isDisabled ? null : widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppDurations.hover,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(AppRadius.cardLarge),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(AppRadius.inputSmall),
                ),
                child: Text(
                  widget.badge,
                  style: AppMono.code(color: badgeFg, size: 12)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Text(
                  widget.label,
                  style: AppMono.code(color: textColor, size: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
