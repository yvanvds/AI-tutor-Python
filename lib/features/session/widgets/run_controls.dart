import 'package:ai_tutor_python/features/reference/reference_panel_state.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/services/output/output_service.dart';
import 'package:ai_tutor_python/services/tutor/shown_question.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/first_that_fits.dart';
import 'package:ai_tutor_python/widgets/question_id_tag.dart';
import 'package:ai_tutor_python/widgets/submit_shortcut.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Strip above the editor: Run/Stop primary button, Reset (ghost), and on the
/// right the reference (#323), hint and send-to-tutor (all ghost). Used by Practice and Playground modes.
/// In Practice it is the header of the code exercise, and carries the
/// question's short ID (#216) as the quiz header does.
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
          // Run and Reset on the left, in what the right side leaves. When
          // that is short — a narrow window with the chat open — Run drops
          // its shortcut hint first (#304), which its tooltip keeps, and
          // then its play icon, so the word stays next to the question ID
          // and the reference button (#323) in a 700 px window.
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: output.isRunning,
                    builder: (context, running, _) => running
                        ? _StopButton(output: output)
                        : FirstThatFits(
                            children: [
                              _RunButton(ref: ref, mode: mode),
                              _RunButton(
                                ref: ref,
                                mode: mode,
                                showShortcut: false,
                              ),
                              _RunButton(
                                ref: ref,
                                mode: mode,
                                showShortcut: false,
                                showIcon: false,
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                GhostIconButton(
                  tooltip: l.session_runControls_tooltip_resetOutput,
                  icon: Icons.refresh_rounded,
                  onTap: output.clear,
                ),
              ],
            ),
          ),
          if (mode == SessionMode.practice) const _QuestionId(),
          const ReferenceButton(),
          const SizedBox(width: AppSpacing.xxs),
          GhostIconButton(
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
          GhostIconButton(
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

/// The short ID of the question in the editor (#216), when there is one.
class _QuestionId extends ConsumerWidget {
  const _QuestionId();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(shownQuestionIdProvider);
    if (id == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.m),
      child: QuestionIdTag(
        id,
        key: const Key('exercise-question-id'),
        tooltip: questionIdTooltip(context, ref),
      ),
    );
  }
}

/// Runs the code in the editor of [mode]: the Run button, and Ctrl+Enter in
/// the editor (#300). Like the button, which is Stop during a run, it does
/// nothing while a run is going.
Future<void> runEditorCode(WidgetRef ref, SessionMode mode) async {
  final output = ref.read(outputServiceProvider);
  if (output.isRunning.value) return;
  final code = ref.read(codeServiceProvider(mode)).getText();
  await output.run(code);
}

class _RunButton extends StatelessWidget {
  const _RunButton({
    required this.ref,
    required this.mode,
    this.showShortcut = true,
    this.showIcon = true,
  });
  final WidgetRef ref;
  final SessionMode mode;

  /// Whether the shortcut is spelled out on the button; without it, it is
  /// in the tooltip.
  final bool showShortcut;

  /// Whether the play icon goes before the word: the last thing the
  /// narrowest strip gives up (#323).
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final button = _PillButton(
      bg: AppColors.accent,
      fg: AppColors.ink0,
      onTap: () => runEditorCode(ref, mode),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(Icons.play_arrow_rounded, size: 16, color: AppColors.ink0),
            const SizedBox(width: 4),
          ],
          Text(
            AppLocalizations.of(context).session_runControls_button_run,
            style: TextStyle(
              color: AppColors.ink0,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (showShortcut) ...[
            const SizedBox(width: 6),
            Text(
              submitShortcutLabel(),
              key: const Key('run-shortcut-hint'),
              style: AppMono.kbd(color: AppColors.ink0).copyWith(fontSize: 11),
            ),
          ],
        ],
      ),
    );
    if (showShortcut) return button;
    return Tooltip(
      message: submitShortcutLabel(),
      waitDuration: const Duration(milliseconds: 400),
      child: button,
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

/// Opens and closes the reference panel (#323): above the editor, and in
/// the quiz header, where the row above the editor is not.
class ReferenceButton extends ConsumerWidget {
  const ReferenceButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GhostIconButton(
      tooltip: AppLocalizations.of(context).reference_button_tooltip,
      icon: Icons.menu_book_outlined,
      active: ref.watch(referencePanelOpenProvider),
      onTap: () => ref.read(referencePanelOpenProvider.notifier).toggle(),
    );
  }
}

/// A 32 px icon button without a background until hovered; [active] lights
/// it up while what it opens is open.
class GhostIconButton extends StatefulWidget {
  const GhostIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  State<GhostIconButton> createState() => _GhostIconButtonState();
}

class _GhostIconButtonState extends State<GhostIconButton> {
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
              color: _hovering || widget.active
                  ? AppColors.ink2
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.inputSmall),
            ),
            child: Icon(
              widget.icon,
              size: 18,
              color: widget.active
                  ? AppColors.accent
                  : (_hovering ? AppColors.fg : AppColors.fgMute),
            ),
          ),
        ),
      ),
    );
  }
}
