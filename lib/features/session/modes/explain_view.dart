import 'dart:async';

import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/content/content.dart';
import 'package:ai_tutor_python/services/content/content_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/lesson_html_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Uitleg — read-and-understand layout. Reads the active subgoal from
/// `goalSelectionProvider`, loads the linked `content` doc, and renders its
/// HTML body in a WebView styled by the shared `assets/lesson/lesson.css`.
/// The header pill, progress counter, and footer buttons stay native.
///
/// The footer pages back and forth through the theory the student has
/// already seen (#115): the earlier non-optional sibling subgoals that carry
/// a `content` doc. Which page is shown is **view-local** state — paging
/// never touches `goalSelectionProvider`, so the tutor keeps working against
/// the same subgoal while the student re-reads an older explanation.
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

  @override
  void initState() {
    super.initState();
    _watchSiblings(ref.read(goalSelectionProvider).activeRootGoal?.id);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
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
      if (mounted) setState(() => _siblings = list);
    });
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

    return Container(
      color: AppColors.ink0,
      child: Column(
        children: [
          _ChromeHeader(child: viewing, root: root, siblings: _siblings),
          Expanded(
            child: viewing.contentId == null || viewing.contentId!.isEmpty
                ? const _MissingContent()
                : _ContentWebView(contentId: viewing.contentId!),
          ),
          _ChromeFooter(
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

class _ContentWebView extends ConsumerWidget {
  const _ContentWebView({required this.contentId});
  final String contentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Scope the watch to this content's body so 5s polls that don't change
    // the body don't rebuild the WebView host (which visibly flickers on
    // Windows even when the fragment string is unchanged).
    final body = ref.watch(
      contentServiceProvider.select((list) {
        for (final c in list) {
          if (c.id == contentId) return c.body;
        }
        return null;
      }),
    );

    if (body != null) {
      return LessonHtmlView(fragment: body);
    }
    return StreamBuilder<Content?>(
      stream: ref.read(contentServiceProvider.notifier).watchById(contentId),
      builder: (context, snap) {
        final c = snap.data;
        if (c == null) {
          return _Placeholder(
            message: AppLocalizations.of(context).session_explain_loading,
          );
        }
        return LessonHtmlView(fragment: c.body);
      },
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

class _ChromeHeader extends StatelessWidget {
  const _ChromeHeader({
    required this.child,
    required this.root,
    required this.siblings,
  });
  final Goal child;
  final Goal? root;
  final List<Goal> siblings;

  @override
  Widget build(BuildContext context) {
    final pill =
        (root?.title ??
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
              pill,
              style: TextStyle(
                color: AppColors.accent,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const Spacer(),
          if (showCounter)
            Text(
              '${idx + 1} / $total',
              style: AppMono.tnum(
                size: 12,
                weight: FontWeight.w500,
                color: AppColors.fgFaint,
              ),
            ),
        ],
      ),
    );
  }
}

class _ChromeFooter extends ConsumerWidget {
  const _ChromeFooter({
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxxl,
        AppSpacing.m,
        AppSpacing.xxxl,
        AppSpacing.xl,
      ),
      child: Row(
        children: [
          _GhostButton(
            label: l.session_explain_prev_button,
            icon: Icons.arrow_back,
            onTap: onPrevious,
          ),
          if (onNext != null) ...[
            const SizedBox(width: AppSpacing.xs),
            _GhostButton(
              label: l.session_explain_next_button,
              icon: Icons.arrow_forward,
              iconAfterLabel: true,
              onTap: onNext,
            ),
          ],
          const Spacer(),
          if (onNewestPage) ...[
            Text(
              // The number the shell actually awards for finishing a
              // subgoal, not a hard-coded one (#116).
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
            onTap: () =>
                ref.read(modeProvider.notifier).state = SessionMode.practice,
          ),
        ],
      ),
    );
  }
}

class _GhostButton extends StatefulWidget {
  const _GhostButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.iconAfterLabel = false,
  });
  final String label;
  final IconData icon;

  /// `null` renders the button dimmed and inert — there is nowhere to go.
  final VoidCallback? onTap;

  /// Puts the icon on the trailing side, for a "forward" affordance.
  final bool iconAfterLabel;

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
    return MouseRegion(
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: widget.iconAfterLabel
                ? [label, const SizedBox(width: 6), icon]
                : [icon, const SizedBox(width: 6), label],
          ),
        ),
      ),
    );
  }
}

class _AccentButton extends StatefulWidget {
  const _AccentButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_AccentButton> createState() => _AccentButtonState();
}

class _AccentButtonState extends State<_AccentButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
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
          child: Row(
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
              Icon(Icons.arrow_forward, size: 14, color: AppColors.ink0),
            ],
          ),
        ),
      ),
    );
  }
}
