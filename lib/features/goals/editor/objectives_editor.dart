import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:ai_tutor_python/services/translation/translations_provider.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/content_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The learning objectives of a subgoal in the goal editor (#313), in the
/// order of `Goal.objectives`.
///
/// In Dutch, the source: per objective its text, kind, weight and optional
/// flag, stored together with the block's Save button
/// (`GoalsService.updateObjectives`). The id is shown and never edited:
/// student beliefs, stamps, `turn_history`, milestones and translations are
/// keyed on it. Adding, removing and reordering objectives is not done here
/// either; that goes through the goal's JSON file.
///
/// In another [language]: the translation of each objective's text
/// (`objective_${subgoal}.${lo}` in `translations`), with the Dutch text as
/// the hint, as for the goal's title and description. Saving a translation
/// never writes `goals`.
class ObjectivesEditor extends ConsumerStatefulWidget {
  const ObjectivesEditor({
    super.key,
    required this.goal,
    required this.language,
  });

  final Goal goal;

  /// The language the goal form edits: [kSourceLanguage] or one of
  /// [kTranslationLanguages].
  final String language;

  @override
  ConsumerState<ObjectivesEditor> createState() => ObjectivesEditorState();
}

/// What the teacher has in the fields of one objective.
class _Draft {
  _Draft(LearningObjective lo)
    : statement = TextEditingController(text: lo.statement),
      weight = TextEditingController(text: _weightText(lo.weight)),
      kind = lo.kind,
      optional = lo.optional;

  final TextEditingController statement;
  final TextEditingController weight;
  LoKind kind;
  bool optional;

  /// The translation of the statement into the chosen language.
  final TextEditingController translation = TextEditingController();

  /// The stored translation [translation] was last filled from.
  Translation? filledFrom;

  void fill(LearningObjective lo) {
    statement.text = lo.statement;
    weight.text = _weightText(lo.weight);
    kind = lo.kind;
    optional = lo.optional;
  }

  void fillTranslation(Translation? stored) {
    filledFrom = stored;
    translation.text = stored?.text ?? '';
  }

  /// The weight typed, or `null` when it is not a number above 0. A decimal
  /// comma counts as a point.
  double? get parsedWeight {
    final value = double.tryParse(weight.text.trim().replaceAll(',', '.'));
    return value != null && value.isFinite && value > 0 ? value : null;
  }

  bool get isValid => statement.text.trim().isNotEmpty && parsedWeight != null;

  /// [lo] with the fields as typed. Only for a valid draft.
  LearningObjective applyTo(LearningObjective lo) => LearningObjective(
    id: lo.id,
    statement: statement.text.trim(),
    kind: kind,
    weight: parsedWeight ?? lo.weight,
    optional: optional,
  );

  bool differsFrom(LearningObjective lo) =>
      statement.text.trim() != lo.statement.trim() ||
      kind != lo.kind ||
      optional != lo.optional ||
      parsedWeight != lo.weight;

  bool get hasTranslationEdits =>
      translation.text.trim() != (filledFrom?.text ?? '').trim();

  void dispose() {
    statement.dispose();
    weight.dispose();
    translation.dispose();
  }

  static String _weightText(double weight) => weight == weight.roundToDouble()
      ? weight.toStringAsFixed(1)
      : weight.toString();
}

bool _sameObjectives(List<LearningObjective> a, List<LearningObjective> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].id != b[i].id ||
        a[i].statement != b[i].statement ||
        a[i].kind != b[i].kind ||
        a[i].weight != b[i].weight ||
        a[i].optional != b[i].optional) {
      return false;
    }
  }
  return true;
}

class ObjectivesEditorState extends ConsumerState<ObjectivesEditor>
    with AutomaticKeepAliveClientMixin {
  /// The goal form is a lazy list: scrolled out of view, this block would
  /// be dropped, and what the teacher typed and has not saved with it.
  @override
  bool get wantKeepAlive => true;

  /// By objective id.
  final Map<String, _Draft> _drafts = {};

  /// The stored objectives the Dutch fields were last filled from, or that
  /// this page last stored.
  List<LearningObjective> _filledFrom = const [];

  bool _saving = false;

  bool get _isSource => widget.language == kSourceLanguage;

  /// Whether the Dutch fields differ from the stored objectives.
  bool get _hasSourceEdits =>
      _filledFrom.any((lo) => _drafts[lo.id]?.differsFrom(lo) ?? false);

  /// Whether the teacher changed a translation since it was filled: what
  /// switching language would throw away. The goal form asks before it
  /// does. The Dutch fields are kept across a language switch.
  bool get hasTranslationEdits =>
      !_isSource && _drafts.values.any((d) => d.hasTranslationEdits);

  @override
  void initState() {
    super.initState();
    _fillSource();
    if (!_isSource) _fillTranslations();
  }

  @override
  void didUpdateWidget(covariant ObjectivesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = widget.goal.objectives;
    if (oldWidget.goal.id != widget.goal.id) {
      _fillSource();
      if (!_isSource) _fillTranslations();
      return;
    }
    if (!_sameObjectives(incoming, _filledFrom)) {
      final sameIds =
          incoming.length == _filledFrom.length &&
          [
            for (var i = 0; i < incoming.length; i++)
              incoming[i].id == _filledFrom[i].id,
          ].every((same) => same);
      // A poll or another editor: the fields follow the stored objectives
      // unless the teacher has typed in them. Other objectives than the
      // fields were made for (an import) always win.
      if (!sameIds || !_hasSourceEdits) {
        _fillSource();
        if (!_isSource) _fillTranslations();
      }
    }
    if (oldWidget.language != widget.language && !_isSource) {
      _fillTranslations();
    }
  }

  @override
  void dispose() {
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    super.dispose();
  }

  /// Puts the goal's stored objectives in the Dutch fields.
  void _fillSource() {
    final objectives = widget.goal.objectives;
    final ids = {for (final lo in objectives) lo.id};
    _drafts.removeWhere((id, draft) {
      if (ids.contains(id)) return false;
      draft.dispose();
      return true;
    });
    for (final lo in objectives) {
      final draft = _drafts[lo.id];
      if (draft == null) {
        _drafts[lo.id] = _Draft(lo);
      } else {
        draft.fill(lo);
      }
    }
    _filledFrom = objectives;
  }

  Translation? _stored(String loId) => ref
      .read(languageTranslationsProvider(widget.language))
      .objectiveFor(widget.goal.id, loId);

  /// Puts the stored translations into the chosen language in the
  /// translation fields.
  void _fillTranslations() {
    for (final entry in _drafts.entries) {
      entry.value.fillTranslation(_stored(entry.key));
    }
  }

  Future<void> _saveSource() async {
    if (_saving) return;
    final goal = widget.goal;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final edited = [
      for (final lo in _filledFrom) _drafts[lo.id]?.applyTo(lo) ?? lo,
    ];
    setState(() => _saving = true);
    try {
      final written = await ref
          .read(goalsServiceProvider)
          .updateObjectives(goal.id, edited);
      if (!written) return;
      if (mounted && widget.goal.id == goal.id) {
        setState(() {
          _filledFrom = edited;
          // As stored: trimmed, the weight written the one way. Not what
          // the teacher went on typing while it was being stored.
          for (final lo in edited) {
            final draft = _drafts[lo.id];
            if (draft != null && !draft.differsFrom(lo)) draft.fill(lo);
          }
        });
      }
      messenger.showSnackBar(
        SnackBar(content: Text(l.goals_editor_objectives_saved)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Stores the translations the teacher changed: a text as the objective's
  /// translation, made from the Dutch statement as it is stored now; an
  /// emptied field removes the translation, so the student reads the Dutch
  /// statement again. With [only], stores that one objective's translation
  /// as it stands: the teacher says a stale translation still holds.
  Future<void> _saveTranslations({String? only}) async {
    final goal = widget.goal;
    final language = widget.language;
    if (language == kSourceLanguage || _saving) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(translationServiceProvider);
    final notifier = ref.read(languageTranslationsProvider(language).notifier);
    final texts = {
      for (final entry in _drafts.entries)
        if (only == null ? entry.value.hasTranslationEdits : entry.key == only)
          entry.key: entry.value.translation.text.trim(),
    };
    setState(() => _saving = true);
    try {
      // Fetched rather than taken from the last poll, as for the goal's own
      // translation: made from older Dutch text it would read as stale.
      final source =
          await ref.read(goalsServiceProvider).getGoalOnce(goal.id) ?? goal;
      final statements = {for (final lo in source.objectives) lo.id: lo};
      for (final MapEntry(key: loId, value: text) in texts.entries) {
        final lo = statements[loId];
        if (lo == null) continue;
        Translation? stored;
        if (text.isEmpty) {
          await service.delete(
            language: language,
            kind: TranslationKind.objective,
            refId: Translation.objectiveRefId(goal.id, loId),
          );
          notifier.remove(Translation.objectiveDocId(goal.id, loId));
        } else {
          stored = await service.upsert(
            Translation.objective(
              language: language,
              subgoalId: goal.id,
              loId: loId,
              statement: text,
              sourceHash: objectiveSourceHash(lo),
            ),
          );
          notifier.put(stored);
        }
        final draft = _drafts[loId];
        if (mounted &&
            widget.goal.id == goal.id &&
            widget.language == language &&
            draft != null &&
            draft.translation.text.trim() == text) {
          draft.fillTranslation(stored);
        }
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l.goals_editor_objectives_translation_saved(
              contentLanguageName(l, language),
            ),
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
    super.build(context);
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final objectives = widget.goal.objectives
        .where((lo) => _drafts.containsKey(lo.id))
        .toList(growable: false);
    final LanguageTranslations? inLanguage = _isSource
        ? null
        : ref.watch(languageTranslationsProvider(widget.language));
    if (!_isSource) {
      // A poll, another editor or this page's own save: a field follows the
      // stored translation unless the teacher has typed in it.
      ref.listen<LanguageTranslations>(
        languageTranslationsProvider(widget.language),
        (_, next) {
          var changed = false;
          for (final entry in _drafts.entries) {
            final stored = next.objectiveFor(widget.goal.id, entry.key);
            final draft = entry.value;
            if (!draft.hasTranslationEdits && stored != draft.filledFrom) {
              draft.fillTranslation(stored);
              changed = true;
            }
          }
          if (changed) setState(() {});
        },
      );
    }
    final canSave =
        !_saving &&
        (_isSource
            ? _hasSourceEdits && _drafts.values.every((d) => d.isValid)
            : hasTranslationEdits);

    return InputDecorator(
      key: const Key('goal-objectives'),
      decoration: InputDecoration(
        labelText: l.goals_editor_objectives_label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (objectives.isEmpty)
            Text(
              l.goals_editor_objectives_empty,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.disabledColor,
                fontStyle: FontStyle.italic,
              ),
            ),
          for (var i = 0; i < objectives.length; i++) ...[
            if (i > 0) const Divider(height: 24),
            _buildObjective(context, objectives[i], inLanguage),
          ],
          if (objectives.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.m),
            if (_isSource)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s),
                child: Text(
                  l.goals_editor_objectives_note,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const Key('goal-objectives-save'),
                onPressed: !canSave
                    ? null
                    : _isSource
                    ? _saveSource
                    : _saveTranslations,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(
                  _isSource
                      ? l.goals_editor_objectives_save
                      : l.goals_editor_translation_save,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildObjective(
    BuildContext context,
    LearningObjective lo,
    LanguageTranslations? inLanguage,
  ) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final draft = _drafts[lo.id]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectableText(
          lo.id,
          key: Key('objective-${lo.id}-id'),
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        if (_isSource) ...[
          TextField(
            key: Key('objective-${lo.id}-statement'),
            controller: draft.statement,
            minLines: 1,
            maxLines: null,
            decoration: InputDecoration(
              labelText: l.goals_editor_objective_statement,
              errorText: draft.statement.text.trim().isEmpty
                  ? l.goals_editor_objective_statement_empty
                  : null,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.m),
          Wrap(
            spacing: AppSpacing.m,
            runSpacing: AppSpacing.s,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 150,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: l.goals_editor_objective_kind,
                    isDense: true,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<LoKind>(
                      key: Key('objective-${lo.id}-kind'),
                      value: draft.kind,
                      isExpanded: true,
                      isDense: true,
                      items: [
                        for (final kind in LoKind.values)
                          DropdownMenuItem(
                            value: kind,
                            child: Text(objectiveKindName(l, kind)),
                          ),
                      ],
                      onChanged: (kind) {
                        if (kind != null) setState(() => draft.kind = kind);
                      },
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 90,
                child: TextField(
                  key: Key('objective-${lo.id}-weight'),
                  controller: draft.weight,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: l.goals_editor_objective_weight,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    key: Key('objective-${lo.id}-optional'),
                    value: draft.optional,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) =>
                        setState(() => draft.optional = v ?? false),
                  ),
                  Text(l.goals_editor_switch_optional),
                ],
              ),
            ],
          ),
          if (draft.parsedWeight == null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Text(
                l.goals_editor_objective_weight_invalid,
                key: Key('objective-${lo.id}-weight-invalid'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ] else ...[
          TextField(
            key: Key('objective-${lo.id}-translation'),
            controller: draft.translation,
            minLines: 1,
            maxLines: null,
            decoration: InputDecoration(
              labelText: l.goals_editor_objective_statement,
              // The Dutch text, to translate from.
              hintText: lo.statement,
              hintMaxLines: 6,
              floatingLabelBehavior: FloatingLabelBehavior.always,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (inLanguage != null && inLanguage.loaded)
            _translationStatus(context, lo, draft),
        ],
      ],
    );
  }

  /// Under a translation field: that the objective has no translation yet,
  /// or that its translation is stale, then with a button that says it
  /// still holds. Nothing for an up-to-date translation.
  Widget _translationStatus(
    BuildContext context,
    LearningObjective lo,
    _Draft draft,
  ) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final language = contentLanguageName(l, widget.language);
    final status = translationStatus(draft.filledFrom, objectiveSourceHash(lo));
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    switch (status) {
      case TranslationStatus.current:
        return const SizedBox.shrink();
      case TranslationStatus.missing:
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs),
          child: Text(
            l.goals_editor_objective_translation_none(language),
            key: Key('objective-${lo.id}-translation-none'),
            style: style,
          ),
        );
      case TranslationStatus.stale:
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.s,
            children: [
              Text(
                l.goals_editor_objective_translation_stale(lo.statement),
                key: Key('objective-${lo.id}-translation-stale'),
                style: style,
              ),
              TextButton(
                key: Key('objective-${lo.id}-translation-confirm'),
                onPressed: _saving || draft.translation.text.trim().isEmpty
                    ? null
                    : () => _saveTranslations(only: lo.id),
                child: Text(l.goals_editor_objective_translation_confirm),
              ),
            ],
          ),
        );
    }
  }
}

/// The name of a learning objective's [kind] in the goal editor.
String objectiveKindName(AppLocalizations l, LoKind kind) => switch (kind) {
  LoKind.recall => l.goals_editor_objective_kind_recall,
  LoKind.apply => l.goals_editor_objective_kind_apply,
  LoKind.predict => l.goals_editor_objective_kind_predict,
  LoKind.reason => l.goals_editor_objective_kind_reason,
};
