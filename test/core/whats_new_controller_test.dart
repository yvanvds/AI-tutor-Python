// #119: the controller between the stash and the overlay. What matters here
// is the gate — it shows notes only for the version this build actually is —
// and that dismissing forgets them, which is the whole "one-time" property.

import 'package:ai_tutor_python/core/update_bootstrap.dart';
import 'package:ai_tutor_python/core/whats_new_controller.dart';
import 'package:ai_tutor_python/core/whats_new_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProviderContainer _containerAt(String version) {
  final container = ProviderContainer(
    overrides: [appVersionProvider.overrideWithValue(version)],
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

  test('dismissing forgets the stash, so the next launch is silent', () async {
    SharedPreferences.setMockInitialValues({});
    await stashReleaseNotes(version: '2.3.0+20', notes: '- Faster quizzes');
    final container = _containerAt('2.3.0+20');
    final controller = container.read(whatsNewControllerProvider.notifier);

    await controller.load();
    expect(container.read(whatsNewControllerProvider), isNotNull);

    await controller.dismiss();
    expect(container.read(whatsNewControllerProvider), isNull);
    expect(await loadReleaseNotesFor('2.3.0+20'), isNull);

    // A fresh container is the next launch: same build, nothing left to say.
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
}
