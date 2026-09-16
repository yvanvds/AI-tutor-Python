/// The "What's new" moment, as state plus a few operations (#119, #130).
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
///
/// Since #130 the same card can also be *asked* for, from Options → About:
/// [openForRunningVersion] shows the running version's notes as often as
/// wanted, from the kept stash when there is one and from the release feed
/// when there is not. The automatic showing stays exactly once per version;
/// only [load] is gated on the seen-flag.
library;

import 'package:ai_tutor_python/core/update_bootstrap.dart';
import 'package:ai_tutor_python/core/update_info.dart';
import 'package:ai_tutor_python/core/whats_new_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The notes on screen, or `null` when there is nothing to show — which is
/// every launch except the first one after the app updated itself, and any
/// moment the student has not just pressed **What's new**.
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

  /// Puts [notes] on screen. The overlay renders whatever is here; it does
  /// not care whether a launch or a button put it there.
  void show(ReleaseNotes notes) {
    if (_disposed) return;
    state = notes;
  }

  /// Shows the running version's notes on request (#130): the kept stash
  /// when the app installed this build itself — no network — and otherwise
  /// the release published under this version's tag.
  ///
  /// Returns `false` when there are no notes to show: no release carries
  /// this version's tag (a dev build), or the one that does has an empty
  /// body. Throws — an [UpdateCheckException] from the feed, or whatever the
  /// preference store threw — when the lookup itself did not complete, so
  /// the button can say why. The state stays `null` in both cases.
  Future<bool> openForRunningVersion() async {
    final String version = ref.read(appVersionProvider);
    final ReleaseNotesFetcher? fetch = ref.read(releaseNotesFetcherProvider);

    final ReleaseNotes? kept = await keptReleaseNotesFor(version);
    if (kept != null) {
      show(kept);
      return true;
    }

    if (fetch == null) {
      throw UpdateCheckException(
        'this build has no release feed to look version $version up on',
      );
    }
    final String? notes = await fetch(version);
    if (notes == null || notes.trim().isEmpty) return false;
    show(ReleaseNotes(version: version, notes: notes));
    return true;
  }

  /// Puts the overlay away and marks the stash seen, so the same build never
  /// shows it again by itself. The notes stay kept for the button. The state
  /// clears first: the student's click must land on the frame they clicked,
  /// not after a disk write.
  Future<void> dismiss() async {
    if (!_disposed) state = null;
    await markReleaseNotesSeen();
  }
}

final whatsNewControllerProvider =
    NotifierProvider<WhatsNewController, ReleaseNotes?>(WhatsNewController.new);
