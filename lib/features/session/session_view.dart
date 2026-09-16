import 'package:ai_tutor_python/features/chat/chat_widget.dart';
import 'package:ai_tutor_python/features/session/chat_panel_state.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/playground_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double chatPanelWidth = 460;

/// Width of the edge strip the chat panel folds to in the theory view
/// (#131): room for one 28 px button and the panel's own 1 px border.
const double chatCollapsedWidth = 32;

/// Workspace shown when [Section.session] is active. Houses the three mode
/// views in the left panel and the chat panel on the right; the chat panel
/// width animates between 0, [chatCollapsedWidth] and [chatPanelWidth]
/// depending on [chatPanelLayoutProvider]: Free hides the chat, an MCQ being
/// rendered inside `PracticeView` hides it so the student can focus on the
/// question, and in the theory view the student can fold it to a strip
/// (#131) — which a window under 1200 px starts with until they choose
/// (#138). Whatever the width, `ChatWidget` stays laid out at full width
/// under an `OverflowBox`, so nothing inside the chat reflows and the mode
/// view on the left is the only thing that changes size.
class SessionView extends ConsumerWidget {
  const SessionView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(modeProvider);
    final layout = ref.watch(chatPanelLayoutProvider);
    // Watched here rather than only in the strip so the notifier is alive —
    // and counting — from the first frame of the workspace, not from the
    // first frame the strip happens to be on screen.
    final unread = ref.watch(chatUnreadProvider);
    final width = switch (layout) {
      ChatPanelLayout.hidden => 0.0,
      ChatPanelLayout.collapsed => chatCollapsedWidth,
      ChatPanelLayout.full => chatPanelWidth,
    };

    return Row(
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: AppDurations.modeSwap,
            switchInCurve: AppCurves.layout,
            switchOutCurve: AppCurves.layout,
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: KeyedSubtree(key: ValueKey(mode), child: _viewFor(mode)),
          ),
        ),
        ClipRect(
          child: AnimatedContainer(
            key: const Key('chat-panel'),
            duration: AppDurations.chatSlide,
            curve: AppCurves.layout,
            width: width,
            child: Stack(
              children: [
                OverflowBox(
                  minWidth: chatPanelWidth,
                  maxWidth: chatPanelWidth,
                  alignment: Alignment.centerLeft,
                  child: const SizedBox(
                    width: chatPanelWidth,
                    child: _ChatPanel(),
                  ),
                ),
                // The strip rides the panel's left edge while the chat slides
                // out underneath it, and is what is left once it has.
                if (layout == ChatPanelLayout.collapsed)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: chatCollapsedWidth,
                    child: _CollapsedChatStrip(unread: unread),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _viewFor(SessionMode mode) {
    switch (mode) {
      case SessionMode.explain:
        return const ExplainView();
      case SessionMode.practice:
        return const PracticeView();
      case SessionMode.playground:
        return const PlaygroundView();
    }
  }
}

class _ChatPanel extends StatelessWidget {
  const _ChatPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.ink1,
        border: Border(left: BorderSide(color: AppColors.ink2, width: 1)),
      ),
      child: const ChatWidget(),
    );
  }
}

/// What is left of the chat panel in the theory view once the student folds
/// it (#131): the panel's own surface, one button that unfolds it, and a dot
/// on that button while a tutor message is waiting behind it. A button for
/// asking about the page on screen would sit under it (#132).
class _CollapsedChatStrip extends ConsumerWidget {
  const _CollapsedChatStrip({required this.unread});

  final bool unread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.ink1,
        border: Border(left: BorderSide(color: AppColors.ink2, width: 1)),
      ),
      // Lines the button up with the avatar row of the header it stands in
      // for: the header's vertical padding plus half its 32 px avatar, less
      // half this 28 px button.
      padding: const EdgeInsets.only(top: AppSpacing.md + 2),
      alignment: Alignment.topCenter,
      child: _StripButton(
        key: const Key('chat-expand'),
        icon: Icons.chevron_left,
        tooltip: AppLocalizations.of(context).chat_panel_expand_tooltip,
        unread: unread,
        onTap: () => ref.read(chatCollapsedProvider.notifier).expand(),
      ),
    );
  }
}

class _StripButton extends StatefulWidget {
  const _StripButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.unread,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool unread;
  final VoidCallback onTap;

  @override
  State<_StripButton> createState() => _StripButtonState();
}

class _StripButtonState extends State<_StripButton> {
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
          message: widget.tooltip,
          waitDuration: const Duration(milliseconds: 400),
          child: AnimatedContainer(
            duration: AppDurations.hover,
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _hovering ? AppColors.ink2 : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.inputSmall),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: Icon(widget.icon, size: 16, color: AppColors.fgMute),
                ),
                if (widget.unread)
                  Positioned(
                    top: 3,
                    right: 3,
                    child: Container(
                      key: const Key('chat-unread-dot'),
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.ink1, width: 1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
