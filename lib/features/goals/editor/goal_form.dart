import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/features/lesson_content/lesson_content_page.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/content/content.dart';
import 'package:ai_tutor_python/services/content/content_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/features/goals/editor/parent_field.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:ai_tutor_python/services/translation/translations_provider.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/content_language.dart';
import 'package:ai_tutor_python/widgets/text_list_editor.dart';
import 'package:ai_tutor_python/widgets/undo_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The goal editor in the goals page's side panel.
///
/// Its language picker (#210) chooses what the title and description fields
/// edit: in Dutch, the source, the `goals` doc itself, as before; in any
/// other language the goal's translation (`goal_${id}` in `translations`),
/// made from the Dutch text as it is stored and saved with its own button.
/// Saving a translation never writes `goals`. Next to the picker a badge per
/// language says which translations the goal has and which are stale. The
/// other fields do not depend on the language.
class GoalForm extends ConsumerStatefulWidget {
  const GoalForm({super.key, required this.goal});
  final Goal goal;

  @override
  ConsumerState<GoalForm> createState() => GoalFormState();
}

class GoalFormState extends ConsumerState<GoalForm> {
  late final TextEditingController _title;
  late final TextEditingController _desc;
  bool _optional = false;
  bool _isConcept = false;

  /// The language the title and description fields edit (#210).
  String _language = kSourceLanguage;

  /// The title and description of the translation into [_language]. The
  /// Dutch fields keep their own controllers, so switching language and
  /// back loses nothing typed there.
  final TextEditingController _trTitle = TextEditingController();
  final TextEditingController _trDesc = TextEditingController();

  /// The stored translation [_trTitle] and [_trDesc] were last filled from;
  /// `null` when there was none.
  Translation? _filledFrom;

  /// While a translation is being written.
  bool _saving = false;

  bool get _isSource => _language == kSourceLanguage;

  /// Whether the teacher changed the translation fields since they were
  /// filled — what switching language would throw away, and what Save
  /// stores.
  bool get _hasTranslationEdits =>
      !_isSource &&
      (_trTitle.text != (_filledFrom?.title ?? '') ||
          _trDesc.text != (_filledFrom?.text ?? ''));

  /// The goal's stored translation into [language], as last polled or
  /// written by this page.
  Translation? _storedTranslation(String language) =>
      ref.read(languageTranslationsProvider(language)).goalFor(widget.goal.id);

  /// Puts [translation] — or nothing, when there is none — in the
  /// translation fields.
  void _fillTranslation(Translation? translation) {
    _filledFrom = translation;
    _trTitle.text = translation?.title ?? '';
    _trDesc.text = translation?.text ?? '';
  }

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.goal.title);
    _desc = TextEditingController(text: widget.goal.description ?? '');
    _optional = widget.goal.optional;
    _isConcept = widget.goal.kind == 'concept';
  }

  @override
  void didUpdateWidget(covariant GoalForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.goal.id != widget.goal.id) {
      _title.text = widget.goal.title;
      _desc.text = widget.goal.description ?? '';
      _optional = widget.goal.optional;
      _isConcept = widget.goal.kind == 'concept';
      // The language stays: a teacher translating goals goes from one to
      // the next in the same language.
      if (!_isSource) _fillTranslation(_storedTranslation(_language));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _trTitle.dispose();
    _trDesc.dispose();
    super.dispose();
  }

  /// Switches the title and description to [language], asking first when
  /// that would throw away an unsaved translation.
  Future<void> _setLanguage(String language) async {
    if (language == _language) return;
    if (_hasTranslationEdits && !await _confirmDiscard(language)) return;
    if (!mounted) return;
    setState(() {
      _language = language;
      if (!_isSource) _fillTranslation(_storedTranslation(language));
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
            l.goals_editor_language_discard_message(
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

  /// Stores the translation fields as the goal's translation into the
  /// chosen language, made from the Dutch title and description as they
  /// are stored now. `goals` is not written.
  Future<void> _saveTranslation() async {
    final goal = widget.goal;
    final language = _language;
    if (language == kSourceLanguage || _saving) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final title = _trTitle.text.trim();
    final description = _trDesc.text.trim();
    setState(() => _saving = true);
    try {
      // Fetched rather than taken from the last poll: the Dutch description
      // is written on every keystroke, and a translation made right after
      // must be made from that text, or it reads as stale at once.
      final source =
          await ref.read(goalsServiceProvider).getGoalOnce(goal.id) ?? goal;
      final stored = await ref
          .read(translationServiceProvider)
          .upsert(
            Translation.goal(
              language: language,
              goalId: goal.id,
              // Never an empty title: as the Dutch goal falls back on
              // "Untitled", the translation falls back on the Dutch title.
              title: title.isEmpty ? source.title : title,
              description: description,
              sourceHash: goalSourceHash(source),
            ),
          );
      if (!mounted) return;
      ref.read(languageTranslationsProvider(language).notifier).put(stored);
      final unchanged =
          _trTitle.text.trim() == title && _trDesc.text.trim() == description;
      if (_language == language && widget.goal.id == goal.id && unchanged) {
        setState(() => _fillTranslation(stored));
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l.goals_editor_translation_saved(contentLanguageName(l, language)),
          ),
        ),
      );
    } on CosmosException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.isContainerNotFound
                ? l.lesson_translation_containerMissing
                : l.lesson_translation_writeFailed('$e'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = ref.read(goalsServiceProvider);
    final l = AppLocalizations.of(context);
    // Which translations the goal has, and which are stale (#210).
    final translations = [
      for (final language in kTranslationLanguages)
        ref.watch(languageTranslationsProvider(language)),
    ];
    final statuses = goalTranslationStatuses(widget.goal, translations);
    final LanguageTranslations? inLanguage = _isSource
        ? null
        : ref.watch(languageTranslationsProvider(_language));
    if (!_isSource) {
      // A poll, another editor or this page's own save: the fields follow
      // the stored translation unless the teacher has typed in them.
      ref.listen<Translation?>(
        languageTranslationsProvider(_language)
            .select((t) => t.goalFor(widget.goal.id)),
        (_, stored) {
          if (!_hasTranslationEdits && stored != _filledFrom) {
            setState(() => _fillTranslation(stored));
          }
        },
      );
    }
    final canSaveTranslation =
        !_isSource &&
        !_saving &&
        (_hasTranslationEdits ||
            statuses[_language] == TranslationStatus.stale);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.goals_editor_title),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: l.goals_editor_tooltip_delete,
            icon: const Icon(Icons.delete),
            onPressed: () => _handleDelete(context),
          ),
          IconButton(
            tooltip: l.goals_editor_tooltip_close,
            onPressed: () => ref
                .read(goalSelectionProvider.notifier)
                .setEditorSelectedGoal(null),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Flexible(
                child: ContentLanguagePicker(
                  language: _language,
                  onChanged: _saving ? null : _setLanguage,
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              TranslationStatusBadges(statuses: statuses),
            ],
          ),
          const SizedBox(height: 12),
          if (inLanguage != null)
            _TranslationNotice(
              status: inLanguage.loaded ? statuses[_language] : null,
              language: contentLanguageName(l, _language),
            ),
          if (_isSource)
            TextField(
              controller: _title,
              decoration: InputDecoration(
                labelText: l.goals_editor_field_title,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (t) => svc.updateTitle(
                widget.goal.id,
                t.trim().isEmpty ? l.goals_editor_untitled : t.trim(),
              ),
              onChanged: (t) {},
            )
          else
            TextField(
              key: const Key('goal-translation-title'),
              controller: _trTitle,
              decoration: InputDecoration(
                labelText: l.goals_editor_field_title,
                // The Dutch text, to translate from.
                hintText: widget.goal.title,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (canSaveTranslation) _saveTranslation();
              },
            ),
          const SizedBox(height: 12),
          widget.goal.parentId != null
              ? ParentField(goal: widget.goal)
              : const SizedBox.shrink(),
          const SizedBox(height: 12),
          if (_isSource)
            TextField(
              controller: _desc,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l.goals_editor_field_description,
                border: const OutlineInputBorder(),
              ),
              onChanged: (t) =>
                  svc.updateDescription(widget.goal.id, t.isEmpty ? null : t),
            )
          else ...[
            TextField(
              key: const Key('goal-translation-description'),
              controller: _trDesc,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l.goals_editor_field_description,
                hintText: widget.goal.description,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const Key('goal-translation-save'),
                onPressed: canSaveTranslation ? _saveTranslation : null,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(l.goals_editor_translation_save),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SwitchListTile(
            value: _optional,
            onChanged: (v) {
              setState(() => _optional = v);
              svc.updateOptional(widget.goal.id, v);
            },
            title: Text(l.goals_editor_switch_optional),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 12),
          if (widget.goal.parentId != null) ...[
            SwitchListTile(
              value: _isConcept,
              onChanged: (v) {
                setState(() => _isConcept = v);
                svc.updateKind(widget.goal.id, v ? 'concept' : null);
              },
              title: Text(l.goals_editor_switch_concept),
              subtitle: Text(l.goals_editor_switch_concept_subtitle),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 12),
            TextListEditor(
              label: l.goals_editor_teachingTips_label,
              values: widget.goal.teachingTips,
              hintText: l.goals_editor_teachingTips_hint,
              emptyText: l.goals_editor_teachingTips_empty,
              addLabel: l.goals_editor_teachingTips_add,
              editTooltip: l.goals_editor_teachingTips_edit,
              deleteTooltip: l.goals_editor_teachingTips_delete,
              saveLabel: l.goals_editor_teachingTips_save,
              cancelLabel: l.goals_editor_teachingTips_cancel,
              onChanged: (vals) => svc.updateTeachingTips(widget.goal.id, vals),
            ),
            const SizedBox(height: 12),
            _LesinhoudRow(goal: widget.goal),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Future<void> _handleDelete(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    final id = widget.goal.id;
    final svc = ref.read(goalsServiceProvider);

    final count = await svc.countDescendants(id);
    if (!context.mounted) return;

    final confirmed = await _confirmDelete(context, count);
    if (!confirmed) return;

    final backup = await svc.backupSubtree(id);
    await svc.deleteSubtree(id);

    if (mounted) {
      ref.read(goalSelectionProvider.notifier).setEditorSelectedGoal(null);
    }

    showUndoSnackBar(
      messenger,
      message: count == 0
          ? l.goals_editor_deleted_single(widget.goal.title)
          : l.goals_editor_deleted_withDescendants(widget.goal.title, count),
      undoLabel: l.common_undo,
      onUndo: () async => svc.restoreSubtree(backup),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, int count) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dCtx) {
        final l = AppLocalizations.of(dCtx);
        return AlertDialog(
          title: Text(l.goals_editor_delete_dialog_title),
          content: Text(
            count == 0
                ? l.goals_editor_delete_dialog_message_single(widget.goal.title)
                : l.goals_editor_delete_dialog_message_withDescendants(
                    widget.goal.title,
                    count,
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: Text(l.goals_editor_delete_action_cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(dCtx, true),
              child: Text(l.goals_editor_delete_action_confirm),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }
}

/// Above the translation fields (#210): that the goal has no translation
/// into the chosen language yet, or that its translation is stale. Nothing
/// for an up-to-date translation, or while [status] is not known yet
/// (`null`: the language's translations have not come back).
class _TranslationNotice extends StatelessWidget {
  const _TranslationNotice({required this.status, required this.language});

  final TranslationStatus? status;

  /// The chosen language's name.
  final String language;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (Key, String)? notice = switch (status) {
      TranslationStatus.missing => (
        const Key('goal-translation-none'),
        l.goals_editor_translation_none(language),
      ),
      TranslationStatus.stale => (
        const Key('goal-translation-stale'),
        l.goals_editor_translation_stale(language),
      ),
      TranslationStatus.current || null => null,
    };
    if (notice == null) return const SizedBox.shrink();
    final (key, text) = notice;
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.s,
      ),
      decoration: BoxDecoration(
        color: AppColors.accent2.withValues(alpha: 0.10),
        border: Border.all(color: AppColors.accent2.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppRadius.inputSmall),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }
}

/// Inline status row in the subgoal editor: shows whether the subgoal has
/// authored content and which translations it has (stale ones marked,
/// #208), with a one-click handoff to the Lesinhoud view.
class _LesinhoudRow extends ConsumerWidget {
  const _LesinhoudRow({required this.goal});
  final Goal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final cid = goal.contentId;
    final hasContent = cid != null && cid.isNotEmpty;
    final cached = ref.watch(contentServiceProvider);
    final content = hasContent
        ? cached
              .where((c) => c.id == cid)
              .cast<Content?>()
              .firstWhere((_) => true, orElse: () => null)
        : null;
    final title = content?.title;
    // Which translations the lesson has, and which are stale (#208).
    final translations = [
      for (final language in kTranslationLanguages)
        ref.watch(languageTranslationsProvider(language)),
    ];
    final statuses = content == null
        ? const <String, TranslationStatus>{}
        : contentTranslationStatuses(content, translations);

    void openInLesinhoud() {
      ref.read(pendingLessonContentGoalIdProvider.notifier).state = goal.id;
      ref.read(sectionProvider.notifier).state = Section.lessonContent;
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Icon(
            hasContent ? Icons.article_outlined : Icons.article_outlined,
            size: 16,
            color: hasContent
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).disabledColor,
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.goals_editor_lesinhoud_label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  hasContent
                      ? (title ?? l.goals_editor_lesinhoud_linked)
                      : l.goals_editor_lesinhoud_none,
                  style: TextStyle(
                    fontSize: 12,
                    color: hasContent ? null : Theme.of(context).disabledColor,
                    fontStyle: hasContent ? FontStyle.normal : FontStyle.italic,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TranslationStatusBadges(statuses: statuses),
          const SizedBox(width: AppSpacing.xxs),
          TextButton(
            onPressed: openInLesinhoud,
            child: Text(
              hasContent
                  ? l.goals_editor_lesinhoud_edit
                  : l.goals_editor_lesinhoud_create,
            ),
          ),
        ],
      ),
    );
  }
}
