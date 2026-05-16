import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';

/// Playground mode. Reuses [PracticeView] under a small header strip,
/// without the share-with-tutor link from RunControls.
class PlaygroundView extends StatelessWidget {
  const PlaygroundView({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.ink0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.s,
            ),
            decoration: const BoxDecoration(
              color: AppColors.ink1,
              border: Border(
                bottom: BorderSide(color: AppColors.ink2, width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.ink2,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    AppLocalizations.of(context).session_playground_pill,
                    style: const TextStyle(
                      color: AppColors.fgMute,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                Text(
                  AppLocalizations.of(context).session_playground_subtitle,
                  style: const TextStyle(
                    color: AppColors.fgMute,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const Expanded(child: PracticeView(showObjective: false)),
        ],
      ),
    );
  }
}
