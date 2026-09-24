// Teacher-only "Vragen" page (#185): the question bank — every question the
// tutor generated — per root goal and subgoal, for the teacher to weed out.
//
// Left: the curriculum, each subgoal with how many questions it has and how
// many of those the teacher has not reviewed yet. Right: the selected
// subgoal's questions, each with its type, level, target LO, how often it
// was asked and what share of the answers was correct, rendered the way the
// student sees it. Per question: mark it reviewed, hide it (never deleted:
// turn records point at it) or show it again, and a note. A filter keeps to
// the questions not reviewed yet; the list sorts on the share correct,
// because an extreme share — very low or very high — points at a bad or a
// too easy question.
//
// Read once when the page opens and after every action, not polled: the
// bank grows with every exercise, and a teacher reviewing it does not need
// it to move under their cursor. The refresh button reloads.
//
// Until the `questions` container exists the page says so instead of
// failing (#170): the one container the app runs without.

import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/question_bank/bank_question.dart';
import 'package:ai_tutor_python/services/question_bank/question_bank_service.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/code_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/tutor_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How the list of one subgoal's questions is ordered.
enum QuestionSort { newest, shareAsc, shareDesc, mostAsked }

/// [questions] in [sort] order. A question nobody answered yet has no share
/// and goes last on both share orders — it says nothing about the question.
List<BankQuestion> sortQuestions(
  Iterable<BankQuestion> questions,
  QuestionSort sort,
) {
  int newest(BankQuestion a, BankQuestion b) =>
      b.createdAt.compareTo(a.createdAt);
  int byShare(BankQuestion a, BankQuestion b, {required bool ascending}) {
    final sa = a.shareCorrect;
    final sb = b.shareCorrect;
    if (sa == null && sb == null) return newest(a, b);
    if (sa == null) return 1;
    if (sb == null) return -1;
    final c = ascending ? sa.compareTo(sb) : sb.compareTo(sa);
    // The same share on more answers is the stronger signal.
    return c != 0 ? c : b.answeredCount.compareTo(a.answeredCount);
  }

  final list = questions.toList();
  switch (sort) {
    case QuestionSort.newest:
      list.sort(newest);
    case QuestionSort.shareAsc:
      list.sort((a, b) => byShare(a, b, ascending: true));
    case QuestionSort.shareDesc:
      list.sort((a, b) => byShare(a, b, ascending: false));
    case QuestionSort.mostAsked:
      list.sort((a, b) {
        final c = b.askedCount.compareTo(a.askedCount);
        return c != 0 ? c : newest(a, b);
      });
  }
  return list;
}

/// Counts per subgoal for the tree.
typedef _SubgoalCounts = ({int total, int unreviewed});

class _Overview {
  const _Overview({required this.goals, required this.counts});

  final List<Goal> goals;
  final Map<String, _SubgoalCounts> counts;
}

class QuestionsPage extends ConsumerStatefulWidget {
  const QuestionsPage({super.key});

  @override
  ConsumerState<QuestionsPage> createState() => _QuestionsPageState();
}

class _QuestionsPageState extends ConsumerState<QuestionsPage> {
  late Future<_Overview> _overview;

  String? _selectedSubgoalId;
  Future<List<BankQuestion>>? _questions;

  /// The selected subgoal's questions as the last read or action left them;
  /// an action replaces its question in here without a reload.
  List<BankQuestion>? _items;

  bool _unreviewedOnly = false;
  QuestionSort _sort = QuestionSort.newest;

  /// Ids of the questions with an action in flight.
  final Set<String> _busy = <String>{};

  QuestionBankService get _bank => ref.read(questionBankServiceProvider);

  @override
  void initState() {
    super.initState();
    _overview = _loadOverview();
  }

  Future<_Overview> _loadOverview() async {
    final summaries = await _bank.listSummaries();
    final goals = await ref.read(goalsServiceProvider).getAllGoalsOnce();
    final counts = <String, _SubgoalCounts>{};
    for (final s in summaries) {
      final c = counts[s.subgoalId] ?? (total: 0, unreviewed: 0);
      counts[s.subgoalId] = (
        total: c.total + 1,
        unreviewed: c.unreviewed + (s.reviewed ? 0 : 1),
      );
    }
    return _Overview(goals: goals, counts: counts);
  }

  void _reload() {
    setState(() {
      _overview = _loadOverview();
      final id = _selectedSubgoalId;
      if (id != null) _loadQuestions(id);
    });
  }

  void _select(String subgoalId) {
    setState(() {
      _selectedSubgoalId = subgoalId;
      _loadQuestions(subgoalId);
    });
  }

  void _loadQuestions(String subgoalId) {
    _items = null;
    final future = _bank.listForSubgoal(subgoalId);
    _questions = future;
    future.then((items) {
      if (!mounted || _questions != future) return;
      setState(() => _items = items);
    }, onError: (_) {});
  }

  Future<void> _act(
    BankQuestion question,
    Future<BankQuestion> Function() action,
  ) async {
    setState(() => _busy.add(question.id));
    try {
      final updated = await action();
      if (!mounted) return;
      setState(() {
        _items = [
          for (final q in _items ?? const <BankQuestion>[])
            q.id == updated.id ? updated : q,
        ];
        // The tree's "new" count follows without a round trip.
        _overview = _overview.then(
          (o) => _Overview(
            goals: o.goals,
            counts: _recount(o.counts, question, updated),
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).questions_actionFailed('$e'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(question.id));
    }
  }

  static Map<String, _SubgoalCounts> _recount(
    Map<String, _SubgoalCounts> counts,
    BankQuestion before,
    BankQuestion after,
  ) {
    if (before.isReviewed == after.isReviewed) return counts;
    final c = counts[before.subgoalId];
    if (c == null) return counts;
    return {
      ...counts,
      before.subgoalId: (
        total: c.total,
        unreviewed: c.unreviewed + (after.isReviewed ? -1 : 1),
      ),
    };
  }

  Future<void> _editNote(BankQuestion question) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _NoteDialog(initial: question.teacherNote ?? ''),
    );
    if (note == null || !mounted) return;
    await _act(question, () => _bank.setNote(question, note));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      key: const Key('questions-page'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxxl,
        AppSpacing.xxl,
        AppSpacing.xxxl,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.questions_page_title,
                      style: TextStyle(
                        color: AppColors.fg,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l.questions_page_subtitle,
                      style: TextStyle(
                        color: AppColors.fgFaint,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('questions-refresh'),
                tooltip: l.questions_refresh_tooltip,
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: FutureBuilder<_Overview>(
              future: _overview,
              builder: (context, snap) {
                if (snap.hasError) {
                  return _LoadFailure(error: snap.error!, onRetry: _reload);
                }
                final overview = snap.data;
                if (overview == null) {
                  return const Align(
                    alignment: Alignment.topCenter,
                    child: LinearProgressIndicator(minHeight: 2),
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 300, child: _buildTree(l, overview)),
                    const VerticalDivider(width: 24),
                    Expanded(child: _buildQuestions(l, overview)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTree(AppLocalizations l, _Overview overview) {
    if (overview.counts.isEmpty) {
      return Text(
        l.questions_tree_empty,
        key: const Key('questions-tree-empty'),
        style: TextStyle(color: AppColors.fgFaint, height: 1.4),
      );
    }
    final roots = overview.goals.where((g) => g.parentId == null).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final childrenOf = <String, List<Goal>>{};
    for (final g in overview.goals.where((g) => g.parentId != null)) {
      childrenOf.putIfAbsent(g.parentId!, () => []).add(g);
    }
    for (final list in childrenOf.values) {
      list.sort((a, b) => a.order.compareTo(b.order));
    }
    final known = {for (final g in overview.goals) g.id};
    final orphans =
        overview.counts.keys.where((id) => !known.contains(id)).toList()
          ..sort();

    return ListView(
      key: const Key('questions-tree'),
      children: [
        for (final root in roots) ...[
          _GroupHeader(title: root.title),
          for (final sub in childrenOf[root.id] ?? const <Goal>[])
            _subgoalTile(l, sub.id, sub.title, overview.counts[sub.id]),
        ],
        if (orphans.isNotEmpty) ...[
          _GroupHeader(title: l.questions_tree_otherGroup),
          for (final id in orphans)
            _subgoalTile(
              l,
              id,
              l.questions_tree_unknownSubgoal(id),
              overview.counts[id],
            ),
        ],
      ],
    );
  }

  Widget _subgoalTile(
    AppLocalizations l,
    String id,
    String title,
    _SubgoalCounts? counts,
  ) {
    final total = counts?.total ?? 0;
    final unreviewed = counts?.unreviewed ?? 0;
    return ListTile(
      key: Key('questions-subgoal-$id'),
      dense: true,
      selected: id == _selectedSubgoalId,
      enabled: total > 0,
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          l.questions_tree_count(total),
          if (unreviewed > 0) l.questions_tree_unreviewed(unreviewed),
        ].join(' · '),
        key: Key('questions-subgoal-count-$id'),
      ),
      onTap: () => _select(id),
    );
  }

  Widget _buildQuestions(AppLocalizations l, _Overview overview) {
    final subgoalId = _selectedSubgoalId;
    if (subgoalId == null) {
      return Center(
        child: Text(
          l.questions_placeholder,
          style: TextStyle(color: AppColors.fgFaint),
        ),
      );
    }
    return FutureBuilder<List<BankQuestion>>(
      future: _questions,
      builder: (context, snap) {
        if (snap.hasError) {
          return _LoadFailure(error: snap.error!, onRetry: _reload);
        }
        final items = _items;
        if (items == null) {
          return const Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(minHeight: 2),
          );
        }
        final shown = sortQuestions(
          _unreviewedOnly ? items.where((q) => !q.isReviewed) : items,
          _sort,
        );
        final goalsById = {for (final g in overview.goals) g.id: g};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildControls(l),
            const SizedBox(height: AppSpacing.m),
            Expanded(
              child: shown.isEmpty
                  ? Text(
                      items.isEmpty
                          ? l.questions_list_empty
                          : l.questions_list_allReviewed,
                      key: const Key('questions-list-empty'),
                      style: TextStyle(color: AppColors.fgFaint),
                    )
                  : ListView.separated(
                      key: const Key('questions-list'),
                      itemCount: shown.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.m),
                      itemBuilder: (context, i) {
                        final q = shown[i];
                        return _QuestionCard(
                          key: Key('questions-card-${q.id}'),
                          question: q,
                          subgoal: goalsById[q.subgoalId],
                          busy: _busy.contains(q.id),
                          onMarkReviewed: () =>
                              _act(q, () => _bank.markReviewed(q)),
                          onToggleHidden: () =>
                              _act(q, () => _bank.setHidden(q, q.isActive)),
                          onNote: () => _editNote(q),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildControls(AppLocalizations l) {
    String label(QuestionSort s) => switch (s) {
      QuestionSort.newest => l.questions_sort_newest,
      QuestionSort.shareAsc => l.questions_sort_shareAsc,
      QuestionSort.shareDesc => l.questions_sort_shareDesc,
      QuestionSort.mostAsked => l.questions_sort_mostAsked,
    };
    return Wrap(
      spacing: AppSpacing.s,
      runSpacing: AppSpacing.s,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilterChip(
          key: const Key('questions-filter-unreviewed'),
          label: Text(l.questions_filter_unreviewed),
          selected: _unreviewedOnly,
          onSelected: (v) => setState(() => _unreviewedOnly = v),
        ),
        const SizedBox(width: AppSpacing.m),
        for (final s in QuestionSort.values)
          ChoiceChip(
            key: Key('questions-sort-${s.name}'),
            label: Text(label(s)),
            selected: _sort == s,
            onSelected: (_) => setState(() => _sort = s),
          ),
      ],
    );
  }
}

/// The note editor. Its own state, so the text controller lives exactly as
/// long as the dialog — disposing it when `showDialog` returns would pull it
/// out from under the closing animation.
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.initial});
  final String initial;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.questions_note_dialog_title),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const Key('questions-note-field'),
          controller: _controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(hintText: l.questions_note_dialog_hint),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('questions-note-cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(l.questions_note_dialog_cancel),
        ),
        FilledButton(
          key: const Key('questions-note-save'),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(l.questions_note_dialog_save),
        ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.m,
        AppSpacing.lg,
        AppSpacing.xxs,
      ),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: AppColors.fgFaint,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// What the page shows when the bank cannot be read: a missing container
/// is a deployment step still to do, anything else an error to retry.
class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final missing =
        error is CosmosException &&
        (error as CosmosException).isContainerNotFound;
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Container(
          key: missing
              ? const Key('questions-container-missing')
              : const Key('questions-load-error'),
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.accent2.withValues(alpha: 0.10),
            border: Border.all(color: AppColors.accent2.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(AppRadius.cardLarge),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                missing
                    ? l.questions_containerMissing_title
                    : l.questions_loadError('$error'),
                style: TextStyle(
                  color: AppColors.fg,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              if (missing) ...[
                const SizedBox(height: AppSpacing.s),
                Text(
                  l.questions_containerMissing_body,
                  style: TextStyle(color: AppColors.fgMute, height: 1.5),
                ),
              ],
              const SizedBox(height: AppSpacing.m),
              OutlinedButton(
                key: const Key('questions-retry'),
                onPressed: onRetry,
                child: Text(l.questions_retry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String questionTypeLabel(
  AppLocalizations l,
  ChatRequestType type,
) => switch (type) {
  ChatRequestType.mcQuestion => l.questions_type_mcQuestion,
  ChatRequestType.completeCodeQuestion => l.questions_type_completeCodeQuestion,
  ChatRequestType.explainCodeQuestion => l.questions_type_explainCodeQuestion,
  ChatRequestType.writeCodeQuestion => l.questions_type_writeCodeQuestion,
  ChatRequestType.socraticQuestion => l.questions_type_socraticQuestion,
  _ => type.name,
};

String _difficultyLabel(AppLocalizations l, QuestionDifficulty d) =>
    switch (d) {
      QuestionDifficulty.easy => l.difficulty_easy,
      QuestionDifficulty.medium => l.difficulty_medium,
      QuestionDifficulty.hard => l.difficulty_hard,
    };

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    super.key,
    required this.question,
    required this.subgoal,
    required this.busy,
    required this.onMarkReviewed,
    required this.onToggleHidden,
    required this.onNote,
  });

  final BankQuestion question;

  /// The subgoal it was asked on, for the target LO's statement; `null`
  /// when that subgoal is gone.
  final Goal? subgoal;
  final bool busy;
  final VoidCallback onMarkReviewed;
  final VoidCallback onToggleHidden;
  final VoidCallback onNote;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final q = question;
    final share = q.shareCorrect;
    final meta = TextStyle(color: AppColors.fgMute, fontSize: 12.5);
    final statements = {
      for (final lo in subgoal?.objectives ?? const []) lo.id: lo.statement,
    };
    final targets = q.targetLOIds.join(', ');
    final note = q.teacherNote;

    return Opacity(
      opacity: q.isActive ? 1 : 0.6,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.ink1,
          border: Border.all(color: AppColors.ink2),
          borderRadius: BorderRadius.circular(AppRadius.cardLarge),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: AppSpacing.m,
                    runSpacing: AppSpacing.xxs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Pill(
                        text: questionTypeLabel(l, q.questionType),
                        color: AppColors.accent3,
                      ),
                      Text(_difficultyLabel(l, q.difficulty), style: meta),
                      if (targets.isNotEmpty)
                        Tooltip(
                          message: q.targetLOIds
                              .map((id) => statements[id] ?? id)
                              .join('\n'),
                          child: Text(
                            l.questions_targets(targets),
                            style: meta,
                          ),
                        ),
                      Text(l.questions_asked(q.askedCount), style: meta),
                      Text(
                        share == null
                            ? l.questions_notAnswered
                            : l.questions_shareCorrect(
                                (share * 100).round(),
                                q.correctCount,
                                q.answeredCount,
                              ),
                        key: Key('questions-share-${q.id}'),
                        style: meta,
                      ),
                    ],
                  ),
                ),
                if (!q.isActive)
                  _Pill(
                    key: Key('questions-hidden-${q.id}'),
                    text: l.questions_badge_hidden,
                    color: AppColors.danger,
                  )
                else if (q.isReviewed)
                  _Pill(
                    key: Key('questions-reviewed-${q.id}'),
                    text: l.questions_badge_reviewed,
                    color: AppColors.accent,
                  ),
              ],
            ),
            if (q.graderDisagreesWithKey ||
                (q.isMultipleChoice && q.correctOption == null)) ...[
              const SizedBox(height: AppSpacing.s),
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: AppColors.accent2,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      q.graderDisagreesWithKey
                          ? l.questions_keyDisagreement
                          : l.questions_noKey,
                      key: Key('questions-warning-${q.id}'),
                      style: TextStyle(
                        color: AppColors.accent2,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.m),
            QuestionPreview(question: q),
            if (note != null && note.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.m),
              Text(
                l.questions_note(note),
                key: Key('questions-note-text-${q.id}'),
                style: TextStyle(
                  color: AppColors.fgMute,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.m),
            Wrap(
              spacing: AppSpacing.s,
              children: [
                if (!q.isReviewed)
                  OutlinedButton.icon(
                    key: Key('questions-review-${q.id}'),
                    onPressed: busy ? null : onMarkReviewed,
                    icon: const Icon(Icons.check, size: 16),
                    label: Text(l.questions_action_markReviewed),
                  ),
                OutlinedButton.icon(
                  key: q.isActive
                      ? Key('questions-hide-${q.id}')
                      : Key('questions-unhide-${q.id}'),
                  onPressed: busy ? null : onToggleHidden,
                  icon: Icon(
                    q.isActive
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 16,
                  ),
                  label: Text(
                    q.isActive
                        ? l.questions_action_hide
                        : l.questions_action_unhide,
                  ),
                ),
                OutlinedButton.icon(
                  key: Key('questions-note-${q.id}'),
                  onPressed: busy ? null : onNote,
                  icon: const Icon(Icons.edit_note, size: 16),
                  label: Text(l.questions_action_note),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// A bank question the way the student gets it: the prompt, the code under
/// it and — multiple choice — the options with their letter. The answer key
/// is marked for the teacher, and under each option the feedback the grader
/// gave the first student who picked it. The options are in the order they
/// were generated; a student sees them shuffled.
class QuestionPreview extends StatelessWidget {
  const QuestionPreview({super.key, required this.question});

  final BankQuestion question;

  static const _badges = ['A', 'B', 'C', 'D', 'E', 'F'];

  @override
  Widget build(BuildContext context) {
    final q = question;
    final options = q.options;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TutorMarkdown(
          q.prompt,
          style: TextStyle(
            color: AppColors.fg,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
        if (q.code.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.m),
          Container(
            padding: const EdgeInsets.all(AppSpacing.m),
            decoration: BoxDecoration(
              color: AppColors.ink0,
              border: Border.all(color: AppColors.ink2),
              borderRadius: BorderRadius.circular(AppRadius.cardLarge),
            ),
            child: HighlightView(
              q.code,
              language: 'python',
              theme: tutorCodeTheme,
              textStyle: AppMono.code(size: 13),
            ),
          ),
        ],
        for (var i = 0; i < options.length; i++) ...[
          const SizedBox(height: AppSpacing.s),
          _PreviewOption(
            badge: i < _badges.length ? _badges[i] : '${i + 1}',
            label: options[i],
            isKey: options[i] == q.correctOption,
            feedback: q.feedbackFor(options[i])?.text,
          ),
        ],
      ],
    );
  }
}

class _PreviewOption extends StatelessWidget {
  const _PreviewOption({
    required this.badge,
    required this.label,
    required this.isKey,
    required this.feedback,
  });

  final String badge;
  final String label;
  final bool isKey;
  final String? feedback;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tint = isKey ? AppColors.accent : AppColors.ink2;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.s,
      ),
      decoration: BoxDecoration(
        color: isKey ? AppColors.accent.withValues(alpha: 0.10) : null,
        border: Border.all(color: isKey ? tint.withValues(alpha: 0.6) : tint),
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isKey ? AppColors.accent : AppColors.ink2,
              borderRadius: BorderRadius.circular(AppRadius.inputSmall),
            ),
            child: Text(
              badge,
              style: AppMono.code(
                color: isKey ? AppColors.ink0 : AppColors.fgMute,
                size: 12,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppMono.code(size: 13)),
                if (feedback != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxs),
                    child: Text(
                      feedback!,
                      style: TextStyle(
                        color: AppColors.fgFaint,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (isKey)
            Tooltip(
              message: l.questions_answerKey_tooltip,
              child: Icon(
                Icons.check_circle,
                size: 18,
                color: AppColors.accent,
              ),
            ),
        ],
      ),
    );
  }
}
