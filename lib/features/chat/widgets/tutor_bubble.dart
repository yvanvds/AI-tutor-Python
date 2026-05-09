import 'package:ai_tutor_python/features/chat/widgets/_chat_time.dart';
import 'package:ai_tutor_python/features/chat/widgets/role_chip.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/tutor_markdown.dart';
import 'package:flutter/material.dart';

/// Receiver bubble for tutor messages. Renders an optional [RoleChip]
/// above the bubble and a small timestamp below.
class TutorBubble extends StatelessWidget {
  const TutorBubble({
    super.key,
    required this.text,
    this.role,
    this.createdAt,
  });

  final String text;
  final TutorRole? role;
  final DateTime? createdAt;

  @override
  Widget build(BuildContext context) {
    final isPraise = role == TutorRole.goed;

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (role != null) ...[
              RoleChip(role: role!),
              const SizedBox(height: 6),
            ],
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: isPraise
                    ? AppColors.accent2.withValues(alpha: 0.12)
                    : AppColors.ink1,
                border: Border.all(
                  color: isPraise
                      ? AppColors.accent2.withValues(alpha: 0.5)
                      : AppColors.ink2,
                ),
                borderRadius: BorderRadius.circular(AppRadius.bubble),
              ),
              child: TutorMarkdown(text),
            ),
            if (createdAt != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xxs),
                child: Text(
                  formatChatTime(createdAt),
                  style: const TextStyle(
                    color: AppColors.fgFaint,
                    fontSize: 10.5,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
