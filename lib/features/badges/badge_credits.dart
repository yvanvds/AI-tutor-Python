// Who drew the badge icons (#220): game-icons.net, CC BY 3.0, which asks for
// the author of every icon. The list is read from the badge definitions, so
// an icon added there is credited here without a second list to keep.

import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/badges/badge_catalog.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The credits: every icon with its author, and the licence.
Future<void> showBadgeCredits(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => const BadgeCreditsDialog(),
);

class BadgeCreditsDialog extends StatelessWidget {
  const BadgeCreditsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final icons = BadgeCatalog.icons;
    return AlertDialog(
      title: Text(l.badges_credits_title),
      content: SizedBox(
        width: 520,
        height: 420,
        child: ListView(
          children: [
            Text(l.badges_credits_intro, style: text.bodyMedium),
            const SizedBox(height: AppSpacing.xs),
            SelectableText(
              '${BadgeIcon.licence}: ${BadgeIcon.licenceUrl}',
              style: text.bodySmall,
            ),
            const SizedBox(height: AppSpacing.m),
            for (final icon in icons)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: SvgPicture.asset(
                  icon.asset,
                  width: 24,
                  height: 24,
                  colorFilter: ColorFilter.mode(AppColors.fg, BlendMode.srcIn),
                ),
                title: Text(l.badges_credits_line(icon.title, icon.author)),
                subtitle: SelectableText(icon.sourceUrl),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.badges_credits_close),
        ),
      ],
    );
  }
}
