// The chat panel's collapse in the theory view (#131).
//
// In `SessionMode.explain` the chat panel takes 460 px of a student laptop
// for a tutor who does not talk about the theory, so the student can fold
// it to a slim strip and the app remembers that per device — like the
// theme (#32) and the Students table options (#95), a property of the
// machine, stored in SharedPreferences, never of the Cosmos account.
//
// Three things live here, so `SessionView` (the layout) and `ChatHeader`
// (the collapse button) agree on one source of truth:
//
//   - [chatCollapsedProvider] — the remembered choice. Default open, so
//     nobody who never touches the button sees a change.
//   - [chatPanelLayoutProvider] — what the panel is drawn as *right now*.
//     The choice applies to the theory view only: practice keeps the panel
//     (the tutor's questions live there), playground keeps hiding it, and
//     an MCQ on screen keeps hiding it too (#122). Leaving explain always
//     shows the full panel, whatever the preference says; coming back
//     re-applies it.
//   - [chatUnreadProvider] — whether the tutor wrote something while the
//     panel was not at full width. Watching the tutor-message count is
//     enough: the flag goes up on the next message and down the moment the
//     full panel is on screen again. No per-message bookkeeping.

import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key of the remembered choice.
const String kChatCollapsedPrefsKey = 'chat_collapsed_explain';

/// Whether the student folded the chat panel in the theory view, hydrated
/// from SharedPreferences on first read.
class ChatCollapsedNotifier extends Notifier<bool> {
  @override
  bool build() {
    _hydrate();
    return false;
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getBool(kChatCollapsedPrefsKey);
    if (stored != null) state = stored;
  }

  /// Applies [collapsed] at once and stores it for the next launch.
  Future<void> setCollapsed(bool collapsed) async {
    state = collapsed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kChatCollapsedPrefsKey, collapsed);
  }

  Future<void> collapse() => setCollapsed(true);

  Future<void> expand() => setCollapsed(false);
}

final chatCollapsedProvider = NotifierProvider<ChatCollapsedNotifier, bool>(
  ChatCollapsedNotifier.new,
);

/// How the chat panel is drawn for the active mode.
enum ChatPanelLayout {
  /// Width zero — playground, or an MCQ on screen (#122).
  hidden,

  /// The slim strip with the expand button — explain, folded.
  collapsed,

  /// The full chat.
  full,
}

/// The panel's layout right now, from the mode, the MCQ state and the
/// remembered choice. `hidden` wins over the choice: a folded chat in a mode
/// that has no chat is still no chat.
final chatPanelLayoutProvider = Provider<ChatPanelLayout>((ref) {
  final mode = ref.watch(modeProvider);
  final mcqActive = ref.watch(activeMcqProvider) != null;
  if (!mode.showsChatPanel || mcqActive) return ChatPanelLayout.hidden;
  if (mode == SessionMode.explain && ref.watch(chatCollapsedProvider)) {
    return ChatPanelLayout.collapsed;
  }
  return ChatPanelLayout.full;
});

/// Whether a tutor message arrived while the full panel was off screen.
///
/// Set when `ChatService.tutorMessageCount` goes up while the layout is
/// anything but [ChatPanelLayout.full]; cleared as soon as the layout is
/// `full` again, or when the chat is emptied (a session restart) and there
/// is nothing left to read. A message that arrives while the panel is
/// hidden (say, in playground) counts too: it is just as unread when the
/// student lands back in the theory view with the strip.
class ChatUnreadNotifier extends Notifier<bool> {
  @override
  bool build() {
    final count = ref.watch(chatServiceProvider).tutorMessageCount;
    var seen = count.value;
    void onCountChanged() {
      final now = count.value;
      if (now == 0) {
        state = false;
      } else if (now > seen &&
          ref.read(chatPanelLayoutProvider) != ChatPanelLayout.full) {
        state = true;
      }
      seen = now;
    }

    count.addListener(onCountChanged);
    ref.onDispose(() => count.removeListener(onCountChanged));
    ref.listen<ChatPanelLayout>(chatPanelLayoutProvider, (_, layout) {
      if (layout == ChatPanelLayout.full) state = false;
    });
    return false;
  }
}

final chatUnreadProvider = NotifierProvider<ChatUnreadNotifier, bool>(
  ChatUnreadNotifier.new,
);
