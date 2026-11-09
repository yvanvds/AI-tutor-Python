// The "Puntenformule" tab (#129, #301): how a grade comes about, shipped
// inside the app so the version a build carries is the version a student
// can read — the formula promises them it is public and versioned.
//
// Two documents, one view:
//
// - the **short explanation** (#301), `docs/puntenformule-leerlingen.nl.md`
//   or `.en.md` in the app's language: plain words, the grade formula with
//   every letter explained and one worked example. The tab opens on it.
// - the **full formula**, `docs/PUNTENFORMULE.md`: the specification the app
//   and the evaluation follow to the decimal, Dutch only. The bar at the
//   bottom of the tab switches to it and back, so "recompute it yourself"
//   always has the exact rules of this build behind it.
//
// The Markdown is bundled as-is (one source of truth each — see
// `pubspec.yaml`) and converted at load time with `package:markdown`; the
// result goes through the same `LessonHtmlView` the theory pages use, so the
// documents get the lesson stylesheet, the WebView's long-document
// scrolling, table layout and text selection, and the students see one
// consistent look.
//
// No Cosmos, no polling, nothing to refresh: each asset is read and
// converted once per process and cached in a plain `FutureProvider.family`.

import 'dart:convert' show utf8;
import 'dart:typed_data' show Uint8List;

import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/lesson_html_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as md;

/// Asset key of the full formula — the specification, Dutch only.
const String kPuntenformuleAssetKey = 'docs/PUNTENFORMULE.md';

/// Asset keys of the short explanation for students (#301), one per app
/// language.
const String kPuntenformuleStudentNlAssetKey =
    'docs/puntenformule-leerlingen.nl.md';
const String kPuntenformuleStudentEnAssetKey =
    'docs/puntenformule-leerlingen.en.md';

/// The short explanation in the app's language: Dutch for `nl`, English
/// for anything else — English is the app's fallback locale too
/// (`resolveAppLocale`).
String puntenformuleStudentAssetKey(String languageCode) => languageCode == 'nl'
    ? kPuntenformuleStudentNlAssetKey
    : kPuntenformuleStudentEnAssetKey;

/// Converts a document's GitHub-flavoured Markdown to the body fragment
/// [LessonHtmlView] renders. `gitHubWeb` covers what the documents use —
/// pipe tables, fenced code blocks, headings, lists, rules — and emits a
/// plain `<pre><code>` for every formula block: never `<pre class="run">`,
/// so nothing in the page grows a live-preview pane.
String puntenformuleToHtml(String markdown) =>
    md.markdownToHtml(markdown, extensionSet: md.ExtensionSet.gitHubWeb);

/// One converted document, by asset key. Loaded and converted once per
/// container — once per process in the app, like the lesson stylesheet: the
/// files never change while the app runs.
///
/// This provider is the cache; `rootBundle.loadString` is not used at all.
/// Its string cache holds the *future* of the first load, created in
/// whichever zone asked first — in a widget-test process that is the first
/// test's fake-async zone, and every later test then awaits a completion
/// that is never delivered to it. (`_LessonHtmlViewState._loadCss`
/// sidesteps the same trap by caching the string itself.) And from 50 KB
/// on — the specification crossed that line in v1.0.14 — `loadString`
/// decodes in an isolate (`compute`), real asynchronous work that the same
/// fake-async pumps never see complete, and a pointless hop here: the
/// Markdown conversion right after it is the expensive step and runs on
/// this thread anyway. So: the bytes, decoded in place.
final puntenformuleFragmentProvider = FutureProvider.family<String, String>((
  ref,
  assetKey,
) async {
  final data = await rootBundle.load(assetKey);
  final source = utf8.decode(Uint8List.sublistView(data));
  return puntenformuleToHtml(source);
});

class PuntenformulePage extends ConsumerStatefulWidget {
  const PuntenformulePage({super.key});

  @override
  ConsumerState<PuntenformulePage> createState() => _PuntenformulePageState();
}

class _PuntenformulePageState extends ConsumerState<PuntenformulePage> {
  /// Every visit opens on the short explanation: the full formula is the
  /// way further, not the first thing a student lands on.
  bool _showFull = false;

  /// The document on screen, kept while a switched-to one converts (the
  /// full formula on its first open, or the other language after a switch
  /// on the Options page). The one `LessonHtmlView` then gets the new
  /// fragment and navigates in place (#128), instead of being swapped for a
  /// loading note and mounted again as a second WebView.
  ({String fragment, String language})? _shown;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final appLanguage = Localizations.localeOf(context).languageCode;
    final assetKey = _showFull
        ? kPuntenformuleAssetKey
        : puntenformuleStudentAssetKey(appLanguage);
    // The specification is written in Dutch; the short explanation in the
    // language its key was picked for.
    final language = _showFull || appLanguage == 'nl' ? 'nl' : 'en';
    final document = ref.watch(puntenformuleFragmentProvider(assetKey));

    final html = document.valueOrNull;
    if (html != null) _shown = (fragment: html, language: language);
    final shown = _shown;

    final Widget body;
    if (document.hasError) {
      body = _Note(l.puntenformule_loadError('${document.error}'));
    } else if (shown == null) {
      body = _Note(l.puntenformule_loading);
    } else {
      body = LessonHtmlView(fragment: shown.fragment, language: shown.language);
    }

    return Container(
      color: AppColors.ink0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            note: _showFull
                ? l.puntenformule_full_header_note
                : l.puntenformule_header_note,
          ),
          Expanded(child: body),
          _Footer(
            showingFull: _showFull,
            onToggle: () => setState(() => _showFull = !_showFull),
          ),
        ],
      ),
    );
  }
}

/// The same chrome the lesson pages put above their document: a pill with
/// the section name, and one muted line saying what the reader is looking
/// at. The documents' own version lines are the version the student sees;
/// the UI adds no second one.
class _Header extends StatelessWidget {
  const _Header({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxxl,
        AppSpacing.xl,
        AppSpacing.xxxl,
        AppSpacing.s,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              Section.puntenformule.label(context).toUpperCase(),
              style: TextStyle(
                color: AppColors.accent,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Text(
              note,
              key: const Key('puntenformule-header-note'),
              style: TextStyle(
                color: AppColors.fgMute,
                fontSize: 12.5,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// The way to the full formula and back (#301), under the document. A
/// Flutter bar rather than a link inside the page: the lesson view has no
/// navigation handling — a link would take the WebView away from the
/// document — and the bar stays in reach at any scroll position.
class _Footer extends StatelessWidget {
  const _Footer({required this.showingFull, required this.onToggle});

  final bool showingFull;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.ink2)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxxl,
        AppSpacing.s,
        AppSpacing.xxxl,
        AppSpacing.s,
      ),
      child: Row(
        children: [
          if (!showingFull) ...[
            Flexible(
              child: Text(
                l.puntenformule_showFull_lead,
                style: TextStyle(color: AppColors.fgMute, fontSize: 12.5),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.m),
          ],
          TextButton.icon(
            // Plain literals, so `integration_flow_symbols_test` sees both.
            key: showingFull
                ? const Key('puntenformule-show-short')
                : const Key('puntenformule-show-full'),
            onPressed: onToggle,
            icon: Icon(
              showingFull ? Icons.arrow_back : Icons.menu_book_outlined,
              size: 18,
              color: AppColors.accent,
            ),
            label: Text(
              showingFull
                  ? l.puntenformule_showShort
                  : l.puntenformule_showFull,
              style: TextStyle(
                color: AppColors.accent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.fgMute, fontSize: 13),
        ),
      ),
    );
  }
}
