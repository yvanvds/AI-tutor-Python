// The teacher's side of translated lessons and goals (#208): which language
// an editor works on, and where each translation stands.
//
//   - [ContentLanguagePicker]: Dutch (the source) or a translation language,
//     for a toolbar.
//   - [TranslationStatusBadges]: one small badge per language a doc has a
//     translation in, marked when it is stale — for a tree row or a status
//     row.

import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';

/// The name of the content language [code], as the Options page names it;
/// the code itself for a language the app has no name for.
String contentLanguageName(AppLocalizations l, String code) => switch (code) {
  'nl' => l.settings_language_dutch,
  'en' => l.settings_language_english,
  _ => code,
};

/// A choice between [kContentLanguages]: the source language, marked as
/// such, then the translation languages.
class ContentLanguagePicker extends StatelessWidget {
  const ContentLanguagePicker({
    super.key,
    required this.language,
    required this.onChanged,
  });

  /// The language chosen now.
  final String language;

  /// Called with the language picked; `null` disables the picker.
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final onChanged = this.onChanged;
    return SegmentedButton<String>(
      key: const Key('content-language-picker'),
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        for (final code in kContentLanguages)
          ButtonSegment<String>(
            value: code,
            label: Text(
              code == kSourceLanguage
                  ? l.translation_language_source(contentLanguageName(l, code))
                  : contentLanguageName(l, code),
            ),
          ),
      ],
      selected: {language},
      onSelectionChanged: onChanged == null
          ? null
          : (selection) => onChanged(selection.single),
    );
  }
}

/// A badge per language in [statuses] that has a translation, in
/// [kTranslationLanguages] order: the language code, and for a stale one a
/// warning colour and icon. The tooltip says which it is. Nothing for a
/// missing translation.
class TranslationStatusBadges extends StatelessWidget {
  const TranslationStatusBadges({super.key, required this.statuses});

  /// Language code → status of the doc's translation into it.
  final Map<String, TranslationStatus> statuses;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final code in kTranslationLanguages)
        if (statuses[code] case final status?
            when status != TranslationStatus.missing)
          (code, status),
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (code, status) in shown)
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xxs),
            child: _Badge(language: code, status: status),
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.language, required this.status});

  final String language;
  final TranslationStatus status;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final name = contentLanguageName(l, language);
    final stale = status == TranslationStatus.stale;
    final color = stale ? AppColors.accent2 : AppColors.accent;
    return Tooltip(
      message: stale
          ? l.translation_status_stale(name)
          : l.translation_status_current(name),
      child: Container(
        key: Key('translation-status-$language-${status.name}'),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (stale) ...[
              Icon(Icons.history, size: 10, color: color),
              const SizedBox(width: 2),
            ],
            Text(
              language.toUpperCase(),
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
