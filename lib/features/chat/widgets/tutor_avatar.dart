import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';

/// Gradient circle with a sparkle glyph — the tutor's visual identity.
class TutorAvatar extends StatelessWidget {
  const TutorAvatar({super.key, this.size = 32, this.showOnlineDot = false});

  final double size;
  final bool showOnlineDot;

  @override
  Widget build(BuildContext context) {
    final dot = size * 0.28;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.accent, AppColors.accent2],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.auto_awesome_outlined,
              color: AppColors.ink0,
              size: size * 0.5,
            ),
          ),
          if (showOnlineDot)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  color: AppColors.accent2,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.ink1, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
