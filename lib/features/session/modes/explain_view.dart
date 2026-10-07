import 'dart:async';

import 'package:ai_tutor_python/features/session/viewed_content_state.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/content/content.dart';
import 'package:ai_tutor_python/services/content/content_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/translation/localized_text.dart';
import 'package:ai_tutor_python/services/translation/translations_provider.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/first_that_fits.dart';
import 'package:ai_tutor_python/widgets/lesson_html_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Uitleg — read-and-understand layout. Reads the active subgoal from
/// `goalSelectionProvider`, loads the linked `content` doc, and renders its
/// HTML body in a WebView styled by the shared `assets/lesson/lesson.css` —
/// in the app language when the lesson has a translation into it, else in
/// Dutch under a notice (#207). The header pill, progress counter, and
/// footer buttons stay native.
///
/// The footer pages back and forth through the theory the student has
/// already seen (#115): the earlier non-optional sibling subgoals that carry
/// a `content` doc. Which page is shown is **view-local** state — paging
/// never touches `goalSelectionProvider`, so the tutor keeps working against
/// the same subgoal while the student re-reads an older explanation.
///
/// What the view shows is published to `viewedContentIdProvider` (#132), so
/// a question typed in the chat can be about the page on screen — the one
/// paged back to, not necessarily the active subgoal's.
class ExplainView extends ConsumerStatefulWidget {
  const ExplainView({super.key});

  @override
  ConsumerState<ExplainView> createState() => _ExplainViewState();
}

class _ExplainViewState extends ConsumerState<ExplainView> {
  /// Id of the already-seen page the student paged back to; `null` means the
  /// newest page, i.e. the active subgoal itself.
  String? _viewingId;

  /// Siblings of the active root, kept in a subscription rather than a
  /// `StreamBuilder` so paging (a `setState`) doesn't resubscribe the poll
  /// and blank the footer for a frame.
  List<Goal> _siblings = const [];
  String? _siblingsRootId;
  StreamSubscription<List<Goal>>? _sub;

  /// Where the page on screen is published (#132). Held from `initState`
  /// because `ref` is gone by the time `dispose` runs.
  late final ViewedContentNotifier _viewed;

  /// The id last handed to [_viewed], so a rebuild that shows the same page
  /// publishes nothing.
  String? _publishedContentId;
  bool _publishedOnce = false;

  @override
  void initState() {
    super.initState();
    _viewed = ref.read(viewedContentIdProvider.notifier);
    _watchSiblings(ref.read(goalSelectionProvider).activeRootGoal?.id);
  }

  @override
  void dispose() {
    _sub?.cancel();
    // Not during unmount: the tree is locked, and a provider write would
    // mark the scope dirty. The owner check in `hide` covers the arriving
    // view that may already have published by the time this runs.
    scheduleMicrotask(() => _viewed.hide(this));
    super.dispose();
  }

  /// Publishes the page this build draws, once it is on screen. `null` is
  /// a placeholder: no subgoal, or one without a lesson.
  void _publishViewed(String? contentId) {
    if (_publishedOnce && contentId == _publishedContentId) return;
    _publishedOnce = true;
    _publishedContentId = contentId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _viewed.show(this, contentId);
    });
  }

  void _watchSiblings(String? rootId) {
    if (rootId == _siblingsRootId) return;
    _siblingsRootId = rootId;
    _viewingId = null;
    _siblings = const [];
    _sub?.cancel();
    _sub = null;
    if (rootId == null) return;
    _sub = ref.read(goalsServiceProvider).streamChildren(rootId).listen((list) {
      // The poll emits every 5 s whether or not anything changed; only a
      // real change is worth a rebuild of the whole view (#128).
      if (mounted && !_sameSiblings(_siblings, list)) {
        setState(() => _siblings = list);
      }
    });
  }

  /// Whether two sibling lists agree on everything this view reads from
  /// them: the ids and their order (the header counter, [_seenPages]),
  /// `optional` and `contentId` (which pages count as seen theory). `Goal`
  /// has no value equality, so a fresh poll always hands back new
  /// instances; comparing the projection is what tells "same curriculum"
  /// from "the teacher changed something".
  static bool _sameSiblings(List<Goal> a, List<Goal> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].optional != b[i].optional ||
          a[i].contentId != b[i].contentId) {
        return false;
      }
    }
    return true;
  }

  /// The theory pages before [active] that the student has already seen:
  /// non-optional siblings carrying a `content` doc.
  List<Goal> _seenPages(Goal active) {
    final activeIdx = _siblings.indexWhere((g) => g.id == active.id);
    if (activeIdx <= 0) return const [];
    return [
      for (final g in _siblings.take(activeIdx))
        if (!g.optional && (g.contentId?.isNotEmpty ?? false)) g,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(goalSelectionProvider);
    ref.listen(goalSelectionProvider, (_, next) {
      _watchSiblings(next.activeRootGoal?.id);
    });
    final active = selection.activeChildGoal;
    final root = selection.activeRootGoal;

    if (active == null) {
      _publishViewed(null);
      return _PlaceholderScreen(
        message: AppLocalizations.of(context)
            .session_explain_placeholder_noSubgoal,
      );
    }

    final seen = _seenPages(active);
    // Where the student is: -1 is the newest page (the active subgoal). A
    // page that has since vanished from the curriculum falls back to it.
    final at = _viewingId == null
        ? -1
        : seen.indexWhere((g) => g.id == _viewingId);
    final viewing = at < 0 ? active : seen[at];

    // Previous: one page back, or the last seen page when on the newest one.
    final Goal? previous = at < 0
        ? (seen.isEmpty ? null : seen.last)
        : (at > 0 ? seen[at - 1] : null);
    // Next only exists once the student has paged back; from the last seen
    // page it returns to the newest one (`null` id).
    final bool hasNext = at >= 0;
    final String? nextId = at >= 0 && at + 1 < seen.length
        ? seen[at + 1].id
        : null;

    final hasPage = viewing.contentId != null && viewing.contentId!.isNotEmpty;
    _publishViewed(hasPage ? viewing.contentId : null);

    return Container(
      color: AppColors.ink0,
      child: Column(
        children: [
          _ChromeHeader(child: viewing, root: root, siblings: _siblings),
          Expanded(
            child: hasPage
                ? _ContentWebView(contentId: viewing.contentId!)
                : const _MissingContent(),
          ),
          _ChromeFooter(
            key: const Key('explain-footer'),
            onPrevious: previous == null
                ? null
                : () => setState(() => _viewingId = previous.id),
            onNext: !hasNext ? null : () => setState(() => _viewingId = nextId),
            // The XP caption is about work still ahead, so it belongs to the
            // newest page only: a page the student paged back to is theory
            // of a subgoal whose XP has already been earned (#116).
            onNewestPage: at < 0,
          ),
        ],
      ),
    );
  }
}

/// The lesson [contentId] in the app language (#207): its translation when
/// there is one, else the Dutch text under a notice that says so.
class _ContentWebView extends ConsumerWidget {
  const _ContentWebView({required this.contentId});
  final String contentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuilds only when the text shown changes — the Dutch lesson, its
    // translation, or the language — so 5 s polls that change none of them
    // don't rebuild the WebView host. This only stops rebuilds that
    // originate here; the "flicker on an unchanged fragment" it was added
    // for came from `LessonHtmlView` re-creating its `WebViewWidget` on
    // *any* rebuild, which is fixed at the source (#128).
    final shown = ref.watch(localizedContentProvider(contentId));
    if (shown != null) return _LessonPage(shown: shown);

    // Not in the content cache yet: fetched on its own.
    return StreamBuilder<Content?>(
      stream: ref.read(contentServiceProvider.notifier).watchById(contentId),
      builder: (context, snap) {
        final c = snap.data;
        if (c == null) {
          return _Placeholder(
            message: AppLocalizations.of(context).session_explain_loading,
          );
        }
        // Its own `Consumer`, so a new translation rebuilds the page and
        // not this widget, which would hand the builder a new stream.
        return Consumer(
          builder: (context, ref, _) => _LessonPage(
            shown: localizedContent(c, ref.watch(translationsProvider)),
          ),
        );
      },
    );
  }
}

/// A lesson in the WebView, with the notice above it when the app language
/// has no translation of it and it is shown in Dutch (#207).
class _LessonPage extends ConsumerWidget {
  const _LessonPage({required this.shown});
  final LocalizedContent shown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Before the app language's translations have come back every lesson
    // reads as Dutch; the notice waits until "no translation" is known.
    final missing =
        shown.isFallback &&
        ref.watch(translationsProvider.select((t) => t.loaded));
    return Column(
      children: [
        // Always in the tree, so the notice coming or going never moves the
        // WebView to another slot and re-mounts it.
        _TranslationMissingNotice(visible: missing),
        Expanded(
          child: LessonHtmlView(fragment: shown.body, language: shown.language),
        ),
      ],
    );
  }
}

class _TranslationMissingNotice extends StatelessWidget {
  const _TranslationMissingNotice({required this.visible});
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Padding(
      key: const Key('explain-translation-missing'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxxl,
        0,
        AppSpacing.xxxl,
        AppSpacing.s,
      ),
      child: Row(
        children: [
          Icon(Icons.translate, size: 14, color: AppColors.fgFaint),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              AppLocalizations.of(context).session_explain_translationMissing,
              style: TextStyle(
                color: AppColors.fgMute,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingContent extends StatelessWidget {
  const _MissingContent();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.ink1,
              border: Border.all(color: AppColors.ink2),
              borderRadius: BorderRadius.circular(AppRadius.cardLarge),
            ),
            child: Text(
              AppLocalizations.of(context).session_explain_missingContent,
              style: TextStyle(
                color: AppColors.fgMute,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.ink0,
      child: _Placeholder(message: message),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Text(
          message,
          style: TextStyle(color: AppColors.fgMute, fontSize: 13),
        ),
      ),
    );
  }
}

/// The pill with the root goal's title — in the app language when there is
/// a translation, else in Dutch (#210) — and the page counter.
class _ChromeHeader extends ConsumerWidget {
  const _ChromeHeader({
    required this.child,
    required this.root,
    required this.siblings,
  });
  final Goal child;
  final Goal? root;
  final List<Goal> siblings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final root = this.root;
    final rootTitle = root == null
        ? null
        : ref.watch(localizedGoalOf(root)).title;
    final pill =
        (rootTitle ??
                AppLocalizations.of(context).session_explain_defaultPillLabel)
            .toUpperCase();
    final idx = siblings.indexWhere((g) => g.id == child.id);
    final total = siblings.length;
    final showCounter = idx >= 0 && total > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxxl,
        AppSpacing.xl,
        AppSpacing.xxxl,
        AppSpacing.s,
      ),
      child: Row(
        children: [
          // A long goal title ends in an ellipsis next to the counter rather
          // than running past a narrow lesson column (#259).
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  pill,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
          ),
          if (showCounter) ...[
            const SizedBox(width: AppSpacing.m),
            Text(
              '${idx + 1} / $total',
              style: AppMono.tnum(
                size: 12,
                weight: FontWeight.w500,
                color: AppColors.fgFaint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChromeFooter extends ConsumerWidget {
  const _ChromeFooter({
    super.key,
    required this.onPrevious,
    required this.onNext,
    required this.onNewestPage,
  });

  /// `null` disables the button — the student is on the oldest theory page.
  final VoidCallback? onPrevious;

  /// `null` hides the button entirely — the student is on the newest page,
  /// where there is nothing to page forward to.
  final VoidCallback? onNext;

  /// Whether the theory on screen belongs to the subgoal the tutor is
  /// working on. Only then is there XP still to earn, so only then is the
  /// XP caption shown.
  final bool onNewestPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    void tryIt() =>
        ref.read(modeProvider.notifier).state = SessionMode.practice;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxxl,
        AppSpacing.m,
        AppSpacing.xxxl,
        AppSpacing.xl,
      ),
      // The richest form that fits the lesson column (#259): next to an
      // open chat in a narrow window, or while the chat slides shut after
      // the window was made narrow, the full row does not.
      child: LayoutBuilder(
        builder: (context, constraints) => FirstThatFits(
          children: [
            for (final density in _FooterDensity.values)
              ConstrainedBox(
                // At least the room there is, so the form on screen puts
                // its two groups at the two edges. A form that needs more
                // is one FirstThatFits passes over.
                constraints: BoxConstraints(
                  minWidth: constraints.hasBoundedWidth
                      ? constraints.maxWidth
                      : 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _GhostButton(
                          label: l.session_explain_prev_button,
                          icon: Icons.arrow_back,
                          withLabel: density.pagingLabels,
                          onTap: onPrevious,
                        ),
                        if (onNext != null) ...[
                          const SizedBox(width: AppSpacing.xs),
                          _GhostButton(
                            label: l.session_explain_next_button,
                            icon: Icons.arrow_forward,
                            iconAfterLabel: true,
                            withLabel: density.pagingLabels,
                            onTap: onNext,
                          ),
                        ],
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.m),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (onNewestPage && density.xpCaption) ...[
                            Text(
                              // The number the shell actually awards for
                              // finishing a subgoal, not a hard-coded one
                              // (#116).
                              l.session_explain_completeXp(kXpPerSubgoal),
                              style: TextStyle(
                                color: AppColors.fgFaint,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.m),
                          ],
                          _AccentButton(
                            label: l.session_explain_tryItYourself,
                            withLabel: density.tryItLabel,
                            onTap: tryIt,
                          ),
                        ],
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

/// How much of the footer is spelled out, from all of it to the least
/// (#259). First the XP caption goes, then the words on the paging buttons,
/// then the words on "Try it yourself"; a button without its words keeps
/// them in a tooltip.
enum _FooterDensity {
  full,
  noXpCaption,
  noPagingLabels,
  noLabels;

  bool get xpCaption => index < noXpCaption.index;
  bool get pagingLabels => index < noPagingLabels.index;
  bool get tryItLabel => index < noLabels.index;
}

class _GhostButton extends StatefulWidget {
  const _GhostButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.iconAfterLabel = false,
    this.withLabel = true,
  });
  final String label;
  final IconData icon;

  /// `null` renders the button dimmed and inert — there is nowhere to go.
  final VoidCallback? onTap;

  /// Puts the icon on the trailing side, for a "forward" affordance.
  final bool iconAfterLabel;

  /// Whether [label] is written next to the icon; without it, it is the
  /// icon's tooltip (#259).
  final bool withLabel;

  @override
  State<_GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<_GhostButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final fg = enabled
        ? AppColors.fgMute
        : AppColors.fgFaint.withValues(alpha: 0.5);
    final icon = Icon(widget.icon, size: 14, color: fg);
    final label = Text(
      widget.label,
      style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w500),
    );
    final button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) {
        if (enabled) setState(() => _hovering = true);
      },
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppDurations.hover,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.m,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: _hovering && enabled ? AppColors.ink2 : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.inputLarge),
          ),
          child: !widget.withLabel
              ? icon
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: widget.iconAfterLabel
                      ? [label, const SizedBox(width: 6), icon]
                      : [icon, const SizedBox(width: 6), label],
                ),
        ),
      ),
    );
    if (widget.withLabel) return button;
    return Tooltip(
      message: widget.label,
      waitDuration: const Duration(milliseconds: 400),
      child: button,
    );
  }
}

class _AccentButton extends StatefulWidget {
  const _AccentButton({
    required this.label,
    required this.onTap,
    this.withLabel = true,
  });
  final String label;
  final VoidCallback onTap;

  /// Whether [label] is written before the arrow; without it, it is the
  /// arrow's tooltip (#259).
  final bool withLabel;

  @override
  State<_AccentButton> createState() => _AccentButtonState();
}

class _AccentButtonState extends State<_AccentButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final arrow = Icon(Icons.arrow_forward, size: 14, color: AppColors.ink0);
    final button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppDurations.hover,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.s,
          ),
          decoration: BoxDecoration(
            color: _hovering
                ? Color.alphaBlend(
                    Colors.white.withValues(alpha: 0.06),
                    AppColors.accent,
                  )
                : AppColors.accent,
            borderRadius: BorderRadius.circular(AppRadius.inputLarge),
          ),
          child: !widget.withLabel
              ? arrow
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: AppColors.ink0,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    arrow,
                  ],
                ),
        ),
      ),
    );
    if (widget.withLabel) return button;
    return Tooltip(
      message: widget.label,
      waitDuration: const Duration(milliseconds: 400),
      child: button,
    );
  }
}
