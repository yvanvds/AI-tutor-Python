import 'package:ai_tutor_python/features/chat/chat_widget.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/free_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double chatPanelWidth = 460;

/// Workspace shown when [Section.session] is active. Houses the three mode
/// views in the left panel and the chat panel on the right; the chat panel
/// width animates between 0 and [chatPanelWidth] depending on the active
/// mode (Free hides the chat) and additionally collapses while an MCQ is
/// being rendered inside `PracticeView`, so the student can focus on the
/// question.
class SessionView extends ConsumerWidget {
  const SessionView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(modeProvider);
    final mcqActive = ref.watch(activeMcqProvider) != null;
    final showChat = mode.showsChatPanel && !mcqActive;

    return Row(
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: AppDurations.modeSwap,
            switchInCurve: AppCurves.layout,
            switchOutCurve: AppCurves.layout,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: child,
            ),
            child: KeyedSubtree(
              key: ValueKey(mode),
              child: _viewFor(mode),
            ),
          ),
        ),
        ClipRect(
          child: AnimatedContainer(
            duration: AppDurations.chatSlide,
            curve: AppCurves.layout,
            width: showChat ? chatPanelWidth : 0,
            child: OverflowBox(
              minWidth: chatPanelWidth,
              maxWidth: chatPanelWidth,
              alignment: Alignment.centerLeft,
              child: const SizedBox(
                width: chatPanelWidth,
                child: _ChatPanel(),
              ),
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
      case SessionMode.free:
        return const FreeView();
    }
  }
}

class _ChatPanel extends StatelessWidget {
  const _ChatPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.ink1,
        border: Border(
          left: BorderSide(color: AppColors.ink2, width: 1),
        ),
      ),
      child: const ChatWidget(),
    );
  }
}
