// #119: the release notes have to survive the installer restart, and then
// be shown exactly once. Both halves live in the stash's rules — it is keyed
// by the version it describes and cleared when it is read against anything
// else, so a stash that outlived the update it belonged to can never surface
// against the wrong release.

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

  test('clearing is what makes the overlay one-time', () async {
    SharedPreferences.setMockInitialValues({});
    await stashReleaseNotes(version: '2.3.0+20', notes: 'Something');
    expect(await loadReleaseNotesFor('2.3.0+20'), isNotNull);

    // Reading alone does NOT consume it — an app closed before the student
    // dismissed the card should still show it next time.
    expect(await loadReleaseNotesFor('2.3.0+20'), isNotNull);

    await clearReleaseNotes();
    expect(await loadReleaseNotesFor('2.3.0+20'), isNull);
  });

  test('a half-written stash is cleaned up rather than half-read', () async {
    SharedPreferences.setMockInitialValues({kWhatsNewVersionPref: '2.3.0+20'});
    expect(await loadReleaseNotesFor('2.3.0+20'), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kWhatsNewVersionPref), isNull);
  });
}
