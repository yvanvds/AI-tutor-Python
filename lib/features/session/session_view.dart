import 'dart:math' as math;

import 'package:ai_tutor_python/features/chat/chat_widget.dart';
import 'package:ai_tutor_python/features/chat/widgets/tutor_avatar.dart';
import 'package:ai_tutor_python/features/session/chat_panel_state.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/playground_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The full chat panel's width in a window wide enough for it.
const double chatPanelWidth = 460;

/// The full chat panel's width in a session area [sessionWidth] wide:
/// [chatPanelWidth], but never more than half the area (#259). In a window
/// under ~990 px the 460 px panel would leave the exercise or the lesson next
/// to it less room than itself — 168 px in a 700 px window, where the row
/// above the editor and the lesson's footer no longer fit.
double chatPanelFullWidth(double sessionWidth) =>
    math.min(chatPanelWidth, sessionWidth / 2);

/// Width of the edge strip the chat panel folds to in the theory view
/// (#131): room for one 28 px button and the panel's own 1 px border.
const double chatCollapsedWidth = 32;

/// Workspace shown when [Section.session] is active. Houses the three mode
/// views in the left panel and the chat panel on the right; the chat panel
/// width animates between 0, [chatCollapsedWidth] and the full width
/// ([chatPanelFullWidth]: 460 px, or half the area in a narrow window, #259)
/// depending on [chatPanelLayoutProvider]: Free hides the chat, and in the
/// theory view the student can fold it to a strip (#131) — which a window
/// under 1200 px starts with until they choose (#138). An MCQ does not hide
/// it (#271): the student can ask about the quiz, or about the lesson while
/// the quiz waits. Whatever the width, `ChatWidget` stays laid out at full
/// width under an `OverflowBox`, so nothing inside the chat reflows and the
/// mode view on the left is the only thing that changes size. The panel is
/// never wider than the full width, not even mid-slide: a window made narrow
/// re-folds the chat in the theory view, and the slide starts from where the
/// panel was, which the cap holds to half the area instead of squeezing the
/// lesson under its own footer.
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final full = chatPanelFullWidth(constraints.maxWidth);
        final width = switch (layout) {
          ChatPanelLayout.hidden => 0.0,
          ChatPanelLayout.collapsed => chatCollapsedWidth,
          ChatPanelLayout.full => full,
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
            // The cap: a slide that starts from a wider panel than the
            // window now allows shows only the part that fits.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: full),
              child: ClipRect(
                child: AnimatedContainer(
                  key: const Key('chat-panel'),
                  duration: AppDurations.chatSlide,
                  curve: AppCurves.layout,
                  width: width,
                  child: Stack(
                    children: [
                      OverflowBox(
                        minWidth: full,
                        maxWidth: full,
                        alignment: Alignment.centerLeft,
                        child: SizedBox(width: full, child: const _ChatPanel()),
                      ),
                      // The strip rides the panel's left edge while the chat
                      // slides out underneath it, and is what is left once
                      // it has.
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
            ),
          ],
        );
      },
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
/// on that button while a tutor message is waiting behind it.
///
/// The button is the tutor's own face — the [TutorAvatar] the chat header
/// shows — not a bare chevron (#271): on a student laptop the chat starts
/// folded (#138), and a `<` at the edge of the lesson did not read as "the
/// tutor is here, ask about this page".
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
        tooltip: AppLocalizations.of(context).chat_panel_expand_tooltip,
        unread: unread,
        onTap: () => ref.read(chatCollapsedProvider.notifier).expand(),
        child: const TutorAvatar(size: chatStripAvatarSize),
      ),
    );
  }
}

/// The tutor avatar on the folded strip (#271): as large as the strip's
/// 28 px button allows, with a pixel to spare for the hover ring.
const double chatStripAvatarSize = 26;

class _StripButton extends StatefulWidget {
  const _StripButton({
    super.key,
    required this.tooltip,
    required this.unread,
    required this.onTap,
    required this.child,
  });

  final Widget child;
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
          // A ring on hover: the avatar fills the button, so a filled
          // background would not show.
          child: AnimatedContainer(
            duration: AppDurations.hover,
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _hovering ? AppColors.fgMute : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(child: widget.child),
                // On the avatar's shoulder, ringed in the strip's colour so
                // it stands off the gradient.
                if (widget.unread)
                  Positioned(
                    top: -1,
                    right: -1,
                    child: Container(
                      key: const Key('chat-unread-dot'),
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.ink1, width: 2),
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
