/// Where the release notes wait out the installer restart (#119) — and, since
/// #130, where they stay afterwards so About can bring them back.
///
/// The updater already fetches a release's notes (`PublishedRelease.notes` →
/// `UpdateInfo.notes`, #50) and then throws them away: `runInstallerAndExit`
/// ends the process, and the build that comes back has no memory of what it
/// was told. The new build also does not contact GitHub again until its next
/// scheduled check, so by the time it *could* look the notes up, the moment
/// to show them has passed.
///
/// Of the two ways out the issue named, this is the stash: the notes are
/// written to SharedPreferences **just before** the installer is launched,
/// and the next launch reads them back. It was picked over re-fetching the
/// release for `kAppVersion` from GitHub because
///
///   - it needs no network on the very launch a student is most likely to be
///     on a school connection that has just been disturbed by an install;
///   - it costs no second API round trip, and cannot be rate-limited;
///   - it is drivable end-to-end from the existing update fakes, where the
///     re-fetch path would need a live `api.github.com` call or a second fake
///     that answers a *by-version* lookup the app does not otherwise make.
///
/// The trade-off is that a build installed by hand (rather than by the app's
/// own updater) has nothing here. That case is what the by-tag fetch behind
/// About's **What's new** button is for (#130, `fetchReleaseNotesByTag`).
///
/// The stash is keyed by the version it describes, so it is self-expiring:
/// notes for a version this build is not are dropped on sight rather than
/// shown against the wrong release.
///
/// Dismissing the card used to *clear* the stash; it now marks it **seen**
/// and keeps the notes (#130). "Seen" is what keeps the automatic card
/// one-time; the kept notes are what lets the button work offline for every
/// build the app installed itself — which is every student's case.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The version the stashed notes belong to.
const String kWhatsNewVersionPref = 'whats_new_version';

/// The stashed release notes themselves.
const String kWhatsNewNotesPref = 'whats_new_notes';

/// Whether the student has dismissed the card for the stashed version (#130).
/// Absent until they do; reset by the next stash.
const String kWhatsNewSeenPref = 'whats_new_seen';

/// Release notes waiting to be shown, and the version they describe.
@immutable
class ReleaseNotes {
  const ReleaseNotes({required this.version, required this.notes});

  /// The version the app came back as — `99.0.0+1`, no leading `v`.
  final String version;

  /// The body of the GitHub release, verbatim. Markdown by origin; rendered
  /// as plain text by the overlay (see `whats_new_overlay.dart`).
  final String notes;
}

/// Parks [notes] for [version] so the build that comes back can show them.
///
/// Called on the way out, from the one place that knows an install is
/// actually going ahead. Writing blank notes is allowed and stores nothing
/// worth showing — [loadReleaseNotesFor] treats it as "no notes". A new
/// stash is by definition unseen, so the flag left by the previous version's
/// dismissal goes with it.
Future<void> stashReleaseNotes({
  required String version,
  required String notes,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kWhatsNewVersionPref, version);
  await prefs.setString(kWhatsNewNotesPref, notes);
  await prefs.remove(kWhatsNewSeenPref);
}

/// The stashed notes, but only when they describe [runningVersion] and the
/// student has not dismissed them yet. This is what the launch reads.
///
/// Anything for another version is cleared on the way past: a stash for
/// another version is an update that did not land (or a build installed over
/// the top by hand), and leaving it behind would show the wrong release's
/// notes on some later launch that happens to match. Blank notes are also
/// cleared — a release published with an empty body has nothing to announce.
/// Notes already seen are *kept* and simply not returned; About can still
/// ask for them with [keptReleaseNotesFor].
Future<ReleaseNotes?> loadReleaseNotesFor(String runningVersion) async {
  final notes = await keptReleaseNotesFor(runningVersion);
  if (notes == null) return null;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(kWhatsNewSeenPref) ?? false) return null;
  return notes;
}

/// The stashed notes for [runningVersion], seen or not — what the **What's
/// new** button shows without a network (#130). Applies the same expiry as
/// [loadReleaseNotesFor]: a stash for another version, or a blank one, is
/// cleared and reads as nothing.
Future<ReleaseNotes?> keptReleaseNotesFor(String runningVersion) async {
  final prefs = await SharedPreferences.getInstance();
  final version = prefs.getString(kWhatsNewVersionPref);
  final notes = prefs.getString(kWhatsNewNotesPref);
  if (version == null || version != runningVersion || notes == null) {
    if (version != null || notes != null) await clearReleaseNotes();
    return null;
  }
  if (notes.trim().isEmpty) {
    await clearReleaseNotes();
    return null;
  }
  return ReleaseNotes(version: version, notes: notes);
}

/// Records that the student has dismissed the card, so the next launch of
/// the same build does not show it again. The notes stay where they are.
///
/// This is what makes the automatic overlay one-time. Set unconditionally —
/// a flag with no stash beside it is harmless, and the next stash removes it.
Future<void> markReleaseNotesSeen() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kWhatsNewSeenPref, true);
}

/// Forgets the stash, seen-flag included. Called when the stash turns out to
/// describe a version this build is not.
Future<void> clearReleaseNotes() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(kWhatsNewVersionPref);
  await prefs.remove(kWhatsNewNotesPref);
  await prefs.remove(kWhatsNewSeenPref);
}
