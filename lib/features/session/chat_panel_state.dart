// The chat panel's collapse in the theory view (#131).
//
// In `SessionMode.explain` the chat panel takes 460 px of a student laptop
// for a tutor who does not talk about the theory, so the student can fold
// it to a slim strip and the app remembers that per device — like the
// theme (#32) and the Students table options (#95), a property of the
// machine, stored in SharedPreferences, never of the Cosmos account.
//
// Four things live here, so `SessionView` (the layout) and `ChatHeader`
// (the collapse button) agree on one source of truth:
//
//   - [chatCollapsedProvider] — the remembered choice, or `null` while the
//     student has never pressed either button on this device.
//   - [windowWidthProvider] — how wide the app window is, kept current as
//     it is resized. What the unset choice falls back on (#138): the
//     students the fold was made for sit at a small laptop, and they should
//     not have to find the button once to get the lesson the room.
//   - [chatPanelLayoutProvider] — what the panel is drawn as *right now*.
//     The choice applies to the theory view only: practice keeps the panel
//     (the tutor's questions live there), playground keeps hiding it, and
//     an MCQ on screen keeps hiding it too (#122). Leaving explain always
//     shows the full panel, whatever the preference says; coming back
//     re-applies it. With no choice stored, a window narrower than
//     [kChatFoldWindowWidth] starts folded and a wider one open — and the
//     panel keeps following the window until the student decides. A stored
//     `false` is a decision: open, even on a small screen.
//   - [chatUnreadProvider] — whether the tutor wrote something while the
//     panel was not at full width. Watching the tutor-message count is
//     enough: the flag goes up on the next message and down the moment the
//     full panel is on screen again. No per-message bookkeeping.

import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key of the remembered choice.
const String kChatCollapsedPrefsKey = 'chat_collapsed_explain';

/// Window width, in logical pixels, under which the theory view starts with
/// the chat folded when the student has never chosen (#138). At 1200 px the
/// lesson still has 668 px next to the 460 px panel and the 72 px sidebar;
/// a 1366 px laptop at 125 % scaling (1093 px) would leave it 561.
const double kChatFoldWindowWidth = 1200;

/// Whether the student folded the chat panel in the theory view, hydrated
/// from SharedPreferences on first read. `null` until a choice is stored:
/// the panel then follows the window ([chatPanelLayoutProvider]).
class ChatCollapsedNotifier extends Notifier<bool?> {
  @override
  bool? build() {
    _hydrate();
    return null;
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    // A button pressed before the store answered is the newer choice.
    if (state == null) state = prefs.getBool(kChatCollapsedPrefsKey);
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

final chatCollapsedProvider = NotifierProvider<ChatCollapsedNotifier, bool?>(
  ChatCollapsedNotifier.new,
);

/// The app window's width in logical pixels, re-read whenever the window's
/// metrics change (a resize, a maximize, a move to another monitor).
///
/// A platform fact read the way `systemBrightnessProvider` reads the
/// operating system's brightness, and overridable in tests the same way.
/// Not `MediaQuery`: the layout that needs it is resolved in a provider,
/// where `chatUnreadProvider` can read it too, not in a widget.
final windowWidthProvider = Provider<double>((ref) {
  final binding = WidgetsBinding.instance;
  final observer = _MetricsObserver(ref.invalidateSelf);
  binding.addObserver(observer);
  ref.onDispose(() => binding.removeObserver(observer));
  final view = binding.platformDispatcher.implicitView;
  if (view == null) return double.infinity;
  return view.physicalSize.width / view.devicePixelRatio;
});

class _MetricsObserver with WidgetsBindingObserver {
  _MetricsObserver(this.onMetrics);

  final VoidCallback onMetrics;

  @override
  void didChangeMetrics() => onMetrics();
}

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
/// remembered choice — or, while there is none, the window width (#138).
/// `hidden` wins over the choice: a folded chat in a mode that has no chat
/// is still no chat.
final chatPanelLayoutProvider = Provider<ChatPanelLayout>((ref) {
  final mode = ref.watch(modeProvider);
  final mcqActive = ref.watch(activeMcqProvider) != null;
  if (!mode.showsChatPanel || mcqActive) return ChatPanelLayout.hidden;
  if (mode != SessionMode.explain) return ChatPanelLayout.full;
  final collapsed =
      ref.watch(chatCollapsedProvider) ??
      ref.watch(windowWidthProvider) < kChatFoldWindowWidth;
  return collapsed ? ChatPanelLayout.collapsed : ChatPanelLayout.full;
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
