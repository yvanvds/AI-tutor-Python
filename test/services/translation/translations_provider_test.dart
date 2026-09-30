// Issue #206 — the translations of the app language, as the student-facing
// widgets will read them (#207, #210): `translationsProvider` follows
// `appLocaleProvider`, and `localizedContent` / `localizedGoal` give the text
// to show with whether it is the Dutch fallback or a stale translation. A
// missing `translations` container shows Dutch; Dutch fetches nothing.

import 'dart:ui';

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/content/content.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/translation/localized_text.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:ai_tutor_python/services/translation/translations_provider.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/unprovisioned_cosmos.dart';

final _lesson = Content(
  id: 's1',
  title: 'Variabelen',
  body: '<p>Een variabele is een doos.</p>',
);

final _goal = Goal(
  id: 's1',
  title: 'Variabelen',
  description: 'Waarden bewaren.',
  parentId: 'r1',
  order: 1000,
);

/// Stands in for the Options language switch.
final _locale = StateProvider<Locale>((_) => const Locale('en'));

void main() {
  late InMemoryCosmos cosmos;

  setUp(() {
    cosmos = InMemoryCosmos.partitioned('language', [
      Translation.content(
        language: 'en',
        contentId: 's1',
        title: 'Variables',
        body: '<p>A variable is a box.</p>',
        sourceHash: contentSourceHash(_lesson),
      ).toMap(),
      Translation.goal(
        language: 'en',
        goalId: 's1',
        title: 'Variables',
        description: 'Keeping values.',
        sourceHash: goalSourceHash(_goal),
      ).toMap(),
    ]);
  });

  ProviderContainer containerFor(
    CosmosContainer translations, {
    Locale locale = const Locale('en'),
  }) {
    final container = ProviderContainer(
      overrides: [
        _locale.overrideWith((_) => locale),
        appLocaleProvider.overrideWith((ref) => ref.watch(_locale)),
        translationServiceProvider.overrideWithValue(
          TranslationService(container: translations),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(translationsProvider, (_, _) {});
    return container;
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('English with a translation shows the translation', () async {
    final container = containerFor(cosmos.container);
    expect(container.read(translationsProvider).loaded, isFalse);
    await settle();

    final translations = container.read(translationsProvider);
    expect(translations.loaded, isTrue);
    expect(translations.language, 'en');
    expect(translations.contentFor('s1')!.title, 'Variables');
    expect(translations.goalFor('s1')!.text, 'Keeping values.');

    expect(
      localizedContent(_lesson, translations),
      const LocalizedContent(
        contentId: 's1',
        language: 'en',
        title: 'Variables',
        body: '<p>A variable is a box.</p>',
      ),
    );
    expect(
      localizedGoal(_goal, translations),
      const LocalizedGoal(
        goalId: 's1',
        language: 'en',
        title: 'Variables',
        description: 'Keeping values.',
      ),
    );
  });

  test('English without a translation falls back to Dutch, flagged', () async {
    final container = containerFor(cosmos.container);
    await settle();
    final translations = container.read(translationsProvider);

    final lesson = localizedContent(
      Content(id: 's2', title: 'Lijsten', body: '<p>lijst</p>'),
      translations,
    );
    expect(lesson.isFallback, isTrue);
    expect(lesson.isStale, isFalse);
    expect(lesson.language, kSourceLanguage);
    expect(lesson.title, 'Lijsten');
    expect(lesson.body, '<p>lijst</p>');

    final goal = localizedGoal(
      Goal(id: 's2', title: 'Lijsten', order: 2000),
      translations,
    );
    expect(goal.isFallback, isTrue);
    expect(goal.title, 'Lijsten');
    expect(goal.description, isNull);
  });

  test('a translation made from older Dutch text is stale', () async {
    final container = containerFor(cosmos.container);
    await settle();
    final translations = container.read(translationsProvider);

    final changedLesson = _lesson.copyWith(body: '<p>Een doos, met naam.</p>');
    final lesson = localizedContent(changedLesson, translations);
    expect(lesson.isStale, isTrue);
    expect(lesson.isFallback, isFalse);
    expect(lesson.body, '<p>A variable is a box.</p>');

    final changedGoal = Goal(
      id: 's1',
      title: 'Variabelen en waarden',
      description: 'Waarden bewaren.',
      order: 1000,
    );
    expect(localizedGoal(changedGoal, translations).isStale, isTrue);
    expect(localizedGoal(_goal, translations).isStale, isFalse);
  });

  test('Dutch shows the source, unflagged, and fetches nothing', () async {
    final missing = UnprovisionedCosmos('translations');
    final container = containerFor(
      missing.container,
      locale: const Locale('nl'),
    );
    await settle();

    final translations = container.read(translationsProvider);
    expect(translations.isSource, isTrue);
    expect(translations.loaded, isTrue);
    final lesson = localizedContent(_lesson, translations);
    expect(lesson.isFallback, isFalse);
    expect(lesson.language, 'nl');
    expect(lesson.body, _lesson.body);
    expect(localizedGoal(_goal, translations).title, 'Variabelen');
    expect(missing.requests, isEmpty);
  });

  test('switching language drops the old translations and loads the new '
      'language', () async {
    final container = containerFor(cosmos.container);
    await settle();
    expect(container.read(translationsProvider).contentFor('s1'), isNotNull);

    container.read(_locale.notifier).state = const Locale('nl');
    await settle();
    final dutch = container.read(translationsProvider);
    expect(dutch.isSource, isTrue);
    expect(dutch.contentFor('s1'), isNull);

    container.read(_locale.notifier).state = const Locale('en');
    expect(
      container.read(translationsProvider).contentFor('s1'),
      isNull,
      reason: 'nothing is shown from before the switch until the fetch',
    );
    await settle();
    expect(container.read(translationsProvider).contentFor('s1'), isNotNull);
  });

  test('without a `translations` container, English shows Dutch', () async {
    final missing = UnprovisionedCosmos('translations');
    final container = containerFor(missing.container);
    // The real REST client answers over a few event-loop turns.
    for (var i = 0; i < 50; i++) {
      if (container.read(translationsProvider).loaded) break;
      await settle();
    }

    final translations = container.read(translationsProvider);
    expect(translations.loaded, isTrue);
    final lesson = localizedContent(_lesson, translations);
    expect(lesson.isFallback, isTrue);
    expect(lesson.body, _lesson.body);
    expect(localizedGoal(_goal, translations).title, 'Variabelen');
  });

  test('a poll that brings nothing new does not notify; a changed '
      'translation does', () {
    fakeAsync((async) {
      final container = ProviderContainer(
        overrides: [
          appLocaleProvider.overrideWithValue(const Locale('en')),
          translationServiceProvider.overrideWithValue(
            TranslationService(container: cosmos.container),
          ),
        ],
      );
      container.listen(translationsProvider, (_, _) {});
      async.flushMicrotasks();
      expect(container.read(translationsProvider).loaded, isTrue);

      var notified = 0;
      container.listen(translationsProvider, (_, _) => notified++);
      async.elapse(kCosmosPollInterval * 3);
      expect(notified, 0);

      cosmos.docs['en/content_s1']!['title'] = 'Variables!';
      async.elapse(kCosmosPollInterval);
      expect(notified, 1);
      expect(
        container.read(translationsProvider).contentFor('s1')!.title,
        'Variables!',
      );
      container.dispose();
    });
  });
}
