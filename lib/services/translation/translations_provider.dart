// The translations of the language the app runs in (#206): what the
// student-facing widgets read lesson and goal texts through, together with
// `localizedContent` / `localizedGoal` (`localized_text.dart`).
//
// Follows `appLocaleProvider`: switching language in Options drops the old
// language's translations at once and fetches the new one's. Dutch fetches
// nothing — it is the source language.

import 'package:ai_tutor_python/services/config/app_locale.dart';
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

class TranslationsNotifier extends Notifier<LanguageTranslations> {
  @override
  LanguageTranslations build() {
    final language = ref.watch(
      appLocaleProvider.select((locale) => locale.languageCode),
    );
    if (language == kSourceLanguage) return const LanguageTranslations.source();

    final sub = ref
        .watch(translationServiceProvider)
        .watchLanguage(language)
        .listen((list) {
          final next = LanguageTranslations(
            language: language,
            loaded: true,
            byId: {for (final t in list) t.id: t},
          );
          // Every poll yields a fresh list: only a real change notifies, so a
          // page that shows a translation does not rebuild every 5 s.
          if (next != state) state = next;
        });
    ref.onDispose(sub.cancel);
    return LanguageTranslations(language: language);
  }
}

/// The translations of the app language (`appLocaleProvider`).
final translationsProvider =
    NotifierProvider<TranslationsNotifier, LanguageTranslations>(
      TranslationsNotifier.new,
    );
