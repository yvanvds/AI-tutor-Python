// The "Puntenformule" tab (#129): `docs/PUNTENFORMULE.md`, the grade formula
// written for students, shipped inside the app so the version a build
// carries is the version a student can read — the document promises them it
// is public and versioned, and until now it only existed in the repository.
//
// The Markdown is bundled as-is (one source of truth — see `pubspec.yaml`)
// and converted at load time with `package:markdown`; the result goes
// through the same `LessonHtmlView` the theory pages use, so the document
// gets the lesson stylesheet, the WebView's long-document scrolling, table
// layout and text selection, and the students see one consistent look.
//
// No Cosmos, no polling, nothing to refresh: the asset is read and converted
// once per process and cached in a plain `FutureProvider`.

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

/// Asset key of the bundled document — the repository file itself.
const String kPuntenformuleAssetKey = 'docs/PUNTENFORMULE.md';

/// Converts the document's GitHub-flavoured Markdown to the body fragment
/// [LessonHtmlView] renders. `gitHubWeb` covers what the document uses —
/// pipe tables, fenced code blocks, headings, lists, rules — and emits a
/// plain `<pre><code>` for every formula block: never `<pre class="run">`,
/// so nothing in the page grows a live-preview pane.
String puntenformuleToHtml(String markdown) =>
    md.markdownToHtml(markdown, extensionSet: md.ExtensionSet.gitHubWeb);

/// The converted document. Loaded and converted once per container — once
/// per process in the app, like the lesson stylesheet: the file never changes
/// while the app runs.
///
/// This provider is the cache; `rootBundle.loadString` is not used at all.
/// Its string cache holds the *future* of the first load, created in
/// whichever zone asked first — in a widget-test process that is the first
/// test's fake-async zone, and every later test then awaits a completion
/// that is never delivered to it. (`_LessonHtmlViewState._loadCss`
/// sidesteps the same trap by caching the string itself.) And from 50 KB
/// on — the document crossed that line in v1.0.14 — `loadString` decodes
/// in an isolate (`compute`), real asynchronous work that the same
/// fake-async pumps never see complete, and a pointless hop here: the
/// Markdown conversion right after it is the expensive step and runs on
/// this thread anyway. So: the bytes, decoded in place.
final puntenformuleFragmentProvider = FutureProvider<String>((ref) async {
  final data = await rootBundle.load(kPuntenformuleAssetKey);
  final source = utf8.decode(Uint8List.sublistView(data));
  return puntenformuleToHtml(source);
});

class PuntenformulePage extends ConsumerWidget {
  const PuntenformulePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final fragment = ref.watch(puntenformuleFragmentProvider);

    return Container(
      color: AppColors.ink0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Header(),
          Expanded(
            child: fragment.when(
              data: (html) => LessonHtmlView(fragment: html),
              loading: () => _Note(l.puntenformule_loading),
              error: (error, _) => _Note(l.puntenformule_loadError('$error')),
            ),
          ),
        ],
      ),
    );
  }
}

/// The same chrome the lesson pages put above their document: a pill with
/// the section name, and one muted line saying what the reader is looking
/// at. The document's own "Versie … Laatste wijziging" line is the version
/// the student sees; the UI adds no second one.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
              l.puntenformule_header_note,
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
