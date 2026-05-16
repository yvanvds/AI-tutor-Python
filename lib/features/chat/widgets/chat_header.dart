import 'package:ai_tutor_python/features/chat/widgets/tutor_avatar.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Top of the chat panel: tutor avatar + name + presence sub-line + restart.
class ChatHeader extends ConsumerWidget {
  const ChatHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topic = ref.watch(profileProvider).topic;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: AppColors.ink1,
        border: Border(bottom: BorderSide(color: AppColors.ink2, width: 1)),
      ),
      child: Row(
        children: [
          const TutorAvatar(showOnlineDot: true),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppLocalizations.of(context).chat_tutorName,
                  style: const TextStyle(
                    color: AppColors.fg,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                _PresenceLine(topic: topic),
              ],
            ),
          ),
          _RestartButton(
            onTap: () =>
                ref.read(tutorServiceProvider.notifier).initializeSession(force: true),
          ),
        ],
      ),
    );
  }
}

class _PresenceLine extends StatelessWidget {
  const _PresenceLine({required this.topic});
  final String topic;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: AppColors.accent2,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: RichText(
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: const TextStyle(
                color: AppColors.fgFaint,
                fontSize: 11.5,
                height: 1.3,
              ),
              children: [
                TextSpan(text: l.chat_header_presence_online),
                if (topic.isNotEmpty) ...[
                  TextSpan(text: l.chat_header_presence_helpsWith),
                  TextSpan(
                    text: topic,
                    style: AppMono.code(color: AppColors.fgMute, size: 11.5),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RestartButton extends StatefulWidget {
  const _RestartButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_RestartButton> createState() => _RestartButtonState();
}

class _RestartButtonState extends State<_RestartButton> {
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
        child: Tooltip(
          message: AppLocalizations.of(context).chat_header_restart_tooltip,
          waitDuration: const Duration(milliseconds: 400),
          child: AnimatedContainer(
            duration: AppDurations.hover,
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _hovering ? AppColors.ink2 : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.inputSmall),
            ),
            child: const Icon(
              Icons.refresh,
              size: 16,
              color: AppColors.fgMute,
            ),
          ),
        ),
      ),
    );
  }
}
