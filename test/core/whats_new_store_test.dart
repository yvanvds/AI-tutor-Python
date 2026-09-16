// #119: the release notes have to survive the installer restart, and then
// be shown exactly once. Both halves live in the stash's rules — it is keyed
// by the version it describes and cleared when it is read against anything
// else, so a stash that outlived the update it belonged to can never surface
// against the wrong release.
//
// #130 splits "shown once" from "kept": dismissing marks the stash seen
// instead of clearing it, so the launch's read (`loadReleaseNotesFor`) goes
// quiet while About's (`keptReleaseNotesFor`) can still bring the notes back
// without a network. The self-expiry for another version stays as it was.

import 'package:ai_tutor_python/core/whats_new_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('round-trips notes for the version that comes back', () async {
    SharedPreferences.setMockInitialValues({});
    await stashReleaseNotes(version: '2.3.0+20', notes: '- Faster quizzes');

    final loaded = await loadReleaseNotesFor('2.3.0+20');
    expect(loaded, isNotNull);
    expect(loaded!.version, '2.3.0+20');
    expect(loaded.notes, '- Faster quizzes');

    // What hit the store is the version STRING and the body verbatim.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kWhatsNewVersionPref), '2.3.0+20');
    expect(prefs.getString(kWhatsNewNotesPref), '- Faster quizzes');
  });

  test('nothing stashed means nothing to show', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await loadReleaseNotesFor('2.3.0+20'), isNull);
  });

  test('a stash for another version is dropped, not shown', () async {
    // The update did not land (or a build was installed over the top by
    // hand): showing 2.4.0's notes on a 2.3.0 build would be a lie.
    SharedPreferences.setMockInitialValues({});
    await stashReleaseNotes(version: '2.4.0+21', notes: 'Not this build');

    expect(await loadReleaseNotesFor('2.3.0+20'), isNull);

    // And it is gone, so it cannot resurface on some later launch that
    // happens to match.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kWhatsNewVersionPref), isNull);
    expect(prefs.getString(kWhatsNewNotesPref), isNull);
  });

  test(
    'a release published with an empty body has nothing to announce',
    () async {
      SharedPreferences.setMockInitialValues({});
      await stashReleaseNotes(version: '2.3.0+20', notes: '   \n  ');

      expect(await loadReleaseNotesFor('2.3.0+20'), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kWhatsNewVersionPref), isNull);
    },
  );

  test('marking seen is what makes the overlay one-time', () async {
    SharedPreferences.setMockInitialValues({});
    await stashReleaseNotes(version: '2.3.0+20', notes: 'Something');
    expect(await loadReleaseNotesFor('2.3.0+20'), isNotNull);

    // Reading alone does NOT consume it — an app closed before the student
    // dismissed the card should still show it next time.
    expect(await loadReleaseNotesFor('2.3.0+20'), isNotNull);

    await markReleaseNotesSeen();
    expect(await loadReleaseNotesFor('2.3.0+20'), isNull);
  });

  // #130 — the button's read: what a dismissal leaves behind.
  test('dismissing keeps the notes and sets the seen flag', () async {
    SharedPreferences.setMockInitialValues({});
    await stashReleaseNotes(version: '2.3.0+20', notes: '- Faster quizzes');

    await markReleaseNotesSeen();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kWhatsNewSeenPref), isTrue);
    expect(prefs.getString(kWhatsNewVersionPref), '2.3.0+20');
    expect(prefs.getString(kWhatsNewNotesPref), '- Faster quizzes');

    // The launch's read is quiet; About's is not.
    expect(await loadReleaseNotesFor('2.3.0+20'), isNull);
    final kept = await keptReleaseNotesFor('2.3.0+20');
    expect(kept, isNotNull);
    expect(kept!.version, '2.3.0+20');
    expect(kept.notes, '- Faster quizzes');

    // And reading them back through About does not un-see them.
    expect(await loadReleaseNotesFor('2.3.0+20'), isNull);
  });

  test('the kept notes are unseen until they are dismissed', () async {
    // Before the student has dismissed the card, both reads agree.
    SharedPreferences.setMockInitialValues({});
    await stashReleaseNotes(version: '2.3.0+20', notes: 'Something');
    expect(await keptReleaseNotesFor('2.3.0+20'), isNotNull);
    expect(await loadReleaseNotesFor('2.3.0+20'), isNotNull);
  });

  test('a seen stash for another version still clears everything', () async {
    // The next update did not land, or a build was put down by hand: the
    // old notes go, and so does the flag that belonged to them.
    SharedPreferences.setMockInitialValues({});
    await stashReleaseNotes(version: '2.3.0+20', notes: 'Old news');
    await markReleaseNotesSeen();

    expect(await keptReleaseNotesFor('2.4.0+21'), isNull);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kWhatsNewVersionPref), isNull);
    expect(prefs.getString(kWhatsNewNotesPref), isNull);
    expect(prefs.getBool(kWhatsNewSeenPref), isNull);
  });

  test('a new stash is unseen, whatever the previous one was', () async {
    // 2.3.0 was dismissed; the update to 2.4.0 stashes fresh notes. The
    // flag left by 2.3.0 must not silence them.
    SharedPreferences.setMockInitialValues({});
    await stashReleaseNotes(version: '2.3.0+20', notes: 'Old news');
    await markReleaseNotesSeen();

    await stashReleaseNotes(version: '2.4.0+21', notes: 'New news');

    final shown = await loadReleaseNotesFor('2.4.0+21');
    expect(shown, isNotNull);
    expect(shown!.notes, 'New news');
  });

  test('a stray seen flag with no stash is harmless', () async {
    // The card was opened from About on a hand-installed build (nothing
    // kept) and dismissed: the flag is written with nothing beside it.
    SharedPreferences.setMockInitialValues({});
    await markReleaseNotesSeen();

    expect(await loadReleaseNotesFor('2.3.0+20'), isNull);
    expect(await keptReleaseNotesFor('2.3.0+20'), isNull);

    await stashReleaseNotes(version: '2.4.0+21', notes: 'New news');
    expect(await loadReleaseNotesFor('2.4.0+21'), isNotNull);
  });

  test('clearing forgets the flag with the notes', () async {
    SharedPreferences.setMockInitialValues({});
    await stashReleaseNotes(version: '2.3.0+20', notes: 'Something');
    await markReleaseNotesSeen();

    await clearReleaseNotes();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kWhatsNewSeenPref), isNull);
    expect(await keptReleaseNotesFor('2.3.0+20'), isNull);
  });

  test('a half-written stash is cleaned up rather than half-read', () async {
    SharedPreferences.setMockInitialValues({kWhatsNewVersionPref: '2.3.0+20'});
    expect(await loadReleaseNotesFor('2.3.0+20'), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kWhatsNewVersionPref), isNull);
  });
}
