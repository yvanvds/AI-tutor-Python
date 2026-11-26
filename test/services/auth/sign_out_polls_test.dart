// #345 — the providers that live as long as the app and poll the database
// stop at a sign-out and start again at the next sign-in. Before, every one
// of them kept polling with nobody signed in; with the database on the
// sign-in each poll had no token, and its 401 pushed the recovery screen
// over the sign-in screen. `config/global` has its own test in
// test/services/config/global_config_service_test.dart; these are the rest
// of them, each held the way the app holds it and counted by its reads.
//
// The mastery XP polled `progress` from an `async*` body waiting in
// `await for`, which hears of its cancellation only at the next value; a
// poll that keeps failing after the sign-out never brought one, so that
// poll ran on. And the ambient rim's progress line lives as long as the
// app: after the sign-out, with the top bar gone, it held its progress
// stream open.

import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/classes/classes_service.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/content/content_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/instructions/instructions_service.dart';
import 'package:ai_tutor_python/services/module/module_service.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:ai_tutor_python/services/translation/translations_provider.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/switchable_auth.dart';

/// A poller under test: the provider, and the overrides that put it on
/// [store].
typedef _Poller = ({
  ProviderListenable<Object?> provider,
  List<Override> Function(InMemoryCosmos store) overrides,
  InMemoryCosmos Function() store,
});

final Map<String, _Poller> _pollers = {
  'the class list (config/classes)': (
    provider: classesServiceProvider,
    overrides: (store) => [
      classesServiceProvider.overrideWith(
        () => ClassesService(container: store.container),
      ),
    ],
    store: InMemoryCosmos.new,
  ),
  'the lessons (content)': (
    provider: contentServiceProvider,
    overrides: (store) => [
      contentServiceProvider.overrideWith(
        () => ContentService(container: store.container),
      ),
    ],
    store: InMemoryCosmos.new,
  ),
  'the prompts (instructions)': (
    provider: instructionsServiceProvider,
    overrides: (store) => [
      instructionsServiceProvider.overrideWith(
        () => InstructionsService(container: store.container),
      ),
    ],
    store: InMemoryCosmos.new,
  ),
  'the modules (modules)': (
    provider: moduleServiceProvider,
    overrides: (store) => [
      moduleServiceProvider.overrideWith(
        () => ModuleService(container: store.container),
      ),
    ],
    store: InMemoryCosmos.new,
  ),
  'the translations of the app language (translations)': (
    provider: translationsProvider,
    overrides: (store) => [
      appLocaleProvider.overrideWithValue(const Locale('en')),
      translationServiceProvider.overrideWithValue(
        TranslationService(container: store.container),
      ),
    ],
    store: () => InMemoryCosmos.partitioned('language'),
  ),
};

void main() {
  for (final MapEntry(key: name, value: poller) in _pollers.entries) {
    test('$name: no polls after the sign-out, and again after the next '
        'sign-in', () {
      fakeAsync((async) {
        final store = poller.store();
        final container = ProviderContainer(
          overrides: [
            authServiceProvider.overrideWith(SwitchableAuth.new),
            ...poller.overrides(store),
          ],
        );
        // Held for the life of the app, as a screen or another provider
        // holds it.
        container.listen(poller.provider, (_, _) {});
        final auth = container.read(authServiceProvider.notifier);

        async.elapse(Duration.zero);
        expect(store.reads, 1, reason: 'the first poll, right away');
        async.elapse(kCosmosPollInterval * 2);
        expect(store.reads, 3);

        auth.signOut();
        async.elapse(Duration.zero);
        final atSignOut = store.reads;
        async.elapse(kCosmosPollInterval * 4);
        expect(
          store.reads,
          atSignOut,
          reason: 'polled the database with nobody signed in',
        );

        auth.signIn();
        async.elapse(Duration.zero);
        expect(store.reads, atSignOut + 1);
        async.elapse(kCosmosPollInterval);
        expect(store.reads, atSignOut + 2);

        container.dispose();
      });
    });
  }

  test('the mastery XP (progress): no polls after the sign-out, and again '
      'after the next sign-in', () {
    fakeAsync((async) {
      final uid = kSwitchableIdentity.oid;
      final accounts = InMemoryCosmos([
        {
          'id': uid,
          'uid': uid,
          'email': kSwitchableIdentity.email,
          'firstName': kSwitchableIdentity.firstName,
          'lastName': kSwitchableIdentity.lastName,
          'mayUseGlobalKey': true,
        },
      ]);
      final goals = InMemoryCosmos([
        for (final (id, parent) in [('r1', null), ('s1', 'r1')])
          {
            'id': id,
            'type': 'goal',
            'title': id,
            'parentId': parent,
            'order': 1000,
            'optional': false,
          },
      ]);
      final progress = InMemoryCosmos([
        {'id': '${uid}_s1', 'uid': uid, 'goalId': 's1', 'progress': 0.5},
      ]);
      late final ProviderContainer container;
      container = ProviderContainer(
        overrides: [
          authServiceProvider.overrideWith(SwitchableAuth.new),
          accountServiceProvider.overrideWith(
            () => AccountService(container: accounts.container),
          ),
          goalsServiceProvider.overrideWithValue(
            GoalsService(container: goals.container),
          ),
          progressServiceProvider.overrideWithValue(
            ProgressService(
              container: progress.container,
              getUid: () => container.read(authServiceProvider)?.oid,
            ),
          ),
        ],
      );
      // Held for the life of the app, as the XP pill and the tutor hold it.
      container.listen(masteryXpProvider, (_, _) {});
      final auth = container.read(authServiceProvider.notifier);

      async.elapse(Duration.zero);
      expect(progress.reads, 1, reason: 'the first poll, right away');
      expect(container.read(masteryXpProvider).valueOrNull, 50);
      async.elapse(kCosmosPollInterval * 2);
      expect(progress.reads, 3);

      auth.signOut();
      async.elapse(Duration.zero);
      final atSignOut = progress.reads;
      async.elapse(kCosmosPollInterval * 4);
      expect(
        progress.reads,
        atSignOut,
        reason: 'polled progress with nobody signed in',
      );
      expect(container.read(masteryXpProvider).valueOrNull, 0);

      auth.signIn();
      async.elapse(Duration.zero);
      expect(progress.reads, atSignOut + 1);
      expect(container.read(masteryXpProvider).valueOrNull, 50);
      async.elapse(kCosmosPollInterval);
      expect(progress.reads, atSignOut + 2);

      container.dispose();
    });
  });

  test("the ambient rim's progress line (progress): no polls after the "
      'sign-out, and again after the next sign-in', () {
    fakeAsync((async) {
      final uid = kSwitchableIdentity.oid;
      final progress = InMemoryCosmos([
        {'id': '${uid}_s1', 'uid': uid, 'goalId': 's1', 'progress': 0.25},
      ]);
      late final ProviderContainer container;
      container = ProviderContainer(
        overrides: [
          authServiceProvider.overrideWith(SwitchableAuth.new),
          goalSelectionProvider.overrideWith(_OnSubgoal.new),
          progressServiceProvider.overrideWithValue(
            ProgressService(
              container: progress.container,
              getUid: () => container.read(authServiceProvider)?.oid,
            ),
          ),
        ],
      );
      // The top bar shows the line, then goes with the shell at the
      // sign-out; the line itself stays.
      var topBar = container.listen(ambientProgressProvider, (_, _) {});
      final auth = container.read(authServiceProvider.notifier);

      async.elapse(Duration.zero);
      expect(progress.reads, 1, reason: 'the first poll, right away');
      expect(container.read(ambientProgressProvider), 0.25);
      async.elapse(kCosmosPollInterval * 2);
      expect(progress.reads, 3);

      auth.signOut();
      topBar.close();
      async.elapse(Duration.zero);
      final atSignOut = progress.reads;
      async.elapse(kCosmosPollInterval * 4);
      expect(
        progress.reads,
        atSignOut,
        reason: 'polled progress with nobody signed in',
      );

      auth.signIn();
      topBar = container.listen(ambientProgressProvider, (_, _) {});
      async.elapse(Duration.zero);
      expect(progress.reads, atSignOut + 1);
      expect(container.read(ambientProgressProvider), 0.25);
      async.elapse(kCosmosPollInterval);
      expect(progress.reads, atSignOut + 2);

      topBar.close();
      container.dispose();
    });
  });
}

/// The student on subgoal `s1` of `r1`.
class _OnSubgoal extends GoalSelectionNotifier {
  @override
  GoalSelectionState build() => GoalSelectionState(
    selectedRoot: Goal(id: 'r1', title: 'r1', order: 1000),
    selectedChild: Goal(id: 's1', title: 's1', parentId: 'r1', order: 1000),
  );
}
