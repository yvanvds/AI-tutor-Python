import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/services/output/output_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Strip above the editor: Run/Stop primary button, Reset (ghost), and on the
/// right hint + send-to-tutor (both ghost). Used by Practice and Playground modes.
class RunControls extends ConsumerWidget {
  const RunControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final output = ref.read(outputServiceProvider);
    final mode = ref.watch(modeProvider);
    final l = AppLocalizations.of(context);

    return Container(
      color: AppColors.ink1,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: output.isRunning,
            builder: (context, running, _) => running
                ? _StopButton(output: output)
                : _RunButton(ref: ref, mode: mode),
          ),
          const SizedBox(width: AppSpacing.s),
          _GhostIconButton(
            tooltip: l.session_runControls_tooltip_resetOutput,
            icon: Icons.refresh_rounded,
            onTap: output.clear,
          ),
          const Spacer(),
          _GhostIconButton(
            tooltip: l.session_runControls_tooltip_askHint,
            icon: Icons.lightbulb_outline,
            onTap: () async {
              ref
                  .read(chatServiceProvider)
                  .addMessage(l.session_runControls_chatMessage_needHint);
              final code = ref.read(codeServiceProvider(mode)).getText();
              await ref.read(tutorServiceProvider.notifier).requestHint(code);
            },
          ),
          const SizedBox(width: AppSpacing.xxs),
          _GhostIconButton(
            tooltip: l.session_runControls_tooltip_sendToTutor,
            icon: Icons.send_outlined,
            onTap: () async {
              ref
                  .read(chatServiceProvider)
                  .addMessage(l.session_runControls_chatMessage_hereIsCode);
              final code = ref.read(codeServiceProvider(mode)).getText();
              await ref.read(tutorServiceProvider.notifier).submitCode(code);
            },
          ),
        ],
      ),
    );
  }
}

class _RunButton extends StatelessWidget {
  const _RunButton({required this.ref, required this.mode});
  final WidgetRef ref;
  final SessionMode mode;

  @override
  Widget build(BuildContext context) {
    return _PillButton(
      bg: AppColors.accent,
      fg: AppColors.ink0,
      onTap: () async {
        final code = ref.read(codeServiceProvider(mode)).getText();
        await ref.read(outputServiceProvider).run(code);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_arrow_rounded, size: 16, color: AppColors.ink0),
          const SizedBox(width: 4),
          Text(
            AppLocalizations.of(context).session_runControls_button_run,
            style: TextStyle(
              color: AppColors.ink0,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '⌘↵',
            style: AppMono.kbd(color: AppColors.ink0).copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _StopButton extends StatelessWidget {
  const _StopButton({required this.output});
  final OutputService output;

  @override
  Widget build(BuildContext context) {
    return _PillButton(
      bg: AppColors.danger.withValues(alpha: 0.15),
      fg: AppColors.danger,
      borderColor: AppColors.danger.withValues(alpha: 0.6),
      onTap: output.stop,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.stop_rounded, size: 16, color: AppColors.danger),
          const SizedBox(width: 4),
          Text(
            AppLocalizations.of(context).session_runControls_button_stop,
            style: TextStyle(
              color: AppColors.danger,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatefulWidget {
  const _PillButton({
    required this.bg,
    required this.fg,
    required this.onTap,
    required this.child,
    this.borderColor,
  });

  final Color bg;
  final Color fg;
  final Color? borderColor;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
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
            color: _hovering
                ? Color.alphaBlend(
                    Colors.white.withValues(alpha: 0.05),
                    widget.bg,
                  )
                : widget.bg,
            border: widget.borderColor != null
                ? Border.all(color: widget.borderColor!)
                : null,
            borderRadius: BorderRadius.circular(AppRadius.inputLarge),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _GhostIconButton extends StatefulWidget {
  const _GhostIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_GhostIconButton> createState() => _GhostIconButtonState();
}

class _GhostIconButtonState extends State<_GhostIconButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppDurations.hover,
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _hovering ? AppColors.ink2 : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.inputSmall),
            ),
            child: Icon(
              widget.icon,
              size: 18,
              color: _hovering ? AppColors.fg : AppColors.fgMute,
            ),
          ),
        ),
      ),
    );
  }
}
