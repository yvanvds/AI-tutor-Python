// The badge proof sheet (#220): ten badges in every state, in both themes,
// at 32, 64 and 128 pixels, then the whole set, the notice and an example
// trophy case — for the teacher to judge shape and colour. It stays in the
// app after the review (the teacher's decision of 2026-10-04), under
// Options for a teacher or a developer build: tweaking the look is a change
// to `theme/badge_style.dart`, and this page shows the result.

import 'package:ai_tutor_python/features/badges/badge_text.dart';
import 'package:ai_tutor_python/features/badges/prijzenkast_page.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/badges/badge_catalog.dart';
import 'package:ai_tutor_python/services/badges/badge_facts.dart';
import 'package:ai_tutor_python/services/badges/badge_service.dart';
import 'package:ai_tutor_python/services/badges/earned_badges.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/badges/badge_frame.dart';
import 'package:ai_tutor_python/widgets/badges/badge_toast_overlay.dart';
import 'package:flutter/material.dart';

/// Opens the proof sheet over the shell.
Future<void> openBadgeProofSheet(BuildContext context) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (_) => const BadgeProofSheetPage()));

/// The sizes the sheet shows every state at.
const List<double> kProofSheetSizes = [32, 64, 128];

/// One sample of the sheet: a badge in one state.
typedef _Sample = ({BadgeDefinition badge, int tier, bool hidden});

/// The ten badges of the sheet, each in another state: not earned, the
/// three metals, dots past the third tier, a secret before and after it is
/// found, a "Kenner van …" and a single one.
List<_Sample> _samples() {
  BadgeDefinition byId(String id) => BadgeCatalog.byId(id)!;
  return [
    (badge: byId('effort'), tier: 0, hidden: false),
    (badge: byId('streak'), tier: 1, hidden: false),
    (badge: byId('gapFiller'), tier: 2, hidden: false),
    (badge: byId('elephantMemory'), tier: 3, hidden: false),
    (badge: byId('knowledge'), tier: 4, hidden: false),
    (badge: byId('effort'), tier: 6, hidden: false),
    (badge: byId('rubberDuck'), tier: 0, hidden: true),
    (badge: byId('bugHunter'), tier: 1, hidden: false),
    (badge: BadgeCatalog.expert(_demoRoot.id), tier: 1, hidden: false),
    (badge: byId('helloWorld'), tier: 1, hidden: false),
  ];
}

String _stateLabel(AppLocalizations l, _Sample s) {
  if (s.hidden) return l.badges_proof_state_secret;
  if (s.tier == 0) return l.badges_proof_state_locked;
  return switch (s.badge.group) {
    BadgeGroup.experts => l.badges_proof_state_expert,
    BadgeGroup.fun =>
      s.badge.secret ? l.badges_proof_state_found : l.badges_proof_state_fun,
    BadgeGroup.tiers => l.badges_proof_state_tier(s.tier, s.badge.maxTier),
  };
}

class BadgeProofSheetPage extends StatelessWidget {
  const BadgeProofSheetPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.ink0,
      appBar: AppBar(
        title: Text(l.badges_proof_title),
        backgroundColor: AppColors.ink1,
      ),
      body: ListView(
        key: const ValueKey('badge-proof-sheet'),
        padding: const EdgeInsets.all(AppSpacing.xxl),
        children: [
          Text(l.badges_proof_intro, style: text.bodyMedium),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.s,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      backgroundColor: AppColors.ink0,
                      appBar: AppBar(
                        title: Text(l.badges_proof_previewCase),
                        backgroundColor: AppColors.ink1,
                      ),
                      body: PrijzenkastView(board: demoBadgeBoard()),
                    ),
                  ),
                ),
                icon: const Icon(Icons.emoji_events_outlined, size: 18),
                label: Text(l.badges_proof_previewCase),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          for (final palette in const [AppPalette.dark, AppPalette.light]) ...[
            _PalettePanel(palette: palette),
            const SizedBox(height: AppSpacing.xl),
          ],
          Text(l.badges_proof_previewToast, style: text.titleMedium),
          const SizedBox(height: AppSpacing.m),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.lg,
            children: [
              for (final a in _demoAnnouncements())
                BadgeToast(announcement: a, onDismiss: () {}, onOpen: () {}),
            ],
          ),
        ],
      ),
    );
  }
}

/// The samples and the whole set on [palette]'s own canvas, whatever theme
/// the app is in.
class _PalettePanel extends StatelessWidget {
  const _PalettePanel({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = palette;
    final heading = TextStyle(
      color: p.fg,
      fontSize: 16,
      fontWeight: FontWeight.w600,
    );
    final label = TextStyle(color: p.fgMute, fontSize: 11.5, height: 1.3);
    final panel = p.isDark ? 'dark' : 'light';
    return Container(
      key: ValueKey('badge-proof-$panel'),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: p.ink0,
        border: Border.all(color: p.ink3),
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            p.isDark ? l.badges_proof_dark : l.badges_proof_light,
            style: heading,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(l.badges_proof_states, style: label),
          const SizedBox(height: AppSpacing.s),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.lg,
            children: [
              for (final s in _samples())
                SizedBox(
                  width: 150,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BadgeFrame.of(
                        s.badge,
                        tier: s.tier,
                        size: kProofSheetSizes[2],
                        hidden: s.hidden,
                        palette: p,
                      ),
                      const SizedBox(height: AppSpacing.s),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          BadgeFrame.of(
                            s.badge,
                            tier: s.tier,
                            size: kProofSheetSizes[1],
                            hidden: s.hidden,
                            palette: p,
                          ),
                          const SizedBox(width: AppSpacing.s),
                          BadgeFrame.of(
                            s.badge,
                            tier: s.tier,
                            size: kProofSheetSizes[0],
                            hidden: s.hidden,
                            palette: p,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(_stateLabel(l, s), style: label),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(l.badges_proof_set, style: label),
          const SizedBox(height: AppSpacing.s),
          Wrap(
            spacing: AppSpacing.m,
            runSpacing: AppSpacing.m,
            children: [
              for (final badge in BadgeCatalog.all(
                expertGoalIds: [_demoRoot.id],
              ))
                SizedBox(
                  width: 88,
                  child: Column(
                    children: [
                      BadgeFrame.of(
                        badge,
                        tier: badge.maxTier >= 3 ? 3 : badge.maxTier,
                        size: 64,
                        palette: p,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        badgeName(l, badge, goalTitle: _demoRoot.title),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: label.copyWith(fontSize: 10.5),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      BadgeFrame.of(
                        badge,
                        tier: badge.maxTier >= 3 ? 3 : badge.maxTier,
                        size: 32,
                        palette: p,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The hoofddoel the examples' "Kenner van …" badge is about.
final Goal _demoRoot = Goal(id: 'proof-sheet-root', title: 'Python', order: 0);

/// A made-up student a month into the year, for the example trophy case:
/// about the median of the September numbers, some single badges found.
BadgeBoard demoBadgeBoard() {
  const facts = BadgeFacts(
    oefeningen: 152,
    correctOefeningen: 104,
    homeOefeningen: 12,
    lessonWeeks: 5,
    hardCorrect: 76,
    bestStreak: 13,
    correctByType: {
      'mcQuestion': 40,
      'completeCodeQuestion': 36,
      'explainCodeQuestion': 7,
      'writeCodeQuestion': 1,
    },
    masteredLos: 40,
    milestones: 11,
    warmUpCorrect: 2,
    transferCredits: 42,
    wrongToRight: 13,
    hintHits: 3,
    persevered: 2,
    toughest: 8,
    experts: {'proof-sheet-root': (mastered: 12, total: 15)},
    earlyBird: 1,
    ownQuestions: 1,
  );
  final snapshot = BadgeSnapshot(facts: facts, roots: [_demoRoot]);
  final reached = {
    for (final b in BadgeCatalog.all(expertGoalIds: [_demoRoot.id]))
      if (b.tierFor(b.valueIn(facts)) > 0)
        b.id: EarnedBadge(tier: b.tierFor(b.valueIn(facts))),
  };
  return BadgeBoard.from(snapshot, EarnedBadges(reached));
}

List<BadgeAnnouncement> _demoAnnouncements() {
  EarnedBadgeNotice notice(String id, int tier) =>
      EarnedBadgeNotice(badge: BadgeCatalog.byId(id)!, tier: tier);
  return [
    BadgeAnnouncement(badges: [notice('effort', 2)]),
    BadgeAnnouncement(
      badges: [
        notice('effort', 2),
        notice('streak', 1),
        notice('knowledge', 2),
        notice('helloWorld', 1),
      ],
      first: true,
    ),
  ];
}
