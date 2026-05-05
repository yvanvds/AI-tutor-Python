import 'package:ai_tutor_python/features/chat/widgets/composer_chrome.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';

/// Composer state shown while a multiple-choice question is awaiting an answer.
/// Disabled — student must pick from the inline options above.
class ComposerMcqDisabled extends StatelessWidget {
  const ComposerMcqDisabled({super.key});

  @override
  Widget build(BuildContext context) {
    return ComposerChrome(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.touch_app_outlined,
            size: 16,
            color: AppColors.accent,
          ),
          const SizedBox(width: AppSpacing.s),
          Text(
            'Klik op een antwoord hierboven',
            style: TextStyle(
              color: AppColors.fgMute,
              fontSize: 12.5,
              fontStyle: FontStyle.italic,
              height: 1.4,
            ).copyWith(),
          ),
        ],
      ),
    );
  }
}
