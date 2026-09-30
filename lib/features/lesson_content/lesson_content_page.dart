import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/content/content.dart';
import 'package:ai_tutor_python/services/content/content_service.dart';
import 'package:ai_tutor_python/services/content/orphaned_content.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/module/module.dart';
import 'package:ai_tutor_python/services/module/module_service.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:ai_tutor_python/services/translation/translations_provider.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/content_language.dart';
import 'package:ai_tutor_python/widgets/lesson_html_view.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One-shot signal from other pages (e.g. the goals editor) to pre-select
/// a specific subgoal on the next mount of `LessonContentPage`. The page
/// consumes and clears the value on bootstrap so the selection only fires
/// once per navigation event.
final pendingLessonContentGoalIdProvider = StateProvider<String?>((_) => null);

/// The `lang` of [source]'s `<html>` element (`en`, `en-GB`, …) as written,
/// or `null` when [source] has no `<html lang>` — a bare body fragment, or
/// a document that does not say. The lesson-authoring skill writes
/// `<html lang="nl">`.
@visibleForTesting
String? htmlLangAttribute(String source) {
  final match = RegExp(
    r'''<html\b[^>]*?\slang\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))''',
    caseSensitive: false,
  ).firstMatch(source);
  if (match == null) return null;
  final value = (match.group(1) ?? match.group(2) ?? match.group(3))!.trim();
  return value.isEmpty ? null : value;
}

/// The language code a `lang` value names: its primary subtag, lower-cased
/// (`en` for `en-GB`).
String _primaryLanguage(String lang) =>
    lang.split(RegExp('[-_]')).first.toLowerCase();

/// Teacher-only "Lesinhoud" view: a tree of module → root goals → subgoals
/// rendered from the goal tree, paired with a raw-HTML editor + WebView
/// preview for the selected subgoal's authored content. The tree is
/// read-only ordering; reorder still happens in `GoalsPage`.
///
/// The toolbar picks the language the editor works on (#208): Dutch, the
/// source, is the `content` doc; any other language is that lesson's
/// translation in `translations`, made from the Dutch text as it is stored.
/// The tree marks which translations a lesson has and which are stale.
class LessonContentPage extends ConsumerStatefulWidget {
  const LessonContentPage({super.key});

  @override
  ConsumerState<LessonContentPage> createState() => _LessonContentPageState();
}

class _LessonContentPageState extends ConsumerState<LessonContentPage> {
  Goal? _selectedGoal;

  /// The language the title, editor, preview and Upload work on.
  String _language = kSourceLanguage;

  /// The selected subgoal's stored Dutch lesson; `null` when it has none.
  Content? _dutch;

  /// The stored translation of [_dutch] into [_language]; `null` in Dutch,
  /// and when the lesson has no translation into [_language] yet.
  Translation? _translation;

  String _workingTitle = '';
  String _workingBody = '';

  /// Bumped by every load of the editor, so a load that finishes after a
  /// later one started is dropped instead of overwriting it.
  int _loadGeneration = 0;

  late final TextEditingController _bodyCtrl;
  late final TextEditingController _titleCtrl;
  late final Stream<List<Goal>> _goalsStream;
  bool _bootstrapping = true;

  String? get _selectedGoalId => _selectedGoal?.id;

  bool get _isSource => _language == kSourceLanguage;

  /// Whether the editor can hold the chosen language's lesson: Dutch always,
  /// a translation only once there is a Dutch lesson to translate from.
  bool get _canEdit => _selectedGoal != null && (_isSource || _dutch != null);

  @override
  void initState() {
    super.initState();
    _bodyCtrl = TextEditingController();
    _bodyCtrl.addListener(_onEditorChanged);
    _titleCtrl = TextEditingController();
    _titleCtrl.addListener(_onTitleChanged);
    // Stable subscription — recreating the stream per build re-triggers
    // ConnectionState.waiting on every setState and flickers the tree.
    _goalsStream = ref.read(goalsServiceProvider).streamAllGoals();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _bodyCtrl.removeListener(_onEditorChanged);
    _bodyCtrl.dispose();
    _titleCtrl.removeListener(_onTitleChanged);
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final modules = ref.read(moduleServiceProvider.notifier);
    final goals = ref.read(goalsServiceProvider);
    final defaultId = await modules.ensureDefaultModule();
    await goals.backfillModuleIds(defaultId);
    if (!mounted) return;
    setState(() => _bootstrapping = false);
    await _consumePendingSelection();
  }

  Future<void> _consumePendingSelection() async {
    final pendingId = ref.read(pendingLessonContentGoalIdProvider);
    if (pendingId == null) return;
    ref.read(pendingLessonContentGoalIdProvider.notifier).state = null;
    final goal = await ref.read(goalsServiceProvider).getGoalOnce(pendingId);
    if (!mounted || goal == null) return;
    await _selectGoal(goal);
  }

  /// The title and body stored in the chosen language — what "unsaved" is
  /// measured against; `null` when nothing is stored in it yet.
  ({String title, String body})? get _stored {
    if (_isSource) {
      final dutch = _dutch;
      return dutch == null ? null : (title: dutch.title, body: dutch.body);
    }
    final translation = _translation;
    return translation == null
        ? null
        : (title: translation.title, body: translation.text);
  }

  bool get _isDirty {
    if (_selectedGoal == null) return false;
    final stored = _stored;
    if (stored == null) {
      return _workingTitle.isNotEmpty || _workingBody.isNotEmpty;
    }
    return stored.title != _workingTitle || stored.body != _workingBody;
  }

  void _onEditorChanged() {
    final text = _bodyCtrl.text;
    if (text == _workingBody) return;
    setState(() => _workingBody = text);
  }

  void _onTitleChanged() {
    final text = _titleCtrl.text;
    if (text == _workingTitle) return;
    setState(() => _workingTitle = text);
  }

  /// What the editor starts from in the chosen language: what is stored;
  /// else, in Dutch, the subgoal's title over an empty body, and in a
  /// translation nothing.
  ({String title, String body}) get _baseline =>
      _stored ??
      (title: _isSource ? (_selectedGoal?.title ?? '') : '', body: '');

  /// Whether the teacher changed the title or the body since the editor was
  /// filled — what switching language would throw away. Unlike [_isDirty]
  /// (which enables Save), an untouched new Dutch lesson has none.
  bool get _hasEdits {
    if (_selectedGoal == null) return false;
    final baseline = _baseline;
    return baseline.title != _workingTitle || baseline.body != _workingBody;
  }

  /// Puts [_baseline] in the title and editor. Call inside `setState`.
  void _fillEditor() {
    final baseline = _baseline;
    _workingTitle = baseline.title;
    _workingBody = baseline.body;
    _titleCtrl.value = TextEditingValue(
      text: _workingTitle,
      selection: TextSelection.collapsed(offset: _workingTitle.length),
    );
    _bodyCtrl.text = _workingBody;
  }

  Future<Content?> _loadDutch(Goal goal) async {
    final cid = goal.contentId;
    if (cid == null || cid.isEmpty) return null;
    // Cache fast-path; fall back to a fetch if not in the latest poll.
    final cached = ref.read(contentServiceProvider);
    for (final c in cached) {
      if (c.id == cid) return c;
    }
    return ref.read(contentServiceProvider.notifier).getById(cid);
  }

  /// The stored translation of the lesson [contentId] into [language],
  /// fetched now rather than taken from the last poll: the editor starts
  /// from what is stored.
  Future<Translation?> _fetchTranslation(
    String language,
    String contentId,
  ) async {
    final id = Translation.contentDocId(contentId);
    final all = await ref
        .read(translationServiceProvider)
        .listLanguage(language);
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> _selectGoal(Goal goal) async {
    final generation = ++_loadGeneration;
    final language = _language;
    final dutch = await _loadDutch(goal);
    final translation = dutch == null || language == kSourceLanguage
        ? null
        : await _fetchTranslation(language, dutch.id);
    if (!mounted || generation != _loadGeneration) return;

    setState(() {
      _selectedGoal = goal;
      _dutch = dutch;
      _translation = translation;
      _fillEditor();
    });
  }

  /// Switches the editor to [language], asking first when that would throw
  /// away unsaved changes.
  Future<void> _setLanguage(String language) async {
    if (language == _language) return;
    if (_hasEdits && !await _confirmDiscard(language)) return;
    final generation = ++_loadGeneration;
    final dutch = _dutch;
    final translation = dutch == null || language == kSourceLanguage
        ? null
        : await _fetchTranslation(language, dutch.id);
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _language = language;
      _translation = translation;
      if (_selectedGoal != null) _fillEditor();
    });
  }

  Future<bool> _confirmDiscard(String target) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(l.lesson_language_discard_title),
          content: Text(
            l.lesson_language_discard_message(
              contentLanguageName(l, _language),
              contentLanguageName(l, target),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.lesson_language_discard_cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.lesson_language_discard_confirm),
            ),
          ],
        );
      },
    );
    return ok == true;
  }

  Future<void> _save() => _isSource ? _saveSource() : _saveTranslation();

  Future<void> _saveSource() async {
    final goalId = _selectedGoalId;
    if (goalId == null) return;
    final goalsSvc = ref.read(goalsServiceProvider);
    final contentSvc = ref.read(contentServiceProvider.notifier);

    final goal = await goalsSvc.getGoalOnce(goalId);
    if (goal == null) return;

    // Content id mirrors the subgoal id so the link is structural — no
    // separate UUID to drift, and re-imports of the goal tree can't orphan
    // the lesinhoud.
    final id = goalId;
    final content = Content(
      id: id,
      title: _workingTitle.trim().isEmpty ? goal.title : _workingTitle.trim(),
      body: _workingBody,
    );
    await contentSvc.upsert(content);
    if (goal.contentId != id) {
      await goalsSvc.setContentId(goalId, id);
    }
    if (!mounted) return;
    setState(() => _dutch = content);
    _showSnack(AppLocalizations.of(context).lesson_snack_saved);
  }

  /// Stores the editor as the lesson's translation into the chosen language,
  /// made from the Dutch lesson as it is stored now. `content` is not
  /// touched.
  Future<void> _saveTranslation() async {
    final dutch = _dutch;
    if (_selectedGoal == null || dutch == null) return;
    final language = _language;
    final l = AppLocalizations.of(context);
    final title = _workingTitle.trim();
    final Translation stored;
    try {
      stored = await ref
          .read(translationServiceProvider)
          .upsert(
            Translation.content(
              language: language,
              contentId: dutch.id,
              // As the Dutch lesson falls back on the subgoal's title.
              title: title.isEmpty ? dutch.title : title,
              body: _workingBody,
              sourceHash: contentSourceHash(dutch),
            ),
          );
    } on CosmosException catch (e) {
      _showSnack(
        e.isContainerNotFound
            ? l.lesson_translation_containerMissing
            : l.lesson_translation_writeFailed('$e'),
      );
      return;
    }
    if (!mounted) return;
    ref.read(languageTranslationsProvider(language).notifier).put(stored);
    if (_language == language && _dutch?.id == dutch.id) {
      setState(() {
        _translation = stored;
        if (title.isEmpty) _fillEditor();
      });
    }
    _showSnack(l.lesson_snack_saved);
  }

  /// Removes the lesson's translation into the chosen language — only that
  /// doc in `translations`; the Dutch lesson stays.
  Future<void> _deleteTranslation() async {
    final translation = _translation;
    if (translation == null) return;
    final language = translation.language;
    final l = AppLocalizations.of(context);
    final name = contentLanguageName(l, language);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(l.lesson_deleteTranslation_dialog_title(name)),
          content: Text(l.lesson_deleteTranslation_dialog_message(name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.lesson_deleteTranslation_dialog_cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.lesson_deleteTranslation_dialog_confirm),
            ),
          ],
        );
      },
    );
    if (confirm != true || !mounted) return;

    try {
      await ref
          .read(translationServiceProvider)
          .delete(
            language: language,
            kind: TranslationKind.content,
            refId: translation.refId,
          );
    } on CosmosException catch (e) {
      _showSnack(
        e.isContainerNotFound
            ? l.lesson_translation_containerMissing
            : l.lesson_translation_writeFailed('$e'),
      );
      return;
    }
    if (!mounted) return;
    ref
        .read(languageTranslationsProvider(language).notifier)
        .remove(translation.id);
    if (_translation?.id == translation.id && _language == language) {
      setState(() {
        _translation = null;
        _fillEditor();
      });
    }
    _showSnack(l.lesson_snack_translationDeleted(name));
  }

  Future<void> _uploadHtml() async {
    if (!_canEdit) return;
    final couldNotReadMessage = AppLocalizations.of(context)
        .lesson_snack_couldNotRead;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['html', 'htm'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    String text;
    final bytes = file.bytes;
    if (bytes != null) {
      text = utf8.decode(bytes, allowMalformed: true);
    } else if (file.path != null) {
      text = await File(file.path!).readAsString();
    } else {
      _showSnack(couldNotReadMessage);
      return;
    }

    // A file that says which language it is in must match the lesson it
    // goes into; one that does not say is taken as it is.
    final lang = htmlLangAttribute(text);
    if (lang != null && _primaryLanguage(lang) != _language) {
      if (!mounted) return;
      if (!await _confirmLanguageMismatch(lang)) return;
    }
    if (!mounted) return;

    final fragment = _extractBodyFragment(text);
    setState(() {
      _workingBody = fragment;
      _bodyCtrl.text = fragment;
    });
  }

  Future<bool> _confirmLanguageMismatch(String lang) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(l.lesson_upload_langMismatch_title),
          content: Text(
            l.lesson_upload_langMismatch_message(
              contentLanguageName(l, _primaryLanguage(lang)),
              lang,
              contentLanguageName(l, _language),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.lesson_upload_langMismatch_cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.lesson_upload_langMismatch_confirm),
            ),
          ],
        );
      },
    );
    return ok == true;
  }

  /// If [source] looks like a full HTML document, returns the body's inner
  /// HTML. Otherwise returns [source] unchanged. Match is case-insensitive
  /// and dot-all so multi-line bodies work.
  static String _extractBodyFragment(String source) {
    final match = RegExp(
      r'<body\b[^>]*>([\s\S]*?)</body\s*>',
      caseSensitive: false,
    ).firstMatch(source);
    if (match == null) return source;
    return match.group(1)!.trim();
  }

  Future<void> _clearLink() async {
    final goalId = _selectedGoalId;
    if (goalId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(l.lesson_unlink_dialog_title),
          content: Text(l.lesson_unlink_dialog_message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.lesson_unlink_dialog_cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.lesson_unlink_dialog_confirm),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;

    await ref.read(goalsServiceProvider).setContentId(goalId, null);
    if (!mounted) return;
    setState(() {
      _dutch = null;
      _translation = null;
      _workingTitle = '';
      _workingBody = '';
      _titleCtrl.clear();
      _bodyCtrl.text = '';
    });
  }

  /// Reassign flow for a content doc no goal points to (see
  /// `orphanedContent`). Asks for a target subgoal, confirms an overwrite
  /// when that subgoal already has content, then moves the doc under the
  /// target id and links the goal to it.
  Future<void> _reassignOrphan(Content orphan, List<Goal> goals) async {
    final target = await _pickReassignTarget(orphan, goals);
    if (target == null || !mounted) return;

    final existingCid = target.contentId;
    if (existingCid != null && existingCid.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final l = AppLocalizations.of(ctx);
          return AlertDialog(
            title: Text(l.lesson_reassign_overwrite_title),
            content: Text(
              l.lesson_reassign_overwrite_message(target.title, orphan.title),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l.lesson_reassign_overwrite_cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l.lesson_reassign_overwrite_confirm),
              ),
            ],
          );
        },
      );
      if (ok != true || !mounted) return;
    }

    final contentSvc = ref.read(contentServiceProvider.notifier);
    final goalsSvc = ref.read(goalsServiceProvider);
    final moved = await contentSvc.reassign(orphan, target.id);
    if (target.contentId != moved.id) {
      await goalsSvc.setContentId(target.id, moved.id);
    }
    if (!mounted) return;
    final reassigned = AppLocalizations.of(context)
        .lesson_snack_reassigned(target.title);
    // If the target was open in the editor, refresh it with the moved doc
    // — and, in a translation, with the translation that moved along.
    if (_selectedGoalId == target.id) {
      final generation = ++_loadGeneration;
      final language = _language;
      final translation = language == kSourceLanguage
          ? null
          : await _fetchTranslation(language, moved.id);
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _dutch = moved;
          _translation = translation;
          _fillEditor();
        });
      }
    }
    if (!mounted) return;
    _showSnack(reassigned);
  }

  Future<Goal?> _pickReassignTarget(Content orphan, List<Goal> goals) {
    final byId = {for (final g in goals) g.id: g};
    final subgoals = goals.where((g) => g.parentId != null).toList()
      ..sort((a, b) {
        final pa = byId[a.parentId]?.order ?? 0;
        final pb = byId[b.parentId]?.order ?? 0;
        if (pa != pb) return pa.compareTo(pb);
        return a.order.compareTo(b.order);
      });

    return showDialog<Goal>(
      context: context,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(l.lesson_reassign_dialog_title),
          content: SizedBox(
            width: 420,
            child: subgoals.isEmpty
                ? Text(l.lesson_reassign_dialog_noSubgoals)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.lesson_reassign_dialog_message(orphan.title)),
                      const SizedBox(height: AppSpacing.m),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final sg in subgoals)
                              ListTile(
                                dense: true,
                                leading: Icon(
                                  sg.contentId == null
                                      ? Icons.add_circle_outline
                                      : Icons.article_outlined,
                                  size: 16,
                                ),
                                title: Text(sg.title),
                                subtitle: Text(byId[sg.parentId]?.title ?? ''),
                                onTap: () => Navigator.of(ctx).pop(sg),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text(l.lesson_reassign_dialog_cancel),
            ),
          ],
        );
      },
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // Don't watch poll-driven providers at this level — they tick every 5s
    // and would rebuild the preview WebView along with the tree. The tree
    // watches them inside its own Consumer below.
    // A Material (not a coloured Container) so the tree rows inside paint
    // their ink on this surface: `_OrphanRow` is an `InkWell`, and a
    // ColoredBox here would sit in front of the nearest Material and hide the
    // splash, the same defect the goals page (#68) and the instructions
    // editor (#69) had with their ListTiles.
    return Material(
      color: AppColors.ink0,
      child: Column(
        children: [
          _Toolbar(
            isDirty: _isDirty,
            hasSelection: _canEdit,
            language: _language,
            onLanguageChanged: _setLanguage,
            onSave: _isDirty && _canEdit ? _save : null,
            onUpload: _canEdit ? _uploadHtml : null,
          ),
          Divider(height: 1, thickness: 1, color: AppColors.ink2),
          Expanded(
            child: _bootstrapping
                ? const Center(child: CircularProgressIndicator())
                : Row(
                    children: [
                      SizedBox(
                        width: 320,
                        child: StreamBuilder<List<Goal>>(
                          stream: _goalsStream,
                          builder: (context, snap) {
                            if (snap.connectionState ==
                                    ConnectionState.waiting &&
                                !snap.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            if (snap.hasError) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    AppLocalizations.of(
                                      context,
                                    ).lesson_loadError(snap.error.toString()),
                                  ),
                                ),
                              );
                            }
                            final goals = snap.data ?? const <Goal>[];
                            return Consumer(
                              builder: (context, ref, _) {
                                final modules = ref.watch(
                                  moduleServiceProvider,
                                );
                                final contentList = ref.watch(
                                  contentServiceProvider,
                                );
                                final translations = [
                                  for (final language in kTranslationLanguages)
                                    ref.watch(
                                      languageTranslationsProvider(language),
                                    ),
                                ];
                                return _GoalTree(
                                  goals: goals,
                                  modules: modules,
                                  contentById: {
                                    for (final c in contentList) c.id: c,
                                  },
                                  translations: translations,
                                  selectedGoalId: _selectedGoalId,
                                  onSelect: _selectGoal,
                                  orphans: orphanedContent(goals, contentList),
                                  onReassignOrphan: (c) =>
                                      _reassignOrphan(c, goals),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      VerticalDivider(width: 1, color: AppColors.ink2),
                      Expanded(child: _buildEditorPane()),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorPane() {
    final l = AppLocalizations.of(context);
    if (_selectedGoalId == null) {
      return Center(
        child: Text(
          l.lesson_editor_empty_pickSubgoal,
          style: TextStyle(color: AppColors.fgMute),
        ),
      );
    }
    final dutch = _dutch;
    if (!_isSource && dutch == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            l.lesson_translation_needsSource,
            key: const Key('lesson-translation-needs-source'),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.fgMute),
          ),
        ),
      );
    }
    final translation = _translation;
    final languageName = contentLanguageName(l, _language);
    final String? notice;
    final Key? noticeKey;
    if (_isSource || dutch == null) {
      notice = null;
      noticeKey = null;
    } else if (translation == null) {
      notice = l.lesson_translation_none(languageName);
      noticeKey = const Key('lesson-translation-none');
    } else if (translation.isStaleFor(contentSourceHash(dutch))) {
      notice = l.lesson_translation_stale(languageName);
      noticeKey = const Key('lesson-translation-stale');
    } else {
      notice = null;
      noticeKey = null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.m,
            AppSpacing.lg,
            AppSpacing.s,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _titleCtrl,
                  decoration: InputDecoration(
                    labelText: l.lesson_editor_field_title,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              // Unlinking is about the subgoal and every language, so it
              // belongs to the Dutch lesson; a translation only goes itself.
              if (_isSource && dutch != null)
                TextButton.icon(
                  onPressed: _clearLink,
                  icon: const Icon(Icons.link_off, size: 16),
                  label: Text(l.lesson_editor_button_unlink),
                ),
              if (!_isSource && translation != null)
                TextButton.icon(
                  key: const Key('lesson-delete-translation'),
                  onPressed: _deleteTranslation,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text(l.lesson_editor_button_deleteTranslation),
                ),
            ],
          ),
        ),
        if (notice != null)
          Container(
            key: noticeKey,
            margin: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.s,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.m,
              vertical: AppSpacing.s,
            ),
            decoration: BoxDecoration(
              color: AppColors.accent2.withValues(alpha: 0.10),
              border: Border.all(
                color: AppColors.accent2.withValues(alpha: 0.4),
              ),
              borderRadius: BorderRadius.circular(AppRadius.inputSmall),
            ),
            child: Text(
              notice,
              style: TextStyle(color: AppColors.fg, fontSize: 12),
            ),
          ),
        Divider(height: 1, color: AppColors.ink2),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildHtmlEditor()),
              VerticalDivider(width: 1, color: AppColors.ink2),
              Expanded(child: _buildPreview()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHtmlEditor() {
    return Container(
      color: AppColors.ink1,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.s,
      ),
      child: TextField(
        controller: _bodyCtrl,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.45,
          color: AppColors.fg,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (_workingBody.isEmpty) {
      return Container(
        color: AppColors.ink0,
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            AppLocalizations.of(context).lesson_preview_empty,
            style: TextStyle(color: AppColors.fgFaint, fontSize: 12),
          ),
        ),
      );
    }
    return LessonHtmlView(fragment: _workingBody, language: _language);
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.isDirty,
    required this.hasSelection,
    required this.language,
    required this.onLanguageChanged,
    required this.onSave,
    required this.onUpload,
  });

  final bool isDirty;
  final bool hasSelection;
  final String language;
  final ValueChanged<String> onLanguageChanged;
  final VoidCallback? onSave;
  final VoidCallback? onUpload;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      height: 48,
      color: AppColors.ink1,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          Text(
            l.lesson_toolbar_title,
            style: TextStyle(
              color: AppColors.fg,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          ContentLanguagePicker(
            language: language,
            onChanged: onLanguageChanged,
          ),
          const SizedBox(width: AppSpacing.m),
          OutlinedButton.icon(
            icon: const Icon(Icons.upload_file, size: 16),
            onPressed: onUpload,
            label: Text(l.lesson_toolbar_upload),
          ),
          const SizedBox(width: AppSpacing.s),
          FilledButton.icon(
            icon: const Icon(Icons.save, size: 16),
            onPressed: hasSelection ? onSave : null,
            label: Text(
              isDirty ? l.lesson_toolbar_save_dirty : l.lesson_toolbar_save,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalTree extends StatelessWidget {
  const _GoalTree({
    required this.goals,
    required this.modules,
    required this.contentById,
    required this.translations,
    required this.selectedGoalId,
    required this.onSelect,
    required this.orphans,
    required this.onReassignOrphan,
  });

  final List<Goal> goals;
  final List<Module> modules;
  final Map<String, Content> contentById;

  /// The translations in each of [kTranslationLanguages], for the status of
  /// each lesson's translations (#208).
  final List<LanguageTranslations> translations;
  final String? selectedGoalId;
  final ValueChanged<Goal> onSelect;

  /// Content docs no goal references (typically left behind by a Replace
  /// import that changed subgoal ids). Rendered in a trailing section so the
  /// teacher can see them and reassign instead of losing the work.
  final List<Content> orphans;
  final ValueChanged<Content> onReassignOrphan;

  @override
  Widget build(BuildContext context) {
    final byParent = <String?, List<Goal>>{};
    for (final g in goals) {
      byParent.putIfAbsent(g.parentId, () => []).add(g);
    }
    for (final list in byParent.values) {
      list.sort((a, b) => a.order.compareTo(b.order));
    }
    final roots = byParent[null] ?? const <Goal>[];

    final byModule = <String, List<Goal>>{};
    for (final r in roots) {
      final mid = r.moduleId.isEmpty ? Module.defaultId : r.moduleId;
      byModule.putIfAbsent(mid, () => []).add(r);
    }

    final ordered = [...modules]..sort((a, b) => a.order.compareTo(b.order));
    if (ordered.isEmpty || !ordered.any((m) => m.id == Module.defaultId)) {
      ordered.add(
        Module(
          id: Module.defaultId,
          title: AppLocalizations.of(context).lesson_default_moduleTitle,
          order: 0,
        ),
      );
    }

    Widget subgoalRow(Goal child) {
      final cid = child.contentId;
      final content = cid == null ? null : contentById[cid];
      return _SubgoalRow(
        goal: child,
        content: content,
        translations: content == null
            ? const {}
            : contentTranslationStatuses(content, translations),
        selected: selectedGoalId == child.id,
        onTap: () => onSelect(child),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
      children: [
        for (final m in ordered) ...[
          _ModuleHeader(title: m.title),
          for (final root in byModule[m.id] ?? const <Goal>[]) ...[
            _RootRow(goal: root),
            for (final child in (byParent[root.id] ?? const <Goal>[]))
              subgoalRow(child),
          ],
        ],
        if (orphans.isNotEmpty) ...[
          _ModuleHeader(
            title: AppLocalizations.of(context).lesson_orphans_header,
          ),
          for (final c in orphans)
            _OrphanRow(content: c, onTap: () => onReassignOrphan(c)),
        ],
      ],
    );
  }
}

class _OrphanRow extends StatelessWidget {
  const _OrphanRow({required this.content, required this.onTap});

  final Content content;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 6,
        ),
        child: Row(
          children: [
            const SizedBox(width: AppSpacing.m),
            Icon(Icons.link_off, size: 14, color: AppColors.danger),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    content.title.isEmpty ? content.id : content.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.fg,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    l.lesson_orphans_hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.fgFaint,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModuleHeader extends StatelessWidget {
  const _ModuleHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.m,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: AppColors.fgFaint,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _RootRow extends StatelessWidget {
  const _RootRow({required this.goal});
  final Goal goal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.s,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(
        goal.title,
        style: TextStyle(
          color: AppColors.fg,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SubgoalRow extends StatefulWidget {
  const _SubgoalRow({
    required this.goal,
    required this.content,
    required this.translations,
    required this.selected,
    required this.onTap,
  });

  final Goal goal;
  final Content? content;

  /// Where the lesson's translations stand, by language (#208).
  final Map<String, TranslationStatus> translations;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SubgoalRow> createState() => _SubgoalRowState();
}

class _SubgoalRowState extends State<_SubgoalRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final hasContent = widget.goal.contentId != null;
    final label = hasContent
        ? (widget.content?.title ?? widget.goal.title)
        : AppLocalizations.of(context).lesson_subgoal_noContent;

    final bg = widget.selected
        ? AppColors.ink2
        : (_hovering
              ? AppColors.ink2.withValues(alpha: 0.6)
              : Colors.transparent);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: 6,
          ),
          color: bg,
          child: Row(
            children: [
              const SizedBox(width: AppSpacing.m),
              Icon(
                hasContent ? Icons.article_outlined : Icons.add_circle_outline,
                size: 14,
                color: hasContent ? AppColors.accent : AppColors.fgFaint,
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.goal.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.fg,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasContent
                            ? AppColors.fgMute
                            : AppColors.fgFaint,
                        fontSize: 11,
                        fontStyle: hasContent
                            ? FontStyle.normal
                            : FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              TranslationStatusBadges(statuses: widget.translations),
            ],
          ),
        ),
      ),
    );
  }
}
