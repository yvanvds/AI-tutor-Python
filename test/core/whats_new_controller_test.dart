// #119: the controller between the stash and the overlay. What matters here
// is the gate — it shows notes only for the version this build actually is —
// and that dismissing silences them, which is the whole "one-time" property.
//
// #130 adds the way back: `openForRunningVersion()` shows the running
// version's notes on request — from the kept stash without a fetch, and
// from the release feed's by-tag lookup when nothing is kept. A lookup that
// fails has to surface to the button that asked, and leave nothing on
// screen.

import 'package:ai_tutor_python/core/update_bootstrap.dart';
import 'package:ai_tutor_python/core/update_info.dart';
import 'package:ai_tutor_python/core/whats_new_controller.dart';
import 'package:ai_tutor_python/core/whats_new_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A container pinned to [version], with the by-tag lookup replaced by
/// [notes] — which records what it was asked for on [lookups] — or switched
/// off entirely when [feedOff] is set, as a harness boot with no feed does.
ProviderContainer _containerAt(
  String version, {
  Future<String?> Function(String version)? notes,
  List<String>? lookups,
  bool feedOff = false,
}) {
  final container = ProviderContainer(
    overrides: [
      appVersionProvider.overrideWithValue(version),
      releaseNotesFetcherProvider.overrideWithValue(
        feedOff
            ? null
            : (asked) {
                lookups?.add(asked);
                return (notes ?? (_) async => null)(asked);
              },
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a launch with nothing stashed shows nothing', () async {
    SharedPreferences.setMockInitialValues({});
    final container = _containerAt('2.3.0+20');

    await container.read(whatsNewControllerProvider.notifier).load();

    expect(container.read(whatsNewControllerProvider), isNull);
  });

  test('the first launch of the installed version shows its notes', () async {
    SharedPreferences.setMockInitialValues({});
    await stashReleaseNotes(version: '2.3.0+20', notes: '- Faster quizzes');
    final container = _containerAt('2.3.0+20');

    await container.read(whatsNewControllerProvider.notifier).load();

    final shown = container.read(whatsNewControllerProvider);
    expect(shown, isNotNull);
    expect(shown!.version, '2.3.0+20');
    expect(shown.notes, '- Faster quizzes');
  });

  test('notes stashed for a version this build is not stay hidden', () async {
    // The install failed, or a different build was put down by hand.
    SharedPreferences.setMockInitialValues({});
    await stashReleaseNotes(version: '2.4.0+21', notes: 'Not this build');
    final container = _containerAt('2.3.0+20');

    await container.read(whatsNewControllerProvider.notifier).load();

    expect(container.read(whatsNewControllerProvider), isNull);
  });

  test('dismissing marks the stash seen, so the next launch is silent — '
      'but the notes are kept', () async {
    SharedPreferences.setMockInitialValues({});
    await stashReleaseNotes(version: '2.3.0+20', notes: '- Faster quizzes');
    final container = _containerAt('2.3.0+20');
    final controller = container.read(whatsNewControllerProvider.notifier);

    await controller.load();
    expect(container.read(whatsNewControllerProvider), isNotNull);

    await controller.dismiss();
    expect(container.read(whatsNewControllerProvider), isNull);
    expect(await loadReleaseNotesFor('2.3.0+20'), isNull);
    expect(await keptReleaseNotesFor('2.3.0+20'), isNotNull);

    // A fresh container is the next launch: same build, nothing to say.
    final next = _containerAt('2.3.0+20');
    await next.read(whatsNewControllerProvider.notifier).load();
    expect(next.read(whatsNewControllerProvider), isNull);
  });

  test(
    'a launch closed before the card was dismissed shows it again',
    () async {
      // Only a dismissal consumes the stash — the app being closed is not the
      // student saying they read it.
      SharedPreferences.setMockInitialValues({});
      await stashReleaseNotes(version: '2.3.0+20', notes: '- Faster quizzes');

      final first = _containerAt('2.3.0+20');
      await first.read(whatsNewControllerProvider.notifier).load();
      expect(first.read(whatsNewControllerProvider), isNotNull);

      final second = _containerAt('2.3.0+20');
      await second.read(whatsNewControllerProvider.notifier).load();
      expect(second.read(whatsNewControllerProvider), isNotNull);
    },
  );

  group('openForRunningVersion (#130)', () {
    test('kept notes are shown without a fetch, seen or not', () async {
      SharedPreferences.setMockInitialValues({});
      await stashReleaseNotes(version: '2.3.0+20', notes: '- Faster quizzes');
      await markReleaseNotesSeen();
      final lookups = <String>[];
      final container = _containerAt('2.3.0+20', lookups: lookups);
      final controller = container.read(whatsNewControllerProvider.notifier);

      // The launch's own read is silent by now...
      await controller.load();
      expect(container.read(whatsNewControllerProvider), isNull);

      // ...the button's is not.
      expect(await controller.openForRunningVersion(), isTrue);
      final shown = container.read(whatsNewControllerProvider);
      expect(shown, isNotNull);
      expect(shown!.version, '2.3.0+20');
      expect(shown.notes, '- Faster quizzes');
      expect(lookups, isEmpty, reason: 'the feed was asked with notes kept');

      // As often as wanted: dismissing and asking again still works offline.
      await controller.dismiss();
      expect(container.read(whatsNewControllerProvider), isNull);
      expect(await controller.openForRunningVersion(), isTrue);
      expect(container.read(whatsNewControllerProvider), isNotNull);
      expect(lookups, isEmpty);
    });

    test('nothing kept: the release for this version is looked up and '
        'shown', () async {
      SharedPreferences.setMockInitialValues({});
      final lookups = <String>[];
      final container = _containerAt(
        '2.3.0+20',
        lookups: lookups,
        notes: (_) async => 'For students\n\n- Faster quizzes',
      );
      final controller = container.read(whatsNewControllerProvider.notifier);

      expect(await controller.openForRunningVersion(), isTrue);

      expect(lookups, ['2.3.0+20']);
      final shown = container.read(whatsNewControllerProvider);
      expect(shown, isNotNull);
      expect(shown!.version, '2.3.0+20');
      expect(shown.notes, 'For students\n\n- Faster quizzes');
    });

    test('a stash for another version is ignored and the feed asked', () async {
      // The launch would have cleared this on its way past; the button must
      // not show it against the wrong release either way.
      SharedPreferences.setMockInitialValues({});
      await stashReleaseNotes(version: '2.2.0+19', notes: 'Old news');
      final lookups = <String>[];
      final container = _containerAt(
        '2.3.0+20',
        lookups: lookups,
        notes: (_) async => 'New news',
      );

      expect(
        await container
            .read(whatsNewControllerProvider.notifier)
            .openForRunningVersion(),
        isTrue,
      );

      expect(lookups, ['2.3.0+20']);
      expect(container.read(whatsNewControllerProvider)!.notes, 'New news');
    });

    test('a fetched showing is not stashed — the next launch stays '
        'silent', () async {
      // A hand-installed build never had its notes stashed and must not
      // start announcing them on the launch after the button was pressed.
      SharedPreferences.setMockInitialValues({});
      final container = _containerAt('2.3.0+20', notes: (_) async => 'News');
      final controller = container.read(whatsNewControllerProvider.notifier);
      await controller.openForRunningVersion();
      await controller.dismiss();

      final next = _containerAt('2.3.0+20');
      await next.read(whatsNewControllerProvider.notifier).load();
      expect(next.read(whatsNewControllerProvider), isNull);
    });

    test('no release under this version\'s tag: nothing shown, and the '
        'caller is told', () async {
      SharedPreferences.setMockInitialValues({});
      final container = _containerAt('2.3.0+20', notes: (_) async => null);

      expect(
        await container
            .read(whatsNewControllerProvider.notifier)
            .openForRunningVersion(),
        isFalse,
      );

      expect(container.read(whatsNewControllerProvider), isNull);
    });

    test('a release published with an empty body counts as no notes', () async {
      SharedPreferences.setMockInitialValues({});
      final container = _containerAt('2.3.0+20', notes: (_) async => ' \n ');

      expect(
        await container
            .read(whatsNewControllerProvider.notifier)
            .openForRunningVersion(),
        isFalse,
      );
      expect(container.read(whatsNewControllerProvider), isNull);
    });

    test('a lookup that fails surfaces, and the state stays null', () async {
      SharedPreferences.setMockInitialValues({});
      final container = _containerAt(
        '2.3.0+20',
        notes: (_) async =>
            throw UpdateCheckException('release lookup returned HTTP 500'),
      );

      await expectLater(
        container
            .read(whatsNewControllerProvider.notifier)
            .openForRunningVersion(),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.message,
            'message',
            contains('HTTP 500'),
          ),
        ),
      );

      expect(container.read(whatsNewControllerProvider), isNull);
    });

    test('a build with no release feed says so rather than hanging', () async {
      SharedPreferences.setMockInitialValues({});
      final container = _containerAt('2.3.0+20', feedOff: true);

      await expectLater(
        container
            .read(whatsNewControllerProvider.notifier)
            .openForRunningVersion(),
        throwsA(isA<UpdateCheckException>()),
      );
      expect(container.read(whatsNewControllerProvider), isNull);
    });

    test('kept notes win even on a build with no feed', () async {
      SharedPreferences.setMockInitialValues({});
      await stashReleaseNotes(version: '2.3.0+20', notes: 'Kept');
      await markReleaseNotesSeen();
      final container = _containerAt('2.3.0+20', feedOff: true);

      expect(
        await container
            .read(whatsNewControllerProvider.notifier)
            .openForRunningVersion(),
        isTrue,
      );
      expect(container.read(whatsNewControllerProvider)!.notes, 'Kept');
    });
  });

  test('show() puts notes on screen directly', () {
    SharedPreferences.setMockInitialValues({});
    final container = _containerAt('2.3.0+20');

    container
        .read(whatsNewControllerProvider.notifier)
        .show(const ReleaseNotes(version: '2.3.0+20', notes: 'Hello'));

    expect(container.read(whatsNewControllerProvider)!.notes, 'Hello');
  });
}
