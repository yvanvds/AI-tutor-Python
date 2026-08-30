import 'package:ai_tutor_python/features/chat/widgets/_chat_time.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';

/// Sender bubble for the student. Solid accent fill, ink-0 text.
class StudentBubble extends StatelessWidget {
  const StudentBubble({super.key, required this.text, this.createdAt});

  final String text;
  final DateTime? createdAt;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(AppRadius.bubble),
              ),
              child: SelectableText(
                text,
                style: TextStyle(
                  color: AppColors.ink0,
                  fontSize: 14,
                  height: 1.55,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (createdAt != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xxs),
                child: Text(
                  formatChatTime(createdAt),
                  style: TextStyle(
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
