// The student's trophy case — "Prijzenkast" (#220): every badge, the earned
// ones in the colour of their tier with the progress to the next, the ones
// not earned yet in grey, and a secret not found yet as a "?".
//
// Badges give no XP and never touch a grade; the page says so at the top.

import 'package:ai_tutor_python/features/badges/badge_credits.dart';
import 'package:ai_tutor_python/features/badges/badge_text.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/badges/badge_service.dart';
import 'package:ai_tutor_python/services/translation/localized_text.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/badges/badge_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The signed-in student's trophy case.
class PrijzenkastPage extends ConsumerWidget {
  const PrijzenkastPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      PrijzenkastView(board: ref.watch(badgeBoardProvider));
}

/// A trophy case for [board] — the student's own, or the proof sheet's
/// example. `null` while the badges are being counted.
class PrijzenkastView extends StatelessWidget {
  const PrijzenkastView({super.key, required this.board});

  final BadgeBoard? board;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final board = this.board;
    return Container(
      color: AppColors.ink0,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxl,
              vertical: AppSpacing.xl,
            ),
            children: [
              Text(l.badges_page_title, style: text.headlineMedium),
              const SizedBox(height: AppSpacing.xxs),
              Text(l.badges_page_subtitle, style: text.bodySmall),
              const SizedBox(height: AppSpacing.lg),
              if (board == null)
                Row(
                  children: [
                    const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: AppSpacing.s),
                    Text(l.badges_page_loading, style: text.bodyMedium),
                  ],
                )
              else ...[
                Text(
                  l.badges_page_count(board.earnedCount, board.total),
                  key: const ValueKey('badges-count'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (!board.progressKnown) ...[
                  const SizedBox(height: AppSpacing.s),
                  Text(l.badges_page_noProgress, style: text.bodySmall),
                ],
                const SizedBox(height: AppSpacing.xl),
                _Section(
                  title: l.badges_section_tiers,
                  hint: l.badges_section_tiers_hint,
                  tiles: board.tiers,
                ),
                if (board.experts.isNotEmpty)
                  _Section(
                    title: l.badges_section_experts,
                    hint: l.badges_section_experts_hint,
                    tiles: board.experts,
                  ),
                _Section(
                  title: l.badges_section_fun,
                  hint: l.badges_section_fun_hint,
                  tiles: board.fun,
                ),
              ],
              const SizedBox(height: AppSpacing.m),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => showBadgeCredits(context),
                  icon: const Icon(Icons.info_outline, size: 16),
                  label: Text(l.badges_credits_button),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.hint,
    required this.tiles,
  });

  final String title;
  final String hint;
  final List<BadgeTile> tiles;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleMedium),
          const SizedBox(height: AppSpacing.xxs),
          Text(hint, style: text.bodySmall),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.m,
            runSpacing: AppSpacing.m,
            children: [for (final tile in tiles) BadgeTileCard(tile: tile)],
          ),
        ],
      ),
    );
  }
}

/// One badge in the trophy case.
class BadgeTileCard extends ConsumerWidget {
  const BadgeTileCard({super.key, required this.tile});

  final BadgeTile tile;

  static const double width = 312;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final badge = tile.badge;
    final goal = tile.goal;
    final goalTitle = goal == null
        ? null
        : ref.watch(localizedGoalOf(goal)).title;
    final hidden = tile.isHidden;
    final name = hidden
        ? l.badges_secret_name
        : badgeName(l, badge, goalTitle: goalTitle);
    final description = hidden
        ? l.badges_secret_description
        : badgeDescription(l, badge, goalTitle: goalTitle);

    final String status;
    if (!tile.isEarned) {
      status = l.badges_tile_locked;
    } else if (badge.maxTier > 1) {
      status = tile.tier >= badge.maxTier
          ? l.badges_tile_top
          : l.badges_tile_tier(tile.tier, badge.maxTier);
    } else {
      status = l.badges_tile_earned;
    }

    return Container(
      key: ValueKey('badge-tile-${badge.id}'),
      width: width,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.ink1,
        border: Border.all(color: AppColors.ink2),
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BadgeFrame.of(
            badge,
            tier: tile.tier,
            size: 64,
            hidden: hidden,
            semanticLabel: name,
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: tile.isEarned ? AppColors.fg : AppColors.fgMute,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  style: TextStyle(color: AppColors.fgFaint, fontSize: 11.5),
                ),
                if (!hidden) ..._progress(l),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  description,
                  style: TextStyle(
                    color: AppColors.fgMute,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The way to the next tier: "37/50" with a bar; a "Kenner van …" badge
  /// counts its LOs ("12/15"). Nothing for a single badge, or for a number
  /// not known.
  List<Widget> _progress(AppLocalizations l) {
    final badge = tile.badge;
    final expert = tile.expertProgress;
    if (expert != null) {
      return _bar(
        expert.total == 0 ? 0 : expert.mastered / expert.total,
        '${expert.mastered}/${expert.total}',
      );
    }
    if (badge.maxTier <= 1) return const [];
    final value = tile.value;
    if (value == null) {
      if (!tile.progressKnown) return const [];
      return [
        const SizedBox(height: AppSpacing.xs),
        Text(
          l.badges_tile_noLessons,
          style: TextStyle(color: AppColors.fgFaint, fontSize: 11.5),
        ),
      ];
    }
    final next = tile.next;
    if (next == null) return _bar(1, '$value');
    return _bar(value / next, '$value/$next');
  }

  List<Widget> _bar(double fraction, String label) => [
    const SizedBox(height: AppSpacing.xs),
    Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: AppColors.ink2,
              color: AppColors.accent2,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColors.fgMute,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  ];
}
