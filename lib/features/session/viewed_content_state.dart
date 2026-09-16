// Which theory page is on screen (#132).
//
// A question the student types while reading a lesson is about that
// lesson, so the tutor needs to know which `content` doc the theory view
// is showing. That is not the active subgoal's: the student may have paged
// back (#115) to re-read an older explanation, and paging is view-local
// state in `ExplainView`. The view publishes here what it draws — the id
// of the page in its WebView, or nothing when it shows a placeholder — and
// the tutor and the chat composer read it.

import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The id of the `content` doc the theory view is showing, or `null` when
/// no theory view is on screen or the one on screen has no page to show.
///
/// The view that shows a page is its *owner* until it goes away, and only
/// the owner can take its page down again: with the mode switcher's
/// cross-fade two theory views can briefly overlap — one leaving, one
/// arriving — and the leaving one must not clear what the arriving one
/// just put up.
class ViewedContentNotifier extends Notifier<String?> {
  Object? _owner;

  @override
  String? build() => null;

  /// [owner] is showing the page [contentId], or a placeholder when `null`.
  void show(Object owner, String? contentId) {
    _owner = owner;
    state = contentId;
  }

  /// [owner] left the screen. Ignored when another owner has shown a page
  /// since.
  void hide(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    state = null;
  }
}

final viewedContentIdProvider =
    NotifierProvider<ViewedContentNotifier, String?>(ViewedContentNotifier.new);

/// Whether a question typed in the chat right now is a question about the
/// theory page on screen: the theory view is the active mode and it shows a
/// page. The tutor routes on this and the composer's hint says so; both
/// read it here so they never disagree.
final askAboutPageProvider = Provider<bool>((ref) {
  return ref.watch(modeProvider) == SessionMode.explain &&
      ref.watch(viewedContentIdProvider) != null;
});
