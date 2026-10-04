// "Badge toekennen" (#221): the teacher gives a student one of a fixed list
// of badges, for what the app cannot see — a question reported as wrong (by
// the question ID of #216), a classmate helped, a good question in class.
// The same badge can be given more than once; the dialog shows how often it
// was so far.
//
// The badge goes on the student's account doc with the other badges
// (`AccountService.awardTeacherBadge`, `awardedBy: teacher`, `earnedAt`), and
// the student's app announces it on its next poll or start. Never XP, never
// a grade.

import 'package:ai_tutor_python/features/badges/badge_text.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/account/account.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/badges/badge_catalog.dart';
import 'package:ai_tutor_python/services/badges/earned_badges.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/badges/badge_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the dialog gave: the badge and its count now.
typedef AwardedBadge = ({BadgeDefinition badge, int count});

/// Opens the dialog for [account] and, once a badge is given, says so in a
/// snack bar.
Future<void> showAwardBadgeDialog(BuildContext context, Account account) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l = AppLocalizations.of(context);
  final awarded = await showDialog<AwardedBadge>(
    context: context,
    builder: (_) => AwardBadgeDialog(account: account),
  );
  if (awarded == null) return;
  // Several in a row: the last one says what was just given.
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        l.awardBadge_done(badgeName(l, awarded.badge), awarded.count),
      ),
    ),
  );
}

/// The teacher's hint at what [badge] is for.
String _hintOf(AppLocalizations l, BadgeDefinition badge) => switch (badge.id) {
  'teacher:faultFinder' => l.awardBadge_faultFinder_hint,
  'teacher:helpingHand' => l.awardBadge_helpingHand_hint,
  'teacher:goodQuestion' => l.awardBadge_goodQuestion_hint,
  _ => '',
};

class AwardBadgeDialog extends ConsumerStatefulWidget {
  const AwardBadgeDialog({super.key, required this.account});

  final Account account;

  @override
  ConsumerState<AwardBadgeDialog> createState() => _AwardBadgeDialogState();
}

class _AwardBadgeDialogState extends ConsumerState<AwardBadgeDialog> {
  String? _selected;
  bool _busy = false;
  bool _failed = false;

  /// The badges as stored now: the drawer's account is the one of when it
  /// was opened.
  EarnedBadges? _earned;

  @override
  void initState() {
    super.initState();
    _earned = widget.account.badges;
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final fresh = await ref
          .read(accountServiceProvider.notifier)
          .getAccount(widget.account.uid);
      if (!mounted || fresh == null) return;
      setState(() => _earned = fresh.badges);
    } catch (e) {
      debugPrint('AwardBadgeDialog: account not read again: $e');
    }
  }

  Future<void> _award() async {
    final id = _selected;
    final badge = id == null ? null : BadgeCatalog.byId(id);
    if (badge == null) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final count = await ref
          .read(accountServiceProvider.notifier)
          .awardTeacherBadge(uid: widget.account.uid, badgeId: badge.id);
      if (!mounted) return;
      if (count == null) {
        setState(() {
          _busy = false;
          _failed = true;
        });
        return;
      }
      Navigator.of(context).pop<AwardedBadge>((badge: badge, count: count));
    } catch (e) {
      debugPrint('AwardBadgeDialog: awarding failed: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final account = widget.account;
    final full = account.fullName.trim().isEmpty
        ? account.email
        : account.fullName.trim();
    final first = account.firstName.trim().isEmpty
        ? full
        : account.firstName.trim();
    return AlertDialog(
      key: const ValueKey('award-badge-dialog'),
      title: Text(l.awardBadge_title(full)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.awardBadge_intro(first), style: text.bodySmall),
              const SizedBox(height: AppSpacing.md),
              for (final badge in BadgeCatalog.teacher)
                _Choice(
                  badge: badge,
                  hint: _hintOf(l, badge),
                  count: _countOf(badge),
                  selected: _selected == badge.id,
                  onTap: _busy
                      ? null
                      : () => setState(() => _selected = badge.id),
                ),
              if (_failed) ...[
                const SizedBox(height: AppSpacing.s),
                Text(
                  l.awardBadge_failed,
                  style: TextStyle(color: AppColors.danger, fontSize: 12.5),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l.awardBadge_cancel),
        ),
        FilledButton(
          key: const ValueKey('award-badge-confirm'),
          onPressed: _selected == null || _busy ? null : _award,
          child: Text(l.awardBadge_confirm),
        ),
      ],
    );
  }

  int _countOf(BadgeDefinition badge) {
    final entry = _earned?.byId[badge.id];
    return entry == null ? 0 : entry.count;
  }
}

/// One badge to choose: its frame, name, what it is for and how often given.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.badge,
    required this.hint,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final BadgeDefinition badge;
  final String hint;
  final int count;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final name = badgeName(l, badge);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: selected ? AppColors.ink2 : Colors.transparent,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: selected ? AppColors.accent : AppColors.ink3),
          borderRadius: BorderRadius.circular(AppRadius.cardLarge),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('award-badge-${badge.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s),
            child: Row(
              children: [
                BadgeFrame.of(badge, tier: 1, size: 44, semanticLabel: name),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color: AppColors.fg,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hint,
                        style: TextStyle(
                          color: AppColors.fgMute,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l.awardBadge_count(count),
                        style: TextStyle(
                          color: AppColors.fgFaint,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  size: 20,
                  color: selected ? AppColors.accent : AppColors.fgFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
