import 'package:ai_tutor_python/features/chat/widgets/composer_chrome.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Idle composer: multi-line TextField, accent send button when populated,
/// `Cmd/Ctrl + Enter` to send, plain `Enter` inserts a newline. Sending a
/// solo `?` is shorthand for "give me a hint".
class ComposerIdle extends ConsumerStatefulWidget {
  const ComposerIdle({super.key});

  @override
  ConsumerState<ComposerIdle> createState() => _ComposerIdleState();
}

class _ComposerIdleState extends ConsumerState<ComposerIdle> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    final has = _controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final chat = ref.read(chatServiceProvider);
    final tutor = ref.read(tutorServiceProvider.notifier);
    _controller.clear();

    if (text == '?') {
      final code = ref.read(codeServiceProvider(SessionMode.practice)).getText();
      chat.addMessage(
        AppLocalizations.of(context).chat_composer_idle_hintMessage,
      );
      await tutor.requestHint(code);
      return;
    }

    chat.addMessage(text);
    await tutor.handleStudentMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    return ComposerChrome(
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): _send,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _send,
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Field(
              controller: _controller,
              focusNode: _focus,
              hasText: _hasText,
              onSend: _send,
            ),
            const SizedBox(height: AppSpacing.xs),
            const _HintFooter(),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.focusNode,
    required this.hasText,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasText;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.ink2,
        border: Border.all(color: AppColors.ink3),
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.m,
        AppSpacing.s,
        AppSpacing.s,
        AppSpacing.s,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 140),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                minLines: 2,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(
                  color: AppColors.fg,
                  fontSize: 14,
                  height: 1.5,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText:
                      AppLocalizations.of(context).chat_composer_idle_hint,
                  hintStyle: const TextStyle(
                    color: AppColors.fgFaint,
                    fontSize: 14,
                    height: 1.5,
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          _SendButton(active: hasText, onTap: onSend),
        ],
      ),
    );
  }
}

class _SendButton extends StatefulWidget {
  const _SendButton({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final disabled = !widget.active;
    final bg = disabled
        ? AppColors.ink3
        : (_hovering
            ? Color.alphaBlend(
                Colors.white.withValues(alpha: 0.06),
                AppColors.accent,
              )
            : AppColors.accent);
    final fg = disabled ? AppColors.fgFaint : AppColors.ink0;

    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: disabled ? null : widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppDurations.hover,
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.inputLarge),
          ),
          child: Icon(Icons.arrow_upward, size: 16, color: fg),
        ),
      ),
    );
  }
}

class _HintFooter extends StatelessWidget {
  const _HintFooter();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            _Kbd(text: '⌘↵'),
            const SizedBox(width: 4),
            Text(l.chat_composer_idle_kbd_send, style: _captionStyle),
            const SizedBox(width: AppSpacing.s),
            _Kbd(text: '↵'),
            const SizedBox(width: 4),
            Text(l.chat_composer_idle_kbd_newline, style: _captionStyle),
          ],
        ),
        const SizedBox(width: AppSpacing.s),
        Flexible(
          child: RichText(
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            text: TextSpan(
              style: _captionStyle,
              children: [
                TextSpan(text: l.chat_composer_idle_tip_prefix),
                TextSpan(
                  text: '?',
                  style: AppMono.kbd(color: AppColors.fgMute),
                ),
                TextSpan(text: l.chat_composer_idle_tip_suffix),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

const TextStyle _captionStyle = TextStyle(
  color: AppColors.fgFaint,
  fontSize: 10.5,
  height: 1.4,
);

class _Kbd extends StatelessWidget {
  const _Kbd({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.ink2,
        border: Border.all(color: AppColors.ink3),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: AppMono.kbd()),
    );
  }
}
