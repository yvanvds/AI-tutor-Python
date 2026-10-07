// A lesson or goal text in the language the student reads in (#206), with
// what a page needs to say about it: that it is the Dutch source because
// there is no translation yet ([isFallback]), or that the translation was
// made from Dutch text that has changed since ([isStale]).
//
//     final shown = localizedContent(content, ref.watch(translationsProvider));
//
// Both value types have `==`, so a widget can `select` on the result and
// rebuild only when the text it shows changes.
//
// A lesson from the content cache has its own provider,
// [localizedContentProvider] (#207): the theory page shows it, and a
// question about that page sends it to the tutor, so both use the same text.
// A goal's title and description are watched through [localizedGoalOf]
// (#210): the leerpad, the objective banner, the theory page's header and
// the goal picker in Options. A notice that was raised about a goal and
// kept only its id and Dutch text watches [localizedGoalByIdOf] (#211): the
// goal-reached splash, the level-up subtitle, and the warm-up, recheck and
// "new goal selected" (#212) pills in chat. A learning objective's "Je kan
// …" statement is watched through [localizedObjectiveOf] (#243): the
// leerpad's list of what a subgoal asks.

import 'package:ai_tutor_python/services/content/content.dart';
import 'package:ai_tutor_python/services/content/content_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:ai_tutor_python/services/translation/translations_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A lesson as it is shown in one language.
@immutable
class LocalizedContent {
  const LocalizedContent({
    required this.contentId,
    required this.language,
    required this.title,
    required this.body,
    this.isFallback = false,
    this.isStale = false,
  });

  final String contentId;

  /// The language [title] and [body] are in: the app language, or
  /// [kSourceLanguage] when [isFallback].
  final String language;

  final String title;

  /// HTML body fragment, as in `Content.body`.
  final String body;

  /// The app language is not Dutch and the lesson has no translation into
  /// it, so this is the Dutch source.
  final bool isFallback;

  /// This is a translation, and the Dutch lesson changed after it was made.
  final bool isStale;

  @override
  bool operator ==(Object other) =>
      other is LocalizedContent &&
      other.contentId == contentId &&
      other.language == language &&
      other.title == title &&
      other.body == body &&
      other.isFallback == isFallback &&
      other.isStale == isStale;

  @override
  int get hashCode =>
      Object.hash(contentId, language, title, body, isFallback, isStale);
}

/// A goal's title and description as they are shown in one language.
@immutable
class LocalizedGoal {
  const LocalizedGoal({
    required this.goalId,
    required this.language,
    required this.title,
    this.description,
    this.isFallback = false,
    this.isStale = false,
  });

  final String goalId;

  /// The language [title] and [description] are in: the app language, or
  /// [kSourceLanguage] when [isFallback].
  final String language;

  final String title;

  /// `null` only when the Dutch goal has none and this is the Dutch text.
  final String? description;

  /// The app language is not Dutch and the goal has no translation into it,
  /// so this is the Dutch source.
  final bool isFallback;

  /// This is a translation, and the Dutch title or description changed
  /// after it was made.
  final bool isStale;

  @override
  bool operator ==(Object other) =>
      other is LocalizedGoal &&
      other.goalId == goalId &&
      other.language == language &&
      other.title == title &&
      other.description == description &&
      other.isFallback == isFallback &&
      other.isStale == isStale;

  @override
  int get hashCode =>
      Object.hash(goalId, language, title, description, isFallback, isStale);
}

/// A learning objective's statement as it is shown in one language (#243).
@immutable
class LocalizedObjective {
  const LocalizedObjective({
    required this.subgoalId,
    required this.loId,
    required this.language,
    required this.statement,
    this.isFallback = false,
    this.isStale = false,
  });

  final String subgoalId;
  final String loId;

  /// The language [statement] is in: the app language, or [kSourceLanguage]
  /// when [isFallback].
  final String language;

  /// The "Je kan …" sentence, or its translation.
  final String statement;

  /// The app language is not Dutch and the statement has no translation
  /// into it, so this is the Dutch source.
  final bool isFallback;

  /// This is a translation, and the Dutch statement changed after it was
  /// made.
  final bool isStale;

  @override
  bool operator ==(Object other) =>
      other is LocalizedObjective &&
      other.subgoalId == subgoalId &&
      other.loId == loId &&
      other.language == language &&
      other.statement == statement &&
      other.isFallback == isFallback &&
      other.isStale == isStale;

  @override
  int get hashCode =>
      Object.hash(subgoalId, loId, language, statement, isFallback, isStale);
}

/// [content] in [translations]' language: its translation when there is
/// one, else the Dutch source with [LocalizedContent.isFallback] set (not
/// set when the language is Dutch).
LocalizedContent localizedContent(
  Content content,
  LanguageTranslations translations,
) {
  final translation = translations.isSource
      ? null
      : translations.contentFor(content.id);
  if (translation == null) {
    return LocalizedContent(
      contentId: content.id,
      language: kSourceLanguage,
      title: content.title,
      body: content.body,
      isFallback: !translations.isSource,
    );
  }
  return LocalizedContent(
    contentId: content.id,
    language: translation.language,
    title: translation.title,
    body: translation.text,
    isStale: translation.isStaleFor(contentSourceHash(content)),
  );
}

/// The lesson [contentId] from the content cache (`contentServiceProvider`)
/// in the app language, as [localizedContent] gives it. `null` while the
/// lesson is not in the cache.
///
/// It notifies only when the text shown changes: the 5 s polls of `content`
/// and `translations` hand back fresh objects each time, but
/// [LocalizedContent] compares by value, so a poll that changes neither the
/// Dutch lesson nor its translation does not reach a listener.
final localizedContentProvider = Provider.autoDispose
    .family<LocalizedContent?, String>((ref, contentId) {
      final translations = ref.watch(translationsProvider);
      for (final content in ref.watch(contentServiceProvider)) {
        if (content.id == contentId) {
          return localizedContent(content, translations);
        }
      }
      return null;
    });

/// [goal]'s title and description in [translations]' language: the
/// translation when there is one, else the Dutch source with
/// [LocalizedGoal.isFallback] set (not set when the language is Dutch).
LocalizedGoal localizedGoal(Goal goal, LanguageTranslations translations) =>
    localizedGoalById(
      goal.id,
      title: goal.title,
      description: goal.description,
      translations: translations,
    );

/// [localizedGoal] for a caller that has only the goal's id and its Dutch
/// [title] and [description] (#211). [LocalizedGoal.isStale] compares the
/// translation against the Dutch text given here, so it is only meaningful
/// when that is the goal's full title and description.
LocalizedGoal localizedGoalById(
  String goalId, {
  required String title,
  String? description,
  required LanguageTranslations translations,
}) {
  final translation = translations.isSource
      ? null
      : translations.goalFor(goalId);
  if (translation == null) {
    return LocalizedGoal(
      goalId: goalId,
      language: kSourceLanguage,
      title: title,
      description: description,
      isFallback: !translations.isSource,
    );
  }
  return LocalizedGoal(
    goalId: goalId,
    language: translation.language,
    title: translation.title,
    description: translation.text,
    isStale: translation.isStaleFor(
      translationSourceHash(title, description ?? ''),
    ),
  );
}

/// [goal]'s title and description in the app language, for a
/// student-facing widget to watch (#210):
///
///     final shown = ref.watch(localizedGoalOf(goal));
///
/// It notifies only when the text shown changes, not on every poll of
/// `translations`. Without a translation it is the Dutch text, which the
/// student-facing widgets show as it is, without a notice. Teacher pages
/// show the Dutch source and do not use this.
ProviderListenable<LocalizedGoal> localizedGoalOf(Goal goal) =>
    translationsProvider.select(
      (translations) => localizedGoal(goal, translations),
    );

/// The goal [goalId]'s title and description in the app language, for a
/// student-facing notice that kept only the goal's id and its Dutch [title]
/// and [description] from when it was raised (#211):
///
///     final shown = ref.watch(
///       localizedGoalByIdOf(splash.goalId, title: splash.goalTitle),
///     );
///
/// Like [localizedGoalOf], it follows a language switch and a translation
/// arriving on a poll while the notice is on screen, notifies only when the
/// text shown changes, and without a translation it is the Dutch text,
/// shown without a notice.
ProviderListenable<LocalizedGoal> localizedGoalByIdOf(
  String goalId, {
  required String title,
  String? description,
}) => translationsProvider.select(
  (translations) => localizedGoalById(
    goalId,
    title: title,
    description: description,
    translations: translations,
  ),
);

/// The statement of [objective], a learning objective of the subgoal
/// [subgoalId], in [translations]' language (#243): the translation when
/// there is one, else the Dutch statement with
/// [LocalizedObjective.isFallback] set (not set when the language is Dutch).
LocalizedObjective localizedObjective(
  String subgoalId,
  LearningObjective objective,
  LanguageTranslations translations,
) {
  final translation = translations.isSource
      ? null
      : translations.objectiveFor(subgoalId, objective.id);
  if (translation == null) {
    return LocalizedObjective(
      subgoalId: subgoalId,
      loId: objective.id,
      language: kSourceLanguage,
      statement: objective.statement,
      isFallback: !translations.isSource,
    );
  }
  return LocalizedObjective(
    subgoalId: subgoalId,
    loId: objective.id,
    language: translation.language,
    statement: translation.text,
    isStale: translation.isStaleFor(objectiveSourceHash(objective)),
  );
}

/// The statement of [objective] of the subgoal [subgoalId] in the app
/// language, for a student-facing widget to watch (#243):
///
///     final shown = ref.watch(localizedObjectiveOf(subgoal.id, lo));
///
/// Like [localizedGoalOf], it notifies only when the text shown changes,
/// and without a translation it is the Dutch statement, shown without a
/// notice.
ProviderListenable<LocalizedObjective> localizedObjectiveOf(
  String subgoalId,
  LearningObjective objective,
) => translationsProvider.select(
  (translations) => localizedObjective(subgoalId, objective, translations),
);
