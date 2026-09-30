// The translations of the language the app runs in (#206): what the
// student-facing widgets read lesson and goal texts through, together with
// `localizedContent` / `localizedGoal` (`localized_text.dart`).
//
// Follows `appLocaleProvider`: switching language in Options drops the old
// language's translations at once and fetches the new one's. Dutch fetches
// nothing — it is the source language.
//
// The teacher's editors (#208) show and write translations in every
// language, not only the app's: `languageTranslationsProvider(language)`.

import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/content/content.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The translations into one language, as last fetched.
@immutable
class LanguageTranslations {
  const LanguageTranslations({
    required this.language,
    this.loaded = false,
    this._byId = const {},
  });

  /// Dutch: complete without a fetch, and without translations.
  const LanguageTranslations.source()
    : language = kSourceLanguage,
      loaded = true,
      _byId = const {};

  /// The app language's code (`nl`, `en`, …).
  final String language;

  /// Whether the first fetch has come back. Until it has, every text falls
  /// back to Dutch — a page can wait on this before saying a translation
  /// is missing.
  final bool loaded;

  final Map<String, Translation> _byId;

  /// Whether [language] is the source language, which has no translations.
  bool get isSource => language == kSourceLanguage;

  /// The translation of the lesson [contentId], or `null`.
  Translation? contentFor(String contentId) =>
      _byId[Translation.contentDocId(contentId)];

  /// The translation of the goal [goalId]'s title and description, or `null`.
  Translation? goalFor(String goalId) => _byId[Translation.goalDocId(goalId)];

  /// Every translation into [language].
  Iterable<Translation> get all => _byId.values;

  @override
  bool operator ==(Object other) =>
      other is LanguageTranslations &&
      other.language == language &&
      other.loaded == loaded &&
      mapEquals(other._byId, _byId);

  @override
  int get hashCode =>
      Object.hash(language, loaded, Object.hashAllUnordered(_byId.values));
}

/// Where the lesson [content]'s translation into each language of
/// [translations] stands, by language code (#208).
Map<String, TranslationStatus> contentTranslationStatuses(
  Content content,
  Iterable<LanguageTranslations> translations,
) {
  final hash = contentSourceHash(content);
  return {
    for (final language in translations)
      language.language: translationStatus(
        language.contentFor(content.id),
        hash,
      ),
  };
}

/// Where [goal]'s title and description stand in each language of
/// [translations], by language code (#210).
Map<String, TranslationStatus> goalTranslationStatuses(
  Goal goal,
  Iterable<LanguageTranslations> translations,
) {
  final hash = goalSourceHash(goal);
  return {
    for (final language in translations)
      language.language: translationStatus(language.goalFor(goal.id), hash),
  };
}

/// Follows [language]'s translations for as long as [ref] lives: [update]
/// gets each fetch as a [LanguageTranslations], and hands it on only when
/// it differs from [current] — every poll yields a fresh list, and a page
/// that shows a translation must not rebuild every 5 s.
void _followLanguage(
  Ref ref,
  String language, {
  required LanguageTranslations Function() current,
  required void Function(LanguageTranslations) update,
}) {
  final sub = ref
      .watch(translationServiceProvider)
      .watchLanguage(language)
      .listen((list) {
        final next = LanguageTranslations(
          language: language,
          loaded: true,
          byId: {for (final t in list) t.id: t},
        );
        if (next != current()) update(next);
      });
  ref.onDispose(sub.cancel);
}

class TranslationsNotifier extends Notifier<LanguageTranslations> {
  @override
  LanguageTranslations build() {
    final language = ref.watch(
      appLocaleProvider.select((locale) => locale.languageCode),
    );
    if (language == kSourceLanguage) return const LanguageTranslations.source();

    _followLanguage(
      ref,
      language,
      current: () => state,
      update: (next) => state = next,
    );
    return LanguageTranslations(language: language);
  }
}

/// The translations of the app language (`appLocaleProvider`).
final translationsProvider =
    NotifierProvider<TranslationsNotifier, LanguageTranslations>(
      TranslationsNotifier.new,
    );

/// The translations into one language, whatever language the app runs in:
/// what the teacher's editors show a status for and write (#208).
class LanguageTranslationsNotifier
    extends AutoDisposeFamilyNotifier<LanguageTranslations, String> {
  @override
  LanguageTranslations build(String language) {
    if (language == kSourceLanguage) return const LanguageTranslations.source();
    _followLanguage(
      ref,
      language,
      current: () => state,
      update: (next) => state = next,
    );
    return LanguageTranslations(language: language);
  }

  /// Takes in [translation] as the page just stored it
  /// (`TranslationService.upsert`), so the status shows it before the next
  /// poll does.
  void put(Translation translation) {
    if (translation.language != arg) return;
    state = LanguageTranslations(
      language: arg,
      loaded: state.loaded,
      byId: {...state._byId, translation.id: translation},
    );
  }

  /// Drops the translation with doc id [id] as the page just deleted it
  /// (`TranslationService.delete`).
  void remove(String id) {
    if (!state._byId.containsKey(id)) return;
    state = LanguageTranslations(
      language: arg,
      loaded: state.loaded,
      byId: {...state._byId}..remove(id),
    );
  }
}

/// The translations into the language given as the family argument,
/// polled while a page watches them; Dutch fetches nothing.
final languageTranslationsProvider = NotifierProvider.autoDispose
    .family<LanguageTranslationsNotifier, LanguageTranslations, String>(
      LanguageTranslationsNotifier.new,
    );
