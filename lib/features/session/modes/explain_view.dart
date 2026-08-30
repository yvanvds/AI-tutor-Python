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
class ExplainView extends ConsumerWidget {
  const ExplainView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(goalSelectionProvider);
    final child = selection.activeChildGoal;
    final root = selection.activeRootGoal;

    if (child == null) {
      return _PlaceholderScreen(
        message: AppLocalizations.of(
          context,
        ).session_explain_placeholder_noSubgoal,
      );
    }

    return Container(
      color: AppColors.ink0,
      child: Column(
        children: [
          _ChromeHeader(child: child, root: root),
          Expanded(
            child: child.contentId == null || child.contentId!.isEmpty
                ? const _MissingContent()
                : _ContentWebView(contentId: child.contentId!),
          ),
          _ChromeFooter(),
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
              style: const TextStyle(
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
          style: const TextStyle(color: AppColors.fgMute, fontSize: 13),
        ),
      ),
    );
  }
}

class _ChromeHeader extends ConsumerWidget {
  const _ChromeHeader({required this.child, required this.root});
  final Goal child;
  final Goal? root;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pill =
        (root?.title ??
                AppLocalizations.of(context).session_explain_defaultPillLabel)
            .toUpperCase();
    return StreamBuilder<List<Goal>>(
      stream: root == null
          ? const Stream.empty()
          : ref.read(goalsServiceProvider).streamChildren(root!.id),
      builder: (context, snap) {
        final siblings = snap.data ?? const <Goal>[];
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
                  style: const TextStyle(
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
      },
    );
  }
}

class _ChromeFooter extends ConsumerWidget {
  const _ChromeFooter();

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
            onTap: () {},
          ),
          const Spacer(),
          Text(
            l.session_explain_completeXp,
            style: const TextStyle(
              color: AppColors.fgFaint,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: AppSpacing.m),
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
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<_GhostButton> {
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
            horizontal: AppSpacing.m,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: _hovering ? AppColors.ink2 : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.inputLarge),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: AppColors.fgMute),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: const TextStyle(
                  color: AppColors.fgMute,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
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
                style: const TextStyle(
                  color: AppColors.ink0,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.arrow_forward, size: 14, color: AppColors.ink0),
            ],
          ),
        ),
      ),
    );
  }
}
