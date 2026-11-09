// The notice for a badge just earned (#220): a card with the confetti the
// goal splash plays, never over a control the student is working with
// (#283). In the session it lies over the chat's messages, under the chat's
// header; on the other pages in the top right corner, under the XP pill.
//
// It never lands in the middle of a question: the badges are counted after
// a graded answer, once its feedback is on screen. It is not modal — the
// next question can come in under it — and it waits while the level-up or
// the goal-reached celebration is up, then shows. Several badges at once,
// and the first look at a student's badges, are one summary, not a stack of
// notices.

import 'dart:async';

import 'package:ai_tutor_python/features/badges/badge_text.dart';
import 'package:ai_tutor_python/features/session/chat_panel_state.dart';
import 'package:ai_tutor_python/features/session/session_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/features/shell/top_bar.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/badges/badge_catalog.dart';
import 'package:ai_tutor_python/services/badges/badge_service.dart';
import 'package:ai_tutor_python/services/progression/level_up_controller.dart';
import 'package:ai_tutor_python/services/splash/splash_service.dart';
import 'package:ai_tutor_python/services/translation/localized_text.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/badges/badge_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';

/// How long a notice for one badge stays up.
const Duration kBadgeToastDuration = Duration(seconds: 8);

/// How long a summary stays up: it has more to read.
const Duration kBadgeSummaryToastDuration = Duration(seconds: 14);

/// The notice's width where there is room for it. Over a chat narrower than
/// this and its margins it takes what the chat has (#283).
const double kBadgeToastWidth = 360;

/// Between the notice and the edges of the chat it lies over.
const double kBadgeToastChatInset = AppSpacing.m;

/// Where the notice for a badge is put up (#283).
///
/// The top right corner, the only place it had, lay over the row above the
/// editor in a 700 px window — "Send to tutor" among it — and in a wide one
/// over the chat's own buttons. A student who handed the next answer in
/// right after the feedback clicked the notice instead, and with the mouse
/// resting there it stayed up.
enum BadgeToastPlace {
  /// Over the chat's messages, just under its header, never wider than the
  /// chat ([BadgeToastOverChat]). In the session, next to the exercise or
  /// the lesson, that is the one part that is only read: the newest
  /// message is at the bottom, by the composer, and the header's buttons
  /// stay clear.
  chat,

  /// The top right corner, under the top bar ([BadgeToastOverlay]): the
  /// pages outside the session, and the theory view with the chat folded —
  /// beside the strip, not over its button.
  corner,

  /// Not now. The playground has no chat, and its buttons are where the
  /// corner is: the notice waits, as it waits for a celebration, until the
  /// student is back with the tutor or on another page.
  waiting,
}

/// Where the notice goes on [section], with the chat panel drawn as
/// [chat] (only the session has one).
BadgeToastPlace badgeToastPlaceFor(Section section, ChatPanelLayout chat) {
  if (section != Section.session) return BadgeToastPlace.corner;
  return switch (chat) {
    ChatPanelLayout.full => BadgeToastPlace.chat,
    ChatPanelLayout.collapsed => BadgeToastPlace.corner,
    ChatPanelLayout.hidden => BadgeToastPlace.waiting,
  };
}

/// [badgeToastPlaceFor] the page and the chat panel on screen.
///
/// Read in a widget's build, as `SessionView` reads the panel's layout —
/// not in a provider. A provider that watched [chatPanelLayoutProvider]
/// could be the one to bring it up to date, inside its own build; the
/// chat's unread flag listens to the layout and drops as the full panel
/// comes back, and Riverpod does not let a provider change another while
/// it builds. Picking a subgoal back up on the learning path did just that.
BadgeToastPlace _placeOf(WidgetRef ref) {
  final section = ref.watch(sectionProvider);
  if (section != Section.session) return BadgeToastPlace.corner;
  return badgeToastPlaceFor(section, ref.watch(chatPanelLayoutProvider));
}

/// Put in the shell's stack, over the content. Shows the first notice
/// waiting in [badgeAnnouncementsProvider] when it goes in the corner.
class BadgeToastOverlay extends ConsumerWidget {
  const BadgeToastOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (_placeOf(ref) != BadgeToastPlace.corner) {
      return const SizedBox.shrink();
    }
    final toast = _currentToast(ref);
    if (toast == null) return const SizedBox.shrink();
    // In the session the corner is the theory view's, with the folded
    // chat's strip at the right edge.
    final strip = ref.watch(sectionProvider) == Section.session
        ? chatCollapsedWidth
        : 0.0;
    return Positioned(
      top: topBarHeight + AppSpacing.m,
      right: strip + AppSpacing.lg,
      child: toast,
    );
  }
}

/// Put in a stack over the chat's messages, under its header: shows the
/// first notice waiting in [badgeAnnouncementsProvider] when it goes over
/// the chat. In the top right corner of the messages, as wide as
/// [kBadgeToastWidth] or the chat allows.
class BadgeToastOverChat extends ConsumerWidget {
  const BadgeToastOverChat({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (_placeOf(ref) != BadgeToastPlace.chat) {
      return const SizedBox.shrink();
    }
    final toast = _currentToast(ref);
    if (toast == null) return const SizedBox.shrink();
    // The width of the chat less the margins; the [Align] leaves the rest
    // of the row to the messages under it, for the mouse too.
    return Positioned(
      top: kBadgeToastChatInset,
      left: kBadgeToastChatInset,
      right: kBadgeToastChatInset,
      child: Align(alignment: Alignment.topRight, child: toast),
    );
  }
}

/// The notice on screen, wherever it is put: the first one waiting, unless
/// a celebration goes first. When its place changes while it is up — the
/// student opens another page, or the playground — it starts over in the
/// new one, with its full time.
Widget? _currentToast(WidgetRef ref) {
  final queue = ref.watch(badgeAnnouncementsProvider);
  // One celebration at a time: the level-up and the goal splash first.
  final waiting =
      ref.watch(levelUpControllerProvider) != null ||
      ref.watch(splashStateProvider) != null;
  if (queue.isEmpty || waiting) return null;
  final current = queue.first;
  final announcer = ref.read(badgeAnnouncementsProvider.notifier);
  return BadgeToast(
    key: ObjectKey(current),
    announcement: current,
    onDismiss: announcer.dismissCurrent,
    onOpen: () {
      ref.read(sectionProvider.notifier).state = Section.trophies;
      announcer.dismissCurrent();
    },
  );
}

/// One notice: a badge, or a summary of several.
class BadgeToast extends StatefulWidget {
  const BadgeToast({
    super.key,
    required this.announcement,
    required this.onDismiss,
    required this.onOpen,
  });

  final BadgeAnnouncement announcement;
  final VoidCallback onDismiss;
  final VoidCallback onOpen;

  @override
  State<BadgeToast> createState() => _BadgeToastState();
}

class _BadgeToastState extends State<BadgeToast>
    with SingleTickerProviderStateMixin {
  Timer? _timer;

  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: AppDurations.levelUpPopup,
  )..forward();

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer(
      widget.announcement.isSummary
          ? kBadgeSummaryToastDuration
          : kBadgeToastDuration,
      widget.onDismiss,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final a = widget.announcement;
    return FadeTransition(
      opacity: _in,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, -0.15),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: _in, curve: AppCurves.levelUp)),
        child: MouseRegion(
          // Reading it with the mouse on it keeps it up.
          onEnter: (_) => _timer?.cancel(),
          onExit: (_) => _start(),
          child: Material(
            key: const ValueKey('badge-toast'),
            color: AppColors.ink1,
            elevation: 8,
            shadowColor: Colors.black.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(
              side: BorderSide(color: AppColors.accent2.withValues(alpha: 0.6)),
              borderRadius: BorderRadius.circular(AppRadius.modal),
            ),
            clipBehavior: Clip.antiAlias,
            // [kBadgeToastWidth], or what the place it is put in has.
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kBadgeToastWidth),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      // Played once, and faint enough to read through.
                      child: Opacity(
                        opacity: 0.7,
                        child: Lottie.asset(
                          'assets/images/Confetti.json',
                          fit: BoxFit.cover,
                          repeat: false,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.xs,
                      AppSpacing.xs,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xxs),
                          child: _Frames(announcement: a),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: _Words(announcement: a, onOpen: widget.onOpen),
                        ),
                        IconButton(
                          tooltip: l.badges_toast_close,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.close,
                            size: 16,
                            color: AppColors.fgFaint,
                          ),
                          onPressed: widget.onDismiss,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Frames extends StatelessWidget {
  const _Frames({required this.announcement});

  final BadgeAnnouncement announcement;

  @override
  Widget build(BuildContext context) {
    final badges = announcement.badges;
    if (!announcement.isSummary) {
      final only = badges.single;
      return BadgeFrame.of(only.badge, tier: only.tier, size: 56);
    }
    // Up to three, overlapping, the first in front.
    final shown = badges.take(3).toList();
    const size = 40.0;
    const step = 18.0;
    return SizedBox(
      width: size + step * (shown.length - 1),
      height: size + 8,
      child: Stack(
        children: [
          for (var i = shown.length - 1; i >= 0; i--)
            Positioned(
              left: step * i,
              top: i.isEven ? 0 : 8,
              child: BadgeFrame.of(
                shown[i].badge,
                tier: shown[i].tier,
                size: size,
              ),
            ),
        ],
      ),
    );
  }
}

class _Words extends ConsumerWidget {
  const _Words({required this.announcement, required this.onOpen});

  final BadgeAnnouncement announcement;

  /// Opens the trophy case.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final a = announcement;
    String? goalTitleOf(EarnedBadgeNotice n) {
      final goal = n.badge.goalId;
      return goal == null
          ? null
          : ref
                .watch(localizedGoalByIdOf(goal, title: n.goalTitle ?? ''))
                .title;
    }

    String nameOf(EarnedBadgeNotice n) =>
        badgeName(l, n.badge, goalTitle: goalTitleOf(n), tier: n.tier);

    final String title;
    final String body;
    if (a.isSummary) {
      title = a.first
          ? l.badges_toast_summary_first(a.badges.length)
          : l.badges_toast_summary(a.badges.length);
      body = a.badges.map(nameOf).join(', ');
    } else {
      final n = a.badges.single;
      title = nameOf(n);
      final description = badgeDescription(
        l,
        n.badge,
        goalTitle: goalTitleOf(n),
        tier: n.tier,
      );
      body = switch (n.badge.group) {
        // From the teacher (#221), and how often by now.
        BadgeGroup.teacher =>
          '${n.count > 1 ? l.badges_toast_fromTeacherCount(n.count) : l.badges_toast_fromTeacher} · $description',
        BadgeGroup.tiers when n.badge.maxTier > 1 =>
          '${l.badges_toast_tier(n.tier)} · $description',
        _ => description,
      };
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l.badges_toast_caption,
          style: TextStyle(
            color: AppColors.accent2,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          key: const ValueKey('badge-toast-title'),
          style: TextStyle(
            color: AppColors.fg,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          body,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.fgMute, fontSize: 12, height: 1.4),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: onOpen,
            child: Text(l.badges_toast_open),
          ),
        ),
      ],
    );
  }
}
