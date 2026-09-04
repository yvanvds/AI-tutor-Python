/// The "What's new" moment, as state plus two operations (#119).
///
/// Sits at the far end of the update flow: `UpdateController.apply()` stashes
/// the release notes on the way out (see `whats_new_store.dart`), the
/// installer replaces the app, and the build that comes back reads them here
/// on its first frame.
///
/// Deliberately shaped like `LevelUpController` — a nullable notifier the
/// shell stacks an overlay on — because it is the same kind of thing: a rare
/// beat the app raises by itself, shown once, dismissed by a click. Unlike
/// the goal splash it is never timed away; a student who is mid-sentence when
/// the app starts should still find it there.
library;

import 'package:ai_tutor_python/core/update_bootstrap.dart';
import 'package:ai_tutor_python/core/whats_new_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The notes on screen, or `null` when there is nothing to show — which is
/// every launch except the first one after the app updated itself.
class WhatsNewController extends Notifier<ReleaseNotes?> {
  bool _disposed = false;

  @override
  ReleaseNotes? build() {
    ref.onDispose(() => _disposed = true);
    return null;
  }

  /// Reads the stash left by the update that installed this build.
  ///
  /// Fired unawaited from the shell's first frame, so — exactly like the
  /// update check next to it — it must never throw and must never write
  /// state into a container that has already gone (a window closed, or a
  /// test torn down, while the prefs read was in flight).
  Future<void> load() async {
    final ReleaseNotes? stashed;
    try {
      stashed = await loadReleaseNotesFor(ref.read(appVersionProvider));
    } on Object {
      // An unreadable preference store is not a reason to fail a launch;
      // the worst case is a student not being told what changed.
      return;
    }
    if (_disposed || stashed == null) return;
    state = stashed;
  }

  /// Puts the overlay away and forgets the stash, so the same build never
  /// shows it again. The state clears first: the student's click must land
  /// on the frame they clicked, not after a disk write.
  Future<void> dismiss() async {
    if (!_disposed) state = null;
    await clearReleaseNotes();
  }
}

final whatsNewControllerProvider =
    NotifierProvider<WhatsNewController, ReleaseNotes?>(WhatsNewController.new);
