import 'dart:math' as math;

import 'package:ai_tutor_python/features/reference/reference_panel_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/code/python_reference.dart';
import 'package:ai_tutor_python/services/translation/localized_text.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/lesson_html_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The reference panel's place in the session view (#323): a box at the
/// [placement] the session view worked out, [right] pixels from its right
/// edge, that slides open and shut with the chat panel's duration and
/// curve. The panel inside is laid out at its full width the whole time, as
/// the chat is, so nothing in it reflows while it slides.
///
/// The panel stays mounted when closed — offstage, so it takes no clicks,
/// keys or finders — and keeps what was typed in its search field for the
/// next time it opens.
class ReferencePanelSlot extends StatefulWidget {
  const ReferencePanelSlot({
    super.key,
    required this.open,
    required this.placement,
    required this.right,
  });

  final bool open;
  final ReferencePlacement placement;
  final double right;

  @override
  State<ReferencePanelSlot> createState() => _ReferencePanelSlotState();
}

class _ReferencePanelSlotState extends State<ReferencePanelSlot> {
  /// On screen: open, or still sliding shut.
  late bool _shown = widget.open;

  @override
  void didUpdateWidget(covariant ReferencePanelSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open) _shown = true;
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.placement.width;
    return AnimatedPositioned(
      duration: AppDurations.chatSlide,
      curve: AppCurves.layout,
      top: 0,
      bottom: 0,
      right: widget.right,
      width: widget.open ? width : 0,
      onEnd: () {
        if (!widget.open && _shown) setState(() => _shown = false);
      },
      child: Offstage(
        offstage: !_shown,
        child: ClipRect(
          child: OverflowBox(
            minWidth: width,
            maxWidth: width,
            alignment: Alignment.centerLeft,
            child: ReferencePanel(open: widget.open),
          ),
        ),
      ),
    );
  }
}

/// Every function, method and class the course uses (#323), from the
/// bundled reference that also feeds the editor's dropdown after a dot
/// (#322): searchable by name — and by a word of the explanation, for a
/// student who no longer knows the name — and browsable by group, in the
/// app language. Each item shows how it is written, one or two sentences,
/// a short example and, when a lesson explains it, a link that opens that
/// lesson over the exercise.
///
/// Opening it puts the keyboard in the search field; Escape, or the cross,
/// closes it.
class ReferencePanel extends ConsumerStatefulWidget {
  const ReferencePanel({super.key, this.open = true});

  /// Whether the panel is open; the search field takes the keyboard when it
  /// becomes so.
  final bool open;

  @override
  ConsumerState<ReferencePanel> createState() => _ReferencePanelState();
}

class _ReferencePanelState extends ConsumerState<ReferencePanel> {
  final _query = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'reference search');

  /// The groups the student opened while browsing.
  final _expanded = <String>{};

  @override
  void initState() {
    super.initState();
    if (widget.open) _focusSearch();
  }

  @override
  void didUpdateWidget(covariant ReferencePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open && !oldWidget.open) _focusSearch();
    if (!widget.open && oldWidget.open) _searchFocus.unfocus();
  }

  @override
  void dispose() {
    _query.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// The search field, with what was typed last time selected: typing
  /// replaces it, an arrow key keeps it.
  void _focusSearch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocus.requestFocus();
      _query.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _query.text.length,
      );
    });
  }

  void _close() => ref.read(referencePanelOpenProvider.notifier).close();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final reference =
        ref.watch(pythonReferenceProvider).valueOrNull ?? PythonReference.empty;
    final query = _query.text.trim();

    return Actions(
      actions: {
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) {
            _close();
            return null;
          },
        ),
      },
      child: Container(
        key: const Key('reference-panel'),
        decoration: BoxDecoration(
          color: AppColors.ink1,
          border: Border(left: BorderSide(color: AppColors.ink2, width: 1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(title: l.reference_title, onClose: _close),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.m,
                0,
                AppSpacing.m,
                AppSpacing.s,
              ),
              child: _SearchField(
                controller: _query,
                focusNode: _searchFocus,
                onChanged: () => setState(() {}),
              ),
            ),
            Container(height: 1, color: AppColors.ink2),
            Expanded(
              child: query.isEmpty
                  ? _browse(reference, language)
                  : _results(reference, query, language, l),
            ),
          ],
        ),
      ),
    );
  }

  /// Every group, closed until the student opens it.
  Widget _browse(PythonReference reference, String language) {
    return ListView(
      key: const Key('reference-groups'),
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      children: [
        for (final group in reference.groups) ...[
          _GroupHeader(
            group: group,
            language: language,
            expanded: _expanded.contains(group.id),
            onTap: () => setState(() {
              if (!_expanded.remove(group.id)) _expanded.add(group.id);
            }),
          ),
          if (_expanded.contains(group.id)) ...[
            if (group.setup != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.m,
                  0,
                  AppSpacing.m,
                  AppSpacing.xs,
                ),
                child: _CodeBox(group.setup!),
              ),
            for (final item in group.items)
              _ItemCard(group: group, item: item, language: language),
          ],
        ],
      ],
    );
  }

  /// What a search finds, best first, each with its group.
  Widget _results(
    PythonReference reference,
    String query,
    String language,
    AppLocalizations l,
  ) {
    final hits = reference.search(query, language);
    if (hits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Text(
          l.reference_noResults(query),
          key: const Key('reference-no-results'),
          style: TextStyle(color: AppColors.fgMute, fontSize: 13),
        ),
      );
    }
    return ListView(
      key: const Key('reference-results'),
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      children: [
        for (final hit in hits)
          _ItemCard(
            group: hit.group,
            item: hit.item,
            language: language,
            showGroup: true,
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.m,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.s,
      ),
      child: Row(
        children: [
          Icon(Icons.menu_book_outlined, size: 16, color: AppColors.accent),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.fg,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            key: const Key('reference-close'),
            tooltip: AppLocalizations.of(context).reference_close_tooltip,
            onPressed: onClose,
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            color: AppColors.fgMute,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return TextField(
      key: const Key('reference-search'),
      controller: controller,
      focusNode: focusNode,
      onChanged: (_) => onChanged(),
      style: TextStyle(color: AppColors.fg, fontSize: 13),
      cursorColor: AppColors.accent,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppColors.ink0,
        hintText: l.reference_search_hint,
        hintStyle: TextStyle(color: AppColors.fgFaint, fontSize: 13),
        prefixIcon: Icon(Icons.search, size: 18, color: AppColors.fgMute),
        prefixIconConstraints: const BoxConstraints(minWidth: 34),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                key: const Key('reference-search-clear'),
                tooltip: l.reference_search_clear_tooltip,
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                color: AppColors.fgMute,
                onPressed: () {
                  controller.clear();
                  onChanged();
                  focusNode.requestFocus();
                },
                icon: const Icon(Icons.close),
              ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s,
          vertical: AppSpacing.s,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.inputSmall),
          borderSide: BorderSide(color: AppColors.ink2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.inputSmall),
          borderSide: BorderSide(color: AppColors.ink2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.inputSmall),
          borderSide: BorderSide(color: AppColors.accent),
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.language,
    required this.expanded,
    required this.onTap,
  });

  final ReferenceGroup group;
  final String language;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: ValueKey('reference-group-${group.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.expand_more : Icons.chevron_right,
              size: 18,
              color: AppColors.fgMute,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Expanded(
              child: Text(
                group.titleIn(language),
                style: TextStyle(
                  color: AppColors.fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s),
            Text(
              '${group.items.length}',
              style: AppMono.code(color: AppColors.fgFaint, size: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// One item: how it is written, what it does, an example, and the lesson
/// that explains it.
class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.group,
    required this.item,
    required this.language,
    this.showGroup = false,
  });

  final ReferenceGroup group;
  final ReferenceItem item;
  final String language;

  /// A search result names its group: `plt.` says less than "Charts".
  final bool showGroup;

  @override
  Widget build(BuildContext context) {
    final summary = item.summaryIn(language);
    final example = item.example;
    final lesson = item.lesson;
    return Container(
      key: ValueKey('reference-item-${group.id}.${item.name}'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.m,
        AppSpacing.sm,
        AppSpacing.m,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.ink2, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showGroup)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                group.titleIn(language),
                style: TextStyle(color: AppColors.fgFaint, fontSize: 11),
              ),
            ),
          Text(
            item.writtenIn(group),
            style: AppMono.code(color: AppColors.syntaxFn, size: 12.5),
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            _Summary(summary),
          ],
          if (example != null && example.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            _CodeBox(example),
          ],
          if (lesson != null) _LessonLink(contentId: lesson),
        ],
      ),
    );
  }
}

/// A summary, with its `code` spans in the code font.
class _Summary extends StatelessWidget {
  const _Summary(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final plain = TextStyle(
      color: AppColors.fgMute,
      fontSize: 12.5,
      height: 1.4,
    );
    final code = AppMono.code(
      color: AppColors.fg,
      size: 11.5,
    ).copyWith(height: 1.4);
    final parts = text.split('`');
    return Text.rich(
      TextSpan(
        style: plain,
        children: [
          for (var i = 0; i < parts.length; i++)
            if (parts[i].isNotEmpty)
              TextSpan(text: parts[i], style: i.isOdd ? code : null),
        ],
      ),
    );
  }
}

/// Code as the editor shows it; a line wider than the panel scrolls.
class _CodeBox extends StatelessWidget {
  const _CodeBox(this.code);

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.ink0,
        border: Border.all(color: AppColors.ink2),
        borderRadius: BorderRadius.circular(AppRadius.inputSmall),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s,
          vertical: AppSpacing.xs,
        ),
        child: Text(code, style: AppMono.code(color: AppColors.fg, size: 12)),
      ),
    );
  }
}

/// "Lesson: " and the title of the lesson [contentId] in the app language,
/// when that lesson is in the app (the content id is the subgoal's).
/// Nothing otherwise: no link is better than one that leads nowhere.
class _LessonLink extends ConsumerWidget {
  const _LessonLink({required this.contentId});

  final String contentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = ref.watch(localizedContentProvider(contentId));
    if (shown == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: InkWell(
        key: ValueKey('reference-lesson-link-$contentId'),
        borderRadius: BorderRadius.circular(AppRadius.inputSmall),
        onTap: () => showReferenceLesson(context, contentId),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.school_outlined, size: 14, color: AppColors.accent),
              const SizedBox(width: AppSpacing.xxs),
              Flexible(
                child: Text(
                  AppLocalizations.of(context)
                      .reference_lessonLink(shown.title),
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the lesson [contentId] in a window over the exercise (#323): the
/// student reads it and closes it, and is back where they were — the
/// session, its subgoal and the theory view's page do not change.
Future<void> showReferenceLesson(BuildContext context, String contentId) {
  return showDialog<void>(
    context: context,
    builder: (_) => ReferenceLessonDialog(contentId: contentId),
  );
}

/// A lesson in the app language, as the theory view shows it, in a window.
class ReferenceLessonDialog extends ConsumerWidget {
  const ReferenceLessonDialog({super.key, required this.contentId});

  final String contentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = ref.watch(localizedContentProvider(contentId));
    final size = MediaQuery.sizeOf(context);
    const inset = AppSpacing.xxl;
    return Dialog(
      key: const Key('reference-lesson'),
      backgroundColor: AppColors.ink0,
      insetPadding: const EdgeInsets.all(inset),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.modal),
        side: BorderSide(color: AppColors.ink2),
      ),
      child: SizedBox(
        width: math.min(880, math.max(0, size.width - 2 * inset)),
        height: math.max(0, size.height - 2 * inset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: AppColors.ink1,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.s,
                AppSpacing.xs,
                AppSpacing.s,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.school_outlined,
                    size: 16,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: Text(
                      shown?.title ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.fg,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('reference-lesson-close'),
                    tooltip: AppLocalizations.of(context)
                        .reference_lesson_close_tooltip,
                    onPressed: () => Navigator.of(context).pop(),
                    iconSize: 18,
                    color: AppColors.fgMute,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: shown == null
                  ? const SizedBox.shrink()
                  : LessonHtmlView(
                      fragment: shown.body,
                      language: shown.language,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
